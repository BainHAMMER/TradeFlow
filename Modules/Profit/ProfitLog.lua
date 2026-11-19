local _, ns = ...

-------------------------------------------------------------------------------
-- Журнал заработка (режимы «Крафт» и «Касса») + трекинг реальных покупок/продаж
-------------------------------------------------------------------------------
local MAX_LOG_ENTRIES = 200
local MAX_LOT_ENTRIES = 120
local MAX_CRAFTED_TRACK = 200
local LOT_MAX_AGE = 7 * 86400
local COALESCE_SECONDS = 30

ns._trackedAhBuyItems = ns._trackedAhBuyItems or {}

local consumedReagentSet = nil
local disenchantNameMap = nil
local soldSubjectPattern = nil
local ahHooksInstalled = false
local lastSnipeRec = nil
local lastDisenchantAt = 0
local pendingAhComm = nil
local pendingAhBid = nil
local lastViewedAhItemID = nil
local merchantMoney = 0
local merchantBagSnap = nil
local mailMoney = 0
local mailSellerSnap = nil
local pendingMailMoney = { amount = 0, ts = 0 }
local pendingMailItems = {}

local function HasAuctionator()
	local api = _G.Auctionator and Auctionator.API and Auctionator.API.v1
	return api ~= nil
end

function ns:HasAuctionatorForLog()
	return HasAuctionator()
end

local function EnsureCraftLogDB()
	if not ns.realmDB then
		return {}
	end
	ns.realmDB.profitLog = ns.realmDB.profitLog or {}
	return ns.realmDB.profitLog
end

local function EnsureCashflowLogDB()
	if not ns.realmDB then
		return {}
	end
	ns.realmDB.cashflowLog = ns.realmDB.cashflowLog or {}
	return ns.realmDB.cashflowLog
end

local function EnsurePurchaseLotsDB()
	if not ns.realmDB then
		return {}
	end
	ns.realmDB.purchaseLots = ns.realmDB.purchaseLots or {}
	return ns.realmDB.purchaseLots
end

local function EnsureCraftedItemsDB()
	if not ns.realmDB then
		return {}, {}
	end
	ns.realmDB.craftedItems = ns.realmDB.craftedItems or {}
	ns.realmDB.craftedItemNames = ns.realmDB.craftedItemNames or {}
	return ns.realmDB.craftedItems, ns.realmDB.craftedItemNames
end

