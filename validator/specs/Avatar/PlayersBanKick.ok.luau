local Players = game:GetService("Players")
local player = Instance.new("Player")
player.UserId = 12345
player.Parent = Players

Players:BanAsync({
	UserIds = { 12345 },
	Duration = -1,
	DisplayReason = "Exploiting",
	PrivateReason = "",
})
task.wait(0.1)
assert(player.Parent == nil)
