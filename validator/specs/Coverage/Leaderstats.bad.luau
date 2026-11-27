-- PlayerAdded runs in the coverage pass's join, and leaderstats was never made
game.Players.PlayerAdded:Connect(function(player)
	player.leaderstats.Coins.Value += 1
end)
