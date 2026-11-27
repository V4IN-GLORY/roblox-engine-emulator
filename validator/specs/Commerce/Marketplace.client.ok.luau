local MarketplaceService = game:GetService("MarketplaceService")
local Player = game:GetService("Players").LocalPlayer

local SubInfo = MarketplaceService:GetSubscriptionProductInfoAsync("EXP-12345")
assert(type(SubInfo.Name) == "string")

local Status = MarketplaceService:GetUserSubscriptionStatusAsync(Player, "EXP-12345")
assert(Status.IsSubscribed == false)

local Top = MarketplaceService:RecommendTopProductsAsync({ Enum.InfoType.GamePass })
assert(type(Top) == "table")
