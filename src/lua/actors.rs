//! Actors: the scripts under an Actor run in a VM of their own, as in Studio.
//!
//! An Actor's scripts have their own `_G` and their own copy of every module they require (modules.rs
//! `Vm`, prelude.luau `Environment`). A Script (RunContext Client) or LocalScript that is enabled and
//! under an Actor in the DataModel starts when it gets there (on a server, a Script that would run there: Legacy under
//! Workspace or ServerScriptService, or Server outside ServerStorage), inside the assignment that put it there
//! ([`start_under`]; measured in a Studio client: the worker's first lines print before the line after
//! `Actor.Parent = ...`).
//!
//! `RunService` signals connected with `ConnectParallel` run after the serial handlers of a fire, in the
//! parallel phase ([`parallel_phase`]). Studio runs the Actors' threads at the same time; ree runs them one
//! after the other on the one Luau state, in Studio's order: every parallel handler runs up to its first
//! `task.synchronize()`, then the synchronized threads run serially in that order up to their next
//! `task.desynchronize()`, then the desynchronized ones, and so on until all have finished (the order a
//! Studio client printed for two Actors: both "parallel", both "synchronized", both "desynchronized",
//! newest connection first). `task.synchronize` and `task.desynchronize` anywhere else are no-ops, as
//! they are in a script that is not in a parallel phase. Results are the same as Studio's as long as no
//! Actor reads what another writes in the same step (Studio does not order Actors against each other).

use std::collections::VecDeque;
use std::rc::Rc;

use mlua::prelude::*;
use rustc_hash::FxHashMap;

use super::{Flow, modules::{self, vm_key}};
use crate::{Engine, InstanceId};

/// The Actor `id` is or is under, the nearest.
pub fn actor_of(engine: &Engine, id: InstanceId) -> Option<InstanceId> {
    let actor = engine.class_id("Actor")?;
    let state = engine.state.borrow();
    let mut at = Some(id);
    while let Some(current) = at {
        if state.dom.class_of(current) == actor {
            return Some(current);
        }
        at = state.dom.parent_of(current);
    }
    None
}

/// Whether the DataModel has an Actor (the fast Parent write steps aside for them: [`start_under`]).
pub fn any_actor(engine: &Engine) -> bool {
    engine.class_id("Actor").is_some_and(|actor| engine.state.borrow_mut().dom.count_of_class(actor) > 0)
}

/// The scripts of `ids` that run in an Actor and have not started: enabled, in the DataModel, a LocalScript or a Script with
/// RunContext Client. Pairs of (actor, script). A server (`--run-context server`) runs no client script, and its own
/// Scripts are the harness's to start, as everywhere else in the DataModel.
fn startable(engine: &Engine, ids: &[InstanceId]) -> Vec<(InstanceId, InstanceId)> {
    let server = engine.options.server();
    let (Some(script_class), Some(local_class)) = (engine.class_id("Script"), engine.class_id("LocalScript")) else { return Vec::new() };
    let (Some(enabled), Some(run_context)) = (engine.reflection.name_id("Enabled"), engine.reflection.name_id("RunContext")) else { return Vec::new() };
    let item = |name: &str| engine.reflection.enum_item("RunContext", name);
    let (legacy, server_context, client_context) = (item("Legacy"), item("Server"), item("Client"));
    // (a server's containers, by the rules a loopback server boots its place's scripts by: loopback/mod.rs eligible)
    let game = engine.world().game;
    let service = |name: &str| if server { crate::services::find_service(engine, game, name) } else { None };
    let (workspace, server_scripts, server_storage) = (Some(engine.world().workspace), service("ServerScriptService"), service("ServerStorage"));
    let mut found = Vec::new();
    for &id in ids {
        let ready = {
            let state = engine.state.borrow();
            let class = state.dom.class_of(id);
            let under = |ancestor: Option<InstanceId>| ancestor.is_some_and(|ancestor| state.dom.is_descendant_of(id, ancestor));
            let context = state.dom.raw_get(id, run_context).and_then(crate::Value::as_enum);
            let runs_here = if server {
                class == script_class
                    && (((context.is_none() || context == legacy) && (under(workspace) || under(server_scripts)))
                        || (context.is_some() && context == server_context && !under(server_storage)))
            } else {
                class == local_class || (class == script_class && context.is_some() && context == client_context)
            };
            runs_here && !engine.modules.borrow().started(id) && state.dom.boolean(id, enabled) != Some(false) && crate::services::in_data_model(&state, id)
        };
        if ready {
            if let Some(actor) = actor_of(engine, id) {
                found.push((actor, id));
            }
        }
    }
    found
}

