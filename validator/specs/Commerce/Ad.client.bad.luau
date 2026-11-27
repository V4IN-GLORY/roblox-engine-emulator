local AdService = game:GetService("AdService")
-- RegisterDisclosureButton without prior GetCampaignEligibilityAsync
AdService:RegisterDisclosureButton(Instance.new("TextButton"), "unverified_placement")
