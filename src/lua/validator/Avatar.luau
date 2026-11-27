--!nocheck
-- Validator extension: see validator/packages/Behaviours.md for what this file owns (Avatar package).
local R = ...
local Method = R.Method
local Create = R.Create
local RawSet = R.RawSet
local RawGet = R.RawGet
local Children = R.Children
local Missing = R.Missing
local IsServer = R.IsServer
local StringParam = R.StringParam
local JsonEncode = R.JsonEncode
local JsonDecode = R.JsonDecode

local Extras = setmetatable({}, { __mode = "k" })
local function Extra(Instance_)
	local Found = Extras[Instance_]
	if not Found then
		Found = {}
		Extras[Instance_] = Found
	end
	return Found
end

local function ReadString(Value, Argument)
	return if type(Value) == "string" then Value else StringParam(Value, Argument)
end

-- the arg checks let an enum's name or number through as it is
local function ResolveEnum(EnumType, Value)
	if typeof(Value) == "EnumItem" then
		return if Value.EnumType == EnumType then Value else nil
	elseif type(Value) == "string" then
		return EnumType:FromName(Value)
	elseif type(Value) == "number" then
		return EnumType:FromValue(Value)
	elseif type(Value) == "boolean" then
		return EnumType:FromValue(if Value then 1 else 0)
	end
	return nil
end

local function ChildrenOfClass(Parent, ClassName)
	local Result = {}
	for _, Child in Children(Parent) do
		if Child:IsA(ClassName) then
			table.insert(Result, Child)
		end
	end
	return Result
end

-- one finished, empty page: unfinished pages would loop a script forever
local function FinishedPages(ClassName)
	local Pages = Create(ClassName)
	RawSet(Pages, "IsFinished", true, true)
	return Pages
end

local function ReturnsPages(Class, ClassName, Names, Check)
	for _, Name in Names do
		Method(Class, Name, function()
			if Check then
				Check(Name)
			end
			task.wait()
			return FinishedPages(ClassName)
		end)
	end
end

-- AccessoryDescription / MakeupDescription

for _, Class in { "AccessoryDescription", "MakeupDescription" } do
	Method(Class, "GetAppliedInstance", function(Self)
		if Self.Parent == nil or not Self.Parent:IsA("HumanoidDescription") then
			error(`{Class} is not parented to a HumanoidDescription. Did you call ApplyDescription()?`, 0)
		end
		return nil
	end)
end

-- AnimationClipProvider / KeyframeSequenceProvider

Method("AnimationClipProvider", "GetClipEvaluatorAsync", function()
	error("AnimationClipProvider:GetClipEvaluatorAsync is not currently enabled", 0)
end)

for _, Class in { "AnimationClipProvider", "KeyframeSequenceProvider" } do
	ReturnsPages(Class, "InventoryPages", { "GetAnimations", "GetAnimationsAsync" })
end

-- Animator

