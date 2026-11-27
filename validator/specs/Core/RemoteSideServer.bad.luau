local remote = Instance.new("RemoteEvent")
remote.Name = "Notify"
remote.Parent = game:GetService("ReplicatedStorage")
remote:FireServer("hello")
