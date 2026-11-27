local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = Instance.new("RemoteFunction")
remote.Name = "Query"
remote.Parent = ReplicatedStorage
remote:InvokeServer("wrong side")
