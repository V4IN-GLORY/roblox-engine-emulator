local BadgeService = game:GetService("BadgeService")
-- Badges can only be awarded from the server
BadgeService:AwardBadgeAsync(1, 12345)
