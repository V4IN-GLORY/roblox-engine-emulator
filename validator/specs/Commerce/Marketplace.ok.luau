local MarketplaceService = game:GetService("MarketplaceService")
local Player = Instance.new("Player")
Player.UserId = 42
Player.Parent = game:GetService("Players")

local Info = MarketplaceService:GetProductInfo(123456, Enum.InfoType.Product)
assert(type(Info.Name) == "string" and type(Info.PriceInRobux) == "number")
assert(MarketplaceService:UserOwnsGamePassAsync(Player.UserId, 999) == false)

MarketplaceService:PromptProductPurchase(Player, 123456)
MarketplaceService:PromptGamePassPurchase(Player, 999)
MarketplaceService:PromptPurchase(Player, 777)
MarketplaceService:PromptBundlePurchase(Player, 555)
MarketplaceService:PromptPremiumPurchase(Player)

local Levels = MarketplaceService:GetUsersPriceLevelsAsync({ 42 })
assert(#Levels == 1 and Levels[1].UserId == 42)

local SubStatus = MarketplaceService:GetUserSubscriptionStatusAsync(Player, "EXP-12345")
assert(SubStatus.IsSubscribed == false)

local Conn = MarketplaceService:BindReceiptHandler(Enum.ReceiptType.DeveloperProduct, function()
	return Enum.ProductPurchaseDecision.PurchaseGranted
end)
Conn:Disconnect()

local DevProducts = MarketplaceService:GetDeveloperProductsAsync()
assert(DevProducts.IsFinished == true and #DevProducts:GetCurrentPage() == 0)
