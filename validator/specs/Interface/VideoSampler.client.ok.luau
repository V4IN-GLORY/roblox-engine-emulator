local VideoService = game:GetService("VideoService")
local Sampler = VideoService:CreateVideoSamplerAsync(Content.fromUri("rbxassetid://12345"))
assert(typeof(Sampler) == "Instance" and Sampler:IsA("VideoSampler"))
