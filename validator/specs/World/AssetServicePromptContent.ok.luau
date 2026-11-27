local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local player = Instance.new("Player")
player.Parent = Players
local img = AssetService:CreateEditableImage({ Size = Vector2.new(8, 8) })
local result, id = AssetService:PromptCreatePlatformContentAsync(player, img, Enum.AssetType.Image)
assert(result == Enum.PromptCreateAssetResult.Success and type(id) == "number")
