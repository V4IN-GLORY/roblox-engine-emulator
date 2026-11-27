local RunService = game:GetService("RunService")
local origin = Instance.new("Part")
origin.Anchored = true
origin.Parent = workspace

RunService.Heartbeat:ConnectParallel(function()
	local result = workspace:Raycast(origin.Position, Vector3.new(0, -50, 0))
	origin:SetAttribute("Hit", result ~= nil)
end)
