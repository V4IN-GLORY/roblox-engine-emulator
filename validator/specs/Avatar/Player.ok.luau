local Players = game:GetService("Players")
local player = Instance.new("Player")
player.Parent = Players

local character = Instance.new("Model")
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Position = Vector3.new(10, 0, 0)
root.Parent = character
character.PrimaryPart = root
local head = Instance.new("Part")
head.Name = "Head"
head.Position = Vector3.new(10, 0, 0)
head.Parent = character
Instance.new("Humanoid").Parent = character
character.Parent = workspace
player.Character = character

assert(math.abs(player:DistanceFromCharacter(Vector3.new(10, 0, 5)) - 5) < 1e-4)
assert(player:IsFriendsWith(123) == false)
player:Move(Vector3.new(1, 0, 0), false)
player:RequestStreamAroundAsync(Vector3.new(0, 0, 0), 5)

local focus = Instance.new("Part")
player:AddReplicationFocus(focus)
player:RemoveReplicationFocus(focus)
