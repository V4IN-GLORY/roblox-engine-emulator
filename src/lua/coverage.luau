--!nocheck
-- `--fire-handlers` (lua/coverage.rs): the handlers a script hands a method are recorded for the coverage pass, which calls
-- each once; Stage gives the pass its player. Loaded after the validator packages, so a method one of them replaced is
-- wrapped too.

local R, Record = ...

local Players = game:GetService("Players")

local function BindActionArguments(ActionName)
	return ActionName, Enum.UserInputState.Begin, R.Create("InputObject")
end

-- The methods that take a handler: which argument it is, and what Roblox calls it with (Roblox's API reference)
local BINDERS = {
	{ Class = "DataModel", Name = "BindToClose", At = 1, Arguments = function() end },
	{ Class = "ContextActionService", Name = "BindAction", At = 2, Arguments = BindActionArguments },
	{ Class = "ContextActionService", Name = "BindActionAtPriority", At = 2, Arguments = BindActionArguments },
}

for _, Binder in BINDERS do
	local Owner = if Binder.Class == "DataModel" then game else game:GetService(Binder.Class)
	local Original = Owner[Binder.Name]
	local Label = `{Binder.Class}.{Binder.Name}`
	R.Method(Binder.Class, Binder.Name, function(Self, ...)
		local Handler = select(Binder.At, ...)
		if type(Handler) == "function" then
			Record(Label, Handler, Binder.Arguments(...))
		end
		return Original(Self, ...)
	end)
end

-- The player the pass hands handlers, in two steps a round apart, as a player joins after the scripts start and its character
-- loads after the PlayerAdded handlers ran. Join: a server's player joins (Players.PlayerAdded); a client's is its local player.
-- Spawn: it gets the default R6 character (Player.CharacterAdded) unless it has one, and returns the instances a handler gets for
-- a parameter of their class (the first that is one, for a parameter of an abstract class: BasePart.Touched's hit is the
-- character's leg) and ProcessReceipt's receipt.
local Player

local function Join(Name, UserId)
	Player = Players.LocalPlayer
	if Player then
		return
	end
	Player = Instance.new("Player")
	Player.Name = Name
	R.RawSet(Player, "UserId", UserId, false)
	Player.Parent = Players
end

local function Spawn()
	local Character = Player.Character
	if not Character then
		Character = R.R6Rig()
		Character.Name = Player.Name
		Character.Parent = workspace
		Player.Character = Character
	end
	local Limb = Character:FindFirstChild("Right Leg") or Character.PrimaryPart
	local Receipt = {
		PurchaseId = "coverage",
		PlayerId = Player.UserId,
		ProductId = 0,
		PlaceIdWherePurchased = game.PlaceId,
		CurrencySpent = 0,
		CurrencyType = Enum.CurrencyType.Robux,
		ProductPurchaseChannel = Enum.ProductPurchaseChannel.InExperience,
	}
	return { Limb, Character, Character:FindFirstChildOfClass("Humanoid"), Player }, Receipt
end

return Join, Spawn
