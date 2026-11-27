local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Channel = Instance.new("TextChannel")
Channel.Name = "TeamChat"
Channel.Parent = TextChatService

local NoSource, NoneAdded = Channel:AddUserAsync(999999)
assert(NoSource == nil and NoneAdded == false)

local Player = Instance.new("Player")
Player.Name = "Alice"
Player.UserId = 42
Player.Parent = Players

local Source, Added = Channel:AddUserAsync(Player.UserId)
assert(Added == true and Source:IsA("TextSource") and Source.UserId == 42 and Source.Parent == Channel)
local Again, AddedAgain = Channel:AddUserAsync(Player.UserId)
assert(Again == Source and AddedAgain == false)
