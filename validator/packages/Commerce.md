# Package: Commerce

File: `src/lua/validator/Commerce.luau`. Specs: `validator/specs/Commerce/`. Read `validator/HANDOFF.md` first.

Marketplace, badges, chat filtering, groups, analytics (~2,000 rows). None of these can reach Roblox's backend, so answers are **deterministic and plausible**, and the follow-up events fire exactly as Roblox fires them. `services.luau` already has some stubs that call `Missing` (search `MarketplaceService`, `BadgeService`): replace them.

## Members

| area | members | must do |
|---|---|---|
| Marketplace prompts | `PromptProductPurchase`, `PromptGamePassPurchase`, `PromptPurchase`, `PromptBundlePurchase`, `PromptSubscriptionPurchase`, `PromptPremiumPurchase`, ... | validate args (Player instance, number ids); next frame fire the matching `Prompt*Finished` with `false` (declined) |
| Receipts | `ProcessReceipt` callback, `BindReceiptHandler` | assigning a non-function errors as Roblox; storing works |
| Info | `GetProductInfo` / `GetProductInfoAsync`, `GetDeveloperProductsAsync`, `GetUsersPriceLevelsAsync`, `GetSubscriptionProductInfoAsync` | full table shape from the docs (Name, Description, PriceInRobux, AssetId/ProductId, IsForSale, Creator={...}, ...) with deterministic values; pages objects where the docs say pages |
| Ownership | `UserOwnsGamePassAsync`, `PlayerOwnsAssetAsync`, `PlayerOwnsBundleAsync`, `GetPassOwnershipAsync` | false; bad id types error |
| Badges | `AwardBadgeAsync` / `AwardBadge` (server only), `UserHasBadgeAsync`, `CheckUserBadgesAsync`, `GetBadgeInfoAsync`, `GetUserBadgesAsync` | award records it so a later `UserHasBadgeAsync` is true; info table with the documented keys |
| Chat / text | `Chat:FilterStringAsync`, `FilterStringForBroadcast`, `TextService:FilterStringAsync` (check if present), `CanUserChatAsync`, `CanUsersChatAsync`, `Chat:Chat` | filter returns the text unchanged / a TextFilterResult whose `GetNonChatStringForBroadcastAsync` etc. return it; Chat:Chat fires `Chatted` locally |
| Groups | `GroupService:GetGroupInfoAsync`, `GetAlliesAsync`, `GetEnemiesAsync`, `GetGroupsAsync`, `PromptJoinAsync` | documented shapes, pages |
| Analytics | `AnalyticsService:LogEconomyEvent`, `LogProgression*Event`, `LogOnboardingFunnelStepEvent`, `LogFunnelStepEvent`, `LogCustomEvent`, `LogJourneyEvent`, `GetPlayerSegmentsAsync` | validate args exactly (enum flow types, required strings), else no-op; these are where data rows misuse arguments most |

## Misuse cases to spec

- `PromptProductPurchase("player", 123)` → cast error.
- `MarketplaceService.ProcessReceipt = 5` → error.
- `LogEconomyEvent(player, "Source", "Coins", 10, 100, "Shop")` (string instead of `Enum.AnalyticsEconomyFlowType`) → error.
