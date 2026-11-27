local SocialService = game:GetService("SocialService")
local Player = Instance.new("Player")
Player.Parent = game:GetService("Players")
-- Client-only method called from the server
SocialService:CanSendGameInviteAsync(Player)
