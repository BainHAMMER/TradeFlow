local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Цены: Auctionator API v1, TSM (резерв), Вендоры и Тренеры
-------------------------------------------------------------------------------
local AUCTION_CUT = 0.05
ns.AUCTION_CUT = AUCTION_CUT
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

ns.DisenchantMatIDs = {}
for _, byQual in pairs(DE_TABLE) do
	for _, rows in pairs(byQual) do
		for _, r in ipairs(rows) do
			for x = 5, #r, 3 do
				if r[x] and r[x] > 0 then
					ns.DisenchantMatIDs[r[x]] = true
				end
			end
		end
	end
end

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

-- Предметы и слоты, которые в игре распылить нельзя (крафтовые жезлы Наложения чар, рубашки, накидки, удочки и т.п.)
local NON_DISENCHANTABLE_ITEMS = {
	[11287] = true,  -- Lesser Magic Wand
	[11288] = true,  -- Greater Magic Wand
	[11289] = true,  -- Lesser Mystic Wand
	[11290] = true,  -- Greater Mystic Wand
	[217287] = true, -- Greater Mystic Wand (WoW Forever)
}

local NON_DISENCHANTABLE_EQUIP = {
	INVTYPE_NON_EQUIP = true,
	INVTYPE_BODY = true,
	INVTYPE_TABARD = true,
	INVTYPE_BAG = true,
	INVTYPE_QUIVER = true,
	INVTYPE_AMMO = true,
	INVTYPE_PROFESSION_TOOL = true,
	INVTYPE_PROFESSION_GEAR = true,
}

local function IsDisenchantableItem(itemID, quality, iLevel, equipLoc, classID, subclassID, bindType)
	if NON_DISENCHANTABLE_ITEMS[itemID] then
		return false
	end
	if not (quality and quality >= 2 and quality <= 4 and iLevel and iLevel > 0) then
		return false
	end
	if not (classID == 2 or classID == 4) then
		return false
	end
	if equipLoc and NON_DISENCHANTABLE_EQUIP[equipLoc] then
		return false
	end
	if classID == 2 and subclassID == 20 then -- Удочки
		return false
	end
	if classID == 4 and subclassID == 5 then -- Декоративные
		return false
	end
	if bindType == 4 then -- Предмет задания
		return false
	end
	return true
end

