local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local player = Instance.new("Player")
player.Parent = Players
local part = Instance.new("Part")
AssetService:PromptCreatePlatformContentAsync(player, part, Enum.AssetType.Image)
