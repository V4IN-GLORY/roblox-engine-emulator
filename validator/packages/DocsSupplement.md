# Brief: classes and member rules the API dump leaves out

You are working in ree (roblox-engine-emulator), a Rust emulation of the Roblox engine that runs a game's Luau offline.
It is being turned into a code validator for a training dataset: a row's Luau passes only if it would run without errors
in a live Roblox game. Read `AGENTS.md` and `validator/HANDOFF.md` first. Don't commit or push. Leave the changes in the
working tree and report.

## The problem

ree's API data, `data/reflection.json`, is Studio 0.748's ReflectionService output (`tools/dump-reflection.luau`). It
leaves things out that game scripts use:

1. **Whole classes.** 46 documented classes are missing, among them **`Player`**, plus `NetworkClient`,
   `NetworkServer`, the settings classes (`UserGameSettings`, `GameSettings`, `PhysicsSettings`, `RenderSettings`,
   `DebugSettings`, `NetworkSettings`, `LuaSettings`, `TaskScheduler`, ...) and the plugin and Studio classes. ree falls
   back to an older database (`rbx_reflection_database`) for these, which lacks recent members:
   ```
   roblox: M Player.IsFriendsWithAsync r function
   ree:    M Player.IsFriendsWithAsync r err IsFriendsWithAsync is not a valid member of Player "Player"
   ```
   About 40 Player members are affected: `User`, `AgeChecked`, `HasRobloxSubscription`, `GetFriendsOnlineAsync`,
   `IsFriendsWithAsync`, `GetCameraState`, `LoadCharacterWithHumanoidDescriptionAsync`, ...
2. **Write permissions.** About 60 property writes Roblox refuses for lack of a capability (`PluginOrOpenCloud`,
   `Plugin`, `RobloxEngine`, `RobloxScript`, `NotAccessible`, `LocalUser`, `WritePlayer`) aren't encoded:
   `python validator/probe/surface_diff.py --list "M w"`.

The creator docs (github.com/Roblox/creator-docs, `content/en-us/reference/engine/classes/*.yaml`, CC-BY-4.0) have all of
it: every class with its members, parameter and return types, defaults, and each member's `security` (`read` / `write`
for properties) and `capabilities`. `tools/optional-parameters.mjs` + `data/optional-parameters.json` already do the same
for optional parameters. Read them, follow the same pattern, and extend that tool rather than writing a second parser.

## The job

1. **Generator:** extend the docs tool (rename it if a broader name fits, e.g. `tools/docs-supplement.mjs`, and update
   every reference) so it also writes the classes that `data/reflection.json` lacks, in the dump's own format (`classes`
   entries: name, superclass, properties with `type {script, engine, enum, instance}`, methods with parameters / returns,
   events, callbacks, permits). Then `src/reflection.rs` merges them exactly as if the dump had them. Map the docs' type
   names onto the dump's: look at how a class that's in both (e.g. `Players`, `Humanoid`) is written in each, and derive
   the mapping from that. Don't guess it. Only add classes and members the docs list as usable by a game script
   (`security` `None` and not `NotScriptable`, as `validator/probe/make_surface_spec.py` decides). Plugin and Studio
   classes stay out unless they're needed for a class's superclass chain.
2. **Write permissions:** from the docs' property `security.write` and `capabilities`, produce the permission the dump
   would have. Measure the rule against the capture's `M w` lines before encoding it (which security value gives which
   `lacking capability X` text). Then make the property write path raise it: find where `permits` is read for
   properties today (`src/reflection/members.rs`, `CAPABILITY_ONLY` in `src/reflection.rs`) and feed it the merged data.
   One rule, no per-property list.
3. Data file: one generated file under `data/` with a header (docs commit, STUDIO_VERSION, license). `--check` mode as
   the existing tool has.

## Constraints

- Data-driven only. No hand-written member lists.
- The existing dump wins wherever it has a class or member. The docs only fill gaps.
- Hot paths unchanged: this is load-time data.
- Output must not change by accident: where the old `rbx_reflection_database` answer and the docs disagree, follow the
  capture, and list each such change in the report.
- Don't touch `src/lua/arg_checks.rs`, `src/lua/fallback.rs` or `src/lua/validator/*` (other agents). Methods you add
  get argument checks and typed fallback answers automatically through them. Confirm that with a test.
- Don't run `cargo fmt`. Never write local user paths, machine names or emails anywhere.

## Verify

```sh
export RUSTFLAGS="-C target-feature=+crt-static" CXXFLAGS_x86_64_pc_windows_msvc="-DMI_WIN_INIT_USE_FLS=1"
export PATH="$HOME/.rokit/bin:$PATH"
cargo build --release --locked --bin ree
python validator/probe/surface_diff.py          # baseline server: c0 51, cv 312, cw 72, r 76, w 88, C 16, R 1; client: c0 51, cv 294, cw 75, r 71, w 86, C 18, R 1
python validator/probe/surface_diff.py --list "M r" --grep "Player."
cargo test --release
node tools/parity/run.mjs && node tools/parity/run.mjs --server
```

`M r` and `M w` must drop a lot. `cv` / `c0` / `cw` may rise for new Player methods, since they become callable and get
compared (say how many). Nothing else may rise. Add tests in `src/tests.rs` that fail without the change: a Player
member from the docs (`player.User`, `player:IsFriendsWithAsync(1)`), a capability-refused write, and a class in both
sources keeping the dump's data.

## Report

```
BRIEF: DocsSupplement
DONE: <classes added (count, names that matter), members, write-permission rule>
SURFACE: server r/w/cv/c0/cw before->after; client same; anything else rise? <yes/no>
CHANGED ANSWERS: <where the old database and the docs disagreed, and what the capture said>
TESTS: cargo test <pass/fail>, parity <pass/fail>
BLOCKED: <none | what>
```
