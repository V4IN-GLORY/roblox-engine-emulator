local part = Instance.new("Part")
part.Transparency = 0.5
assert(part:IsPropertyModified("Transparency") == true, "expected Transparency modified")
assert(part:GetStyled("Transparency") == 0.5, "expected styled Transparency")

local changed = false
local conn = part:GetStyledPropertyChangedSignal("Transparency"):Connect(function()
	changed = true
end)
part:ResetPropertyToDefault("Transparency")
task.wait()
assert(part.Transparency == 0, "expected default Transparency")
assert(changed == true, "expected styled changed signal")
conn:Disconnect()
