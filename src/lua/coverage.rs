//! `--fire-handlers` ([`crate::Options::fire_handlers`], docs/engine.md "Coverage pass"): a validator's run is short and offline,
//! so nobody joins, touches or clicks, and the handlers a script only connects never run. The run records what its scripts hand
//! the engine to call (connections, callbacks, the handlers of coverage.luau's BINDERS), and after its frames a coverage pass
//! (record/run.rs) calls each once that the run never called. A server's player joins and every player gets a character first,
//! so PlayerAdded and CharacterAdded run on the real path; the rest are called with arguments of their reflected parameter
//! types (fallback.rs's values; a parameter of the player's, the character's, its humanoid's or its leg's class gets that one).
//! The engine's own Luau (`=rur.*`, `=ree.*` chunks) is never recorded. Lines written meanwhile carry `coverage`.

use std::rc::Rc;

use mlua::prelude::*;

use super::{convert, fallback};
use crate::{
    ClassId, Engine, InstanceId, NameId,
    reflection::TypeInfo,
    scheduler::{DispatchKind, JobTarget},
    signal::{ConnectionId, SignalId},
    value::Value,
};

static SOURCE: &str = include_str!("coverage.luau");

/// What a run records per kind before it stops recording (a script that connects in a loop)
const MAX_RECORDED: usize = 256;

/// Stands for ProcessReceipt's receipt table among [`CALLBACK_ARGUMENTS`]
const RECEIPT: &str = "Receipt";

/// The arguments Roblox calls a callback with, by its name: the API dump records none (reflection.rs CALLBACK_SUPPLEMENT), so
/// these are Roblox's API reference's, as class names. A callback not listed is called with none.
const CALLBACK_ARGUMENTS: &[(&str, &[&str])] = &[
    ("OnServerInvoke", &["Player"]),
    ("ProcessReceipt", &[RECEIPT]),
    ("OnIncomingMessage", &["TextChatMessage"]),
    ("OnChatWindowAdded", &["TextChatMessage"]),
    ("OnBubbleAdded", &["TextChatMessage", "Instance"]),
    ("ShouldDeliverCallback", &["TextChatMessage", "TextSource"]),
];

/// Whether a recorded thing was called, and by whom
#[derive(Clone, Copy, PartialEq, Eq)]
enum Called {
    Not,
    /// By the run's own events, before the pass
    ByRun,
    /// By an event during the pass (the player's join, its character, the frames after them)
    ByStaging,
    /// By the pass, with typed arguments
    ByPass,
}

struct Connected {
    connection: ConnectionId,
    signal: SignalId,
    called: Called,
}

struct Bound {
    label: String,
    handler: LuaFunction,
    arguments: Vec<Value>,
    called: Called,
}

/// What the run's scripts handed the engine to call, and the pass's player ([`Engine`]'s `LuaRefs::coverage`).
#[derive(Default)]
pub(crate) struct Recorded {
    connections: Vec<Connected>,
    /// A callback set on an instance, and whether the pass called it
    callbacks: Vec<(InstanceId, NameId, Called)>,
    bound: Vec<Bound>,
    /// coverage.luau's Join and Spawn, set when it loads
    staging: Option<(LuaFunction, LuaFunction)>,
    /// From the staging on: what a handler gets for an Instance parameter, by class, in Spawn's order
    samples: Vec<(ClassId, LuaValue)>,
    receipt: LuaValue,
    staged: bool,
}

/// Whether `function` is a script's (not the engine's own Luau)
fn from_script(function: &LuaFunction) -> bool {
    let source = function.info().source.unwrap_or_default();
    !(source.starts_with("=rur.") || source.starts_with("=ree."))
}

/// Loads coverage.luau into the service stubs (`r`, lua/stubs.rs), after every file that may replace a method it wraps.
pub(crate) fn load(lua: &Lua, engine: &Rc<Engine>, r: &LuaTable, shared: LuaTable) -> LuaResult<()> {
    let e = engine.clone();
    let record = super::lua_fn(lua, move |_, (label, handler, arguments): (String, LuaFunction, LuaMultiValue)| {
        let mut refs = e.lua.borrow_mut();
        let bound = &mut refs.coverage.bound;
        if from_script(&handler) && bound.len() < MAX_RECORDED {
            bound.push(Bound { label, handler, arguments: arguments.iter().map(convert::from_lua).collect(), called: Called::Not });
        }
        Ok(())
    })?;
    let chunk = super::modules::load_engine_luau(lua, SOURCE, "=ree.coverage", Some(shared))?;
    let staging: (LuaFunction, LuaFunction) = crate::cost::engine_luau(lua, chunk)?.call((r.clone(), record))?;
    engine.lua.borrow_mut().coverage.staging = Some(staging);
    Ok(())
}

