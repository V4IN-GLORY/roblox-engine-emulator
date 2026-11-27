local hinge = Instance.new("HingeConstraint")
hinge.ActuatorType = Enum.ActuatorType.Motor
hinge.AngularVelocity = 5
assert(hinge:IsA("Constraint"))
