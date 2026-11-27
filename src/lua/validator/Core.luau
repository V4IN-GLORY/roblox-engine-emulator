--!nocheck
-- Validator extension: see validator/packages/Behaviours.md for what this file owns.
local R = ...
local Method = R.Method
local Create = R.Create
local RawGet = R.RawGet
local Missing = R.Missing
local IsServer = R.IsServer
local CastStringParam = R.StringParam

local Players = game:GetService("Players")

local function StringParamRead(Value, Argument)
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

local function CastName(Value)
	local Kind = typeof(Value)
	if Kind == "number" then
		return "double"
	elseif Kind == "boolean" then
		return "bool"
	elseif Kind == "table" then
		return if rawlen(Value) > 0 then "Array" else "Dictionary"
	end
	return Kind
end

local function CallerScript()
	for Level = 2, 64 do
		local Fn, Source = debug.info(Level, "fs")
		if Fn == nil then
			break
		end
		if Source ~= "[C]" and string.sub(Source, 1, 4) ~= "rur." and string.sub(Source, 1, 4) ~= "ree." then
			local Ok, Env = pcall(getfenv, Fn)
			if Ok and type(Env) == "table" and typeof(Env.script) == "Instance" then
				return Env.script
			end
		end
	end
	return nil
end

-- Actor: SendMessage / BindToMessage / BindToMessageParallel

local ActorTopics = setmetatable({}, { __mode = "k" })

local function ActorTopicEvent(Actor, Topic, Make)
	local Topics = ActorTopics[Actor]
	if not Topics then
		if not Make then
			return nil
		end
		Topics = {}
		ActorTopics[Actor] = Topics
	end
	local Event = Topics[Topic]
	if not Event and Make then
		Event = Create("BindableEvent")
		Topics[Topic] = Event
	end
	return Event
end

Method("Actor", "SendMessage", function(Self, Topic, ...)
	if not Self:IsDescendantOf(game) then
		error("Actor:SendMessage may only be called on Actors attached to the DataModel.", 0)
	end
	local Event = ActorTopicEvent(Self, Topic, false)
	if Event then
		Event:Fire(...)
	end
end)

for _, Name in { "BindToMessage", "BindToMessageParallel" } do
	Method("Actor", Name, function(Self, Topic, Callback)
		if not Self:IsDescendantOf(game) then
			error(`{Name} is being executed from a ModuleScript, which requires the ModuleScript to be a descendant of the desired Actor. If you intended to call this function from the ModuleScript's requirer, please consider exporting a function that calls {Name} instead.`, 0)
		end
		local Event = ActorTopicEvent(Self, Topic, true)
		return Event.Event:Connect(Callback)
	end)
end

-- Remotes: wrong-side errors on the client, clean client sends, and parentless server InvokeClient

if IsServer then
	Method("RemoteFunction", "InvokeClient", function(Self, Player)
		if Player == nil then
			error("Argument 1 missing or nil", 0)
		elseif not IsPlayer(Player) then
			error("InvokeClient: player argument must be a Player object", 0)
		end
		if not coroutine.isyieldable() then
			error("thread is not yieldable", 0)
		end
		if Player.Parent == Players then
			Missing("RemoteFunction", "InvokeClient")
			local Thread = coroutine.running()
			local Connection
			Connection = Players.PlayerRemoving:Connect(function(Leaving)
				if Leaving == Player then
					Connection:Disconnect()
					task.spawn(Thread)
				end
			end)
			coroutine.yield()
		elseif not Self:IsDescendantOf(game) then
			return coroutine.yield()
		end
		error(`InvokeClient: {Player.Name} left the game before {Self:GetFullName()} returned`, 0)
	end)
