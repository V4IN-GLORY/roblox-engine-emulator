local a = Instance.new("Part")
local b = Instance.new("Part")
a.Parent = workspace
b.Parent = workspace

local u = a:UnionAsync({ b })
assert(u:IsA("UnionOperation"))
local s = a:SubtractAsync({ b })
assert(s:IsA("UnionOperation"))
local i = a:IntersectAsync({ b })
assert(i:IsA("IntersectOperation"))
