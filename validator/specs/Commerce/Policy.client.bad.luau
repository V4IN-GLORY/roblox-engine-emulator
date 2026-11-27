local PolicyService = game:GetService("PolicyService")
-- Server-only method called from client
PolicyService:CanViewBrandProjectAsync(game:GetService("Players").LocalPlayer, "brand_1")
