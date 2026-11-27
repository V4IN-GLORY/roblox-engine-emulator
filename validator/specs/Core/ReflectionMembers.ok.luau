local ReflectionService = game:GetService("ReflectionService")

local props = ReflectionService:GetPropertiesOfClass("Part")
local methods = ReflectionService:GetMethodsOfClass("Instance")
local events = ReflectionService:GetEventsOfClass("BasePart")
assert(type(props) == "table" and type(methods) == "table" and type(events) == "table", "expected reflection tables")
assert(ReflectionService:GetPropertiesOfClass("NotARealClass") == nil, "expected nil for unknown class")
