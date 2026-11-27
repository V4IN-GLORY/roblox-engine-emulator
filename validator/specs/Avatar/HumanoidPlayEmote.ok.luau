local model = Instance.new("Model")
model.Parent = workspace
local humanoid = Instance.new("Humanoid")
humanoid.Parent = model

local desc = Instance.new("HumanoidDescription")
desc:AddEmote("Dance", 99999)
humanoid:ApplyDescriptionAsync(desc)

assert(humanoid:PlayEmoteAsync("Dance") == true)
