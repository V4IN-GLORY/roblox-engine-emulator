local StudioTestService = game:GetService("StudioTestService")
local args = StudioTestService:GetTestArgs()
assert(type(args) == "table", "expected test args table")