fn start(lua: &Lua, engine: &Rc<Engine>, pending: Vec<(InstanceId, InstanceId)>) -> LuaResult<()> {
    for (actor, script) in pending {
        if engine.modules.borrow().started(script) {
            continue;
        }
        engine.modules.borrow_mut().mark_started(script);
        let Some(source) = modules::source_of(engine, script) else { continue };
        let name = engine.state.borrow().dom.full_name(&engine.reflection, script);
        match modules::compile_in(lua, engine, script, &source, Some(vm_key(actor))) {
            Ok(chunk) => {
                let thread = lua.create_thread(chunk)?;
                crate::scheduler::resume(lua, engine, &thread, LuaMultiValue::new());
            }
            Err(error) => engine.output("error", format!("{name}: {}", crate::scheduler::error_message(&error)), None),
        }
    }
    Ok(())
}

/// The subtree of `root` entered the DataModel, or the script `root` got enabled: starts the scripts under Actors in it, now.
pub fn start_under(lua: &Lua, engine: &Rc<Engine>, root: InstanceId) -> LuaResult<()> {
    let Some(actor_class) = engine.class_id("Actor") else { return Ok(()) };
    if engine.state.borrow_mut().dom.count_of_class(actor_class) == 0 {
        return Ok(());
    }
    let mut ids = vec![root];
    ids.extend(engine.state.borrow().dom.descendants(root));
    start(lua, engine, startable(engine, &ids))
}

/// Starts every script under an Actor that has not started (a frame step's sweep for what no assignment reported).
pub fn start_scripts(lua: &Lua, engine: &Rc<Engine>) -> LuaResult<()> {
    {
        let mut modules = engine.modules.borrow_mut();
        let parallel = &mut modules.parallel;
        if !parallel.waking.is_empty() {
            let finished: Vec<usize> = parallel.waking.iter().filter(|(_, thread)| thread.status() != LuaThreadStatus::Resumable).map(|(&key, _)| key).collect();
            for key in finished {
                parallel.waking.remove(&key);
                parallel.modes.remove(&key);
            }
        }
    }
    let Some(actor_class) = engine.class_id("Actor") else { return Ok(()) };
    let actors = engine.state.borrow_mut().dom.instances_of_class(actor_class);
    let mut ids = Vec::new();
    for actor in actors {
        ids.extend(engine.state.borrow().dom.descendants(actor));
    }
    if ids.is_empty() {
        return Ok(());
    }
    start(lua, engine, startable(engine, &ids))
}

/// Where the threads of a parallel phase stand.
#[derive(Default)]
pub struct Parallel {
    /// Threads of running parallel phases: true while the thread is in the parallel part of its callback
    modes: FxHashMap<usize, bool>,
    /// The phases running (a parallel handler can fire a signal with parallel handlers): the innermost last
    phases: Vec<Phase>,
    /// Parallel handlers' threads that yielded in their parallel part on something else (task.wait) and so resume
    /// desynchronized, as in Studio (measured: GetService after a task.wait in a ConnectParallel handler raised); held until
    /// they finish ([`start_scripts`] sweeps them) so their key is not another thread's
    waking: FxHashMap<usize, LuaThread>,
}

#[derive(Default)]
struct Phase {
    /// Threads that called task.synchronize, in the order they did
    synchronized: VecDeque<LuaThread>,
    /// Threads that called task.desynchronize, in the order they did
    desynchronized: VecDeque<LuaThread>,
}

fn key(thread: &LuaThread) -> usize {
    thread.to_pointer() as usize
}

/// Whether the thread whose state is `state` runs in the parallel part of a parallel phase (desynchronized): the raw API's
/// methods, property writes and event reads refuse what is not thread safe there ([`parallel_refusal`]). Free while no
/// phase runs.
pub(crate) fn desynchronized(engine: &Engine, state: *mut mlua::ffi::lua_State) -> bool {
    let Ok(modules) = engine.modules.try_borrow() else { return false };
    let parallel = &modules.parallel;
    (!parallel.phases.is_empty() || !parallel.waking.is_empty()) && parallel.modes.get(&(state as usize)) == Some(&true)
}

