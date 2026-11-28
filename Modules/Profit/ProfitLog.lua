local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Журнал заработка (режимы «Крафт» и «Касса») + трекинг реальных покупок/продаж
-------------------------------------------------------------------------------
local MAX_LOG_ENTRIES = 500
local MAX_CASHFLOW_ENTRIES = 1000
local CASHFLOW_RETENTION_SECONDS = 86400
local MAX_LOT_ENTRIES = 120
local MAX_CRAFTED_TRACK = 200
local LOT_MAX_AGE = 7 * 86400
local COALESCE_SECONDS = 30
local MAIL_PAIR_WINDOW = 5
local MERCHANT_PAIR_WINDOW = 2.0
local MERCHANT_BUY_WINDOW = 10.0

local consumedReagentSet = nil
local vendorScrollSet = nil
local disenchantNameMap = nil
local disenchantMapComplete = false
local soldSubjectPattern = nil
local ahHooksInstalled = false
local merchantHooksInstalled = false
local lastDisenchantAt = 0
local pendingAhComm = nil
local confirmingAhComm = nil
local pendingAhBid = nil
local ahMoney = nil
local pendingAhPosts = {}
local lastViewedAhItemKey = nil
local merchantMoney = 0
local merchantBagSnap = nil
local merchantCatalog = nil
local merchantBuySnap = nil
local merchantLastBuyAt = 0
local pendingMerchantMoney = { amount = 0, ts = 0 }
local pendingMerchantDrops = {}
local mailMoney = 0
local mailSellerSnap = nil
local pendingMailMoney = { amount = 0, ts = 0 }
local pendingMailItems = {}

local function IsProfitEnabled()
	return not (ns.IsModuleEnabled and not ns:IsModuleEnabled("profit"))
end

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

local function EnsureCraftArchiveDB()
	if not ns.realmDB then
		return nil
	end
	ns.realmDB.profitArchive = ns.realmDB.profitArchive or {
		opsTotal = 0,
		craftsTotal = 0,
		cost = 0,
		revenue = 0,
		profit = 0,
	}
	return ns.realmDB.profitArchive
end

local function EnsureCashflowArchiveDB()
	if not ns.realmDB then
		return nil
	end
	ns.realmDB.cashflowArchive = ns.realmDB.cashflowArchive or {
		opsTotal = 0,
		spent = 0,
		earned = 0,
	}
	return ns.realmDB.cashflowArchive
end

local function TrimCraftLog(log)
	while #log > MAX_LOG_ENTRIES do
		local evicted = table.remove(log)
		if type(evicted) == "table" then
			local arch = EnsureCraftArchiveDB()
			if arch then
				arch.opsTotal = (arch.opsTotal or 0) + 1
				if (evicted.kind or "craft") == "craft" then
					arch.craftsTotal = (arch.craftsTotal or 0) + (evicted.count or 1)
				end
				arch.cost = (arch.cost or 0) + (evicted.cost or 0)
				arch.revenue = (arch.revenue or 0) + (evicted.revenue or 0)
				arch.profit = (arch.profit or 0) + (evicted.profit or 0)
			end
		end
	end
end

local function TrimCashflowLog(log, now)
	local cur = (now and now > 0) and now or (time and time() or 0)
	local cutoff = (cur > CASHFLOW_RETENTION_SECONDS) and (cur - CASHFLOW_RETENTION_SECONDS) or 0
	while #log > 0 and (#log > MAX_CASHFLOW_ENTRIES or (cutoff > 0 and (log[#log].ts or 0) < cutoff)) do
		local evicted = table.remove(log)
		if type(evicted) == "table" then
			local arch = EnsureCashflowArchiveDB()
			if arch then
				arch.opsTotal = (arch.opsTotal or 0) + 1
				local amt = evicted.amount or 0
				if amt < 0 then
					arch.spent = (arch.spent or 0) + (-amt)
				elseif amt > 0 then
					arch.earned = (arch.earned or 0) + amt
				end
			end
		end
	end
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
		if not craftedItems[itemID] or (type(name) == "string" and name:find("#%d+")) then
			craftedNames[name] = nil
		end
	end
end

local function DecrementCraftedItem(itemID, qty)
	if not (itemID and qty and qty > 0) then
		return
	end
	local craftedItems, craftedNames = EnsureCraftedItemsDB()
	local cur = craftedItems[itemID]
	if not cur or cur <= 0 then
		craftedItems[itemID] = nil
		return
	end
	local left = cur - qty
	if left > 0 then
		craftedItems[itemID] = left
	else
		craftedItems[itemID] = nil
		for name, mappedID in pairs(craftedNames) do
			if mappedID == itemID then
				craftedNames[name] = nil
			end
		end
	end
end

local function GetLoadedItemName(itemID)
	if not itemID or itemID <= 0 then
		return nil
	end
	if ns.GetItemDisplay then
		local name, _, _, _, loaded = ns:GetItemDisplay(itemID)
		if loaded and type(name) == "string" and name ~= "" then
			return name
		end
	end
	if C_Item and C_Item.GetItemNameByID then
		local name = C_Item.GetItemNameByID(itemID)
		if type(name) == "string" and name ~= "" then
			return name
		end
	end
	if ns.RequestItemData then
		ns:RequestItemData(itemID)
	end
	return nil
end

