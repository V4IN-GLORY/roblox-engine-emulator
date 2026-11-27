//! `--stand-ins` ([`crate::Options::stand_ins`]): a validator's run has an empty place, so the children a script expects the place
//! to hold (`workspace.Map`, `ReplicatedStorage.Remotes.Buy`, `script.Parent.Handle`) are missing, and the script stops at the
//! first one (an index raises, a WaitForChild waits for good) before the rest of it is checked. With the option, a lookup by
//! name that finds no child makes a stand-in of that name and returns it, with a class guessed from its name and its parent's
//! ([`class_for`]): the script goes on, and an error a wrong guess causes names the stand-in, which a validator reads as the
//! place's (the summary's `standIns` lists them).
//!
//! A name a script means as a member is never stood in for: one that is a member of any class (`script.Parent.Touched` on a
//! folder is a wrong parent, not a missing child), a typo of any member (`part.Positon`), and any name under a
//! service that holds no instances of the place's (UserInputService), the DataModel (its services: services/mod.rs
//! PLACE_SERVICES) or Players and a Player (who joins and what a game script makes under them are the run's).

use std::sync::OnceLock;

use rustc_hash::FxHashSet;

use crate::{Engine, InstanceId};

/// Services that hold the place's own instances: a name under one may be a child the place has
const CONTAINER_SERVICES: &[&str] = &[
    "Workspace", "ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "ServerScriptService", "StarterGui", "StarterPack",
    "StarterPlayer", "Lighting", "SoundService", "Teams", "Chat", "TextChatService", "MaterialService",
];

/// Every member name of every class, lower-cased
fn member_names(engine: &Engine) -> &'static FxHashSet<String> {
    static NAMES: OnceLock<FxHashSet<String>> = OnceLock::new();
    NAMES.get_or_init(|| {
        let reflection = &engine.reflection;
        reflection.all_classes().flat_map(|class| reflection.members(class.id)).map(|member| reflection.name(member.name()).to_lowercase()).collect()
    })
}

/// One edit apart, two for a name over six letters (a typo of it)
fn near(word: &str, other: &str) -> bool {
    let allowed = if other.len() > 6 { 2 } else { 1 };
    if word.len().abs_diff(other.len()) > allowed {
        return false;
    }
    let other: Vec<char> = other.chars().collect();
    let mut previous: Vec<usize> = (0..=other.len()).collect();
    for (row, letter) in word.chars().enumerate() {
        let mut current = vec![row + 1];
        for (column, wanted) in other.iter().enumerate() {
            current.push((previous[column + 1] + 1).min(current[column] + 1).min(previous[column] + usize::from(letter != *wanted)));
        }
        previous = current;
    }
    previous[other.len()] <= allowed
}

/// The class of a stand-in named `name` under `parent`: a class of that name; else what the name says (a remote, a GUI
/// element, a value, a module, a model); else what the parent holds (a GUI's children are frames, a model's or the
/// Workspace's parts, anything else's folders)
fn class_for(engine: &Engine, parent: InstanceId, name: &str) -> Option<crate::ClassId> {
    let reflection = &engine.reflection;
    if let Some(class) = reflection.class_by_name(name).filter(|class| class.creatable && !class.service) {
        return Some(class.id);
    }
    reflection.class_id(guessed_class(engine, parent, name))
}