/// A script connected `callback` to `signal` (types.rs connect_as).
pub(crate) fn connected(engine: &Engine, callback: &LuaFunction, signal: SignalId, connection: ConnectionId) {
    let Ok(mut refs) = engine.lua.try_borrow_mut() else { return };
    let connections = &mut refs.coverage.connections;
    if connections.len() < MAX_RECORDED && from_script(callback) {
        connections.push(Connected { connection, signal, called: Called::Not });
    }
}

/// A script set the callback `name` of `id` to `function` (instance.rs).
pub(crate) fn callback_set(engine: &Engine, id: InstanceId, name: NameId, function: &LuaFunction) {
    let Ok(mut refs) = engine.lua.try_borrow_mut() else { return };
    let callbacks = &mut refs.coverage.callbacks;
    let known = callbacks.iter().any(|(instance, callback, _)| *instance == id && *callback == name);
    if !known && callbacks.len() < MAX_RECORDED && from_script(function) {
        callbacks.push((id, name, Called::Not));
    }
}

/// A handler of `connection` runs (scheduler.rs run_handler).
pub(crate) fn ran(engine: &Engine, connection: ConnectionId) {
    // (the hooks run deep in dispatch and in script calls: one that finds the refs borrowed records nothing rather than panic)
    let Ok(mut refs) = engine.lua.try_borrow_mut() else { return };
    let recorded = &mut refs.coverage;
    let by = if recorded.staged { Called::ByStaging } else { Called::ByRun };
    if let Some(connected) = recorded.connections.iter_mut().find(|connected| connected.connection == connection && connected.called == Called::Not) {
        connected.called = by;
    }
}

fn staging(engine: &Engine) -> LuaResult<(LuaFunction, LuaFunction)> {
    engine.lua.borrow().coverage.staging.clone().ok_or_else(|| LuaError::runtime("coverage.luau is not loaded"))
}

/// The pass's first step: a server's player joins (a client has its local player). What its events call from now on counts as
/// the staging's.
pub(crate) fn join(engine: &Rc<Engine>) -> LuaResult<()> {
    let (join, _) = staging(engine)?;
    engine.lua.borrow_mut().coverage.staged = true;
    let profile = engine.profile();
    join.call::<()>((profile.identity.name().to_string(), profile.identity.user_id()))
}

/// The pass's second step, a round after the join: the player's character, and what handlers get for Instance parameters.
pub(crate) fn spawn(engine: &Rc<Engine>) -> LuaResult<()> {
    let (_, spawn) = staging(engine)?;
    let (instances, receipt): (LuaTable, LuaValue) = spawn.call(())?;
    let mut samples = Vec::new();
    for instance in instances.sequence_values::<LuaValue>() {
        let instance = instance?;
        if let Value::Instance(id) = convert::from_lua(&instance)
            && let Some(class) = engine.state.borrow().dom.get(id).map(|instance| instance.class)
        {
            samples.push((class, instance));
        }
    }
    let mut refs = engine.lua.borrow_mut();
    refs.coverage.samples = samples;
    refs.coverage.receipt = receipt;
    Ok(())
}

