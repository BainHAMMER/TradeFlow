local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Цены: Auctionator API v1, TSM (резерв), Вендоры и Тренеры
-------------------------------------------------------------------------------
local AUCTION_CUT = 0.05
local priceRev = 1
local reagentPriceCache = {}
local recipeEconomyCache = {}

-- Таблица распыления Classic / WoW Forever, сверена с DisenchantBuddy 2.8.0 (ветка классики и Forever)
-- и Auctionator Source_Classic/Enchant/DisenchantingProbabilities.lua (на Forever Auctionator грузит
-- ветку Mainline, и этой таблицы там нет). Уровни предметов на Forever совпадают с ванильными.
-- Строка: { мин. уровень, макс. уровень, шанс %, штук, ID материала, шанс %, штук, ID материала, ... }
local DE_RARE = {
	{ 11, 25, 100, 1, 10978 },
	{ 26, 30, 100, 1, 11084 },
	{ 31, 35, 100, 1, 11138 },
	{ 36, 40, 100, 1, 11139 },
	{ 41, 45, 100, 1, 11177 },
	{ 46, 50, 100, 1, 11178 },
	{ 51, 55, 100, 1, 14343 },
	{ 56, 86, 99.5, 1, 14344, 0.5, 1, 20725 },
}
local DE_EPIC = {
	{ 40, 45, 100 / 3, 2, 11177, 100 / 3, 3, 11177, 100 / 3, 4, 11177 },
	{ 46, 50, 100 / 3, 2, 11178, 100 / 3, 3, 11178, 100 / 3, 4, 11178 },
	{ 51, 55, 100 / 3, 2, 14343, 100 / 3, 3, 14343, 100 / 3, 4, 14343 },
	{ 56, 60, 100, 1, 20725 },
	{ 61, 92, 33, 1, 20725, 67, 2, 20725 },
}
local DE_TABLE = {
	[4] = { -- броня
		[2] = {
			{ 5, 15, 40, 1, 10940, 40, 2, 10940, 10, 1, 10938, 10, 2, 10938 },
			{ 16, 20, 37.5, 2, 10940, 37.5, 3, 10940, 10, 1, 10939, 10, 2, 10939, 5, 1, 10978 },
			{ 21, 25, 25, 4, 10940, 25, 5, 10940, 25, 6, 10940, 7.5, 1, 10998, 7.5, 2, 10998, 10, 1, 10978 },
			{ 26, 30, 37.5, 1, 11083, 37.5, 2, 11083, 10, 1, 11082, 10, 2, 11082, 5, 1, 11084 },
			{ 31, 35, 18.75, 2, 11083, 18.75, 3, 11083, 18.75, 4, 11083, 18.75, 5, 11083, 10, 1, 11134, 10, 2, 11134, 5, 1, 11138 },
			{ 36, 40, 37.5, 1, 11137, 37.5, 2, 11137, 10, 1, 11135, 10, 2, 11135, 5, 1, 11139 },
			{ 41, 45, 18.75, 2, 11137, 18.75, 3, 11137, 18.75, 4, 11137, 18.75, 5, 11137, 10, 1, 11174, 10, 2, 11174, 5, 1, 11177 },
			{ 46, 50, 37.5, 1, 11176, 37.5, 2, 11176, 10, 1, 11175, 10, 2, 11175, 5, 1, 11178 },
			{ 51, 55, 15, 2, 11176, 15, 3, 11176, 15, 4, 11176, 15, 5, 11176, 15, 6, 11176, 10, 1, 16202, 10, 2, 16202, 5, 1, 14343 },
			{ 56, 60, 37.5, 1, 16204, 37.5, 2, 16204, 10, 1, 16203, 10, 2, 16203, 5, 1, 14344 },
			{ 61, 65, 18.75, 2, 16204, 18.75, 3, 16204, 18.75, 4, 16204, 18.75, 5, 16204, 10, 2, 16203, 10, 3, 16203, 5, 1, 14344 },
		},
		[3] = DE_RARE,
		[4] = DE_EPIC,
	},
	[2] = { -- оружие
		[2] = {
			{ 6, 15, 10, 1, 10940, 10, 2, 10940, 40, 1, 10938, 40, 2, 10938 },
			{ 16, 20, 10, 2, 10940, 10, 3, 10940, 37.5, 1, 10939, 37.5, 2, 10939, 5, 1, 10978 },
			{ 21, 25, 5, 4, 10940, 5, 5, 10940, 5, 6, 10940, 37.5, 1, 10939, 37.5, 2, 10939, 10, 1, 10978 },
			{ 26, 30, 10, 1, 11083, 10, 2, 11083, 37.5, 1, 10939, 37.5, 2, 10939, 5, 1, 11084 },
			{ 31, 35, 5, 2, 11083, 5, 3, 11083, 5, 4, 11083, 5, 5, 11083, 37.5, 1, 11134, 37.5, 2, 11134, 5, 1, 11138 },
			{ 36, 40, 10, 1, 11137, 10, 2, 11137, 37.5, 1, 11135, 37.5, 2, 11135, 5, 1, 11139 },
			{ 41, 45, 5, 2, 11137, 5, 3, 11137, 5, 4, 11137, 5, 5, 11137, 37.5, 1, 11174, 37.5, 2, 11174, 5, 1, 11177 },
			{ 46, 50, 10, 1, 11176, 10, 2, 11176, 37.5, 1, 11175, 37.5, 2, 11175, 5, 1, 11178 },
			{ 51, 55, 5, 2, 11176, 5, 3, 11176, 5, 4, 11176, 5, 5, 11176, 37.5, 1, 16202, 37.5, 2, 16202, 5, 1, 14343 },
			{ 56, 60, 10, 1, 16204, 10, 2, 16204, 37.5, 1, 16203, 37.5, 2, 16203, 5, 1, 14344 },
			{ 61, 65, 5, 2, 16204, 5, 3, 16204, 5, 4, 16204, 5, 5, 16204, 37.5, 2, 16203, 37.5, 3, 16203, 5, 1, 14344 },
		},
		[3] = DE_RARE,
		[4] = DE_EPIC,
	},
}

