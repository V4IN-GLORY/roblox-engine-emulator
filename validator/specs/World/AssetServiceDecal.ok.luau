local AssetService = game:GetService("AssetService")
local image = AssetService:CreateEditableImage()
local decal = AssetService:CreateDecalAsync({
	TextureContent = Content.fromObject(image),
})
assert(decal:IsA("Decal"))
AssetService:ComposeDecalAsync(decal, {
	{ ColorMap = Content.fromUri("rbxassetid://123456") },
})
