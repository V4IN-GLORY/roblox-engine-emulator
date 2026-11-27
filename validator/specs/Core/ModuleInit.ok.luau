local Shop = {}
Shop.Prices = { Sword = 100 }

function Shop:Init()
	for item, price in self.Prices do
		print(item .. ": " .. price)
	end
end

function Shop.GetPrice(item)
	return Shop.Prices[item]
end

return Shop
