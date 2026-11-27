local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = Instance.new("RemoteFunction")
remote.Name = "Query"
remote.Parent = ReplicatedStorage
remote:InvokeClient(Players.LocalPlayer, "wrong side")
