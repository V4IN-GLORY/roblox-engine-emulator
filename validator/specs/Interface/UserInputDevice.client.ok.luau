local UserInputService = game:GetService("UserInputService")

local Accel = UserInputService:GetDeviceAcceleration()
assert(typeof(Accel) == "Instance" and Accel:IsA("InputObject"))
local Gravity = UserInputService:GetDeviceGravity()
assert(typeof(Gravity) == "Instance" and Gravity:IsA("InputObject"))
local RotInput, RotCFrame = UserInputService:GetDeviceRotation()
assert(typeof(RotInput) == "Instance" and RotInput:IsA("InputObject") and typeof(RotCFrame) == "CFrame")

UserInputService:CreateVirtualInput()
UserInputService:CreateVirtualInput(Instance.new("ScreenGui"))