Method("Animator", "ApplyJointVelocities", function(_, Motors)
	if type(Motors) ~= "table" or (next(Motors) ~= nil and #Motors == 0) then
		error("motors must be an array.", 0)
	end
end)

Method("Animator", "GetTrackByAnimationId", function(Self, AnimationId)
	local Wanted = tostring(AnimationId)
	for _, Track in Self:GetPlayingAnimationTracks() do
		local Animation = Track.Animation
		if Animation and Animation.AnimationId == Wanted then
			return Track
		end
	end
	return nil
end)

-- AvatarCreationService

local function RequireServerCreation(Name)
	if not IsServer then
		error(`AvatarCreationService::{Name} - Can Only be Called on the Server.`, 0)
	end
end

local function IsText(Value)
	return type(Value) == "string" and Value ~= ""
end

local function Generated(Progress, Id)
	task.wait()
	if Progress then
		task.spawn(Progress, { Progress = 1 })
	end
	return Id
end

Method("AvatarCreationService", "AutoSetupAvatarAsync", function(_, _Player, Params, Progress)
	if not IsServer then
		error("AvatarCreationService::AutoSetupAvatarAsync can only be called on the server", 0)
	end
	local Accessories = Params.Accessories
	if not Params.Body and (type(Accessories) ~= "table" or next(Accessories) == nil) then
		error("AutoSetupAvatarAsync - no body or accessories were provided", 0)
	end
	return Generated(Progress, "auto-setup-avatar-1")
end)

-- (the docs spell the keys in PascalCase, the client's errors in camelCase: both are taken)
Method("AvatarCreationService", "GenerateAvatar2DPreviewAsync", function(_, Params, Progress)
	if not (IsText(Params.TextPrompt) or IsText(Params.textPrompt) or IsText(Params.FileId)) then
		error("textPrompt not provided or invalid type.", 0)
	end
	return Generated(Progress, "avatar-2d-preview-1")
end)

Method("AvatarCreationService", "GenerateAvatarAsync", function(_, Params, Progress)
	if not (IsText(Params.PreviewId) or IsText(Params.previewId)) then
		error("previewId not provided or invalid type.", 0)
	end
	return Generated(Progress, "avatar-generation-1")
end)

Method("AvatarCreationService", "GetBatchTokenDetailsAsync", function(_, TokenIds)
	if #TokenIds == 0 then
		error("AvatarCreationService:getTokenDetailsAsync - tokenIds must not be empty", 0)
	end
	task.wait()
	local Details = {}
	for _, TokenId in TokenIds do
		table.insert(Details, { TokenId = tostring(TokenId), PriceInRobux = 0, CreatorType = "User", CreatorId = 1 })
	end
	return Details
end)

Method("AvatarCreationService", "LoadAvatar2DPreviewAsync", function()
	if IsServer then
		error("AvatarCreationService:LoadAvatarPreviewImageAsync should only be called on the client.", 0)
	end
	task.wait()
	return Create("EditableImage")
end)

Method("AvatarCreationService", "PrepareAvatarForPreviewAsync", function(_, Model)
	if not Model:FindFirstChildOfClass("Humanoid") then
		error("AvatarCreationService:PrepareAvatarForPreviewAsync - Humanoid not found in model.", 0)
	end
	task.wait()
end)

local function RequireDescriptionChildren(Description, Source)
	if not Description:IsA("HumanoidDescription") or #Children(Description) == 0 then
		error(`AvatarCreationService::{Source} invalid humanoid description - no children`, 0)
	end
end

Method("AvatarCreationService", "PromptCreateAvatarAssetAsync", function(_, _TokenId, _Player, AssetInstance)
	RequireServerCreation("PromptCreateAvatarAssetAsync")
	if not (AssetInstance:IsA("Accessory") or (AssetInstance:IsA("Model") and not AssetInstance:IsA("Workspace"))) then
		error("AvatarCreationService::PromptCreateAvatarAssetAsync - No valid Accessory provided.", 0)
	end
	task.wait()
	return Enum.PromptCreateAvatarResult.Success, 1
end)

Method("AvatarCreationService", "PromptCreateAvatarAsync", function(_, _TokenId, _Player, Description)
	RequireServerCreation("PromptCreateAvatarAsync")
	RequireDescriptionChildren(Description, "PromptCreateAvatarAsync")
	task.wait()
	return Enum.PromptCreateAvatarResult.Success, Create("HumanoidDescription")
end)

Method("AvatarCreationService", "PromptCreateMakeupAsync", function(_, _Player, Entries)
	RequireServerCreation("PromptCreateMakeupAsync")
	local Count = #Entries
	if Count < 2 or Count > 6 then
		error(`AvatarCreationService::PromptCreateMakeupAsync invalid input - entry count {Count} is out of range [2, 6]`, 0)
	end
	task.wait()
	return Enum.PromptCreateAvatarResult.Success, 1
end)

Method("AvatarCreationService", "PromptSelectAvatarGenerationImageAsync", function()
	if not IsServer then
		error("ServerOnly: Method can only be called on the server", 0)
	end
	task.wait()
	return "selected-avatar-image-1"
end)

Method("AvatarCreationService", "RequestAvatarGenerationSessionAsync", function(_, _Player, Callback)
	task.wait()
	return Create("BindableEvent").Event:Connect(Callback), 0
end)

for _, Name in { "ValidateUGCAccessoryAsync", "ValidateUGCBodyPartAsync" } do
	Method("AvatarCreationService", Name, function(_, _Player, AssetInstance)
		RequireServerCreation(Name)
		if AssetInstance:IsA("Workspace") then
			error("Workspace cannot be cloned", 0)
		end
		task.wait()
		return true, {}
	end)
end

Method("AvatarCreationService", "ValidateUGCFullBodyAsync", function(_, _Player, Description)
	RequireServerCreation("ValidateUGCFullBodyAsync")
	RequireDescriptionChildren(Description, "onPublishAuthorizationComplete")
	task.wait()
	return true, {}
end)

-- AvatarEditorService

local MAX_BATCH_ITEMS = 100
local InventoryAccessGranted = false
local Favorites = {}

local function RequireInventoryAccess()
	if IsServer then
		error("This method can only be called on the client", 0)
	end
	if not InventoryAccessGranted then
		error("Permission must be obtained with PromptAllowInventoryReadAccess before calling this method", 0)
	end
end

local function RequireEditorClient(Name)
	if IsServer then
		error(`{Name} can only be called on the client`, 0)
	end
end

local ACCESSORY_TYPE_BY_ASSET_TYPE = {
	Hat = "Hat",
	HairAccessory = "Hair",
	FaceAccessory = "Face",
	NeckAccessory = "Neck",
	ShoulderAccessory = "Shoulder",
	FrontAccessory = "Front",
	BackAccessory = "Back",
	WaistAccessory = "Waist",
	TShirtAccessory = "TShirt",
	ShirtAccessory = "Shirt",
	PantsAccessory = "Pants",
	JacketAccessory = "Jacket",
	SweaterAccessory = "Sweater",
	ShortsAccessory = "Shorts",
	LeftShoeAccessory = "LeftShoe",
	RightShoeAccessory = "RightShoe",
	DressSkirtAccessory = "DressSkirt",
	EyebrowAccessory = "Eyebrow",
	EyelashAccessory = "Eyelash",
}

local function ItemDetails(ItemId, ItemType)
	local Resolved = ResolveEnum(Enum.AvatarItemType, ItemType)
	local IsBundle = Resolved == Enum.AvatarItemType.Bundle
	return {
		Id = ItemId,
		ItemType = if IsBundle then "Bundle" else "Asset",
		AssetType = if IsBundle then nil else "Hat",
		BundleType = if IsBundle then "BodyParts" else nil,
		Name = `Item {ItemId}`,
		Description = "",
		ProductId = ItemId,
		ItemStatus = {},
		ItemRestrictions = {},
		CreatorType = "User",
		CreatorTargetId = 1,
		CreatorName = "Roblox",
		CreatorHasVerifiedBadge = true,
		Price = 0,
		LowestPrice = 0,
		PriceStatus = "Free",
		FavoriteCount = 0,
		PurchaseCount = 0,
		HasResellers = false,
	}
end

for _, Name in { "GetItemDetails", "GetItemDetailsAsync" } do
	Method("AvatarEditorService", Name, function(_, ItemId, ItemType)
		task.wait()
		local Details = ItemDetails(ItemId, ItemType)
		Details.Owned = false
		Details.IsPurchasable = true
		Details.ExpectedSellerId = Details.CreatorTargetId
		return Details
	end)
end

for _, Name in { "GetBatchItemDetails", "GetBatchItemDetailsAsync" } do
	Method("AvatarEditorService", Name, function(_, ItemIds, ItemType)
		if #ItemIds > MAX_BATCH_ITEMS then
			error(`{Name} accepts at most {MAX_BATCH_ITEMS} item ids`, 0) -- text: docs
		end
		task.wait()
		local Result = {}
		for _, ItemId in ItemIds do
			table.insert(Result, ItemDetails(ItemId, ItemType))
		end
		return Result
	end)
end

for _, Name in { "CheckApplyDefaultClothing", "CheckApplyDefaultClothingAsync", "ConformToAvatarRules", "ConformToAvatarRulesAsync" } do
	Method("AvatarEditorService", Name, function(_, Description)
		task.wait()
		return Description:Clone()
	end)
end

Method("AvatarEditorService", "GetAccessoryType", function(_, AssetType)
	local Resolved = ResolveEnum(Enum.AvatarAssetType, AssetType)
	local Mapped = Resolved and ACCESSORY_TYPE_BY_ASSET_TYPE[Resolved.Name]
	return if Mapped then Enum.AccessoryType[Mapped] else Enum.AccessoryType.Unknown
end)

local SCALE_RANGES = {
	Height = { 0.9, 1.05 },
	Width = { 0.7, 1 },
	Head = { 0.95, 1 },
	Depth = { 0.85, 1 },
	Proportion = { 0, 1 },
	BodyType = { 0, 1 },
}

for _, Name in { "GetAvatarRules", "GetAvatarRulesAsync" } do
	Method("AvatarEditorService", Name, function()
		task.wait()
		local Scales = {}
		for Scale, Range in SCALE_RANGES do
			Scales[Scale] = { Min = Range[1], Max = Range[2], Increment = 0.01 }
		end
		return {
			PlayerAvatarTypes = { "R6", "R15" },
			Scales = Scales,
			WearableAssetTypes = {},
			BodyColorsPalette = {},
			BasicBodyColorsPalette = {},
			MinimumDeltaEBodyColorDifference = 11.4,
			ProportionsAndBodyTypeEnabledForUser = true,
			DefaultClothingAssetLists = { DefaultShirtAssetIds = {}, DefaultPantAssetIds = {} },
			BundlesEnabledForUser = true,
			EmotesEnabledForUser = true,
		}
	end)
end

local OUTFIT_LIMBS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }

for _, Name in { "GetOutfitDetails", "GetOutfitDetailsAsync" } do
	Method("AvatarEditorService", Name, function(_, OutfitId)
		task.wait()
		local BodyColors = {}
		for _, Limb in OUTFIT_LIMBS do
			BodyColors[`{Limb}Color`] = Color3.fromRGB(163, 162, 165)
		end
		return {
			Id = OutfitId,
			Name = `Outfit {OutfitId}`,
			Assets = {},
			BodyColors = BodyColors,
			Scale = { Height = 1, Width = 1, Head = 1, Depth = 1, Proportion = 0, BodyType = 0 },
			PlayerAvatarType = "R15",
			OutfitType = "Avatar",
			IsEditable = true,
		}
	end)
end

local function FavoriteKey(ItemId, ItemType)
	return `{ResolveEnum(Enum.AvatarItemType, ItemType)}:{ItemId}`
end

for _, Name in { "GetFavorite", "GetFavoriteAsync" } do
	Method("AvatarEditorService", Name, function(_, ItemId, ItemType)
		RequireInventoryAccess()
		task.wait()
		return Favorites[FavoriteKey(ItemId, ItemType)] == true
	end)
end

ReturnsPages("AvatarEditorService", "InventoryPages", { "GetInventory", "GetInventoryAsync" }, RequireInventoryAccess)
ReturnsPages("AvatarEditorService", "OutfitPages", { "GetOutfits", "GetOutfitsAsync" }, RequireInventoryAccess)
ReturnsPages("AvatarEditorService", "CatalogPages", { "SearchCatalog", "SearchCatalogAsync", "GetBundlesByAssetIdAsync" })

-- (the Completed events these prompts end with can't be fired from here)
Method("AvatarEditorService", "PromptAllowInventoryReadAccess", function()
	RequireEditorClient("PromptAllowInventoryReadAccess")
	InventoryAccessGranted = true
end)

Method("AvatarEditorService", "PromptCreateOutfit", function(_, _Description, _RigType, OutfitOptions, OutfitType)
	if OutfitOptions ~= nil or OutfitType ~= nil then
		error("PromptCreateOutfit: outfitOptions and outfitType arguments are not supported yet.", 0)
	end
	RequireEditorClient("PromptCreateOutfit")
end)

for _, Name in { "PromptDeleteOutfit", "PromptRenameOutfit", "PromptSaveAvatar", "PromptUpdateOutfit" } do
	Method("AvatarEditorService", Name, function()
		RequireEditorClient(Name)
	end)
end

Method("AvatarEditorService", "PromptSetFavorite", function(_, ItemId, ItemType, ShouldFavorite)
	RequireEditorClient("PromptSetFavorite")
	Favorites[FavoriteKey(ItemId, ItemType)] = not not ShouldFavorite
end)

-- HumanoidDescription: its data is kept in the instance's own hidden properties, so Clone carries it

local RIGID_PROPERTY_BY_TYPE = {
	Hat = "HatAccessory",
	Hair = "HairAccessory",
	Face = "FaceAccessory",
	Neck = "NeckAccessory",
	Shoulder = "ShouldersAccessory",
	Front = "FrontAccessory",
	Back = "BackAccessory",
	Waist = "WaistAccessory",
}

local function ReadData(Description, Property)
	local Text = RawGet(Description, Property)
	if not Text or Text == "" then
		return {}
	end
	local Decoded, Value = JsonDecode(Text)
	return if Decoded then Value else {} -- (a script can write AccessoryBlob itself)
end

local function WriteData(Description, Property, Value)
	RawSet(Description, Property, JsonEncode(Value), true)
end

Method("HumanoidDescription", "AddEmote", function(Self, Name, AssetId)
	local Emotes = ReadData(Self, "EmotesDataInternal")
	Name = ReadString(Name, 1)
	local Ids = Emotes[Name] or {}
	local Id = tonumber(AssetId)
	if not table.find(Ids, Id) then
		table.insert(Ids, Id)
	end
	Emotes[Name] = Ids
	WriteData(Self, "EmotesDataInternal", Emotes)
end)

Method("HumanoidDescription", "RemoveEmote", function(Self, Name)
	local Emotes = ReadData(Self, "EmotesDataInternal")
	Emotes[ReadString(Name, 1)] = nil
	WriteData(Self, "EmotesDataInternal", Emotes)
end)

Method("HumanoidDescription", "GetEmotes", function(Self)
	return ReadData(Self, "EmotesDataInternal")
end)

Method("HumanoidDescription", "SetEmotes", function(Self, Emotes)
	local Kept = {}
	for Name, AssetIds in Emotes do
		if type(Name) == "string" and type(AssetIds) == "table" then
			Kept[Name] = table.clone(AssetIds)
		end
	end
	WriteData(Self, "EmotesDataInternal", Kept)
end)

Method("HumanoidDescription", "GetEquippedEmotes", function(Self)
	return ReadData(Self, "EquippedEmotesDataInternal")
end)

Method("HumanoidDescription", "SetEquippedEmotes", function(Self, Equipped)
	local Kept = {}
	for Index, Entry in Equipped do
		if type(Entry) == "string" then
			table.insert(Kept, { Name = Entry, Slot = Index })
		elseif type(Entry) == "table" then
			table.insert(Kept, { Name = Entry.Name, Slot = Entry.Slot or Index })
		end
	end
	WriteData(Self, "EquippedEmotesDataInternal", Kept)
end)

Method("HumanoidDescription", "GetAccessories", function(Self, IncludeRigid)
	local Result = ReadData(Self, "AccessoryBlob")
	for _, Entry in Result do
		Entry.AccessoryType = ResolveEnum(Enum.AccessoryType, Entry.AccessoryType)
	end
	if IncludeRigid then
		for TypeName, Property in RIGID_PROPERTY_BY_TYPE do
			for AssetId in string.gmatch(RawGet(Self, Property) or "", "%d+") do
				table.insert(Result, { AccessoryType = Enum.AccessoryType[TypeName], AssetId = tonumber(AssetId), IsLayered = false })
			end
		end
	end
	return Result
end)

Method("HumanoidDescription", "SetAccessories", function(Self, Accessories, IncludeRigid)
	local Layered = {}
	local RigidIds = {}
	for _, Entry in Accessories do
		if type(Entry) ~= "table" then
			continue
		end
		local AccessoryType = ResolveEnum(Enum.AccessoryType, Entry.AccessoryType)
		local TypeName = AccessoryType and AccessoryType.Name
		local Property = TypeName and RIGID_PROPERTY_BY_TYPE[TypeName]
		-- an entry with no Order is a rigid accessory
		if IncludeRigid and Property and Entry.Order == nil then
			RigidIds[Property] = RigidIds[Property] or {}
			table.insert(RigidIds[Property], tostring(Entry.AssetId))
		else
			local Kept = table.clone(Entry)
			Kept.AccessoryType = TypeName
			table.insert(Layered, Kept)
		end
	end
	if IncludeRigid then
		for _, Property in RIGID_PROPERTY_BY_TYPE do
			RawSet(Self, Property, table.concat(RigidIds[Property] or {}, ","), false)
		end
	end
	WriteData(Self, "AccessoryBlob", Layered)
end)

-- Humanoid (TakeDamage, MoveTo and ChangeState's simulation are not emulated)

local PART_NAME_BY_BODY_PART = {}
local BODY_PART_BY_PART_NAME = {}
for _, BodyPart in Enum.BodyPartR15:GetEnumItems() do
	if BodyPart ~= Enum.BodyPartR15.Unknown then
		local PartName = if BodyPart == Enum.BodyPartR15.RootPart then "HumanoidRootPart" else BodyPart.Name
		PART_NAME_BY_BODY_PART[BodyPart] = PartName
		BODY_PART_BY_PART_NAME[PartName] = BodyPart
	end
end

local LIMB_BY_PART_NAME = {
	Head = Enum.Limb.Head,
	Torso = Enum.Limb.Torso,
	UpperTorso = Enum.Limb.Torso,
	LowerTorso = Enum.Limb.Torso,
	["Left Arm"] = Enum.Limb.LeftArm,
	LeftUpperArm = Enum.Limb.LeftArm,
	LeftLowerArm = Enum.Limb.LeftArm,
	LeftHand = Enum.Limb.LeftArm,
	["Right Arm"] = Enum.Limb.RightArm,
	RightUpperArm = Enum.Limb.RightArm,
	RightLowerArm = Enum.Limb.RightArm,
	RightHand = Enum.Limb.RightArm,
	["Left Leg"] = Enum.Limb.LeftLeg,
	LeftUpperLeg = Enum.Limb.LeftLeg,
	LeftLowerLeg = Enum.Limb.LeftLeg,
	LeftFoot = Enum.Limb.LeftLeg,
	["Right Leg"] = Enum.Limb.RightLeg,
	RightUpperLeg = Enum.Limb.RightLeg,
	RightLowerLeg = Enum.Limb.RightLeg,
	RightFoot = Enum.Limb.RightLeg,
}

Method("Humanoid", "GetBodyPartR15", function(Self, Part)
	if Self.Parent == nil or Part.Parent ~= Self.Parent then
		error("Part does not have the same parent as Humanoid", 0)
	end
	return BODY_PART_BY_PART_NAME[Part.Name] or Enum.BodyPartR15.Unknown
end)

Method("Humanoid", "GetLimb", function(Self, Part)
	if Self.Parent == nil or Part.Parent ~= Self.Parent then
		error("Part is not a child of Humanoid", 0)
	end
	return LIMB_BY_PART_NAME[Part.Name] or Enum.Limb.Unknown
end)

Method("Humanoid", "ReplaceBodyPartR15", function(Self, BodyPart, Part)
	local PartName = PART_NAME_BY_BODY_PART[ResolveEnum(Enum.BodyPartR15, BodyPart) or Enum.BodyPartR15.Unknown]
	local Character = Self.Parent
	local Replaced = PartName and Character and Character:FindFirstChild(PartName)
	if not Replaced or Replaced == Part or not Part:IsA("BasePart") then
		return false
	end
	Part.Name = PartName
	Part.Parent = Character
	Replaced:Destroy()
	return true
end)

Method("Humanoid", "AddAccessory", function(Self, Accessory)
	if not Accessory:IsA("Accessory") then
		error("AddAccessory should be passed a valid Accessory object.", 0)
	end
	if Self.Parent then
		Accessory.Parent = Self.Parent
	end
end)

Method("Humanoid", "RemoveAccessories", function(Self)
	if not Self.Parent then
		return
	end
	for _, Accessory in ChildrenOfClass(Self.Parent, "Accessory") do
		Accessory:Destroy()
	end
end)

-- (only a player's character has a Backpack to unequip into)
local function UnequipTools(Self)
	local Character = Self.Parent
	local Player = Character and game:GetService("Players"):GetPlayerFromCharacter(Character)
	local Backpack = Player and Player:FindFirstChildOfClass("Backpack")
	if not Backpack then
		return
	end
	for _, Tool in ChildrenOfClass(Character, "Tool") do
		Tool.Parent = Backpack
	end
end

Method("Humanoid", "UnequipTools", UnequipTools)

Method("Humanoid", "EquipTool", function(Self, Tool)
	if not Tool:IsA("BackpackItem") or not Self.Parent or Tool.Parent == Self.Parent then
		return
	end
	UnequipTools(Self)
	Tool.Parent = Self.Parent
end)

Method("Humanoid", "Move", function(Self, MoveDirection)
	RawSet(Self, "MoveDirection", MoveDirection, false)
end)

Method("Humanoid", "BuildRigFromAttachments", function(Self)
	local Root = Self.Parent and Self.Parent:FindFirstChild("HumanoidRootPart")
	if not Root or not Root:IsA("BasePart") then
		error("Humanoid has no HumanoidRootPart.", 0)
	end
end)

Method("Humanoid", "GetCanCollideOnDeath", function()
	error("Humanoid:GetCanCollideOnDeath is not yet enabled", 0)
end)

Method("Humanoid", "ApplyAvatarRulesAsync", function(_, AvatarRules)
	if type(AvatarRules) ~= "table" and not (typeof(AvatarRules) == "Instance" and AvatarRules:IsA("AvatarRules")) then
		error("Argument 1 is invalid: expected an 'AvatarRules' instance or a table describing one", 0)
	end
	task.wait()
end)

local function AppliedDescription(Self)
	return Extra(Self).AppliedDescription or Self:FindFirstChildOfClass("HumanoidDescription")
end

for _, Name in { "ApplyDescription", "ApplyDescriptionAsync", "ApplyDescriptionReset", "ApplyDescriptionResetAsync" } do
	Method("Humanoid", Name, function(Self, Description)
		if not Self:IsDescendantOf(game) then
			error("Humanoid::ApplyDescription() DataModel was not available", 0)
		end
		if not Description:IsA("HumanoidDescription") then
			error("Humanoid::ApplyDescription() HumanoidDescription is not valid", 0) -- text: docs
		end
		task.wait()
		Extra(Self).AppliedDescription = Description:Clone()
	end)
end

Method("Humanoid", "GetAppliedDescription", function(Self)
	local Applied = AppliedDescription(Self)
	return if Applied then Applied:Clone() else Create("HumanoidDescription")
end)

for _, Name in { "PlayEmote", "PlayEmoteAsync" } do
	Method("Humanoid", Name, function(Self, EmoteName)
		local Emote = ReadString(EmoteName, 1)
		local Description = AppliedDescription(Self)
		if not Description or not ReadData(Description, "EmotesDataInternal")[Emote] then
			error(`No emote exists with name {Emote}`, 0)
		end
		task.wait()
		return true
	end)
end

Method("Humanoid", "GetState", function(Self)
	if Self.Health <= 0 then
		return Enum.HumanoidStateType.Dead
	end
	return Extra(Self).State or Enum.HumanoidStateType.Running
end)

local function StateEnabled(Self, State)
	local Disabled = Extra(Self).DisabledStates
	return not (Disabled and Disabled[State])
end

-- (these check their own arguments: a client takes nil and unknown names where the cast would refuse them)
Method("Humanoid", "ChangeState", function(Self, State)
	local Resolved = if State == nil then Enum.HumanoidStateType.None else ResolveEnum(Enum.HumanoidStateType, State)
	if Resolved and StateEnabled(Self, Resolved) then
		Extra(Self).State = Resolved
	end
	Missing("Humanoid", "ChangeState") -- TODO: drop once unemulated_tests.rs stops expecting it
end, true)

Method("Humanoid", "GetStateEnabled", function(Self, State)
	if State == nil then
		error("Argument 1 missing or nil", 0)
	end
	local Resolved = ResolveEnum(Enum.HumanoidStateType, State)
	return Resolved ~= nil and StateEnabled(Self, Resolved)
end, true)

Method("Humanoid", "SetStateEnabled", function(Self, State, Enabled)
	local Resolved = ResolveEnum(Enum.HumanoidStateType, State)
	if Resolved then
		local Data = Extra(Self)
		Data.DisabledStates = Data.DisabledStates or {}
		Data.DisabledStates[Resolved] = not Enabled
	end
end)

-- Statuses: the enum ones take any value without an error, the custom ones are names

local function SetStatus(Self, Key, Status, Wanted)
	if Status == nil then
		return false
	end
	local Data = Extra(Self)
	Data[Key] = Data[Key] or {}
	if (Data[Key][Status] == true) == Wanted then
		return false
	end
	Data[Key][Status] = Wanted or nil
	return true
end

local function HasStatus(Self, Key, Status)
	local Held = Extra(Self)[Key]
	return Status ~= nil and Held ~= nil and Held[Status] == true
end

for Name, Wanted in { AddStatus = true, RemoveStatus = false } do
	Method("Humanoid", Name, function(Self, Status)
		return SetStatus(Self, "Statuses", ResolveEnum(Enum.Status, Status), Wanted)
	end, true)
end

Method("Humanoid", "HasStatus", function(Self, Status)
	return HasStatus(Self, "Statuses", ResolveEnum(Enum.Status, Status))
end, true)

for Name, Wanted in { AddCustomStatus = true, RemoveCustomStatus = false } do
	Method("Humanoid", Name, function(Self, Status)
		return SetStatus(Self, "CustomStatuses", ReadString(Status, 1), Wanted)
	end)
end

Method("Humanoid", "HasCustomStatus", function(Self, Status)
	return HasStatus(Self, "CustomStatuses", ReadString(Status, 1))
end)

Method("Humanoid", "GetStatuses", function(Self)
	local Result = {}
	for Status in Extra(Self).Statuses or {} do
		table.insert(Result, Status)
	end
	return Result
end)

-- Keyframe / KeyframeSequence / Pose: each holds its items as children

local CHILD_LISTS = {
	{ "Keyframe", "AddMarker", "RemoveMarker", "GetMarkers", "KeyframeMarker" },
	{ "Keyframe", "AddPose", "RemovePose", "GetPoses", "PoseBase" },
	{ "KeyframeSequence", "AddKeyframe", "RemoveKeyframe", "GetKeyframes", "Keyframe" },
	{ "Pose", "AddSubPose", "RemoveSubPose", "GetSubPoses", "PoseBase" },
}

for _, List in CHILD_LISTS do
	local Class, Add, Remove, Get, ItemClass = table.unpack(List)
	Method(Class, Add, function(Self, Item)
		Item.Parent = Self
	end)
	Method(Class, Remove, function(Self, Item)
		if Item.Parent == Self then
			Item.Parent = nil
		end
	end)
	Method(Class, Get, function(Self)
		return ChildrenOfClass(Self, ItemClass)
	end)
end

-- PlayerViewService

Method("PlayerViewService", "GetDeviceCameraCFrame", function(_, Player)
	if IsServer then
		error("GetDeviceCameraCFrame must be called from the client", 0)
	end
	if Player == nil then
		error("No player specified", 0)
	end
	return CFrame.new()
end)

-- Players

local MAX_BAN_USERS = 50
local BAN_REASON_LIMITS = { DisplayReason = 400, PrivateReason = 1000 }

local function RequirePlayersServer(Name)
	if not IsServer then
		error(`{Name}() can only be called on the server`, 0)
	end
end

local function BanUserIds(Config)
	if type(Config.UserIds) ~= "table" then
		error("Config must contain field UserIds with type array", 0)
	end
	if #Config.UserIds == 0 or #Config.UserIds > MAX_BAN_USERS then
		error(`Config field UserIds must hold 1 to {MAX_BAN_USERS} user ids`, 0) -- text: docs
	end
	return Config.UserIds
end

Method("Players", "BanAsync", function(Self, Config)
	RequirePlayersServer("BanAsync")
	local UserIds = BanUserIds(Config)
	local Duration = Config.Duration
	if type(Duration) ~= "number" or (Duration <= 0 and Duration ~= -1) then
		error("Config must contain field Duration: -1 or a positive number of seconds", 0) -- text: docs
	end
	for Field, Limit in BAN_REASON_LIMITS do
		if type(Config[Field]) ~= "string" or #Config[Field] > Limit then
			error(`Config must contain field {Field} with type string of at most {Limit} characters`, 0) -- text: docs
		end
	end
	task.wait()
	for _, UserId in UserIds do
		local Player = Self:GetPlayerByUserId(UserId)
		if Player then
			Player:Kick(Config.DisplayReason)
		end
	end
end)

Method("Players", "UnbanAsync", function(_, Config)
	RequirePlayersServer("UnbanAsync")
	BanUserIds(Config)
	task.wait()
end)

ReturnsPages("Players", "BanHistoryPages", { "GetBanHistoryAsync" }, RequirePlayersServer) -- text: docs

Method("Players", "GetPlayerFromCharacter", function(Self, Character)
	for _, Player in Self:GetPlayers() do
		if Player.Character == Character then
			return Player
		end
	end
	return nil
end)

Method("Players", "GetCharacterAppearanceInfoAsync", function()
	task.wait()
	local BodyColors = {}
	for _, Limb in OUTFIT_LIMBS do
		BodyColors[`{string.lower(string.sub(Limb, 1, 1))}{string.sub(Limb, 2)}ColorId`] = 194
	end
	return {
		assets = {},
		bodyColors = BodyColors,
		scales = { bodyType = 0, head = 1, height = 1, proportion = 0, depth = 1, width = 1 },
		emotes = {},
		playerAvatarType = "R15",
		defaultShirtApplied = false,
		defaultPantsApplied = false,
	}
end)

Method("Players", "GetProfileConfigurationFromUserIdAsync", function()
	RequirePlayersServer("GetProfileConfigurationFromUserIdAsync") -- text: docs
	task.wait()
	return {}
end)

-- Player (the members ree knows: the dump lists none, so each checks its own arguments)

local function RequireDatatype(Value, TypeName, Argument)
	if Value == nil then
		error(`Argument {Argument} missing or nil`, 0)
	end
	if typeof(Value) ~= TypeName then
		error(`Unable to cast {typeof(Value)} to {TypeName}`, 0)
	end
end

Method("Player", "DistanceFromCharacter", function(Self, Point)
	RequireDatatype(Point, "Vector3", 1)
	local Head = Self.Character and Self.Character:FindFirstChild("Head")
	return if Head and Head:IsA("BasePart") then (Head.Position - Point).Magnitude else 0
end)

Method("Player", "IsFriendsWith", function(_, UserId)
	local Id, Message = R.Int64Argument(UserId, 1)
	if not Id then
		error(Message, 0)
	end
	return false
end)

-- (with no character Humanoid it does nothing, as in a client)
Method("Player", "Move", function(Self, WalkDirection, RelativeToCamera)
	RequireDatatype(WalkDirection, "Vector3", 1)
	local Humanoid = Self.Character and Self.Character:FindFirstChildOfClass("Humanoid")
	if Humanoid then
		Humanoid:Move(WalkDirection, not not RelativeToCamera)
	end
end)

Method("Player", "RequestStreamAroundAsync", function(_, Position, Timeout)
	RequireDatatype(Position, "Vector3", 1)
	if Timeout ~= nil then
		RequireDatatype(Timeout, "number", 2)
	end
	task.wait()
end)

-- (a server's Kick is server.luau's; its LoadCharacter stays unemulated)
if not IsServer then
	Method("Player", "Kick", function(Self)
		if Self ~= R.LocalPlayer() then
			error("Only the local player can be kicked from the client", 0) -- text: docs
		end
	end)
	for _, Name in { "LoadCharacter", "LoadCharacterAsync" } do
		Method("Player", Name, function()
			error("LoadCharacter can only be called by the backend server", 0) -- text: docs
		end)
	end
end

-- WrapDeformer / WrapTextureTransfer

local function RequireWrapParent(Deformer, Name)
	local Parent = Deformer.Parent
	if
		not Parent
		or not Parent:IsA("MeshPart")
		or not (Parent:FindFirstChildWhichIsA("WrapTarget") or Parent:FindFirstChildWhichIsA("WrapLayer"))
	then
		error(`WrapDeformer:{Name}(): WrapDeformer has no WrapTarget. Must be parented to a MeshPart with a WrapTarget or WrapLayer.`, 0)
	end
end

Method("WrapDeformer", "CreateEditableMeshAsync", function(Self)
	RequireWrapParent(Self, "CreateEditableMeshAsync")
	task.wait()
	return Create("EditableMesh")
end)

Method("WrapDeformer", "GetDeformedCFrameAsync", function(Self, TargetCFrame)
	RequireWrapParent(Self, "GetDeformedCFrameAsync")
	task.wait()
	return TargetCFrame
end)

Method("WrapTextureTransfer", "PrepareProjectionMeshDataAsync", function(Self)
	local Decal = Self.Parent
	local MeshPart = if Decal and Decal:IsA("Decal") then Decal.Parent else nil
	if not Self:IsDescendantOf(game) or not MeshPart or not MeshPart:IsA("MeshPart") or not MeshPart:FindFirstChildWhichIsA("WrapTarget") then
		error("PrepareProjectionMeshDataAsync: Expected a Decal on a MeshPart with mesh content and a valid WrapTarget in a DataModel.", 0)
	end
	task.wait()
end)

-- (a server's player has no mouse: nil, measured in a 0.748 play session's server)
if IsServer then
	Method("Player", "GetMouse", function()
		return nil
	end)
end
