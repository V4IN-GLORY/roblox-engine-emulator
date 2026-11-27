local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

AnalyticsService:GetPlayerSegmentsAsync(Players.LocalPlayer)
