local GenerationService = game:GetService("GenerationService")
local Players = game:GetService("Players")
GenerationService:GenerateMeshAsync({ Prompt = "chair" }, Players.LocalPlayer, {})
