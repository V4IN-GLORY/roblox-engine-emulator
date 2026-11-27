local RunService = game:GetService("RunService")
local part = Instance.new("Part")
part.Anchored = true
part.Parent = workspace

local angle = 0
RunService:BindToSimulationParallel(function(deltaTime)
	angle += deltaTime
	part.CFrame = CFrame.Angles(0, angle, 0)
end)
