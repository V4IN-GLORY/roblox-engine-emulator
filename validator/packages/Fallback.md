# Brief: what methods return (tier 3 fallback)

You are working in ree (roblox-engine-emulator), a Rust emulation of the Roblox engine that runs a game's Luau offline.
It is being turned into a code validator: a Luau snippet passes only if it would run without errors in Roblox. Read
`AGENTS.md` (repo rules) and `validator/HANDOFF.md` ("How a method behaves") first. Branch `validator`, don't commit or
push: leave the changes in the working tree and report. **Starts after the ArgChecks brief has landed**: arguments are
already checked by the time your code runs.

## The problem

A method ree doesn't emulate returns nothing, so valid code that uses the result errors in ree but not in Roblox:

```lua
local description = Players:GetHumanoidDescriptionFromUserId(1)
description.HeadColor = Color3.new(1, 0, 0) -- roblox: fine. ree: attempt to index nil
```

Measured in a Roblox 0.748 playtest, calling each method with valid sample args (`cv` lines in
`validator/probe/expected/surface_{server,client}.txt`), ~600 lines per context differ:

| Roblox | ree | lines (server) | e.g. |
|---|---|---|---|
| returns a value | returns nothing | 533 | `AdService.CreateAdRewardFromDevProductId` → `AdReward`; `AnalyticsService.GetPlayerSegmentsAsync` → `table` |
| errors (the method's own check) | returns nothing | 530 (both contexts) | `AccessoryDescription.GetAppliedInstance` → `AccessoryDescription is not parented to a HumanoidDescription` |
| returns nil | returns nothing | 30 | `BasePart.GetRootPart`, `Animator.GetTrackByAnimationId` |
| yields | returns at once | 9 | `MarketplaceService.PlayerOwnsAssetAsync`, `MessagingService.PublishAsync` |

`ok -` means no return values, `ok nil` means one nil, and `Instance:X` means an instance of class X.

## The job

1. **Typed defaults, one mechanism.** Replace `unimplemented_function` (`src/lua/instance.rs` ~204) so an unemulated
   method returns a value of its reflected return type (`MethodInfo.returns`, `src/reflection/members.rs`). That's a
   fresh instance of the class, `""`, `0`, `false`, `{}`, the datatype's default, or the enum's first item. Where the
   type is optional (`X?`) and the capture says `ok nil`, return nil. Where a method yields in Roblox (the `Async`
   ones, the capture's `yield`), yield one frame first. It still reports itself: change the Output line from `missing`
   to a new kind, `stubbed`, and make `validator/validate.py` list them under `"stubbed"` and count the run as ok.
2. **Inherited behaviours.** Some subclasses don't get their base class's emulated methods. On a server run,
   `CornerWedgePart` reports 27 BasePart methods as missing (`GetConnectedParts`, `CanCollideWith`, `GetJoints`, ...)
   that ree has for `Part`. Find why behaviour lookup misses them and fix the lookup, not the class list. Then check
   every other class for the same miss: compare `missing` lines per class against their siblings.
3. **Not yours:** "Roblox errors / ree returns nothing" lines where the error is the method's own state check (not
   parented, wrong context, not published). Those belong to behaviour packages. Count them by class in the report so
   they can be handed out.

## Constraints

- Data-driven only: no per-method return tables. The reflection data says the type, and the capture says which ones
  return nil or yield. If the capture disagrees with the reflected type, follow the capture and say where.
- No allocation on hot paths. A default instance is made per call, as Roblox does; a datatype default is built once.
- Script-visible output changes go in `docs/engine.md` with the capture cited (`Roblox Studio 0.748.0.7481526,
  validator/probe/expected`).

## Verify

```sh
cargo build --release --locked --bin ree
python validator/probe/surface_diff.py                  # "M cv" must drop; no other kind may rise
python validator/probe/surface_diff.py --list "M cv"
python validator/validate.py <a snippet using GetHumanoidDescriptionFromUserId> --context server   # ok true, stubbed lists it
cargo test --release
node tools/parity/run.mjs && node tools/parity/run.mjs --server
```

Baseline: server `M cv 621`, client `M cv 609`. Write your own baseline after ArgChecks lands. Add tests in `src/tests.rs`
that fail without the change: an instance return, a datatype return, a nil-returning optional, a yielding Async method,
and a subclass that now gets its base class's behaviour.

## Report

```
BRIEF: Fallback
DONE: <typed defaults, stubbed output kind, inherited behaviour fix (root cause in one line)>
SURFACE: server cv <before>-><after>; client same; other kinds unchanged? <yes/no>
FOR BEHAVIOUR PACKAGES: <classes with "Roblox errors / ree ok" lines, counts>
TESTS: cargo test <pass/fail>, parity <pass/fail>
BLOCKED: <none | what>
```
