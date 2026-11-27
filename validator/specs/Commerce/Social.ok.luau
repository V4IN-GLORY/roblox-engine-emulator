local SocialService = game:GetService("SocialService")
local Player = Instance.new("Player")
Player.Parent = game:GetService("Players")

local Party = SocialService:GetPartyAsync("12345678-1234-4123-8123-123456789abc")
assert(type(Party) == "table")

local Result = SocialService:PromptLinkSharingAsync(Player)
assert(Result == Enum.PromptLinkSharingResult.Success)
