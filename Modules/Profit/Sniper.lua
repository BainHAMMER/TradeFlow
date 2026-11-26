local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Снайпер материалов: целевые пороги цен, пассивный перехват сканов AH и плашка
-------------------------------------------------------------------------------
local MAX_SNIPE_STOCK_AGE = 3600 -- не сигналим по вчерашнему кэшу (> 1 часа)
local DEFAULT_SNIPE_MAX_SPEND = 100000 -- 10g по умолчанию за 1 клик выкупа
local DEFAULT_SNIPE_MAX_QTY = 200
local DEFAULT_SNIPE_MIN_RESERVE = 0
local DEFAULT_SNIPE_AUTOSCAN_INTERVAL = 5
local MIN_SNIPE_AUTOSCAN_INTERVAL = 1
local MAX_SNIPE_AUTOSCAN_INTERVAL = 15
local DEFAULT_SNIPE_DISCOUNT_PCT = 20
local MIN_SNIPE_DISCOUNT_PCT = 5
local MAX_SNIPE_DISCOUNT_PCT = 80
local EMA_SAMPLE_INTERVAL = 15
local EMA_ALPHA = 0.25
local EMA_LOW_STREAK_THRESHOLD = 4
local EMA_MAX_UP_MULT = 1.5
local EXTERNAL_AH_PAUSE_SEC = 6
local snipeBar = nil
local sniperSettingsFrame = nil
local sniperSettingsAnchorKind = nil
local sniperSettingsSpecialRegistered = false
local lastSoundAt = -10
local lastAutoScanAt = -30
local lastExternalAhActivityAt = -30
local autoScanTimerToken = 0
local lastChatHitAt = {}
local lastSnipeListSig = nil
local snipeSyncToken = 0
local pendingUiRefresh = false
local hookedAuctionFrames = {}
local pendingBuy = nil
local pendingSnipeBid = nil
local buyTokenCounter = 0
local SNIPE_BATCH_CHUNK_SIZE = 100
local SNIPE_BATCH_TIMEOUT = 6.0
local activeSnipeBatch = nil
local snipeBatchToken = 0
local pendingSnipeDetailItemID = nil
local pendingSnipeDetailQueued = nil
local detailQueryToken = 0
local lastDetailQueryAt = {}

function ns:GetActiveSnipeBatchSet()
	return activeSnipeBatch and activeSnipeBatch.chunkSet or nil
end

function ns:GetSnipeAutoScanInterval()
	local opts = self.db and self.db.options
	local v = opts and tonumber(opts.snipeAutoScanInterval)
	if not v then
		return DEFAULT_SNIPE_AUTOSCAN_INTERVAL
	end
	v = math.floor(v + 0.5)
	if v < MIN_SNIPE_AUTOSCAN_INTERVAL then
		return MIN_SNIPE_AUTOSCAN_INTERVAL
	elseif v > MAX_SNIPE_AUTOSCAN_INTERVAL then
		return MAX_SNIPE_AUTOSCAN_INTERVAL
	end
	return v
end

function ns:GetSnipeDiscountPct()
	local opts = self.db and self.db.options
	local v = opts and tonumber(opts.snipeDiscountPct)
	if not v then
		return DEFAULT_SNIPE_DISCOUNT_PCT
	end
	v = math.floor(v + 0.5)
	if v < MIN_SNIPE_DISCOUNT_PCT then
		return MIN_SNIPE_DISCOUNT_PCT
	elseif v > MAX_SNIPE_DISCOUNT_PCT then
		return MAX_SNIPE_DISCOUNT_PCT
	end
	return v
end

function ns:GetSnipeDiscountRatio()
	return (100 - self:GetSnipeDiscountPct()) / 100
end

local function ParseSnipeDiscountPct(text)
	if text == nil then
		return DEFAULT_SNIPE_DISCOUNT_PCT
	end
	local s = tostring(text):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%%$", "")
	if s == "" then
		return DEFAULT_SNIPE_DISCOUNT_PCT
	end
	if not s:match("^%d+$") then
		return nil
	end
	local n = tonumber(s)
	if not n or n < MIN_SNIPE_DISCOUNT_PCT or n > MAX_SNIPE_DISCOUNT_PCT then
		return nil
	end
	return n
end

function ns:IsSnipeTargetEnabled(target)
	return target ~= nil and target.enabled ~= false
end

function ns:GetSnipeLiveMarketPrice(itemID)
	if not itemID or itemID <= 0 then
		return nil, nil
	end
	local stock = self.realmDB and self.realmDB.ahStock and self.realmDB.ahStock[itemID]
	local now = time and time() or 0
	if stock and stock.price and stock.price > 0 then
		if not stock.ts or stock.ts <= 0 or now <= 0 or (now - stock.ts) <= MAX_SNIPE_STOCK_AGE then
			return stock.price, "live"
		end
	end
	local p, src = self:GetAuctionPrice(itemID)
	return p, src
end

local function UpdateSnipeMarketEMA(target, livePrice, now)
	if not (target and livePrice and livePrice > 0) then
		return false
	end
	local opts = ns.db and ns.db.options
	if opts and opts.snipeAutoReprice == false then
		return false
	end
	if target.manual == true then
		return false
	end
	local lastAt = target.lastEmaAt or 0
	if now > 0 and lastAt > 0 and (now - lastAt) < EMA_SAMPLE_INTERVAL then
		return false
	end
	local ratio = ns:GetSnipeDiscountRatio()
	if not target.emaPrice or target.emaPrice <= 0 then
		target.emaPrice = livePrice
		target.lastEmaAt = now
		target.lowStreak = 0
		-- При первичной инициализации якоря не сбиваем уже сработавший хит вниз
		if livePrice > (target.maxPrice or 0) then
			local newMax = math.max(1, math.floor(target.emaPrice * ratio + 0.5))
			if newMax ~= target.maxPrice then
				target.maxPrice = newMax
				target.ts = now
				return true
			end
		end
		return false
	end

	if livePrice <= (target.maxPrice or 0) then
		-- Похоже на дешёвый лот: игнорируем разовые выбросы, тянем якорь вниз только при устойчивом падении рынка
		target.lowStreak = (target.lowStreak or 0) + 1
		target.lastEmaAt = now
		if target.lowStreak < EMA_LOW_STREAK_THRESHOLD then
			return false
		end
		target.emaPrice = math.max(1, math.floor(target.emaPrice * (1 - EMA_ALPHA) + livePrice * EMA_ALPHA + 0.5))
	else
		target.lowStreak = 0
		target.lastEmaAt = now
		local capped = math.min(livePrice, math.max(1, math.floor(target.emaPrice * EMA_MAX_UP_MULT + 0.5)))
		target.emaPrice = math.max(1, math.floor(target.emaPrice * (1 - EMA_ALPHA) + capped * EMA_ALPHA + 0.5))
	end

	local newMax = math.max(1, math.floor(target.emaPrice * ratio + 0.5))
	if newMax ~= target.maxPrice then
		target.maxPrice = newMax
		target.ts = now
		return true
	end
	return false
end

local function ParseAutoScanInterval(text)
	if text == nil then
		return DEFAULT_SNIPE_AUTOSCAN_INTERVAL
	end
	local s = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then
		return DEFAULT_SNIPE_AUTOSCAN_INTERVAL
	end
	if not s:match("^%d+$") then
		return nil
	end
	local n = tonumber(s)
	if not n or n < MIN_SNIPE_AUTOSCAN_INTERVAL or n > MAX_SNIPE_AUTOSCAN_INTERVAL then
		return nil
	end
	return n
end

local function EnsureSnipeDB()
	if not ns.realmDB then
		return {}
	end
	ns.realmDB.snipeTargets = ns.realmDB.snipeTargets or {}
	return ns.realmDB.snipeTargets
end

local function IsAuctionHouseOpen()
	return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
end

local function GetActiveAuctionFrame()
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		return AuctionHouseFrame
	end
	if AuctionFrame and AuctionFrame:IsShown() then
		return AuctionFrame
	end
	return nil
end

local function StopSnipeAutoScan()
	autoScanTimerToken = autoScanTimerToken + 1
end

local ScheduleNextSnipeAutoScan

function ns:SetSnipeAutoScanEnabled(on)
	local enabled = (on == true)
	if self.db and self.db.options then
		self.db.options.snipeAutoScan = enabled
	end
	if snipeBar and snipeBar.autoScanCb then
		snipeBar.autoScanCb:SetChecked(enabled)
	end
	if sniperSettingsFrame and sniperSettingsFrame.cbAutoScan then
		sniperSettingsFrame.cbAutoScan:SetChecked(enabled)
	end
	if enabled then
		ScheduleNextSnipeAutoScan(0.1)
	else
		StopSnipeAutoScan()
	end
	self:RefreshSnipeUI()
end

ScheduleNextSnipeAutoScan = function(delayOverride)
	autoScanTimerToken = autoScanTimerToken + 1
	local tok = autoScanTimerToken
	if not (C_Timer and C_Timer.After) then
		return
	end
	if not (C_AuctionHouse and C_AuctionHouse.SearchForItemKeys) then
		return
	end
	if not IsAuctionHouseOpen() then
		return
	end
	if not (ns.IsModuleEnabled and ns:IsModuleEnabled("profit")) then
		return
	end
	if not (ns.db and ns.db.options and ns.db.options.snipeAutoScan == true) then
		return
	end
	if #ns:GetActiveSnipeTargetList() == 0 then
		return
	end
	local delay = delayOverride or ns:GetSnipeAutoScanInterval()
	if delay < 0.1 then
		delay = 0.1
	end
	C_Timer.After(delay, function()
		if tok ~= autoScanTimerToken then
			return
		end
		if not IsAuctionHouseOpen() then
			return
		end
		if not (ns.IsModuleEnabled and ns:IsModuleEnabled("profit")) then
			return
		end
		if not (ns.db and ns.db.options and ns.db.options.snipeAutoScan == true) then
			return
		end
		if #ns:GetActiveSnipeTargetList() == 0 then
			return
		end
		if activeSnipeBatch then
			return
		end
		if pendingBuy then
			ScheduleNextSnipeAutoScan(2.0)
			return
		end
		local now = GetTime and GetTime() or 0
		local sinceExt = now - lastExternalAhActivityAt
		if sinceExt >= 0 and sinceExt < EXTERNAL_AH_PAUSE_SEC then
			ScheduleNextSnipeAutoScan(math.max(0.5, EXTERNAL_AH_PAUSE_SEC - sinceExt + 0.2))
			return
		end
		if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
			ScheduleNextSnipeAutoScan(0.6)
			return
		end
		lastAutoScanAt = now
		ns:SearchSnipeTargetsOnAH()
	end)
end

function ns:GetSnipeTargets()
	return EnsureSnipeDB()
end