local function DisenchantRow(classID, quality, iLevel)
	local rows = DE_TABLE[classID] and DE_TABLE[classID][quality]
	if not rows then
		return nil
	end
	for _, r in ipairs(rows) do
		if iLevel >= r[1] and iLevel <= r[2] then
			return r
		end
	end
	return nil
end

-- Навык Наложения чар: до 20-го уровня предмета 1, дальше +25 за каждые 5 уровней; синим не меньше 25.
-- Для фиолетовых оставлены прежние значения TradeFlow (175 / 225).
local function DisenchantSkill(quality, iLevel)
	if quality == 4 then
		return (iLevel >= 56) and 225 or 175
	end
	local skill = (iLevel <= 20) and 1 or 25 * math.ceil((iLevel - 20) / 5)
	if quality == 3 and skill < 25 then
		skill = 25
	end
	return math.min(skill, 300)
end

-- Строка таблицы -> выход по материалам: { itemID, chance (0..1), avg (штук, когда выпал), min, max }.
-- Строки неизменны, поэтому разбор кэшируется по самой строке.
local deYieldCache = {}
local function DisenchantYields(row)
	local cached = deYieldCache[row]
	if cached then
		return cached
	end
	local yields, byID = {}, {}
	for x = 3, #row, 3 do
		local share, count, id = row[x] / 100, row[x + 1], row[x + 2]
		local y = byID[id]
		if not y then
			y = { itemID = id, chance = 0, avg = 0, min = count, max = count }
			byID[id] = y
			yields[#yields + 1] = y
		end
		y.chance = y.chance + share
		y.avg = y.avg + share * count
		if count < y.min then y.min = count end
		if count > y.max then y.max = count end
	end
	for _, y in ipairs(yields) do
		y.avg = y.avg / y.chance
	end
	deYieldCache[row] = yields
	return yields
end

-- «x1-2» или «x3» для строки выхода распыления
function ns.FormatDisenchantCount(y)
	if y.min and y.max and y.min ~= y.max then
		return string.format("x%d-%d", y.min, y.max)
	end
	return string.format("x%d", y.min or math.floor((y.avg or 1) + 0.5))
end

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
	local row = DisenchantRow(classID, quality, iLevel)
	if not row then
		return nil
	end
	-- Навык только для показа: Наложение чар у персонажа не требуем, распылять может и другой (bf97f2e)
	local reqSkill = DisenchantSkill(quality, iLevel)
	local yields = DisenchantYields(row)

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

