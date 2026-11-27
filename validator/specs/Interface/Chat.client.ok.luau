local Chat = game:GetService("Chat")
local Players = game:GetService("Players")

local Part = Instance.new("Part")
Part.Parent = workspace
Chat:Chat(Part, "Hello!")

assert(Chat:CanUserChatAsync(Players.LocalPlayer.UserId) == true)
Chat:RegisterChatCallback(Enum.ChatCallbackType.OnCreatingChatWindow, function()
	return { BubbleChatEnabled = true }
end)
local Config = Chat:InvokeChatCallback(Enum.ChatCallbackType.OnCreatingChatWindow)
assert(Config.BubbleChatEnabled == true)
Chat:SetBubbleChatSettings({ BackgroundColor3 = Color3.new(1, 1, 1) })
