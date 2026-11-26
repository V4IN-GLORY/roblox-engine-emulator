# Package: ContextGuards

File: `src/lua/validator/ContextGuards.luau`. Specs: `validator/specs/ContextGuards/`. Read `validator/HANDOFF.md` first.

The most common real bug in Roblox training data is **calling an API from the wrong side**: a LocalScript using DataStoreService, a server calling `FireServer`, a client calling `FireAllClients`. Today ree just reports these as unemulated on the client, so the validator can't tell it's a bug. This package makes them fail the way Roblox does.

## What to guard

| called from | API | Roblox's behaviour |
|---|---|---|
| client | `DataStoreService:GetDataStore` / `GetGlobalDataStore` / `GetOrderedDataStore` / `ListDataStoresAsync` / `GetRequestBudgetForRequestType` | error (`DataStore can't be accessed from client`; check the exact text in the docs / devforum) |
| client | `MemoryStoreService:Get*` | error (server only) |
| client | `MessagingService:PublishAsync` / `SubscribeAsync` | error (server only) |
| client | `RemoteEvent:FireClient` / `FireAllClients`, `RemoteFunction:InvokeClient` | `FireClient can only be called from the server` etc. |
| server | `RemoteEvent:FireServer`, `RemoteFunction:InvokeServer` | `FireServer can only be called from the client` etc. |
| client | `BadgeService:AwardBadge(Async)`, `Player:Kick` on another player, `TeleportService:TeleportAsync`, `HttpService:GetAsync/PostAsync/RequestAsync` | Roblox's errors (`Http requests can only be executed by game server` etc.) |
| server | `Players.LocalPlayer` use (nil), `UserInputService` input-only members, `Player:GetMouse()` | match Roblox: LocalPlayer is nil on server (likely already), GetMouse errors/returns nil as Roblox does |

Use `R.IsServer`. Check first what ree already does for each (some are already right): only add what's missing, and list in the report which were already correct.

## Misuse cases to spec

Each row above: a `.client.bad.luau` or `.bad.luau` spec with the wrong-side call, plus an `.ok` spec showing the right-side call still works.
