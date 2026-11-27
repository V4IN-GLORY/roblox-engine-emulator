local GenerationService = game:GetService("GenerationService")
local Players = game:GetService("Players")
local player = Instance.new("Player")
player.Parent = Players
GenerationService:GenerateMeshAsync({}, player, {})
