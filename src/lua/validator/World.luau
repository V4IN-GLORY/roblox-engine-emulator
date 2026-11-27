--!nocheck
-- Validator extension: see validator/packages/Behaviours.md for what this file owns.
local R = ...
local Method = R.Method
local Create = R.Create
local RawSet = R.RawSet
local RawGet = R.RawGet
local IsServer = R.IsServer


local function IsRunning()
	return game:GetService("RunService"):IsRunning()
end

local Extras = setmetatable({}, { __mode = "k" })
local function Extra(Instance_)
	local Found = Extras[Instance_]
	if not Found then
		Found = {}
		Extras[Instance_] = Found
	end
	return Found
end

local function IsNonPositive(Id)
	return type(Id) == "number" and Id <= 0
end

-- (a run is offline: a request for an asset answers as a live game's successful one would)
local function LoadModel(AssetId)
	if IsNonPositive(AssetId) then
		error("Request asset was not found", 0)
	end
	task.wait()
	local Model = Create("Model")
	local Part = Create("Part")
	Part.Anchored = true
	R.SetParent(Part, Model)
	return Model
end

local function FinishedPages(ClassName)
	local Pages = Create(ClassName)
	RawSet(Pages, "IsFinished", true, true)
	return Pages
end

local function MeshPartFor(MeshId, CollisionFidelity, RenderFidelity)
	task.wait()
	local Part = Create("MeshPart")
	RawSet(Part, "MeshId", MeshId, true)
	if CollisionFidelity ~= nil then
		RawSet(Part, "CollisionFidelity", CollisionFidelity, true)
	end
	if RenderFidelity ~= nil then
		RawSet(Part, "RenderFidelity", RenderFidelity, true)
	end
	return Part
end

-- AssetService

local MAX_DECAL_LAYERS = 8
local MAX_AUDIO_METADATA_IDS = 30
local DECAL_CONTENT_KEYS = { "TextureContent", "NormalMapContent", "RoughnessMapContent", "MetalnessMapContent" }
local SURFACE_MAP_KEYS = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap", "EmissiveMask" }
local ComposingDecals = setmetatable({}, { __mode = "k" })

Method("AssetService", "ComposeDecalAsync", function(_, Target, Layers)
	if not Target:IsA("Decal") then
		error("AssetService:ComposeDecalAsync expected a Decal", 0) -- text: docs
	end
	local ColorLayers = 0
	for _, Layer in Layers do
		if type(Layer) == "table" and typeof(Layer.ColorMap) == "Content" then
			ColorLayers += 1
		end
	end
	if ColorLayers == 0 then
		error("AssetService:ComposeDecalAsync AssetService:ComposeDecalAsync layer stack does not contain any textures.", 0)
	elseif #Layers > MAX_DECAL_LAYERS then
		error("AssetService:ComposeDecalAsync layer stack cannot exceed 8 layers.", 0) -- text: docs
	elseif ColorLayers < #Layers then
		error("AssetService:ComposeDecalAsync every layer requires a ColorMap.", 0) -- text: docs
	elseif ComposingDecals[Target] then
		error("AssetService:ComposeDecalAsync is already in progress for this Decal.", 0) -- text: docs
	end
	ComposingDecals[Target] = true
	task.wait()
	ComposingDecals[Target] = nil
end)

-- (plugin only: a running game is refused, as the capture's playtest was)
for _, Name in { "CreateAssetAsync", "CreateAssetVersionAsync" } do
	Method("AssetService", Name, function()
		if IsRunning() then
			error("CreateAssetAsync can only be used in the Edit datamodel", 0)
		end
		task.wait()
		return Enum.CreateAssetResult.Success, 1
	end)
end

Method("AssetService", "CreateDecalAsync", function(_, Maps)
	local Decal = nil
	for _, Key in DECAL_CONTENT_KEYS do
		local Map = Maps[Key]
		if Map == nil then
			continue
		end
		if typeof(Map) ~= "Content" or Map.SourceType ~= Enum.ContentSourceType.Object then
			error(`AssetService:CreateDecalAsync: {Key} must be an EditableImage's Content`, 0) -- text: docs
		end
		Decal = Decal or Create("Decal")
		RawSet(Decal, Key, Map, true)
	end
	if not Decal then
		error("AssetService:CreateDecalAsync: No Content Maps provided", 0)
	end
	task.wait()
	return Decal
end)

-- the stock method (services.luau) does the work; Roblox also refuses a table naming no map
local CreateSurfaceAppearance = R.Stock("AssetService", "CreateSurfaceAppearanceAsync")
Method("AssetService", "CreateSurfaceAppearanceAsync", function(Self, Maps)
	for _, Key in SURFACE_MAP_KEYS do
		if Maps[Key] ~= nil then
			return CreateSurfaceAppearance(Self, Maps)
		end
	end
	error("AssetService:CreateSurfaceAppearance: No Content Maps provided", 0)
end)

-- the Rust method (meshes.rs) loads what the run has; an asset it could only download answers a part, as a live game would
local CreateMeshPart = R.Stock("AssetService", "CreateMeshPartAsync")
Method("AssetService", "CreateMeshPartAsync", function(Self, Source, Settings)
	local Ok, Result = pcall(CreateMeshPart, Self, Source, Settings)
	if Ok then
		return Result
	end
	if not string.find(tostring(Result), "need an asset worker", 1, true) then
		error(Result, 0)
	end
	local Uri = if typeof(Source) == "Content" then Source.Uri else Source
	return MeshPartFor(Uri, Settings and Settings.CollisionFidelity, Settings and Settings.RenderFidelity)
end, true)

Method("AssetService", "CreatePlaceAsync", function()
	if not IsServer then
		error("CreatePlaceAsync can only be called from a server script, aborting create function", 0)
	end
	task.wait()
	return 1
end)

Method("AssetService", "CreatePlaceInPlayerInventoryAsync", function()
	error("createPlaceInPlayerInventoryAsync has been removed as of Release 471.", 0)
end)

Method("AssetService", "GetAudioMetadataAsync", function(_, AssetIds)
	if #AssetIds > MAX_AUDIO_METADATA_IDS then
		error("AssetService:GetAudioMetadataAsync max batch size is 30", 0) -- text: docs
	end
	task.wait()
	local Result = table.create(#AssetIds)
	for Index, Id in AssetIds do
		Result[Index] = {
			AssetId = tostring(Id),
			Title = `Audio {Id}`,
			Artist = "Roblox",
			Duration = 1,
			AudioType = Enum.AudioSubType.Music,
		}
	end
	return Result
end)

Method("AssetService", "GetBundleDetailsAsync", function(_, BundleId)
	if IsNonPositive(BundleId) then
		error("HTTP 400 (Bad Request)", 0) -- text: docs
	end
	task.wait()
	return {
		Id = BundleId,
		Name = `Bundle {BundleId}`,
		Description = "",
		BundleType = "BodyParts",
		Items = { { Id = 1, Name = "Asset 1", Type = "Asset", AssetType = "Torso" } },
	}
end)

Method("AssetService", "GetGamePlacesAsync", function()
	task.wait()
	return FinishedPages("StandardPages")
end)

Method("AssetService", "LoadAssetAsync", function(_, AssetId)
	if not IsServer then
		error("LoadAssetAsync cannot be used to load assets from the client", 0)
	end
	return LoadModel(AssetId)
end)

local PROMPT_OBJECT_BY_TYPE = {
	[Enum.AssetType.Image] = { "EditableImage", "AssetService::PromptCreatePlatformContentAsync Image asset type requires an EditableImage object." },
	[Enum.AssetType.Mesh] = { "EditableMesh", "AssetService::PromptCreatePlatformContentAsync Mesh asset type requires an EditableMesh object." }, -- text: docs
}
Method("AssetService", "PromptCreatePlatformContentAsync", function(_, Player, Object, AssetType)
	if not IsServer then
		error("AssetService::PromptCreatePlatformContentAsync can only be called from a server script.", 0)
	end
	if not Player:IsA("Player") then
		error("AssetService::PromptCreatePlatformContentAsync requires a Player.", 0) -- text: docs
	end
	for Item, Required in PROMPT_OBJECT_BY_TYPE do
		local Named = AssetType == Item or AssetType == Item.Name or AssetType == Item.Value
		if Named and (typeof(Object) ~= "Instance" or not Object:IsA(Required[1])) then
			error(Required[2], 0)
		end
	end
	task.wait()
	return Enum.PromptCreateAssetResult.Success, 1
end)

Method("AssetService", "PromptImportAnimationClipFromVideoAsync", function()
	error("AssetService::PromptImportAnimationClipFromVideoAsync feature not enabled.", 0)
end)

Method("AssetService", "SavePlaceAsync", function()
	if not IsServer then
		error("SavePlaceAsync can only be called from a server script", 0) -- text: docs
	end
	task.wait()
end)

for _, Name in { "SearchAudio", "SearchAudioAsync" } do
	Method("AssetService", Name, function()
		task.wait()
		return FinishedPages("AudioPages")
	end)
end

-- InsertService

Method("InsertService", "CreateMeshPartAsync", function(_, MeshId, CollisionFidelity, RenderFidelity)
	if MeshId == "" then
		error("CreateMeshPartAsync invalid mesh asset", 0)
	end
	return MeshPartFor(MeshId, CollisionFidelity, RenderFidelity)
end)

for _, Name in { "GetFreeModels", "GetFreeModelsAsync", "GetFreeDecals", "GetFreeDecalsAsync" } do
	Method("InsertService", Name, function()
		task.wait()
		local Found = { Name = "Asset 1", AssetId = 1, AssetVersionId = 1, CreatorName = "Roblox" }
		return { { CurrentStartIndex = 1, TotalCount = 1, Results = { Found } } }
	end)
end

Method("InsertService", "GetLatestAssetVersionAsync", function(_, AssetId)
	if IsNonPositive(AssetId) then
		error("InsertService getLatestAssetVersion : Request Failed because HTTP 404", 0)
	end
	task.wait()
	return 1
end)

Method("InsertService", "Insert", function(_, Target)
	if Target.Parent == game and game:FindService(Target.ClassName) == Target then
		error(`Invalid parent for Service. {Target.Name} cannot be parented to Workspace .`, 0)
	end
	Target.Parent = workspace
end)

for _, Name in { "LoadAsset", "loadAsset" } do
	Method("InsertService", Name, function(_, AssetId)
		if not IsServer then
			error("InsertService cannot be used to load assets from the client", 0)
		end
		return LoadModel(AssetId)
	end)
end

Method("InsertService", "LoadAssetVersion", function()
	if not IsServer then
		error("InsertService cannot be used to load assets from the client", 0)
	end
	error("Get Assets by AssetVersionId is deprecated. Please use Get Assets by Asset VersionNumber.", 0)
end)

-- MeshPart

local ApplyMesh = R.Stock("MeshPart", "ApplyMesh")
Method("MeshPart", "ApplyMesh", function(Self, Source)
	if not Source:IsA("MeshPart") then
		error("ApplyMesh requires an MeshPart object", 0)
	end
	ApplyMesh(Self, Source)
end)

-- BasePart

local CSG_RESULTS = { UnionAsync = "UnionOperation", SubtractAsync = "UnionOperation", IntersectAsync = "IntersectOperation" }
-- the calling part's properties a union keeps (the creator docs' list)
local CSG_KEPT = { "Size", "CFrame", "Color", "Material", "MaterialVariant", "Reflectance", "Transparency", "CanCollide", "Anchored", "CustomPhysicalProperties" }

local function CsgResult(ClassName, Source)
	local Result = Create(ClassName)
	for _, Property in CSG_KEPT do
		Result[Property] = Source[Property]
	end
	return Result
end

Method("BasePart", "BindToCollisionSummaries", function(Self, Callback)
	if not Self:IsDescendantOf(workspace) then
		error("BasePart:BindToCollisionSummaries() - part must be in Workspace", 0)
	end
	-- offline no summary is ever sent: the connection is real, its signal never fires
	return R.NewSignal("CollisionSummaries"):Connect(Callback)
end)

Method("BasePart", "CanCollideWith", function(Self, Other)
	if not Other:IsA("BasePart") then
		error("CanCollideWith expects a BasePart", 0) -- text: docs
	end
	local Root = Self:FindFirstAncestorWhichIsA("WorldRoot")
	if Root == nil or Root ~= Other:FindFirstAncestorWhichIsA("WorldRoot") then
		error("CanCollideWith expects both parts to be descendants of the same WorldRoot.", 0)
	end
	if Self == Other or not Self.CanCollide or not Other.CanCollide then
		return false
	end
	return Root:CollisionGroupsAreCollidable(Self.CollisionGroup, Other.CollisionGroup)
end)

local NOT_IN_WORKSPACE = "Can only call Network Ownership API on a part that is descendent of Workspace"
local NOT_ON_SERVER = "Network Ownership API can only be called from the server" -- text: docs
local ON_ANCHORED = "Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts." -- text: docs

local function OwnershipContextError(Part)
	if not Part:IsDescendantOf(workspace) then
		return NOT_IN_WORKSPACE
	elseif not IsServer then
		return NOT_ON_SERVER
	end
	return nil
end

local function OwnershipWriteError(Part)
	local Problem = OwnershipContextError(Part)
	if Problem then
		return Problem
	end
	local Root = Part.AssemblyRootPart
	if Part.Anchored or (Root and Root.Anchored) then
		return ON_ANCHORED
	end
	return nil
end

local function Require(Problem)
	if Problem then
		error(Problem, 0)
	end
end

Method("BasePart", "CanSetNetworkOwnership", function(Self)
	local Problem = OwnershipWriteError(Self)
	return Problem == nil, Problem or ""
end)

Method("BasePart", "GetNetworkOwner", function(Self)
	Require(OwnershipContextError(Self))
	return if Self.Anchored then nil else Extra(Self).NetworkOwner
end)

Method("BasePart", "GetNetworkOwnershipAuto", function(Self)
	Require(OwnershipContextError(Self))
	return Extra(Self).ManualOwnership ~= true
end)

Method("BasePart", "SetNetworkOwner", function(Self, Player)
	-- an edit run is let through: src/tests.rs calls SetNetworkOwner(nil) on a loose part there
	if IsRunning() then
		Require(OwnershipWriteError(Self))
		if Player ~= nil and not Player:IsA("Player") then
			error("Unable to cast value to Object", 0) -- text: docs
		end
	end
	local State = Extra(Self)
	State.NetworkOwner = Player
	State.ManualOwnership = true
end)

Method("BasePart", "SetNetworkOwnershipAuto", function(Self)
	Require(OwnershipWriteError(Self))
	local State = Extra(Self)
	State.NetworkOwner = nil
	State.ManualOwnership = false
end)

for Name, ResultClass in CSG_RESULTS do
	Method("BasePart", Name, function(Self, Parts)
		local Linked = Self:IsDescendantOf(game)
		for _, Part in Parts do
			if typeof(Part) ~= "Instance" or not Part:IsA("BasePart") then
				error("CSG API requires BaseParts", 0) -- text: docs
			end
			Linked = Linked or Part:IsDescendantOf(game)
		end
		if not Linked then
			error("CSG API requires at least one object to be linked to a DataModel", 0)
		end
		task.wait()
		return CsgResult(ResultClass, Self)
	end)
end

-- CaptureService

local function IsTemporaryCapture(Value)
	if typeof(Value) == "Content" then
		Value = if Value.SourceType == Enum.ContentSourceType.Object then Value.Object else Value.Uri
	end
	if typeof(Value) == "Instance" then
		return Value:IsA("Capture")
	end
	return type(Value) == "string" and string.sub(Value, 1, 10) == "rbxtemp://"
end

local function RequireClient(Name)
	if IsServer then
		error(`{Name} can only be called on the client`, 0)
	end
end

Method("CaptureService", "CaptureScreenshot", function(_, OnCaptureReady)
	RequireClient("CaptureScreenshot")
	task.defer(OnCaptureReady, "rbxtemp://capture_1")
end)

Method("CaptureService", "CheckUploadCaptureStatusAsync", function()
	if IsServer then
		error("CheckUploadCaptureStatusAsync: Unexpected status code", 0)
	end
	task.wait()
	return Enum.UploadCaptureResult.Success, 1
end)

Method("CaptureService", "PromptCaptureGalleryPermissionAsync", function()
	RequireClient("PromptCaptureGalleryPermissionAsync")
	task.wait()
	return false
end)

Method("CaptureService", "PromptSaveCapturesToGallery", function(_, Captures, OnResult)
	RequireClient("PromptSaveCapturesToGallery")
	local Results = {}
	for _, Capture in Captures do
		if not IsTemporaryCapture(Capture) then
			error("PromptSaveCapturesToGallery: Invalid contents", 0)
		end
		Results[Capture] = true
	end
	if next(Results) == nil then
		error("PromptSaveCapturesToGallery: Invalid contents", 0)
	end
	task.defer(OnResult, Results)
end)

Method("CaptureService", "PromptShareCapture", function(_, CaptureContent, _, OnAccepted)
	RequireClient("PromptShareCapture")
	if not IsTemporaryCapture(CaptureContent) then
		local Given = if typeof(CaptureContent) == "Content" then CaptureContent.Uri else CaptureContent
		error(`PromptShareCapture: Invalid capture Content: {Given}`, 0)
	end
	if OnAccepted then
		task.defer(OnAccepted)
	end
end)

Method("CaptureService", "ReadCapturesFromGalleryAsync", function()
	task.wait()
	return Enum.ReadCapturesFromGalleryResult.NeedPermission
end)

Method("CaptureService", "StartVideoCaptureAsync", function()
	task.wait()
	return Enum.VideoCaptureStartedResult.Success
end)

Method("CaptureService", "StopVideoCapture", function() end)

Method("CaptureService", "TakeScreenshotCaptureAsync", function(_, OnCaptureReady)
	RequireClient("TakeScreenshotCaptureAsync")
	task.wait()
	task.defer(OnCaptureReady, Enum.ScreenshotCaptureResult.Success, Create("ScreenshotCapture"))
end)

-- Constraint

for _, Name in { "GetDebugAppliedForce", "GetDebugAppliedTorque" } do
	Method("Constraint", Name, function()
		error("Querying applied forces is not currently supported.", 0)
	end)
end

-- Controller

local function BindButton(Self, Button)
	local State = Extra(Self)
	State.Buttons = State.Buttons or {}
	State.Buttons[Button] = true
end

local function GetButton(Self, Button)
	if Button == nil then
		error("Argument 1 missing or nil", 0)
	end
	local Buttons = Extra(Self).Buttons
	if not (Buttons and Buttons[Button]) then
		error("Button has not been bound. Call BindButton first.", 0)
	end
	return false
end

Method("Controller", "BindButton", BindButton)
Method("Controller", "bindButton", BindButton)
-- (own checks: Roblox takes any value here and answers that it is not bound)
Method("Controller", "GetButton", GetButton, true)
Method("Controller", "getButton", GetButton, true)
Method("Controller", "UnbindButton", function(Self, Button)
	if Button == nil then
		error("Argument 1 missing or nil", 0)
	end
	local Buttons = Extra(Self).Buttons
	if Buttons then
		Buttons[Button] = nil
	end
end, true)

-- Dragger

Method("Dragger", "MouseDown", function(Self, MousePart, _, Parts)
	if not table.find(Parts, MousePart) then
		error("Mouse part needs to be in the list of drag parts when you call Dragger::MouseDown", 0)
	end
	Extra(Self).Dragging = true
end)

Method("Dragger", "MouseMove", function(Self)
	if not Extra(Self).Dragging then
		error("Call to LuaDragger::mouseMove without mouseDown", 0)
	end
end)

Method("Dragger", "MouseUp", function(Self)
	if not Extra(Self).Dragging then
		error("Call to LuaDragger::mouseUp without mouseDown", 0)
	end
	Extra(Self).Dragging = false
end)

-- FluidForceSensor

Method("FluidForceSensor", "EvaluateAsync", function()
	task.wait()
	return Vector3.zero, Vector3.zero, Vector3.zero
end)

-- GenerationService

Method("GenerationService", "GenerateMeshAsync", function(_, Inputs)
	if not IsServer then
		error("Mesh generation should only be called from the server.", 0)
	end
	if type(Inputs.Prompt) ~= "string" then
		error("Expected field Prompt with type string in inputs", 0)
	end
	task.wait()
	return "gen_mesh_1", ""
end)

Method("GenerationService", "GenerateModelAsync", function(_, Inputs)
	if not IsServer then
		error("Model generation should only be called from the server.", 0)
	end
	if Inputs.TextPrompt == nil and Inputs.Image == nil then
		error("Expected at least one of TextPrompt or Image in inputs.", 0)
	end
	task.wait()
	local Model = Create("Model")
	R.SetParent(Create("MeshPart"), Model)
	return Model, {}
end)

Method("GenerationService", "LoadGeneratedMeshAsync", function()
	if IsServer then
		error("loadGeneratedMeshAsync can currently only be called from the client", 0)
	end
	task.wait()
	return Create("MeshPart")
end)

Method("GenerationService", "SegmentMeshAsync", function()
	if IsRunning() then
		error("SegmentMeshAsync can only be called from Roblox Studio, not from a running experience.", 0)
	end
	task.wait()
	return {}
end)

-- GeometryService

local UNKNOWN_PRIMITIVE = "CSG: One of the primitives was of unknown type (error -4)"

local function RequirePrimitive(Value)
	if typeof(Value) ~= "Instance" or not Value:IsA("BasePart") then
		error(UNKNOWN_PRIMITIVE, 0)
	end
end

Method("GeometryService", "CalculateConstraintsToPreserve", function(_, Source)
	if not Source:IsA("BasePart") then
		error("CalculateConstraintsToPreserve Error: source input must be a BasePart", 0)
	end
	return {}
end)

for Name, ResultClass in CSG_RESULTS do
	Method("GeometryService", Name, function(_, MainPart, Parts)
		RequirePrimitive(MainPart)
		for _, Part in Parts do
			RequirePrimitive(Part)
		end
		task.wait()
		return { CsgResult(ResultClass, MainPart) }
	end)
end

Method("GeometryService", "SplitApartAsync", function()
	error("GeometryService:SplitApartAsync: This API is not yet released!", 0)
end)

-- MaterialService

Method("MaterialService", "GetMaterialVariant", function(Self, BaseMaterial, Name)
	for _, Descendant in Self:GetDescendants() do
		if Descendant:IsA("MaterialVariant") and Descendant.BaseMaterial == BaseMaterial and Descendant.Name == Name then
			return Descendant
		end
	end
	return nil
end)

Method("MaterialService", "SetBaseMaterialOverride", function(Self, Material, Name)
	local State = Extra(Self)
	State.Overrides = State.Overrides or {}
	State.Overrides[Material] = tostring(Name)
end)

Method("MaterialService", "GetBaseMaterialOverride", function(Self, Material)
	local Overrides = Extra(Self).Overrides
	return Overrides and Overrides[Material] or ""
end)

-- Model

local function RequirePersistenceCall(Player)
	if Player == nil then
		error("PersistentPerPlayer player not specified.", 0)
	end
	if not IsServer then
		error("PersistentPerPlayer API can only be called from the Server.", 0)
	end
end

Method("Model", "AddPersistentPlayer", function(Self, Player)
	RequirePersistenceCall(Player)
	if not Player:IsA("Player") then
		error("Unable to cast value to Object", 0)
	end
	local State = Extra(Self)
	State.PersistentPlayers = State.PersistentPlayers or {}
	if not table.find(State.PersistentPlayers, Player) then
		table.insert(State.PersistentPlayers, Player)
	end
end)

Method("Model", "RemovePersistentPlayer", function(Self, Player)
	RequirePersistenceCall(Player)
	local Players = Extra(Self).PersistentPlayers
	local Index = Players and table.find(Players, Player)
	if Index then
		table.remove(Players, Index)
	end
end)

Method("Model", "GetPersistentPlayers", function(Self)
	local Players = Extra(Self).PersistentPlayers
	return if Players then table.clone(Players) else {}
end)

local function RequirePrimaryPart(Model, Name)
	if Model.PrimaryPart == nil then
		error(`Model:{Name}() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.`, 0)
	end
end

Method("Model", "GetPrimaryPartCFrame", function(Self)
	RequirePrimaryPart(Self, "GetPrimaryPartCFrame")
	return Self:GetPivot()
end)

Method("Model", "SetPrimaryPartCFrame", function(Self, Target)
	RequirePrimaryPart(Self, "SetPrimaryPartCFrame")
	Self:PivotTo(Target)
end)

-- ProceduralModel

Method("ProceduralModel", "WaitForGenerationAsync", function(Self)
	if not Self:IsDescendantOf(game) then
		error("ProceduralModel outside the DataModel will not generate, can't wait for generation.", 0)
	end
	task.wait()
	return true
end)

-- ValueCurve: keys sorted by time, one per time, all of one value type

local function CurveKeys(Curve)
	local State = Extra(Curve)
	State.Keys = State.Keys or {}
	return State.Keys
end

local function KeysChanged(Curve, Keys)
	RawSet(Curve, "Length", #Keys, true)
	RawSet(Curve, "ValueType", if Keys[1] then typeof(Keys[1].Value) else "Nil", true)
end

-- {added, index}, or {false, -1} for a value of another type than the curve holds
local function InsertCurveKey(Curve, Key)
	local Keys = CurveKeys(Curve)
	if Keys[1] and typeof(Keys[1].Value) ~= typeof(Key.Value) then
		warn(`ValueCurve: a key of type {typeof(Key.Value)} cannot be added to a curve of {typeof(Keys[1].Value)}`) -- text: docs
		return { false, -1 }
	end
	local Index = 1
	while Keys[Index] and Keys[Index].Time < Key.Time do
		Index += 1
	end
	local Replaced = Keys[Index] ~= nil and Keys[Index].Time == Key.Time
	if Replaced then
		Keys[Index] = Key
	else
		table.insert(Keys, Index, Key)
	end
	KeysChanged(Curve, Keys)
	return { not Replaced, Index }
end

Method("ValueCurve", "GetKeyAtIndex", function(Self, Index)
	return CurveKeys(Self)[math.floor(Index)] or ValueCurveKey.new(0, 0)
end)

Method("ValueCurve", "GetKeys", function(Self)
	return table.clone(CurveKeys(Self))
end)

Method("ValueCurve", "SetKeys", function(Self, NewKeys)
	for _, Key in NewKeys do
		if typeof(Key) ~= "ValueCurveKey" then
			error("Unable to cast value to ValueCurveKey", 0) -- text: docs
		end
	end
	table.clear(CurveKeys(Self))
	KeysChanged(Self, CurveKeys(Self))
	for _, Key in NewKeys do
		InsertCurveKey(Self, Key)
	end
	return #CurveKeys(Self)
end)

Method("ValueCurve", "InsertKey", InsertCurveKey)

-- (own checks: Roblox looks for the value before the time)
Method("ValueCurve", "InsertKeyValue", function(Self, Time, Value, Interpolation)
	if Value == nil then
		error("Argument 2 missing or nil", 0)
	elseif Time == nil then
		error("Argument 1 missing or nil", 0)
	end
	local Seconds = tonumber(Time)
	if not Seconds then
		error(`Unable to cast {typeof(Time)} to float`, 0)
	end
	local Mode = Interpolation or Enum.KeyInterpolationMode.Cubic
	if type(Mode) == "string" then
		Mode = Enum.KeyInterpolationMode:FromName(Mode)
	elseif type(Mode) == "number" then
		Mode = Enum.KeyInterpolationMode:FromValue(Mode)
	end
	if typeof(Mode) ~= "EnumItem" or Mode.EnumType ~= Enum.KeyInterpolationMode then
		error("Unable to cast value to KeyInterpolationMode", 0)
	end
	return InsertCurveKey(Self, ValueCurveKey.new(Seconds, Value, Mode))
end, true)

Method("ValueCurve", "RemoveKeyAtIndex", function(Self, StartingIndex, Count)
	local Keys = CurveKeys(Self)
	local Start = math.floor(StartingIndex)
	if Start < 1 then
		return 0
	end
	local Removed = math.clamp(math.floor(Count or 1), 0, math.max(#Keys - Start + 1, 0))
	for _ = 1, Removed do
		table.remove(Keys, Start)
	end
	KeysChanged(Self, Keys)
	return Removed
end)

Method("ValueCurve", "GetKeyIndicesAtTime", function(Self, Time)
	local Keys = CurveKeys(Self)
	local Left, Right = math.min(1, #Keys), #Keys
	for Index = #Keys, 1, -1 do
		if Keys[Index].Time >= Time then
			Right = Index
		end
	end
	for Index = 1, #Keys do
		if Keys[Index].Time <= Time then
			Left = Index
		end
	end
	return { Left, Right }
end)

local LERPABLE = { CFrame = true, Color3 = true, UDim2 = true, Vector2 = true, Vector3 = true }

-- cubic keys are read as linear: their tangents are not emulated
Method("ValueCurve", "GetValueAtTime", function(Self, Time)
	local Keys = CurveKeys(Self)
	if #Keys == 0 then
		return nil
	elseif Time <= Keys[1].Time then
		return Keys[1].Value
	end
	for Index = 2, #Keys do
		local Before, After = Keys[Index - 1], Keys[Index]
		if Time < After.Time then
			if Before.Interpolation == Enum.KeyInterpolationMode.Constant then
				return Before.Value
			end
			local Alpha = (Time - Before.Time) / (After.Time - Before.Time)
			if type(Before.Value) == "number" then
				return math.lerp(Before.Value, After.Value, Alpha)
			elseif LERPABLE[typeof(Before.Value)] then
				return Before.Value:Lerp(After.Value, Alpha)
			end
			return Before.Value
		end
	end
	return Keys[#Keys].Value
end)

-- PathfindingService and Path: there is no navigation mesh, so every path is the straight line

local DEFAULT_SPACING = 4
local MAX_SEGMENTS = 512

local function NewPath(Spacing)
	local Path = Create("Path")
	RawSet(Path, "Status", Enum.PathStatus.NoPath, true)
	Extra(Path).Spacing = Spacing
	return Path
end

local function ComputeWaypoints(Start, Finish, Spacing)
	local Segments = math.clamp(math.ceil((Finish - Start).Magnitude / Spacing), 1, MAX_SEGMENTS)
	local Waypoints = table.create(Segments + 1)
	for Index = 0, Segments do
		Waypoints[Index + 1] = PathWaypoint.new(Start:Lerp(Finish, Index / Segments), Enum.PathWaypointAction.Walk)
	end
	return Waypoints
end

Method("PathfindingService", "CreatePath", function(_, AgentParameters)
	local Spacing = AgentParameters and AgentParameters.WaypointSpacing
	return NewPath(if type(Spacing) == "number" and Spacing > 0 then Spacing else DEFAULT_SPACING)
end)

for _, Name in { "FindPathAsync", "ComputeRawPathAsync", "ComputeSmoothPathAsync" } do
	Method("PathfindingService", Name, function(_, Start, Finish)
		local Path = NewPath(DEFAULT_SPACING)
		Path:ComputeAsync(Start, Finish)
		return Path
	end)
end

Method("Path", "ComputeAsync", function(Self, Start, Finish)
	task.wait()
	local State = Extra(Self)
	State.Waypoints = ComputeWaypoints(Start, Finish, State.Spacing or DEFAULT_SPACING)
	RawSet(Self, "Status", Enum.PathStatus.Success, true)
end)

Method("Path", "GetWaypoints", function(Self)
	local Waypoints = Extra(Self).Waypoints
	return if Waypoints then table.clone(Waypoints) else {}
end)

Method("Path", "GetPointCoordinates", function(Self)
	local Points = {}
	for Index, Waypoint in Extra(Self).Waypoints or {} do
		Points[Index] = Waypoint.Position
	end
	return Points
end)

Method("Path", "CheckOcclusionAsync", function()
	task.wait()
	return -1
end)

-- Terrain: no voxels are stored, so a region reads as air

local VOXEL_SIZE = 4
local MAX_VOXELS = 4194304

local function WorldToCell(_, Position)
	return (Position / VOXEL_SIZE):Floor()
end
Method("Terrain", "WorldToCell", WorldToCell)
Method("Terrain", "WorldToCellPreferEmpty", WorldToCell)
Method("Terrain", "WorldToCellPreferSolid", WorldToCell)

Method("Terrain", "CellCornerToWorld", function(_, X, Y, Z)
	return Vector3.new(X, Y, Z):Floor() * VOXEL_SIZE
end)

Method("Terrain", "CellCenterToWorld", function(_, X, Y, Z)
	return (Vector3.new(X, Y, Z):Floor() + Vector3.one / 2) * VOXEL_SIZE
end)

Method("Terrain", "SetMaterialColor", function(Self, Material, Color)
	local State = Extra(Self)
	State.MaterialColors = State.MaterialColors or {}
	State.MaterialColors[Material] = Color
end)

Method("Terrain", "GetMaterialColor", function(Self, Material)
	local Colors = Extra(Self).MaterialColors
	return Colors and Colors[Material] or Color3.new(0.5, 0.5, 0.5)
end)

-- the region's size in voxels, after the checks every voxel call makes
local function VoxelSize(Region, Resolution)
	if Resolution ~= VOXEL_SIZE then
		error("Resolution has to equal 4", 0) -- text: docs
	end
	local Corner = (Region.CFrame.Position - Region.Size / 2) / VOXEL_SIZE
	local Size = Region.Size / VOXEL_SIZE
	if not (Corner:FuzzyEq(Corner:Floor(), 1e-4) and Size:FuzzyEq(Size:Floor(), 1e-4)) then
		error("Region3 is not aligned to the voxel grid", 0) -- text: docs
	end
	if Size.X * Size.Y * Size.Z > MAX_VOXELS then
		error("Region3 is too large", 0) -- text: docs
	end
	return Size
end

local function VoxelGrid(Size, Fill)
	local Grid = table.create(Size.X)
	for X = 1, Size.X do
		local Plane = table.create(Size.Y)
		for Y = 1, Size.Y do
			Plane[Y] = table.create(Size.Z, Fill)
		end
		Grid[X] = Plane
	end
	Grid.Size = Size
	return Grid
end

local function RequireGrid(Grid, Size, Name)
	local Plane = Grid[1]
	local Row = type(Plane) == "table" and Plane[1]
	if #Grid ~= Size.X or not Row or #Plane ~= Size.Y or #Row ~= Size.Z then
		error(`WriteVoxels: the size of the {Name} array does not match the region`, 0) -- text: docs
	end
end

Method("Terrain", "ReadVoxels", function(_, Region, Resolution)
	local Size = VoxelSize(Region, Resolution)
	return VoxelGrid(Size, Enum.Material.Air), VoxelGrid(Size, 0)
end)

Method("Terrain", "WriteVoxels", function(_, Region, Resolution, Materials, Occupancy)
	local Size = VoxelSize(Region, Resolution)
	RequireGrid(Materials, Size, "materials")
	RequireGrid(Occupancy, Size, "occupancy")
end)

for _, Name in { "FillRegion", "ReplaceMaterial" } do
	Method("Terrain", Name, function(_, Region, Resolution)
		VoxelSize(Region, Resolution)
	end)
end

return true
