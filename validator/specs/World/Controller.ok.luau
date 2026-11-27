local controller = Instance.new("HumanoidController")
controller:BindButton(Enum.Button.Jump, "Jump")
assert(controller:GetButton(Enum.Button.Jump) == false)
controller:UnbindButton(Enum.Button.Jump)
