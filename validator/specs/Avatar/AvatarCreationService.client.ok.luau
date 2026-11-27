local AvatarCreationService = game:GetService("AvatarCreationService")
local previewId = AvatarCreationService:GenerateAvatar2DPreviewAsync({ textPrompt = "wizard" })
local image = AvatarCreationService:LoadAvatar2DPreviewAsync(previewId)
assert(image:IsA("EditableImage"))
