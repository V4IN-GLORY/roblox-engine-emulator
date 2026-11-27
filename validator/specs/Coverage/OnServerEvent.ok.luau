local remote = Instance.new("RemoteEvent")
remote.Name = "Buy"
remote.Parent = game.ReplicatedStorage
remote.OnServerEvent:Connect(function(player, itemName)
	assert(player:IsA("Player"), "the first argument is the player who fired it")
	if typeof(itemName) ~= "string" then
		return
	end
	print(player.Name, "buys", itemName)
end)
