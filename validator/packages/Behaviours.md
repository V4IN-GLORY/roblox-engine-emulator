# Brief: behaviour packages (tier 2)

You are working in ree (roblox-engine-emulator), a Rust emulation of the Roblox engine that runs a game's Luau offline.
It is being turned into a code validator for a training dataset: each row's Luau runs in ree, and a row passes only if it
would run without errors in a live Roblox game. Bad rows get dropped or repaired, so ree must **error where Roblox errors
and not error where Roblox doesn't**. Methods don't need real behaviour, only Roblox's checks plus values close enough
that the code after the call runs the same.

Read `AGENTS.md` (repo rules) and `validator/HANDOFF.md` ("How a method behaves", "The contract") first. Don't commit or
push. Leave the changes in the working tree and report.

## What already works (don't redo it)

- **Argument checks** (`src/lua/arg_checks.rs`) run before every method, yours included: missing / nil arguments, casts
  (`Unable to cast string to int64`), capability errors. Your function only sees arguments that already passed.
- **Fallback** (`src/lua/fallback.rs`): a method no behaviour implements returns a fresh value of its reflected return
  type, `Async` ones a frame later, and is listed as `stubbed`. So a method that has no checks of its own and whose result
  is only used by type needs **nothing** from you.
- Property reads and writes, class reach and the API data are other briefs. Stay out of them.

## Your job

For each class you own (your section below), the lines where the capture and ree still differ are the work list:

```sh
python validator/probe/surface_diff.py --list "M cv" --grep "<Class>."   # also "M cw", "M c0"
```

```
roblox: M Actor.SendMessage cv err Actor:SendMessage may only be called on Actors attached to the DataModel.
ree:    M Actor.SendMessage cv ok -
```

`cv` calls the method with valid sample args, on a fresh unparented `Instance.new` instance or the service. `c0` calls it
with no args, and `cw` with a wrong-typed first arg. Every line falls into one of three kinds:

1. **The method's own check** (state, parenting, context, argument *values*): implement it with Roblox's exact text.
   Examples: `... is not parented to a HumanoidDescription`, `RegisterAdOpportunityAsync can only be called from the
   client.`, `Actor:SendMessage may only be called on Actors attached to the DataModel.`, `Local player is not available`.
   Generalise from the line. The rule is "raises when not in the DataModel", not "raises in the probe": a parented
   instance must pass.
2. **Only because the capture place is offline / unpublished / has no backend**: `Request failed`, `HTTP 403`,
   `Animation failed to load`, asset downloads, `You must publish this place`. A live game would succeed, so **don't
   copy the error**. Return a plausible success shaped like Roblox's real answer (the docs' return description: table
   keys, field types). Say in the report which lines you left differing for this reason.
3. **Return shape**: Roblox answers a value whose shape later code depends on (a table with `Name`, `PriceInRobux`, ...,
   a Pages object, a connection). Return that shape with deterministic plausible values, and fire the follow-up events
   Roblox fires (`PromptProductPurchase` → `PromptProductPurchaseFinished(player, id, false)` a frame later).

