local AvatarCreationService = game:GetService("AvatarCreationService")
local player = Instance.new("Player")

local rules = AvatarCreationService:GetValidationRules()
assert(type(rules) == "table")

local previewId = AvatarCreationService:GenerateAvatar2DPreviewAsync({ textPrompt = "cyberpunk knight" })
assert(type(previewId) == "string")

local genId = AvatarCreationService:GenerateAvatarAsync({ previewId = previewId })
assert(type(genId) == "string")

-- the keys as the docs spell them, with a progress callback
local progress = 0
local docsPreview = AvatarCreationService:GenerateAvatar2DPreviewAsync({ SessionId = "session", TextPrompt = "pirate" }, function(info)
	progress = info.Progress
end)
AvatarCreationService:GenerateAvatarAsync({ SessionId = "session", PreviewId = docsPreview })
assert(progress == 1)

local loadedDesc = AvatarCreationService:LoadGeneratedAvatarAsync(genId)
assert(loadedDesc:IsA("HumanoidDescription"))

local tokens = AvatarCreationService:GetBatchTokenDetailsAsync({ "token-1" })
assert(type(tokens) == "table" and #tokens == 1)

local rig = Instance.new("Model")
Instance.new("Humanoid").Parent = rig
AvatarCreationService:PrepareAvatarForPreviewAsync(rig)

local setupId = AvatarCreationService:AutoSetupAvatarAsync(player, { Body = rig })
assert(type(setupId) == "string")

local hat = Instance.new("Accessory")
local assetResult, assetId = AvatarCreationService:PromptCreateAvatarAssetAsync("token-1", player, hat, Enum.AvatarAssetType.Hat)
assert(assetResult == Enum.PromptCreateAvatarResult.Success and type(assetId) == "number")

local fullDesc = Instance.new("HumanoidDescription")
Instance.new("AccessoryDescription").Parent = fullDesc
local avatarResult = AvatarCreationService:PromptCreateAvatarAsync("token-1", player, fullDesc)
assert(avatarResult == Enum.PromptCreateAvatarResult.Success)

local makeupResult = AvatarCreationService:PromptCreateMakeupAsync(player, { {}, {} })
assert(makeupResult == Enum.PromptCreateAvatarResult.Success)

local conn, sessionId = AvatarCreationService:RequestAvatarGenerationSessionAsync(player, function() end)
assert(typeof(conn) == "RBXScriptConnection" and type(sessionId) == "number")
conn:Disconnect()

local validAcc = AvatarCreationService:ValidateUGCAccessoryAsync(player, hat, Enum.AccessoryType.Hat)
assert(validAcc == true)

local validFull = AvatarCreationService:ValidateUGCFullBodyAsync(player, fullDesc)
assert(validFull == true)
