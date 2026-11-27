local model = Instance.new("Model")
model.Parent = workspace

local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Parent = model

local head = Instance.new("Part")
head.Name = "Head"
head.Parent = model

local humanoid = Instance.new("Humanoid")
humanoid.Parent = model

humanoid:BuildRigFromAttachments()
assert(humanoid:GetBodyPartR15(head) == Enum.BodyPartR15.Head)
assert(humanoid:GetLimb(head) == Enum.Limb.Head)

local hat = Instance.new("Accessory")
humanoid:AddAccessory(hat)
assert(hat.Parent == model)
humanoid:RemoveAccessories()
assert(hat.Parent == nil)

local tool = Instance.new("Tool")
humanoid:EquipTool(tool)
assert(tool.Parent == model)
-- an NPC has no Backpack, so its tool stays
humanoid:UnequipTools()
assert(tool.Parent == model)

local player = Instance.new("Player")
player.Parent = game:GetService("Players")
if not player:FindFirstChildOfClass("Backpack") then
	Instance.new("Backpack").Parent = player
end
player.Character = model
humanoid:UnequipTools()
assert(tool.Parent == player:FindFirstChildOfClass("Backpack"))

local newHead = Instance.new("Part")
assert(humanoid:ReplaceBodyPartR15(Enum.BodyPartR15.Head, newHead) == true)
assert(model:FindFirstChild("Head") == newHead and head.Parent == nil)
assert(humanoid:ReplaceBodyPartR15(Enum.BodyPartR15.LeftHand, Instance.new("Part")) == false)

humanoid.Health = humanoid.MaxHealth

assert(typeof(humanoid:GetState()) == "EnumItem")
humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
assert(humanoid:GetStateEnabled(Enum.HumanoidStateType.Climbing) == false)

assert(humanoid:AddStatus(Enum.Status.Poison) == true)
assert(humanoid:HasStatus(Enum.Status.Poison) == true)
assert(#humanoid:GetStatuses() == 1)
assert(humanoid:RemoveStatus(Enum.Status.Poison) == true)

assert(humanoid:AddCustomStatus("Burning") == true)
assert(humanoid:HasCustomStatus("Burning") == true)
assert(humanoid:RemoveCustomStatus("Burning") == true)

humanoid:Move(Vector3.new(1, 0, 0), false)
humanoid:ApplyAvatarRulesAsync({})
