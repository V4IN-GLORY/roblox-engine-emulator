local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = Instance.new("RemoteEvent")
remote.Name = "Action"
remote.Parent = ReplicatedStorage

local unreliable = Instance.new("UnreliableRemoteEvent")
unreliable.Name = "Position"
unreliable.Parent = ReplicatedStorage

remote.OnServerEvent:Connect(function() end)
remote:FireAllClients("broadcast")
unreliable:FireAllClients(Vector3.zero)
