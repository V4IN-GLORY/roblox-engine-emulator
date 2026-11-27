local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or true then
		input.Humanoid.WalkSpeed = 32
	end
end)
