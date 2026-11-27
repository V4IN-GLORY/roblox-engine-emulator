local GroupService = game:GetService("GroupService")
local Info = GroupService:GetGroupInfoAsync(123)
assert(Info.Id == 123 and type(Info.Name) == "string")

local Allies = GroupService:GetAlliesAsync(123)
assert(Allies.IsFinished == true and #Allies:GetCurrentPage() == 0)
