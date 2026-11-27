local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

AnalyticsService:FireEvent("Gameplay", "LevelUp")
local player = Instance.new("Player")
player.Parent = Players
local segments = AnalyticsService:GetPlayerSegmentsAsync(player)
assert(type(segments) == "table", "expected segments table")
