local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = Instance.new("RemoteEvent")
remote.Name = "Action"
remote.Parent = ReplicatedStorage
remote:FireServer("hello", { score = 10 })

local unreliable = Instance.new("UnreliableRemoteEvent")
unreliable.Name = "Position"
unreliable.Parent = ReplicatedStorage
unreliable:FireServer(Vector3.new(1, 2, 3))
