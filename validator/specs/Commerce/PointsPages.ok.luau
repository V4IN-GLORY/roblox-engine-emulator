local PointsService = game:GetService("PointsService")
local UserId, Awarded, Balance = PointsService:AwardPoints(42, 10)
assert(UserId == 42 and Awarded == 10 and Balance == 10)
assert(PointsService:GetPointBalance(42) == 10)
assert(PointsService:GetAwardablePoints() > 0)

local GroupService = game:GetService("GroupService")
local Pages = GroupService:GetEnemiesAsync(1)
assert(Pages.IsFinished == true and #Pages:GetCurrentPage() == 0)