local function ConvertDisenchantBuddyResults(results)
	if type(results) ~= "table" or #results == 0 then
		return nil
	end
	local totalProb = 0
	for _, entry in ipairs(results) do
		totalProb = totalProb + (tonumber(entry and entry.probability) or 0)
	end
	if totalProb <= 0 then
		return nil
	end
	local scale = (totalProb > 1.5) and 100 or 1
	local yields, byID = {}, {}
	for _, entry in ipairs(results) do
		local id = entry and tonumber(entry.itemId)
		local share = (tonumber(entry and entry.probability) or 0) / scale
		local minQ = tonumber(entry and entry.minQuantity) or 1
		local maxQ = tonumber(entry and entry.maxQuantity) or minQ
		if maxQ < minQ then
			maxQ = minQ
		end
		if id and id > 0 and share > 0 then
			local avgQ = (minQ + maxQ) / 2
			local y = byID[id]
			if not y then
				y = { itemID = id, chance = 0, avg = 0, min = minQ, max = maxQ }
				byID[id] = y
				yields[#yields + 1] = y
			end
			y.chance = y.chance + share
			y.avg = y.avg + share * avgQ
			if minQ < y.min then y.min = minQ end
			if maxQ > y.max then y.max = maxQ end
		end
	end
	if #yields == 0 then
		return nil
	end
	for _, y in ipairs(yields) do
		y.avg = y.avg / y.chance
	end
	table.sort(yields, function(a, b)
		if math.abs((a.chance or 0) - (b.chance or 0)) > 1e-6 then
			return (a.chance or 0) > (b.chance or 0)
		end
		return (a.itemID or 0) < (b.itemID or 0)
	end)
	return yields
end

-- «x1-2» или «x3» для строки выхода распыления
function ns.FormatDisenchantCount(y)
	if y.min and y.max and y.min ~= y.max then
		return string.format("x%d-%d", y.min, y.max)
	end
	return string.format("x%d", y.min or math.floor((y.avg or 1) + 0.5))
end

local deBuddyCache = {}

function ns:GetItemDisenchantInfo(itemID)
	if self.db and self.db.options and self.db.options.includeDisenchant == false then
		return nil
	end
	if not (itemID and itemID > 0 and C_Item and C_Item.GetItemInfo) then
		return nil
	end
	local _, itemLink, quality, iLevel, _, _, _, _, equipLoc, _, _, classID, subclassID, bindType = C_Item.GetItemInfo(itemID)
	if not quality then
		if self.RequestItemData then
			self:RequestItemData(itemID)
		end
		return nil
	end
	if not IsDisenchantableItem(itemID, quality, iLevel, equipLoc, classID, subclassID, bindType) then
		return nil
	end
	-- Навык только для показа: Наложение чар у персонажа не требуем, распылять может и другой (bf97f2e)
	local reqSkill = DisenchantSkill(quality, iLevel)
	local yields = nil
	local deApi = _G.DisenchantBuddy and _G.DisenchantBuddy.API and _G.DisenchantBuddy.API.v1
	if deApi and type(deApi.GetDisenchantResults) == "function" then
		local cachedDe = deBuddyCache[itemID]
		if cachedDe ~= nil then
			if cachedDe == false then
				return nil
			end
			yields = cachedDe
		else
			local ok, dbResults = pcall(deApi.GetDisenchantResults, ADDON_NAME, itemLink or itemID)
			if ok then
				yields = ConvertDisenchantBuddyResults(dbResults)
				deBuddyCache[itemID] = yields or false
				if not yields then
					return nil
				end
			end
		end
	end
	if not yields then
		local row = DisenchantRow(classID, quality, iLevel)
		if not row then
			return nil
		end
		yields = DisenchantYields(row)
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

function ns:GetPriceRevision()
	return priceRev
end

function ns:InvalidatePrices()
	priceRev = priceRev + 1
	wipe(reagentPriceCache)
	wipe(recipeEconomyCache)
	if self.NotifyModules then
		self:NotifyModules("OnPricesInvalidated")
	end
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

-- Выручка, которую вычитаем из цены за +1 навык и в калькуляторе прокачки (alts — 6-е значение
-- GetRecipeEconomy): продажа торговцу, если отмечена «Продажа торговцу», или распыление, если оно
-- включено в настройках, — что больше. Перепродажа на аукционе в прокачку не входит, как и раньше.
function ns.GetSkillUpReturn(alts, deductVendor)
	local vendor = (deductVendor and alts and alts.vendor) or 0
	local de = (alts and alts.disenchant) or 0
	if de > vendor then
		return de, "disenchant"
	end
	return vendor, (vendor > 0) and "vendor" or nil
end

local OUTPUT_SOURCES = { "vendor", "ah", "disenchant" }
ns.OUTPUT_SOURCES = OUTPUT_SOURCES

-- Экономика рецепта: craftCost, outputValue, netProfit, reagentBreakdown, outputSource,
-- alts — выручка по каждому источнику { vendor, ah, disenchant } (только те, что есть)
function ns:GetRecipeEconomy(recipeID)
	local cached = recipeEconomyCache[recipeID]
	if cached then
		return cached[1], cached[2], cached[3], cached[4], cached[5], cached[6]
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
	local alts = {}

	if rec.outputItemID and rec.outputItemID > 0 then
		local numMade = rec.numMade or 1
		-- «Продажа торговцу»: вещь не перепродаём на аукционе, остаются торговец и распыление
		local vendorOnly = self.db and self.db.options and self.db.options.deductVendorInRoute == true
		local vendorSell = self:GetItemSellPrice(rec.outputItemID) * numMade
		if vendorSell > 0 then
			alts.vendor = vendorSell
		end
		if not vendorOnly then
			local ahUnit = self:GetAuctionPrice(rec.outputItemID)
			if ahUnit and ahUnit > 0 then
				alts.ah = math.floor(ahUnit * numMade * (1 - AUCTION_CUT) + 0.5)
			end
		end
		local deNet = self:GetItemDisenchantInfo(rec.outputItemID)
		if deNet then
			alts.disenchant = math.floor(deNet * numMade + 0.5)
		end
		-- лучшее из доступного; при равенстве — торговец, потом аукцион, потом распыление
		for _, src in ipairs(OUTPUT_SOURCES) do
			local v = alts[src]
			if v and v > (outputValue or 0) then
				outputValue = v
				outputSource = src
			end
		end
	end

	local netProfit = (craftCost and outputValue) and (outputValue - craftCost) or nil
	recipeEconomyCache[recipeID] = { craftCost, outputValue, netProfit, breakdown, outputSource, alts }
	return craftCost, outputValue, netProfit, breakdown, outputSource, alts
end

local MAX_AH_TIERS = 25
local AH_STOCK_MAX_AGE = 7 * 86400
local trackedAhItems = nil

local function EnsureTrackedAhItems()
	if trackedAhItems then
		return trackedAhItems
	end
	trackedAhItems = {}
	for _, rec in pairs(ns.RecipeData or {}) do
		if rec.reagents then
			for _, r in ipairs(rec.reagents) do
				if r.itemID then
					trackedAhItems[r.itemID] = true
				end
			end
		end
		if type(rec.output) == "table" and rec.output.itemID then
			trackedAhItems[rec.output.itemID] = true
		end
	end
	for _, sc in pairs(ns.RecipeScrolls or {}) do
		if sc and sc[1] then
			trackedAhItems[sc[1]] = true
		end
	end
	for _, byQual in pairs(DE_TABLE) do
		for _, rows in pairs(byQual) do
			for _, r in ipairs(rows) do
				for x = 5, #r, 3 do
					if r[x] then
						trackedAhItems[r[x]] = true
					end
				end
			end
		end
	end
	return trackedAhItems
end

local function IsTrackedAhItem(itemID)
	if not (itemID and itemID > 0) then
		return false
	end
	local map = EnsureTrackedAhItems()
	if map[itemID] then
		return true
	end
	local snipes = ns.GetSnipeTargets and ns:GetSnipeTargets()
	return snipes ~= nil and snipes[itemID] ~= nil
end

local function PruneAuctionStock()
	local stock = ns.realmDB and ns.realmDB.ahStock
	if not stock then
		return
	end
	local now = time and time() or 0
	for itemID, entry in pairs(stock) do
		local stale = now > 0 and entry and entry.ts and (now - entry.ts) > AH_STOCK_MAX_AGE
		if stale or not IsTrackedAhItem(itemID) then
			stock[itemID] = nil
		end
	end
end

local pendingPriceInvalidation = false
local function SchedulePriceInvalidation()
	if pendingPriceInvalidation then
		return
	end
	if C_Timer and C_Timer.After then
		pendingPriceInvalidation = true
		C_Timer.After(0.15, function()
			pendingPriceInvalidation = false
			ns:InvalidatePrices()
		end)
	else
		ns:InvalidatePrices()
	end
end

local function BuildAuctionTiers(qtyByPrice)
	local prices = {}
	local total = 0
	for p, q in pairs(qtyByPrice) do
		if p > 0 and q > 0 then
			prices[#prices + 1] = p
			total = total + q
		end
	end
	if #prices == 0 then
		return nil, nil, 0, 0
	end
	table.sort(prices)
	local tiers = {}
	local count = math.min(#prices, MAX_AH_TIERS)
	for i = 1, count do
		local p = prices[i]
		tiers[i] = { p, qtyByPrice[p] }
	end
	return tiers, tiers[1][1], tiers[1][2], total
end

local function RecordAuctionStock(itemID, minPrice, qtyAtMin, totalQty, tiers, isAggregate)
	if not (ns.realmDB and itemID and itemID > 0 and minPrice and minPrice > 0) then
		return
	end
	if not IsTrackedAhItem(itemID) then
		return
	end
	ns.realmDB.ahStock = ns.realmDB.ahStock or {}
	local slot = ns.realmDB.ahStock[itemID]
	if not slot then
		slot = {}
		ns.realmDB.ahStock[itemID] = slot
	end
	slot.price = minPrice
	slot.qty = qtyAtMin or totalQty or 0
	slot.total = totalQty or qtyAtMin or 0
	slot.tiers = tiers
	slot.isAggregate = isAggregate and true or false
	slot.ts = time and time() or 0
	local snipes = ns.GetSnipeTargets and ns:GetSnipeTargets()
	if snipes and snipes[itemID] and ns.NotifyModules then
		ns:NotifyModules("OnAuctionStockUpdated", itemID)
	end
end

function ns:GetAuctionSeenQty(itemID, expectedPrice)
	local stock = self.realmDB and self.realmDB.ahStock and self.realmDB.ahStock[itemID]
	if not stock then
		return nil, nil, false
	end
	if expectedPrice and stock.price and math.abs(stock.price - expectedPrice) <= math.max(1, expectedPrice * 0.02) then
		return stock.qty, stock.total, true
	end
	return stock.total, stock.total, false
end

-- Расчёт стоимости покупки needQty единиц с аукциона с учётом уже выкупленных в маршруте boughtOffset единиц и ценовых уровней
function ns:EvalAuctionBuyCost(itemID, boughtOffset, needQty, fallbackPrice)
	local n = needQty or 0
	if n <= 0 then
		return 0, 0
	end
	local fb = fallbackPrice or 0
	local stock = self.realmDB and self.realmDB.ahStock and self.realmDB.ahStock[itemID]
	if not stock then
		return n * fb, 0
	end
	local tiers = (stock.tiers and #stock.tiers > 0 and stock.tiers)
		or (stock.price and { { stock.price, stock.total or stock.qty or 0 } })
	if not tiers or #tiers == 0 then
		return n * fb, 0
	end
	local skip = boughtOffset or 0
	local rem = n
	local cost = 0
	local lastPrice = fb
	for _, tier in ipairs(tiers) do
		local p, q = tier[1] or fb, tier[2] or 0
		lastPrice = p
		if q > 0 then
			if skip >= q then
				skip = skip - q
			else
				local avail = q - skip
				skip = 0
				local take = math.min(rem, avail)
				cost = cost + take * p
				rem = rem - take
				if rem <= 0 then
					break
				end
			end
		end
	end
	if rem > 0 then
		cost = cost + rem * math.max(fb, lastPrice)
	end
	return cost, rem
end

-- Подписка на обновления базы Auctionator + запись живых цен у вендоров, тренеров и остатков AH
local priceFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"PLAYER_LOGIN",
	"MERCHANT_SHOW",
	"TRAINER_SHOW",
	"TRAINER_UPDATE",
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
}) do
	pcall(priceFrame.RegisterEvent, priceFrame, ev)
end

priceFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		PruneAuctionStock()
		local api = Auctionator and Auctionator.API and Auctionator.API.v1
		if api and api.RegisterForDBUpdate then
			pcall(api.RegisterForDBUpdate, ADDON_NAME, function()
				SchedulePriceInvalidation()
			end)
		end
		if Auctionator and Auctionator.Database and Auctionator.Database.ProcessScan and hooksecurefunc and not ns.atrScanHooked then
			ns.atrScanHooked = true
			pcall(hooksecurefunc, Auctionator.Database, "ProcessScan", function(_, priceInfo)
				if type(priceInfo) ~= "table" then
					return
				end
				local now = time and time() or 0
				for dbKey, list in pairs(priceInfo) do
					local itemID = tonumber(dbKey) or tonumber(tostring(dbKey):match("^(%d+)$"))
					if itemID and IsTrackedAhItem(itemID) and type(list) == "table" and #list > 0 then
						local qtyByPrice = {}
						for _, e in ipairs(list) do
							local p = e and tonumber(e.price)
							local q = e and tonumber(e.available) or 0
							if p and p > 0 and q > 0 then
								qtyByPrice[p] = (qtyByPrice[p] or 0) + q
							end
						end
						local tiers, minP, qtyMin, total = BuildAuctionTiers(qtyByPrice)
						if minP and total > 0 then
							-- Сводный скан Auctionator (ProcessScan) часто отдаёт 1 запись со всем остатком по minPrice
							local isAgg = (#tiers <= 1)
							local prev = ns.realmDB and ns.realmDB.ahStock and ns.realmDB.ahStock[itemID]
							local keepDetailed = isAgg and prev and not prev.isAggregate and prev.tiers and #prev.tiers >= 1 and (now - (prev.ts or 0)) <= 120
							if not keepDetailed then
								RecordAuctionStock(itemID, minP, qtyMin, total, tiers, isAgg)
							end
						end
					end
				end
			end)
		end
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" and arg1 and C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults then
		local itemID = tonumber(arg1)
		if not (itemID and IsTrackedAhItem(itemID)) then
			return
		end
		local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
		if n and n > 0 and C_AuctionHouse.GetCommoditySearchResultInfo then
			local qtyByPrice = {}
			for i = 1, math.min(n, 200) do
				local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
				if info and info.unitPrice and info.unitPrice > 0 and (info.quantity or 0) > 0 then
					qtyByPrice[info.unitPrice] = (qtyByPrice[info.unitPrice] or 0) + info.quantity
				end
			end
			local tiers, minP, qtyMin, total = BuildAuctionTiers(qtyByPrice)
			if minP and total > 0 then
				RecordAuctionStock(itemID, minP, qtyMin, total, tiers, false)
				SchedulePriceInvalidation()
			end
		elseif itemID and ns.realmDB and ns.realmDB.ahStock and ns.realmDB.ahStock[itemID] then
			ns.realmDB.ahStock[itemID] = nil
			local snipes = ns.GetSnipeTargets and ns:GetSnipeTargets()
			if snipes and snipes[itemID] and ns.NotifyModules then
				ns:NotifyModules("OnAuctionStockUpdated", itemID)
			end
		end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" and C_AuctionHouse and C_AuctionHouse.GetBrowseResults then
		local results = C_AuctionHouse.GetBrowseResults()
		if type(results) == "table" then
			local now = time and time() or 0
			for _, r in ipairs(results) do
				local itemID = r and r.itemKey and r.itemKey.itemID
				if itemID and IsTrackedAhItem(itemID) and (r.minPrice or 0) > 0 and (r.totalQuantity or 0) > 0 then
					local prev = ns.realmDB and ns.realmDB.ahStock and ns.realmDB.ahStock[itemID]
					local keepTiers = prev and not prev.isAggregate and prev.tiers and #prev.tiers >= 1 and (now - (prev.ts or 0)) <= 60
					if not keepTiers and (not prev or (now - (prev.ts or 0)) > 5) then
						RecordAuctionStock(itemID, r.minPrice, r.totalQuantity, r.totalQuantity, nil, true)
					end
				end
			end
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

