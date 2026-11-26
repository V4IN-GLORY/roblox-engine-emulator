//! Method argument checks: every reflected engine method checks its arguments as a client's reflection casts them, before its
//! behaviour runs, from the method's reflected parameters. The rules are docs/engine.md "Argument casts", measured in a Roblox
//! Studio 0.748.0.7481526 playtest (validator/probe/expected: every method called with no arguments and with a wrong-typed first
//! one) and in the Camera's casts (world/tests.rs `camera_casts_name_values_as_a_client_does`).
//!
//! A method's [`ArgPlan`] is built once, when its function is made (lua/instance.rs), and interned for the process: the
//! function's C closure (lua/cfunction.rs) or its raw namecall member (lua/raw.rs) holds a pointer to it, so a call allocates
//! nothing unless it raises.

use std::{
    ffi::c_int,
    rc::Rc,
    sync::{Mutex, OnceLock},
};

use mlua::{ffi, prelude::*};
use rustc_hash::FxHashSet;

use super::{convert, raw};
use crate::{
    ClassId, Engine, NameId,
    reflection::{EnumId, MemberOrigin, ParameterInfo, Reflection},
};

/// What a parameter takes besides nil.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
enum Expect {
    /// Any value (a string or bool parameter casts whatever it gets: a table passed as a string runs)
    Any,
    /// A number, a bool (true is 1) or a string that reads as a number
    Number,
    /// What a number takes, or a userdata (a User)
    User,
    /// An item of this enum, a number, a bool, or the name of one of its items (another enum's item is refused)
    Enum(EnumId),
    Instance,
    /// An instance list: a client's words for a wrong one differ by method ("Unable to cast value to Objects", "Expected table
    /// argument, got string"), so a Rust behaviour's is its own
    Instances,
    Table,
    Function,
    /// A string or a Content (ContentId, Content)
    Text,
    /// A buffer: anything else is as if missing
    Buffer,
    /// A datatype (Vector3, CFrame, ...): a userdata whose `__type` is the parameter's script type, a vector for a Vector3; a
    /// table, or a userdata naming no type, is the behaviour's (some of ree's datatypes are tables)
    Datatype,
}

#[derive(Debug, PartialEq, Eq, Hash)]
struct Param {
    expect: Expect,
    nil_ok: bool,
    /// Whether ree's 0.747 dump is trusted to mark this kind of parameter optional (it never lost an enum's, a bool's, a User's or
    /// most datatypes' default against Roblox's 0.748 dump, but lost 95 of number, string, Instance, table, function and CFrame
    /// parameters): a Rust behaviour's plan raises a missing one only then
    nil_mark_trusted: bool,
    /// The type a refusal names ("Unable to cast string to <target>")
    target: Box<str>,
    /// A datatype's name as `typeof` gives it (`CFrame` for a CoordinateFrame), empty when the dump gives none
    script_type: Box<str>,
}

/// A method's parameters as its calls check them.
#[derive(Debug, PartialEq, Eq, Hash)]
pub struct ArgPlan {
    /// The class that declares the method: a call whose self is another class's instance raises the method's self error first
    declaring: ClassId,
    params: Box<[Param]>,
    /// Whether a nil raises "Argument N missing or nil" here; a Rust behaviour's plan leaves a nil, and every check before it,
    /// to the behaviour
    checks_missing: bool,
    /// The unemulated method this is the stand-in's plan of, as Output names it (class, member): a call it refuses is still a
    /// call of a member ree does not emulate, so the refusal records it first
    stand_in: Option<(Box<str>, Box<str>)>,
}

/// The plan of method `name` of `class` in the engine's Luau or without a behaviour (the unemulated stand-in), `None` when its
/// calls check nothing here: a method ree records no parameters for (MemberOrigin::Engine), one a game script may not call (its
/// capability error comes first: reflection.rs CAPABILITY_CALLS), an Instance method raw.rs runs inline, one whose behaviour
/// checks its own arguments (Behaviors::checks_own_arguments), and one whose every parameter takes anything.
pub fn plan(engine: &Engine, class: ClassId, name: NameId) -> Option<&'static ArgPlan> {
    build(engine, class, name, true, false)
}

