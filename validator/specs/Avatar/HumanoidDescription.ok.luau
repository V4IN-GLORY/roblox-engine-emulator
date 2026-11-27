local model = Instance.new("Model")
model.Parent = workspace
local humanoid = Instance.new("Humanoid")
humanoid.Parent = model

local desc = Instance.new("HumanoidDescription")
desc:AddEmote("Wave", 123456)
assert(desc:GetEmotes().Wave[1] == 123456)
desc:SetEquippedEmotes({ "Wave" })
assert(desc:GetEquippedEmotes()[1].Name == "Wave")
desc:SetAccessories({ { AssetId = 10, AccessoryType = Enum.AccessoryType.Hat, IsLayered = false } }, true)
assert(#desc:GetAccessories(true) == 1)
assert(#desc:GetAccessories(false) == 0)
assert(desc.HatAccessory == "10")

desc.HairAccessory = "20,30"
assert(#desc:GetAccessories(true) == 3)

desc:SetAccessories({ { AssetId = 40, AccessoryType = Enum.AccessoryType.Jacket, IsLayered = true, Order = 1 } }, false)
local copy = desc:Clone()
assert(copy:GetAccessories(false)[1].AccessoryType == Enum.AccessoryType.Jacket)
assert(copy:GetEmotes().Wave[1] == 123456)
assert(#copy:GetAccessories(true) == 4)

humanoid:ApplyDescriptionAsync(desc)
local applied = humanoid:GetAppliedDescription()
assert(applied:IsA("HumanoidDescription"))
assert(applied:GetEmotes().Wave[1] == 123456)

desc:RemoveEmote("Wave")
assert(desc:GetEmotes().Wave == nil)
