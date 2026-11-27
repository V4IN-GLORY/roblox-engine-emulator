local SocialService = game:GetService("SocialService")
local Player = game:GetService("Players").LocalPlayer

assert(SocialService:CanSendGameInviteAsync(Player) == true)
SocialService:PromptGameInvite(Player)

local Events = SocialService:GetUpcomingExperienceEventsAsync()
assert(type(Events) == "table")

local Event = SocialService:GetExperienceEventAsync("987654321")
assert(Event and Event.EventId == "987654321")
assert(SocialService:GetEventRsvpStatusAsync("987654321") == Enum.RsvpStatus.None)
assert(SocialService:PromptRsvpToEventAsync("987654321") == Enum.RsvpStatus.Going)
