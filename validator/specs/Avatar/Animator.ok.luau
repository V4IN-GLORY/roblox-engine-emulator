local animator = Instance.new("Animator")
animator:ApplyJointVelocities({})
assert(animator:GetTrackByAnimationId("rbxassetid://123456") == nil)
animator:RegisterEvaluationParallelCallback(function() end)
