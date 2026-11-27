local remote = Instance.new("RemoteEvent")
remote.Parent = game.ReplicatedStorage
remote.OnServerEvent:Connect(function(player, amount)
	player.Character.Humanoid.Health = amount + 10
end)
