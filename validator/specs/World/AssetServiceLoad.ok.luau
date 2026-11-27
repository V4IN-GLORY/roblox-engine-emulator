local AssetService = game:GetService("AssetService")
local model = AssetService:LoadAssetAsync(123456)
assert(model:IsA("Model"))
assert(#model:GetChildren() >= 1)

local meta = AssetService:GetAudioMetadataAsync({ 123456 })
assert(#meta == 1 and type(meta[1].Title) == "string" and type(meta[1].Duration) == "number")

local places = AssetService:GetGamePlacesAsync()
assert(places:IsA("StandardPages"))

local newId = AssetService:CreatePlaceAsync("Arena", 123456, "Battle arena")
assert(type(newId) == "number")

AssetService:SavePlaceAsync()
