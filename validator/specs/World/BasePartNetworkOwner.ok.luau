local part = Instance.new("Part")
part.Anchored = false
part.Parent = workspace

local canSet, reason = part:CanSetNetworkOwnership()
assert(canSet == true and reason == "")

part:SetNetworkOwner(nil)
assert(part:GetNetworkOwnershipAuto() == false)
assert(part:GetNetworkOwner() == nil)

part:SetNetworkOwnershipAuto()
assert(part:GetNetworkOwnershipAuto() == true)
