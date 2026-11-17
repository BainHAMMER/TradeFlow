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

function ns:RecordCraftProfit(spellID)
	if not spellID or spellID <= 0 then
		return
	end
	local rec = self.GetRecipeRecord and self:GetRecipeRecord(spellID)
	if not rec or not rec.reagents or #rec.reagents == 0 or not rec.outputItemID or rec.outputItemID <= 0 then
		return
	end
	local craftCost, outVal, _, _, outSource = self:GetRecipeEconomy(spellID)
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
	local top = log[1]
	if top and top.recipeID == spellID and top.charKey == charKey and top.source == src
		and top.dayKey == dayKey
		and now >= (top.ts or 0) and (now - (top.ts or 0)) <= COALESCE_SECONDS
	then
		top.count = (top.count or 1) + 1
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