local function PrunePurchaseLots(lots, now)
	local count = 0
	for itemID, lot in pairs(lots) do
		if type(lot) ~= "table" or (lot.qty or 0) <= 0 or (now > 0 and (now - (lot.ts or 0)) > LOT_MAX_AGE) then
			lots[itemID] = nil
		else
			count = count + 1
		end
	end
	if count <= MAX_LOT_ENTRIES then
		return
	end
	local keys = {}
	for itemID, lot in pairs(lots) do
		keys[#keys + 1] = { itemID = itemID, ts = lot.ts or 0 }
	end
	table.sort(keys, function(a, b)
		if a.ts ~= b.ts then
			return a.ts < b.ts
		end
		return a.itemID < b.itemID
	end)
	for i = 1, #keys - MAX_LOT_ENTRIES do
		lots[keys[i].itemID] = nil
	end
end

local function PruneCraftedTrack(craftedItems, craftedNames)
	local count = 0
	for itemID, qty in pairs(craftedItems) do
		if type(qty) ~= "number" or qty <= 0 then
			craftedItems[itemID] = nil
		else
			count = count + 1
		end
	end
	if count > MAX_CRAFTED_TRACK then
		local keys = {}
		for itemID, qty in pairs(craftedItems) do
			keys[#keys + 1] = { itemID = itemID, qty = qty }
		end
		table.sort(keys, function(a, b)
			if a.qty ~= b.qty then
				return a.qty < b.qty
			end
			return a.itemID < b.itemID
		end)
		for i = 1, #keys - MAX_CRAFTED_TRACK do
			craftedItems[keys[i].itemID] = nil
		end
	end
	for name, itemID in pairs(craftedNames) do
		if not craftedItems[itemID] then
			craftedNames[name] = nil
		end
	end
end

local function GetConsumedReagentSet()
	if consumedReagentSet then
		return consumedReagentSet
	end
	consumedReagentSet = {}
	for _, rec in pairs(ns.RecipeData or {}) do
		if type(rec) == "table" and rec.reagents then
			for _, rg in ipairs(rec.reagents) do
				if rg.itemID and rg.itemID > 0 then
					consumedReagentSet[rg.itemID] = true
				end
			end
		end
	end
	return consumedReagentSet
end

local function GetTodayStartTimestamp()
	if time and date then
		local ok, dt = pcall(date, "*t")
		if ok and type(dt) == "table" then
			dt.hour = 0
			dt.min = 0
			dt.sec = 0
			dt.isdst = nil
			local ts = time(dt)
			if ts then
				return ts
			end
		end
	end
	return (time and time() or 0) - 86400
end

local function RefreshProfitLogUI()
	if ns.modules and ns.modules.byId and ns.modules.byId["profit"] then
		local mod = ns.modules.byId["profit"]
		if mod.view and mod.view:IsVisible() and mod.OnRefresh then
			mod:OnRefresh()
		end
	end
end

function ns:GetProfitLogMode()
	if self.db and self.db.options and self.db.options.profitLogMode == "cashflow" then
		return "cashflow"
	end
	return "craft"
end

function ns:TrackTradeFlowAhItem(itemID)
	if type(itemID) == "number" and itemID > 0 then
		ns._trackedAhBuyItems[itemID] = true
	end
end

local function IsInTradeFlowAhScope(itemID)
	if not itemID or itemID <= 0 then
		return false
	end
	if ns._trackedAhBuyItems[itemID] then
		return true
	end
	local targets = ns.GetSnipeTargets and ns:GetSnipeTargets()
	if targets and targets[itemID] then
		ns._trackedAhBuyItems[itemID] = true
		return true
	end
	if ns.GetShoppingList then
		local list = ns:GetShoppingList()
		for _, item in ipairs(list or {}) do
			if item.itemID == itemID then
				ns._trackedAhBuyItems[itemID] = true
				return true
			end
		end
	end
	return false
end

local function AddPurchaseLot(itemID, qty, totalCost, now)
	if not (itemID and itemID > 0 and qty and qty > 0 and totalCost and totalCost > 0) then
		return
	end
	local lots = EnsurePurchaseLotsDB()
	local lot = lots[itemID]
	if not lot then
		lot = { qty = 0, totalCost = 0, ts = now }
		lots[itemID] = lot
	end
	lot.qty = (lot.qty or 0) + qty
	lot.totalCost = (lot.totalCost or 0) + totalCost
	lot.ts = now
	PrunePurchaseLots(lots, now)
end

local function PreviewPurchaseLot(lots, itemID, qty)
	local lot = lots and lots[itemID]
	if not lot or (lot.qty or 0) <= 0 or qty <= 0 then
		return 0, 0
	end
	local take = math.min(lot.qty, qty)
	local takeCost = (take >= lot.qty) and (lot.totalCost or 0) or math.floor(((lot.totalCost or 0) * take / lot.qty) + 0.5)
	return take, takeCost
end

local function CommitPurchaseLot(lots, itemID, take, takeCost)
	local lot = lots and lots[itemID]
	if not lot or take <= 0 then
		return
	end
	lot.qty = (lot.qty or 0) - take
	lot.totalCost = math.max(0, (lot.totalCost or 0) - takeCost)
	if lot.qty <= 0 then
		lots[itemID] = nil
	end
end

local function AppendCashflowEntry(kind, itemID, recipeID, name, qty, amount, charKey, dayKey, now)
	local log = EnsureCashflowLogDB()
	local top = log[1]
	if top and top.kind == kind and top.charKey == charKey and top.dayKey == dayKey
		and top.itemID == itemID and top.recipeID == recipeID
		and now >= (top.ts or 0) and (now - (top.ts or 0)) <= COALESCE_SECONDS
	then
		top.count = (top.count or 1) + (qty or 1)
		top.amount = (top.amount or 0) + amount
		top.ts = now
	else
		table.insert(log, 1, {
			ts = now,
			dayKey = dayKey,
			charKey = charKey,
			kind = kind,
			itemID = itemID,
			recipeID = recipeID,
			name = name,
			count = qty or 1,
			amount = amount,
		})
		while #log > MAX_LOG_ENTRIES do
			table.remove(log)
		end
	end
end

function ns:RecordTradeFlowPurchase(kind, itemID, qty, totalCost)
	if not (itemID and itemID > 0 and qty and qty > 0 and totalCost and totalCost > 0) then
		return
	end
	local now = time and time() or 0
	local gNow = GetTime and GetTime() or 0
	if kind == "snipe_buy" then
		lastSnipeRec = { itemID = itemID, qty = qty, ts = gNow }
	end
	local dayKey = (date and now > 0) and date("%Y-%m-%d", now) or nil
	local charKey = self.CharKey and self:CharKey() or ""

	AddPurchaseLot(itemID, qty, totalCost, now)
	AppendCashflowEntry(kind or "ah_buy", itemID, nil, nil, qty, -totalCost, charKey, dayKey, now)
	RefreshProfitLogUI()
end

function ns:RecordTrainerExpense(recipeID, name, cost)
	if not (cost and cost > 0) then
		return
	end
	local now = time and time() or 0
	local dayKey = (date and now > 0) and date("%Y-%m-%d", now) or nil
	local charKey = self.CharKey and self:CharKey() or ""

	local craftLog = EnsureCraftLogDB()
	table.insert(craftLog, 1, {
		ts = now,
		dayKey = dayKey,
		charKey = charKey,
		kind = "trainer",
		recipeID = recipeID,
		name = name,
		count = 1,
		cost = cost,
		revenue = 0,
		profit = -cost,
		source = "trainer",
	})
	while #craftLog > MAX_LOG_ENTRIES do
		table.remove(craftLog)
	end

	AppendCashflowEntry("trainer", nil, recipeID, name, 1, -cost, charKey, dayKey, now)
	RefreshProfitLogUI()
end

function ns:RecordCashflowIncome(kind, itemID, qty, totalEarned)
	if not (qty and qty > 0 and totalEarned and totalEarned > 0) then
		return
	end
	local now = time and time() or 0
	local dayKey = (date and now > 0) and date("%Y-%m-%d", now) or nil
	local charKey = self.CharKey and self:CharKey() or ""

	AppendCashflowEntry(kind or "vendor_sell", itemID, nil, nil, qty, totalEarned, charKey, dayKey, now)
	RefreshProfitLogUI()
end

-- Списывает из сегодняшнего лога того же персонажа скрафченные ранее полуфабрикаты,
-- когда они фактически уходят в крафт финального предмета (без двойного учёта).
local function ConsumeIntermediateFromLog(log, rec, charKey, dayKey)
	if not (rec and rec.reagents) then
		return
	end
	for _, rg in ipairs(rec.reagents) do
		local need = rg.quantity or 0
		if need > 0 and rg.itemID and rg.itemID > 0 then
			local idx = 1
			while idx <= #log and need > 0 do
				local e = log[idx]
				if (e.kind or "craft") == "craft"
					and e.outItemID == rg.itemID and e.recipeID ~= rec.recipeID
					and e.charKey == charKey and e.dayKey == dayKey
				then
					local eRec = ns.GetRecipeRecord and ns:GetRecipeRecord(e.recipeID)
					local perCraft = (eRec and eRec.numMade and eRec.numMade > 0) and eRec.numMade or 1
					local avail = e.itemQty or ((e.count or 1) * perCraft)
					if avail <= need then
						need = need - avail
						table.remove(log, idx)
					else
						local rem = avail - need
						local ratio = rem / avail
						e.itemQty = rem
						e.count = math.max(0.01, math.floor((rem / perCraft) * 100 + 0.5) / 100)
						e.cost = math.floor((e.cost or 0) * ratio + 0.5)
						e.revenue = math.floor((e.revenue or 0) * ratio + 0.5)
						e.profit = e.revenue - e.cost
						need = 0
						idx = idx + 1
					end
				else
					idx = idx + 1
				end
			end
		end
	end
end

function ns:RecordCraftProfit(spellID, isSubcraft)
	if not spellID or spellID <= 0 then
		return
	end
	local rec = self.GetRecipeRecord and self:GetRecipeRecord(spellID)
	if not rec or not rec.reagents or #rec.reagents == 0 or not rec.outputItemID or rec.outputItemID <= 0 then
		return
	end

	local now = time and time() or 0
	local lots = EnsurePurchaseLotsDB()
	local plannedTakes = {}
	local actualCost = 0
	local allPriced = true
	local usedRealCost = false
	for _, rg in ipairs(rec.reagents) do
		local qty = rg.quantity or 0
		if qty > 0 and rg.itemID then
			local took, spent = PreviewPurchaseLot(lots, rg.itemID, qty)
			if took > 0 then
				plannedTakes[#plannedTakes + 1] = { itemID = rg.itemID, take = took, spent = spent }
				actualCost = actualCost + spent
				usedRealCost = true
			end
			local rem = qty - took
			if rem > 0 then
				local unitP = self.GetReagentBestPrice and self:GetReagentBestPrice(rg.itemID)
				if not unitP then
					allPriced = false
					break
				end
				actualCost = actualCost + unitP * rem
			end
		end
	end

	local numMade = (rec.numMade and rec.numMade > 0) and rec.numMade or 1
	if allPriced and usedRealCost then
		for _, pt in ipairs(plannedTakes) do
			CommitPurchaseLot(lots, pt.itemID, pt.take, pt.spent)
		end
		if isSubcraft or GetConsumedReagentSet()[rec.outputItemID] then
			AddPurchaseLot(rec.outputItemID, numMade, actualCost, now)
		end
	else
		usedRealCost = false
	end

	if isSubcraft then
		return
	end

	-- Помечаем произведённый предмет для отслеживания его реальной продажи вендору или на АХ (Режим «Касса»)
	local craftedItems, craftedNames = EnsureCraftedItemsDB()
	craftedItems[rec.outputItemID] = (craftedItems[rec.outputItemID] or 0) + numMade
	local outName = self.GetItemDisplay and select(1, self:GetItemDisplay(rec.outputItemID))
	if (not outName or outName == "" or outName:find("^#")) and C_Item and C_Item.GetItemNameByID then
		outName = C_Item.GetItemNameByID(rec.outputItemID)
	end
	if outName and outName ~= "" and not outName:find("^#") then
		craftedNames[outName] = rec.outputItemID
	end
	PruneCraftedTrack(craftedItems, craftedNames)

	local craftCost, outVal, _, _, outSource, alts = self:GetRecipeEconomy(spellID)
	local unitCost = (usedRealCost and actualCost) or craftCost
	local vendorOnly = self.db and self.db.options and self.db.options.deductVendorInRoute ~= false
	if ns.EvalRecipeChannel and unitCost ~= nil then
		local ch = vendorOnly and "safe" or ((self.db and self.db.options and self.db.options.profitChannel) or "all")
		local evalOut, _, evalSrc = ns.EvalRecipeChannel(rec, unitCost, alts, ch)
		if evalOut ~= nil then
			outVal = evalOut
			outSource = evalSrc
		elseif vendorOnly then
			outVal = nil
		end
	end
	if unitCost == nil or outVal == nil then
		return
	end

	local unitRev = outVal
	local unitProfit = unitRev - unitCost
	local src = outSource or "unknown"
	local dayKey = (date and now > 0) and date("%Y-%m-%d", now) or nil
	local charKey = self.CharKey and self:CharKey() or ""

	local log = EnsureCraftLogDB()
	ConsumeIntermediateFromLog(log, rec, charKey, dayKey)
	local top = log[1]
	if top and (top.kind or "craft") == "craft"
		and top.recipeID == spellID and top.charKey == charKey and top.source == src
		and (top.usedRealCost == true) == (usedRealCost == true)
		and top.dayKey == dayKey
		and now >= (top.ts or 0) and (now - (top.ts or 0)) <= COALESCE_SECONDS
	then
		top.count = (top.count or 1) + 1
		if top.itemQty ~= nil then
			top.itemQty = top.itemQty + numMade
		end
		top.cost = (top.cost or 0) + unitCost
		top.revenue = (top.revenue or 0) + unitRev
		top.profit = (top.profit or 0) + unitProfit
		top.ts = now
	else
		table.insert(log, 1, {
			ts = now,
			dayKey = dayKey,
			charKey = charKey,
			kind = "craft",
			skillLine = rec.skillLine,
			recipeID = spellID,
			outItemID = rec.outputItemID,
			count = 1,
			cost = unitCost,
			revenue = unitRev,
			profit = unitProfit,
			source = src,
			usedRealCost = usedRealCost or nil,
		})
		while #log > MAX_LOG_ENTRIES do
			table.remove(log)
		end
	end

	RefreshProfitLogUI()
end

function ns:GetProfitLogSummary(period, mode)
	mode = mode or self:GetProfitLogMode()
	local minTs = (period == "today") and GetTodayStartTimestamp() or 0
	local entries = {}

	if mode == "cashflow" then
		local log = EnsureCashflowLogDB()
		local spent = 0
		local earned = 0
		for _, e in ipairs(log) do
			if (e.ts or 0) >= minTs then
				entries[#entries + 1] = e
				local amt = e.amount or 0
				if amt < 0 then
					spent = spent + (-amt)
				elseif amt > 0 then
					earned = earned + amt
				end
			end
		end
		return {
			mode = "cashflow",
			entries = entries,
			craftsTotal = 0,
			opsTotal = #entries,
			spent = spent,
			earned = earned,
			profit = earned - spent,
		}
	end

	local log = EnsureCraftLogDB()
	local craftsTotal = 0
	local totalCost = 0
	local totalRev = 0
	local totalProfit = 0

	for _, e in ipairs(log) do
		if (e.ts or 0) >= minTs then
			entries[#entries + 1] = e
			if (e.kind or "craft") == "craft" then
				craftsTotal = craftsTotal + (e.count or 1)
			end
			totalCost = totalCost + (e.cost or 0)
			totalRev = totalRev + (e.revenue or 0)
			totalProfit = totalProfit + (e.profit or 0)
		end
	end

	return {
		mode = "craft",
		entries = entries,
		craftsTotal = (craftsTotal > 0) and math.max(1, math.floor(craftsTotal + 0.5)) or 0,
		opsTotal = #entries,
		cost = totalCost,
		revenue = totalRev,
		spent = totalCost,
		earned = totalRev,
		profit = totalProfit,
	}
end

function ns:ClearProfitLog(mode)
	mode = mode or self:GetProfitLogMode()
	if self.realmDB then
		if mode == "cashflow" then
			self.realmDB.cashflowLog = {}
		else
			self.realmDB.profitLog = {}
		end
	end
	RefreshProfitLogUI()
end

-------------------------------------------------------------------------------
-- Лёгкий taint-free трекинг транзакций АХ (Auctionator + списки TradeFlow),
-- продажи вендору скрафченных вещей и писем с выручкой от АХ
-------------------------------------------------------------------------------
local function InstallAhHooks()
	if ahHooksInstalled or not C_AuctionHouse then
		return
	end
	if C_AuctionHouse.StartCommoditiesPurchase or C_AuctionHouse.PlaceBid then
		ahHooksInstalled = true
	end
	if C_AuctionHouse.StartCommoditiesPurchase then
		hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, qty)
			if not HasAuctionator() then
				return
			end
			if ns.IsSnipePurchaseActive and ns:IsSnipePurchaseActive() then
				return
			end
			if type(itemID) ~= "number" or not qty or qty <= 0 or not IsInTradeFlowAhScope(itemID) then
				return
			end
			pendingAhComm = {
				itemID = itemID,
				qty = qty,
				ts = GetTime and GetTime() or 0,
			}
		end)
	end
	if C_AuctionHouse.PlaceBid then
		hooksecurefunc(C_AuctionHouse, "PlaceBid", function(_, bidAmount)
			if not HasAuctionator() then
				return
			end
			if ns.IsSnipePurchaseActive and ns:IsSnipePurchaseActive() then
				return
			end
			local amt = tonumber(bidAmount)
			local iid = lastViewedAhItemID
			if not (iid and amt and amt > 0 and IsInTradeFlowAhScope(iid)) then
				return
			end
			pendingAhBid = {
				itemID = iid,
				amount = amt,
				moneyBefore = GetMoney and GetMoney() or 0,
				ts = GetTime and GetTime() or 0,
			}
		end)
	end
end

local function SnapshotMerchantBags()
	local craftedItems = EnsureCraftedItemsDB()
	local snap = {}
	for itemID, qty in pairs(craftedItems) do
		if type(qty) == "number" and qty > 0 then
			local inBags = ns.GetBagCount and ns:GetBagCount(itemID) or 0
			if inBags > 0 then
				snap[itemID] = inBags
			end
		end
	end
	merchantBagSnap = snap
	merchantMoney = GetMoney and GetMoney() or 0
end

local function CheckMerchantSoldCrafted()
	if not (merchantBagSnap and MerchantFrame and MerchantFrame:IsShown()) then
		return
	end
	local curMoney = GetMoney and GetMoney() or 0
	if curMoney <= merchantMoney then
		merchantMoney = curMoney
		for itemID in pairs(merchantBagSnap) do
			merchantBagSnap[itemID] = ns.GetBagCount and ns:GetBagCount(itemID) or 0
		end
		return
	end
	local gained = curMoney - merchantMoney
	local craftedItems = EnsureCraftedItemsDB()
	for itemID, prevCnt in pairs(merchantBagSnap) do
		local curCnt = ns.GetBagCount and ns:GetBagCount(itemID) or 0
		if curCnt < prevCnt then
			local dropped = prevCnt - curCnt
			local capCrafted = craftedItems[itemID] or 0
			local sold = math.min(dropped, capCrafted)
			if sold > 0 and gained > 0 then
				local unitSell = ns.GetItemSellPrice and ns:GetItemSellPrice(itemID) or 0
				local earned = (unitSell > 0) and math.min(unitSell * sold, gained) or 0
				if earned > 0 then
					ns:RecordCashflowIncome("vendor_sell", itemID, sold, earned)
					craftedItems[itemID] = math.max(0, capCrafted - sold)
					gained = math.max(0, gained - earned)
				end
			end
			merchantBagSnap[itemID] = curCnt
		end
	end
	merchantMoney = curMoney
end

local MAIL_PAIR_WINDOW = 5

local function GetDisenchantMatNameMap()
	disenchantNameMap = disenchantNameMap or {}
	if not ns.DisenchantMatIDs then
		return disenchantNameMap
	end
	for itemID in pairs(ns.DisenchantMatIDs) do
		local name = ns.GetItemDisplay and select(1, ns:GetItemDisplay(itemID))
		if (not name or name == "" or name:find("^#")) and C_Item and C_Item.GetItemNameByID then
			name = C_Item.GetItemNameByID(itemID)
		end
		if name and name ~= "" and not name:find("^#") then
			disenchantNameMap[name] = itemID
		elseif ns.RequestItemData then
			ns:RequestItemData(itemID)
		end
	end
	return disenchantNameMap
end

local function ResolveTrackedSellItemID(cleanName)
	if not cleanName or cleanName == "" then
		return nil
	end
	local _, craftedNames = EnsureCraftedItemsDB()
	if craftedNames[cleanName] then
		return craftedNames[cleanName]
	end
	return GetDisenchantMatNameMap()[cleanName]
end

local function GetAuctionSoldSubjectPattern()
	if soldSubjectPattern ~= nil then
		return soldSubjectPattern or nil
	end
	local tmpl = _G.AUCTION_SOLD_MAIL_SUBJECT
	if type(tmpl) ~= "string" or tmpl == "" then
		soldSubjectPattern = false
		return nil
	end
	local escaped = tmpl:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	soldSubjectPattern = "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
	return soldSubjectPattern
end

local function ParseSoldItemName(rawName)
	if type(rawName) ~= "string" or rawName == "" then
		return nil, 1
	end
	local clean, suffixQty = rawName:match("^(.-)%s*%((%d+)%)%s*$")
	if not clean then
		clean, suffixQty = rawName:match("^(.-)%s+[xX](%d+)%s*$")
	end
	if not clean then
		clean, suffixQty = rawName:match("^(.-)%s+х(%d+)%s*$")
	end
	if not clean then
		clean, suffixQty = rawName:match("^(.-)%s+Х(%d+)%s*$")
	end
	clean = (clean or rawName):gsub("^%s+", ""):gsub("%s+$", "")
	return clean, tonumber(suffixQty) or 1
end

local function MatchLootQty(msg)
	return tonumber(
		msg:match("|h|r%s*[xX](%d+)")
		or msg:match("|h|r%s*х(%d+)")
		or msg:match("|h|r%s*Х(%d+)")
		or msg:match("%]%s*[xX](%d+)")
		or msg:match("%]%s*х(%d+)")
		or msg:match("%]%s*Х(%d+)")
	) or 1
end

local function BuildMailSellerSnap()
	if not (HasAuctionator() and GetInboxNumItems and GetInboxHeaderInfo) then
		return nil
	end
	local counts = {}
	local entries = {}
	local subjPat = GetAuctionSoldSubjectPattern()
	local n = GetInboxNumItems() or 0
	for i = 1, n do
		local _, _, sender, subject, money = GetInboxHeaderInfo(i)
		if money and money > 0 then
			local invoiceType, itemName, count
			if GetInboxInvoiceInfo then
				local ok, iType, iName, _, _, _, _, _, _, _, _, iCount = pcall(GetInboxInvoiceInfo, i)
				if ok then
					invoiceType, itemName, count = iType, iName, iCount
				end
			end
			if (not itemName or itemName == "") and subjPat and type(subject) == "string" then
				local extracted = subject:match(subjPat)
				if extracted and extracted ~= "" then
					invoiceType = invoiceType or "seller"
					itemName = extracted
				end
			end
			if invoiceType == "seller" and itemName and itemName ~= "" then
				local cleanName, suffixQty = ParseSoldItemName(itemName)
				local itemID = ResolveTrackedSellItemID(cleanName)
				if itemID then
					local qty = math.max(1, tonumber(count) or suffixQty or 1)
					local key = (sender or "") .. "|" .. (subject or "") .. "|" .. itemID .. "|" .. qty .. "|" .. money
					counts[key] = (counts[key] or 0) + 1
					if not entries[key] then
						entries[key] = { itemID = itemID, count = qty, money = money }
					end
				end
			end
		end
	end
	return { counts = counts, entries = entries }
end

local function FlushPendingMailSales(now)
	if (now - (pendingMailMoney.ts or 0)) > MAIL_PAIR_WINDOW then
		pendingMailMoney.amount = 0
		pendingMailMoney.ts = 0
	end
	local kept = {}
	for _, entry in ipairs(pendingMailItems) do
		if (now - (entry.ts or 0)) <= MAIL_PAIR_WINDOW then
			kept[#kept + 1] = entry
		end
	end
	pendingMailItems = kept

	if (pendingMailMoney.amount or 0) <= 0 or #pendingMailItems == 0 then
		return
	end

	local craftedItems = EnsureCraftedItemsDB()
	while (pendingMailMoney.amount or 0) > 0 and #pendingMailItems > 0 do
		local matchIdx = nil
		for idx, entry in ipairs(pendingMailItems) do
			if math.abs(entry.money - pendingMailMoney.amount) <= 5 then
				matchIdx = idx
				break
			end
		end
		if not matchIdx then
			for idx, entry in ipairs(pendingMailItems) do
				if entry.money <= (pendingMailMoney.amount + 5) then
					matchIdx = idx
					break
				end
			end
		end
		if not matchIdx then
			break
		end
		local entry = table.remove(pendingMailItems, matchIdx)
		local earned = math.min(entry.money, pendingMailMoney.amount)
		if earned > 0 then
			ns:RecordCashflowIncome("ah_sell", entry.itemID, entry.count, earned)
			if craftedItems[entry.itemID] then
				craftedItems[entry.itemID] = math.max(0, craftedItems[entry.itemID] - entry.count)
			end
			pendingMailMoney.amount = math.max(0, pendingMailMoney.amount - earned)
		end
	end
end

local function CheckMailSellerUpdate(now)
	if not (MailFrame and MailFrame:IsShown()) then
		return
	end
	local curSnap = BuildMailSellerSnap()
	if mailSellerSnap and curSnap then
		for key, prevCount in pairs(mailSellerSnap.counts) do
			local curCount = curSnap.counts[key] or 0
			local collected = prevCount - curCount
			if collected > 0 then
				local info = mailSellerSnap.entries[key]
				if info and info.itemID and (info.money or 0) > 0 then
					for _ = 1, collected do
						pendingMailItems[#pendingMailItems + 1] = {
							itemID = info.itemID,
							count = info.count,
							money = info.money,
							ts = now,
						}
					end
				end
			end
		end
	end
	mailSellerSnap = curSnap
	FlushPendingMailSales(now)
end

local txFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"PLAYER_LOGIN",
	"AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_CLOSED",
	"ITEM_SEARCH_RESULTS_UPDATED",
	"COMMODITY_PRICE_UPDATED",
	"COMMODITY_PRICE_UNAVAILABLE",
	"COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED",
	"MERCHANT_SHOW",
	"MERCHANT_CLOSED",
	"BAG_UPDATE_DELAYED",
	"MAIL_SHOW",
	"MAIL_CLOSED",
	"MAIL_INBOX_UPDATE",
	"PLAYER_MONEY",
	"UNIT_SPELLCAST_SUCCEEDED",
	"CHAT_MSG_LOOT",
}) do
	pcall(txFrame.RegisterEvent, txFrame, ev)
end

txFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
	local now = GetTime and GetTime() or 0
	if event == "PLAYER_LOGIN" then
		InstallAhHooks()
	elseif event == "AUCTION_HOUSE_SHOW" then
		InstallAhHooks()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		pendingAhComm = nil
		pendingAhBid = nil
		lastViewedAhItemID = nil
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
		if type(arg1) == "table" and arg1.itemID and arg1.itemID > 0 then
			lastViewedAhItemID = arg1.itemID
		end
	elseif event == "COMMODITY_PRICE_UPDATED" then
		if pendingAhComm and (now - (pendingAhComm.ts or 0)) <= 10 then
			local unitP = tonumber(arg1) or 0
			local totalP = tonumber(arg2) or (unitP * pendingAhComm.qty)
			if totalP > 0 then
				pendingAhComm.totalPrice = totalP
			end
		else
			pendingAhComm = nil
		end
	elseif event == "COMMODITY_PRICE_UNAVAILABLE" or event == "COMMODITY_PURCHASE_FAILED" then
		pendingAhComm = nil
	elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
		local p = pendingAhComm
		pendingAhComm = nil
		if p and (now - (p.ts or 0)) <= 15 and (p.totalPrice or 0) > 0 then
			local isDupSnipe = lastSnipeRec and lastSnipeRec.itemID == p.itemID
				and lastSnipeRec.qty == p.qty and (now - (lastSnipeRec.ts or 0)) <= 1.5
			if not isDupSnipe then
				ns:RecordTradeFlowPurchase("ah_buy", p.itemID, p.qty, p.totalPrice)
			end
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if arg1 == "player" and tonumber(arg3) == 13262 then
			lastDisenchantAt = now
		end
	elseif event == "CHAT_MSG_LOOT" then
		if lastDisenchantAt > 0 and (now - lastDisenchantAt) <= 3.0 and type(arg1) == "string" then
			local itemID = tonumber(arg1:match("item:(%d+)"))
			if itemID and itemID > 0 then
				local itemName = arg1:match("|h%[(.-)%]|h") or arg1:match("%[(.-)%]")
				local qty = MatchLootQty(arg1)
				local craftedItems, craftedNames = EnsureCraftedItemsDB()
				craftedItems[itemID] = (craftedItems[itemID] or 0) + qty
				if itemName and itemName ~= "" then
					craftedNames[itemName] = itemID
				end
				PruneCraftedTrack(craftedItems, craftedNames)
			end
		end
	elseif event == "MERCHANT_SHOW" then
		SnapshotMerchantBags()
	elseif event == "MERCHANT_CLOSED" then
		merchantBagSnap = nil
	elseif event == "BAG_UPDATE_DELAYED" then
		if MerchantFrame and MerchantFrame:IsShown() and merchantBagSnap then
			CheckMerchantSoldCrafted()
		end
	elseif event == "MAIL_SHOW" then
		GetDisenchantMatNameMap()
		mailMoney = GetMoney and GetMoney() or 0
		pendingMailMoney = { amount = 0, ts = 0 }
		pendingMailItems = {}
		mailSellerSnap = BuildMailSellerSnap()
	elseif event == "MAIL_CLOSED" then
		FlushPendingMailSales(now)
		mailSellerSnap = nil
		pendingMailMoney = { amount = 0, ts = 0 }
		pendingMailItems = {}
	elseif event == "MAIL_INBOX_UPDATE" then
		if MailFrame and MailFrame:IsShown() then
			CheckMailSellerUpdate(now)
		end
	elseif event == "PLAYER_MONEY" then
		if pendingAhBid then
			local b = pendingAhBid
			pendingAhBid = nil
			local curM = GetMoney and GetMoney() or 0
			if (now - (b.ts or 0)) <= 2.5 and (b.moneyBefore - curM) == b.amount then
				ns:RecordTradeFlowPurchase("ah_buy", b.itemID, 1, b.amount)
			end
		end
		if MailFrame and MailFrame:IsShown() then
			local curM = GetMoney and GetMoney() or 0
			if curM > mailMoney then
				pendingMailMoney.amount = (pendingMailMoney.amount or 0) + (curM - mailMoney)
				pendingMailMoney.ts = now
			end
			mailMoney = curM
			FlushPendingMailSales(now)
		end
	end
end)
