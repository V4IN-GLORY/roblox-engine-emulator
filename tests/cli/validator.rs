//! The options `validator/validate.py` runs with, through the built `ree`: `--luau-flag` (syntax the live client runs off,
//! which the module cache must not serve to a run without it) and `--stand-ins` (the place's missing children).

use std::{path::PathBuf, process::Command};

fn scratch(name: &str) -> PathBuf {
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
    let root = std::env::temp_dir().join(format!("ree-validator-{name}-{}-{nanos}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    root
}

/// `ree run` of `body` as a harness, in `root`'s own state: the summary
fn run(root: &PathBuf, body: &str, extra: &[&str]) -> serde_json::Value {
    let harness = root.join("Row.luau");
    std::fs::write(&harness, format!("return function()\n{body}\nend\n")).unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_ree"))
        .args(["run", "--harness"])
        .arg(&harness)
        .args(["--mode", "play", "--run-context", "server", "--seconds", "0.2"])
        .args(extra)
        .env("RUR_STATE_DIR", root.join("state"))
        .output()
        .unwrap();
    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(&stdout[stdout.find('{').unwrap()..]).unwrap()
}

fn lines(summary: &serde_json::Value) -> Vec<String> {
    summary["output"].as_array().unwrap().iter().map(|line| format!("{} {}", line["kind"].as_str().unwrap(), line["message"].as_str().unwrap())).collect()
}

/// `if local` compiles only with its flag on, and a source compiled with it is compiled again without it (the module cache's
/// key follows the flag), not served from the cache
#[test]
fn a_luau_flag_turns_on_its_syntax_for_that_run_only() {
    let root = scratch("luau-flag");
    let body = "local function f() return 5 end\nif local x = f() then print('if-local', x) end";
    let flags = ["--luau-flag", "LuauExperimentalIfLocalSyntax=true"];
    assert_eq!(lines(&run(&root, body, &flags)), ["print if-local 5"]);
    let plain = lines(&run(&root, body, &[]));
    assert!(plain.len() == 1 && plain[0].contains("Expected identifier when parsing expression, got 'local'"), "{plain:?}");
    assert_eq!(lines(&run(&root, body, &flags)), ["print if-local 5"]);
    let _ = std::fs::remove_dir_all(&root);
}

/// A child the place would hold is stood in for, with a class its name says, and the code goes on; a member's name, a typo of
/// one and a name under a service that holds no instances of the place's are not
#[test]
fn stand_ins_hold_the_places_children_and_not_members() {
    let root = scratch("stand-ins");
    let body = r#"
        local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
        print(Remotes:WaitForChild("BuyItem").ClassName, Remotes.GetPrice.ClassName, workspace.Map.Spawn.ClassName)
        print(pcall(function() return workspace.Map.Positon end))
        print(pcall(function() return game:GetService("UserInputService").MouseDelta end))"#;
    let summary = run(&root, body, &["--stand-ins"]);
    assert_eq!(
        lines(&summary),
        [
            "print RemoteEvent RemoteFunction Part",
            "print false Positon is not a valid member of Model \"Workspace.Map\"",
            "print false MouseDelta is not a valid member of UserInputService \"UserInputService\"",
        ]
    );
    let mut made: Vec<&str> = summary["standIns"].as_array().unwrap().iter().map(|name| name.as_str().unwrap()).collect();
    made.sort_unstable();
    assert_eq!(made, ["ReplicatedStorage.Remotes", "ReplicatedStorage.Remotes.BuyItem", "ReplicatedStorage.Remotes.GetPrice", "Workspace.Map", "Workspace.Map.Spawn"]);
    let plain = lines(&run(&root, body, &[]));
    assert!(plain.iter().any(|line| line.starts_with("error")) || plain.is_empty(), "{plain:?}");
    let _ = std::fs::remove_dir_all(&root);
}
