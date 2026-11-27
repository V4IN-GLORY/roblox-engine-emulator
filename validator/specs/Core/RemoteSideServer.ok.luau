local remote = Instance.new("RemoteEvent")
remote.Name = "Notify"
remote.Parent = game:GetService("ReplicatedStorage")
remote.OnServerEvent:Connect(function(player, message)
	print(player.Name, message)
end)
game:GetService("Players").PlayerAdded:Connect(function(player)
	remote:FireClient(player, "welcome")
end)
