--!nocheck
-- Validator extension (Commerce): see validator/packages/Behaviours.md for what this file owns.
local R = ...
local Method = R.Method
local Create = R.Create
local RawSet = R.RawSet
local IsServer = R.IsServer
local LocalPlayer = R.LocalPlayer
local CastStringParam = R.StringParam

local UuidCounter = 0
local function NextUuid()
	UuidCounter += 1
	return string.format("00000000-0000-4000-8000-%012x", UuidCounter)
end

local function ReadStringParam(Value, Argument)
	if type(Value) == "string" then
		return Value
	elseif Value == nil then
		error(`Argument {Argument} missing or nil`, 0)
	end
	return CastStringParam(Value, Argument)
end

local function IsPlayer(Value)
	return typeof(Value) == "Instance" and Value:IsA("Player")
end

local function IsUuid(Value)
	if type(Value) ~= "string" then
		return false
	end
	local Inner = string.match(Value, "^%{(.+)%}$") or Value
	return string.match(Inner, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local function IsSubscriptionId(Value)
	return type(Value) == "string" and string.match(Value, "^EXP%-%d+$") ~= nil
end

local function IsCommerceProductId(Value)
	return type(Value) == "string" and (string.match(Value, "^%d+$") ~= nil or string.match(Value, "^COM%-+[%w%-]+$") ~= nil)
end

local function IsEventId(Value)
	return type(Value) == "string" and string.match(Value, "^%d+$") ~= nil
end

local function CloneValue(Value)
	if type(Value) == "table" then
		local Copy = {}
		for Key, Item in next, Value do
			Copy[Key] = CloneValue(Item)
		end
		return Copy
	end
	return Value
end

-- Pages (base class: StandardPages, RecommendationPages, DataStoreListingPages, etc.;
-- server.luau keeps its own subclass methods on DataStorePages / DataStoreVersionPages /
-- DataStoreKeyPages / MemoryStoreHashMapPages)

local PageLists = setmetatable({}, { __mode = "k" })

local function MakePages(ClassName, Items, PageSize)
	local Pages = Create(ClassName)
	local Size = if type(PageSize) == "number" and PageSize > 0 then math.floor(PageSize) else 50
	local List = {}
	for Index = 1, #Items, Size do
		table.insert(List, table.move(Items, Index, math.min(Index + Size - 1, #Items), 1, {}))
	end
	if #List == 0 then
		List[1] = {}
	end
	PageLists[Pages] = { List = List, Index = 1 }
	RawSet(Pages, "IsFinished", #List <= 1, true)
	return Pages
end

Method("Pages", "GetCurrentPage", function(Self)
	local Pages = PageLists[Self]
	if not Pages then
		return {}
	end
	local Copy = {}
	for Index, Item in Pages.List[Pages.Index] do
		Copy[Index] = if type(Item) == "table" then CloneValue(Item) else Item
	end
	return Copy
end)

Method("Pages", "AdvanceToNextPageAsync", function(Self)
	local Pages = PageLists[Self]
	if not Pages or Pages.Index >= #Pages.List then
		error("No pages to advance to", 0)
	end
	task.wait()
	Pages.Index += 1
	RawSet(Self, "IsFinished", Pages.Index >= #Pages.List, true)
end)

-- AdService

local EligibleCampaigns = {}

local function MakeAdReward(DevProductId)
	local Reward = newproxy(true)
	local Meta = getmetatable(Reward)
	Meta.__type = "AdReward"
	Meta.__index = function(_, Key)
		if Key == "ReferenceId" then
			return tostring(DevProductId)
		end
		error(`{Key} is not a valid member of AdReward`, 0)
	end
	Meta.__tostring = function()
		return `AdReward({DevProductId})`
	end
	Meta.__metatable = "The metatable is locked"
	return Reward
end

Method("AdService", "CreateAdRewardFromDevProductId", function(_, DevProductId)
	return MakeAdReward(DevProductId)
end)

Method("AdService", "GetAdAvailabilityNowAsync", function(_, _AdFormat)
	if IsServer or LocalPlayer() == nil then
		error("Local player is not available", 0)
	end
	task.wait()
	return { AdAvailabilityResult = Enum.AdAvailabilityResult.IsAvailable }
end)

Method("AdService", "GetCampaignEligibilityAsync", function(_, CampaignId, Player)
	if IsServer then
		if not IsPlayer(Player) then
			error("GetCampaignEligibilityAsync must be called with a valid player on the server", 0)
		end
	elseif Player ~= nil and not IsPlayer(Player) then
		error("Unable to cast value to Object", 0)
	end
	task.wait()
	if type(CampaignId) == "string" and #CampaignId > 0 then
		EligibleCampaigns[CampaignId] = true
	end
	return { IsEligible = true }
end)

Method("AdService", "RegisterAdOpportunityAsync", function(_, _Target, _PlacementId)
	if IsServer then
		error("RegisterAdOpportunityAsync can only be called from the client.", 0)
	end
	task.wait()
end)

Method("AdService", "RegisterDisclosureButton", function(_, Button, PlacementId)
	if IsServer then
		error("RegisterDisclosureButton may only be called on the client", 0)
	end
	if typeof(Button) ~= "Instance" or not Button:IsA("GuiButton") then
		error("Instance must be a GuiButton", 0) -- text: docs
	end
	local Id = tostring(PlacementId)
	if not EligibleCampaigns[Id] then
		error(`Missing associated campaign eligibility status for placement "{Id}". Make sure GetCampaignEligibilityAsync for your campaign succeeded and the user is eligible`, 0)
	end
end)

Method("AdService", "RegisterImpressionSource", function(_, Target, _PlacementId)
	if IsServer then
		error("RegisterImpressionSource may only be called on the client", 0)
	end
	if typeof(Target) ~= "Instance" or not Target:IsA("BasePart") then
		error("Instance must be a Part", 0)
	end
end)

Method("AdService", "ShowRewardedVideoAdAsync", function(_, Player, _Reward, _PlacementId)
	if not IsServer then
		error("ShowRewardedVideoAdAsync can only be called from the server", 0) -- text: docs
	end
	if not IsPlayer(Player) then
		error("First argument to ShowRewardedVideoAdAsync must be a Player", 0) -- text: docs
	end
	task.wait()
	return Enum.ShowAdResult.ShowCompleted
end)

Method("AdService", "UnregisterAdOpportunity", function(_, _Target) end)

-- BadgeService

local AwardedBadges = {}

local function HasAwardedBadge(UserId, BadgeId)
	local UserBadges = AwardedBadges[UserId]
	return UserBadges ~= nil and UserBadges[BadgeId] == true
end

local function AwardBadgeImpl(Name)
	return function(_, UserId, BadgeId)
		if not IsServer then
			error(`BadgeService:{Name} can only be called from the server`, 0) -- text: docs
		end
		task.wait()
		local UserBadges = AwardedBadges[UserId]
		if not UserBadges then
			UserBadges = {}
			AwardedBadges[UserId] = UserBadges
		end
		UserBadges[BadgeId] = true
		return true
	end
end

Method("BadgeService", "AwardBadge", AwardBadgeImpl("AwardBadge"))
Method("BadgeService", "AwardBadgeAsync", AwardBadgeImpl("AwardBadgeAsync"))

Method("BadgeService", "GetBadgeInfoAsync", function(_, BadgeId)
	if type(BadgeId) == "number" and BadgeId <= 0 then
		error("badgeId is invalid or does not exist.", 0)
	end
	task.wait()
	return { Name = "Badge", Description = "", IconImageId = 0, IsEnabled = true }
end)

Method("BadgeService", "UserHasBadge", function(_, UserId, BadgeId)
	return HasAwardedBadge(UserId, BadgeId)
end)

Method("BadgeService", "UserHasBadgeAsync", function(_, UserId, BadgeId)
	return HasAwardedBadge(UserId, BadgeId)
end)

-- CommerceService

Method("CommerceService", "GetCommerceProductInfoAsync", function(_, CommerceProductId)
	if not IsCommerceProductId(CommerceProductId) then
		error("Invalid commerceProductId", 0)
	end
	task.wait()
	return {
		IsForSale = true,
		Item = {
			Name = `Product {CommerceProductId}`,
			Description = "",
			IconImageAssetId = 0,
			DisplayPrice = "$0.00",
			IsPurchasable = true,
		},
		Benefits = {},
	}
end)

Method("CommerceService", "PromptCommerceProductPurchase", function(_, User, CommerceProductId)
	if not IsPlayer(User) then
		error("First argument to PromptCommerceProductPurchase must be a Player", 0) -- text: docs
	end
	if not IsCommerceProductId(CommerceProductId) then
		error("Invalid commerceProductId", 0)
	end
end)

-- ConfigService and ConfigSnapshot

local TestingConfig = {}
local SnapshotData = setmetatable({}, { __mode = "k" })

local function SnapshotConfig()
	local Snapshot = Create("ConfigSnapshot")
	SnapshotData[Snapshot] = {
		Values = CloneValue(TestingConfig),
		Signals = {},
	}
	return Snapshot
end

Method("ConfigService", "ClearTestingValue", function(_, Key)
	TestingConfig[tostring(Key)] = nil
end)

Method("ConfigService", "SetTestingValue", function(_, Key, Value, ...)
	if Value == nil then
		error("Argument 2 missing or nil", 0)
	end
	if Key == nil then
		error("Argument 1 missing or nil", 0)
	end
	TestingConfig[tostring(Key)] = Value
end, true)

Method("ConfigService", "GetConfigAsync", function()
	if not IsServer then
		error("ConfigService is only available in the game server.", 0)
	end
	task.wait()
	return SnapshotConfig()
end)

Method("ConfigService", "GetConfigForPlayerAsync", function(_, Player)
	if not IsServer then
		error("ConfigService is only available in the game server.", 0)
	end
	if not IsPlayer(Player) then
		error("First argument to GetConfigForPlayerAsync must be a Player", 0) -- text: docs
	end
	task.wait()
	return SnapshotConfig()
end)

Method("ConfigSnapshot", "GetValue", function(Self, Key)
	local Data = SnapshotData[Self]
	if not Data then
		return nil
	end
	return Data.Values[tostring(Key)]
end)

Method("ConfigSnapshot", "GetValueChangedSignal", function(Self, Key)
	local Data = SnapshotData[Self]
	if not Data then
		Data = { Values = {}, Signals = {} }
		SnapshotData[Self] = Data
	end
	local Name = tostring(Key)
	local Bindable = Data.Signals[Name]
	if not Bindable then
		Bindable = Create("BindableEvent")
		Data.Signals[Name] = Bindable
	end
	return Bindable.Event
end)

Method("ConfigSnapshot", "Refresh", function(Self)
	local Data = SnapshotData[Self]
	if not Data then
		return
	end
	local Previous = Data.Values
	local Next = CloneValue(TestingConfig)
	Data.Values = Next
	for Name, Bindable in Data.Signals do
		if Previous[Name] ~= Next[Name] then
			Bindable:Fire(Next[Name])
		end
	end
end)

-- DataStoreService & GlobalDataStore

local KnownDataStores = {}

if IsServer then
	local OrigGetDataStore = Create("DataStoreService").GetDataStore
	Method("DataStoreService", "GetDataStore", function(Self, Name, Scope, Options)
		if Options ~= nil and (typeof(Options) ~= "Instance" or not Options:IsA("DataStoreOptions")) then
			error("510: Options instance not of type DataStoreOptions", 0)
		end
		local Store = OrigGetDataStore(Self, Name, Scope, Options)
		if not KnownDataStores[Store.Name] then
			KnownDataStores[Store.Name] = DateTime.now().UnixTimestampMillis
		end
		return Store
	end)

	Method("DataStoreService", "ListDataStoresAsync", function(_, Prefix, PageSize, Cursor)
		Prefix = if Prefix == nil then "" else tostring(Prefix)
		Cursor = if type(Cursor) == "string" then Cursor else ""
		task.wait()
		local Names = {}
		for Name in KnownDataStores do
			if string.sub(Name, 1, #Prefix) == Prefix and Name >= Cursor then
				table.insert(Names, Name)
			end
		end
		table.sort(Names)
		local Items = {}
		for _, Name in Names do
			local Info = Create("DataStoreInfo")
			RawSet(Info, "DataStoreName", Name, true)
			RawSet(Info, "CreatedTime", KnownDataStores[Name], true)
			RawSet(Info, "UpdatedTime", KnownDataStores[Name], true)
			table.insert(Items, Info)
		end
		return MakePages("DataStoreListingPages", Items, if type(PageSize) == "number" and PageSize > 0 then PageSize else 50)
	end)

	Method("GlobalDataStore", "BatchGetAsync", function(Self, Keys, Options)
		local Result = {}
		if #Keys == 0 then
			task.wait()
			return Result
		end
		for _, Key in Keys do
			Result[Key] = Self:GetAsync(Key, Options)
		end
		return Result
	end)

	local UpdateEvents = setmetatable({}, { __mode = "k" })
	Method("GlobalDataStore", "OnUpdate", function(Self, Key, Callback)
		if type(Key) ~= "string" or #Key == 0 then
			error("101: Key name can't be empty.", 0)
		elseif #Key > 50 then
			error("102: Key name exceeds the 50 character limit.", 0)
		end
		local Map = UpdateEvents[Self]
		if not Map then
			Map = {}
			UpdateEvents[Self] = Map
		end
		local Bindable = Map[Key]
		if not Bindable then
			Bindable = Create("BindableEvent")
			Map[Key] = Bindable
		end
		return Bindable.Event:Connect(Callback)
	end)
else
	Method("DataStoreService", "GetDataStore", function(_, _Name, _Scope, Options)
		if Options ~= nil and (typeof(Options) ~= "Instance" or not Options:IsA("DataStoreOptions")) then
			error("510: Options instance not of type DataStoreOptions", 0)
		end
		error("DataStore can't be accessed from client", 0)
	end)

	Method("DataStoreService", "GetGlobalDataStore", function()
		error("DataStore can't be accessed from client", 0)
	end)

	Method("DataStoreService", "GetOrderedDataStore", function()
		error("DataStore can't be accessed from client", 0)
	end)

	Method("DataStoreService", "ListDataStoresAsync", function()
		error("DataStore can't be accessed from client", 0)
	end)

	-- MemoryStoreService (client-side restriction; server uses server.luau)
	for _, Name in { "GetHashMap", "GetSortedMap", "GetQueue" } do
		Method("MemoryStoreService", Name, function()
			error("MemoryStoreService cannot be accessed from client", 0) -- text: docs
		end)
	end

	-- MessagingService (client-side restriction; server uses server.luau)
	for _, Name in { "PublishAsync", "SubscribeAsync" } do
		Method("MessagingService", Name, function()
			error("MessagingService can only be executed by game server", 0)
		end)
	end
end

-- ExperienceNotificationService

Method("ExperienceNotificationService", "CanPromptOptInAsync", function()
	if IsServer then
		error("ExperienceNotificationService:CanPromptOptInAsync can only be executed by a local script", 0)
	end
	task.wait()
	return true
end)

Method("ExperienceNotificationService", "PromptOptIn", function()
	if IsServer then
		error("ExperienceNotificationService:PromptOptIn can only be executed by a local script", 0)
	end
end)

-- GroupService

Method("GroupService", "GetAlliesAsync", function(_, _GroupId)
	task.wait()
	return MakePages("StandardPages", {})
end)

Method("GroupService", "GetEnemiesAsync", function(_, _GroupId)
	task.wait()
	return MakePages("StandardPages", {})
end)

Method("GroupService", "GetGroupInfoAsync", function(_, GroupId)
	task.wait()
	return {
		Name = `Group {GroupId}`,
		Id = GroupId,
		Owner = { Name = "Owner", Id = 1 },
		EmblemUrl = "",
		Description = "",
		Roles = {},
	}
end)

Method("GroupService", "PromptJoinAsync", function(_, _GroupId)
	if IsServer then
		error("GroupService:PromptJoinAsync: Must be called on the client.", 0)
	end
	task.wait()
	return Enum.GroupMembershipStatus.None
end)

-- MarketplaceService

local ReceiptHandlers = {}

Method("MarketplaceService", "BindReceiptHandler", function(_, _TransactionType, Handler, _Filter)
	if not IsServer then
		error("BindReceiptHandler can only be called from the server", 0)
	end
	local Bindable = Create("BindableEvent")
	table.insert(ReceiptHandlers, Bindable)
	return Bindable.Event:Connect(Handler)
end)

local function GetProductInfo(_, AssetId, InfoType)
	task.wait()
	return {
		Name = `Product {AssetId}`,
		Description = "",
		PriceInRobux = 0,
		IsForSale = true,
		IsPublicDomain = false,
		IsLimited = false,
		IsLimitedUnique = false,
		IconImageAssetId = 0,
		AssetId = AssetId,
		ProductId = AssetId,
		AssetTypeId = 0,
		Created = "2020-01-01T00:00:00Z",
		Updated = "2020-01-01T00:00:00Z",
		Creator = { Name = "Roblox", CreatorType = "Group", Id = 1, CreatorTargetId = 1, HasVerifiedBadge = false },
		ProductType = if typeof(InfoType) == "EnumItem" then InfoType.Name else "Asset",
		Remaining = 0,
		Sales = 0,
		MinimumMembershipLevel = 0,
		ContentRatingTypeId = 0,
	}
end

Method("MarketplaceService", "GetProductInfo", GetProductInfo)
Method("MarketplaceService", "GetProductInfoAsync", GetProductInfo)

Method("MarketplaceService", "GetDeveloperProductsAsync", function()
	task.wait()
	return MakePages("StandardPages", {})
end)

Method("MarketplaceService", "GetRobloxSubscriptionDetailsAsync", function(_, User)
	if not IsServer then
		error("Can only call GetRobloxSubscriptionDetailsAsync from Script with RunContext = Server", 0)
	end
	if not IsPlayer(User) then
		error("First argument to GetRobloxSubscriptionDetailsAsync must be a Player", 0) -- text: docs
	end
	task.wait()
	return {}
end)

Method("MarketplaceService", "GetSubscriptionProductInfoAsync", function(_, SubscriptionId)
	if IsServer then
		error("Can only call GetSubscriptionProductInfoAsync from Script with RunContext = Client", 0)
	end
	if not IsSubscriptionId(SubscriptionId) then
		error("Invalid SubscriptionId", 0)
	end
	task.wait()
	return {
		Name = "Subscription",
		Description = "",
		DisplayPrice = "$0.99",
		DisplaySubscriptionPeriod = "Monthly",
		SubscriptionPeriod = Enum.SubscriptionPeriod.Month,
		IsForSale = true,
		IconImageAssetId = 0,
	}
end)

Method("MarketplaceService", "GetUsersPriceLevelsAsync", function(_, UserIds)
	if #UserIds == 0 then
		error("MarketplaceService:GetUsersPriceLevelsAsync() must have at least one user ID", 0)
	end
	task.wait()
	local Result = {}
	for _, UserId in UserIds do
		table.insert(Result, { UserId = UserId, PriceLevel = 1 })
	end
	return Result
end)

Method("MarketplaceService", "GetUserSubscriptionDetailsAsync", function(_, User, SubscriptionId)
	if not IsPlayer(User) then
		error("First argument to GetUserSubscriptionDetailsAsync must be a Player", 0) -- text: docs
	end
	if not IsSubscriptionId(SubscriptionId) then
		error("Invalid SubscriptionId", 0)
	end
	task.wait()
	return {
		IsSubscribed = false,
		IsRenewing = false,
		SubscriptionState = Enum.SubscriptionState.NeverSubscribed,
	}
end)

Method("MarketplaceService", "GetUserSubscriptionPaymentHistoryAsync", function(_, User, SubscriptionId)
	if not IsPlayer(User) then
		error("First argument to GetUserSubscriptionPaymentHistoryAsync must be a Player", 0) -- text: docs
	end
	if not IsSubscriptionId(SubscriptionId) then
		error("Invalid SubscriptionId", 0)
	end
	task.wait()
	return {}
end)

Method("MarketplaceService", "GetUserSubscriptionStatusAsync", function(_, User, SubscriptionId)
	if not IsPlayer(User) then
		error("First argument to GetUserSubscriptionStatusAsync must be a Player", 0) -- text: docs
	end
	if not IsSubscriptionId(SubscriptionId) then
		error("Invalid SubscriptionId", 0)
	end
	task.wait()
	return { IsSubscribed = false, IsRenewing = false }
end)

Method("MarketplaceService", "PromptBulkPurchase", function(_, Player, LineItems, _Options)
	if not IsPlayer(Player) then
		error("MarketplaceService.PromptBulkPurchase: player should be of type Player", 0) -- text: docs
	end
	if #LineItems == 0 then
		error("MarketplaceService.PromptBulkPurchase: 0 items in order", 0)
	end
end)

Method("MarketplaceService", "PromptBundlePurchase", function(_, Player, _BundleId)
	if not IsPlayer(Player) then
		error("MarketplaceService:PromptBundlePurchase() player should be of type Player", 0)
	end
end)

Method("MarketplaceService", "PromptCancelSubscription", function(_, User, SubscriptionId)
	if not IsPlayer(User) then
		error("First argument to PromptCancelSubscription must be a Player", 0) -- text: docs
	end
	if not IsSubscriptionId(SubscriptionId) then
		error("Invalid SubscriptionId", 0)
	end
end)

Method("MarketplaceService", "PromptGamePassPurchase", function(_, Player, _GamePassId)
	if not IsPlayer(Player) then
		error("MarketplaceService:PromptGamePassPurchase(): player should be of type Player.", 0)
	end
end)

Method("MarketplaceService", "PromptPremiumPurchase", function(_, Player)
	if not IsPlayer(Player) then
		error("First argument to PromptPremiumPurchase must be a Player", 0)
	end
end)

Method("MarketplaceService", "PromptProductPurchase", function(_, Player, _ProductId, _EquipIfPurchased, _CurrencyType)
	if not IsPlayer(Player) then
		error("MarketplaceService:PromptProductPurchase(): player should be of type Player.", 0)
	end
end)

Method("MarketplaceService", "PromptPurchase", function(_, Player, _AssetId, _EquipIfPurchased, _CurrencyType)
	if not IsPlayer(Player) then
		error("MarketplaceService:PromptPurchase(): player should be of type Player.", 0)
	end
end)

Method("MarketplaceService", "PromptRobuxTransferAsync", function(_, Sender, _ReceiverUserId, Amount)
	if not IsServer then
		error("Can only call PromptRobuxTransferAsync from Script with RunContext = Server", 0)
	end
	if not IsPlayer(Sender) then
		error("First argument to PromptRobuxTransferAsync must be a Player", 0) -- text: docs
	end
	if type(Amount) == "number" and Amount <= 0 then
		error("Transfer amount must be positive", 0) -- text: docs
	end
	task.wait()
	return NextUuid()
end)

Method("MarketplaceService", "PromptSubscriptionPurchase", function(_, User, SubscriptionId)
	if not IsPlayer(User) then
		error("First argument to PromptSubscriptionPurchase must be a Player", 0) -- text: docs
	end
	if not IsSubscriptionId(SubscriptionId) then
		error("Invalid SubscriptionId", 0)
	end
end)

Method("MarketplaceService", "PromptVIPServerPurchase", function()
	error("MarketplaceService:PromptVIPServerPurchase() API is not yet released.", 0)
end)

Method("MarketplaceService", "RankProductsAsync", function(_, ProductIdentifiers)
	if #ProductIdentifiers == 0 then
		error("MarketplaceService:RankProductsAsync() must have at least one ProductIdentifier.", 0)
	end
	task.wait()
	return table.clone(ProductIdentifiers)
end)

Method("MarketplaceService", "RecommendTopProductsAsync", function(_, InfoTypes)
	if IsServer then
		error("MarketplaceService:RecommendTopProductsAsync() Cannot be called from the Server.", 0)
	end
	if #InfoTypes == 0 then
		error("MarketplaceService:RecommendTopProductsAsync() must specify at least InfoType", 0)
	end
	task.wait()
	return {}
end)

-- MatchmakingService

local ServerAttributes = {}

Method("MatchmakingService", "InitializeServerAttributesForStudio", function(_, Attributes)
	ServerAttributes = {}
	for Key, Value in Attributes do
		ServerAttributes[tostring(Key)] = Value
	end
	return true, nil
end)

Method("MatchmakingService", "GetServerAttribute", function(_, Name)
	local Key = tostring(Name)
	local Value = ServerAttributes[Key]
	if Value == nil then
		return nil, `Attribute "{Key}" not found`
	end
	return Value, nil
end)

Method("MatchmakingService", "SetServerAttribute", function(_, Name, Value)
	if Value == nil then
		error("Argument 2 missing or nil", 0)
	end
	if Name == nil then
		error("Argument 1 missing or nil", 0)
	end
	local Key = tostring(Name)
	if ServerAttributes[Key] == nil then
		return false, `Attribute "{Key}" does not exist`
	end
	ServerAttributes[Key] = Value
	return true, nil
end, true)

-- OpenCloudService

Method("OpenCloudService", "InvokeAsync", function(_, Version, _MethodName, _Arguments, _Headers)
	if not IsServer then
		error("InvokeAsync should only be called from the server.", 0)
	end
	if Version ~= "v1" and Version ~= "v2" then
		error("Unable to find version.", 0)
	end
	task.wait()
	return {}
end)

-- PointsService

local PointBalances = {}

Method("PointsService", "AwardPoints", function(_, UserId, Amount)
	task.wait()
	local Balance = (PointBalances[UserId] or 0) + Amount
	PointBalances[UserId] = Balance
	return UserId, Amount, Balance
end)

Method("PointsService", "GetAwardablePoints", function()
	return 2147483647
end)

Method("PointsService", "GetGamePointBalance", function(_, UserId)
	return PointBalances[UserId] or 0
end)

Method("PointsService", "GetPointBalance", function(_, UserId)
	return PointBalances[UserId] or 0
end)

-- PolicyService

Method("PolicyService", "CanViewBrandProjectAsync", function(_, Player, _BrandProjectId)
	if not IsServer then
		error("PolicyService:CanViewBrandProjectAsync can only be called on the server", 0)
	end
	if not IsPlayer(Player) then
		error("Instance was not a player", 0)
	end
	task.wait()
	return false
end)

-- the stock method (services.luau) answers the client profile's policy; Roblox also refuses a non-player
local GetPolicyInfo = Create("PolicyService").GetPolicyInfoForPlayerAsync
Method("PolicyService", "GetPolicyInfoForPlayerAsync", function(Self, Player)
	if not IsPlayer(Player) then
		error("Instance was not a player", 0)
	end
	return GetPolicyInfo(Self, Player)
end)

-- RecommendationService

local RecommendationItems = {}

Method("RecommendationService", "GenerateItemListAsync", function(_, Request)
	if type(Request.ConfigName) ~= "string" or #Request.ConfigName == 0 then
		error("generateItemListAsync: ConfigName must be provided", 0)
	end
	task.wait()
	return MakePages("RecommendationPages", {})
end)

Method("RecommendationService", "GetRecommendationItemAsync", function(_, ItemId)
	if not IsServer then
		error("GetRecommendationItemAsync must run as Server Script.", 0)
	end
	task.wait()
	local Found = RecommendationItems[tostring(ItemId)]
	if Found then
		return CloneValue(Found)
	end
	return { ItemId = tostring(ItemId), ReferenceId = "", Attributes = {} }
end)

Method("RecommendationService", "LogActionEvent", function(_, _ActionType, ItemId, _TracingId, _Details)
	if IsServer then
		error("LogImpressionEvent should only be called with Client Run Context", 0)
	end
	if not IsUuid(ItemId) then
		error("itemId is not a UUID, please provide the itemId returned from RegisterItemAsync or GenerateItemListAsync", 0)
	end
end)

Method("RecommendationService", "LogImpressionEvent", function(_, _ImpressionType, ItemId, _TracingId, _Details)
	if IsServer then
		error("LogImpressionEvent should only be called with Client Run Context", 0)
	end
	if not IsUuid(ItemId) then
		error("itemId is not a UUID, please provide the itemId returned from RegisterItemAsync or GenerateItemListAsync", 0)
	end
end)

Method("RecommendationService", "LogPreferenceEvent", function(_, _PreferenceType, _TargetType, _TargetId, _TracingId, _ItemId)
	if IsServer then
		error("LogPreferenceEvent should only be called with Client Run Context", 0)
	end
end)

Method("RecommendationService", "RegisterItemAsync", function(_, Player, Request)
	if not IsServer then
		error("RegisterItemAsync must run as Server Script.", 0)
	end
	if not IsPlayer(Player) then
		error("First argument to RegisterItemAsync must be a Player", 0) -- text: docs
	end
	if type(Request.ReferenceId) ~= "string" or #Request.ReferenceId == 0 then
		error("RegisterRecommendationItemRequest must contain ReferenceId", 0)
	end
	task.wait()
	local ItemId = NextUuid()
	local Stored = CloneValue(Request)
	Stored.ItemId = ItemId
	RecommendationItems[ItemId] = Stored
	return { ItemId = ItemId }
end)

Method("RecommendationService", "UpdateItemAsync", function(_, Request)
	if not IsServer then
		error("UpdateItemAsync must run as Server Script.", 0)
	end
	if type(Request.ItemId) ~= "string" or #Request.ItemId == 0 then
		error("UpdateRecommendationItemRequest must contain ItemId", 0)
	end
	task.wait()
	local Existing = RecommendationItems[Request.ItemId]
	if Existing then
		for Key, Value in Request do
			Existing[Key] = CloneValue(Value)
		end
	end
end)

-- SocialService

Method("SocialService", "CanSendGameInviteAsync", function(_, Player, _RecipientId)
	if IsServer then
		error("SocialService:CanSendGameInviteAsync Must be called from a local script.", 0)
	end
	if Player ~= LocalPlayer() then
		error("SocialService:CanSendGameInviteAsync Must prompt the LocalPlayer when called from a local script.", 0)
	end
	task.wait()
	return true
end)

Method("SocialService", "GetEventRsvpStatusAsync", function(_, EventId)
	if not IsEventId(EventId) then
		error("SocialService:GetEventRsvpStatusAsync Received invalid event id.", 0)
	end
	task.wait()
	return Enum.RsvpStatus.None
end)

Method("SocialService", "GetExperienceEventAsync", function(_, EventId)
	if not IsEventId(EventId) then
		error("SocialService:GetExperienceEventAsync Received invalid event id.", 0)
	end
	task.wait()
	return {
		EventId = EventId,
		Title = "Event",
		Subtitle = "",
		Description = "",
		EventStatus = "Active",
		StartUtc = DateTime.now():ToIsoDate(),
		EndUtc = DateTime.now():ToIsoDate(),
		Thumbnails = {},
	}
end)

Method("SocialService", "GetPartyAsync", function(_, PartyId)
	if not IsServer then
		error("SocialService:GetPartyAsync Must be called from a server script.", 0)
	end
	if not IsUuid(PartyId) then
		error("SocialService:GetPartyAsync Received invalid party id.", 0)
	end
	task.wait()
	return {}
end)

Method("SocialService", "GetPlayersByPartyId", function(_, _PartyId)
	if not IsServer then
		error("SocialService:GetPlayersByPartyId Must be called from a server script.", 0)
	end
	return {}
end)

Method("SocialService", "GetUpcomingExperienceEventsAsync", function()
	if IsServer then
		error("SocialService:GetUpcomingExperienceEventsAsync must be called on the client.", 0)
	end
	return {}
end)

Method("SocialService", "PromptGameInvite", function(_, Player, Options)
	if not IsPlayer(Player) then
		error("SocialService:PromptGameInvite First argument should be a Player instance.", 0)
	end
	if not IsServer and Player ~= LocalPlayer() then
		error("SocialService:PromptGameInvite Must prompt the LocalPlayer when called from a local script.", 0) -- text: docs
	end
	if Options ~= nil and (typeof(Options) ~= "Instance" or not Options:IsA("ExperienceInviteOptions")) then
		error("SocialService:PromptGameInvite Second argument should be an ExperienceInviteOptions instance.", 0) -- text: docs
	end
end)

local function PromptLinkSharingImpl(_, Player, _Options)
	if not IsServer then
		error("SocialService:PromptLinkSharing can only be called from script with Server RunContext", 0)
	end
	if not IsPlayer(Player) then
		error("SocialService:PromptLinkSharing First argument should be a Player instance.", 0) -- text: docs
	end
	task.wait()
	return Enum.PromptLinkSharingResult.Success
end

Method("SocialService", "PromptLinkSharing", PromptLinkSharingImpl)
Method("SocialService", "PromptLinkSharingAsync", PromptLinkSharingImpl)

Method("SocialService", "PromptPhoneBook", function(_, Player, _Tag)
	if not IsPlayer(Player) then
		error("SocialService:PromptPhoneBook First argument should be a Player instance.", 0)
	end
end)

Method("SocialService", "PromptRsvpToEventAsync", function(_, EventId)
	if not IsEventId(EventId) then
		error("SocialService:GetEventRsvpStatusAsync Received invalid event id.", 0)
	end
	task.wait()
	return Enum.RsvpStatus.Going
end)

-- TeleportOptions & TeleportService

local TeleportOptionsData = setmetatable({}, { __mode = "k" })
local TeleportSettings = {}
local ArrivingTeleportGui = nil

Method("TeleportOptions", "GetTeleportData", function(Self)
	return TeleportOptionsData[Self]
end)

Method("TeleportOptions", "SetTeleportData", function(Self, Data)
	TeleportOptionsData[Self] = Data
end)

local function CheckPlayerList(PlayersList)
	if type(PlayersList) ~= "table" or #PlayersList == 0 then
		error("Invalid list of players for teleport.", 0)
	end
	for _, Player in PlayersList do
		if not IsPlayer(Player) then
			error("Invalid list of players for teleport.", 0)
		end
	end
end

Method("TeleportService", "GetArrivingTeleportGui", function()
	return ArrivingTeleportGui
end)

Method("TeleportService", "SetTeleportGui", function(_, Gui)
	ArrivingTeleportGui = Gui
end)

Method("TeleportService", "SetTeleportSetting", function(_, Setting, Value)
	if Value == nil then
		error("Argument 2 missing or nil", 0)
	end
	TeleportSettings[ReadStringParam(Setting, 1)] = Value
end, true)

Method("TeleportService", "PromptExperienceDetailsAsync", function(_, Player, _UniverseId)
	if IsServer then
		error("TeleportService::PromptExperienceDetailsAsync can only be called on the client", 0)
	end
	if not IsPlayer(Player) then
		error("First argument to PromptExperienceDetailsAsync must be a Player", 0) -- text: docs
	end
	task.wait()
	return Enum.PromptExperienceDetailsResult.PromptClosed
end)

local function ReserveServerImpl(_, _PlaceId)
	if not IsServer then
		error("TeleportService:ReserveServer can only be called by the server.", 0)
	end
	task.wait()
	return NextUuid(), NextUuid()
end

Method("TeleportService", "ReserveServer", ReserveServerImpl)
Method("TeleportService", "ReserveServerAsync", ReserveServerImpl)

Method("TeleportService", "Teleport", function(_, _PlaceId, Player, _TeleportData, _CustomLoadingScreen)
	if IsServer and not IsPlayer(Player) then
		error("Invalid list of players for teleport.", 0)
	end
end)

Method("TeleportService", "TeleportAsync", function(_, _PlaceId, PlayersList, Options)
	if not IsServer then
		error("TeleportUnknown must be called from a Server", 0)
	end
	CheckPlayerList(PlayersList)
	if Options ~= nil and (typeof(Options) ~= "Instance" or not Options:IsA("TeleportOptions")) then
		error("TeleportOptions must be a TeleportOptions instance", 0) -- text: docs
	end
	task.wait()
	local Result = Create("TeleportAsyncResult")
	if Options and Options.ShouldReserveServer then
		RawSet(Result, "PrivateServerId", NextUuid(), true)
		RawSet(Result, "ReservedServerAccessCode", NextUuid(), true)
	end
	return Result
end)

Method("TeleportService", "TeleportPartyAsync", function(_, _PlaceId, PlayersList, _TeleportData, _CustomLoadingScreen)
	if not IsServer then
		error("TeleportPartyAsync must be called from a Server", 0)
	end
	CheckPlayerList(PlayersList)
	task.wait()
	return NextUuid()
end)

Method("TeleportService", "TeleportToPlaceInstance", function(_, _PlaceId, _InstanceId, Player, _SpawnName, _TeleportData, _CustomLoadingScreen)
	if IsServer and not IsPlayer(Player) then
		error("Invalid list of players for teleport.", 0)
	end
end)

Method("TeleportService", "TeleportToPrivateServer", function(_, _PlaceId, _AccessCode, PlayersList, _SpawnName, _TeleportData, _CustomLoadingScreen)
	if not IsServer then
		error("TeleportToPrivateServer can only be called from the server", 0)
	end
	CheckPlayerList(PlayersList)
end)

Method("TeleportService", "TeleportToSpawnByName", function(_, _PlaceId, _SpawnName, Player, _TeleportData, _CustomLoadingScreen)
	if IsServer and not IsPlayer(Player) then
		error("Invalid list of players for teleport.", 0)
	end
end)

-- UserService

Method("UserService", "GetUserFromGlobalUserIdAsync", function(_, UserId)
	if not IsServer then
		error("UserService: GetUserFromGlobalUserIdAsync can only be called from the server", 0)
	end
	task.wait()
	return UserId
end)
