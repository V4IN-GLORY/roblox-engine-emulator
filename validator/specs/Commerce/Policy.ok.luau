local PolicyService = game:GetService("PolicyService")
local Player = Instance.new("Player")
Player.Parent = game:GetService("Players")

local Policy = PolicyService:GetPolicyInfoForPlayerAsync(Player)
assert(type(Policy.AreAdsAllowed) == "boolean" and type(Policy.AllowedExternalLinkReferences) == "table")
assert(PolicyService:CanViewBrandProjectAsync(Player, "brand_1") == false)
