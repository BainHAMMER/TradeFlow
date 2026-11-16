local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Цены: Auctionator API v1, TSM (резерв), Вендоры и Тренеры
-------------------------------------------------------------------------------
local AUCTION_CUT = 0.05
local priceRev = 1
local reagentPriceCache = {}
local recipeEconomyCache = {}

-- Таблица распыления Classic / WoW Forever: { maxIlvl, reqEnch, dustID, dustAvg, essID, essAvg, shardID }
local DE_UNCOMMON_BRACKETS = {
	{ 20,  1,   10940, 1.5, 10938, 1.5, nil   },
	{ 25,  25,  10940, 2.5, 10939, 1.5, 10978 },
	{ 30,  50,  11083, 1.5, 10998, 1.5, 11084 },
	{ 35,  75,  11083, 3.5, 11082, 1.5, 11138 },
	{ 40,  100, 11137, 1.5, 11134, 1.5, 11139 },
	{ 45,  125, 11137, 3.5, 11135, 1.5, 11177 },
	{ 50,  150, 11176, 1.5, 11174, 1.5, 11178 },
	{ 55,  175, 11176, 3.5, 11175, 1.5, 14343 },
	{ 60,  200, 16204, 1.5, 16202, 1.5, 14344 },
	{ 999, 225, 16204, 3.5, 16203, 1.5, 14344 },
}

local DE_RARE_BRACKETS = {
	{ 25,  25,  10978 },
	{ 30,  50,  11084 },
	{ 35,  75,  11138 },
	{ 40,  100, 11139 },
	{ 45,  125, 11177 },
	{ 50,  150, 11178 },
	{ 55,  175, 14343 },
	{ 999, 200, 14344 },
}