/// [`plan`] for the stand-in of a method no behaviour implements (lua/instance.rs `unimplemented_function`).
pub fn stand_in_plan(engine: &Engine, class: ClassId, name: NameId) -> Option<&'static ArgPlan> {
    build(engine, class, name, true, true)
}

/// [`plan`] for a Rust behaviour: the casts of the values given, from the last back to a nil of a kind whose optional mark ree's
/// dump may have lost (Param::nil_mark_trusted), which the behaviour takes or refuses itself (`Shapecast`'s `cframeOverride`, a
/// `CFrame?` in 0.748's dump), or to an instance list, whose words are its own.
pub fn cast_plan(engine: &Engine, class: ClassId, name: NameId) -> Option<&'static ArgPlan> {
    build(engine, class, name, false, false)
}

fn build(engine: &Engine, class: ClassId, name: NameId, checks_missing: bool, stand_in: bool) -> Option<&'static ArgPlan> {
    if raw::is_inline_method(name) || engine.behaviors.borrow().has_own_argument_checks(class, name) {
        return None;
    }
    let reflection = &engine.reflection;
    let method = reflection.class_method(class, name)?;
    if method.origin != MemberOrigin::Dump || method.parameters.is_empty() || !method.permits.allows("Call") {
        return None;
    }
    let params: Box<[Param]> = method.parameters.iter().enumerate().map(|(position, info)| param(reflection, position, info)).collect();
    if params.iter().all(|param| param.expect == Expect::Any && (param.nil_ok || !(checks_missing || param.nil_mark_trusted))) {
        return None;
    }
    let stand_in = stand_in.then(|| (Box::from(&*reflection.class(class).name), Box::from(reflection.name(name))));
    Some(intern(ArgPlan { declaring: reflection.declaring_class(class, name), params, checks_missing, stand_in }))
}

fn param(reflection: &Reflection, position: usize, info: &ParameterInfo) -> Param {
    let engine_type = &*info.type_info.engine;
    let enum_type = info.type_info.enum_name.as_deref().and_then(|enum_name| Some((reflection.enum_id(enum_name)?, enum_name)));
    let (expect, target) = match engine_type {
        "int" | "int64" | "float" | "double" => (Expect::Number, engine_type),
        "User" => (Expect::User, engine_type),
        "Enum" => match enum_type {
            Some((enum_type, enum_name)) => (Expect::Enum(enum_type), enum_name),
            None => (Expect::Any, ""),
        },
        "Instance" | "Object" => (Expect::Instance, "Object"),
        "Instances" => (Expect::Instances, "Objects"),
        "string" | "bool" | "Variant" | "Tuple" => (Expect::Any, ""),
        "ValueArray" => (Expect::Table, "Array"),
        "ValueTable" => (Expect::Table, "Dictionary"),
        "WeakFunctionRef" => (Expect::Function, "Function"),
        "ContentId" | "Content" => (Expect::Text, engine_type),
        "Buffer" => (Expect::Buffer, ""),
        datatype => (Expect::Datatype, datatype),
    };
    let script = &*info.type_info.script;
    // (Roblox's 0.748 dump marks every parameter the capture lets take nil with a default or a `?` type, but ree's 0.747 dump lost
    // most `nil` defaults of instance, options-table and callback parameters, so a later one of those takes nil: a valid call
    // never raises, at the price of some missed misuse, a later function's above all)
    let later_optional_kind = position > 0 && matches!(engine_type, "Instance" | "ValueTable" | "WeakFunctionRef");
    let nil_ok = info.default.is_some() || script.ends_with('?') || matches!(engine_type, "Variant" | "Tuple") || later_optional_kind;
    let nil_mark_trusted = !matches!(
        engine_type,
        "string" | "int" | "int64" | "float" | "double" | "Instance" | "Object" | "ValueTable" | "ValueArray" | "WeakFunctionRef" | "CoordinateFrame"
    );
    let script_type = if expect == Expect::Datatype { script.trim_end_matches('?') } else { "" };
    Param { expect, nil_ok, nil_mark_trusted, target: target.into(), script_type: script_type.into() }
}

