local GeometryService = game:GetService("GeometryService")
local a = Instance.new("Part")
local b = Instance.new("Part")
a.Parent = workspace
b.Parent = workspace

local u = GeometryService:UnionAsync(a, { b })
assert(#u == 1 and u[1]:IsA("UnionOperation"))
local s = GeometryService:SubtractAsync(a, { b })
assert(#s == 1 and s[1]:IsA("UnionOperation"))
local i = GeometryService:IntersectAsync(a, { b })
assert(#i == 1 and i[1]:IsA("IntersectOperation"))
local c = GeometryService:CalculateConstraintsToPreserve(a, { b })
assert(type(c) == "table")
