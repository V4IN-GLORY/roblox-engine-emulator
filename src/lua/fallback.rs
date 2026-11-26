//! What a reflected method no behaviour implements answers (lua/instance.rs `unimplemented_function`): a value of its reflected
//! return type, so a script that uses the result runs on as it does in Roblox, and its use is written as an Output line of kind
//! `stubbed`. The rules (docs/engine.md "Unemulated methods") come from the method's reflected return type alone and were checked
//! against what each method returned in a Roblox Studio 0.748.0.7481526 playtest called with valid arguments
//! (validator/probe/expected, the `cv` lines).

use std::{cell::OnceCell, rc::Rc};

use mlua::prelude::*;

use super::{Flow, convert};
use crate::{
    ClassId, Engine, NameId,
    reflection::{ScriptType, TypeInfo},
    scheduler::TimerKind,
    value::Value,
};

/// What a stand-in returns.
enum Returns {
    /// Nothing: a Void method, a Tuple (whose values the dump does not name), a method with no recorded signature
    Nothing,
    /// One nil: a Variant, an optional (`X?`), an abstract class, a datatype ree cannot make
    Nil,
    /// One value made once and shared by every call: an immutable one (a number, a string, an enum item, a datatype)
    Shared(LuaValue),
    /// A fresh table per call (a table, an instance list: a script may fill it)
    Table,
    /// A fresh buffer per call
    Buffer,
    /// A fresh instance of the class per call, as Roblox makes one
    Instance(ClassId),
    /// A fresh value per call from the datatype's constructor (a mutable datatype: RaycastParams, SharedTable)
    Made(LuaFunction),
    /// A connection (`connects`) to, or the signal of, a BindableEvent made at the first call ([`signal`])
    Signal { connects: bool, made: OnceCell<(LuaValue, LuaFunction)> },
}

/// A stand-in's answer, made once when its function is.
pub(crate) struct Fallback {
    returns: Returns,
    /// Roblox's `Async` methods yield: the answer comes a frame later
    yields: bool,
}

impl Fallback {
    pub(crate) fn new(lua: &Lua, engine: &Rc<Engine>, class: ClassId, name: NameId) -> LuaResult<Fallback> {
        let reflection = &engine.reflection;
        let returns = match reflection.class_method(class, name).and_then(|method| method.returns.as_ref()) {
            Some(type_info) => returns(lua, engine, type_info)?,
            None => Returns::Nothing,
        };
        Ok(Fallback { returns, yields: reflection.name(name).ends_with("Async") })
    }

    /// The call's results, or its yield with them registered as its resumption.
    pub(crate) fn answer(&self, lua: &Lua, engine: &Rc<Engine>) -> LuaResult<LuaMultiValue> {
        let value = match &self.returns {
            Returns::Nothing => None,
            Returns::Nil => Some(LuaValue::Nil),
            Returns::Shared(value) => Some(value.clone()),
            Returns::Table => Some(LuaValue::Table(lua.create_table()?)),
            Returns::Buffer => Some(LuaValue::Buffer(lua.create_buffer([])?)),
            Returns::Instance(class) => {
                let id = crate::instance::create(&mut engine.state.borrow_mut(), &engine.reflection, *class);
                Some(convert::to_lua(lua, engine, &Value::Instance(id))?)
            }
            Returns::Made(constructor) => Some(constructor.call::<LuaValue>(())?),
            Returns::Signal { connects, made } => {
                if made.get().is_none() {
                    let _ = made.set(signal(lua, engine)?);
                }
                let (event, connect) = made.get().expect("made above");
                Some(if *connects { connect.call::<LuaValue>(())? } else { event.clone() })
            }
        };
        if !self.yields {
            return Ok(LuaMultiValue::from_iter(value));
        }
        let thread = lua.current_thread();
        if let Err(refused) = super::refuse_unyieldable(&thread, super::NOT_YIELDABLE) {
            return super::encode(lua, Err(refused));
        }
        let resumed: Vec<Value> = value.iter().map(convert::from_lua).collect();
        engine.state.borrow_mut().sched.schedule_task(TimerKind::Delay, 0.0, thread, resumed);
        super::encode(lua, Err(Flow::Yield))
    }
}

