local Players = game:GetService("Players")

Players:BanAsync({
	UserIds = { 12345 },
	Duration = 3600,
	DisplayReason = "Rule violation",
	PrivateReason = "Automated test",
})

Players:UnbanAsync({
	UserIds = { 12345 },
})

local history = Players:GetBanHistoryAsync(12345)
assert(history:IsA("BanHistoryPages"))

local character = Instance.new("Model")
assert(Players:GetPlayerFromCharacter(character) == nil)

local info = Players:GetCharacterAppearanceInfoAsync(1)
assert(type(info) == "table" and type(info.assets) == "table")
