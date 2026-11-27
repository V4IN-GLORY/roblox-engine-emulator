local TweenService = game:GetService("TweenService")

local n, nv = TweenService:SmoothDamp(0, 10, 0, 0.5)
assert(type(n) == "number" and type(nv) == "number", "expected number SmoothDamp")

local v2, v2v = TweenService:SmoothDamp(Vector2.zero, Vector2.new(5, 5), Vector2.zero, 0.5)
assert(typeof(v2) == "Vector2" and typeof(v2v) == "Vector2", "expected Vector2 SmoothDamp")

local v3, v3v = TweenService:SmoothDamp(Vector3.zero, Vector3.new(1, 2, 3), Vector3.zero, 0.5)
assert(typeof(v3) == "Vector3" and typeof(v3v) == "Vector3", "expected Vector3 SmoothDamp")

local cf, cfv = TweenService:SmoothDamp(CFrame.new(), CFrame.new(1, 2, 3), Vector3.zero, 0.5)
assert(typeof(cf) == "CFrame" and typeof(cfv) == "Vector3", "expected CFrame SmoothDamp")
