# ree validator: handoff

**Goal:** make ree (Roblox engine emulator, this repo) able to run any Roblox Luau snippet and say whether it works. It's used to validate LLM training data: code passes only if it runs without errors. When ree hits an API it doesn't emulate, it prints `missing X is not emulated` and returns nil, so the run can't be trusted. Each package below removes one area of those gaps.

We don't need pixel-perfect Roblox. We need **what a script can see** to match Roblox: right return types, right events firing, and **Roblox's own error messages for misuse**. Never silently return nil.

## Setup

- Branch: `validator` (local only, don't push). Upstream: Anime-Vanguards/roblox-engine-emulator v0.13.0, GPL-3.0.
- Build (Windows, ~2 min after the first build):
  ```sh
  export RUSTFLAGS="-C target-feature=+crt-static" CXXFLAGS_x86_64_pc_windows_msvc="-DMI_WIN_INIT_USE_FLS=1"
  cargo build --release --locked --bin ree
  ```
- Run one file: `python validator/validate.py some.luau --context server|client` → `{"ok", "errors", "unemulated", "stubbed", "coverage", "warnings"}`. It runs with `--fire-handlers` (every handler the row connected gets called once after the run; errors there carry `coverage`) and adds luau-lsp diagnostics as `warnings`, which never change `ok`.
- See what's still missing: `python validator/probe/gaps.py --classes Humanoid,ContextActionService`. The probe has blind spots: on a server it lists no Humanoid gaps, yet `TakeDamage` is unemulated there. Your specs are the real check.
- `validator/specs/Avatar/TakeDamage.{ok,bad}.luau` are worked examples of the spec format, and both fail today on purpose.
- Repo's own guide: `AGENTS.md`, `docs/engine.md`, and `docs/cli.md` for run contexts. Read the section for the area you touch.

## Run contexts (read this first)

ree's **default context is client**. Server-only services (DataStore, MemoryStore, MessagingService, server side of remotes) only exist with `--mode play --run-context server`. `validate.py` always passes the context explicitly. Test every package in **both** contexts.

## The surface diff (the main measure)

`validator/probe/expected/surface_{server,client}.txt` is what real Roblox (Studio 0.748 playtest, game script identity)
printed for SurfaceProbe: every documented in-game class reached, every member read, every property written with a
bad value, every method called with no args (`c0`), with a wrong-typed arg (`cw`) and with valid sample args (`cv`,
with the types it returned), and classes only a method hands out probed on what those calls returned (`R`). `python validator/probe/surface_diff.py` runs the
same probe in ree and counts the lines that differ, by kind (`--list <kind>` shows them). Every change has to bring a
count down without raising another.

- Spec from the creator docs: `make_surface_spec.py --docs <creator-docs>/content/en-us/reference/engine` (only
  documented classes; members a normal script may use).
- Re-capture after a Roblox update: `lune run validator/probe/surface.luau pack <probe.rbxm>`, import it into a playtest
  server's ReplicatedStorage (robloxstudio MCP `import_rbxm`), run it on server and client, export
  `ServerStorage.SurfaceResults` and `lune run validator/probe/surface.luau unpack <results.rbxm> <dir>`.
- `expected/unpublished.txt`: errors the capture place gives only because it is unpublished, left out of the diff.
- `expected/crashes.txt`: valid calls that crash Studio or end the playtest, skipped in both engines. `python
  validator/probe/studio.py open` launches Studio on a throwaway place; `studio.py crash` names the call that was running
  when Studio died (set `_G.SurfaceProbeLog = true` before the probe runs, so each call is logged first).

## How a method behaves (the three tiers)

Every call first checks its arguments like Roblox (ArgChecks). After that:

| tier | when | what ree does | example |
|---|---|---|---|
| 1 real | local and cheap | does the real work, because later code can depend on the exact result | `EncodingService:Base64Encode`, `HttpService:JSONEncode`, CFrame math |
| 2 faked | needs Roblox's servers | runs the method's own checks, returns a fake answer with the right shape, fires the follow-up events | `GetProductInfo` → table with `Name`, `PriceInRobux`, ...; `PromptProductPurchase` → `PromptProductPurchaseFinished` |
| 3 fallback | everything else | returns a value of the type Roblox returns (the capture's `cv` line), listed under `stubbed`, counted as ok | `GetHumanoidDescriptionFromUserId` → a fresh `HumanoidDescription` |

## Plan

| # | step | who | state |
|---|---|---|---|
| 0 | Measure: surface probe, server + client captures, crash list, valid-call return types (`cv`) | orchestrator | done |
| 1 | [ArgChecks](packages/ArgChecks.md), [ClassReach](packages/ClassReach.md), [PropertyAccess](packages/PropertyAccess.md), [Fallback](packages/Fallback.md) (tier 3), API dump 0.748, optional parameters from the creator docs | agents + orchestrator | done |
| 2 | [DocsSupplement](packages/DocsSupplement.md): classes the dump leaves out (`Player`, settings, network) and property write permissions, from the creator docs | Gemini | |
| 2 | [Behaviours](packages/Behaviours.md) (tier 2): Commerce, Avatar, World, Interface, Core, one agent each | Gemini | |
| 2 | [Coverage](packages/Coverage.md): fire every connected handler once with typed args; luau-lsp `warnings` | Opus | |
| 3 | Dataset scale: many rows per ree process (`--batch`), timing per row | orchestrator | after 2 |
| 4 | Upstream PRs to REE: one change per PR (AGENTS.md), each with tests, `docs/engine.md`, the capture as measurement, AI disclosure. Only when the user says so | orchestrator | user's go |

Done for the whole thing: `surface_diff.py` shows only lines left on purpose (each listed with why), the behaviour
packages' specs pass, `cargo test --release` and the parity probes pass.

## Packages: one agent each

Brief for all five: [packages/Behaviours.md](packages/Behaviours.md) (which classes each owns). File:
`src/lua/validator/<Package>.luau`; specs: `validator/specs/<Package>/`. Packages: Commerce, Avatar, World, Interface,
Core.

### The contract (frozen, don't change it, report BLOCKED instead)

- Each file is loaded once per run, after ree's stock `services.luau` (and `server.luau` on a server). It gets `local R = ...`, the same engine primitives table those files use:
  - `R.Method(class, name, fn)` registers or replaces a method.
  - `R.Getter`, `R.Create`, `R.RawSet`, `R.RawGet` and `R.Children` work as in `services.luau`.
  - `R.Missing(class, member)` reports a gap you deliberately leave.
  - `R.IsServer` is a boolean: check it yourself for context-only behaviour.
- The hook is in `src/lua/stubs.rs` (`VALIDATOR` list + the loop after the server chunk). Chunk names are `=ree.validator.<Name>`, so error traces point at the user's script line, not yours.
- **Only edit your own file** plus new spec files under `validator/specs/<Package>/`. If you need Rust changes or a change to someone else's file, stop and write `BLOCKED: <what and why>` in your report. Don't do it yourself.
- Match `services.luau`'s style: `--!nocheck`, tabs, PascalCase locals as in that file.

## How to implement a member

1. Look up the real behaviour on create.roblox.com/docs/reference/engine. You need parameters, return types, events fired, yields or not, and **the exact error text** for bad args and wrong context.
2. Keep state in Luau tables (weak-keyed by instance where it's per instance, like `services.luau`'s `Extra`).
3. Things that need a real Roblox backend (purchases, badges, ownership, filtering) return a **deterministic plausible answer** and fire the follow-up events Roblox fires. Examples: `PromptProductPurchase` → `PromptProductPurchaseFinished(player, id, false)` a frame later; `FilterStringAsync` → a TextFilterResult whose getters return the input.
4. Wrong-context calls raise Roblox's error. That's handled in ContextGuards, not in your package.

```lua
-- wrong: silent nil, the validator can't tell good code from bad
R.Method("Humanoid", "GetState", function(self) end)

-- right: real answer, and Roblox's error on bad input
R.Method("Humanoid", "ChangeState", function(self, State)
	if typeof(State) ~= "EnumItem" or State.EnumType ~= Enum.HumanoidStateType then
		error("Unable to cast value to Enum", 0)
	end
	...
end)
```

## Definition of done (per package)

1. `python validator/probe/gaps.py --classes <your classes>` prints none of your members in the contexts Roblox allows them in.
2. `validator/specs/<Package>/` has a `*.luau` spec per member group (a harness body like validate.py runs). Each spec has:
   - a **correct-use** case that must give `"ok": true`;
   - a **misuse** case (bad arg, wrong type, wrong context) that must give `"ok": false` with Roblox's error text;
   - name them `<Thing>.ok.luau` / `<Thing>.bad.luau`.
3. `python validator/specs/run.py <Package>` passes: every `.ok` is ok and every `.bad` fails.
4. `cargo build --release --locked --bin ree` is clean, and the existing `cargo test --release` still passes for the tests touching your area (`cargo test --release <name>`).
5. Report back in this shape:
   ```
   PACKAGE: <name>
   DONE: <members implemented>
   LEFT MISSING ON PURPOSE: <members + why>
   SPECS: <n ok / n bad, all passing>
   BLOCKED: <none | what>
   ```

## Priority (rows in the training data that call each area)

| area | rows |
|---|---|
| Humanoid (TakeDamage, GetState, ChangeState, MoveTo, Move, EquipTool) | ~6,100 |
| ContextActionService.BindAction + StarterGui.SetCore / SetCoreGuiEnabled | ~1,200 |
| Marketplace / Badge / Chat filter | ~2,000 |
| Client calling server-only APIs (DataStore etc.) — must error like Roblox | ~17,000 rows touch DataStore |
| Pathfinding on the client | ~500 |
