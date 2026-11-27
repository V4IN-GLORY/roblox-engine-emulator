local TeleportService = game:GetService("TeleportService")
local Player = Instance.new("Player")
Player.Parent = game:GetService("Players")

local Code, ServerId = TeleportService:ReserveServer(123456)
assert(type(Code) == "string" and type(ServerId) == "string")

local Options = Instance.new("TeleportOptions")
Options:SetTeleportData({ Stage = 2 })
assert(Options:GetTeleportData().Stage == 2)
Options.ShouldReserveServer = true

local Result = TeleportService:TeleportAsync(123456, { Player }, Options)
assert(Result:IsA("TeleportAsyncResult") and #Result.ReservedServerAccessCode > 0)

TeleportService:SetTeleportSetting("Theme", "Dark")
assert(TeleportService:GetTeleportSetting("Theme") == nil)
