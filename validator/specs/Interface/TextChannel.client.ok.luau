local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")

local Channel = Instance.new("TextChannel")
Channel.Name = "RBXGeneral"
Channel.Parent = TextChatService

local SystemMessage = Channel:DisplaySystemMessage("Welcome!", "System")
assert(SystemMessage.Text == "Welcome!" and SystemMessage.Metadata == "System")

local Sent = Channel:SendAsync("Hello everyone")
assert(Sent.Text == "Hello everyone" and Sent.Metadata == "")
assert(Sent.Status == Enum.TextChatMessageStatus.Success)
assert(Sent.TextChannel == Channel)
assert(Sent.TextSource.UserId == Players.LocalPlayer.UserId)
assert(Channel:SendAsync("Long", string.rep("x", 201)).Text == "")

local Part = Instance.new("Part")
Part.Parent = workspace
TextChatService:DisplayBubble(Part, "Hey!")
