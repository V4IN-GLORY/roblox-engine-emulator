# Brief: class reach, enums, datatypes, globals

You are working in ree (roblox-engine-emulator), a Rust emulation of the Roblox engine that runs a game's Luau offline.
It is being turned into a code validator: a Luau snippet passes only if it would run without errors in Roblox. Read
`AGENTS.md` (repo rules) and `validator/HANDOFF.md` first. Branch `validator`, don't commit or push: leave the changes in
the working tree and report. Runs alongside the ArgChecks brief: stay out of `src/lua/raw.rs` method dispatch and
`src/lua/instance.rs`.

## The problem

Measured in a Roblox 0.748 playtest (`validator/probe/expected/surface_{server,client}.txt`), these lines differ:

- **C lines (~55):** how a game script reaches each class.
  `C X svc ok|svc nil|svc err <msg>` is `game:GetService`, `C X new ok|new err <msg>` is `Instance.new`, and
  `C X none existing Y` means Roblox's session already holds an instance of it.
  ```
  roblox: C CacheableContentProvider svc nil
  ree:    C CacheableContentProvider svc ok
  roblox: C BubbleChatConfiguration none existing BubbleChatConfiguration
  ree:    C BubbleChatConfiguration none
  ```
  The first kind is the service list Roblox hides from game scripts. ree already has that list (`src/services/mod.rs`
  ~406, measured on 0.747), so extend it from the capture and update its measurement note. The second kind is instances
  a fresh Roblox place has by default: TextChatService's configuration children and similar. Find out which ones ree is
  missing and create them where ree builds the default DataModel.
- **E lines:** enum items Roblox has and ree lacks (`E present 3028` vs ree's 3025; `--list E` shows which).
- **V lines:** `User.fromId` / `User.fromString` (the `User` datatype, see `create.roblox.com/docs/reference/engine/datatypes/User`),
  and the `DebuggerManager` global function.

Leave `C` lines that only differ because Studio has something a live game doesn't. Say which ones in the report.

## Rules

- Every fix follows the capture. Script-visible changes cite it (`Roblox Studio 0.748.0.7481526,
  validator/probe/expected`) in a comment or in `docs/engine.md`.
- Enums: if the items come from `data/reflection.json`'s enums (0.747) and the missing ones are new in 0.748, don't
  hand-add them. List them for the dump bump.
- `vendor/` is generated, so never edit it. A datatype that would have to live in Lune's vendored datatypes goes through
  `patches/` + `node tools/vendor.mjs` (AGENTS.md "The VM is vendored"), or into `src/lua/` if that's the simpler home.
  Pick one and say why.
- Never add a per-name special case where a data-driven fix exists.

## Verify

```sh
cargo build --release --locked --bin ree
python validator/probe/surface_diff.py            # C, E, V counts must drop; no other kind may rise
python validator/probe/surface_diff.py --list C   # what's left
cargo test --release
node tools/parity/run.mjs && node tools/parity/run.mjs --server
```

Baseline: server `C 54`, `E 1`, `V 3`, client `C 53`, `E 1`, `V 3`. Add tests in `src/tests.rs` that fail without the change.

## Report

```
BRIEF: ClassReach
DONE: <services hidden, default instances added, enums, datatypes, globals>
SURFACE: server C/E/V <before>-><after>; client same; other kinds unchanged? <yes/no>
LEFT: <lines left on purpose (Studio-only, needs dump bump), with why>
TESTS: cargo test <pass/fail>, parity <pass/fail>
BLOCKED: <none | what>
```