else
	for _, Class in { "RemoteEvent", "UnreliableRemoteEvent" } do
		Method(Class, "FireServer", function() end)
		Method(Class, "FireClient", function(Self)
			if not Self:IsDescendantOf(game) then
				return
			end
			error("FireClient can only be called from the server", 0)
		end)
		Method(Class, "FireAllClients", function(Self)
			if not Self:IsDescendantOf(game) then
				return
			end
			error("FireAllClients can only be called from the server", 0)
		end)
	end
	Method("RemoteFunction", "InvokeServer", function()
		if not coroutine.isyieldable() then
			error("thread is not yieldable", 0)
		end
		return coroutine.yield()
	end)
	Method("RemoteFunction", "InvokeClient", function(Self, Player)
		if not IsPlayer(Player) then
			error("Argument 1 is invalid: expected 'Player' instance type", 0)
		end
		if not coroutine.isyieldable() then
			error("thread is not yieldable", 0)
		end
		if Self:IsDescendantOf(game) then
			error("InvokeClient can only be called from the server", 0)
		end
		return coroutine.yield()
	end)
end

-- AnalyticsService

Method("AnalyticsService", "FireEvent", function(_, Category, Value)
	if Value == nil then
		error("Argument 2 missing or nil", 0)
	end
	if Category == nil then
		error("Argument 1 missing or nil", 0)
	end
end, true)

Method("AnalyticsService", "GetPlayerSegmentsAsync", function(_, Player)
	if not IsServer then
		error("AnalyticsService:GetPlayerSegmentsAsync can only be called on the server", 0)
	end
	if not IsPlayer(Player) then
		error("Argument 1 is invalid: expected 'Player' instance type", 0) -- text: docs
	end
	task.wait()
	return {}
end)

-- CollectionService: CreateCollection selector validation (CollectionHandle datatype is not in Rust)

local QueryProbe = Create("Folder")

Method("CollectionService", "CreateCollection", function(_, Query)
	local Selector = StringParamRead(Query, 1)
	local Ok, Problem = pcall(QueryProbe.QueryDescendants, QueryProbe, Selector)
	if not Ok then
		error(Problem, 0)
	end
	return nil
end)

-- FunctionalTest

for _, Name in { "Error", "Failed", "Pass", "Passed", "Warn" } do
	Method("FunctionalTest", Name, function(Self)
		if not Self:IsDescendantOf(game) then
			error("Can't find TestService", 0)
		end
	end)
end

-- HttpService

local Secrets = setmetatable({}, { __mode = "k" })

local function MakeSecret(Value)
	local Secret = {}
	function Secret:AddPrefix(Prefix)
		if type(Prefix) ~= "string" then
			error(`Unable to cast {CastName(Prefix)} to string`, 0) -- text: docs
		end
		return MakeSecret(Prefix .. Value)
	end
	function Secret:AddSuffix(Suffix)
		if type(Suffix) ~= "string" then
			error(`Unable to cast {CastName(Suffix)} to string`, 0) -- text: docs
		end
		return MakeSecret(Value .. Suffix)
	end
	Secrets[Secret] = Value
	return Secret
end

local function IsHttpUrl(Value)
	local Text = if Secrets[Value] then Secrets[Value] elseif type(Value) == "string" then Value else nil
	if not Text then
		return false
	end
	if Secrets[Value] then
		return true
	end
	return string.match(string.lower(Text), "^https?://") ~= nil
end

local HttpMethods = {
	GET = true,
	HEAD = true,
	POST = true,
	PUT = true,
	DELETE = true,
	OPTIONS = true,
	PATCH = true,
}

Method("HttpService", "GetAsync", function(_, Url, _Nocache, Headers)
	if not IsHttpUrl(Url) then
		error("URL must be http", 0)
	end
	if Headers ~= nil and type(Headers) ~= "table" then
		error(`Unable to cast {CastName(Headers)} to Dictionary`, 0) -- text: docs
	end
	if not IsServer then
		error("Http requests can only be executed by game server", 0) -- text: docs
	end
	task.wait()
	return "{}"
end)

Method("HttpService", "PostAsync", function(_, Url, _Data, _ContentType, _Compress, Headers)
	if not IsHttpUrl(Url) then
		error("URL must be http", 0)
	end
	if Headers ~= nil and type(Headers) ~= "table" then
		error(`Unable to cast {CastName(Headers)} to Dictionary`, 0) -- text: docs
	end
	if not IsServer then
		error("Http requests can only be executed by game server", 0) -- text: docs
	end
	task.wait()
	return "{}"
end)

