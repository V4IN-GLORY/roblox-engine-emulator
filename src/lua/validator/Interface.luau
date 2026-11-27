--!nocheck
-- Validator extension: see validator/packages/Behaviours.md for what this file owns.
local R = ...
local Create = R.Create
local RawSet = R.RawSet
local RawGet = R.RawGet
local Children = R.Children
local IsServer = R.IsServer

local Extras = setmetatable({}, { __mode = "k" })
local function Extra(Instance_)
	local Found = Extras[Instance_]
	if not Found then
		Found = {}
		Extras[Instance_] = Found
	end
	return Found
end

-- (a call whose self is no instance of the class is the body's to refuse: lua/arg_checks.rs)
local function Method(ClassName, MemberName, Body, OwnChecks)
	R.Method(ClassName, MemberName, function(Self, ...)
		if typeof(Self) ~= "Instance" or not Self:IsA(ClassName) then
			error(`Expected ':' not '.' calling member function {MemberName}`, 0)
		end
		return Body(Self, ...)
	end, OwnChecks)
end

-- What a 0.748 server and playing client refuse outright (validator/probe/expected)
local function Refuse(ClassName, Message, MemberNames, OwnChecks)
	for _, MemberName in MemberNames do
		Method(ClassName, MemberName, function()
			error(Message, 0)
		end, OwnChecks)
	end
end

-- a string parameter as a client reads it (services.luau StringParam)
local function ReadString(Value, Argument)
	return if type(Value) == "string" then Value else R.StringParam(Value, Argument)
end

-- a number, a User or a bool parameter, which the argument checks let through as a number, a bool or a numeric string
local function ReadNumber(Value)
	if type(Value) == "boolean" then
		return if Value then 1 else 0
	end
	return tonumber(Value)
end

-- an enum parameter's item, which the argument checks let through as an item of the enum, an item's name, a number or a bool
local function ReadEnum(EnumType, Value)
	if typeof(Value) == "EnumItem" then
		return Value
	end
	local Item = if type(Value) == "string" then EnumType[Value] else EnumType:FromValue(ReadNumber(Value))
	if not Item then
		error(`Unable to cast value to {EnumType}`, 0)
	end
	return Item
end

local function ChildrenOfClass(Parent, ClassName)
	local Found = {}
	for _, Child in Children(Parent) do
		if Child:IsA(ClassName) then
			table.insert(Found, Child)
		end
	end
	return Found
end

local function ConnectedPlayer(UserId)
	local Players = game:FindService("Players")
	local Wanted = ReadNumber(UserId)
	for _, Player in if Players then Players:GetPlayers() else {} do
		if RawGet(Player, "UserId") == Wanted then
			return Player
		end
	end
	return nil
end

local function CheckInWorkspace(Adornee)
	if not Adornee:IsDescendantOf(workspace) then
		error("partOrCharacter must be in the Workspace", 0)
	end
end

-- SoundService and the Audio* classes

-- (the mixer clock starts at an arbitrary value, per the docs: far from os.time() and from the seconds since the run began)
local MIXER_START = 100000
local function MixerTime()
	return MIXER_START + time()
end

Method("SoundService", "GetMixerTime", MixerTime)

local ListenerType, Listener = Enum.ListenerType.Camera, nil

Method("SoundService", "GetListener", function()
	return ListenerType, Listener
end)

Method("SoundService", "SetListener", function(_, Kind, Target)
	local Item = ReadEnum(Enum.ListenerType, Kind)
	if Item == Enum.ListenerType.Camera then
		Target = nil
	elseif Item == Enum.ListenerType.CFrame then
		if typeof(Target) ~= "CFrame" then
			error("SoundService:SetListener expects a CFrame for Enum.ListenerType.CFrame", 0) -- text: docs
		end
	elseif typeof(Target) ~= "Instance" or not (Target:IsA("BasePart") or Target:IsA("Attachment")) then
		error("SoundService:SetListener expects a BasePart or Attachment", 0) -- text: docs
	end
	ListenerType, Listener = Item, Target
end)

-- (the stock behaviour reports the sound to the recorder: world/mod.rs)
local ReportLocalSound = game:GetService("SoundService").PlayLocalSound

Method("SoundService", "PlayLocalSound", function(Self, Sound)
	if IsServer then
		error("SoundService:PlayLocalSound only works on a client.", 0)
	end
	if not Sound:IsA("Sound") then
		error("SoundService:PlayLocalSound expects a Sound object.", 0)
	end
	ReportLocalSound(Self, Sound)
end)

for _, ClassName in { "AudioEmitter", "AudioListener" } do
	for _, Curve in { "AngleAttenuation", "DistanceAttenuation" } do
		-- (a client takes a curve that is no table without raising)
		Method(ClassName, `Set{Curve}`, function(Self, Points)
			Extra(Self)[Curve] = if type(Points) == "table" then table.clone(Points) else nil
		end, true)
		Method(ClassName, `Get{Curve}`, function(Self)
			local Points = Extra(Self)[Curve]
			return if Points then table.clone(Points) else {}
		end)
	end
end

local ScheduledActions = 0
for _, MemberName in { "Play", "Stop" } do
	local Playing = MemberName == "Play"
	-- with an atTime the change waits for that mixer time and the call returns its id, else it applies now
	Method("AudioPlayer", MemberName, function(Self, AtTime)
		if AtTime == nil then
			RawSet(Self, "IsPlaying", Playing)
			return nil
		end
		if IsServer then
			error(`AudioPlayer:{MemberName}(atTime) cannot be used on the server`, 0)
		end
		local Target = ReadNumber(AtTime)
		local Now = MixerTime()
		-- (a minute before the clock started or over a day ahead is no mixer time: os.time(), a delay in seconds)
		if not (Target >= MIXER_START - 60 and Target <= Now + 86400) then
			error(`AudioPlayer:{MemberName}(atTime) can only use times based on SoundService:GetMixerTime()`, 0)
		end
		local Data = Extra(Self)
		Data.Pending = Data.Pending or {}
		ScheduledActions += 1
		local ActionId = ScheduledActions
		Data.Pending[ActionId] = task.delay(Target - Now, function()
			Data.Pending[ActionId] = nil
			RawSet(Self, "IsPlaying", Playing)
		end)
		return ActionId
	end)
end

Method("AudioPlayer", "Cancel", function(Self, ActionId)
	local Pending = Extra(Self).Pending
	local Id = ReadNumber(ActionId)
	local Action = Pending and Pending[Id]
	if not Action then
		return false
	end
	task.cancel(Action)
	Pending[Id] = nil
	return true
end)

Refuse("AudioRecorder", "AudioRecorder is not enabled yet", { "CanRecordAsync", "GetUnrecordableInstancesAsync", "RecordAsync" })
Refuse("AudioStreamReader", "AudioStreamReader is not enabled", { "Peek", "Read" }, true)
Refuse("AudioStreamWriter", "AudioStreamWriter is not enabled", { "Space", "Write" }, true)

-- ContextActionService (no input reaches a binding: only a host's input layer reads a device)

local Bindings = {}
local BindingCount = 0

local function IsBindableInput(Input)
	if type(Input) == "string" then
		return true
	end
	if typeof(Input) ~= "EnumItem" then
		return false
	end
	local Kind = Input.EnumType
	return Kind == Enum.KeyCode or Kind == Enum.UserInputType or Kind == Enum.PlayerActions
end

local function Bind(ActionName, CreateTouchButton, Priority, ...)
	local Name = ReadString(ActionName, 1) -- (the string's warning comes first on a server too: string_parameter_methods probe)
	if IsServer then
		error("ContextActionService:BindAction can only be called from a local script", 0)
	end
	local Inputs = table.pack(...)
	for Index = 1, Inputs.n do
		if not IsBindableInput(Inputs[Index]) then
			error("ContextActionService:BindAction called with an invalid hotkey (should be either Enum.KeyCode, Enum.UserInputType or string)", 0)
		end
	end
	Inputs.n = nil
	local Button = nil
	if CreateTouchButton and game:GetService("UserInputService").TouchEnabled then
		Button = Create("ImageButton")
		RawSet(Button, "Name", Name, true)
	end
	BindingCount += 1
	Bindings[Name] = {
		Button = Button,
		Info = { inputTypes = Inputs, stackOrder = BindingCount, priorityLevel = Priority, createTouchButton = not not CreateTouchButton },
	}
end

for _, MemberName in { "BindAction", "BindActionToInputTypes" } do
	Method("ContextActionService", MemberName, function(_, ActionName, _Callback, CreateTouchButton, ...)
		Bind(ActionName, CreateTouchButton, 2000, ...)
	end)
end

Method("ContextActionService", "BindActionAtPriority", function(_, ActionName, _Callback, CreateTouchButton, Priority, ...)
	Bind(ActionName, CreateTouchButton, ReadNumber(Priority), ...)
end)

Method("ContextActionService", "UnbindAction", function(_, ActionName)
	Bindings[ReadString(ActionName, 1)] = nil
end)

Method("ContextActionService", "UnbindAllActions", function()
	table.clear(Bindings)
end)

local function BindingInfo(Binding)
	local Info = table.clone(Binding.Info)
	Info.inputTypes = table.clone(Info.inputTypes)
	return Info
end

Method("ContextActionService", "GetBoundActionInfo", function(_, ActionName)
	local Binding = Bindings[ReadString(ActionName, 1)]
	return if Binding then BindingInfo(Binding) else {}
end)

Method("ContextActionService", "GetAllBoundActionInfo", function()
	local All = {}
	for Name, Binding in Bindings do
		All[Name] = BindingInfo(Binding)
	end
	return All
end)

Method("ContextActionService", "GetButton", function(_, ActionName)
	local Binding = Bindings[ReadString(ActionName, 1)]
	return if Binding then Binding.Button else nil
end)

-- each setter's key in the binding's info, and the property it writes on the touch button
for MemberName, Target in {
	SetTitle = { Key = "title" },
	SetDescription = { Key = "description" },
	SetImage = { Key = "image", Property = "Image" },
	SetPosition = { Property = "Position" },
} do
	Method("ContextActionService", MemberName, function(_, ActionName, Value)
		if Target.Key then
			Value = ReadString(Value, 2)
		end
		local Binding = Bindings[ReadString(ActionName, 1)]
		if not Binding then
			return
		end
		if Target.Key then
			Binding.Info[Target.Key] = Value
		end
		if Target.Property and Binding.Button then
			Binding.Button[Target.Property] = Value
		end
	end)
end

Method("ContextActionService", "BindActivate", function(_, _UserInputType, ...)
	if IsServer then
		error("ContextActionService:BindActivate can only be called from a local script", 0)
	end
	local Keys = table.pack(...)
	for Index = 1, Keys.n do
		if typeof(Keys[Index]) ~= "EnumItem" or Keys[Index].EnumType ~= Enum.KeyCode then
			error("ContextActionService:BindActivate called with an invalid keyCode (should be Enum.KeyCode)", 0)
		end
	end
end)

Method("ContextActionService", "UnbindActivate", function()
	if IsServer then
		error("ContextActionService:UnbindActivate can only be called from a local script", 0)
	end
end)

-- StarterGui: the names the core scripts register (docs: StarterGui:SetCore, :GetCore)

-- the values GetCore reads back
local CoreValues = {
	AvatarContextMenuEnabled = false,
	BadgesNotificationsActive = true,
	ChatActive = true,
	ChatBarDisabled = false,
	ChatWindowPosition = UDim2.new(),
	ChatWindowSize = UDim2.fromScale(0.3, 0.25),
	DevConsoleVisible = false,
	PointsNotificationsActive = true,
	TopbarEnabled = true,
}

local function IsPlayer(Value)
	return typeof(Value) == "Instance" and Value:IsA("Player")
end

local function AnyValue()
	return true
end

-- what SetCore takes besides the values above, with the check of each argument the docs require
local CORE_SETTERS = {
	AddAvatarContextMenuOption = AnyValue,
	AvatarContextMenuTarget = IsPlayer,
	AvatarContextMenuTheme = AnyValue,
	CoreGuiChatConnections = AnyValue,
	RemoveAvatarContextMenuOption = AnyValue,
	VREnableControllerModels = AnyValue,
	VRLaserPointerMode = AnyValue,
	PromptBlockPlayer = IsPlayer,
	PromptSendFriendRequest = IsPlayer,
	PromptUnblockPlayer = IsPlayer,
	PromptUnfriend = IsPlayer,
	ChatMakeSystemMessage = function(Value)
		return type(Value) == "table" and type(Value.Text) == "string"
	end,
	ResetButtonCallback = function(Value)
		return type(Value) == "boolean" or (typeof(Value) == "Instance" and Value:IsA("BindableEvent"))
	end,
	SendNotification = function(Value)
		return type(Value) == "table" and type(Value.Title) == "string" and type(Value.Text) == "string"
	end,
}

-- GetCore's BindableEvents, each made when first asked for
local CoreEvents = {}
for _, Name in { "PlayerBlockedEvent", "PlayerUnblockedEvent", "PlayerMutedEvent", "PlayerUnmutedEvent", "PlayerFriendedEvent", "PlayerUnfriendedEvent" } do
	CoreEvents[Name] = false
end

Method("StarterGui", "SetCore", function(_, ParameterName, Value)
	local Name = ReadString(ParameterName, 1)
	-- (a server's call does nothing, whatever the name)
	if IsServer then
		return
	end
	if CoreValues[Name] ~= nil then
		if Value ~= nil then
			CoreValues[Name] = Value
		end
		return
	end
	local Accepts = CORE_SETTERS[Name]
	if not Accepts then
		error(`SetCore: {Name} has not been registered by the CoreScripts`, 0)
	end
	if not Accepts(Value) then
		error(`SetCore: {Name} was given an invalid value`, 0) -- text: docs
	end
end)

Method("StarterGui", "GetCore", function(_, ParameterName)
	-- (read without the string cast's warning, as a client reads it: lua/convert.rs)
	local Name = if type(ParameterName) == "table" then "{}" else tostring(ParameterName)
	-- (a server waits for core scripts it does not run)
	if IsServer then
		if not coroutine.isyieldable() then
			error("thread is not yieldable", 0)
		end
		return coroutine.yield()
	end
	if Name == "GetBlockedUserIds" then
		local Social = R.Profile and R.Profile.social
		return table.clone(Social and Social.blocked or {})
	end
	if CoreEvents[Name] ~= nil then
		CoreEvents[Name] = CoreEvents[Name] or Create("BindableEvent")
		return CoreEvents[Name]
	end
	if CoreValues[Name] == nil then
		error(`GetCore: {Name} has not been registered by the CoreScripts`, 0)
	end
	return CoreValues[Name]
end)

local DisabledCoreGuis = {}

local function CoreGuiItems(CoreGuiType)
	local Item = ReadEnum(Enum.CoreGuiType, CoreGuiType)
	return if Item == Enum.CoreGuiType.All then Enum.CoreGuiType:GetEnumItems() else { Item }
end

Method("StarterGui", "SetCoreGuiEnabled", function(_, CoreGuiType, Enabled)
	for _, Item in CoreGuiItems(CoreGuiType) do
		DisabledCoreGuis[Item.Name] = not Enabled
	end
end)

Method("StarterGui", "GetCoreGuiEnabled", function(_, CoreGuiType)
	for _, Item in CoreGuiItems(CoreGuiType) do
		if Item ~= Enum.CoreGuiType.All and DisabledCoreGuis[Item.Name] then
			return false
		end
	end
	return true
end)

-- GuiService and LayerCollector

-- (RemoveSelectionGroup does nothing, so no group is kept)
Method("GuiService", "AddSelectionParent", function(_, SelectionName)
	ReadString(SelectionName, 1)
end)

Method("GuiService", "Select", function(Self, SelectionParent)
	if not SelectionParent:IsA("BasePlayerGui") and not SelectionParent:FindFirstAncestorWhichIsA("BasePlayerGui") then
		error("Calling GuiService:Select() on an instance that is not a descendant of a BasePlayerGui", 0)
	end
	local Selected = nil
	for _, Descendant in SelectionParent:GetDescendants() do
		if Descendant:IsA("GuiObject") and Descendant.Selectable and Descendant.Visible and (not Selected or Descendant.SelectionOrder < Selected.SelectionOrder) then
			Selected = Descendant
		end
	end
	if Selected then
		Self.SelectedObject = Selected
	end
end)

Method("GuiService", "InspectPlayerFromHumanoidDescription", function(_, Description)
	if not Description:IsA("HumanoidDescription") then
		error("GuiService:InspectPlayerFromHumanoidDescription - Expected a HumanoidDescription object.", 0)
	end
end)

Refuse("GuiService", "GuiService:DismissNotification is not yet enabled!", { "DismissNotification" })
Refuse("GuiService", "GuiService:SendNotification is not yet enabled!", { "SendNotification" })

local GuiFlags = {}
for _, Flag in { "EmotesMenuOpen", "InspectMenuEnabled", "GameplayPausedNotificationEnabled" } do
	Method("GuiService", `Set{Flag}`, function(_, Value)
		GuiFlags[Flag] = not not Value
	end)
	Method("GuiService", `Get{Flag}`, function()
		return GuiFlags[Flag] == true
	end)
end

Refuse("LayerCollector", "Internal Permission is required for this feature.", { "GetLayoutNodeTree" })

-- TextBox focus and UserInputService (no input layer: only scripts move the focus)

local FocusedTextBox = nil

Method("TextBox", "CaptureFocus", function(Self)
	FocusedTextBox = Self
end)

Method("TextBox", "ReleaseFocus", function(Self)
	if FocusedTextBox == Self then
		FocusedTextBox = nil
	end
end)

Method("TextBox", "IsFocused", function(Self)
	return FocusedTextBox == Self
end)

Method("UserInputService", "GetFocusedTextBox", function()
	return FocusedTextBox
end)

-- (nil is a documented answer: the docs have callers check for it)
Method("UserInputService", "CreateVirtualInput", function(_, Target)
	if Target ~= nil and not Target:IsA("LayerCollector") then
		error("UserInputService::CreateVirtualInput: target must be a LayerCollector (e.g. a DockWidgetPluginGui).", 0)
	end
	return nil
end)

for _, MemberName in { "GetDeviceAcceleration", "GetDeviceGravity", "GetDeviceRotation" } do
	Method("UserInputService", MemberName, function()
		if IsServer then
			error(`{MemberName} data can only be used from local scripts`, 0)
		end
		if MemberName == "GetDeviceRotation" then
			return Create("InputObject"), CFrame.identity
		end
		return Create("InputObject")
	end)
end

-- HapticEffect

local function CheckCustomEffect(Effect, Message)
	if RawGet(Effect, "Type") ~= Enum.HapticEffectType.Custom then
		error(Message, 0)
	end
end

Method("HapticEffect", "GetWaveformKeys", function(Self)
	CheckCustomEffect(Self, "HapticEffect.Type is not Custom")
	local Keys = Extra(Self).WaveformKeys
	return if Keys then table.clone(Keys) else {}
end)

Method("HapticEffect", "SetWaveformKeys", function(Self, Keys)
	CheckCustomEffect(Self, "Cannot modify non-custom haptic effect!")
	Extra(Self).WaveformKeys = table.clone(Keys)
end)

-- Styling: rules and derives are child instances; a rule's properties and a query's conditions are kept as given

local function CheckListArgument(Value)
	if Value == nil then
		error("Argument 1 missing or nil", 0)
	end
	if type(Value) ~= "table" then
		error(`Expected table argument, got {typeof(Value)}`, 0)
	end
end

Method("StyleBase", "GetStyleRules", function(Self)
	return ChildrenOfClass(Self, "StyleRule")
end)

Method("StyleBase", "SetStyleRules", function(Self, Rules)
	CheckListArgument(Rules)
	for _, Rule in ChildrenOfClass(Self, "StyleRule") do
		if not table.find(Rules, Rule) then
			Rule.Parent = nil
		end
	end
	for _, Rule in Rules do
		Rule.Parent = Self
	end
end, true)

Method("StyleBase", "InsertStyleRule", function(Self, Rule, Priority)
	if Priority == nil then
		Priority = 0
		for _, Other in ChildrenOfClass(Self, "StyleRule") do
			Priority = math.max(Priority, Other.Priority + 1)
		end
	end
	Rule.Priority = ReadNumber(Priority)
	Rule.Parent = Self
end)

Method("StyleSheet", "GetDerives", function(Self)
	local Sheets = {}
	for _, Derive in ChildrenOfClass(Self, "StyleDerive") do
		table.insert(Sheets, Derive.StyleSheet)
	end
	return Sheets
end)

Method("StyleSheet", "SetDerives", function(Self, Sheets)
	CheckListArgument(Sheets)
	for _, Derive in ChildrenOfClass(Self, "StyleDerive") do
		Derive:Destroy()
	end
	for Index, Sheet in Sheets do
		local Derive = Create("StyleDerive")
		Derive.StyleSheet = Sheet
		Derive.Priority = Index
		Derive.Parent = Self
	end
end, true)

for _, Store in {
	{ ClassName = "StyleRule", One = "Property", Many = "Properties" },
	{ ClassName = "StyleQuery", One = "Condition", Many = "Conditions" },
} do
	local function Entries(Self)
		local Data = Extra(Self)
		Data[Store.Many] = Data[Store.Many] or {}
		return Data[Store.Many]
	end
	Method(Store.ClassName, `Set{Store.One}`, function(Self, Name, Value)
		Entries(Self)[ReadString(Name, 1)] = Value
	end)
	Method(Store.ClassName, `Get{Store.One}`, function(Self, Name)
		return Entries(Self)[ReadString(Name, 1)]
	end)
	Method(Store.ClassName, `Set{Store.Many}`, function(Self, Given)
		for Name, Value in Given do
			Entries(Self)[Name] = Value
		end
	end)
	Method(Store.ClassName, `Get{Store.Many}`, function(Self)
		return table.clone(Entries(Self))
	end)
end

-- Chat (offline: every filter passes the text as it is, a frame later as the web call answers)

Method("Chat", "CanUserChatAsync", function(_, UserId)
	if IsServer then
		if not ConnectedPlayer(UserId) then
			error("The user must be connected to the current server", 0)
		end
	else
		local Player = R.LocalPlayer()
		if not Player or RawGet(Player, "UserId") ~= ReadNumber(UserId) then
			error("Must only be called for the local user from local scripts", 0)
		end
	end
	task.wait()
	return true
end)

Method("Chat", "CanUsersChatAsync", function(_, FromUserId, ToUserId)
	if not IsServer then
		error("Must only be called from server scripts", 0)
	end
	if not ConnectedPlayer(FromUserId) or not ConnectedPlayer(ToUserId) then
		error("Both users must be connected to the current server", 0)
	end
	task.wait()
	return true
end)

Method("Chat", "Chat", function(_, PartOrCharacter)
	CheckInWorkspace(PartOrCharacter)
end)

for _, MemberName in { "FilterStringAsync", "FilterStringForBroadcast", "FilterStringForPlayerAsync" } do
	Method("Chat", MemberName, function(_, Text, ...)
		if MemberName == "FilterStringForPlayerAsync" and not IsServer then
			error("ChatService:FilterString called on a client, only works from server.", 0)
		end
		for _, Player in { ... } do
			if not Player:IsA("Player") then
				error(`Chat:{MemberName} expects a Player`, 0) -- text: docs
			end
		end
		Text = ReadString(Text, 1)
		task.wait()
		return Text
	end)
end

local ChatCallbacks = {}
local CLIENT_CHAT_CALLBACKS = { OnCreatingChatWindow = true, OnClientSendingMessage = true, OnClientFormattingMessage = true }

Method("Chat", "RegisterChatCallback", function(_, CallbackType, Callback)
	local Name = ReadEnum(Enum.ChatCallbackType, CallbackType).Name
	if CLIENT_CHAT_CALLBACKS[Name] then
		if IsServer then
			error("Chat client callbacks can only be set from a local script.", 0)
		end
	elseif not IsServer then
		error("Chat server callbacks can only be set from a server script.", 0) -- text: docs
	end
	ChatCallbacks[Name] = Callback
end)

Method("Chat", "InvokeChatCallback", function(_, CallbackType, ...)
	local Callback = ChatCallbacks[ReadEnum(Enum.ChatCallbackType, CallbackType).Name]
	if Callback then
		return Callback(...)
	end
end)

Method("Chat", "SetBubbleChatSettings", function()
	if IsServer then
		error("SetBubbleChatSettings can only be called from the client", 0)
	end
end)

-- TextChatService and TextChannel

Method("TextChatService", "DisplayBubble", function(_, PartOrCharacter)
	CheckInWorkspace(PartOrCharacter)
end)

Refuse("TextChatService", "TextChatService:GetChatGroupsAsync is disabled.", { "GetChatGroupsAsync" })

local function CheckClientChannel(Channel, MemberName)
	local Service = game:FindService("TextChatService")
	if not Service or not Channel:IsDescendantOf(Service) then
		error(`{MemberName} error: TextChannel not a descendant of TextChatService`, 0)
	end
	if IsServer then
		error(`{MemberName} can only be called from a local script`, 0) -- text: docs
	end
end

local function ChatMessage(Channel, Text, Metadata)
	local Message = Create("TextChatMessage")
	RawSet(Message, "Text", Text, true)
	RawSet(Message, "Metadata", Metadata, true)
	RawSet(Message, "TextChannel", Channel, true)
	RawSet(Message, "Status", Enum.TextChatMessageStatus.Success, true)
	return Message
end

local function ReadMessage(Text, Metadata)
	return ReadString(Text, 1), if Metadata == nil then "" else ReadString(Metadata, 2)
end

Method("TextChannel", "DisplaySystemMessage", function(Self, Text, Metadata)
	CheckClientChannel(Self, "DisplaySystemMessage")
	return ChatMessage(Self, ReadMessage(Text, Metadata))
end)

Method("TextChannel", "SendAsync", function(Self, Text, Metadata)
	CheckClientChannel(Self, "SendAsync")
	Text, Metadata = ReadMessage(Text, Metadata)
	-- (documented: past 200 characters of metadata nothing is sent, and the message comes back empty)
	if #Metadata > 200 then
		Text, Metadata = "", ""
	end
	task.wait()
	local Message = ChatMessage(Self, Text, Metadata)
	local Source = Create("TextSource")
	RawSet(Source, "UserId", RawGet(R.LocalPlayer(), "UserId"), true)
	RawSet(Message, "TextSource", Source, true)
	return Message
end)

Method("TextChannel", "AddUserAsync", function(Self, UserId)
	if not IsServer then
		error("TextChannel:AddUserAsync can only be called from the server", 0) -- text: docs
	end
	task.wait()
	local Player = ConnectedPlayer(UserId)
	if not Player then
		return nil, false
	end
	local Id = RawGet(Player, "UserId")
	for _, Existing in ChildrenOfClass(Self, "TextSource") do
		if RawGet(Existing, "UserId") == Id then
			return Existing, false
		end
	end
	local Source = Create("TextSource")
	RawSet(Source, "Name", RawGet(Player, "Name"), true)
	RawSet(Source, "UserId", Id, true)
	R.SetParent(Source, Self)
	return Source, true
end)

-- TextService and its filter results

local function FilterResult(Text)
	local Result = Create("TextFilterResult")
	Extra(Result).Text = Text
	return Result
end

local function CheckSender(UserId)
	if not IsServer then
		error("Must only be called from server scripts", 0)
	end
	if not ConnectedPlayer(UserId) then
		error("The sender must be connected to the current server", 0)
	end
end

Method("TextService", "FilterStringAsync", function(_, Text, FromUserId)
	CheckSender(FromUserId)
	Text = ReadString(Text, 1)
	task.wait()
	return FilterResult(Text)
end)

-- (translations are kept by language: "es-es" and "es-mx" both read "es")
local function Language(Locale)
	return string.lower(string.match(Locale, "^%a*"))
end

Method("TextService", "FilterAndTranslateStringAsync", function(_, Text, FromUserId, TargetLocales)
	CheckSender(FromUserId)
	Text = ReadString(Text, 1)
	task.wait()
	local Translations = {}
	for _, Locale in TargetLocales do
		Translations[Language(Locale)] = FilterResult(Text)
	end
	local Result = Create("TextFilterTranslatedResult")
	Extra(Result).Translations = Translations
	RawSet(Result, "SourceText", FilterResult(Text), true)
	RawSet(Result, "SourceLanguage", "en", true)
	return Result
end)

for _, MemberName in { "GetNonChatStringForBroadcastAsync", "GetNonChatStringForUserAsync", "GetChatForUserAsync" } do
	Method("TextFilterResult", MemberName, function(Self, ToUserId)
		if MemberName == "GetChatForUserAsync" and not ConnectedPlayer(ToUserId) then
			error("The recipient must be connected to the current server", 0) -- text: docs
		end
		task.wait()
		return Extra(Self).Text
	end)
end

Method("TextFilterTranslatedResult", "GetTranslationForLocale", function(Self, Locale)
	return Extra(Self).Translations[Language(ReadString(Locale, 1))]
end)

Method("TextFilterTranslatedResult", "GetTranslations", function(Self)
	return table.clone(Extra(Self).Translations)
end)

-- TextGenerator, video and voice

Method("TextGenerator", "GenerateTextAsync", function(Self, Request)
	if not Self:IsDescendantOf(game) then
		error("TextGenerator must be parented into the DataModel.", 0)
	end
	task.wait()
	return {
		-- (with a JsonSchema the answer is JSON)
		GeneratedText = if Request.JsonSchema then "{}" else "Generated text.",
		ContextToken = Request.ContextToken or "context",
		Model = "default",
	}
end)

Refuse("VideoPlayer", "VideoPlayer:loadAsync is not enabled", { "LoadAsync" })

Method("VideoService", "CreateVideoSamplerAsync", function()
	if IsServer then
		error("VideoSampler can only be created on the Client", 0)
	end
	task.wait()
	return Create("VideoSampler")
end)

Refuse("VoiceChatService", "VoiceChatService:GetChatGroupsAsync is disabled.", { "GetChatGroupsAsync" })
