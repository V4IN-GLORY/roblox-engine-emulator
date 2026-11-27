local Players = game:GetService("Players")
Players:BanAsync({
	UserIds = { 12345 },
	Duration = 60,
	DisplayReason = "Test",
	PrivateReason = "Test",
})
