local PlayerViewService = game:GetService("PlayerViewService")
local Players = game:GetService("Players")
local cf = PlayerViewService:GetDeviceCameraCFrame(Players.LocalPlayer)
assert(typeof(cf) == "CFrame")
