local AvatarCreationService = game:GetService("AvatarCreationService")
local Players = game:GetService("Players")
local rig = Instance.new("Model")
AvatarCreationService:AutoSetupAvatarAsync(Players.LocalPlayer, { Body = rig })
