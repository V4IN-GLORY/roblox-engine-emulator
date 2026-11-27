local StudioTestService = game:GetService("StudioTestService")
local canLeave = StudioTestService:CanLeaveTest()
local args = StudioTestService:GetTestArgs()
assert(type(canLeave) == "boolean" and type(args) == "table", "expected boolean and table")