/// What a desynchronized thread may not do to a member, as Roblox refuses it (measured in Studio 0.748, a server Script
/// under an Actor in a Heartbeat ConnectParallel handler): a method the dump gives no `CallParallel` (Destroy, Clone,
/// SetAttribute, GetService, FireAllClients, WaitForChild, PivotTo; FindFirstChild, GetChildren, GetAttribute, Raycast, IsA
/// and BindableEvent.Fire ran), any property write (an unparented part's Name too) and any event read (`part.Touched`).
/// Reads, Instance.new, task.wait and task.spawn ran. The member's declaring class names it.
pub(crate) enum ParallelUse {
    Call,
    Write,
    Event,
}

pub(crate) fn parallel_refusal(engine: &Engine, class: crate::ClassId, name: crate::NameId, use_: ParallelUse) -> Option<String> {
    let reflection = &engine.reflection;
    let (kind, owner, verb) = match use_ {
        ParallelUse::Call => {
            let method = reflection.class_method(class, name).filter(|method| !method.callable_in_parallel())?;
            ("Function", method.owner, "call")
        }
        ParallelUse::Write => ("Property", reflection.class_property(class, name)?.owner, "write"),
        ParallelUse::Event => ("Event", reflection.class_event(class, name)?.owner, "access"),
    };
    Some(format!("{kind} {}.{} is not safe to {verb} in parallel", reflection.class(owner).name, reflection.name(name)))
}

/// task.synchronize (`to_serial`) or task.desynchronize of the running thread: true when it must yield now, because it is a
/// parallel handler's thread of a running phase that is leaving its part for the other. Where the thread cannot yield it
/// raises `thread is not yieldable` and stays in its part (by the rule measured for the engine's other yielding calls,
/// lua/mod.rs NOT_YIELDABLE; not measured in an Actor).
pub fn park(lua: &Lua, engine: &Engine, to_serial: bool) -> Result<bool, Flow> {
    let thread = lua.current_thread();
    let mut modules = engine.modules.borrow_mut();
    let parallel = &mut modules.parallel;
    let Some(&in_parallel) = parallel.modes.get(&key(&thread)) else { return Ok(false) };
    // (a thread resumed desynchronized outside a phase: task.synchronize makes it serial where it stands)
    if parallel.waking.contains_key(&key(&thread)) {
        if to_serial && in_parallel {
            parallel.modes.insert(key(&thread), false);
        }
        return Ok(false);
    }
    let Some(phase) = parallel.phases.last_mut() else { return Ok(false) };
    if in_parallel != to_serial {
        return Ok(false);
    }
    if !super::yieldable(&thread) {
        drop(modules);
        return super::raise_plain(super::NOT_YIELDABLE);
    }
    parallel.modes.insert(key(&thread), !to_serial);
    if to_serial {
        phase.synchronized.push_back(thread);
    } else {
        phase.desynchronized.push_back(thread);
    }
    Ok(true)
}

/// A fire's parallel handlers, after its serial ones: `threads` are their threads with the arguments of the fire.
pub fn parallel_phase(lua: &Lua, engine: &Rc<Engine>, threads: Vec<(LuaThread, LuaMultiValue)>) {
    {
        let mut modules = engine.modules.borrow_mut();
        modules.parallel.phases.push(Phase::default());
        for (thread, _) in &threads {
            modules.parallel.modes.insert(key(thread), true);
        }
    }
    for (thread, values) in &threads {
        crate::scheduler::resume(lua, engine, thread, values.clone());
    }
    loop {
        let (synchronized, desynchronized) = {
            let mut modules = engine.modules.borrow_mut();
            let phase = modules.parallel.phases.last_mut().expect("a parallel phase");
            (std::mem::take(&mut phase.synchronized), std::mem::take(&mut phase.desynchronized))
        };
        if synchronized.is_empty() && desynchronized.is_empty() {
            break;
        }
        for thread in synchronized.into_iter().chain(desynchronized) {
            crate::scheduler::resume(lua, engine, &thread, LuaMultiValue::new());
        }
    }
    let mut modules = engine.modules.borrow_mut();
    let parallel = &mut modules.parallel;
    parallel.phases.pop();
    for (thread, _) in &threads {
        if thread.status() == LuaThreadStatus::Resumable && parallel.modes.get(&key(thread)) == Some(&true) {
            parallel.waking.insert(key(thread), thread.clone());
        } else {
            parallel.modes.remove(&key(thread));
        }
    }
}

/// Whether a function runs in an Actor's VM: its environment is one of Actor VM environments (prelude.luau `Environment` gives
/// those their own `_G`).
pub fn runs_in_actor(function: &LuaFunction) -> bool {
    function.environment().is_some_and(|env| env.raw_get::<LuaValue>("_G").is_ok_and(|globals| !globals.is_nil()))
}