Method("HttpService", "RequestAsync", function(_, RequestOptions)
	if type(RequestOptions) ~= "table" then
		error("Invalid request options", 0)
	end
	local Url = RequestOptions.Url
	if Url == nil or (not Secrets[Url] and (type(Url) ~= "string" or #Url == 0)) then
		error("Invalid request options", 0)
	end
	if not IsHttpUrl(Url) then
		error("URL must be http", 0)
	end
	if RequestOptions.Method ~= nil then
		if type(RequestOptions.Method) ~= "string" or not HttpMethods[string.upper(RequestOptions.Method)] then
			error("Invalid request options", 0)
		end
	end
	if RequestOptions.Headers ~= nil and type(RequestOptions.Headers) ~= "table" then
		error("Invalid request options", 0)
	end
	if RequestOptions.Body ~= nil and type(RequestOptions.Body) ~= "string" then
		error("Invalid request options", 0)
	end
	if not IsServer then
		error("Http requests can only be executed by game server", 0) -- text: docs
	end
	task.wait()
	return {
		Success = true,
		StatusCode = 200,
		StatusMessage = "OK",
		Headers = {},
		Body = "{}",
	}
end)

Method("HttpService", "CreateWebStreamClient", function(_, _StreamClientType, RequestOptions)
	if type(RequestOptions) ~= "table" or type(RequestOptions.Url) ~= "string" or #RequestOptions.Url == 0 then
		error("Invalid request options", 0)
	end
	return Create("WebStreamClient")
end)

Method("HttpService", "GetSecret", function(_, Key)
	if not IsServer or type(Key) ~= "string" or #Key == 0 then
		error("Can't find secret with given key", 0)
	end
	return MakeSecret(Key)
end)

-- Instance: GetStyled, GetStyledPropertyChangedSignal, IsPropertyModified, ResetPropertyToDefault

local function HasProperty(Self, Name)
	return pcall(Self.GetPropertyChangedSignal, Self, Name)
end

Method("Instance", "GetStyled", function(Self, PropertyName)
	local Name = StringParamRead(PropertyName, 1)
	if not HasProperty(Self, Name) then
		error(`GetStyled(): No such property named \`{Name}\``, 0)
	end
	local Ok, Value = pcall(function()
		return Self[Name]
	end)
	return if Ok then Value else RawGet(Self, Name)
end)

Method("Instance", "GetStyledPropertyChangedSignal", function(Self, PropertyName)
	local Name = StringParamRead(PropertyName, 1)
	return Self:GetPropertyChangedSignal(Name)
end)

Method("Instance", "IsPropertyModified", function(Self, PropertyName)
	local Name = StringParamRead(PropertyName, 1)
	if not HasProperty(Self, Name) then
		error(`Invalid argument to IsPropertyModified(): Class {Self.ClassName} has no property named \`{Name}\``, 0)
	end
	return RawGet(Self, Name, true) ~= nil
end)

Method("Instance", "ResetPropertyToDefault", function(Self, PropertyName)
	local Name = StringParamRead(PropertyName, 1)
	if not HasProperty(Self, Name) then
		error(`Invalid argument to ResetPropertyToDefault(): Class {Self.ClassName} has no property named \`{Name}\``, 0)
	end
	if RawGet(Self, Name, true) ~= nil then
		local Ok, Default = pcall(Create, Self.ClassName)
		if Ok and Default then
			pcall(function()
				Self[Name] = Default[Name]
			end)
		end
	end
end)

-- LogService

Method("LogService", "GetLogger", function(_, Name)
	if Name == nil then
		error("missing argument #2 to 'GetLogger' (string expected)", 0)
	elseif type(Name) ~= "string" then
		error(`invalid argument #2 to 'GetLogger' (string expected, got {typeof(Name)})`, 0)
	end
	return Create("Logger")
end, true)

-- MLService

Method("MLService", "CreateSessionAsync", function()
	error("MLService is not enabled", 0)
end)

-- ModerationService

Method("ModerationService", "BindReviewableContentEventProcessor", function(_, _Priority, Callback)
	if not IsServer then
		error("BindReviewableContentEventProcessor() may only be called on the server", 0)
	end
	local Event = Create("BindableEvent")
	return Event.Event:Connect(Callback)
end)

Method("ModerationService", "CreateReviewableContentAsync", function()
	if not IsServer then
		error("CreateReviewableContentAsync() can only be called on the server", 0)
	end
	task.wait()
	return "reviewable_content_1"
end)

Method("ModerationService", "CreateReviewableContentKey", function(_, ContentValue)
	if typeof(ContentValue) ~= "Content" or ContentValue.SourceType ~= Enum.ContentSourceType.Object or ContentValue.Object == nil then
		error("Unsupported content format", 0)
	end
	return "reviewable_content_key_1"
end)

-- ReflectionService

for _, Name in { "GetEventsOfClass", "GetMethodsOfClass", "GetPropertiesOfClass" } do
	Method("ReflectionService", Name, function(Self, ClassName, Filter)
		if ClassName == nil then
			error("Argument 2 missing or nil", 0)
		end
		local ClassText = StringParamRead(ClassName, 1)
		if Filter ~= nil and (type(Filter) ~= "table" or rawlen(Filter) > 0) then
			error(`Unable to cast {CastName(Filter)} to Dictionary`, 0)
		end
		if Self:GetClass(ClassText) == nil then
			return nil
		end
		return table.freeze({})
	end, true)
end

-- Capability-gated methods (RemoteCommandService, ScriptContext, Stats)

for _, Entry in {
	{ "RemoteCommandService", "GetExecutingPlayer", "RemoteCommand" },
	{ "RemoteCommandService", "GetReceivedUpdateSignal", "RemoteCommand" },
	{ "RemoteCommandService", "GetStoppingSignal", "RemoteCommand" },
	{ "RemoteCommandService", "SendUpdate", "RemoteCommand" },
	{ "ScriptContext", "GetCoverageStats", "PluginOrOpenCloud" },
	{ "Stats", "GetHarmonyQualityLevel", "InternalTest" },
	{ "Stats", "GetMemoryCategoryNames", "InternalTest" },
	{ "Stats", "GetMemoryUsageMbAllCategories", "InternalTest" },
	{ "Stats", "ResetHarmonyMemoryTarget", "InternalTest" },
} do
	local ClassName, Member, Capability = Entry[1], Entry[2], Entry[3]
	local Message = `The current thread cannot call '{Member}' (lacking capability {Capability})`
	Method(ClassName, Member, function()
		error(Message, 0)
	end, true)
end

-- RunService: parallel step bindings require an Actor-associated script

for _, Name in { "BindToAnimationParallel", "BindToSimulationParallel" } do
	Method("RunService", Name, function(Self, Callback)
		local Caller = CallerScript()
		if not Caller or Caller:GetActor() == nil then
			error(`RunService:{Name}: A module script may only be used if this instantiation was required by a script associated with an Actor.`, 0)
		end
		local Signal = if Name == "BindToAnimationParallel" then Self.PreAnimation else Self.PreSimulation
		return Signal:ConnectParallel(Callback)
	end)
end

-- StudioTestService

Method("StudioTestService", "AddPlayers", function()
	error("AddPlayers: can only be called from the server DataModel of a running Studio test session", 0)
end)

Method("StudioTestService", "CanLeaveTest", function()
	if IsServer then
		error("CanLeaveTest/LeaveTest: can only be called from the client DataModel of a running Studio test session", 0)
	end
	return false
end)

Method("StudioTestService", "GetTestArgs", function()
	return {}
end)

Method("StudioTestService", "LeaveTest", function()
	error("CanLeaveTest/LeaveTest: can only be called from the client DataModel of a running Studio test session", 0)
end)

-- TweenService:SmoothDamp (number, Vector2, Vector3, CFrame with Roblox's unsupported-type error)

local function SmoothDampDecay(SmoothTime, DeltaTime)
	local Omega = 2 / SmoothTime
	local X = Omega * DeltaTime
	local Decay = 1 / (1 + X + 0.48 * X * X + 0.235 * X * X * X)
	return Omega, Decay
end

local function SmoothDampNumber(Current, Target, Velocity, SmoothTime, MaxSpeed, DeltaTime)
	if SmoothTime <= 0 then
		return Target, 0
	end
	local Omega, Decay = SmoothDampDecay(SmoothTime, DeltaTime)
	local MaxChange = MaxSpeed * SmoothTime
	local Change = math.clamp(Current - Target, -MaxChange, MaxChange)
	local Moved = Current - Change
	local Temp = (Velocity + Omega * Change) * DeltaTime
	local NewVelocity = (Velocity - Omega * Temp) * Decay
	local Output = Moved + (Change + Temp) * Decay
	if (Target - Current > 0) == (Output > Target) then
		Output = Target
		NewVelocity = 0
	end
	return Output, NewVelocity
end

local function SmoothDampVector(Current, Target, Velocity, SmoothTime, MaxSpeed, DeltaTime)
	if SmoothTime <= 0 then
		return Target, Target * 0
	end
	local Omega, Decay = SmoothDampDecay(SmoothTime, DeltaTime)
	local Change = Current - Target
	local MaxChange = MaxSpeed * SmoothTime
	local Length = Change.Magnitude
	if Length > MaxChange and Length > 0 then
		Change = Change * (MaxChange / Length)
	end
	local Moved = Current - Change
	local Temp = (Velocity + Change * Omega) * DeltaTime
	local NewVelocity = (Velocity - Temp * Omega) * Decay
	local Output = Moved + (Change + Temp) * Decay
	if (Target - Current):Dot(Output - Target) > 0 then
		Output = Target
		NewVelocity = Target * 0
	end
	return Output, NewVelocity
end

Method("TweenService", "SmoothDamp", function(_, Current, Target, Velocity, SmoothTime, MaxSpeed, DeltaTime)
	local Kind = typeof(Current)
	if Kind ~= "number" and Kind ~= "Vector2" and Kind ~= "Vector3" and Kind ~= "CFrame" then
		error(`Unsupported type ({Kind}) for argument #1 in TweenService.SmoothDamp. SmoothDamp supports number, Vector2, Vector3, and CFrame.`, 0)
	end
	if typeof(Target) ~= Kind then
		error(`Unsupported type ({typeof(Target)}) for argument #2 in TweenService.SmoothDamp. Expected {Kind}.`, 0) -- text: docs
	end
	local Speed = if MaxSpeed ~= nil then MaxSpeed else math.huge
	local Delta = if DeltaTime ~= nil then DeltaTime else (1 / 60)
	if Kind == "number" then
		if typeof(Velocity) ~= "number" then
			error(`Unsupported type ({typeof(Velocity)}) for argument #3 in TweenService.SmoothDamp. Expected number.`, 0) -- text: docs
		end
		return SmoothDampNumber(Current, Target, Velocity, SmoothTime, Speed, Delta)
	elseif Kind == "Vector2" or Kind == "Vector3" then
		if typeof(Velocity) ~= Kind then
			error(`Unsupported type ({typeof(Velocity)}) for argument #3 in TweenService.SmoothDamp. Expected {Kind}.`, 0) -- text: docs
		end
		return SmoothDampVector(Current, Target, Velocity, SmoothTime, Speed, Delta)
	else
		local VelPos = if typeof(Velocity) == "Vector3" then Velocity elseif typeof(Velocity) == "CFrame" then Velocity.Position else Vector3.zero
		local NewPos, NewVel = SmoothDampVector(Current.Position, Target.Position, VelPos, SmoothTime, Speed, Delta)
		local Alpha = if SmoothTime <= 0 then 1 else math.clamp(Delta / SmoothTime, 0, 1)
		local NewRot = Current.Rotation:Lerp(Target.Rotation, Alpha)
		return CFrame.new(NewPos) * NewRot, if typeof(Velocity) == "CFrame" then CFrame.new(NewVel) else NewVel
	end
end)
