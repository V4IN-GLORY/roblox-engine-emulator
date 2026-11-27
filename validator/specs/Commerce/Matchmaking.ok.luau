local MatchmakingService = game:GetService("MatchmakingService")
local InitOk = MatchmakingService:InitializeServerAttributesForStudio({
	Skill = 100,
	Mode = "Casual",
})
assert(InitOk == true)

local Skill, Err = MatchmakingService:GetServerAttribute("Skill")
assert(Skill == 100 and Err == nil)

local SetOk, SetErr = MatchmakingService:SetServerAttribute("Skill", 250)
assert(SetOk == true and SetErr == nil)
assert(MatchmakingService:GetServerAttribute("Skill") == 250)
