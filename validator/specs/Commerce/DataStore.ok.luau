local DataStoreService = game:GetService("DataStoreService")
local Options = Instance.new("DataStoreOptions")
local Store = DataStoreService:GetDataStore("PlayerData", "global", Options)

Store:SetAsync("player_1", { Coins = 100, Level = 3 })
local Data = Store:GetAsync("player_1")
assert(Data and Data.Coins == 100 and Data.Level == 3)

Store:UpdateAsync("player_1", function(Old)
	Old.Coins += 50
	return Old
end)
assert(Store:GetAsync("player_1").Coins == 150)

local Batch = Store:BatchGetAsync({ "player_1", "missing_key" })
assert(Batch.player_1.Coins == 150 and Batch.missing_key == nil)

local Listing = DataStoreService:ListDataStoresAsync("Player")
local Page = Listing:GetCurrentPage()
assert(#Page >= 1 and Page[1].DataStoreName == "PlayerData")
