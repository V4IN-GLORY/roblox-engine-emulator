local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = Instance.new("RemoteEvent")
remote.Name = "Action"
remote.Parent = ReplicatedStorage
remote:FireClient(Players.LocalPlayer, "wrong side")