function ns:GetSnipeTargetList()
	local targets = EnsureSnipeDB()
	local list = {}
	for _, t in pairs(targets) do
		list[#list + 1] = t
	end
	table.sort(list, function(a, b)
		return (a.itemID or 0) < (b.itemID or 0)
	end)
	return list
end

function ns:GetActiveSnipeTargetList()
	local targets = EnsureSnipeDB()
	local list = {}
	for _, t in pairs(targets) do
		if t and t.enabled ~= false then
			list[#list + 1] = t
		end
	end
	table.sort(list, function(a, b)
		return (a.itemID or 0) < (b.itemID or 0)
	end)
	return list
end

function ns:SetSnipeTargetEnabled(itemID, enabled)
	local targets = EnsureSnipeDB()
	local t = targets[itemID]
	if not t then
		return
	end
	t.enabled = (enabled == true)
	if not t.enabled then
		if self.snipeHits then
			self.snipeHits[itemID] = nil
		end
	else
		self:EvaluateSnipeItem(itemID, true)
		if not activeSnipeBatch then
			ScheduleNextSnipeAutoScan()
		end
	end
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
end

function ns:AddSnipeTarget(itemID, maxPrice, recipeID, deferSync, isManual)
	if not itemID or itemID <= 0 or not maxPrice or maxPrice <= 0 then
		return false
	end
	local targets = EnsureSnipeDB()
	local prev = targets[itemID]
	local now = time and time() or 0
	local liveP = self:GetSnipeLiveMarketPrice(itemID)
	targets[itemID] = {
		itemID = itemID,
		maxPrice = math.max(1, math.floor(maxPrice + 0.5)),
		recipeID = recipeID or (prev and prev.recipeID),
		ts = now,
		enabled = (prev and prev.enabled == false) and false or true,
		manual = (isManual == true),
		emaPrice = (liveP and liveP > 0) and liveP or (prev and prev.emaPrice) or nil,
		lastEmaAt = (liveP and liveP > 0) and now or (prev and prev.lastEmaAt) or 0,
		lowStreak = 0,
	}
	self:EvaluateSnipeItem(itemID, true)
	if not deferSync then
		self:SyncSnipeShoppingList(true)
		self:RefreshSnipeUI()
		if not activeSnipeBatch then
			ScheduleNextSnipeAutoScan()
		end
	end
	return true
end

function ns.ParseMoneyInput(text)
	if text == nil then
		return nil
	end
	local s = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then
		return nil
	end
	s = s:gsub(",", ".")
		:gsub("Г", "g"):gsub("г", "g")
		:gsub("З", "g"):gsub("з", "g")
		:gsub("С", "s"):gsub("с", "s")
		:gsub("М", "c"):gsub("м", "c")
		:gsub("G", "g"):gsub("S", "s"):gsub("C", "c")
		:gsub("%s+", "")
	local gStr = s:match("(%d*%.?%d+)g")
	local sStr = s:match("(%d*%.?%d+)s")
	local cStr = s:match("(%d*%.?%d+)c")
	if gStr or sStr or cStr then
		local rem = s
		if gStr then rem = rem:gsub(gStr:gsub("%.", "%%.") .. "g", "", 1) end
		if sStr then rem = rem:gsub(sStr:gsub("%.", "%%.") .. "s", "", 1) end
		if cStr then rem = rem:gsub(cStr:gsub("%.", "%%.") .. "c", "", 1) end
		if rem ~= "" then
			return nil
		end
		local total = (tonumber(gStr) or 0) * 10000 + (tonumber(sStr) or 0) * 100 + (tonumber(cStr) or 0)
		total = math.floor(total + 0.5)
		return (total > 0) and total or nil
	end
	local num = tonumber(s)
	if not num or num <= 0 then
		return nil
	end
	return math.max(1, math.floor(num * 10000 + 0.5))
end

function ns.FormatMoneyPlain(copper)
	local c = math.max(0, math.floor(tonumber(copper) or 0))
	if c <= 0 then
		return ""
	end
	local g = math.floor(c / 10000)
	local s = math.floor((c % 10000) / 100)
	local m = c % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if m > 0 or #parts == 0 then parts[#parts + 1] = m .. "c" end
	return table.concat(parts, " ")
end

function ns:GetSnipeBuyLimits()
	local opts = self.db and self.db.options
	local maxSpend = (opts and opts.snipeMaxSpend ~= nil) and tonumber(opts.snipeMaxSpend) or DEFAULT_SNIPE_MAX_SPEND
	local maxQty = (opts and opts.snipeMaxQty ~= nil) and tonumber(opts.snipeMaxQty) or DEFAULT_SNIPE_MAX_QTY
	local minReserve = (opts and opts.snipeMinReserve ~= nil) and tonumber(opts.snipeMinReserve) or DEFAULT_SNIPE_MIN_RESERVE
	maxSpend = math.max(0, math.floor((maxSpend or 0) + 0.5))
	maxQty = math.max(0, math.floor((maxQty or 0) + 0.5))
	minReserve = math.max(0, math.floor((minReserve or 0) + 0.5))
	return maxSpend, maxQty, minReserve
end

function ns:FormatSnipeLimitsSummary()
	local maxSpend, maxQty, minReserve = self:GetSnipeBuyLimits()
	local parts = {}
	if maxSpend > 0 then
		parts[#parts + 1] = "<= " .. self.FormatMoney(maxSpend)
	end
	if minReserve > 0 then
		parts[#parts + 1] = L["SNIPE_LIMIT_MIN_RESERVE"] .. " " .. self.FormatMoney(minReserve)
	end
	if maxQty > 0 then
		parts[#parts + 1] = "x" .. maxQty
	end
	if #parts == 0 then
		return L["SNIPE_LIMIT_UNLIMITED"]
	end
	return table.concat(parts, " | ")
end

local function ComputeAvailableSnipeBudget(money)
	local maxSpend, maxQty, minReserve = ns:GetSnipeBuyLimits()
	local m = math.max(0, tonumber(money) or 0)
	local avail = math.max(0, m - minReserve)
	local budget = (maxSpend > 0) and math.min(avail, maxSpend) or avail
	return budget, maxQty, maxSpend, minReserve
end

local function ClassifyBudgetBlock(money, price, maxSpend, minReserve)
	local m = math.max(0, tonumber(money) or 0)
	if m < price then
		return "nomoney"
	end
	if minReserve > 0 and (m - minReserve) < price then
		return "reserve"
	end
	if maxSpend > 0 and price > maxSpend then
		return "budget"
	end
	return "nomoney"
end

local function ValidateBuyoutSpend(totalPrice, money)
	local tp = tonumber(totalPrice) or 0
	local m = math.max(0, tonumber(money) or 0)
	if tp <= 0 then
		return true, nil
	end
	local maxSpend, _, minReserve = ns:GetSnipeBuyLimits()
	if tp > m then
		return false, L["SNIPE_BUY_NOMONEY"]
	end
	if minReserve > 0 and (m - tp) < minReserve then
		return false, string.format(L["SNIPE_BUY_RESERVE_CAP"], ns.FormatMoney(minReserve))
	end
	if maxSpend > 0 and tp > maxSpend then
		return false, string.format(L["SNIPE_BUY_BUDGET_CAP"], ns.FormatMoney(tp), ns.FormatMoney(maxSpend))
	end
	return true, nil
end

local function ParseOptionalMoneyLimit(text)
	local s = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" or s == "0" then
		return 0
	end
	local norm = s:gsub(",", ".")
		:gsub("Г", "g"):gsub("г", "g")
		:gsub("З", "g"):gsub("з", "g")
		:gsub("С", "s"):gsub("с", "s")
		:gsub("М", "c"):gsub("м", "c")
		:gsub("G", "g"):gsub("S", "s"):gsub("C", "c")
		:gsub("%s+", "")
	if norm == "0.0"
		or norm:match("^0+[gsc]$")
		or norm:match("^0+g0+s$")
		or norm:match("^0+g0+s0+c$")
		or norm:match("^0+s0+c$")
	then
		return 0
	end
	return ns.ParseMoneyInput(s)
end

local function ParseOptionalQtyLimit(text)
	local s = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then
		return 0
	end
	local n = tonumber(s:match("^(%d+)$"))
	if n == nil or n < 0 then
		return nil
	end
	return math.floor(n)
end

function ns:ResolveItemIDFromInput(input)
	if input == nil then
		return nil
	end
	local s = tostring(input):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then
		return nil
	end
	local fromLink = tonumber(s:match("item:(%d+)"))
	if fromLink and fromLink > 0 then
		if C_Item and C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(fromLink) then
			return nil
		end
		return fromLink
	end
	local pureID = tonumber(s:match("^(%d+)$"))
	if pureID and pureID > 0 then
		if C_Item and C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(pureID) then
			return nil
		end
		return pureID
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local ok, id = pcall(C_Item.GetItemInfoInstant, s)
		if ok and type(id) == "number" and id > 0 then
			return id
		end
	end
	if C_Item and C_Item.GetItemInfo then
		local ok, _, link = pcall(C_Item.GetItemInfo, s)
		local id = ok and link and tonumber(link:match("item:(%d+)"))
		if id and id > 0 then
			return id
		end
	end

	-- Поиск по известным TradeFlow предметам (сумки, банк, рецепты, распыл, текущие цели снайпа)
	local qLow = s:lower()
	local checked = {}
	local subMatchID, subMatchLen = nil, math.huge
	local function CheckItem(id)
		if not (type(id) == "number" and id > 0) or checked[id] then
			return nil
		end
		checked[id] = true
		local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
			or (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id))
		if type(itemName) == "string" and itemName ~= "" then
			if itemName == s or itemName:lower() == qLow then
				return id
			end
			if itemName:lower():find(qLow, 1, true) and #itemName < subMatchLen then
				subMatchID = id
				subMatchLen = #itemName
			end
		end
		return nil
	end
	for id in pairs(EnsureSnipeDB()) do
		if CheckItem(id) then return id end
	end
	if self.charDB then
		for id in pairs(self.charDB.bags or {}) do
			if CheckItem(id) then return id end
		end
		for id in pairs(self.charDB.bank or {}) do
			if CheckItem(id) then return id end
		end
	end
	for id in pairs(self.DisenchantMatIDs or {}) do
		if CheckItem(id) then return id end
	end
	for id in pairs(self.VendorPrices or {}) do
		if CheckItem(id) then return id end
	end
	for _, sc in pairs(self.RecipeScrolls or {}) do
		if sc and sc[1] and CheckItem(sc[1]) then return sc[1] end
	end
	for _, rec in pairs(self.RecipeData or {}) do
		if rec.output and rec.output.itemID and CheckItem(rec.output.itemID) then
			return rec.output.itemID
		end
		if rec.reagents then
			for _, r in ipairs(rec.reagents) do
				if r.itemID and CheckItem(r.itemID) then
					return r.itemID
				end
			end
		end
	end
	return subMatchID
end

function ns:AddManualSnipeTarget(itemInput, priceInput, explicitItemID)
	local itemID = (type(explicitItemID) == "number" and explicitItemID > 0) and explicitItemID
		or self:ResolveItemIDFromInput(itemInput)
	if not itemID or itemID <= 0 or (C_Item and C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(itemID)) then
		if self.Print then
			self:Print(L["SNIPE_ADD_NOT_FOUND"])
		end
		return false
	end
	local priceStr = tostring(priceInput or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local maxPrice
	if priceStr ~= "" then
		maxPrice = ns.ParseMoneyInput(priceStr)
		if not maxPrice then
			if self.Print then
				self:Print(L["SNIPE_ADD_BAD_PRICE"])
			end
			return false
		end
	else
		local curAh = self:GetSnipeLiveMarketPrice(itemID)
		if curAh and curAh > 0 then
			maxPrice = math.max(1, math.floor(curAh * self:GetSnipeDiscountRatio() + 0.5))
		else
			if self.Print then
				self:Print(L["SNIPE_ADD_NEED_PRICE"])
			end
			return false
		end
	end
	if not self:AddSnipeTarget(itemID, maxPrice, nil, false, priceStr ~= "") then
		return false
	end
	local name, _, _, link, _, hex = self:GetItemDisplay(itemID)
	local label = link or ((hex or "|cffffffff") .. (name or ("#" .. itemID)) .. "|r")
	if self.Print then
		self:Print(string.format(L["SNIPE_ADD_DONE"], label, ns.FormatMoney(maxPrice)))
	end
	return true
end

function ns:GetRecipeSnipePreview(recipeID, discountRatio, craftPlan)
	local items = {}
	local newCount = 0
	if not recipeID then
		return items, 0, 0
	end
	local ratio = discountRatio or self:GetSnipeDiscountRatio()
	local targets = EnsureSnipeDB()
	local seenItems = {}
	local visitedRecipes = {}

	local function AddAhReagent(itemID, curPrice)
		if not (itemID and curPrice and curPrice > 0) or seenItems[itemID] then
			return
		end
		seenItems[itemID] = true
		local maxP = math.max(1, math.floor(curPrice * ratio + 0.5))
		local watched = targets[itemID] ~= nil
		if not watched then
			newCount = newCount + 1
		end
		items[#items + 1] = {
			itemID = itemID,
			curPrice = curPrice,
			maxPrice = targets[itemID] and targets[itemID].maxPrice or maxP,
			watched = watched,
		}
	end

	local function Collect(rID)
		if not rID or visitedRecipes[rID] then
			return
		end
		visitedRecipes[rID] = true
		local _, _, _, breakdown = self:GetRecipeEconomy(rID)
		if not breakdown then
			visitedRecipes[rID] = nil
			return
		end
		for _, b in ipairs(breakdown) do
			if b.itemID then
				if b.source == "ah" and b.unitPrice and b.unitPrice > 0 then
					AddAhReagent(b.itemID, b.unitPrice)
				elseif b.source == "craft" and b.subRecipeID then
					if craftPlan and craftPlan[b.itemID] == false then
						local ahP = self.GetAuctionPrice and self:GetAuctionPrice(b.itemID)
						if ahP and ahP > 0 then
							AddAhReagent(b.itemID, ahP)
						else
							Collect(b.subRecipeID)
						end
					else
						Collect(b.subRecipeID)
					end
				end
			end
		end
		visitedRecipes[rID] = nil
	end

	Collect(recipeID)
	return items, newCount, #items
end

function ns:AddRecipeReagentsToSnipe(recipeID, discountRatio, craftPlan)
	local items = self:GetRecipeSnipePreview(recipeID, discountRatio, craftPlan)
	local added = 0
	for _, entry in ipairs(items) do
		if not entry.watched then
			if self:AddSnipeTarget(entry.itemID, entry.maxPrice, recipeID, true) then
				added = added + 1
			end
		end
	end
	if added > 0 then
		self:SyncSnipeShoppingList(true)
		self:RefreshSnipeUI()
	end
	return added, #items
end

function ns:ImportShoppingToSnipe(discountRatio)
	local ratio = discountRatio or self:GetSnipeDiscountRatio()
	local shopping = self.GetShoppingList and self:GetShoppingList() or {}
	local targets = EnsureSnipeDB()
	local added = 0
	for _, item in ipairs(shopping) do
		local buyQty = (item.toBuy ~= nil) and item.toBuy or item.missing
		if item.itemID and item.source == "ah" and (buyQty or 0) > 0 and item.unitPrice and item.unitPrice > 0 and not targets[item.itemID] then
			local maxP = math.max(1, math.floor(item.unitPrice * ratio + 0.5))
			if self:AddSnipeTarget(item.itemID, maxP, nil, true) then
				added = added + 1
			end
		end
	end
	if added > 0 then
		self:SyncSnipeShoppingList(true)
		self:RefreshSnipeUI()
	end
	return added
end

function ns:SetSnipeTargetPrice(itemID, maxPrice, isManual)
	local targets = EnsureSnipeDB()
	local t = targets[itemID]
	if not t or not maxPrice or maxPrice <= 0 then
		return false
	end
	t.maxPrice = math.max(1, math.floor(maxPrice + 0.5))
	t.manual = (isManual ~= false)
	t.ts = time and time() or 0
	t.lowStreak = 0
	self:EvaluateSnipeItem(itemID, true)
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
	return true
end

function ns:ResetSnipeTargetPin(itemID)
	local targets = EnsureSnipeDB()
	local t = targets[itemID]
	if not t then
		return false
	end
	local now = time and time() or 0
	t.manual = false
	t.lowStreak = 0
	local cur = self:GetSnipeLiveMarketPrice(itemID)
	if cur and cur > 0 then
		t.emaPrice = cur
		t.lastEmaAt = now
		t.maxPrice = math.max(1, math.floor(cur * self:GetSnipeDiscountRatio() + 0.5))
		t.ts = now
	end
	self:EvaluateSnipeItem(itemID, true)
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
	return true
end

function ns:AdjustSnipeTarget(itemID, factor)
	local targets = EnsureSnipeDB()
	local t = targets[itemID]
	if not t then
		return
	end
	self:SetSnipeTargetPrice(itemID, math.max(1, math.floor((t.maxPrice or 1) * factor + 0.5)), true)
end

function ns:RepriceSnipeTargets(ratio)
	local r = ratio or self:GetSnipeDiscountRatio()
	local discPct = math.max(1, math.floor((1 - r) * 100 + 0.5))
	local targets = EnsureSnipeDB()
	local now = time and time() or 0
	local updated = 0
	for itemID, t in pairs(targets) do
		if not t.manual then
			local cur = self:GetSnipeLiveMarketPrice(itemID)
			if cur and cur > 0 then
				t.maxPrice = math.max(1, math.floor(cur * r + 0.5))
				t.ts = now
				t.emaPrice = cur
				t.lastEmaAt = now
				t.lowStreak = 0
				self:EvaluateSnipeItem(itemID, true)
				updated = updated + 1
			end
		end
	end
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
	self:Print(string.format(L["SNIPE_REPRICED_MSG"], updated, discPct))
	return updated
end

function ns:RemoveSnipeTarget(itemID)
	local targets = EnsureSnipeDB()
	targets[itemID] = nil
	if self.snipeHits then
		self.snipeHits[itemID] = nil
	end
	lastChatHitAt[itemID] = nil
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
end

function ns:ClearSnipeTargets()
	if self.realmDB then
		self.realmDB.snipeTargets = {}
	end
	self.snipeHits = {}
	wipe(lastChatHitAt)
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
end

function ns.FormatSnipeHitQty(hit)
	if not hit or not hit.qty then
		return L["SNIPE_LOT_ANY"]
	end
	if hit.totalCheapQty and hit.totalCheapQty > hit.qty then
		return string.format(L["SNIPE_QTY_RANGE"], hit.qty, hit.totalCheapQty)
	end
	return "x" .. hit.qty
end

-- Сверяем актуальный снимок ahStock для itemID со снайп-целью
function ns:EvaluateSnipeItem(itemID, silent)
	self.snipeHits = self.snipeHits or {}
	if not (self.IsModuleEnabled and self:IsModuleEnabled("profit")) then
		self.snipeHits[itemID] = nil
		return nil
	end
	local targets = EnsureSnipeDB()
	local target = targets[itemID]
	if not target or target.enabled == false then
		self.snipeHits[itemID] = nil
		return nil
	end
	local stock = self.realmDB and self.realmDB.ahStock and self.realmDB.ahStock[itemID]
	local now = time and time() or 0
	if not stock or (stock.ts and stock.ts > 0 and now > 0 and (now - stock.ts) > MAX_SNIPE_STOCK_AGE) then
		self.snipeHits[itemID] = nil
		return nil
	end
	if stock.price and stock.price > 0 and (not stock.ts or stock.ts <= 0 or now <= 0 or (now - stock.ts) <= 60) then
		UpdateSnipeMarketEMA(target, stock.price, now)
	end

	local bestQty = nil
	local cheapQty = nil
	local bestPrice = nil
	if stock.isAggregate then
		if stock.price and stock.price > 0 and stock.price <= target.maxPrice then
			bestPrice = stock.price
			bestQty = nil -- сводка BrowseResults / ProcessScan не даёт точное кол-во на минимальной цене
			cheapQty = nil
		end
	else
		local tiers = (stock.tiers and #stock.tiers > 0 and stock.tiers)
			or (stock.price and { { stock.price, stock.total or stock.qty or 0 } })
		if tiers then
			local sumQty = 0
			for _, tier in ipairs(tiers) do
				local p, q = tier[1] or 0, tier[2] or 0
				if p > 0 and q > 0 and p <= target.maxPrice then
					sumQty = sumQty + q
					if not bestPrice or p < bestPrice then
						bestPrice = p
						bestQty = q
					elseif p == bestPrice then
						bestQty = (bestQty or 0) + q
					end
				end
			end
			if sumQty > 0 then
				cheapQty = sumQty
			end
		end
	end

	if bestPrice then
		local prev = self.snipeHits[itemID]
		local isPriceAlert = (not prev) or (prev.silentOnly == true) or (bestPrice < prev.bestPrice)
		local alerted = (not silent) and isPriceAlert and IsAuctionHouseOpen()
		local discountPct = (target.maxPrice > 0)
			and math.max(0, math.floor((target.maxPrice - bestPrice) / target.maxPrice * 100 + 0.5))
			or 0
		local hit = {
			itemID = itemID,
			bestPrice = bestPrice,
			qty = bestQty,
			totalCheapQty = cheapQty,
			maxPrice = target.maxPrice,
			discountPct = discountPct,
			ts = stock.ts or now,
			silentOnly = (not alerted) and ((not prev) or prev.silentOnly == true),
		}
		self.snipeHits[itemID] = hit
		if alerted then
			local tNow = GetTime and GetTime() or 0
			if PlaySound and (tNow - lastSoundAt) > 5 then
				lastSoundAt = tNow
				pcall(PlaySound, 8959)
			end
			if (tNow - (lastChatHitAt[itemID] or 0)) > 5 then
				lastChatHitAt[itemID] = tNow
				local name, _, _, link, _, hex = self:GetItemDisplay(itemID)
				local label = link or ((hex or "|cffffffff") .. name .. "|r")
				self:Print(string.format(
					L["SNIPE_HIT_CHAT"],
					label,
					ns.FormatSnipeHitQty(hit),
					ns.FormatMoney(bestPrice),
					ns.FormatMoney(target.maxPrice),
					discountPct
				))
			end
		end
		return hit
	end

	self.snipeHits[itemID] = nil
	return nil
end

function ns:GetSnipeHitList()
	local res = {}
	for _, hit in pairs(self.snipeHits or {}) do
		res[#res + 1] = hit
	end
	table.sort(res, function(a, b)
		if (a.discountPct or 0) ~= (b.discountPct or 0) then
			return (a.discountPct or 0) > (b.discountPct or 0)
		end
		return (a.itemID or 0) < (b.itemID or 0)
	end)
	return res
end

local function SafeAuctionatorMaxPrice(target)
	if not target or target <= 0 then
		return nil
	end
	-- Auctionator раскладывает maxPrice на золото/серебро/медь через /100 и /10000 во float;
	-- проверяем итоговую восстановленную цену против target (обычно до +1..+2c)
	local q = target
	for _ = 1, 10 do
		local g = math.floor(q / 10000)
		local s = math.floor(((q / 10000) - g) * 100)
		local c = math.floor(((q / 100) - math.floor(q / 100)) * 100)
		local remGold = math.floor(((q / 10000) - g) * 10000)
		local rebuilt = g * 10000 + s * 100 + c
		if math.floor((q / 100) * 100) < target
			or math.floor((q / 10000) * 10000) < target
			or (g * 10000 + remGold) < target
			or rebuilt < target
		then
			q = q + 1
		else
			return q
		end
	end
	return q
end

function ns:SyncSnipeShoppingList(silent)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
		return
	end
	local targets = self:GetActiveSnipeTargetList()
	local listName = L["SNIPE_LIST_NAME"]
	local parts = {}
	for _, t in ipairs(targets) do
		parts[#parts + 1] = (t.itemID or 0) .. ":" .. (t.maxPrice or 0)
	end
	local sig = listName .. "|" .. table.concat(parts, ",")
	snipeSyncToken = snipeSyncToken + 1
	local token = snipeSyncToken
	if silent and sig == lastSnipeListSig then
		return
	end

	if #targets == 0 then
		lastSnipeListSig = sig
		if api.GetShoppingListItems and api.DeleteShoppingList then
			local ok, existing = pcall(api.GetShoppingListItems, ADDON_NAME, listName)
			if ok and existing then
				pcall(api.DeleteShoppingList, ADDON_NAME, listName)
			end
		end
		return
	end

	self:WithLoadedItems(targets, function()
		if token ~= snipeSyncToken then
			return
		end
		local searches = {}
		for _, t in ipairs(targets) do
			local name, _, _, _, loaded = self:GetItemDisplay(t.itemID)
			if loaded and name then
				local ok, str = pcall(api.ConvertToSearchString, ADDON_NAME, {
					searchString = name,
					isExact = true,
					maxPrice = SafeAuctionatorMaxPrice(t.maxPrice),
				})
				if ok and str then
					searches[#searches + 1] = str
				end
			end
		end
		if #searches > 0 then
			lastSnipeListSig = sig
			pcall(api.CreateShoppingList, ADDON_NAME, listName, searches)
		end
	end)
end

local function RunAuctionatorSnipeSearch(items, skipPriceFilter)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and (api.MultiSearchAdvanced or api.MultiSearchExact)) then
		ns:Print(L["ATR_NOT_FOUND"])
		return
	end
	ns:WithLoadedItems(items, function()
		if not IsAuctionHouseOpen() then
			return
		end
		local advanced, names = {}, {}
		for _, t in ipairs(items) do
			local name, _, _, _, loaded = ns:GetItemDisplay(t.itemID)
			if loaded and name then
				names[#names + 1] = name
				local q = {
					searchString = name,
					isExact = true,
				}
				-- При общем скане передаём SafeAuctionatorMaxPrice; для уже найденных хитов открываем стакан целиком
				if not skipPriceFilter and t.maxPrice and t.maxPrice > 0 then
					q.maxPrice = SafeAuctionatorMaxPrice(t.maxPrice)
				end
				advanced[#advanced + 1] = q
			end
		end
		local searched = false
		if api.MultiSearchAdvanced and #advanced > 0 then
			local ok = pcall(api.MultiSearchAdvanced, ADDON_NAME, advanced)
			searched = ok
		end
		if not searched and api.MultiSearchExact and #names > 0 then
			pcall(api.MultiSearchExact, ADDON_NAME, names)
		end
	end)
end

local function CancelSnipeBatch(silent)
	if not activeSnipeBatch then
		return
	end
	activeSnipeBatch = nil
	if not silent then
		ns:RefreshSnipeUI()
		ScheduleNextSnipeAutoScan()
	end
end

local SendNextSnipeBatchChunk
local RequestTopSnipeHitDetails

SendNextSnipeBatchChunk = function()
	local batch = activeSnipeBatch
	if not batch then
		return
	end
	if not IsAuctionHouseOpen() then
		CancelSnipeBatch(true)
		return
	end
	local chunk = batch.chunks[batch.index]
	if not chunk or #chunk == 0 then
		CancelSnipeBatch(false)
		return
	end
	if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		batch.throttleRetries = (batch.throttleRetries or 0) + 1
		if batch.throttleRetries > 12 then
			CancelSnipeBatch(false)
			return
		end
		batch.waitingThrottle = true
		if C_Timer and C_Timer.After then
			local tok = batch.token
			local idx = batch.index
			C_Timer.After(0.35, function()
				if activeSnipeBatch and activeSnipeBatch.token == tok and activeSnipeBatch.index == idx and activeSnipeBatch.waitingThrottle then
					SendNextSnipeBatchChunk()
				end
			end)
		end
		return
	end
	batch.throttleRetries = 0

	local keys = {}
	local chunkSet = {}
	for _, itemID in ipairs(chunk) do
		chunkSet[itemID] = true
		if C_AuctionHouse.MakeItemKey then
			keys[#keys + 1] = C_AuctionHouse.MakeItemKey(itemID)
		else
			keys[#keys + 1] = { itemID = itemID }
		end
	end
	batch.chunkSet = chunkSet
	batch.seen = {}
	batch.waitingThrottle = false
	batch.waitingResults = true
	batch.gotInitialUpdate = false
	batch.pendingMore = false

	local ok = pcall(C_AuctionHouse.SearchForItemKeys, keys, {})
	if not ok then
		local fallbackItems = batch.items
		CancelSnipeBatch(true)
		ns:RefreshSnipeBar()
		RunAuctionatorSnipeSearch(fallbackItems, false)
		return
	end

	if C_Timer and C_Timer.After then
		local tok = batch.token
		local idx = batch.index
		C_Timer.After(SNIPE_BATCH_TIMEOUT, function()
			if activeSnipeBatch and activeSnipeBatch.token == tok and activeSnipeBatch.index == idx then
				CancelSnipeBatch(false)
			end
		end)
	end
end

local function HandleSnipeBatchResults(results, isAdded)
	local batch = activeSnipeBatch
	if not (batch and batch.waitingResults and batch.chunkSet) then
		return
	end
	if isAdded and not batch.gotInitialUpdate then
		lastExternalAhActivityAt = GetTime and GetTime() or lastExternalAhActivityAt
		return
	end
	local chunkSet = batch.chunkSet
	if type(results) == "table" then
		-- Если пришёл непустой ответ, в котором нет ни одного itemID из нашего чанка —
		-- это чужой browse-запрос, игнорируем его чтобы не сбросить свои хиты.
		if #results > 0 then
			local matchedAny = false
			for _, r in ipairs(results) do
				local id = r and r.itemKey and r.itemKey.itemID
				if id and chunkSet[id] then
					matchedAny = true
					break
				end
			end
			if not matchedAny then
				lastExternalAhActivityAt = GetTime and GetTime() or lastExternalAhActivityAt
				return
			end
		end
		if not isAdded then
			batch.gotInitialUpdate = true
		end
		for _, r in ipairs(results) do
			local id = r and r.itemKey and r.itemKey.itemID
			if id and chunkSet[id] and (r.minPrice or 0) > 0 and (r.totalQuantity or 0) > 0 then
				batch.seen[id] = true
			end
		end
	elseif not isAdded then
		batch.gotInitialUpdate = true
	end

	local hasFull = (not (C_AuctionHouse and C_AuctionHouse.HasFullBrowseResults)) or C_AuctionHouse.HasFullBrowseResults()
	if not hasFull then
		if C_AuctionHouse and C_AuctionHouse.RequestMoreBrowseResults then
			if (not C_AuctionHouse.IsThrottledMessageSystemReady) or C_AuctionHouse.IsThrottledMessageSystemReady() then
				batch.pendingMore = false
				pcall(C_AuctionHouse.RequestMoreBrowseResults)
			else
				batch.pendingMore = true
			end
		end
		return
	end

	-- Чанк полностью получен: убираем устаревшие хиты по позициям, которых на AH больше нет (0 лотов)
	for itemID in pairs(chunkSet) do
		if not batch.seen[itemID] then
			if ns.realmDB and ns.realmDB.ahStock then
				ns.realmDB.ahStock[itemID] = nil
			end
			ns:EvaluateSnipeItem(itemID, true)
		end
	end

	batch.waitingResults = false
	batch.index = batch.index + 1
	if batch.index <= #batch.chunks then
		SendNextSnipeBatchChunk()
	else
		activeSnipeBatch = nil
		if RequestTopSnipeHitDetails then
			RequestTopSnipeHitDetails()
		end
		ns:RefreshSnipeUI()
		ScheduleNextSnipeAutoScan()
	end
end

local function StartSnipeBatchScan(items)
	if activeSnipeBatch then
		return
	end
	local chunks = {}
	local cur = {}
	for _, t in ipairs(items) do
		if t and t.itemID and t.itemID > 0 then
			cur[#cur + 1] = t.itemID
			if #cur >= SNIPE_BATCH_CHUNK_SIZE then
				chunks[#chunks + 1] = cur
				cur = {}
			end
		end
	end
	if #cur > 0 then
		chunks[#chunks + 1] = cur
	end
	if #chunks == 0 then
		return
	end
	snipeBatchToken = snipeBatchToken + 1
	activeSnipeBatch = {
		token = snipeBatchToken,
		chunks = chunks,
		index = 1,
		items = items,
		chunkSet = nil,
		seen = nil,
		waitingThrottle = false,
		waitingResults = false,
		pendingMore = false,
	}
	ns:RefreshSnipeBar()
	SendNextSnipeBatchChunk()
end

function ns:SearchSnipeTargetsOnAH(targetOrFilter, ignorePrice)
	if not IsAuctionHouseOpen() then
		self:Print(L["AH_NOT_OPEN"])
		return
	end
	if self.LogTrace then
		self:LogTrace("SnipeSearchAH", tostring(targetOrFilter or "all"))
	end

	self:SyncSnipeShoppingList(true)
	local targets = EnsureSnipeDB()
	local items = {}
	local skipPriceFilter = (ignorePrice == true) or (targetOrFilter == "hits")
	if targetOrFilter == "hits" then
		for _, h in ipairs(self:GetSnipeHitList()) do
			if targets[h.itemID] then
				items[#items + 1] = targets[h.itemID]
			end
		end
	elseif type(targetOrFilter) == "number" then
		if targets[targetOrFilter] then
			items[1] = targets[targetOrFilter]
		end
	else
		items = self:GetActiveSnipeTargetList()
	end
	if #items == 0 then
		return
	end

	-- Общий скан снайпера: нативный батч-запрос C_AuctionHouse.SearchForItemKeys (до 100 позиций за 1 запрос)
	if targetOrFilter == nil and C_AuctionHouse and C_AuctionHouse.SearchForItemKeys then
		StartSnipeBatchScan(items)
		return
	end

	CancelSnipeBatch(true)
	lastExternalAhActivityAt = GetTime and GetTime() or lastExternalAhActivityAt
	self:RefreshSnipeBar()
	RunAuctionatorSnipeSearch(items, skipPriceFilter)
end

local function HookAuctionFrameShow(ah)
	if ah and not hookedAuctionFrames[ah] and ah.HookScript then
		hookedAuctionFrames[ah] = true
		ah:HookScript("OnShow", function()
			if ns.RefreshSnipeBar then
				ns:RefreshSnipeBar()
			end
		end)
		ah:HookScript("OnHide", function()
			if snipeBar then
				snipeBar:Hide()
			end
		end)
	end
end

local function ClearStaleSnipeHit(itemID, newMinPrice)
	if itemID and ns.snipeHits then
		ns.snipeHits[itemID] = nil
	end
	if itemID and ns.realmDB and ns.realmDB.ahStock and ns.realmDB.ahStock[itemID] then
		if newMinPrice and newMinPrice > 0 then
			local s = ns.realmDB.ahStock[itemID]
			s.price = newMinPrice
			s.tiers = { { newMinPrice, s.total or 1 } }
			s.isAggregate = true
			s.ts = (time and time()) or s.ts
		else
			ns.realmDB.ahStock[itemID] = nil
		end
	end
end

local function CancelPendingCommodity(reasonText, dropItemID, newMinPrice)
	if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
		pcall(C_AuctionHouse.CancelCommoditiesPurchase)
	end
	pendingBuy = nil
	if dropItemID then
		ClearStaleSnipeHit(dropItemID, newMinPrice)
	end
	if reasonText and ns.Print then
		ns:Print(reasonText)
	end
	ns:RefreshSnipeUI()
end

local function IsCommodityItem(itemID)
	if C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults then
		local ok, n = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
		if ok and type(n) == "number" and n > 0 then
			return true
		end
	end
	if C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
		local ok, st = pcall(C_AuctionHouse.GetItemCommodityStatus, itemID)
		if ok and st ~= nil then
			if st == Enum.ItemCommodityStatus.Commodity then
				return true
			elseif st == Enum.ItemCommodityStatus.NonCommodity then
				return false
			end
		end
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
		if classID == 0 or classID == 3 or classID == 7 then
			return true
		elseif classID == 2 or classID == 4 or classID == 9 then
			return false
		end
	end
	return true
end

RequestTopSnipeHitDetails = function()
	if activeSnipeBatch or pendingBuy or not IsAuctionHouseOpen() then
		return
	end
	if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery) then
		return
	end
	local hits = ns:GetSnipeHitList()
	local first = hits and hits[1]
	if not (first and first.itemID) then
		return
	end
	local itemID = first.itemID
	if not IsCommodityItem(itemID) then
		return
	end
	local stock = ns.realmDB and ns.realmDB.ahStock and ns.realmDB.ahStock[itemID]
	if stock and not stock.isAggregate and stock.tiers and #stock.tiers > 0 then
		return
	end
	local now = GetTime and GetTime() or 0
	if (now - (lastDetailQueryAt[itemID] or 0)) < 2.0 then
		return
	end
	detailQueryToken = detailQueryToken + 1
	local dTok = detailQueryToken
	if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
		pendingSnipeDetailQueued = itemID
		if C_Timer and C_Timer.After then
			C_Timer.After(3.0, function()
				if detailQueryToken == dTok and pendingSnipeDetailQueued == itemID then
					pendingSnipeDetailQueued = nil
					ns:RefreshSnipeBar()
				end
			end)
		end
		return
	end
	pendingSnipeDetailQueued = nil
	pendingSnipeDetailItemID = itemID
	lastDetailQueryAt[itemID] = now
	local key = C_AuctionHouse.MakeItemKey and C_AuctionHouse.MakeItemKey(itemID) or { itemID = itemID }
	local ok = pcall(C_AuctionHouse.SendSearchQuery, key, {}, false)
	if not ok then
		pendingSnipeDetailItemID = nil
	elseif C_Timer and C_Timer.After then
		C_Timer.After(3.0, function()
			if detailQueryToken == dTok and pendingSnipeDetailItemID == itemID then
				pendingSnipeDetailItemID = nil
				ns:RefreshSnipeBar()
			end
		end)
	end
end

local function ComputeCommodityBuyQty(itemID, maxPrice, hit)
	local money = (GetMoney and GetMoney()) or 0
	local budget, qtyCap, maxSpend, minReserve = ComputeAvailableSnipeBudget(money)
	if C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetCommoditySearchResultInfo then
		local ok, n = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
		if ok and type(n) == "number" and n > 0 then
			local buyQty, spent, liveMin = 0, 0, nil
			local blockedKind = nil
			for i = 1, math.min(n, 200) do
				local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
				local p = info and info.unitPrice
				local q = info and info.quantity
				if p and p > 0 and q and q > 0 then
					if not liveMin or p < liveMin then
						liveMin = p
					end
					if p <= maxPrice then
						local remQty = (qtyCap > 0) and (qtyCap - buyQty) or q
						if remQty <= 0 then
							break
						end
						local canAfford = math.floor((budget - spent) / p)
						if canAfford > 0 then
							local take = math.min(q, canAfford, remQty)
							buyQty = buyQty + take
							spent = spent + take * p
							if take < q or (qtyCap > 0 and buyQty >= qtyCap) then
								break
							end
						elseif buyQty == 0 then
							blockedKind = ClassifyBudgetBlock(money, p, maxSpend, minReserve)
							break
						else
							break
						end
					end
				end
			end
			if buyQty > 0 then
				return buyQty, nil, liveMin
			end
			return 0, blockedKind or "gone", liveMin
		end
	end

	local stock = ns.GetAuctionTiers and ns:GetAuctionTiers(itemID)
	if stock and not stock.isAggregate and stock.tiers and #stock.tiers > 0 then
		local buyQty, spent = 0, 0
		for _, t in ipairs(stock.tiers) do
			if t.price <= maxPrice and (t.qty or 0) > 0 then
				local remQty = (qtyCap > 0) and (qtyCap - buyQty) or t.qty
				if remQty <= 0 then
					break
				end
				local canAfford = math.floor((budget - spent) / t.price)
				if canAfford > 0 then
					local take = math.min(t.qty, canAfford, remQty)
					buyQty = buyQty + take
					spent = spent + take * t.price
					if take < t.qty or (qtyCap > 0 and buyQty >= qtyCap) then
						break
					end
				elseif buyQty == 0 then
					return 0, ClassifyBudgetBlock(money, t.price, maxSpend, minReserve), t.price
				else
					break
				end
			end
		end
		if buyQty > 0 then
			return buyQty, nil, stock.tiers[1] and stock.tiers[1].price
		end
		return 0, "gone", stock.tiers[1] and stock.tiers[1].price
	end

	if hit and hit.bestPrice and hit.bestPrice <= maxPrice then
		if budget < hit.bestPrice then
			return 0, ClassifyBudgetBlock(money, hit.bestPrice, maxSpend, minReserve), hit.bestPrice
		end
		local desired = (hit.totalCheapQty and hit.totalCheapQty > 0) and hit.totalCheapQty or (hit.qty or 1)
		local qty = math.min(desired, math.floor(budget / math.max(1, hit.bestPrice)))
		if qtyCap > 0 then
			qty = math.min(qty, qtyCap)
		end
		if qty > 0 then
			return qty, nil, hit.bestPrice
		end
	end
	return 0, "gone", nil
end

local buyApiDepth = 0
local buyApiBlocked = false

function ns:BuyFirstSnipeHit()
	if not IsAuctionHouseOpen() then
		return
	end
	if pendingBuy and pendingBuy.state == "confirm" then
		local money = (GetMoney and GetMoney()) or 0
		local okSpend, errMsg = ValidateBuyoutSpend(pendingBuy.totalPrice or 0, money)
		if not okSpend then
			CancelPendingCommodity(errMsg, nil)
			return
		end
		if (pendingBuy.unitPrice or 0) > pendingBuy.maxPrice then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_GONE_PRICE"], pendingBuy.label, ns.FormatMoney(pendingBuy.unitPrice), ns.FormatMoney(pendingBuy.maxPrice)), pendingBuy.itemID, pendingBuy.unitPrice)
			return
		end
		if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
			if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
				self:Print(L["SNIPE_BUY_WAIT"])
				return
			end
			buyTokenCounter = buyTokenCounter + 1
			local confirmTok = buyTokenCounter
			pendingBuy.token = confirmTok
			pendingBuy.state = "buying"
			buyApiBlocked = false
			buyApiDepth = buyApiDepth + 1
			C_AuctionHouse.ConfirmCommoditiesPurchase(pendingBuy.itemID, pendingBuy.qty)
			buyApiDepth = buyApiDepth - 1
			if buyApiBlocked then
				CancelPendingCommodity(string.format(L["SNIPE_BUY_FAILED"], pendingBuy.label), pendingBuy.itemID, nil)
			elseif pendingBuy and pendingBuy.token == confirmTok and pendingBuy.state == "buying" then
				self:RefreshSnipeBar()
				if C_Timer and C_Timer.After then
					C_Timer.After(6.0, function()
						if pendingBuy and pendingBuy.token == confirmTok and pendingBuy.state == "buying" then
							CancelPendingCommodity(string.format(L["SNIPE_BUY_TIMEOUT"], pendingBuy.label), nil)
						end
					end)
				end
			end
		end
		return
	end
	if pendingBuy and (pendingBuy.state == "awaiting" or pendingBuy.state == "buying") then
		return
	end

	local hits = self:GetSnipeHitList()
	local first = hits[1]
	if not first then
		return
	end
	local itemID = first.itemID
	local maxPrice = first.maxPrice or 0
	if maxPrice <= 0 then
		return
	end
	local name, _, _, link, _, hex = self:GetItemDisplay(itemID)
	local label = link or ((hex or "|cffffffff") .. (name or ("#" .. itemID)) .. "|r")

	if IsCommodityItem(itemID) and C_AuctionHouse and C_AuctionHouse.StartCommoditiesPurchase then
		if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
			self:Print(L["SNIPE_BUY_WAIT"])
			return
		end
		local qty, errKind, liveMin = ComputeCommodityBuyQty(itemID, maxPrice, first)
		if qty <= 0 then
			local maxSpend, _, minReserve = self:GetSnipeBuyLimits()
			if errKind == "nomoney" then
				self:Print(L["SNIPE_BUY_NOMONEY"])
			elseif errKind == "reserve" then
				self:Print(string.format(L["SNIPE_BUY_RESERVE_CAP"], ns.FormatMoney(minReserve)))
			elseif errKind == "budget" then
				self:Print(string.format(L["SNIPE_BUY_BUDGET_CAP"], ns.FormatMoney(liveMin or maxPrice), ns.FormatMoney(maxSpend)))
			else
				CancelPendingCommodity(string.format(L["SNIPE_BUY_GONE"], label), itemID, liveMin)
			end
			return
		end
		buyTokenCounter = buyTokenCounter + 1
		local tok = buyTokenCounter
		pendingBuy = {
			itemID = itemID,
			qty = qty,
			maxPrice = maxPrice,
			state = "awaiting",
			token = tok,
			label = label,
		}
		-- Важно: вызываем StartCommoditiesPurchase напрямую (без pcall) ДО Disable/RefreshSnipeBar,
		-- чтобы не сбивать активный hardware event клика в WoW 1.60.1 / 12.0.
		buyApiBlocked = false
		buyApiDepth = buyApiDepth + 1
		C_AuctionHouse.StartCommoditiesPurchase(itemID, qty)
		buyApiDepth = buyApiDepth - 1
		if buyApiBlocked then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_FAILED"], label), nil)
			return
		end
		if pendingBuy and pendingBuy.token == tok and pendingBuy.state == "awaiting" then
			self:RefreshSnipeBar()
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(4.0, function()
				if pendingBuy and pendingBuy.token == tok and pendingBuy.state == "awaiting" then
					CancelPendingCommodity(string.format(L["SNIPE_BUY_TIMEOUT"], label), nil)
				end
			end)
		end
	elseif C_AuctionHouse and C_AuctionHouse.MakeItemKey and C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetItemSearchResultInfo and C_AuctionHouse.PlaceBid then
		local key = C_AuctionHouse.MakeItemKey(itemID)
		local n = C_AuctionHouse.GetNumItemSearchResults(key) or 0
		if n == 0 then
			self:SearchSnipeTargetsOnAH(itemID, true)
			self:Print(string.format(L["SNIPE_BUY_LOADING"], label))
			return
		end
		local bestAuction = nil
		for i = 1, n do
			local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
			if info and info.auctionID and info.buyoutAmount and info.buyoutAmount > 0 then
				if not bestAuction or info.buyoutAmount < bestAuction.buyoutAmount then
					bestAuction = info
				end
			end
		end
		if not bestAuction or bestAuction.buyoutAmount > maxPrice then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_GONE"], label), itemID, bestAuction and bestAuction.buyoutAmount)
			return
		end
		local money = (GetMoney and GetMoney()) or 0
		local okSpend, errMsg = ValidateBuyoutSpend(bestAuction.buyoutAmount, money)
		if not okSpend then
			self:Print(errMsg)
			return
		end
		pendingSnipeBid = {
			itemID = itemID,
			label = label,
			amount = bestAuction.buyoutAmount,
			maxPrice = maxPrice,
			moneyBefore = money,
			ts = GetTime and GetTime() or 0,
		}
		buyApiBlocked = false
		buyApiDepth = buyApiDepth + 1
		C_AuctionHouse.PlaceBid(bestAuction.auctionID, bestAuction.buyoutAmount)
		buyApiDepth = buyApiDepth - 1
		if buyApiBlocked then
			pendingSnipeBid = nil
			CancelPendingCommodity(string.format(L["SNIPE_BUY_FAILED"], label), itemID, nil)
		end
	end
end

function ns:OnExternalCommodityPurchase()
	if pendingBuy and pendingBuy.state == "confirm" then
		pendingBuy = nil
		self:RefreshSnipeUI()
	end
end

function ns:IsSnipePurchaseActive()
	return (pendingBuy ~= nil and pendingBuy.state ~= "confirm") or buyApiDepth > 0
end

function ns:RefreshSnipeBar()
	local ah = GetActiveAuctionFrame()
	local enabled = self.IsModuleEnabled and self:IsModuleEnabled("profit")
	local targets = self:GetActiveSnipeTargetList()
	local hits = self:GetSnipeHitList()
	if not (ah and enabled and (#targets > 0 or pendingBuy)) then
		if snipeBar then
			snipeBar:Hide()
		end
		return
	end

	HookAuctionFrameShow(ah)

	if not snipeBar then
		snipeBar = CreateFrame("Frame", "TradeFlowSnipeBar", ah, "BackdropTemplate")
		snipeBar:SetHeight(38)
		snipeBar:SetFrameStrata("DIALOG")
		snipeBar:SetToplevel(true)
		snipeBar:SetClampedToScreen(true)
		snipeBar:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		snipeBar:SetBackdropColor(0.08, 0.07, 0.05, 0.96)

		snipeBar.label = snipeBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		snipeBar.label:SetPoint("LEFT", 10, 0)
		snipeBar.label:SetPoint("RIGHT", -318, 0)
		snipeBar.label:SetJustifyH("LEFT")
		snipeBar.label:SetWordWrap(false)

		snipeBar.settingsBtn = CreateFrame("Button", nil, snipeBar, "UIPanelButtonTemplate")
		snipeBar.settingsBtn:SetSize(72, 24)
		snipeBar.settingsBtn:SetPoint("RIGHT", -8, 0)
		snipeBar.settingsBtn:SetScript("OnClick", function(self)
			if ns.ToggleSniperSettingsFrame then
				ns:ToggleSniperSettingsFrame(self, "ah")
			end
		end)
		snipeBar.settingsBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["SNIPE_SETTINGS_TITLE"], 1, 0.82, 0)
			GameTooltip:AddLine(L["SNIPE_SETTINGS_TIP"], 0.85, 0.85, 0.85, true)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(string.format(L["SNIPE_LIMIT_SUMMARY_FMT"], ns:FormatSnipeLimitsSummary()), 0.4, 0.9, 1, true)
			GameTooltip:Show()
		end)
		snipeBar.settingsBtn:SetScript("OnLeave", GameTooltip_Hide)

		snipeBar.autoScanCb = CreateFrame("CheckButton", nil, snipeBar, "UICheckButtonTemplate")
		snipeBar.autoScanCb:SetSize(22, 22)
		snipeBar.autoScanCb:SetPoint("RIGHT", snipeBar.settingsBtn, "LEFT", -48, 0)
		snipeBar.autoScanCb.text = snipeBar.autoScanCb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		snipeBar.autoScanCb.text:SetPoint("LEFT", snipeBar.autoScanCb, "RIGHT", 2, 0)
		snipeBar.autoScanCb.text:SetText(L["SNIPE_AUTOSCAN_SHORT"])
		snipeBar.autoScanCb:SetHitRectInsets(0, -44, 0, 0)
		snipeBar.autoScanCb:SetScript("OnClick", function(self)
			ns:SetSnipeAutoScanEnabled(self:GetChecked() and true or false)
		end)
		snipeBar.autoScanCb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["SNIPE_AUTOSCAN_CB"], 1, 0.82, 0)
			GameTooltip:AddLine(string.format(L["SNIPE_AUTOSCAN_TIP"], ns:GetSnipeAutoScanInterval()), 0.85, 0.85, 0.85, true)
			GameTooltip:Show()
		end)
		snipeBar.autoScanCb:SetScript("OnLeave", GameTooltip_Hide)

		snipeBar.scanBtn = CreateFrame("Button", nil, snipeBar, "UIPanelButtonTemplate")
		snipeBar.scanBtn:SetSize(104, 24)
		snipeBar.scanBtn:SetPoint("RIGHT", snipeBar.autoScanCb, "LEFT", -8, 0)
		snipeBar.scanBtn:SetScript("OnClick", function()
			ns:SearchSnipeTargetsOnAH()
		end)
		snipeBar.scanBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["SNIPE_SCAN_BTN"], 1, 0.82, 0)
			GameTooltip:AddLine(L["SNIPE_SCAN_TIP"], 0.85, 0.85, 0.85, true)
			GameTooltip:Show()
		end)
		snipeBar.scanBtn:SetScript("OnLeave", GameTooltip_Hide)

		snipeBar.openBtn = CreateFrame("Button", nil, snipeBar, "UIPanelButtonTemplate")
		snipeBar.openBtn:SetSize(98, 24)
		snipeBar.openBtn:SetPoint("RIGHT", snipeBar.scanBtn, "LEFT", -6, 0)
		snipeBar.openBtn:SetScript("OnClick", function()
			local hits = ns:GetSnipeHitList()
			if #hits > 0 then
				ns:SearchSnipeTargetsOnAH("hits")
			end
		end)
		snipeBar.openBtn:SetScript("OnEnter", function(self)
			local hits = ns:GetSnipeHitList()
			if #hits == 0 then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["SNIPE_HITS_HEADER"], 0.25, 1, 0.25)
			for _, h in ipairs(hits) do
				local name, _, _, _, _, hex = ns:GetItemDisplay(h.itemID)
				GameTooltip:AddDoubleLine(
					string.format("%s%s|r %s (-%d%%)", hex or "|cffffffff", name, ns.FormatSnipeHitQty(h), h.discountPct or 0),
					string.format("%s (<= %s)", ns.FormatMoney(h.bestPrice), ns.FormatMoney(h.maxPrice)),
					1, 1, 1, 0.4, 1, 0.4
				)
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(L["SNIPE_FIND_HIT_TIP"], 0.75, 0.9, 1, true)
			GameTooltip:Show()
		end)
		snipeBar.openBtn:SetScript("OnLeave", GameTooltip_Hide)

		snipeBar.buyBtn = CreateFrame("Button", "TradeFlowSnipeBuyBtn", snipeBar, "UIPanelButtonTemplate")
		snipeBar.buyBtn:SetSize(134, 24)
		snipeBar.buyBtn:SetPoint("RIGHT", snipeBar.openBtn, "LEFT", -6, 0)
		snipeBar.buyBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		snipeBar.buyBtn:SetScript("OnClick", function(_, button)
			if button == "RightButton" then
				if pendingBuy then
					CancelPendingCommodity(nil, nil)
				end
				return
			end
			ns:BuyFirstSnipeHit()
		end)
		if AuctionHouseFrame and AuctionHouseFrame.BuyDialog and not hookedAuctionFrames[AuctionHouseFrame.BuyDialog] then
			hookedAuctionFrames[AuctionHouseFrame.BuyDialog] = true
			pcall(AuctionHouseFrame.BuyDialog.HookScript, AuctionHouseFrame.BuyDialog, "OnHide", function()
				if pendingBuy and pendingBuy.state == "confirm" then
					if C_Timer and C_Timer.After then
						C_Timer.After(0.05, function()
							if pendingBuy and pendingBuy.state == "confirm" then
								CancelPendingCommodity(nil, nil)
							end
						end)
					else
						CancelPendingCommodity(nil, nil)
					end
				end
			end)
		end
		snipeBar.buyBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if pendingBuy and pendingBuy.state == "confirm" then
				GameTooltip:SetText(string.format(L["SNIPE_BUY_CONFIRM"], pendingBuy.qty), 0.25, 1, 0.25)
				GameTooltip:AddLine(string.format(
					L["SNIPE_BUY_CONFIRM_TIP"],
					pendingBuy.qty,
					ns.FormatMoney(pendingBuy.unitPrice or 0),
					ns.FormatMoney(pendingBuy.totalPrice or 0)
				), 0.9, 0.9, 0.9, true)
			else
				GameTooltip:SetText(string.format(L["SNIPE_BUY_BTN"], 1):gsub("%s*x%d+", ""), 1, 0.82, 0)
				GameTooltip:AddLine(L["SNIPE_BUY_TIP"], 0.85, 0.85, 0.85, true)
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(string.format(L["SNIPE_LIMIT_SUMMARY_FMT"], ns:FormatSnipeLimitsSummary()), 0.4, 0.9, 1, true)
			end
			GameTooltip:Show()
		end)
		snipeBar.buyBtn:SetScript("OnLeave", GameTooltip_Hide)
	end

	if snipeBar:GetParent() ~= ah then
		snipeBar:SetParent(ah)
	end
	snipeBar:ClearAllPoints()
	local ahScale = (ah.GetEffectiveScale and ah:GetEffectiveScale()) or 1
	local ahBottom = (ah.GetBottom and ah:GetBottom() or 0) * ahScale
	-- Нижние вкладки AH (Blizzard + Auctionator) выступают на ~32px ниже рамки AuctionHouseFrame
	local bottomOffset = 32
	if ahBottom > 0 and (ahBottom - (bottomOffset + 42) * ahScale) < 0 then
		snipeBar:SetPoint("BOTTOMLEFT", ah, "TOPLEFT", 0, 2)
		snipeBar:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", 0, 2)
		snipeBar._anchorPos = "top"
	else
		snipeBar:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 0, -bottomOffset)
		snipeBar:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", 0, -bottomOffset)
		snipeBar._anchorPos = "bottom"
	end

	snipeBar.settingsBtn:SetText(L["SNIPE_SETTINGS_BAR_BTN"])
	if snipeBar.autoScanCb then
		snipeBar.autoScanCb:SetChecked(self.db and self.db.options and self.db.options.snipeAutoScan == true)
		snipeBar.autoScanCb.text:SetText(L["SNIPE_AUTOSCAN_SHORT"])
	end
	if activeSnipeBatch then
		snipeBar.scanBtn:SetText(L["SNIPE_SCANNING_BTN"])
		snipeBar.scanBtn:SetEnabled(false)
	else
		snipeBar.scanBtn:SetText(L["SNIPE_SCAN_BTN"])
		snipeBar.scanBtn:SetEnabled(true)
	end

	snipeBar.openBtn:SetText(string.format(L["SNIPE_FIND_HIT_BTN"], #hits))
	if #hits > 0 or pendingBuy then
		local first = hits[1]
		if pendingBuy and pendingBuy.state == "awaiting" then
			snipeBar.buyBtn:SetText(L["SNIPE_BUY_WAIT"])
			snipeBar.buyBtn:SetEnabled(false)
		elseif pendingBuy and pendingBuy.state == "confirm" then
			snipeBar.buyBtn:SetText(string.format(L["SNIPE_BUY_CONFIRM"], pendingBuy.qty or 1))
			snipeBar.buyBtn:SetEnabled(true)
		elseif pendingBuy and pendingBuy.state == "buying" then
			snipeBar.buyBtn:SetText(L["SNIPE_BUY_WAIT"])
			snipeBar.buyBtn:SetEnabled(false)
		elseif first and (pendingSnipeDetailItemID == first.itemID or pendingSnipeDetailQueued == first.itemID) then
			snipeBar.buyBtn:SetText(L["SNIPE_BUY_WAIT"])
			snipeBar.buyBtn:SetEnabled(false)
		elseif first then
			local qty = ComputeCommodityBuyQty(first.itemID, first.maxPrice or 0, first)
			if qty <= 0 then
				local _, qtyCap = self:GetSnipeBuyLimits()
				qty = (first.totalCheapQty and first.totalCheapQty > 0) and first.totalCheapQty or (first.qty or 1)
				if qtyCap > 0 then
					qty = math.min(qty, qtyCap)
				end
			end
			snipeBar.buyBtn:SetText(string.format(L["SNIPE_BUY_BTN"], qty))
			snipeBar.buyBtn:SetEnabled(true)
		end
		snipeBar.buyBtn:Show()
		snipeBar.label:ClearAllPoints()
		snipeBar.label:SetPoint("LEFT", 10, 0)
		snipeBar.label:SetPoint("RIGHT", snipeBar.buyBtn, "LEFT", -8, 0)
	else
		snipeBar.buyBtn:Hide()
		snipeBar.label:ClearAllPoints()
		snipeBar.label:SetPoint("LEFT", 10, 0)
		snipeBar.label:SetPoint("RIGHT", snipeBar.scanBtn, "LEFT", -8, 0)
	end
	if #hits > 0 then
		local first = hits[1]
		local name = self:GetItemDisplay(first.itemID)
		snipeBar:SetBackdropBorderColor(0.25, 0.90, 0.35, 1)
		snipeBar.label:SetText(string.format(
			L["SNIPE_BAR_HIT"],
			#hits,
			name,
			ns.FormatSnipeHitQty(first),
			ns.FormatMoney(first.bestPrice),
			first.discountPct or 0
		))
		snipeBar.openBtn:Show()
	else
		snipeBar:SetBackdropBorderColor(0.85, 0.65, 0.20, 1)
		snipeBar.label:SetText(string.format(L["SNIPE_BAR_IDLE"], #targets))
		snipeBar.openBtn:Hide()
	end
	snipeBar:Show()
end

local function ApplySnipeUIRefresh()
	ns:RefreshSnipeBar()
	if ns.modules and ns.modules.byId and ns.modules.byId["profit"] then
		local mod = ns.modules.byId["profit"]
		if ns:IsModuleEnabled("profit") and mod.view and mod.view:IsVisible() and mod.OnRefresh then
			mod:OnRefresh()
		end
	end
end

function ns:RefreshSnipeUI()
	if pendingUiRefresh then
		return
	end
	if C_Timer and C_Timer.After then
		pendingUiRefresh = true
		C_Timer.After(0.05, function()
			pendingUiRefresh = false
			ApplySnipeUIRefresh()
		end)
	else
		ApplySnipeUIRefresh()
	end
end

function ns:HideSniperSettingsFrame(onlyAnchorKind)
	if sniperSettingsFrame and sniperSettingsFrame:IsShown() then
		if not onlyAnchorKind or sniperSettingsAnchorKind == onlyAnchorKind then
			sniperSettingsFrame:Hide()
		end
	end
end

function ns:ResetSniperSettingsFrame()
	if sniperSettingsFrame then
		sniperSettingsFrame:Hide()
		sniperSettingsFrame = nil
		sniperSettingsAnchorKind = nil
	end
end

local function FillSniperSettingsInputs(sf)
	local maxSpend, maxQty, minReserve = ns:GetSnipeBuyLimits()
	sf.maxSpendBox:SetText((maxSpend > 0) and ns.FormatMoneyPlain(maxSpend) or "0")
	sf.minReserveBox:SetText((minReserve > 0) and ns.FormatMoneyPlain(minReserve) or "0")
	sf.maxQtyBox:SetText(tostring(maxQty or 0))
	sf.autoScanIntervalBox:SetText(tostring(ns:GetSnipeAutoScanInterval()))
	sf.discountPctBox:SetText(tostring(ns:GetSnipeDiscountPct()))
	sf.cbAutoScan:SetChecked(ns.db and ns.db.options and ns.db.options.snipeAutoScan == true)
	sf.cbAutoReprice:SetChecked(not (ns.db and ns.db.options and ns.db.options.snipeAutoReprice == false))
end

function ns:ToggleSniperSettingsFrame(anchorBtn, anchorKind)
	if not sniperSettingsFrame then
		local sf = CreateFrame("Frame", "TradeFlowSniperSettingsFrame", UIParent, "BackdropTemplate")
		sf:SetSize(350, 304)
		sf:SetFrameStrata("DIALOG")
		sf:SetToplevel(true)
		sf:SetClampedToScreen(true)
		sf:SetMovable(true)
		sf:EnableMouse(true)
		sf:RegisterForDrag("LeftButton")
		sf:SetScript("OnDragStart", sf.StartMoving)
		sf:SetScript("OnDragStop", sf.StopMovingOrSizing)
		if sf.SetBackdrop then
			sf:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8X8",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			sf:SetBackdropColor(0.07, 0.065, 0.055, 0.98)
			sf:SetBackdropBorderColor(0.55, 0.45, 0.25, 0.9)
		end
		sf:Hide()

		local title = sf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 12, -10)
		title:SetText("|cffffd100" .. L["SNIPE_SETTINGS_TITLE"] .. "|r")

		local close = CreateFrame("Button", nil, sf, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
		close:SetScript("OnClick", function() sf:Hide() end)

		local function MakeLimitRow(labelText, tipTitle, tipText, y)
			local box = CreateFrame("EditBox", nil, sf, "InputBoxTemplate")
			box:SetSize(106, 20)
			box:SetPoint("TOPRIGHT", -14, y + 3)
			box:SetAutoFocus(false)
			box.placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			box.placeholder:SetPoint("LEFT", 4, 0)
			box.placeholder:SetText(L["SNIPE_LIMIT_ZERO_PH"])
			box:SetScript("OnTextChanged", function(self)
				self.placeholder:SetShown((self:GetText() or "") == "")
			end)
			box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
			box:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(tipTitle, 1, 0.82, 0)
				GameTooltip:AddLine(tipText, 0.85, 0.85, 0.85, true)
				GameTooltip:Show()
			end)
			box:SetScript("OnLeave", GameTooltip_Hide)

			local lbl = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			lbl:SetPoint("TOPLEFT", 12, y)
			lbl:SetPoint("RIGHT", box, "LEFT", -8, 0)
			lbl:SetJustifyH("LEFT")
			lbl:SetText(labelText)
			return box
		end

		sf.maxSpendBox = MakeLimitRow(L["SNIPE_LIMIT_MAX_SPEND"], L["SNIPE_LIMIT_MAX_SPEND"], L["SNIPE_LIMIT_MAX_SPEND_TIP"], -38)
		sf.minReserveBox = MakeLimitRow(L["SNIPE_LIMIT_MIN_RESERVE"], L["SNIPE_LIMIT_MIN_RESERVE"], L["SNIPE_LIMIT_MIN_RESERVE_TIP"], -70)
		sf.maxQtyBox = MakeLimitRow(L["SNIPE_LIMIT_MAX_QTY"], L["SNIPE_LIMIT_MAX_QTY"], L["SNIPE_LIMIT_MAX_QTY_TIP"], -102)
		sf.autoScanIntervalBox = MakeLimitRow(L["SNIPE_AUTOSCAN_INTERVAL"], L["SNIPE_AUTOSCAN_INTERVAL"], L["SNIPE_AUTOSCAN_INTERVAL_TIP"], -134)
		sf.autoScanIntervalBox.placeholder:SetText("1 - 15")
		sf.discountPctBox = MakeLimitRow(L["SNIPE_DISCOUNT_PCT"], L["SNIPE_DISCOUNT_PCT"], L["SNIPE_DISCOUNT_PCT_TIP"], -166)
		sf.discountPctBox.placeholder:SetText("5 - 80")

		local cbAutoScan = CreateFrame("CheckButton", nil, sf, "UICheckButtonTemplate")
		cbAutoScan:SetSize(22, 22)
		cbAutoScan:SetPoint("TOPLEFT", 10, -194)
		cbAutoScan.text = cbAutoScan:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cbAutoScan.text:SetPoint("LEFT", cbAutoScan, "RIGHT", 4, 0)
		cbAutoScan.text:SetText(L["SNIPE_AUTOSCAN_CB"])
		cbAutoScan:SetHitRectInsets(0, -240, 0, 0)
		cbAutoScan:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["SNIPE_AUTOSCAN_CB"], 1, 0.82, 0)
			GameTooltip:AddLine(string.format(L["SNIPE_AUTOSCAN_TIP"], ns:GetSnipeAutoScanInterval()), 0.85, 0.85, 0.85, true)
			GameTooltip:Show()
		end)
		cbAutoScan:SetScript("OnLeave", GameTooltip_Hide)
		sf.cbAutoScan = cbAutoScan

		local cbAutoReprice = CreateFrame("CheckButton", nil, sf, "UICheckButtonTemplate")
		cbAutoReprice:SetSize(22, 22)
		cbAutoReprice:SetPoint("TOPLEFT", 10, -220)
		cbAutoReprice.text = cbAutoReprice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cbAutoReprice.text:SetPoint("LEFT", cbAutoReprice, "RIGHT", 4, 0)
		cbAutoReprice.text:SetText(L["SNIPE_AUTOREPRICE_CB"])
		cbAutoReprice:SetHitRectInsets(0, -240, 0, 0)
		cbAutoReprice:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["SNIPE_AUTOREPRICE_CB"], 1, 0.82, 0)
			GameTooltip:AddLine(string.format(L["SNIPE_AUTOREPRICE_TIP"], ns:GetSnipeDiscountPct()), 0.85, 0.85, 0.85, true)
			GameTooltip:Show()
		end)
		cbAutoReprice:SetScript("OnLeave", GameTooltip_Hide)
		sf.cbAutoReprice = cbAutoReprice

		local hint = sf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("TOPLEFT", 12, -248)
		hint:SetPoint("RIGHT", -12, 0)
		hint:SetJustifyH("LEFT")
		hint:SetText(L["SNIPE_LIMIT_HINT"])

		local function SaveLimits()
			local maxSpend = ParseOptionalMoneyLimit(sf.maxSpendBox:GetText())
			if maxSpend == nil then
				ns:Print(L["SNIPE_ADD_BAD_PRICE"])
				return
			end
			local minReserve = ParseOptionalMoneyLimit(sf.minReserveBox:GetText())
			if minReserve == nil then
				ns:Print(L["SNIPE_ADD_BAD_PRICE"])
				return
			end
			local maxQty = ParseOptionalQtyLimit(sf.maxQtyBox:GetText())
			if maxQty == nil then
				ns:Print(L["SNIPE_LIMIT_BAD_QTY"])
				return
			end
			local interval = ParseAutoScanInterval(sf.autoScanIntervalBox:GetText())
			if interval == nil then
				ns:Print(L["SNIPE_AUTOSCAN_BAD_INTERVAL"])
				return
			end
			local discPct = ParseSnipeDiscountPct(sf.discountPctBox:GetText())
			if discPct == nil then
				ns:Print(L["SNIPE_DISCOUNT_BAD"])
				return
			end
			local autoOn = cbAutoScan:GetChecked() and true or false
			local autoReprice = cbAutoReprice:GetChecked() and true or false
			if ns.db and ns.db.options then
				ns.db.options.snipeMaxSpend = maxSpend
				ns.db.options.snipeMinReserve = minReserve
				ns.db.options.snipeMaxQty = maxQty
				ns.db.options.snipeAutoScanInterval = interval
				ns.db.options.snipeDiscountPct = discPct
				ns.db.options.snipeAutoReprice = autoReprice
				ns.db.options.snipeAutoScan = autoOn
			end
			if autoOn then
				ScheduleNextSnipeAutoScan()
			else
				StopSnipeAutoScan()
			end
			sf:Hide()
			ns:RefreshSnipeUI()
			ns:Print(string.format(L["SNIPE_LIMIT_SAVED"], ns:FormatSnipeLimitsSummary()))
		end

		sf.maxSpendBox:SetScript("OnTabPressed", function() sf.minReserveBox:SetFocus() end)
		sf.minReserveBox:SetScript("OnTabPressed", function() sf.maxQtyBox:SetFocus() end)
		sf.maxQtyBox:SetScript("OnTabPressed", function() sf.autoScanIntervalBox:SetFocus() end)
		sf.autoScanIntervalBox:SetScript("OnTabPressed", function() sf.discountPctBox:SetFocus() end)
		sf.discountPctBox:SetScript("OnTabPressed", function() sf.maxSpendBox:SetFocus() end)
		sf.maxSpendBox:SetScript("OnEnterPressed", SaveLimits)
		sf.minReserveBox:SetScript("OnEnterPressed", SaveLimits)
		sf.maxQtyBox:SetScript("OnEnterPressed", SaveLimits)
		sf.autoScanIntervalBox:SetScript("OnEnterPressed", SaveLimits)
		sf.discountPctBox:SetScript("OnEnterPressed", SaveLimits)

		local saveBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
		saveBtn:SetSize(158, 22)
		saveBtn:SetPoint("BOTTOMLEFT", 12, 10)
		saveBtn:SetText(L["SNIPE_LIMIT_SAVE"])
		saveBtn:SetScript("OnClick", SaveLimits)

		local resetBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
		resetBtn:SetSize(158, 22)
		resetBtn:SetPoint("BOTTOMRIGHT", -12, 10)
		resetBtn:SetText(L["SNIPE_LIMIT_RESET"])
		resetBtn:SetScript("OnClick", function()
			if ns.db and ns.db.options then
				ns.db.options.snipeMaxSpend = DEFAULT_SNIPE_MAX_SPEND
				ns.db.options.snipeMinReserve = DEFAULT_SNIPE_MIN_RESERVE
				ns.db.options.snipeMaxQty = DEFAULT_SNIPE_MAX_QTY
				ns.db.options.snipeAutoScanInterval = DEFAULT_SNIPE_AUTOSCAN_INTERVAL
				ns.db.options.snipeDiscountPct = DEFAULT_SNIPE_DISCOUNT_PCT
				ns.db.options.snipeAutoReprice = true
			end
			if ns.db and ns.db.options and ns.db.options.snipeAutoScan == true then
				ScheduleNextSnipeAutoScan()
			end
			FillSniperSettingsInputs(sf)
			ns:RefreshSnipeUI()
			ns:Print(string.format(L["SNIPE_LIMIT_SAVED"], ns:FormatSnipeLimitsSummary()))
		end)

		if not sniperSettingsSpecialRegistered then
			sniperSettingsSpecialRegistered = true
			tinsert(UISpecialFrames, "TradeFlowSniperSettingsFrame")
		end
		sniperSettingsFrame = sf
	end

	local sf = sniperSettingsFrame
	local newKind = anchorKind or ((anchorBtn and snipeBar and anchorBtn == snipeBar.settingsBtn) and "ah" or "tab")
	if sf:IsShown() and sniperSettingsAnchorKind == newKind then
		sf:Hide()
		return
	end
	sniperSettingsAnchorKind = newKind
	sf:ClearAllPoints()
	if anchorBtn and anchorBtn.IsVisible and anchorBtn:IsVisible() then
		if newKind == "ah" and snipeBar and snipeBar._anchorPos == "bottom" then
			sf:SetPoint("BOTTOMRIGHT", anchorBtn, "TOPRIGHT", 0, 4)
		else
			sf:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -4)
		end
	else
		sf:SetPoint("CENTER")
	end
	FillSniperSettingsInputs(sf)
	sf:Show()
end

local snipeEventFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_CLOSED",
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
	"AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
	"AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"AUCTION_ITEM_LIST_UPDATE",
	"COMMODITY_PRICE_UPDATED",
	"COMMODITY_PRICE_UNAVAILABLE",
	"COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED",
	"PLAYER_MONEY",
	"ADDON_ACTION_BLOCKED",
}) do
	pcall(snipeEventFrame.RegisterEvent, snipeEventFrame, ev)
end
snipeEventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_ACTION_BLOCKED" then
		if buyApiDepth > 0 and arg1 == "TradeFlow" then
			buyApiBlocked = true
		end
		return
	end
	if not (ns.IsModuleEnabled and ns:IsModuleEnabled("profit")) then
		if snipeBar then
			snipeBar:Hide()
		end
		return
	end
	if event == "AUCTION_HOUSE_SHOW" then
		HookAuctionFrameShow(AuctionHouseFrame)
		HookAuctionFrameShow(AuctionFrame)
		local targets = ns:GetActiveSnipeTargetList()
		for _, t in ipairs(targets) do
			ns:EvaluateSnipeItem(t.itemID, true)
		end
		ns:SyncSnipeShoppingList(true)
		ns:RefreshSnipeBar()
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function() ns:RefreshSnipeBar() end)
			C_Timer.After(0.15, function() ns:RefreshSnipeBar() end)
			if #targets > 0 and ns.db and ns.db.options and ns.db.options.snipeAutoScan == true then
				local tNow = GetTime and GetTime() or 0
				if C_AuctionHouse and C_AuctionHouse.SearchForItemKeys then
					local interval = ns:GetSnipeAutoScanInterval()
					local minOpenCd = math.min(5, interval)
					local wait = (tNow - lastAutoScanAt >= minOpenCd) and 0.45 or math.max(0.45, minOpenCd - (tNow - lastAutoScanAt))
					ScheduleNextSnipeAutoScan(wait)
				elseif (tNow - lastAutoScanAt) >= 30 then
					C_Timer.After(0.45, function()
						local cbNow = GetTime and GetTime() or 0
						if IsAuctionHouseOpen() and ns.IsModuleEnabled and ns:IsModuleEnabled("profit") and (cbNow - lastAutoScanAt) >= 30 then
							lastAutoScanAt = cbNow
							ns:SearchSnipeTargetsOnAH()
						end
					end)
				end
			end
		end
	elseif event == "COMMODITY_PRICE_UPDATED" then
		if pendingBuy and pendingBuy.state == "awaiting" then
			local unitP = tonumber(arg1)
			local totalP = tonumber(arg2)
			local effUnit = (unitP and pendingBuy.qty > 0 and totalP) and math.ceil(totalP / pendingBuy.qty) or unitP
			if not unitP or unitP <= 0 or unitP > pendingBuy.maxPrice or (effUnit and effUnit > pendingBuy.maxPrice) then
				CancelPendingCommodity(
					string.format(L["SNIPE_BUY_GONE_PRICE"], pendingBuy.label, ns.FormatMoney(unitP or effUnit or 0), ns.FormatMoney(pendingBuy.maxPrice)),
					pendingBuy.itemID,
					unitP or effUnit
				)
			else
				local money = (GetMoney and GetMoney()) or 0
				local calcTotal = totalP or (unitP * pendingBuy.qty)
				local okSpend, errMsg = ValidateBuyoutSpend(calcTotal, money)
				if not okSpend then
					CancelPendingCommodity(errMsg, nil)
				else
					local confirmTok = pendingBuy.token
					pendingBuy.state = "confirm"
					pendingBuy.unitPrice = unitP
					pendingBuy.totalPrice = calcTotal
					ns:RefreshSnipeBar()
					if C_Timer and C_Timer.After then
						C_Timer.After(20.0, function()
							if pendingBuy and pendingBuy.token == confirmTok and pendingBuy.state == "confirm" then
								CancelPendingCommodity(nil, nil)
							end
						end)
					end
				end
			end
		end
	elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
		if pendingBuy and pendingBuy.state == "awaiting" then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_GONE"], pendingBuy.label), pendingBuy.itemID, nil)
		end
	elseif event == "COMMODITY_PURCHASE_FAILED" then
		if pendingBuy and pendingBuy.state == "buying" then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_FAILED"], pendingBuy.label), pendingBuy.itemID, nil)
		end
	elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
		if pendingBuy and pendingBuy.state == "buying" then
			local bought = pendingBuy
			pendingBuy = nil
			local totalSpent = bought.totalPrice or ((bought.unitPrice or 0) * bought.qty)
			ns:Print(string.format(L["SNIPE_BUY_DONE"], bought.label, bought.qty, ns.FormatMoney(totalSpent), ns.FormatMoney(bought.maxPrice)))
			if ns.RecordTradeFlowPurchase then
				ns:RecordTradeFlowPurchase("snipe_buy", bought.itemID, bought.qty, totalSpent)
			end
			ClearStaleSnipeHit(bought.itemID, nil)
			ns:RefreshSnipeUI()
		end
	elseif event == "PLAYER_MONEY" then
		if pendingSnipeBid then
			local b = pendingSnipeBid
			local now = GetTime and GetTime() or 0
			if (now - (b.ts or 0)) <= 2.5 then
				local curM = (GetMoney and GetMoney()) or 0
				if (b.moneyBefore - curM) == b.amount then
					pendingSnipeBid = nil
					ns:Print(string.format(L["SNIPE_BUY_DONE"], b.label, 1, ns.FormatMoney(b.amount), ns.FormatMoney(b.maxPrice)))
					if ns.RecordTradeFlowPurchase then
						ns:RecordTradeFlowPurchase("snipe_buy", b.itemID, 1, b.amount)
					end
					ClearStaleSnipeHit(b.itemID, nil)
					ns:RefreshSnipeUI()
				end
			else
				pendingSnipeBid = nil
			end
		end
	elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
		if activeSnipeBatch then
			if activeSnipeBatch.pendingMore and C_AuctionHouse and C_AuctionHouse.RequestMoreBrowseResults then
				activeSnipeBatch.pendingMore = false
				pcall(C_AuctionHouse.RequestMoreBrowseResults)
			elseif activeSnipeBatch.waitingThrottle then
				SendNextSnipeBatchChunk()
			end
		elseif pendingSnipeDetailQueued then
			pendingSnipeDetailQueued = nil
			if RequestTopSnipeHitDetails then
				RequestTopSnipeHitDetails()
			end
			if not pendingSnipeDetailItemID and not pendingSnipeDetailQueued then
				ns:RefreshSnipeBar()
			end
		end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		if activeSnipeBatch and activeSnipeBatch.waitingResults then
			HandleSnipeBatchResults(C_AuctionHouse and C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults(), false)
		else
			lastExternalAhActivityAt = GetTime and GetTime() or lastExternalAhActivityAt
		end
		if next(ns:GetSnipeTargets()) ~= nil then
			ns:RefreshSnipeUI()
		end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		if activeSnipeBatch and activeSnipeBatch.waitingResults then
			HandleSnipeBatchResults(arg1, true)
		else
			lastExternalAhActivityAt = GetTime and GetTime() or lastExternalAhActivityAt
		end
		if next(ns:GetSnipeTargets()) ~= nil then
			ns:RefreshSnipeUI()
		end
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "AUCTION_ITEM_LIST_UPDATE" then
		local isOwnDetail = (event == "COMMODITY_SEARCH_RESULTS_UPDATED" and pendingSnipeDetailItemID and tonumber(arg1) == pendingSnipeDetailItemID)
		if isOwnDetail then
			pendingSnipeDetailItemID = nil
		elseif not pendingBuy then
			lastExternalAhActivityAt = GetTime and GetTime() or lastExternalAhActivityAt
		end
		if next(ns:GetSnipeTargets()) ~= nil then
			ns:RefreshSnipeUI()
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		StopSnipeAutoScan()
		CancelSnipeBatch(true)
		pendingSnipeDetailItemID = nil
		pendingSnipeDetailQueued = nil
		pendingSnipeBid = nil
		if pendingBuy then
			CancelPendingCommodity(nil, nil)
		end
		if snipeBar then
			snipeBar:Hide()
		end
		ns:HideSniperSettingsFrame("ah")
	elseif next(ns:GetSnipeTargets()) ~= nil then
		ns:RefreshSnipeUI()
	end
end)
