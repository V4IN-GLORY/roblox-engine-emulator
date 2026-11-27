-- a server's SetCore does nothing, whatever the name
local StarterGui = game:GetService("StarterGui")
StarterGui:SetCore("NotARegisteredCoreName", false)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
