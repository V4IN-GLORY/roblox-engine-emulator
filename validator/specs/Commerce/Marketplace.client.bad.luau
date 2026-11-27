local MarketplaceService = game:GetService("MarketplaceService")
-- Server-only method called from client
MarketplaceService:BindReceiptHandler(Enum.ReceiptType.DeveloperProduct, function() end)