function ns:GetItemDisenchantInfo(itemID)
	if self.db and self.db.options and self.db.options.includeDisenchant == false then
		return nil
	end
	if not (itemID and itemID > 0 and C_Item and C_Item.GetItemInfo) then
		return nil
	end
	local _, _, quality, iLevel, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
	if not quality then
		if self.RequestItemData then
			self:RequestItemData(itemID)
		end
		return nil
	end
	if not (iLevel and iLevel > 0 and (classID == 2 or classID == 4)) then
		return nil
	end
	if quality < 2 or quality > 4 then
		return nil
	end

	local yields = {}
	local reqSkill = 1

	if quality == 2 then
		local row = DE_UNCOMMON_BRACKETS[#DE_UNCOMMON_BRACKETS]
		for _, r in ipairs(DE_UNCOMMON_BRACKETS) do
			if iLevel <= r[1] then
				row = r
				break
			end
		end
		reqSkill = row[2]
		local isWeapon = (classID == 2)
		local hasShard = row[7] ~= nil
		local dustChance = isWeapon and 0.20 or (hasShard and 0.75 or 0.80)
		local essChance  = isWeapon and (hasShard and 0.75 or 0.80) or (hasShard and 0.20 or 0.20)
		yields[#yields + 1] = { itemID = row[3], chance = dustChance, avg = row[4] }
		yields[#yields + 1] = { itemID = row[5], chance = essChance,  avg = row[6] }
		if hasShard then
			yields[#yields + 1] = { itemID = row[7], chance = 0.05, avg = 1 }
		end
	elseif quality == 3 then
		local row = DE_RARE_BRACKETS[#DE_RARE_BRACKETS]
		for _, r in ipairs(DE_RARE_BRACKETS) do
			if iLevel <= r[1] then
				row = r
				break
			end
		end
		reqSkill = row[2]
		if iLevel >= 56 then
			yields[#yields + 1] = { itemID = row[3], chance = 0.995, avg = 1 }
			yields[#yields + 1] = { itemID = 20725,  chance = 0.005, avg = 1 }
		else
			yields[#yields + 1] = { itemID = row[3], chance = 1.0, avg = 1 }
		end
	elseif quality == 4 then
		reqSkill = (iLevel >= 56) and 225 or 175
		if iLevel >= 56 then
			yields[#yields + 1] = { itemID = 20725, chance = 1.0, avg = 1.5 }
		else
			yields[#yields + 1] = { itemID = 11178, chance = 1.0, avg = 3 }
		end
	end

	local expectedGross = 0
	local pricedAny = false
	for _, y in ipairs(yields) do
		local p = self:GetAuctionPrice(y.itemID)
		if p and p > 0 then
			expectedGross = expectedGross + (p * y.chance * y.avg)
			pricedAny = true
		end
	end
	if not pricedAny then
		return nil, yields, reqSkill
	end
	local expectedNet = math.floor(expectedGross * (1 - AUCTION_CUT) + 0.5)
	return expectedNet, yields, reqSkill
end

function ns:InvalidatePrices()
	priceRev = priceRev + 1
	wipe(reagentPriceCache)
	wipe(recipeEconomyCache)
	if self.RefreshVisibleUI then
		self:RefreshVisibleUI()
	end
end

function ns:HasAuctionator()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	return api and api.GetAuctionPriceByItemID ~= nil
end

function ns:IsVendorItem(itemID)
	if not itemID then
		return false
	end
	if self.VendorPrices and self.VendorPrices[itemID] then
		return true
	end
	if self.db and self.db.vendorPrices and self.db.vendorPrices[itemID] then
		return true
	end
	return false
end

function ns:GetVendorPrice(itemID)
	if not itemID then
		return nil
	end
	if self.db and self.db.vendorPrices and self.db.vendorPrices[itemID] then
		return self.db.vendorPrices[itemID]
	end
	if self.VendorPrices and self.VendorPrices[itemID] then
		return self.VendorPrices[itemID]
	end
	return nil
end

function ns:GetItemSellPrice(itemID)
	if not itemID or itemID <= 0 then
		return 0
	end
	local sell = select(11, C_Item.GetItemInfo(itemID))
	if type(sell) == "number" and sell >= 0 then
		if self.db then
			self.db.sellPrices = self.db.sellPrices or {}
			self.db.sellPrices[itemID] = sell
		end
		return sell
	end
	if self.RequestItemData then
		self:RequestItemData(itemID)
	end
	return (self.db and self.db.sellPrices and self.db.sellPrices[itemID]) or 0
end

-- Возвращает: copper, source ("auctionator" | "tsm"), ageDays
function ns:GetAuctionPrice(itemID)
	if not itemID or itemID <= 0 then
		return nil, nil, nil
	end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.GetAuctionPriceByItemID then
		local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON_NAME, itemID)
		if ok and type(price) == "number" and price > 0 then
			local age = nil
			if api.GetAuctionAgeByItemID then
				local okAge, d = pcall(api.GetAuctionAgeByItemID, ADDON_NAME, itemID)
				if okAge and type(d) == "number" then
					age = d
				end
			end
			return price, "auctionator", age
		end
	end
	if TSM_API and TSM_API.GetCustomPriceValue then
		local ok, val = pcall(TSM_API.GetCustomPriceValue, "first(DBRecent, DBMinBuyout, DBMarket)", "i:" .. itemID)
		if ok and type(val) == "number" and val > 0 then
			return val, "tsm", nil
		end
	end
	return nil, nil, nil
end

-- Возвращает: fee (медь), reqSkill (требуемый навык у тренера), isTrainerRecipe
function ns:GetTrainerFee(recipeID)
	if not recipeID then
		return nil, nil, false
	end
	if self.db and self.db.trainerFees and self.db.trainerFees[recipeID] then
		local t = self.db.trainerFees[recipeID]
		return t[1], t[2], true
	end
	if self.TrainerFees and self.TrainerFees[recipeID] then
		local t = self.TrainerFees[recipeID]
		return t[1], t[2], true
	end
	return nil, nil, false
end

-- Определяет лучшую цену 1 шт. реагента и источник: "vendor", "craft", "ah", "unknown"
function ns:GetReagentBestPrice(itemID, visiting)
	if not itemID or itemID <= 0 then
		return nil, "unknown", nil
	end
	local isRoot = (visiting == nil)
	if isRoot and reagentPriceCache[itemID] then
		local c = reagentPriceCache[itemID]
		return c[1], c[2], c[3]
	end
	visiting = visiting or {}

	local vendorPrice = self:GetVendorPrice(itemID)
	if vendorPrice then
		return vendorPrice, "vendor", nil
	end

	local ahPrice = self:GetAuctionPrice(itemID)
	local bestPrice = ahPrice
	local bestSource = ahPrice and "ah" or "unknown"
	local bestRecipeID = nil

	if vendorPrice and (not bestPrice or vendorPrice < bestPrice) then
		bestPrice = vendorPrice
		bestSource = "vendor"
	end

	-- Проверяем, нельзя ли скрафтить этот промежуточный реагент дешевле своей профессией
	if not visiting[itemID] then
		local producers = self.ItemProducedBy and self.ItemProducedBy[itemID]
		if producers and #producers > 0 then
			visiting[itemID] = true
			for _, childRecipeID in ipairs(producers) do
				if self:IsRecipeLearned(childRecipeID) then
					local rec = self:GetRecipeRecord(childRecipeID)
					if rec and #rec.reagents > 0 and (rec.numMade or 1) > 0 then
						local totalSub = 0
						local okAll = true
						for _, r in ipairs(rec.reagents) do
							local subP = self:GetReagentBestPrice(r.itemID, visiting)
							if not subP then
								okAll = false
								break
							end
							totalSub = totalSub + subP * r.quantity
						end
						if okAll then
							local unitCraft = math.floor(totalSub / rec.numMade + 0.5)
							if not bestPrice or unitCraft < bestPrice then
								bestPrice = unitCraft
								bestSource = "craft"
								bestRecipeID = childRecipeID
							end
						end
					end
				end
			end
			visiting[itemID] = nil
		end
	end

	if isRoot then
		reagentPriceCache[itemID] = { bestPrice, bestSource, bestRecipeID }
	end
	return bestPrice, bestSource, bestRecipeID
end

-- Экономика рецепта: craftCost, outputValue, netProfit, reagentBreakdown
function ns:GetRecipeEconomy(recipeID)
	local cached = recipeEconomyCache[recipeID]
	if cached then
		return cached[1], cached[2], cached[3], cached[4], cached[5]
	end
	local rec = self:GetRecipeRecord(recipeID)
	if not rec or #rec.reagents == 0 then
		return nil, nil, nil, {}
	end

	local totalCost = 0
	local allPriced = true
	local breakdown = {}

	for _, r in ipairs(rec.reagents) do
		local unitPrice, source, subRecipeID = self:GetReagentBestPrice(r.itemID)
		local lineCost = unitPrice and (unitPrice * r.quantity) or nil
		if lineCost then
			totalCost = totalCost + lineCost
		else
			allPriced = false
		end
		breakdown[#breakdown + 1] = {
			itemID = r.itemID,
			quantity = r.quantity,
			unitPrice = unitPrice,
			lineCost = lineCost,
			source = source,
			subRecipeID = subRecipeID,
		}
	end

	local craftCost = allPriced and totalCost or nil
	local outputValue = nil
	local outputSource = nil

	if rec.outputItemID and rec.outputItemID > 0 then
		local vendorOnly = self.db and self.db.options and self.db.options.deductVendorInRoute == true
		local vendorSell = self:GetItemSellPrice(rec.outputItemID) * (rec.numMade or 1)
		if vendorOnly then
			if vendorSell > 0 then
				outputValue = vendorSell
				outputSource = "vendor"
			end
		else
			local ahUnit = self:GetAuctionPrice(rec.outputItemID)
			local ahNet = ahUnit and math.floor(ahUnit * (rec.numMade or 1) * (1 - AUCTION_CUT) + 0.5) or nil
			local deNet = self:GetItemDisenchantInfo(rec.outputItemID)
			if deNet then
				deNet = math.floor(deNet * (rec.numMade or 1) + 0.5)
			end
			if ahNet and ahNet > vendorSell then
				outputValue = ahNet
				outputSource = "ah"
			elseif vendorSell > 0 then
				outputValue = vendorSell
				outputSource = "vendor"
			end
			if deNet and deNet > (outputValue or 0) then
				outputValue = deNet
				outputSource = "disenchant"
			end
		end
	end

	local netProfit = (craftCost and outputValue) and (outputValue - craftCost) or nil
	recipeEconomyCache[recipeID] = { craftCost, outputValue, netProfit, breakdown, outputSource }
	return craftCost, outputValue, netProfit, breakdown, outputSource
end

-- Подписка на обновления базы Auctionator + запись живых цен у вендоров и тренеров
local priceFrame = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "MERCHANT_SHOW", "TRAINER_SHOW", "TRAINER_UPDATE" }) do
	pcall(priceFrame.RegisterEvent, priceFrame, ev)
end

priceFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		local api = Auctionator and Auctionator.API and Auctionator.API.v1
		if api and api.RegisterForDBUpdate then
			pcall(api.RegisterForDBUpdate, ADDON_NAME, function()
				ns:InvalidatePrices()
			end)
		end
	elseif event == "MERCHANT_SHOW" then
		if GetMerchantNumItems and GetMerchantItemInfo and GetMerchantItemLink then
			local n = GetMerchantNumItems() or 0
			for i = 1, n do
				local link = GetMerchantItemLink(i)
				local itemID = link and tonumber(link:match("item:(%d+)"))
				local _, _, price, quantity, numAvailable = GetMerchantItemInfo(i)
				if itemID and price and price > 0 and (quantity or 1) > 0 and (numAvailable == -1 or (numAvailable or 0) > 0) then
					local unit = math.floor(price / quantity + 0.5)
					if ns.VendorPrices and ns.VendorPrices[itemID] then
						ns.db.vendorPrices[itemID] = unit
						wipe(reagentPriceCache)
					end
				end
			end
		end
		if ns.OnMerchantShow then
			ns:OnMerchantShow()
		end
	elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
		if GetNumTrainerServices and GetTrainerServiceCost and GetTrainerServiceItemLink then
			local n = GetNumTrainerServices() or 0
			for i = 1, n do
				local link = GetTrainerServiceItemLink(i)
				local spellID = link and tonumber(link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
				local moneyCost = GetTrainerServiceCost(i)
				local _, reqSkill = GetTrainerServiceSkillReq and GetTrainerServiceSkillReq(i)
				if spellID and moneyCost and moneyCost > 0 then
					ns.db.trainerFees[spellID] = { moneyCost, reqSkill or 1 }
				end
			end
		end
	end
end)

