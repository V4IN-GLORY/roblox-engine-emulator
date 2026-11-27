local Players = game:GetService("Players")
local player = Players.LocalPlayer
assert(player:DistanceFromCharacter(Vector3.zero) == 0)
player:Move(Vector3.new(1, 0, 0))
player:Kick("goodbye")
