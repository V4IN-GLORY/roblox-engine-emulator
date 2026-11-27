local part = Instance.new("Part")
part.Anchored = true
part.Parent = workspace
part.Touched:Connect(function(hit)
	hit.Parent.Humanoid:TakeDamages(10)
end)
