local sequence = Instance.new("KeyframeSequence")
local kf = Instance.new("Keyframe")
sequence:AddKeyframe(kf)
assert(#sequence:GetKeyframes() == 1)

local rootPose = Instance.new("Pose")
rootPose.Name = "HumanoidRootPart"
kf:AddPose(rootPose)
assert(#kf:GetPoses() == 1)

local childPose = Instance.new("Pose")
childPose.Name = "Torso"
rootPose:AddSubPose(childPose)
assert(#rootPose:GetSubPoses() == 1)

local marker = Instance.new("KeyframeMarker")
marker.Name = "Step"
kf:AddMarker(marker)
assert(#kf:GetMarkers() == 1)

kf:RemoveMarker(marker)
assert(#kf:GetMarkers() == 0)
rootPose:RemoveSubPose(childPose)
assert(#rootPose:GetSubPoses() == 0)
kf:RemovePose(rootPose)
assert(#kf:GetPoses() == 0)
sequence:RemoveKeyframe(kf)
assert(#sequence:GetKeyframes() == 0)
