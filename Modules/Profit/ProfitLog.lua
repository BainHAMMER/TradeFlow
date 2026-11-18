local _, ns = ...

-------------------------------------------------------------------------------
-- Журнал заработка (Лог крафта): снимок себестоимости, выручки и профита
-------------------------------------------------------------------------------
local MAX_LOG_ENTRIES = 200
local COALESCE_SECONDS = 30

local function EnsureLogDB()
	if not ns.realmDB then
		return {}
	end
	ns.realmDB.profitLog = ns.realmDB.profitLog or {}
	return ns.realmDB.profitLog
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
				if e.outItemID == rg.itemID and e.recipeID ~= rec.recipeID
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
						e.count = math.max(1, math.ceil(rem / perCraft))
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
	if isSubcraft or not spellID or spellID <= 0 then
		return
	end
	local rec = self.GetRecipeRecord and self:GetRecipeRecord(spellID)
	if not rec or not rec.reagents or #rec.reagents == 0 or not rec.outputItemID or rec.outputItemID <= 0 then
		return
	end
	local craftCost, outVal, _, _, outSource, alts = self:GetRecipeEconomy(spellID)
	if ns.EvalRecipeChannel and craftCost ~= nil then
		local evalOut, _, evalSrc = ns.EvalRecipeChannel(rec, craftCost, alts, "all")
		if evalOut ~= nil then
			outVal = evalOut
			outSource = evalSrc
		end
	end
	if craftCost == nil or outVal == nil then
		return
	end

	local unitCost = craftCost
	local unitRev = outVal
	local unitProfit = unitRev - unitCost
	local src = outSource or "unknown"
	local now = time and time() or 0
	local dayKey = (date and now > 0) and date("%Y-%m-%d", now) or nil
	local charKey = self.CharKey and self:CharKey() or ""

	local log = EnsureLogDB()
	ConsumeIntermediateFromLog(log, rec, charKey, dayKey)
	local top = log[1]
	if top and top.recipeID == spellID and top.charKey == charKey and top.source == src
		and top.dayKey == dayKey
		and now >= (top.ts or 0) and (now - (top.ts or 0)) <= COALESCE_SECONDS
	then
		top.count = (top.count or 1) + 1
		if top.itemQty ~= nil then
			top.itemQty = top.itemQty + ((rec.numMade and rec.numMade > 0) and rec.numMade or 1)
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
			skillLine = rec.skillLine,
			recipeID = spellID,
			outItemID = rec.outputItemID,
			count = 1,
			cost = unitCost,
			revenue = unitRev,
			profit = unitProfit,
			source = src,
		})
		while #log > MAX_LOG_ENTRIES do
			table.remove(log)
		end
	end

	if self.modules and self.modules.byId and self.modules.byId["profit"] then
		local mod = self.modules.byId["profit"]
		if mod.view and mod.view:IsVisible() and mod.OnRefresh then
			mod:OnRefresh()
		end
	end
end

function ns:GetProfitLogSummary(period)
	local log = EnsureLogDB()
	local minTs = (period == "today") and GetTodayStartTimestamp() or 0
	local entries = {}
	local craftsTotal = 0
	local totalCost = 0
	local totalRev = 0
	local totalProfit = 0

	for _, e in ipairs(log) do
		if (e.ts or 0) >= minTs then
			entries[#entries + 1] = e
			craftsTotal = craftsTotal + (e.count or 1)
			totalCost = totalCost + (e.cost or 0)
			totalRev = totalRev + (e.revenue or 0)
			totalProfit = totalProfit + (e.profit or 0)
		end
	end

	return {
		entries = entries,
		craftsTotal = craftsTotal,
		cost = totalCost,
		revenue = totalRev,
		profit = totalProfit,
	}
end

function ns:ClearProfitLog()
	if self.realmDB then
		self.realmDB.profitLog = {}
	end
	if self.modules and self.modules.byId and self.modules.byId["profit"] then
		local mod = self.modules.byId["profit"]
		if mod.view and mod.view:IsVisible() and mod.OnRefresh then
			mod:OnRefresh()
		end
	end
end
