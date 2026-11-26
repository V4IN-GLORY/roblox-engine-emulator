# Package: Misc

File: `src/lua/validator/Misc.luau`. Specs: `validator/specs/Misc/`. Read `validator/HANDOFF.md` first.

Everything left after the other packages, lowest priority. Run `python validator/probe/gaps.py` (no `--classes`) for the full current list, and skip classes another package owns (Humanoid, ContextActionService, StarterGui, TextBox, GuiService, Marketplace/Badge/Chat/Group/Analytics, Pathfinding, and the server-only stores on the client).

## Start with (most used first)

| area | members |
|---|---|
| Audio API | `AudioPlayer:Play/Stop/Cancel`, `GetConnectedWires`, `GetInputPins`, `GetOutputPins` on every Audio* class, `AudioAnalyzer:GetSpectrum` |
| DataStore extras (server) | `DataStoreService:ListDataStoresAsync`, `SetRateLimitForRequestType`, `DataStoreSetOptions/IncrementOptions:GetMetadata/SetMetadata`, `DataStoreOptions:SetExperimentalFeatures` |
| Animation | `Animator:GetTrackByAnimationId`, `ApplyJointVelocities`, `KeyframeSequence:AddKeyframe/GetKeyframes/RemoveKeyframe` |
| Instances | `Attachment:GetConstraints`, `Tool:Activate/Deactivate`, `Seat:Sit`, `GetStyledPropertyChangedSignal` (every class: return a real signal), `Actor:SendMessage/BindToMessageParallel` |
| Assets | `InsertService:LoadAsset` / `CreateMeshPartAsync`, `AssetService:CreateEditableMesh...` → errors Roblox raises without network are fine, but say which |

Same rules: right return types, right events, Roblox's errors, never silent nil. Leave things that truly can't run offline as `R.Missing` and list them in the report.
