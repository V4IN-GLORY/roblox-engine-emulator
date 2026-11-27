local AssetService = game:GetService("AssetService")

local meshPart = Instance.new("MeshPart")
meshPart.Parent = workspace

local wrapTarget = Instance.new("WrapTarget")
wrapTarget.Parent = meshPart

local deformer = Instance.new("WrapDeformer")
deformer.Parent = meshPart
deformer:SetCageMeshContent(Content.fromUri("rbxassetid://1"))

local editableMesh = deformer:CreateEditableMeshAsync()
assert(editableMesh:IsA("EditableMesh"))

local deformed = deformer:GetDeformedCFrameAsync(CFrame.new(1, 2, 3))
assert(typeof(deformed) == "CFrame")

local decal = Instance.new("Decal")
decal.Parent = meshPart
local transfer = Instance.new("WrapTextureTransfer")
transfer.Parent = decal
transfer:PrepareProjectionMeshDataAsync()

local img = AssetService:CreateEditableImage()
local cageTex = wrapTarget:CreateTextureInCageSpaceAsync(img)
assert(cageTex:IsA("EditableImage"))
local targetTex = wrapTarget:CreateTextureInTargetSpaceAsync(img, transfer)
assert(targetTex:IsA("EditableImage"))
