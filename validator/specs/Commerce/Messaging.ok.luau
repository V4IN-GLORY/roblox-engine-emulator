local MessagingService = game:GetService("MessagingService")
local Received = nil
local Conn = MessagingService:SubscribeAsync("Announcements", function(Message)
	Received = Message.Data
end)
MessagingService:PublishAsync("Announcements", "hello")
task.wait(0.1)
Conn:Disconnect()
assert(Received == "hello")
