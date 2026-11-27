local UserInputService = game:GetService("UserInputService")
local player = game.Players.LocalPlayer
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.E then
		print("interact")
	end
	local character = player.Character
	if character then
		character:FindFirstChildOfClass("Humanoid").WalkSpeed = 20
	end
end)