local function GetConsumedReagentSet()
	if not consumedReagentSet then
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
	end
	if ns.liveRecipes then
		for _, rec in pairs(ns.liveRecipes) do
			if type(rec) == "table" and rec.reagents then
				for _, rg in ipairs(rec.reagents) do
					if rg.itemID and rg.itemID > 0 then
						consumedReagentSet[rg.itemID] = true
					end
				end
			end
		end
	end
	return consumedReagentSet
end

local function GetVendorScrollSet()
	if vendorScrollSet then
		return vendorScrollSet
	end
	vendorScrollSet = {}
	for _, row in pairs(ns.VendorRecipeScrolls or {}) do
		local scrollID = type(row) == "table" and row[1]
		if scrollID and scrollID > 0 then
			vendorScrollSet[scrollID] = true
		end
	end
	return vendorScrollSet
end

local function GetRolling24hTimestamp()
	local now = time and time() or 0
	if now > CASHFLOW_RETENTION_SECONDS then
		return now - CASHFLOW_RETENTION_SECONDS
	end
	return 0
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

local function IsInTradeFlowAhScope(itemID)
	if not itemID or itemID <= 0 then
		return false
	end
	local targets = ns.GetSnipeTargets and ns:GetSnipeTargets()
	if targets and targets[itemID] then
		return true
	end
	if ns.GetShoppingList then
		local list = ns:GetShoppingList()
		for _, item in ipairs(list or {}) do
			if item.itemID == itemID then
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

local function PreviewPurchaseLot(lots, itemID, qty, now)
	local lot = lots and lots[itemID]
	if not lot or (lot.qty or 0) <= 0 or qty <= 0 then
		return 0, 0
	end
	if now and now > 0 and (now - (lot.ts or 0)) > LOT_MAX_AGE then
		lots[itemID] = nil
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
		TrimCashflowLog(log, now)
	end
end

function ns:RecordTradeFlowPurchase(kind, itemID, qty, totalCost)
	if not IsProfitEnabled() then
		return
	end
	if not (itemID and itemID > 0 and qty and qty > 0 and totalCost and totalCost > 0) then
		return
	end
	local now = time and time() or 0
	local dayKey = (date and now > 0) and date("%Y-%m-%d", now) or nil
	local charKey = self.CharKey and self:CharKey() or ""

	AddPurchaseLot(itemID, qty, totalCost, now)
	AppendCashflowEntry(kind or "ah_buy", itemID, nil, nil, qty, -totalCost, charKey, dayKey, now)
	RefreshProfitLogUI()
end

function ns:RecordTrainerExpense(recipeID, name, cost)
	if not IsProfitEnabled() then
		return
	end
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
	TrimCraftLog(craftLog)

	AppendCashflowEntry("trainer", nil, recipeID, name, 1, -cost, charKey, dayKey, now)
	RefreshProfitLogUI()
end

function ns:RecordCashflowIncome(kind, itemID, qty, totalEarned)
	if not IsProfitEnabled() then
		return
	end
	if not (qty and qty > 0 and totalEarned and totalEarned > 0) then
		return
	end
	local now = time and time() or 0
	local dayKey = (date and now > 0) and date("%Y-%m-%d", now) or nil
	local charKey = self.CharKey and self:CharKey() or ""

	AppendCashflowEntry(kind or "vendor_sell", itemID, nil, nil, qty, totalEarned, charKey, dayKey, now)
	RefreshProfitLogUI()
end

