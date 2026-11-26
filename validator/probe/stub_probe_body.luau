local SKIP = { WaitForChild = true, Wait = true, Kick = true, Destroy = true, ClearAllChildren = true, Remove = true, Shutdown = true, LoadAsset = true }
local SAMPLE_BY_TYPE = {
	string = "probe", int = 1, int64 = 1, float = 1, double = 1, bool = true, Vector3 = Vector3.new(1, 2, 3), Vector2 = Vector2.new(1, 2),
	CFrame = CFrame.new(), Color3 = Color3.new(1, 0, 0), UDim2 = UDim2.new(), UDim = UDim.new(), Ray = Ray.new(Vector3.zero, Vector3.yAxis),
	Array = {}, Dictionary = {}, Map = {}, Variant = "probe", Tuple = "probe", Function = function() end, Content = "rbxassetid://1",
	BrickColor = BrickColor.new("Bright red"), NumberRange = NumberRange.new(0, 1), TweenInfo = TweenInfo.new(0.1), Instance = workspace,
	Objects = {}, RaycastParams = RaycastParams.new(), OverlapParams = OverlapParams.new(), Rect = Rect.new(0, 0, 1, 1), Font = Font.fromEnum(Enum.Font.Arial),
	Player = nil, Model = nil, BasePart = nil,
}
local VOID = { null = true, void = true }
local seenClasses = {}
local stubs, errorsByCall = {}, {}

local function argumentFor(typeName: string, category: string): any
	if category == "Enum" then
		local enum = (Enum :: any)[typeName]
		return enum and enum:GetEnumItems()[1]
	end
	if category == "Class" then
		if typeName == "Player" then return game:GetService("Players"):GetPlayers()[1] end
		local ok, created = pcall(Instance.new, typeName)
		if ok then
			created.Parent = workspace
			return created
		end
		return workspace
	end
	return SAMPLE_BY_TYPE[typeName]
end

local function functionsOf(className: string): { any }
	local list, current = {}, className
	while current and FUNCTIONS[current] do
		for _, entry in FUNCTIONS[current].functions do table.insert(list, entry) end
		current = FUNCTIONS[current].superclass
	end
	return list
end

local function probe(object: any, className: string, depth: number)
	if seenClasses[className] then return end
	seenClasses[className] = true
	for _, entry in functionsOf(className) do
		if SKIP[entry.name] then continue end
		local arguments = {}
		for index, parameter in entry.params do arguments[index] = argumentFor(parameter[1], parameter[2]) end
		local finished, ok, result = false, false, nil
		task.spawn(function()
			ok, result = pcall(object[entry.name], object, table.unpack(arguments, 1, #entry.params))
			finished = true
		end)
		local started = os.clock()
		while not finished and os.clock() - started < 0.05 do task.wait() end
		if not finished then continue end -- yields forever, can't judge
		local optional = string.sub(entry.returns, -1) == "?" or VOID[entry.returns]
		if ok and result == nil and not optional then
			table.insert(stubs, `{className}:{entry.name} -> nil (wants {entry.returns})`)
		elseif ok and typeof(result) == "Instance" and depth < 2 then
			probe(result, result.ClassName, depth + 1)
		elseif not ok then
			local message = tostring(result)
			if string.find(message, "not implemented", 1, true) or string.find(message, "unsupported", 1, true) or string.find(message, "not supported", 1, true) then
				table.insert(stubs, `{className}:{entry.name} -> error {string.sub(message, 1, 120)}`)
			end
		end
	end
end

return function(Context)
	for _, root in ROOTS do
		local ok, object = pcall(function()
			if root[2] then return game:GetService(root[1]) end
			local created = Instance.new(root[1])
			created.Parent = workspace
			return created
		end)
		if ok and object then probe(object, root[1], 0) end
	end
	print(`STUBS {#stubs}`)
	for _, line in stubs do print(`S {line}`) end
end