/// One copy of each distinct plan for the process (bounded by the reflection's methods), so a C closure can hold a pointer.
fn intern(plan: ArgPlan) -> &'static ArgPlan {
    static PLANS: OnceLock<Mutex<FxHashSet<&'static ArgPlan>>> = OnceLock::new();
    let mut plans = PLANS.get_or_init(Default::default).lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(found) = plans.get(&plan) {
        return found;
    }
    let kept: &'static ArgPlan = Box::leak(Box::new(plan));
    plans.insert(kept);
    kept
}

/// Checks the arguments of a call whose self, an instance, is at stack index `self_index` (the arguments follow it), last to
/// first as a client does (Actor:BindToMessage() says "Argument 2 missing or nil", Camera:ViewportPointToRay("a", workspace)
/// "Unable to cast Instance to float"): Err is the message to raise, without a position.
///
/// # Safety
/// `state` must be the running thread, inside the C function making the call, with `self_index` a valid stack index.
pub unsafe fn check(state: *mut ffi::lua_State, plan: &ArgPlan, self_index: c_int) -> Result<(), String> {
    unsafe {
        let top = ffi::lua_gettop(state);
        for (position, param) in plan.params.iter().enumerate().rev() {
            let index = self_index + 1 + position as c_int;
            let kind = if index <= top { ffi::lua_type(state, index) } else { ffi::LUA_TNIL };
            if kind <= ffi::LUA_TNIL && param.nil_ok {
                continue;
            }
            let left_to_behaviour = param.expect == Expect::Instances || (kind <= ffi::LUA_TNIL && !param.nil_mark_trusted);
            if !plan.checks_missing && left_to_behaviour {
                return Ok(());
            }
            if kind <= ffi::LUA_TNIL {
                return Err(format!("Argument {} missing or nil", position + 1));
            }
            if !accepts(state, param, self_index, index, kind) {
                return Err(refusal(state, param, index, position + 1));
            }
        }
        Ok(())
    }
}

/// What a call the plan refuses does before it raises: a stand-in's records its unemulated member (Output `missing`), as its
/// body would have.
///
/// # Safety
/// `state` must be the running thread, inside the C function making the call.
pub unsafe fn refused(state: *mut ffi::lua_State, plan: &ArgPlan) {
    let Some((class, member)) = &plan.stand_in else { return };
    let lua = unsafe { Lua::get_or_init_from_ptr(state) };
    if let Ok(Some(engine)) = lua.try_app_data_ref::<Rc<Engine>>() {
        engine.missing(Some(lua), class, member);
    }
}

/// Whether the instance `id` is one a call of the plan's method checks arguments for: an instance of the class that declares it
/// (another's is the behaviour's, whose "Expected ':' not '.' calling member function X" comes before the arguments, measured:
/// lua/instance.rs method_function_uncached).
///
/// # Safety
/// `state` must be the running thread, inside the C function making the call.
pub unsafe fn takes_self(state: *mut ffi::lua_State, plan: &ArgPlan, id: crate::InstanceId) -> bool {
    let fits = |engine: &Engine| {
        let Ok(dom_state) = engine.state.try_borrow() else { return true };
        dom_state.dom.get(id).is_some_and(|instance| engine.reflection.class(instance.class).is_a(plan.declaring))
    };
    unsafe { with_engine(state, fits) }.unwrap_or(true)
}

unsafe fn accepts(state: *mut ffi::lua_State, param: &Param, self_index: c_int, index: c_int, kind: c_int) -> bool {
    unsafe {
        match param.expect {
            Expect::Any => true,
            Expect::Number => reads_as_number(state, index, kind),
            Expect::User => kind == ffi::LUA_TUSERDATA || reads_as_number(state, index, kind),
            Expect::Enum(enum_type) => match kind {
                ffi::LUA_TNUMBER | ffi::LUA_TBOOLEAN => true,
                ffi::LUA_TSTRING => names_enum_item(state, &param.target, index),
                ffi::LUA_TUSERDATA => raw::stack_enum_item(state, self_index, index)
                    .is_some_and(|item| with_engine(state, |engine| engine.reflection.enum_item_info(item).enum_type == enum_type).unwrap_or(true)),
                _ => false,
            },
            Expect::Instance => raw::stack_instance(state, index).is_some(),
            Expect::Instances | Expect::Table => kind == ffi::LUA_TTABLE,
            Expect::Function => kind == ffi::LUA_TFUNCTION,
            Expect::Text => matches!(kind, ffi::LUA_TSTRING | ffi::LUA_TUSERDATA),
            Expect::Buffer => kind == ffi::LUA_TBUFFER,
            Expect::Datatype => match kind {
                ffi::LUA_TTABLE => true,
                ffi::LUA_TVECTOR => param.script_type.is_empty() || &*param.script_type == "Vector3",
                ffi::LUA_TUSERDATA => is_datatype(state, &param.script_type, self_index, index),
                _ => false,
            },
        }
    }
}