function ns:RecordCashflowExpense(kind, itemID, qty, totalSpent)
	if not IsProfitEnabled() then
		return
	end
	if not (qty and qty > 0 and totalSpent and totalSpent > 0) then
		return
	end
	local now = time and time() or 0
	local dayKey = (date and now > 0) and date("%Y-%m-%d", now) or nil
	local charKey = self.CharKey and self:CharKey() or ""

	AppendCashflowEntry(kind or "ah_deposit", itemID, nil, nil, qty, -totalSpent, charKey, dayKey, now)
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
			local took, spent = PreviewPurchaseLot(lots, rg.itemID, qty, now)
			if took > 0 then
				plannedTakes[#plannedTakes + 1] = { itemID = rg.itemID, take = took, spent = spent }
				actualCost = actualCost + spent
				usedRealCost = true
			end
			local rem = qty - took
			if rem > 0 and allPriced then
				local unitP = self.GetReagentBestPrice and self:GetReagentBestPrice(rg.itemID)
				if not unitP then
					allPriced = false
				else
					actualCost = actualCost + unitP * rem
				end
			end
		end
	end

	local numMade = (rec.numMade and rec.numMade > 0) and rec.numMade or 1
	if #plannedTakes > 0 then
		for _, pt in ipairs(plannedTakes) do
			CommitPurchaseLot(lots, pt.itemID, pt.take, pt.spent)
		end
	end
	if allPriced and usedRealCost then
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
	local outName = GetLoadedItemName(rec.outputItemID)
	if outName then
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
		TrimCraftLog(log)
	end

	RefreshProfitLogUI()
end

function ns:GetProfitLogSummary(period, mode)
	mode = mode or self:GetProfitLogMode()
	local minTs = (period == "today") and GetRolling24hTimestamp() or 0
	local entries = {}

	if mode == "cashflow" then
		local log = EnsureCashflowLogDB()
		TrimCashflowLog(log)
		local spent = 0
		local earned = 0
		local opsTotal = 0
		for _, e in ipairs(log) do
			if (e.ts or 0) >= minTs then
				entries[#entries + 1] = e
				opsTotal = opsTotal + 1
				local amt = e.amount or 0
				if amt < 0 then
					spent = spent + (-amt)
				elseif amt > 0 then
					earned = earned + amt
				end
			end
		end
		if minTs == 0 and self.realmDB and type(self.realmDB.cashflowArchive) == "table" then
			local arch = self.realmDB.cashflowArchive
			opsTotal = opsTotal + (arch.opsTotal or 0)
			spent = spent + (arch.spent or 0)
			earned = earned + (arch.earned or 0)
		end
		return {
			mode = "cashflow",
			entries = entries,
			craftsTotal = 0,
			opsTotal = opsTotal,
			spent = spent,
			earned = earned,
			profit = earned - spent,
		}
	end

	local log = EnsureCraftLogDB()
	local craftsTotal = 0
	local opsTotal = 0
	local totalCost = 0
	local totalRev = 0
	local totalProfit = 0

	for _, e in ipairs(log) do
		if (e.ts or 0) >= minTs then
			entries[#entries + 1] = e
			opsTotal = opsTotal + 1
			if (e.kind or "craft") == "craft" then
				craftsTotal = craftsTotal + (e.count or 1)
			end
			totalCost = totalCost + (e.cost or 0)
			totalRev = totalRev + (e.revenue or 0)
			totalProfit = totalProfit + (e.profit or 0)
		end
	end
	if minTs == 0 and self.realmDB and type(self.realmDB.profitArchive) == "table" then
		local arch = self.realmDB.profitArchive
		opsTotal = opsTotal + (arch.opsTotal or 0)
		craftsTotal = craftsTotal + (arch.craftsTotal or 0)
		totalCost = totalCost + (arch.cost or 0)
		totalRev = totalRev + (arch.revenue or 0)
		totalProfit = totalProfit + (arch.profit or 0)
	end

	return {
		mode = "craft",
		entries = entries,
		craftsTotal = (craftsTotal > 0) and math.max(1, math.floor(craftsTotal + 0.5)) or 0,
		opsTotal = opsTotal,
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
		if mode == "all" then
			self.realmDB.cashflowLog = {}
			self.realmDB.cashflowArchive = nil
			self.realmDB.profitLog = {}
			self.realmDB.profitArchive = nil
		elseif mode == "cashflow" then
			self.realmDB.cashflowLog = {}
			self.realmDB.cashflowArchive = nil
		else
			self.realmDB.profitLog = {}
			self.realmDB.profitArchive = nil
		end
	end
	RefreshProfitLogUI()
	if self.Print and L["OPT_CLEAR_PROFIT_LOG_DONE"] then
		self:Print(L["OPT_CLEAR_PROFIT_LOG_DONE"])
	end
end

-------------------------------------------------------------------------------
-- Лёгкий taint-free трекинг транзакций АХ (Auctionator + списки TradeFlow),
-- продажи вендору скрафченных вещей и писем с выручкой от АХ
-------------------------------------------------------------------------------
local function IsInTradeFlowSellScope(itemID)
	if not itemID or itemID <= 0 then
		return false
	end
	local craftedItems = EnsureCraftedItemsDB()
	if (craftedItems[itemID] or 0) > 0 then
		return true
	end
	return (ns.DisenchantMatIDs and ns.DisenchantMatIDs[itemID]) == true
end

local function QueuePendingAhPost(itemID, qty, deposit, tracked)
	if not (itemID and itemID > 0 and deposit and deposit > 0) then
		return
	end
	if ahMoney == nil then
		ahMoney = GetMoney and GetMoney() or 0
	end
	local now = GetTime and GetTime() or 0
	pendingAhPosts[#pendingAhPosts + 1] = {
		itemID = itemID,
		qty = math.max(1, tonumber(qty) or 1),
		deposit = deposit,
		tracked = tracked == true,
		ts = now,
	}
	if #pendingAhPosts > 40 then
		table.remove(pendingAhPosts, 1)
	end
end

local function FindExactDepositIndices(list, target)
	-- 1. Одиночное точное совпадение (самый частый случай)
	for i = 1, #list do
		if list[i].deposit == target then
			return { i }
		end
	end
	-- 2. Префиксная сумма (пачка последовательных выставлений в одном PLAYER_MONEY)
	local prefix = 0
	for i = 1, #list do
		prefix = prefix + list[i].deposit
		if prefix == target then
			local idxs = {}
			for j = 1, i do
				idxs[j] = j
			end
			return idxs
		elseif prefix > target then
			break
		end
	end
	-- 3. Точный поиск подмножества по последним элементам (ограничен 12, чтобы исключить ложные срабатывания)
	local limit = math.min(#list, 12)
	local chosen = {}
	local function Search(pos, rem)
		if rem == 0 then
			return true
		end
		if pos > limit or rem < 0 then
			return false
		end
		local dep = list[pos].deposit
		if dep <= rem then
			chosen[#chosen + 1] = pos
			if Search(pos + 1, rem - dep) then
				return true
			end
			chosen[#chosen] = nil
		end
		return Search(pos + 1, rem)
	end
	if Search(1, target) and #chosen > 0 then
		return chosen
	end
	return nil
end

local function FlushPendingAhDeposits(spent, now)
	local kept = {}
	for _, entry in ipairs(pendingAhPosts) do
		if (now - (entry.ts or 0)) <= 3.5 then
			kept[#kept + 1] = entry
		end
	end
	pendingAhPosts = kept
	if not spent or spent <= 0 or #pendingAhPosts == 0 then
		return
	end
	local matched = FindExactDepositIndices(pendingAhPosts, spent)
	if not matched then
		return
	end
	local matchedSet = {}
	for _, idx in ipairs(matched) do
		matchedSet[idx] = true
		local entry = pendingAhPosts[idx]
		if entry and entry.tracked then
			ns:RecordCashflowExpense("ah_deposit", entry.itemID, entry.qty, entry.deposit)
		end
	end
	local remaining = {}
	for i, entry in ipairs(pendingAhPosts) do
		if not matchedSet[i] then
			remaining[#remaining + 1] = entry
		end
	end
	pendingAhPosts = remaining
end

local function InstallAhHooks()
	if ahHooksInstalled or not C_AuctionHouse then
		return
	end
	if C_AuctionHouse.StartCommoditiesPurchase or C_AuctionHouse.ConfirmCommoditiesPurchase
		or C_AuctionHouse.CancelCommoditiesPurchase or C_AuctionHouse.PlaceBid
		or C_AuctionHouse.PostItem or C_AuctionHouse.PostCommodity
	then
		ahHooksInstalled = true
	end
	if C_AuctionHouse.StartCommoditiesPurchase then
		hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, qty)
			pendingAhComm = nil
			if ns.IsSnipePurchaseActive and ns:IsSnipePurchaseActive() then
				return
			end
			if ns.OnExternalCommodityPurchase then
				ns:OnExternalCommodityPurchase()
			end
			if not IsProfitEnabled() or not HasAuctionator() then
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
	if C_AuctionHouse.ConfirmCommoditiesPurchase then
		hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, qty)
			confirmingAhComm = nil
			if ns.IsSnipePurchaseActive and ns:IsSnipePurchaseActive() then
				return
			end
			local snipeTotal = nil
			if ns.GetPendingSnipeCommodityQuote then
				local sItem, sQty, sTotal = ns:GetPendingSnipeCommodityQuote()
				if sItem == itemID and sQty == qty and sTotal and sTotal > 0 then
					snipeTotal = sTotal
				end
			end
			if ns.OnExternalCommodityPurchase then
				ns:OnExternalCommodityPurchase()
			end
			if not IsProfitEnabled() or not HasAuctionator() then
				return
			end
			if type(itemID) ~= "number" or not qty or qty <= 0 or not IsInTradeFlowAhScope(itemID) then
				return
			end
			local quotedTotal = nil
			if pendingAhComm and pendingAhComm.itemID == itemID and pendingAhComm.qty == qty and (pendingAhComm.totalPrice or 0) > 0 then
				quotedTotal = pendingAhComm.totalPrice
			elseif snipeTotal then
				quotedTotal = snipeTotal
			end
			confirmingAhComm = {
				itemID = itemID,
				qty = qty,
				totalPrice = quotedTotal,
				moneyBefore = GetMoney and GetMoney() or 0,
				spentMoney = 0,
				ts = GetTime and GetTime() or 0,
			}
		end)
	end
	if C_AuctionHouse.CancelCommoditiesPurchase then
		hooksecurefunc(C_AuctionHouse, "CancelCommoditiesPurchase", function()
			pendingAhComm = nil
		end)
	end
	if C_AuctionHouse.PlaceBid then
		hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
			pendingAhBid = nil
			if not IsProfitEnabled() or not HasAuctionator() then
				return
			end
			if ns.IsSnipePurchaseActive and ns:IsSnipePurchaseActive() then
				return
			end
			local amt = tonumber(bidAmount)
			local key = lastViewedAhItemKey
			local iid = key and key.itemID
			if not (iid and amt and amt > 0 and IsInTradeFlowAhScope(iid)) then
				return
			end
			if C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetItemSearchResultInfo then
				if not auctionID then
					return
				end
				local matched = false
				local n = C_AuctionHouse.GetNumItemSearchResults(key) or 0
				for i = 1, n do
					local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
					if info and info.auctionID == auctionID then
						matched = (info.buyoutAmount == amt)
						break
					end
				end
				if not matched then
					return
				end
			end
			pendingAhBid = {
				itemID = iid,
				amount = amt,
				moneyBefore = GetMoney and GetMoney() or 0,
				ts = GetTime and GetTime() or 0,
			}
		end)
	end
	if C_AuctionHouse.PostItem then
		hooksecurefunc(C_AuctionHouse, "PostItem", function(itemLocation, duration, quantity)
			if not IsProfitEnabled() or not HasAuctionator() or not itemLocation then
				return
			end
			if not (C_Item and C_Item.GetItemID and C_AuctionHouse.CalculateItemDeposit) then
				return
			end
			local okId, itemID = pcall(C_Item.GetItemID, itemLocation)
			if not (okId and itemID and itemID > 0) then
				return
			end
			local okDep, dep = pcall(C_AuctionHouse.CalculateItemDeposit, itemLocation, duration, quantity)
			if okDep and type(dep) == "number" and dep > 0 then
				QueuePendingAhPost(itemID, quantity, dep, IsInTradeFlowSellScope(itemID))
			end
		end)
	end
	if C_AuctionHouse.PostCommodity then
		hooksecurefunc(C_AuctionHouse, "PostCommodity", function(itemLocation, duration, quantity)
			if not IsProfitEnabled() or not HasAuctionator() or not itemLocation then
				return
			end
			if not (C_Item and C_Item.GetItemID and C_AuctionHouse.CalculateCommodityDeposit) then
				return
			end
			local okId, itemID = pcall(C_Item.GetItemID, itemLocation)
			if not (okId and itemID and itemID > 0) then
				return
			end
			local okDep, dep = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, quantity)
			if okDep and type(dep) == "number" and dep > 0 then
				QueuePendingAhPost(itemID, quantity, dep, IsInTradeFlowSellScope(itemID))
			end
		end)
	end
end

local function IsInTradeFlowVendorScope(itemID)
	if not itemID or itemID <= 0 then
		return false
	end
	if GetConsumedReagentSet()[itemID] then
		return true
	end
	if ns.VendorPrices and ns.VendorPrices[itemID] then
		return true
	end
	if GetVendorScrollSet()[itemID] then
		return true
	end
	return IsInTradeFlowAhScope(itemID)
end

local function GetMerchantSlotItemID(slot)
	if not slot then
		return nil
	end
	if GetMerchantItemID then
		local id = GetMerchantItemID(slot)
		if id and id > 0 then
			return id
		end
	end
	if GetMerchantItemLink then
		local link = GetMerchantItemLink(slot)
		local id = link and tonumber(link:match("item:(%d+)"))
		if id and id > 0 then
			return id
		end
	end
	if C_MerchantFrame and C_MerchantFrame.GetItemLink then
		local link = C_MerchantFrame.GetItemLink(slot)
		local id = link and tonumber(link:match("item:(%d+)"))
		if id and id > 0 then
			return id
		end
	end
	return nil
end

local function GetMerchantSlotInfo(slot)
	if not slot then
		return nil
	end
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(slot)
		if info then
			local canBuy = (info.isPurchasable ~= false) and not info.hasExtendedCost
			return info.price or 0, math.max(1, info.stackCount or 1), info.numAvailable or -1, canBuy
		end
	end
	if GetMerchantItemInfo then
		local _, _, price, stackSize, numAvailable, isPurchasable, _, extendedCost = GetMerchantItemInfo(slot)
		local canBuy = (isPurchasable ~= false) and not extendedCost
		return price or 0, math.max(1, stackSize or 1), numAvailable or -1, canBuy
	end
	return nil
end

local function ScanMerchantCatalog(initSnap)
	merchantCatalog = merchantCatalog or {}
	merchantBuySnap = merchantBuySnap or {}
	if initSnap and ns.GetBagCount then
		for itemID in pairs(ns.VendorPrices or {}) do
			if merchantBuySnap[itemID] == nil then
				merchantBuySnap[itemID] = ns:GetBagCount(itemID) or 0
			end
		end
		if ns.GetShoppingList then
			for _, item in ipairs(ns:GetShoppingList() or {}) do
				if item.itemID and merchantBuySnap[item.itemID] == nil then
					merchantBuySnap[item.itemID] = ns:GetBagCount(item.itemID) or 0
				end
			end
		end
	end
	if not GetMerchantNumItems then
		return
	end
	local numMerchant = GetMerchantNumItems() or 0
	for slot = 1, numMerchant do
		local itemID = GetMerchantSlotItemID(slot)
		if itemID and IsInTradeFlowVendorScope(itemID) then
			local price, stackSize, _, canBuy = GetMerchantSlotInfo(slot)
			if canBuy and price and price > 0 then
				merchantCatalog[itemID] = {
					batchPrice = price,
					stackSize = math.max(1, stackSize or 1),
				}
				if merchantBuySnap[itemID] == nil then
					merchantBuySnap[itemID] = ns.GetBagCount and ns:GetBagCount(itemID) or 0
				end
			end
		end
	end
end

local function ScanMerchantPurchases(now)
	if not merchantCatalog or not merchantBuySnap then
		return
	end
	if MerchantFrame and MerchantFrame:IsShown() then
		ScanMerchantCatalog(false)
	end
	local isOpen = (MerchantFrame and MerchantFrame:IsShown()) == true
	local recentBuy = (merchantLastBuyAt > 0) and ((now - merchantLastBuyAt) <= MERCHANT_BUY_WINDOW)
	local active = isOpen or recentBuy
	for itemID, cat in pairs(merchantCatalog) do
		local prevCnt = merchantBuySnap[itemID]
		local curCnt = ns.GetBagCount and ns:GetBagCount(itemID) or 0
		if prevCnt == nil then
			merchantBuySnap[itemID] = curCnt
		elseif curCnt > prevCnt then
			local gained = curCnt - prevCnt
			merchantBuySnap[itemID] = curCnt
			if active and cat.batchPrice and cat.batchPrice > 0 then
				local cost = math.floor((cat.batchPrice * gained / math.max(1, cat.stackSize or 1)) + 0.5)
				if cost > 0 then
					ns:RecordTradeFlowPurchase("vendor_buy", itemID, gained, cost)
				end
			end
		elseif curCnt < prevCnt then
			merchantBuySnap[itemID] = curCnt
		end
	end
	if not active then
		merchantCatalog = nil
		merchantBuySnap = nil
		merchantLastBuyAt = 0
	end
end

function ns:FlushPendingMerchantBuys()
	if not IsProfitEnabled() then
		return
	end
	ScanMerchantPurchases(GetTime and GetTime() or 0)
end

local function InstallMerchantHooks()
	if merchantHooksInstalled then
		return
	end
	if not _G.BuyMerchantItem and not _G.PickupMerchantItem then
		return
	end
	merchantHooksInstalled = true
	local function OnMerchantBuySlot(slot)
		if not IsProfitEnabled() or not slot then
			return
		end
		local now = GetTime and GetTime() or 0
		merchantLastBuyAt = now
		merchantCatalog = merchantCatalog or {}
		merchantBuySnap = merchantBuySnap or {}
		local itemID = GetMerchantSlotItemID(slot)
		if itemID and IsInTradeFlowVendorScope(itemID) then
			local price, stackSize, _, canBuy = GetMerchantSlotInfo(slot)
			if canBuy and price and price > 0 then
				merchantCatalog[itemID] = {
					batchPrice = price,
					stackSize = math.max(1, stackSize or 1),
				}
				if merchantBuySnap[itemID] == nil then
					merchantBuySnap[itemID] = ns.GetBagCount and ns:GetBagCount(itemID) or 0
				end
			end
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(0.35, function()
				if IsProfitEnabled() then
					ScanMerchantPurchases(GetTime and GetTime() or 0)
				end
			end)
			C_Timer.After(0.9, function()
				if IsProfitEnabled() then
					ScanMerchantPurchases(GetTime and GetTime() or 0)
				end
			end)
		end
	end
	if _G.BuyMerchantItem then
		hooksecurefunc("BuyMerchantItem", function(slot)
			OnMerchantBuySlot(slot)
		end)
	end
	if _G.PickupMerchantItem then
		hooksecurefunc("PickupMerchantItem", function(slot)
			OnMerchantBuySlot(slot)
		end)
	end
end

local function SnapshotMerchantBags(now)
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
	pendingMerchantMoney = { amount = 0, ts = 0 }
	pendingMerchantDrops = {}
	if not (merchantLastBuyAt > 0 and now and (now - merchantLastBuyAt) <= 1.0) then
		merchantCatalog = {}
		merchantBuySnap = {}
	end
	ScanMerchantCatalog(true)
end

local function ScanMerchantBagDelta(now, force)
	if not merchantBagSnap then
		return
	end
	if not force and not (MerchantFrame and MerchantFrame:IsShown()) then
		return
	end
	local craftedItems = EnsureCraftedItemsDB()
	local watchIDs = {}
	for itemID in pairs(merchantBagSnap) do
		watchIDs[itemID] = true
	end
	for itemID, qty in pairs(craftedItems) do
		if type(qty) == "number" and qty > 0 then
			watchIDs[itemID] = true
		end
	end
	for itemID in pairs(watchIDs) do
		local prevCnt = merchantBagSnap[itemID] or 0
		local curCnt = ns.GetBagCount and ns:GetBagCount(itemID) or 0
		if curCnt > prevCnt then
			merchantBagSnap[itemID] = curCnt
		elseif curCnt < prevCnt then
			local dropped = prevCnt - curCnt
			local capCrafted = craftedItems[itemID] or 0
			local sellQty = math.min(dropped, capCrafted)
			if sellQty > 0 then
				local unitSell = ns.GetItemSellPrice and ns:GetItemSellPrice(itemID) or 0
				if unitSell > 0 then
					pendingMerchantDrops[#pendingMerchantDrops + 1] = {
						itemID = itemID,
						count = sellQty,
						money = unitSell * sellQty,
						ts = now,
					}
				end
			end
			merchantBagSnap[itemID] = (curCnt > 0) and curCnt or nil
		end
	end
end

local function FlushPendingMerchantSales(now)
	if (now - (pendingMerchantMoney.ts or 0)) > MERCHANT_PAIR_WINDOW then
		pendingMerchantMoney.amount = 0
		pendingMerchantMoney.ts = 0
	end
	local kept = {}
	for _, entry in ipairs(pendingMerchantDrops) do
		if (now - (entry.ts or 0)) <= MERCHANT_PAIR_WINDOW then
			kept[#kept + 1] = entry
		end
	end
	pendingMerchantDrops = kept

	if (pendingMerchantMoney.amount or 0) <= 0 or #pendingMerchantDrops == 0 then
		return
	end

	local craftedItems = EnsureCraftedItemsDB()
	while (pendingMerchantMoney.amount or 0) > 0 and #pendingMerchantDrops > 0 do
		local matchIdx = nil
		for idx, entry in ipairs(pendingMerchantDrops) do
			if math.abs(entry.money - pendingMerchantMoney.amount) <= 2 then
				matchIdx = idx
				break
			end
		end
		if not matchIdx then
			for idx, entry in ipairs(pendingMerchantDrops) do
				if entry.money <= (pendingMerchantMoney.amount + 2) then
					matchIdx = idx
					break
				end
			end
		end
		if not matchIdx then
			break
		end
		local entry = table.remove(pendingMerchantDrops, matchIdx)
		local availCrafted = craftedItems[entry.itemID] or 0
		local qty = math.min(entry.count, availCrafted)
		if qty > 0 then
			local unitMoney = (entry.count > 0) and (entry.money / entry.count) or 0
			local capMoney = math.floor(unitMoney * qty + 0.5)
			local earned = math.min(capMoney, pendingMerchantMoney.amount)
			if earned > 0 then
				ns:RecordCashflowIncome("vendor_sell", entry.itemID, qty, earned)
				DecrementCraftedItem(entry.itemID, qty)
				pendingMerchantMoney.amount = math.max(0, pendingMerchantMoney.amount - earned)
			end
		end
	end
end

local function GetDisenchantMatNameMap()
	disenchantNameMap = disenchantNameMap or {}
	if disenchantMapComplete or not ns.DisenchantMatIDs then
		return disenchantNameMap
	end
	local missing = false
	for itemID in pairs(ns.DisenchantMatIDs) do
		local name = GetLoadedItemName(itemID)
		if name then
			disenchantNameMap[name] = itemID
		else
			missing = true
		end
	end
	if not missing then
		disenchantMapComplete = true
	end
	return disenchantNameMap
end

local function ResolveTrackedSellItemID(cleanName)
	if not cleanName or cleanName == "" then
		return nil
	end
	local craftedItems, craftedNames = EnsureCraftedItemsDB()
	local craftedID = craftedNames[cleanName]
	if craftedID and (craftedItems[craftedID] or 0) > 0 then
		return craftedID
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
		local _, _, _, subject, money = GetInboxHeaderInfo(i)
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
					local rawCount = tonumber(count)
					local qty = math.max(1, (rawCount and rawCount > 0 and rawCount) or suffixQty or 1)
					local key = (subject or "") .. "|" .. itemID .. "|" .. money
					counts[key] = (counts[key] or 0) + 1
					local entry = entries[key]
					if not entry then
						entries[key] = { itemID = itemID, count = qty, money = money }
					elseif qty > entry.count then
						entry.count = qty
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
			DecrementCraftedItem(entry.itemID, entry.count)
			pendingMailMoney.amount = math.max(0, pendingMailMoney.amount - earned)
			local craftedItems = EnsureCraftedItemsDB()
			if mailSellerSnap and (craftedItems[entry.itemID] or 0) <= 0 and not (ns.DisenchantMatIDs and ns.DisenchantMatIDs[entry.itemID]) then
				for k, info in pairs(mailSellerSnap.entries) do
					if info and info.itemID == entry.itemID then
						mailSellerSnap.counts[k] = nil
						mailSellerSnap.entries[k] = nil
					end
				end
			end
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
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"COMMODITY_PRICE_UPDATED",
	"COMMODITY_PRICE_UNAVAILABLE",
	"COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED",
	"MERCHANT_SHOW",
	"MERCHANT_UPDATE",
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

txFrame:SetScript("OnEvent", function(_, event, ...)
	local arg1, arg2, arg3 = ...
	local now = GetTime and GetTime() or 0
	if event == "PLAYER_LOGIN" or event == "AUCTION_HOUSE_SHOW" then
		InstallAhHooks()
	end
	if event == "PLAYER_LOGIN" or event == "MERCHANT_SHOW" then
		InstallMerchantHooks()
	end
	if not IsProfitEnabled() then
		pendingAhComm = nil
		confirmingAhComm = nil
		pendingAhBid = nil
		ahMoney = nil
		pendingAhPosts = {}
		lastViewedAhItemKey = nil
		merchantBagSnap = nil
		merchantCatalog = nil
		merchantBuySnap = nil
		merchantLastBuyAt = 0
		pendingMerchantMoney.amount = 0
		pendingMerchantDrops = {}
		mailSellerSnap = nil
		pendingMailMoney.amount = 0
		pendingMailItems = {}
		return
	end
	if event == "PLAYER_LOGIN" then
		return
	elseif event == "AUCTION_HOUSE_SHOW" then
		ahMoney = GetMoney and GetMoney() or 0
		pendingAhPosts = {}
		return
	elseif event == "AUCTION_HOUSE_CLOSED" then
		pendingAhComm = nil
		confirmingAhComm = nil
		pendingAhBid = nil
		ahMoney = nil
		pendingAhPosts = {}
		lastViewedAhItemKey = nil
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		lastViewedAhItemKey = nil
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
		if type(arg1) == "table" and arg1.itemID and arg1.itemID > 0 then
			lastViewedAhItemKey = arg1
		end
	elseif event == "COMMODITY_PRICE_UPDATED" then
		if pendingAhComm and (now - (pendingAhComm.ts or 0)) <= 30 then
			local unitP = tonumber(arg1) or 0
			local totalP = tonumber(arg2) or (unitP * pendingAhComm.qty)
			if totalP > 0 then
				pendingAhComm.totalPrice = totalP
				pendingAhComm.ts = now
			end
		else
			pendingAhComm = nil
		end
	elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
		pendingAhComm = nil
	elseif event == "COMMODITY_PURCHASE_FAILED" then
		pendingAhComm = nil
		confirmingAhComm = nil
	elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
		local c = confirmingAhComm
		confirmingAhComm = nil
		local p = pendingAhComm
		pendingAhComm = nil
		if ns.IsSnipePurchaseActive and ns:IsSnipePurchaseActive() then
			return
		end
		if c and (now - (c.ts or 0)) <= 15 then
			local cost = (c.spentMoney and c.spentMoney > 0) and c.spentMoney or (c.totalPrice or 0)
			if cost <= 0 and c.moneyBefore and GetMoney then
				local diff = c.moneyBefore - (GetMoney() or 0)
				if diff > 0 then
					cost = diff
				end
			end
			if cost > 0 then
				ns:RecordTradeFlowPurchase("ah_buy", c.itemID, c.qty, cost)
				return
			end
		end
		if p and (now - (p.ts or 0)) <= 60 and (p.totalPrice or 0) > 0 then
			ns:RecordTradeFlowPurchase("ah_buy", p.itemID, p.qty, p.totalPrice)
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if issecretvalue and (issecretvalue(arg1) or issecretvalue(arg3)) then
			return
		end
		if arg1 == "player" and tonumber(arg3) == 13262 then
			lastDisenchantAt = now
		end
	elseif event == "CHAT_MSG_LOOT" then
		if issecretvalue and issecretvalue(arg1) then
			return
		end
		if lastDisenchantAt > 0 and (now - lastDisenchantAt) <= 3.0 and type(arg1) == "string" then
			local lootGuid = select(12, ...)
			if issecretvalue and issecretvalue(lootGuid) then
				lootGuid = nil
			end
			local playerGuid = UnitGUID and UnitGUID("player")
			if issecretvalue and issecretvalue(playerGuid) then
				playerGuid = nil
			end
			if not (lootGuid and lootGuid ~= "" and playerGuid and playerGuid ~= "" and lootGuid ~= playerGuid) then
				local itemID = tonumber(arg1:match("item:(%d+)"))
				if itemID and itemID > 0 and ns.DisenchantMatIDs and ns.DisenchantMatIDs[itemID] then
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
		end
	elseif event == "MERCHANT_SHOW" then
		SnapshotMerchantBags(now)
	elseif event == "MERCHANT_UPDATE" then
		if MerchantFrame and MerchantFrame:IsShown() then
			ScanMerchantCatalog(false)
		end
	elseif event == "MERCHANT_CLOSED" then
		ScanMerchantPurchases(now)
		ScanMerchantBagDelta(now, true)
		FlushPendingMerchantSales(now)
		merchantBagSnap = nil
		pendingMerchantMoney = { amount = 0, ts = 0 }
		pendingMerchantDrops = {}
		if not (merchantLastBuyAt > 0 and (now - merchantLastBuyAt) <= MERCHANT_BUY_WINDOW) then
			merchantCatalog = nil
			merchantBuySnap = nil
			merchantLastBuyAt = 0
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		if (MerchantFrame and MerchantFrame:IsShown()) or (merchantLastBuyAt > 0 and (now - merchantLastBuyAt) <= MERCHANT_BUY_WINDOW) then
			ScanMerchantPurchases(now)
		end
		if MerchantFrame and MerchantFrame:IsShown() and merchantBagSnap then
			ScanMerchantBagDelta(now, false)
			FlushPendingMerchantSales(now)
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
		local curM = GetMoney and GetMoney() or 0
		local commSpentAmt = 0
		if confirmingAhComm then
			if (now - (confirmingAhComm.ts or 0)) > 15 then
				confirmingAhComm = nil
			elseif curM < (confirmingAhComm.moneyBefore or 0) then
				local diff = confirmingAhComm.moneyBefore - curM
				if diff > (confirmingAhComm.spentMoney or 0) then
					commSpentAmt = diff - (confirmingAhComm.spentMoney or 0)
					confirmingAhComm.spentMoney = diff
				end
			end
		end
		local bidMatchedAmt = 0
		if pendingAhBid then
			local b = pendingAhBid
			if (now - (b.ts or 0)) > 2.5 then
				pendingAhBid = nil
			elseif (b.moneyBefore - curM) == b.amount then
				pendingAhBid = nil
				bidMatchedAmt = b.amount
				ns:RecordTradeFlowPurchase("ah_buy", b.itemID, 1, b.amount)
			end
		end
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			local ahSpent = (ahMoney ~= nil and ahMoney > curM) and (ahMoney - curM - bidMatchedAmt - commSpentAmt) or 0
			ahMoney = curM
			if ahSpent > 0 and #pendingAhPosts > 0 then
				FlushPendingAhDeposits(ahSpent, now)
			end
		end
		if MerchantFrame and MerchantFrame:IsShown() and merchantBagSnap then
			if curM > merchantMoney then
				pendingMerchantMoney.amount = (pendingMerchantMoney.amount or 0) + (curM - merchantMoney)
				pendingMerchantMoney.ts = now
			elseif curM < merchantMoney then
				merchantLastBuyAt = now
			end
			merchantMoney = curM
			FlushPendingMerchantSales(now)
			ScanMerchantPurchases(now)
		end
		if MailFrame and MailFrame:IsShown() then
			if curM > mailMoney then
				pendingMailMoney.amount = (pendingMailMoney.amount or 0) + (curM - mailMoney)
				pendingMailMoney.ts = now
			end
			mailMoney = curM
			FlushPendingMailSales(now)
		end
	end
end)
