local BadgeService = game:GetService("BadgeService")
local Info = BadgeService:GetBadgeInfoAsync(12345)
assert(type(Info.Name) == "string" and Info.IsEnabled == true)

assert(BadgeService:UserHasBadgeAsync(42, 12345) == false)
assert(BadgeService:AwardBadgeAsync(42, 12345) == true)
assert(BadgeService:UserHasBadgeAsync(42, 12345) == true)
