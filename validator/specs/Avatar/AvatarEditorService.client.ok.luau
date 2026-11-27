local AvatarEditorService = game:GetService("AvatarEditorService")

AvatarEditorService:PromptAllowInventoryReadAccess()
AvatarEditorService:PromptSetFavorite(100, Enum.AvatarItemType.Asset, true)
assert(AvatarEditorService:GetFavoriteAsync(100, Enum.AvatarItemType.Asset) == true)

local inv = AvatarEditorService:GetInventoryAsync({ Enum.AvatarAssetType.Hat })
assert(inv:IsA("InventoryPages"))

local outfits = AvatarEditorService:GetOutfitsAsync(Enum.OutfitSource.All, Enum.OutfitType.Avatar)
assert(outfits:IsA("OutfitPages"))

AvatarEditorService:PromptCreateOutfit(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
AvatarEditorService:PromptSaveAvatar(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
AvatarEditorService:PromptDeleteOutfit(1)
AvatarEditorService:PromptRenameOutfit(1)
AvatarEditorService:PromptUpdateOutfit(1, Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
