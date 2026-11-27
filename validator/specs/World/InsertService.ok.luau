local InsertService = game:GetService("InsertService")
local model = InsertService:LoadAsset(123456)
assert(model:IsA("Model") and #model:GetChildren() >= 1)

local part = Instance.new("Part")
InsertService:Insert(part)
assert(part.Parent == workspace)

local meshPart = InsertService:CreateMeshPartAsync("rbxassetid://123456", Enum.CollisionFidelity.Default, Enum.RenderFidelity.Automatic)
assert(meshPart:IsA("MeshPart"))

local version = InsertService:GetLatestAssetVersionAsync(123456)
assert(type(version) == "number" and version >= 1)
