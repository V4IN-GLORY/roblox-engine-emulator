local OpenCloudService = game:GetService("OpenCloudService")
-- Server-only method called from client
OpenCloudService:InvokeAsync("v1", "test", {})
