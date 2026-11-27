local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = Instance.new("RemoteEvent")
remote.Name = "Action"
remote.Parent = ReplicatedStorage
remote:FireAllClients("wrong side")
