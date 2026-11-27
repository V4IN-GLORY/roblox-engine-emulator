local actor = script:GetActor()
local count = 0
actor:BindToMessageParallel("Tick", function(amount)
	count += amount
	task.synchronize()
	actor:SetAttribute("Count", count)
end)
actor:SendMessage("Tick", 1)
