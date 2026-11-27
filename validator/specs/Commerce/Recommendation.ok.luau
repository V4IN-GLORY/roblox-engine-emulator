local RecommendationService = game:GetService("RecommendationService")
local Player = Instance.new("Player")
Player.Parent = game:GetService("Players")

local Registered = RecommendationService:RegisterItemAsync(Player, { ReferenceId = "item_1" })
assert(type(Registered.ItemId) == "string")

local Fetched = RecommendationService:GetRecommendationItemAsync(Registered.ItemId)
assert(Fetched.ReferenceId == "item_1")

RecommendationService:UpdateItemAsync({ ItemId = Registered.ItemId, ReferenceId = "item_1_v2" })
assert(RecommendationService:GetRecommendationItemAsync(Registered.ItemId).ReferenceId == "item_1_v2")

local Pages = RecommendationService:GenerateItemListAsync({ ConfigName = "MaximizeEngagement" })
assert(Pages.IsFinished == true and #Pages:GetCurrentPage() == 0)
