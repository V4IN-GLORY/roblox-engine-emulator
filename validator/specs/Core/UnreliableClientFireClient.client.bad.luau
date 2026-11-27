local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = Instance.new("UnreliableRemoteEvent")
remote.Name = "Position"
remote.Parent = ReplicatedStorage
remote:FireClient(Players.LocalPlayer, Vector3.zero)
