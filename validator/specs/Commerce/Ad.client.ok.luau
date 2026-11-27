local AdService = game:GetService("AdService")
local Avail = AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
assert(Avail.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable)

local Elig = AdService:GetCampaignEligibilityAsync("placement_1")
assert(Elig.IsEligible == true)

local Button = Instance.new("TextButton")
AdService:RegisterDisclosureButton(Button, "placement_1")

local Part = Instance.new("Part")
AdService:RegisterImpressionSource(Part, "placement_1")
AdService:RegisterAdOpportunityAsync(Part)
AdService:UnregisterAdOpportunity(Part)
