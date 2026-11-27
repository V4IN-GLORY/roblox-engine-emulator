local GenerationService = game:GetService("GenerationService")
local Players = game:GetService("Players")
local player = Instance.new("Player")
player.Parent = Players

local genId = GenerationService:GenerateMeshAsync({ Prompt = "wooden chair" }, player, {})
assert(type(genId) == "string")

local model = GenerationService:GenerateModelAsync({ TextPrompt = "wooden table" }, {})
assert(model:IsA("Model"))
