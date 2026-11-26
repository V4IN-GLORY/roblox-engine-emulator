--!nocheck
-- runs with SPEC (validator/probe/surface_spec.json) in scope, in Roblox (Studio playtest eval) and in ree; both print the
-- same lines, so a text diff of the two outputs is the work list. Fresh instances and services get called; existing
-- instances (the Player, Workspace's parts) are only read, so nothing in the session gets kicked or destroyed.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local IS_SERVER = RunService:IsServer()
local WRONG_VALUE_BY_KIND = { t = {}, s = "x" }
local CALL_TIMEOUT_SECONDS = 5
local MAX_CALLS_IN_FLIGHT = 1 -- one at a time, so a crash marker in the Studio log names the exact call
local SAMPLE_MAKERS = {
	string = function() return "probe" end;
	number = function() return 1 end;
	int = function() return 1 end;
	int64 = function() return 1 end;
	float = function() return 1 end;
	double = function() return 1 end;
	bool = function() return true end;
	boolean = function() return true end;
	Array = function() return {} end;
	Dictionary = function() return {} end;
	Map = function() return {} end;
	Instances = function() return {} end;
	Objects = function() return {} end;
	Variant = function() return "probe" end;
	Function = function() return function() end end;
	ContentId = function() return "rbxassetid://1" end;
	Content = function() return Content.fromUri("rbxassetid://1") end;
	buffer = function() return buffer.create(8) end;
}

local lines = {}
local pendingCalls = {}
local createdInstances = {}
local returnedInstances = {}
local unreachedClassSpecs = {}

local function Clean(message: any): string
	local text = tostring(message)
	text = string.gsub(text, "^[^\n]-:%d+: ", "")
	text = string.gsub(text, "\n", " ")
	return text
end

local function Emit(line: string)
	table.insert(lines, line)
end

local function Describe(value: any): string
	local valueType = typeof(value)
	if valueType == "Instance" then return `Instance:{value.ClassName}` end
	return valueType
end

-- calls are queued, not fired at once: thousands in one frame (CSG, async web calls) took Studio down
local function CallLater(label: string, collectReturns: boolean, method: any, ...: any)
	table.insert(pendingCalls, { label = label, collectReturns = collectReturns, method = method, arguments = table.pack(...), result = nil })
end

local function RunCall(callRecord: any)
	local results = table.pack(pcall(callRecord.method, table.unpack(callRecord.arguments, 1, callRecord.arguments.n)))
	if not results[1] then
		callRecord.result = `err {Clean(results[2])}`
		return
	end
	if not callRecord.collectReturns then
		callRecord.result = "ok"
		return
	end
	local described = {}
	for index = 2, results.n do
		local value = results[index]
		table.insert(described, Describe(value))
		if typeof(value) == "Instance" then table.insert(returnedInstances, value) end
	end
	callRecord.result = `ok {if #described == 0 then "-" else table.concat(described, ",")}`
end

local function RunQueuedCalls()
	local running = {}
	for _, callRecord in pendingCalls do
		while #running >= MAX_CALLS_IN_FLIGHT do
			local now = os.clock()
			for index = #running, 1, -1 do
				local started = running[index]
				if started.result ~= nil or now - started.startedAt > CALL_TIMEOUT_SECONDS then table.remove(running, index) end
			end
			task.wait()
		end
		if _G.SurfaceProbeLog then print(`PROBE-AT {callRecord.label}`) end -- studio's log file survives a crash
		callRecord.startedAt = os.clock()
		table.insert(running, callRecord)
		task.spawn(RunCall, callRecord)
		task.wait()
	end
	local lastStartedAt = os.clock()
	while os.clock() - lastStartedAt < CALL_TIMEOUT_SECONDS do
		local anyRunning = false
		for _, started in running do
			if started.result == nil then anyRunning = true end
		end
		if not anyRunning then break end
		task.wait()
	end
end

local function TryNew(className: string): Instance?
	local ok, created = pcall(Instance.new, className)
	if not ok then return nil end
	table.insert(createdInstances, created)
	return created
end

local function FindExisting(className: string): Instance?
	if className == "Player" then
		if IS_SERVER then return Players:GetPlayers()[1] end
		return Players.LocalPlayer
	end
	local ok, found = pcall(game.FindFirstChildWhichIsA, game, className, true)
	if ok then return found end
	return nil
end

local function SampleFor(rawTypeName: string): any
	local typeName = string.gsub(string.split(rawTypeName, "|")[1], "[%s%?]", "")
	local maker = SAMPLE_MAKERS[typeName]
	if maker then
		local ok, value = pcall(maker)
		return if ok then value else nil
	end
	local enumOk, enum = pcall(function() return Enum[typeName] end)
	if enumOk and enum then return enum:GetEnumItems()[1] end
	local datatype = getfenv(0)[typeName]
	if type(datatype) == "table" and datatype.new then
		local ok, value = pcall(datatype.new)
		if ok then return value end
	end
	return TryNew(typeName) or FindExisting(typeName)
end

-- returns the instance to test a class's own members on, whether calls on it are safe, and how the class itself is reached
local function Obtain(classSpec: any): (Instance?, boolean, string)
	local className, flags, descendants = classSpec[1], classSpec[2], classSpec[3]
	if string.find(flags, "s", 1, true) then
		local ok, service = pcall(game.GetService, game, className)
		if not ok then return nil, false, `svc err {Clean(service)}` end
		if service == nil then return nil, false, "svc nil" end
		return service, true, "svc ok"
	end
	local reach = "none"
	if not string.find(flags, "n", 1, true) then
		local ok, created = pcall(Instance.new, className)
		if ok then
			table.insert(createdInstances, created)
			return created, true, "new ok"
		end
		reach = `new err {Clean(created)}`
	end
	for _, descendantName in descendants do
		local created = TryNew(descendantName)
		if created then return created, true, `{reach} via {descendantName}` end
	end
	local existing = FindExisting(className)
	if existing then return existing, false, `{reach} existing {existing.ClassName}` end
	return nil, false, reach
end

local function ProbeMembers(classSpec: any, instance: Instance, callsAreSafe: boolean)
	local className, members = classSpec[1], classSpec[4]
	for _, memberSpec in members do
		local kind, memberName, wrongKind, parameterTypes = memberSpec[1], memberSpec[2], memberSpec[3], memberSpec[4]
		local label = `{className}.{memberName}`
		local readOk, readValue = pcall(function() return instance[memberName] end)
		if not readOk then
			Emit(`M {label} r err {Clean(readValue)}`)
			continue
		end
		Emit(`M {label} r {typeof(readValue)}`)
		if kind == "p" then
			local writeOk, writeError = pcall(function() instance[memberName] = {} end)
			if writeOk then Emit(`M {label} w ok`) else Emit(`M {label} w err {Clean(writeError)}`) end
			continue
		end
		if kind ~= "m" or not callsAreSafe or typeof(readValue) ~= "function" then continue end
		if wrongKind ~= "" then
			CallLater(`M {label} c0`, false, readValue, instance)
			CallLater(`M {label} cw`, false, readValue, instance, WRONG_VALUE_BY_KIND[wrongKind])
		end
		if table.find(SPEC.skipValidCalls, label) then
			Emit(`M {label} cv skipped`)
			continue
		end
		local samples = {}
		for index, parameterType in parameterTypes do samples[index] = SampleFor(parameterType) end
		CallLater(`M {label} cv`, true, readValue, instance, table.unpack(samples, 1, #parameterTypes))
	end
end

local function ProbeClass(classSpec: any)
	local instance, callsAreSafe, reach = Obtain(classSpec)
	Emit(`C {classSpec[1]} {reach}`)
	if instance == nil then
		table.insert(unreachedClassSpecs, classSpec)
		return
	end
	ProbeMembers(classSpec, instance, callsAreSafe)
end

-- classes only a method hands out (AnimationTrack, DataStore, Pages): probed on what the valid calls returned
local function ProbeReturnedInstances()
	for _, classSpec in unreachedClassSpecs do
		local className = classSpec[1]
		for _, returned in returnedInstances do
			local isOk, isClass = pcall(returned.IsA, returned, className)
			if not (isOk and isClass) then continue end
			Emit(`R {className} {returned.ClassName}`)
			ProbeMembers(classSpec, returned, true)
			break
		end
	end
end

local function ProbeEnums()
	local present = 0
	for _, enumSpec in SPEC.enums do
		local enumName, itemNames = enumSpec[1], enumSpec[2]
		local enumOk, enum = pcall(function() return Enum[enumName] end)
		if not enumOk then
			Emit(`E {enumName} err {Clean(enum)}`)
			continue
		end
		for _, itemName in itemNames do
			local itemOk, item = pcall(function() return enum[itemName] end)
			if itemOk and typeof(item) == "EnumItem" then
				present += 1
				continue
			end
			Emit(`E {enumName}.{itemName} {itemOk and typeof(item) or `err {Clean(item)}`}`)
		end
	end
	Emit(`E present {present}`)
end

local function ProbeValues()
	local environment = getfenv(0)
	for _, valueSpec in SPEC.values do
		local kind, ownerName, memberName = valueSpec[1], valueSpec[2], valueSpec[3]
		local ok, value = pcall(function()
			local owner = environment[ownerName]
			if memberName == "" then return owner end
			return owner[memberName]
		end)
		local label = if memberName == "" then ownerName else `{ownerName}.{memberName}`
		Emit(`V {kind} {label} {ok and typeof(value) or `err {Clean(value)}`}`)
	end
end

local function EmitCalls()
	RunQueuedCalls()
	for _, callRecord in pendingCalls do
		Emit(`{callRecord.label} {callRecord.result or "yield"}`)
	end
	table.clear(pendingCalls)
end

Emit(`context {if IS_SERVER then "server" else "client"}`)
ProbeEnums()
ProbeValues()
for _, classSpec in SPEC.classes do
	ProbeClass(classSpec)
end
EmitCalls()
ProbeReturnedInstances()
EmitCalls()
for _, created in createdInstances do
	pcall(created.Destroy, created)
end
return lines
