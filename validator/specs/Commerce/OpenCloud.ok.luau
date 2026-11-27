local OpenCloudService = game:GetService("OpenCloudService")
local Response = OpenCloudService:InvokeAsync("v1", "test", {})
assert(type(Response) == "table")
