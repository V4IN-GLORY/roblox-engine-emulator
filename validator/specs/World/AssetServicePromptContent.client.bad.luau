local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local img = AssetService:CreateEditableImage({ Size = Vector2.new(8, 8) })
AssetService:PromptCreatePlatformContentAsync(Players.LocalPlayer, img, Enum.AssetType.Image)
