local GenerationService = game:GetService("GenerationService")
local meshPart = GenerationService:LoadGeneratedMeshAsync("gen_mesh_1")
assert(meshPart:IsA("MeshPart"))
