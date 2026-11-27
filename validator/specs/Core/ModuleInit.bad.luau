local Shop = {}
Shop.Prices = { Sword = 100 }

function Shop.Init()
	for item, price in Shop.Prices do
		print(item .. ": " .. price.Amount)
	end
end

return Shop
