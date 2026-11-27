local AdService = game:GetService("AdService")
local Player = Instance.new("Player")
Player.Parent = game:GetService("Players")

local Reward = AdService:CreateAdRewardFromDevProductId(12345)
assert(Reward.ReferenceId == "12345")

local Eligibility = AdService:GetCampaignEligibilityAsync("camp_1", Player)
assert(Eligibility.IsEligible == true)

local Result = AdService:ShowRewardedVideoAdAsync(Player, Reward)
assert(Result == Enum.ShowAdResult.ShowCompleted)
