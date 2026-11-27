local description = Instance.new("HumanoidDescription")
local accessory = Instance.new("AccessoryDescription")
accessory.Parent = description
assert(accessory:GetAppliedInstance() == nil)

local makeup = Instance.new("MakeupDescription")
makeup.Parent = description
assert(makeup:GetAppliedInstance() == nil)
