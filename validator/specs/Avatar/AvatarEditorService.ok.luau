local AvatarEditorService = game:GetService("AvatarEditorService")

assert(AvatarEditorService:GetAccessoryType(Enum.AvatarAssetType.HairAccessory) == Enum.AccessoryType.Hair)

local rules = AvatarEditorService:GetAvatarRulesAsync()
assert(type(rules) == "table" and type(rules.Scales) == "table")

local details = AvatarEditorService:GetItemDetailsAsync(12345, Enum.AvatarItemType.Asset)
assert(details.Id == 12345 and details.ItemType == "Asset")

local batch = AvatarEditorService:GetBatchItemDetailsAsync({ 1, 2 }, Enum.AvatarItemType.Asset)
assert(#batch == 2)

local outfit = AvatarEditorService:GetOutfitDetailsAsync(42)
assert(type(outfit.Name) == "string")

local desc = Instance.new("HumanoidDescription")
local conformed = AvatarEditorService:ConformToAvatarRulesAsync(desc)
assert(conformed:IsA("HumanoidDescription"))

local clothed = AvatarEditorService:CheckApplyDefaultClothingAsync(desc)
assert(clothed:IsA("HumanoidDescription"))

local pages = AvatarEditorService:SearchCatalogAsync(CatalogSearchParams.new())
assert(pages:IsA("CatalogPages"))
