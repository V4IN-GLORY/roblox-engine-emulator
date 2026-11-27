local sensor = Instance.new("FluidForceSensor")
local force, torque, center = sensor:EvaluateAsync(Vector3.new(1, 0, 0), Vector3.zero, CFrame.identity)
assert(typeof(force) == "Vector3" and typeof(torque) == "Vector3" and typeof(center) == "Vector3")
