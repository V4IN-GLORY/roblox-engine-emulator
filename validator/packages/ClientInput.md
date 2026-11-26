# Package: ClientInput

File: `src/lua/validator/ClientInput.luau`. Specs: `validator/specs/ClientInput/` (client specs: name them `X.client.ok.luau`). Read `validator/HANDOFF.md` first.

Client-side UI and input APIs (~1,200 rows). ree's `src/services/input_actions.rs` already does the new Input Action System; this is the older API surface.

## Members

| member | must do |
|---|---|
| `ContextActionService:BindAction(name, fn, createTouchButton, ...inputs)` | store the binding; inputs must be `Enum.KeyCode` / `Enum.UserInputType` / `Enum.PlayerActions` (Roblox errors otherwise); `fn` must be a function |
| `BindActionAtPriority`, `UnbindAction`, `UnbindAllActions`, `GetBoundActionInfo`, `GetAllBoundActionInfo` | consistent with what's bound (check which of these ree already has, complete the rest) |
| `SetTitle`, `SetDescription`, `SetImage`, `SetPosition`, `GetButton` | store values; `GetButton` returns nil (no touch device), as on desktop Roblox |
| `BindActivate`, `UnbindActivate`, `GetCurrentLocalToolIcon` | store / return "" |
| `StarterGui:SetCore(name, value)` | accept Roblox's known SetCore names (`SendNotification`, `ResetButtonCallback`, `ChatMakeSystemMessage`, `TopbarEnabled`, `ChatActive`, `PointsNotificationsActive`, `BadgesNotificationsActive`, `AvatarContextMenuEnabled`, ...); unknown name → `SetCore: <name> has not been registered by the CoreScripts` |
| `StarterGui:GetCore(name)` | returns what SetCore stored |
| `StarterGui:SetCoreGuiEnabled(type, enabled)` / `GetCoreGuiEnabled` | `Enum.CoreGuiType` only, store per type (`All` sets every type) |
| `StarterGui:GetGuiObjectsAtPosition(x, y)` | GuiObjects under the point in PlayerGui, topmost first (AbsolutePosition/AbsoluteSize hit test) |
| `TextBox:CaptureFocus()` / `ReleaseFocus(submitted?)` / `IsFocused()` | toggle focus, fire `Focused` / `FocusLost(enterPressed, input)` |
| `GuiService` ones (`SendNotification`, `Select`, `SetEmotesMenuOpen`, `SetInspectMenuEnabled`, `InspectPlayerFromUserId`, ...) | store / no-op with right return types |

## Misuse cases to spec

- `BindAction("Sprint", nil, false, Enum.KeyCode.LeftShift)` → error.
- `SetCore("NotARealThing", true)` → the registration error.
- `SetCoreGuiEnabled("Backpack", false)` → enum cast error.
