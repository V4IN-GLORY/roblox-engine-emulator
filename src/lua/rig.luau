--!nocheck
-- The default blocky R6 rig Roblox's documentation describes (a HumanoidRootPart, Torso, Head and four limbs at their standard
-- sizes, joined by the standard Motor6Ds, named after nothing: the caller names it): R.R6Rig, for a server's
-- CreateHumanoidModelFromDescription (server.luau) and the coverage pass's character (coverage.luau). Loaded only where one of
-- them is (lua/stubs.rs), so another run builds none of it.

local R = ...
local Create = R.Create
local SetParent = R.SetParent

local R6_PARTS = {
	{ "HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0) },
	{ "Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0) },
	{ "Head", Vector3.new(2, 1, 1), CFrame.new(0, 4.5, 0) },
	{ "Left Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0) },
	{ "Right Arm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0) },
	{ "Left Leg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0) },
	{ "Right Leg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0) },
}
local R6_JOINTS = {
	{ "RootJoint", "HumanoidRootPart", "Torso", CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0) },
	{ "Neck", "Torso", "Head", CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, -0) },
	{ "Left Shoulder", "Torso", "Left Arm", CFrame.new(-1, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0) },
	{ "Right Shoulder", "Torso", "Right Arm", CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0) },
	{ "Left Hip", "Torso", "Left Leg", CFrame.new(-1, -1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0) },
	{ "Right Hip", "Torso", "Right Leg", CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0) },
}

function R.R6Rig()
	local Model = Create("Model")
	local Parts = {}
	for _, Spec in R6_PARTS do
		local Part = Create("Part")
		Part.Name = Spec[1]
		Part.Size = Spec[2]
		Part.CFrame = Spec[3]
		if Spec[1] == "HumanoidRootPart" then
			Part.Transparency = 1
		end
		SetParent(Part, Model)
		Parts[Spec[1]] = Part
	end
	for _, Spec in R6_JOINTS do
		local Joint = Create("Motor6D")
		Joint.Name = Spec[1]
		Joint.Part0 = Parts[Spec[2]]
		Joint.Part1 = Parts[Spec[3]]
		Joint.C0 = Spec[4]
		Joint.C1 = Spec[5]
		SetParent(Joint, if Spec[1] == "RootJoint" then Parts.HumanoidRootPart else Parts.Torso)
	end
	local Humanoid = Create("Humanoid")
	Humanoid.RigType = Enum.HumanoidRigType.R6
	SetParent(Humanoid, Model)
	Model.PrimaryPart = Parts.HumanoidRootPart
	return Model
end

return true
