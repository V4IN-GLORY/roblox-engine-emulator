local AssetService = game:GetService("AssetService")
local ModerationService = game:GetService("ModerationService")

local conn = ModerationService:BindReviewableContentEventProcessor(0, function() end)
local contentId = ModerationService:CreateReviewableContentAsync({})
assert(type(contentId) == "string", "expected content id string")

local image = AssetService:CreateEditableImage()
local key = ModerationService:CreateReviewableContentKey(Content.fromObject(image))
assert(type(key) == "string", "expected content key string")
conn:Disconnect()
