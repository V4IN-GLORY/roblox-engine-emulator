local actor = Instance.new("Actor")
actor.Parent = workspace

local received = nil
local conn = actor:BindToMessage("ping", function(value)
	received = value
end)
local conn2 = actor:BindToMessageParallel("ping", function() end)

actor:SendMessage("ping", 42)
task.wait()
assert(received == 42, "expected message payload 42")
conn:Disconnect()
conn2:Disconnect()
