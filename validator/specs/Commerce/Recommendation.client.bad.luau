local RecommendationService = game:GetService("RecommendationService")
-- Server-only method called from client
RecommendationService:RegisterItemAsync(game:GetService("Players").LocalPlayer, { ReferenceId = "item_1" })
