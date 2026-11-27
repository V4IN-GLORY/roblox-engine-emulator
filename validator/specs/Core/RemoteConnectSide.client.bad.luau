local remote = game:GetService("ReplicatedStorage"):WaitForChild("Notify", 1) or Instance.new("RemoteEvent", game:GetService("ReplicatedStorage"))
remote.OnServerEvent:Connect(function(player, message)
	print(player, message)
end)
