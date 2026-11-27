local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Screen = Instance.new("ScreenGui")
local Button = Instance.new("TextButton")
Button.Parent = Screen
local Box = Instance.new("TextBox")
Box.SelectionOrder = 1
Box.Parent = Screen
Screen.Parent = Players.LocalPlayer.PlayerGui

GuiService:Select(Screen)
assert(GuiService.SelectedObject == Button)
GuiService:AddSelectionParent("Menu", Screen)
GuiService:RemoveSelectionGroup("Menu")
GuiService:InspectPlayerFromHumanoidDescription(Instance.new("HumanoidDescription"), "Player")
GuiService:SetEmotesMenuOpen(true)
assert(GuiService:GetEmotesMenuOpen() == true)
assert(GuiService:GetInspectMenuEnabled() == false)

Box:CaptureFocus()
assert(Box:IsFocused() == true)
assert(UserInputService:GetFocusedTextBox() == Box)
Box:ReleaseFocus()
assert(Box:IsFocused() == false)
assert(UserInputService:GetFocusedTextBox() == nil)
