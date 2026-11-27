local dragger = Instance.new("Dragger")
local part = Instance.new("Part")
part.Parent = workspace
dragger:MouseDown(part, Vector3.zero, { part })
dragger:MouseMove(Ray.new(Vector3.zero, Vector3.zAxis))
dragger:MouseUp()
