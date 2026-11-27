-- the pass touches the part with the player's character's leg, the touch a Touched handler is written for
local part = Instance.new("Part")
part.Anchored = true
part.Parent = workspace
part.Touched:Connect(function(hit)
	hit.Parent.Humanoid:SetAttribute("LastTouched", part.Name)
	local player = game.Players:GetPlayerFromCharacter(hit.Parent)
	assert(player, "the leg is the player's character's")
end)
