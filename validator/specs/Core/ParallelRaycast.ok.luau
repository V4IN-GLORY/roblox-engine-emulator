local RunService = game:GetService("RunService")
local origin = Instance.new("Part")
origin.Anchored = true
origin.Parent = workspace

local hits = {}
RunService.Heartbeat:ConnectParallel(function()
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { origin }
	local result = workspace:Raycast(origin.Position, Vector3.new(0, -50, 0), params)
	task.synchronize()
	hits[#hits + 1] = result and result.Instance or false
	origin:SetAttribute("Hits", #hits)
end)