fn guessed_class(engine: &Engine, parent: InstanceId, name: &str) -> &'static str {
    let reflection = &engine.reflection;
    let state = engine.state.borrow();
    let parent_class = state.dom.class_of(parent);
    let parent_name = state.dom.at(parent).name.to_string().to_lowercase();
    let lower = name.to_lowercase();
    let has = |words: &[&str]| words.iter().any(|word| lower.contains(word));
    let ends = |words: &[&str]| words.iter().any(|word| lower.ends_with(word));
    let starts = |words: &[&str]| words.iter().any(|word| lower.starts_with(word));
    // (a remote named for what it asks, `GetPrice`, `RequestTrade`, answers: a RemoteFunction)
    let remote_parent = parent_name.contains("remote") || parent_name.contains("event") || parent_name.contains("network");
    if has(&["remotefunction", "function"]) || ends(&["func"]) || (remote_parent && starts(&["get", "request", "fetch", "check", "can", "try"])) {
        return "RemoteFunction";
    }
    if has(&["bindable"]) {
        return "BindableEvent";
    }
    if has(&["remote", "event"]) || parent_name.contains("remote") || parent_name.contains("event") {
        return "RemoteEvent";
    }
    if parent_name == "leaderstats" || ends(&["coins", "cash", "money", "points", "gold", "gems", "level", "xp", "kills", "wins", "score"]) {
        return "IntValue";
    }
    if ends(&["value"]) {
        return "NumberValue";
    }
    if ends(&["module", "config", "settings", "util", "utils", "service", "manager", "controller", "handler", "lib"]) {
        return "ModuleScript";
    }
    if ends(&["gui"]) {
        return "ScreenGui";
    }
    if ends(&["button"]) {
        return "TextButton";
    }
    if ends(&["label", "text", "title"]) {
        return "TextLabel";
    }
    if ends(&["box", "input"]) {
        return "TextBox";
    }
    if ends(&["image", "icon"]) {
        return "ImageLabel";
    }
    if ends(&["frame", "panel", "container", "menu", "bar", "list", "window"]) {
        return "Frame";
    }
    if ends(&["sound", "music", "sfx"]) {
        return "Sound";
    }
    if ends(&["animation", "anim"]) {
        return "Animation";
    }
    if has(&["model", "map", "npc", "rig", "tycoon", "building", "house", "dummy"]) {
        return "Model";
    }
    let is = |class: &str| reflection.is_a(parent_class, class);
    if is("GuiBase2d") || is("PlayerGui") || is("StarterGui") {
        return "Frame";
    }
    if is("Model") || is("Workspace") || is("BasePart") {
        return "Part";
    }
    "Folder"
}

/// FindFirstChild's stand-in: only directly under a service that holds the place's instances or under a stand-in (the place's
/// content, `ReplicatedStorage:FindFirstChild("BuyItem")` a script uses unchecked), never where finding nothing is an answer a
/// script asks for (`hit.Parent:FindFirstChild("Humanoid")`), and never for a recursive search
pub(crate) fn found_stand_in(engine: &Engine, parent: InstanceId, name: &[u8], recursive: bool) -> Option<InstanceId> {
    if !engine.options.stand_ins || recursive {
        return None;
    }
    let held = {
        let state = engine.state.borrow();
        let info = engine.reflection.class(state.dom.class_of(parent));
        (info.service && CONTAINER_SERVICES.contains(&&*info.name)) || state.output.stand_ins.contains(&state.dom.full_name(&engine.reflection, parent))
    };
    if held { stand_in(engine, parent, name) } else { None }
}

/// A stand-in for the child `name` of `parent` that a lookup missed, made and parented now; None where the option is off or
/// the name is no child's (module doc)
pub(crate) fn stand_in(engine: &Engine, parent: InstanceId, name: &[u8]) -> Option<InstanceId> {
    if !engine.options.stand_ins {
        return None;
    }
    let name = std::str::from_utf8(name).ok().filter(|name| !name.is_empty() && name.len() <= 100)?;
    let reflection = &engine.reflection;
    let parent_class = engine.state.borrow().dom.class_of(parent);
    let parent_info = reflection.class(parent_class);
    if parent_info.service && !CONTAINER_SERVICES.contains(&&*parent_info.name) {
        return None;
    }
    if ["DataModel", "Players", "Player"].iter().any(|class| reflection.is_a(parent_class, class)) {
        return None;
    }
    let lower = name.to_lowercase();
    if member_names(engine).contains(&lower) {
        return None;
    }
    // (any class's: the parent may be a stand-in whose class was guessed, `workspace.Map.Positon`)
    if lower.len() >= 4 && member_names(engine).iter().any(|member| near(&lower, member)) {
        return None;
    }
    let class = class_for(engine, parent, name)?;
    // (a module's stand-in would answer `{}`, and the script's use of what it expects there would fail as the script's own:
    // `require` of a missing module stays the place's error)
    if reflection.class(class).name.as_ref() == "ModuleScript" {
        return None;
    }
    let id = {
        let mut state = engine.state.borrow_mut();
        crate::instance::create_named(&mut state, reflection, class, name)
    };
    super::instance::set_parent(engine, id, Some(parent)).ok()?;
    let full_name = engine.state.borrow().dom.full_name(reflection, id);
    engine.state.borrow_mut().output.stand_ins.push(full_name);
    Some(id)
}
