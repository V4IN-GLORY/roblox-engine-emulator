# Brief: run the code a snippet only connects (coverage) + static type warnings

You are working in ree (roblox-engine-emulator), a Rust emulation of the Roblox engine that runs a game's Luau offline.
It is being turned into a code validator for a training dataset: `python validator/validate.py row.luau --context
server|client` runs a row's Luau for 1 second of game time and returns `{"ok", "errors", "unemulated", "stubbed"}`. Read
`AGENTS.md` and `validator/HANDOFF.md` first. Don't commit or push. Leave the changes in the working tree and report.

## The problem

Most dataset rows connect handlers and return: `Players.PlayerAdded:Connect(...)`, `part.Touched:Connect(...)`,
`tool.Activated:Connect(...)`, `remote.OnServerEvent:Connect(...)`, `UserInputService.InputBegan:Connect(...)`. In a
1-second offline run nobody joins, touches or clicks, so the handler body **never runs** and a bug inside it passes:

```lua
game.Players.PlayerAdded:Connect(function(player)
	player.leaderstats.Coins.Value += 1   -- leaderstats doesn't exist: errors in Roblox the first time anyone joins
end)
```

Today that row gives `"ok": true`.

## The job

1. **Fire every connected handler once** after the row's own code has run (and its threads have settled), each with
   arguments of the event's reflected parameter types. The event's `parameters` are in the reflection data, so build
   the arguments from those types the way `src/lua/fallback.rs` builds return values (reuse it, don't write a second
   one). Use a sensible real value where the type is an Instance: a `Player` for `PlayerAdded`, a `Part` in Workspace
   for `Touched`, an `InputObject` for input events.
   - Errors raised inside a fired handler count as errors of the run. Mark them as coming from the coverage pass
     (e.g. Output kind `error` with a `coverage` flag, or a separate list in validate.py), so a reviewer can tell
     "errors when PlayerAdded fires" from "errors at load".
   - Only events whose handlers the row's code connected (`Connect`, `Once`, `ConnectParallel`), plus callbacks it set
     (`OnServerInvoke`, `OnClientInvoke`, `ProcessReceipt`, `BindToClose` functions, `BindAction` handlers,
     `RenderStepped` / `Heartbeat` / `Stepped` once). Never engine-internal connections.
   - A fired handler that yields forever must not hang the run. Bound it with the existing script timeout.
   - Where a richer real path exists, prefer it. E.g. ree can really join a player on a server (`Context` / loopback,
     see docs/engine.md and how the server tests add players), and that runs `PlayerAdded` and `CharacterAdded` with
     real objects. Use the real path where it exists and the typed fallback elsewhere. Say which in the report.
   - Make it a `ree run` option (e.g. `--fire-handlers`), on in `validate.py`, off by default so other users' output
     doesn't change (docs/cli.md).
2. **Static type warnings:** run `luau-lsp analyze` (in `~/.rokit/bin`, with Roblox definitions; see how `luau-lsp`
   finds its definitions file, and download nothing new at run time) on the row in `validate.py`. Put the diagnostics in
   a new `"warnings"` list that does **not** change `ok`. Strip the temp file path from messages.

## Constraints

- No change to normal `ree run` output unless the new flag is passed (rur's golden tests record it).
- Don't touch `src/lua/arg_checks.rs`, `src/lua/validator/*` (other agents) or `data/` (another agent).
- Don't run `cargo fmt`. Never write local user paths, machine names or emails anywhere (including the warnings text).

## Verify

```sh
export RUSTFLAGS="-C target-feature=+crt-static" CXXFLAGS_x86_64_pc_windows_msvc="-DMI_WIN_INIT_USE_FLS=1"
export PATH="$HOME/.rokit/bin:$PATH"
cargo build --release --locked --bin ree
cargo test --release
node tools/parity/run.mjs && node tools/parity/run.mjs --server
python validator/probe/surface_diff.py     # totals must not change (the probe doesn't use the flag)
```

Add `validator/specs/Coverage/` with specs: the leaderstats row above `.bad`, the same with `leaderstats` created first
`.ok`, a `Touched` handler indexing `hit.Parent.Humanoid` without a check `.ok` (Roblox code commonly does this and the
fired Part has no Humanoid: decide what's right and say why), a `.client.` `InputBegan` handler, and an `OnServerEvent`
handler. Run with `python validator/specs/run.py Coverage`. Add Rust tests that fail without the change.

## Report

```
BRIEF: Coverage
DONE: <flag, which events and callbacks fire, real vs typed args, how errors are marked, warnings field>
SPECS: <n ok / n bad, all passing>
TESTS: cargo test <pass/fail>, parity <pass/fail>, surface totals unchanged <yes/no>
BLOCKED: <none | what>
```