Then go past the probe: the capture only tries one valid call per method. For the methods in your classes that dataset
code uses most (your judgment; the docs' code samples are a good guide), add the misuse errors the docs describe:
wrong context (`R.IsServer`), invalid values (negative amounts, empty strings where the docs say non-empty), wrong state.
Take the exact text from the capture where it has it. Otherwise use the docs, and mark those in a short comment
`-- text: docs` so they can be measured later.

## How (the frozen contract)

- Only edit **your own file** `src/lua/validator/<Package>.luau` plus specs under `validator/specs/<Package>/`. It gets
  `local R = ...`: `R.Method(class, name, fn)`, `R.Getter`, `R.Create`, `R.RawSet`, `R.RawGet`, `R.Children`, as in
  `src/lua/services.luau` (read how it uses them), `R.Missing`, and `R.IsServer`.
- If a fix needs Rust or another file, stop and write it under `BLOCKED`. Don't do it yourself.
- `R.Method` replaces any existing behaviour. Before replacing a method ree already implements (in `services.luau`,
  `server.luau` or Rust), check what it does: keep its behaviour and add the check, or leave it alone.
- Match `services.luau`'s style: `--!nocheck`, tabs, PascalCase locals. Errors use `error(message, 0)`... check how
  `services.luau` raises so the error position matches Roblox's (no `ree.validator` line in the message).
- No per-instance global tables that leak: per-instance state goes in a weak-keyed table, as `services.luau`'s `Extra` does.

```lua
-- wrong: silently ok, a row calling this on an unparented Actor would pass
R.Method("Actor", "SendMessage", function(self, topic, ...) end)

-- right: Roblox's check, generalised, then the (stub) behaviour
R.Method("Actor", "SendMessage", function(self, topic, ...)
	if not self:IsDescendantOf(game) then
		error("Actor:SendMessage may only be called on Actors attached to the DataModel.", 0)
	end
end)
```

## Specs

`validator/specs/<Package>/<Thing>.ok.luau` / `.bad.luau` (add `.client.` for a client run). Each is a script body.
`python validator/specs/run.py <Package>` passes when every `.ok` gives `"ok": true` and every `.bad` gives `"ok": false`.
Write at least one ok + one bad pair per method group you change, using code a dataset row would really contain.

## Verify (scoped to your package)

```sh
export RUSTFLAGS="-C target-feature=+crt-static" CXXFLAGS_x86_64_pc_windows_msvc="-DMI_WIN_INIT_USE_FLS=1"
export PATH="$HOME/.rokit/bin:$PATH"   # lune, needed by surface_diff.py
cargo build --release --locked --bin ree
python validator/probe/surface_diff.py                         # totals: no kind may rise
python validator/probe/surface_diff.py --list "M cv" --grep "<Class>."
python validator/specs/run.py <Package>
cargo test --release
node tools/parity/run.mjs && node tools/parity/run.mjs --server
```

Don't run `cargo fmt`. Never write local user paths, machine names or emails into code, specs, docs or your report.
Studio isn't available to you. Work from the capture (`validator/probe/expected/surface_{server,client}.txt`) and the docs
(create.roblox.com/docs/reference/engine, or a shallow clone of github.com/Roblox/creator-docs outside the repo).

## Report

```
PACKAGE: <name>
DONE: <methods with checks or shapes added, grouped by class>
SURFACE: your classes' cv/cw/c0 lines server <before>-><after>, client <before>-><after>; totals of other kinds unchanged? <yes/no>
LEFT ON PURPOSE: <lines left differing + why (offline/unpublished capture, Studio-only, needs Rust)>
SPECS: <n ok / n bad, all passing>
TESTS: cargo test <pass/fail>, parity <pass/fail>
BLOCKED: <none | what>
```

## The packages

Counts are the lines (cv + cw + c0) of the owned classes that differ today (commit after 55e2d29), server / client. A
class not listed belongs to Core.

| package | classes | lines |
|---|---|---|
| **Commerce** | MarketplaceService, AdService, CommerceService, BadgeService, PointsService, PolicyService, GroupService, SocialService, ExperienceNotificationService, RecommendationService, MatchmakingService, TeleportService, MessagingService, DataStoreService (and its stores, MemoryStoreService), OpenCloudService, ConfigService, Pages and its subclasses, UserService | 95 / 97 |
| **Avatar** | Player, Players, AvatarEditorService, AvatarCreationService, Humanoid, HumanoidDescription, AccessoryDescription, MakeupDescription, Animator, AnimationController, AnimationClipProvider, KeyframeSequenceProvider, Keyframe, KeyframeSequence, Pose, WrapLayer, WrapTarget, BaseWrap, WrapDeformer, WrapTextureTransfer, HumanoidRigDescription, SurfaceAppearance, PlayerViewService | 84 / 77 |
| **World** | AssetService, InsertService, GeometryService, GenerationService, CaptureService, BasePart, MeshPart, PartOperation, TriangleMeshPart, WorldRoot, Workspace, Model, Terrain, Decal, MaterialService, MaterialVariant, PhysicsService, Constraint, FluidForceSensor, Controller, Dragger, ProceduralModel, Path2D, ValueCurve, Lighting, PathfindingService and Path | 91 / 90 |
| **Interface** | GuiBase2d and every GuiObject, GuiService, PlayerGui, StarterGui, LayerCollector, UI constraints, StyleSheet, StyleBase, ContextActionService, UserInputService, GamepadService, HapticEffect, InputAction, Chat, TextChatService, TextChannel, TextService, TextGenerator, VoiceChatService, every Audio* class, SoundService, Sound, VideoPlayer, VideoFrame, VideoService, Translator, LocalizationTable, StarterPlayer | 76 / 72 |
| **Core** | everything else: Instance, CollectionService, HttpService, ReflectionService, Actor, Debris, TweenService, RunService, LogService, TestService, FunctionalTest, StudioTestService, Stats, ScriptContext, scripts, remotes (RemoteEvent, RemoteFunction, UnreliableRemoteEvent, BindableEvent ...), NetworkServer, NetworkClient, AnalyticsService, ModerationService, MLService, IntegrityService, ... | 89 / 84 |

Package notes:

- **Commerce:** rows call DataStores, MarketplaceService and BadgeService a lot (~17,000 rows touch DataStore). The
  wrong side matters most here. A client touching `DataStoreService`, `MessagingService` or `MemoryStoreService` must
  fail as in Roblox (check what ree does today first). `GetProductInfo`, `UserOwnsGamePassAsync`, `PlayerOwnsAsset`,
  `GetAsync` / `SetAsync` / `UpdateAsync` keep working with plausible shapes. DataStore values must round-trip
  (`SetAsync` then `GetAsync` returns it) and reject what Roblox rejects (functions, Instances, non-string keys over
  50 chars ...).
- **Avatar:** Humanoid is the most used area in the dataset (~6,100 rows: TakeDamage, GetState, ChangeState, MoveTo,
  Move, EquipTool, LoadAnimation). Check what ree already emulates first. `validator/specs/Avatar/TakeDamage.*` are
  worked examples (make them pass). `Player` gets more members once the DocsSupplement brief lands (it's missing from
  the API dump today). Do the members ree already knows, and list the rest in the report.
- **World:** Pathfinding (`CreatePath`, `ComputeAsync`, `GetWaypoints`, `Status`) on the server and the client, raycasts,
  `PivotTo`, `GetPartBoundsInBox` ... are mostly real already. Focus on the probe lines and the Async asset services.
- **Interface:** `ContextActionService:BindAction` and `StarterGui:SetCore` / `SetCoreGuiEnabled` are in ~1,200 rows.
  `SetCore` with an unknown or not-yet-registered name errors in Roblox (`SetCore: X has not been registered by the
  CoreScripts`), so match it. Client-only APIs called on a server must behave as Roblox does.
- **Core:** remotes from the wrong side (`FireServer` on a server, `FireClient` / `FireAllClients` / `InvokeClient` on a
  client) must raise Roblox's error. That is the most common real bug in the dataset. Check what ree does today first.
