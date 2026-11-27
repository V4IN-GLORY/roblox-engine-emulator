local CommerceService = game:GetService("CommerceService")
local Player = Instance.new("Player")
Player.Parent = game:GetService("Players")

local Info = CommerceService:GetCommerceProductInfoAsync("COM-12345")
assert(Info.IsForSale == true and type(Info.Item.Name) == "string")
CommerceService:PromptCommerceProductPurchase(Player, "COM-12345")