/// A number, a bool or a string that reads as one (measured: Camera:SetRoll(true) runs, SetRoll("a") "Unable to cast string to
/// float").
unsafe fn reads_as_number(state: *mut ffi::lua_State, index: c_int, kind: c_int) -> bool {
    match kind {
        ffi::LUA_TNUMBER | ffi::LUA_TBOOLEAN => true,
        ffi::LUA_TSTRING => unsafe { ffi::lua_isnumber(state, index) != 0 },
        _ => false,
    }
}

/// Whether the userdata at `index` can be a datatype parameter's value: not an Instance or an EnumItem, and when it names its
/// type (`__type`), the parameter's.
unsafe fn is_datatype(state: *mut ffi::lua_State, script_type: &str, self_index: c_int, index: c_int) -> bool {
    unsafe {
        if raw::stack_instance(state, index).is_some() || raw::stack_enum_item(state, self_index, index).is_some() {
            return false;
        }
        if script_type.is_empty() || ffi::luaL_getmetafield(state, index, c"__type".as_ptr()) == 0 {
            return true;
        }
        let mut length = 0;
        let text = ffi::lua_tolstring(state, -1, &mut length);
        let same = !text.is_null() && std::slice::from_raw_parts(text.cast::<u8>(), length) == script_type.as_bytes();
        ffi::lua_pop(state, 1);
        same
    }
}

/// The message for a value `param` refuses (`number` is its position, 1 the first after self).
unsafe fn refusal(state: *mut ffi::lua_State, param: &Param, index: c_int, number: usize) -> String {
    match param.expect {
        Expect::Buffer => format!("Argument {number} missing or nil"),
        // (whatever it was: "Unable to cast value to Object")
        Expect::Instance | Expect::Instances => format!("Unable to cast value to {}", param.target),
        _ => {
            let value = unsafe { value_at(state, index) };
            let name = value.and_then(|value| unsafe { with_engine(state, |engine| convert::cast_name(engine, &value)) });
            let name = name.unwrap_or_else(|| "value".into());
            format!("Unable to cast {name} to {}", param.target)
        }
    }
}

/// The stack value at `index` as an mlua value (copied through mlua's own thread; a refusal's, so the call raises anyway).
unsafe fn value_at(state: *mut ffi::lua_State, index: c_int) -> Option<LuaValue> {
    unsafe {
        let lua = Lua::get_or_init_from_ptr(state);
        lua.exec_raw::<LuaValue>((), |own| ffi::lua_xpush(state, own, index)).ok()
    }
}

/// Whether the string at `index` names an item of enum `enum_name` (or no engine is there to ask).
unsafe fn names_enum_item(state: *mut ffi::lua_State, enum_name: &str, index: c_int) -> bool {
    unsafe {
        let mut length = 0;
        let text = ffi::lua_tolstring(state, index, &mut length);
        let Ok(name) = std::str::from_utf8(std::slice::from_raw_parts(text.cast::<u8>(), length)) else { return false };
        with_engine(state, |engine| engine.reflection.enum_item(enum_name, name).is_some()).unwrap_or(true)
    }
}

/// `read` of the engine running `state`'s VM (none in a VM without one).
///
/// # Safety
/// `state` must be a live thread of the running VM.
unsafe fn with_engine<T>(state: *mut ffi::lua_State, read: impl FnOnce(&Engine) -> T) -> Option<T> {
    let lua = unsafe { Lua::get_or_init_from_ptr(state) };
    let engine = lua.try_app_data_ref::<Rc<Engine>>().ok().flatten()?;
    Some(read(&engine))
}
