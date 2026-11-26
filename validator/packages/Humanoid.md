# Package: Humanoid

File: `src/lua/validator/Humanoid.luau`. Specs: `validator/specs/Humanoid/`. Read `validator/HANDOFF.md` first.

Most-used area in the data (~6,100 rows). Unemulated in **both** contexts today (ree's own `src/serve/mod.rs` test expects `Humanoid.TakeDamage` to be missing, so update that test's expectation if your change makes it fail, and say so in the report).

## Members, in priority order

| member | must do |
|---|---|
| `TakeDamage(amount)` | lowers Health by amount, clamped at 0, **no effect if a ForceField is a child of the Humanoid's parent (character)**; Health reaching 0 fires `Died` and sets state Dead |
| `GetState()` | returns the current `Enum.HumanoidStateType` (start: Running if parented into a character in workspace, else None/Physics as Roblox does) |
| `ChangeState(state)` | sets state, fires `StateChanged(old, new)`; respects `SetStateEnabled` (disabled → no change); Dead → Health untouched but `Died` fires |
| `SetStateEnabled` / `GetStateEnabled` | check whether ree already has them; complete if not |
| `MoveTo(location, part?)` | sets `WalkToPoint`/`WalkToPart`; fires `MoveToFinished(reached)`. No physics needed: finish with `true` after distance / WalkSpeed seconds of game time if the character has a root part, `false` after 8 s timeout as Roblox does |
| `Move(direction, relativeToCamera?)` | sets `MoveDirection` (unit or zero) |
| `GetMoveVelocity()` | `MoveDirection * WalkSpeed` |
| `EquipTool(tool)` / `UnequipTools()` | parent Tool to character / to Backpack (player's), fire `Tool.Equipped`/`Unequipped` |
| `GetLimb(part)`, `GetBodyPartR15(part)` | map part names to `Enum.Limb` / `Enum.BodyPartR15`, `Unknown` otherwise |
| `AddAccessory(acc)`, `RemoveAccessories()`, `GetAccessories()` | parent to character, weld via matching attachments if present |
| `GetAppliedDescription()`, `ApplyDescriptionAsync(desc)`, `ApplyDescriptionResetAsync` | keep the last applied HumanoidDescription; Apply clones it in; errors if called on client for a non-local character as Roblox does |
| `BuildRigFromAttachments`, `ReplaceBodyPartR15`, `PlayEmoteAsync` | plausible no-crash behaviour, return types right (`PlayEmoteAsync` → false when the emote isn't in the description, Roblox's error for bad name) |

## Misuse cases to spec (Roblox errors)

- `TakeDamage("ten")` → cast error; `ChangeState(5)` → enum cast error.
- `EquipTool(part)` (not a Tool) → Roblox's error.
- `MoveTo(nil)` → argument missing error.