/// Queues a call of each recorded handler nothing has called yet, with arguments of its parameters' types: the number queued.
pub(crate) fn fire(lua: &Lua, engine: &Rc<Engine>) -> LuaResult<usize> {
    let (connections, callbacks, bound) = {
        let mut refs = engine.lua.borrow_mut();
        let recorded = &mut refs.coverage;
        let state = engine.state.borrow();
        let mut connections = Vec::new();
        for connected in recorded.connections.iter_mut().filter(|connected| connected.called == Called::Not) {
            if state.signals.connection(connected.connection).is_some() {
                connected.called = Called::ByPass;
                connections.push((connected.connection, connected.signal));
            }
        }
        let mut callbacks = Vec::new();
        for (id, name, called) in recorded.callbacks.iter_mut().filter(|(_, _, called)| *called == Called::Not) {
            *called = Called::ByPass;
            callbacks.push((*id, *name));
        }
        let mut bound = Vec::new();
        for entry in recorded.bound.iter_mut().filter(|entry| entry.called == Called::Not) {
            entry.called = Called::ByPass;
            bound.push((entry.handler.clone(), entry.arguments.clone()));
        }
        (connections, callbacks, bound)
    };
    let queued = connections.len() + callbacks.len() + bound.len();
    for (connection, signal) in connections {
        let arguments = arguments(lua, engine, &event_parameters(engine, signal))?;
        let target = JobTarget::Handler { connection, kind: DispatchKind::Signal(crate::cost::SignalKind::Unmeasured) };
        engine.state.borrow_mut().sched.defer_handler(target, arguments, 0.0, signal);
    }
    for (id, name) in callbacks {
        let function = engine.state.borrow().dom.get(id).and_then(|instance| instance.callback(name).cloned());
        let Some(LuaValue::Function(function)) = function else { continue };
        let callback = engine.reflection.name(name);
        let types = CALLBACK_ARGUMENTS.iter().find(|(listed, _)| *listed == callback).map_or(&[][..], |(_, types)| types);
        let mut values = Vec::with_capacity(types.len());
        for &type_name in types {
            if type_name == RECEIPT {
                values.push(convert::from_lua(&engine.lua.borrow().coverage.receipt));
                continue;
            }
            let type_info = TypeInfo { script: "Instance".into(), engine: "Instance".into(), instance_type: Some(type_name.into()), ..TypeInfo::default() };
            values.extend(arguments(lua, engine, &[type_info])?);
        }
        call(lua, engine, function, values)?;
    }
    for (handler, values) in bound {
        call(lua, engine, handler, values)?;
    }
    Ok(queued)
}

/// Queues `function` on a fresh thread, as a callback the engine calls runs
fn call(lua: &Lua, engine: &Rc<Engine>, function: LuaFunction, arguments: Vec<Value>) -> LuaResult<()> {
    let thread = lua.create_thread(function)?;
    engine.state.borrow_mut().sched.defer_event(JobTarget::Thread(thread), arguments);
    Ok(())
}

/// The parameter types of the event `signal` is (its label names the class and the event); none for a property's or an
/// attribute's changed signal, which fire with none
fn event_parameters(engine: &Engine, signal: SignalId) -> Vec<TypeInfo> {
    let label = engine.state.borrow().signals.get(signal).label.to_str_lossy().into_owned();
    let reflection = &engine.reflection;
    let Some((class, event)) = label.split_once('.') else { return Vec::new() };
    let (Some(class), Some(event)) = (reflection.class_id(class), reflection.name_id(event)) else { return Vec::new() };
    reflection.class_event(class, event).map_or_else(Vec::new, |info| info.parameters.iter().map(|parameter| parameter.type_info.clone()).collect())
}

/// Values of `types`: a staged instance for an Instance parameter of its class (of a subclass, for an abstract class), else what a
/// stand-in returning the type answers. Stops at a type that has no value (a Tuple: the rest of the arguments).
fn arguments(lua: &Lua, engine: &Rc<Engine>, types: &[TypeInfo]) -> LuaResult<Vec<Value>> {
    let mut values = Vec::with_capacity(types.len());
    for type_info in types {
        let type_name = if type_info.script.is_empty() { &*type_info.engine } else { &*type_info.script };
        let class = type_info.instance_type.as_deref().and_then(|name| engine.reflection.class_id(name));
        let staged = match class {
            Some(class) if matches!(type_name, "Instance" | "Object") => sample(engine, class),
            _ => None,
        };
        let value = match staged {
            Some(value) => value,
            None => match fallback::value_of(lua, engine, type_info)? {
                Some(value) => value,
                None => break,
            },
        };
        values.push(convert::from_lua(&value));
    }
    Ok(values)
}

/// The staged instance of `class`, else for an abstract class the first staged instance that is one
fn sample(engine: &Engine, class: ClassId) -> Option<LuaValue> {
    let refs = engine.lua.borrow();
    let samples = &refs.coverage.samples;
    if let Some((_, value)) = samples.iter().find(|(sampled, _)| *sampled == class) {
        return Some(value.clone());
    }
    if !fallback::is_abstract(engine.reflection.class(class)) {
        return None;
    }
    samples.iter().find(|(sampled, _)| engine.reflection.class(*sampled).is_a(class)).map(|(_, value)| value.clone())
}

