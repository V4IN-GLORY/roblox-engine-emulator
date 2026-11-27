local ContextActionService = game:GetService("ContextActionService")

local function OnAction()
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction("Jump", OnAction, false, Enum.KeyCode.Space)
ContextActionService:BindAction("Move", OnAction, false, Enum.PlayerActions.CharacterForward, "w")
ContextActionService:BindActionAtPriority("Attack", OnAction, true, 2500, Enum.UserInputType.MouseButton1, Enum.KeyCode.F)
ContextActionService:SetTitle("Attack", "Hit")
ContextActionService:SetDescription("Attack", "Swing weapon")
ContextActionService:SetImage("Attack", "rbxassetid://1")
ContextActionService:SetPosition("Attack", UDim2.new(0.5, 0, 0.5, 0))

local Info = ContextActionService:GetBoundActionInfo("Attack")
assert(Info.title == "Hit" and Info.description == "Swing weapon")
assert(Info.createTouchButton == true and Info.priorityLevel == 2500)
assert(#Info.inputTypes == 2)
assert(ContextActionService:GetBoundActionInfo("Jump").priorityLevel == 2000)
assert(ContextActionService:GetButton("Attack") == nil) -- a desktop has no touch buttons

ContextActionService:BindActivate(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR2)
ContextActionService:UnbindActivate(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR2)
ContextActionService:UnbindAction("Jump")
assert(next(ContextActionService:GetBoundActionInfo("Jump")) == nil)
ContextActionService:UnbindAllActions()
assert(next(ContextActionService:GetAllBoundActionInfo()) == nil)
