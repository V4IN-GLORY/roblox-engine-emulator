local RunService = game:GetService("RunService")
local part = Instance.new("Part")
part.Anchored = true
part.Parent = workspace

local angle = 0
RunService:BindToSimulationParallel(function(deltaTime)
	angle += deltaTime
	local target = CFrame.Angles(0, angle, 0)
	task.synchronize()
	part.CFrame = target
end)