/// The summary's `coverage`: the labels of what the pass's events called on the real path (`real`: the join, the character and
/// the frames after them), what the pass called with typed arguments (`fired`) and what the run had called itself (`ran`)
pub(crate) fn summary(engine: &Engine) -> serde_json::Value {
    let refs = engine.lua.borrow();
    let recorded = &refs.coverage;
    let state = engine.state.borrow();
    let mut lists: [Vec<String>; 3] = Default::default();
    let mut add = |called: Called, label: String| {
        let index = match called {
            Called::Not => return,
            Called::ByRun => 2,
            Called::ByStaging => 0,
            Called::ByPass => 1,
        };
        lists[index].push(label);
    };
    for connected in &recorded.connections {
        add(connected.called, state.signals.get(connected.signal).label.to_str_lossy().into_owned());
    }
    for (id, name, called) in &recorded.callbacks {
        let class = state.dom.get(*id).map_or("Instance", |instance| &*engine.reflection.class(instance.class).name);
        add(*called, format!("{class}.{}", engine.reflection.name(*name)));
    }
    for entry in &recorded.bound {
        add(entry.called, entry.label.clone());
    }
    let [real, fired, ran] = lists;
    serde_json::json!({ "real": real, "fired": fired, "ran": ran })
}

#[cfg(test)]
mod tests {
    use crate::{launch::Host, record::run};

