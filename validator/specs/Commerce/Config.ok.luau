local ConfigService = game:GetService("ConfigService")
ConfigService:SetTestingValue("DoubleXP", true)

local Snapshot = ConfigService:GetConfigAsync()
assert(Snapshot:GetValue("DoubleXP") == true)

local ChangedTo = nil
Snapshot:GetValueChangedSignal("DoubleXP"):Connect(function(NewValue)
	ChangedTo = NewValue
end)

ConfigService:SetTestingValue("DoubleXP", false)
Snapshot:Refresh()
task.wait(0.05)
assert(Snapshot:GetValue("DoubleXP") == false and ChangedTo == false)

ConfigService:ClearTestingValue("DoubleXP")
