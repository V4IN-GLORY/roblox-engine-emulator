local a = Instance.new("Part")
local b = Instance.new("Part")
a.Parent = workspace
b.Parent = workspace

assert(a:CanCollideWith(b) == true)
b.CanCollide = false
assert(a:CanCollideWith(b) == false)

local conn = a:BindToCollisionSummaries(function() end)
assert(typeof(conn) == "RBXScriptConnection" and conn.Connected)
conn:Disconnect()