    /// `ree run` of `body` (a script's body, as validator/validate.py wraps it) in `context` with `extra` arguments
    #[inline(never)]
    fn run_body(name: &str, context: &str, body: &str, extra: &[&str]) -> serde_json::Value {
        let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
        let dir = std::env::temp_dir().join(format!("ree-coverage-{name}-{}-{nanos}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join(format!("{name}.luau"));
        std::fs::write(&file, format!("return function(Context)\n{body}\nend\n")).unwrap();
        let mut words: Vec<String> = ["--harness", &file.to_string_lossy(), "--seconds", "0.5", "--mode", "play", "--run-context", context].iter().map(|s| s.to_string()).collect();
        words.extend(extra.iter().map(|s| s.to_string()));
        let summary = run::parse(&words, false).and_then(|args| run::run_only(&args, &Host::default()));
        let _ = std::fs::remove_dir_all(&dir);
        summary.unwrap_or_else(|error| panic!("{error}"))
    }

    /// Every output line as `kind message`, with ` [coverage]` after a line of the pass
    fn lines(summary: &serde_json::Value) -> Vec<String> {
        let marked = |line: &serde_json::Value| if line["coverage"] == true { " [coverage]" } else { "" };
        summary["output"].as_array().unwrap().iter().map(|line| format!("{} {}{}", line["kind"].as_str().unwrap(), line["message"].as_str().unwrap(), marked(line))).collect()
    }

    fn listed(summary: &serde_json::Value, list: &str) -> Vec<String> {
        summary["coverage"][list].as_array().unwrap().iter().map(|label| label.as_str().unwrap().to_string()).collect()
    }

    /// A handler nothing in the run calls is called once by the pass, and what it raises is an error of the run marked as the
    /// pass's; without the flag the run is as it was (no call, no `coverage` in the summary or on a line)
    #[test]
    fn a_handler_only_connected_runs_in_the_coverage_pass() {
        let body = "print('loaded') game:GetService('Players').PlayerAdded:Connect(function(player) player.leaderstats.Coins.Value += 1 end)";
        let plain = run_body("plain", "server", body, &[]);
        assert_eq!(lines(&plain), ["print loaded"]);
        assert!(plain.get("coverage").is_none(), "{plain}");
        let covered = run_body("covered", "server", body, &["--fire-handlers"]);
        let lines = lines(&covered);
        assert_eq!(lines[0], "print loaded");
        assert!(lines.iter().any(|line| line == "error leaderstats is not a valid member of Player \"Players.Player\" [coverage]"), "{lines:?}");
        assert_eq!(covered["errors"], 1, "{covered}");
        // (the join is the real path: PlayerAdded ran on it, nothing was called with made-up arguments)
        assert_eq!(listed(&covered, "real"), ["Players.PlayerAdded"]);
        assert!(listed(&covered, "fired").is_empty(), "{covered}");
    }

    /// The pass's calls get arguments of the event's parameter types: the joined player for a Player, the character's leg for
    /// Touched's BasePart (its Parent the character, with a Humanoid), a fresh InputObject; callbacks and the handlers given to
    /// BindToClose are called; a handler connected by a handler of the pass (Died, in CharacterAdded) is called the round after;
    /// the engine's own connections are not
    #[test]
    fn the_pass_calls_with_typed_arguments_and_the_staged_player() {
        let body = r##"
        local Players = game:GetService("Players")
        local Part = Instance.new("Part")
        Part.Parent = workspace
        Part.Touched:Connect(function(Hit)
            print("touched", Hit.Name, Hit.Parent.Humanoid.Health, Players:GetPlayerFromCharacter(Hit.Parent) ~= nil)
        end)
        local Remote = Instance.new("RemoteEvent")
        Remote.Parent = game:GetService("ReplicatedStorage")
        Remote.OnServerEvent:Connect(function(Player, ...) print("remote", Player:IsA("Player"), select("#", ...)) end)
        local Function = Instance.new("RemoteFunction")
        Function.OnServerInvoke = function(Player) print("invoked", Player.Name) end
        game:GetService("MarketplaceService").ProcessReceipt = function(Receipt) print("receipt", Receipt.PlayerId, Receipt.ProductId) end
        game:BindToClose(function() print("closing") end)
        Players.PlayerAdded:Connect(function(Player)
            Player.CharacterAdded:Connect(function(Character)
                Character:FindFirstChildOfClass("Humanoid").Died:Connect(function() print("died") end)
            end)
        end)
        "##;
        let summary = run_body("typed", "server", body, &["--fire-handlers"]);
        let lines = lines(&summary);
        for wanted in ["print touched Right Leg 100 true [coverage]", "print remote true 0 [coverage]", "print invoked Player [coverage]", "print receipt 1 0 [coverage]", "print closing [coverage]", "print died [coverage]"] {
            assert!(lines.iter().any(|line| line == wanted), "{wanted}: {lines:?}");
        }
        assert_eq!(summary["errors"], 0, "{summary}");
        assert_eq!(listed(&summary, "real"), ["Players.PlayerAdded", "Player.CharacterAdded"]);
        let mut fired = listed(&summary, "fired");
        fired.sort();
        assert_eq!(fired, ["BasePart.Touched", "DataModel.BindToClose", "Humanoid.Died", "MarketplaceService.ProcessReceipt", "RemoteEvent.OnServerEvent", "RemoteFunction.OnServerInvoke"]);
        let client = run_body("input", "client", r#"
        game:GetService("UserInputService").InputBegan:Connect(function(Input, Processed) print("input", typeof(Input), Input.ClassName, Processed) end)
        local Character = game:GetService("Players").LocalPlayer.CharacterAdded:Wait()
        print("character", Character:FindFirstChildOfClass("Humanoid") ~= nil)
        Character.Missing.Value = 1
        "#, &["--fire-handlers"]);
        let client_lines = super::tests::lines(&client);
        assert!(client_lines.iter().any(|line| line == "print input Instance InputObject false [coverage]"), "{client_lines:?}");
        assert!(client_lines.iter().any(|line| line == "print character true [coverage]"), "{client_lines:?}");
        // (the harness, waiting for the character when the frames ended, went on in the pass and failed there)
        assert!(client_lines.iter().any(|line| line.starts_with("error Missing is not a valid member of Model") && line.ends_with("[coverage]")), "{client_lines:?}");
    }

    /// A handler that the run's events already called is not called again, and one that never returns does not hold the run: a
    /// yielding one is left waiting, a busy one stops at the script timeout
    #[test]
    fn called_handlers_are_left_and_endless_ones_end_with_the_run() {
        let body = r#"
        local Event = Instance.new("BindableEvent")
        Event.Event:Connect(function() print("event") end)
        Event:Fire()
        local Part = Instance.new("Part")
        Part.Parent = workspace
        Part.Touched:Connect(function() while true do task.wait() end end)
        Part.TouchEnded:Connect(function() while true do end end)
        "#;
        let summary = run_body("endless", "server", body, &["--fire-handlers", "--script-timeout", "0.5"]);
        let lines = lines(&summary);
        assert_eq!(lines.iter().filter(|line| line.starts_with("print event")).count(), 1, "{lines:?}");
        assert_eq!(listed(&summary, "ran"), ["BindableEvent.Event"]);
        assert!(lines.iter().any(|line| line.contains("timeout") && line.ends_with("[coverage]")), "{lines:?}");
    }
}