/// The answer for a reflected return type. Where the capture disagrees with the type, the type wins and docs/engine.md says where.
fn returns(lua: &Lua, engine: &Rc<Engine>, type_info: &TypeInfo) -> LuaResult<Returns> {
    let reflection = &engine.reflection;
    // (the dump names some types only by their engine name: AdReward, CollectionHandle, ValueCurveKey)
    let type_name = if type_info.script.is_empty() { &*type_info.engine } else { &*type_info.script };
    if type_name.ends_with('?') {
        return Ok(Returns::Nil);
    }
    match &*type_info.engine {
        "Void" | "Tuple" => return Ok(Returns::Nothing),
        "Variant" => return Ok(Returns::Nil),
        _ => {}
    }
    Ok(match type_name {
        "table" | "Array" | "Dictionary" | "Instances" | "Objects" => Returns::Table,
        "buffer" => Returns::Buffer,
        "Instance" | "Object" => {
            let Some(class) = type_info.instance_type.as_deref().and_then(|name| reflection.class_id(name)) else { return Ok(Returns::Nil) };
            let info = reflection.class(class);
            // (an abstract class names what kind of instance comes back, not one to make: GetRootPart's Instance, Capture's
            // subclasses; Roblox's answers for these were nil in the capture)
            if info.service || (!info.creatable && !info.subclasses.is_empty()) {
                Returns::Nil
            } else {
                Returns::Instance(class)
            }
        }
        "Connection" | "EventInstance" => Returns::Signal { connects: &*type_info.engine == "Connection", made: OnceCell::new() },
        _ => {
            let enum_type = type_info.enum_name.as_deref().and_then(|name| reflection.enum_id(name));
            match crate::value::zero_value(reflection, ScriptType::parse(type_name), type_name, enum_type) {
                Some(value) => Returns::Shared(convert::to_lua(lua, engine, &value)?),
                None => datatype_returns(engine, type_name)?,
            }
        }
    })
}

/// A datatype zero_value does not cover: what its library's `new()` makes with no arguments, a fresh one per call, where that is
/// a value of the type; else nil.
fn datatype_returns(engine: &Rc<Engine>, type_name: &str) -> LuaResult<Returns> {
    let Some(shared) = engine.lua.borrow().shared.clone() else { return Ok(Returns::Nil) };
    let Ok(LuaValue::Table(library)) = shared.get::<LuaValue>(type_name) else { return Ok(Returns::Nil) };
    let Ok(LuaValue::Function(constructor)) = library.get::<LuaValue>("new") else { return Ok(Returns::Nil) };
    let typeof_function: LuaFunction = shared.get("typeof")?;
    let Ok(sample) = constructor.call::<LuaValue>(()) else { return Ok(Returns::Nil) };
    let sample_type: LuaString = typeof_function.call(sample)?;
    Ok(if sample_type.as_bytes() == type_name.as_bytes() { Returns::Made(constructor) } else { Returns::Nil })
}

/// A BindableEvent's signal, which nothing fires, and a function connecting to it (connected, as Roblox's are: a script may
/// disconnect it).
fn signal(lua: &Lua, engine: &Rc<Engine>) -> LuaResult<(LuaValue, LuaFunction)> {
    let Some(shared) = engine.lua.borrow().shared.clone() else { return Err(LuaError::runtime("no script globals")) };
    lua.load("local Bindable = Instance.new(\"BindableEvent\")
local function Ignore() end
return Bindable.Event, function() return Bindable.Event:Connect(Ignore) end")
        .set_name("=ree.fallback")
        .set_environment(shared)
        .call(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An optional (`X?`) return answers nil, a Void one nothing, a Variant nil, an abstract class nil, a leaf class an
    /// instance of it (validator/probe/expected: WorldRoot.Blockcast's `RaycastResult?` gave nil)
    #[test]
    fn return_types_choose_the_answer() {
        let engine = Engine::new(crate::Options::default()).unwrap();
        let lua = Lua::new();
        crate::lua::start(&lua, &engine).unwrap();
        let typed = |script: &str, engine_type: &str, instance: Option<&str>| TypeInfo {
            script: script.into(),
            engine: engine_type.into(),
            instance_type: instance.map(Into::into),
            ..TypeInfo::default()
        };
        let pick = |type_info: TypeInfo| returns(&lua, &engine, &type_info).unwrap();
        assert!(matches!(pick(typed("RaycastResult?", "RaycastResult", None)), Returns::Nil));
        assert!(matches!(pick(typed("", "Void", None)), Returns::Nothing));
        assert!(matches!(pick(typed("...", "Tuple", None)), Returns::Nothing));
        assert!(matches!(pick(typed("", "Variant", None)), Returns::Nil));
        assert!(matches!(pick(typed("Instance", "Instance", Some("Instance"))), Returns::Nil));
        let path = engine.reflection.class_id("Path").unwrap();
        assert!(matches!(pick(typed("Instance", "Instance", Some("Path"))), Returns::Instance(class) if class == path));
        assert!(matches!(pick(typed("table", "ValueArray", None)), Returns::Table));
        assert!(matches!(pick(typed("number", "int64", None)), Returns::Shared(LuaValue::Number(zero)) if zero == 0.0));
    }
}
