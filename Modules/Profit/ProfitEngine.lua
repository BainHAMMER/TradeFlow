local _, ns = ...

-------------------------------------------------------------------------------
-- Движок сканера профита по всем изученным профессиям персонажа (и альтов)
-------------------------------------------------------------------------------
local profitCache = nil
local profitCacheKey = nil
local profitCachePriceRev = -1
local profitCacheInvRev = -1

local function EvalRecipeForChannel(recipeID, craftCost, outputValue, netProfit, outputSource, alts, channel)
	if not craftCost then
		return nil
	end
	if channel == "safe" then
		local vendorVal = (alts and alts.vendor) or 0
		local deVal = (alts and alts.disenchant) or 0
		if deVal >= vendorVal and deVal > 0 then
			return deVal, deVal - craftCost, "disenchant"
		elseif vendorVal > 0 then
			return vendorVal, vendorVal - craftCost, "vendor"
		end
		return nil
	elseif channel == "ah" then
		local ahVal = alts and alts.ah
		if ahVal and ahVal > 0 then
			return ahVal, ahVal - craftCost, "ah"
		end
		return nil
	end
	if outputValue and netProfit then
		return outputValue, netProfit, outputSource
	end
	return nil
end

local function GetMaxAuctionAgeDays(outItemID, outSource, breakdown)
	local maxAge = nil
	if outSource == "ah" and outItemID then
		local _, _, age = ns:GetAuctionPrice(outItemID)
		if age then
			maxAge = age
		end
	end
	if breakdown then
		for _, b in ipairs(breakdown) do
			if b.source == "ah" and b.itemID then
				local _, _, age = ns:GetAuctionPrice(b.itemID)
				if age and (not maxAge or age > maxAge) then
					maxAge = age
				end
			end
		end
	end
	return maxAge
end

function ns.InvalidateProfitCache()
	profitCache = nil
	profitCacheKey = nil
end

-- Возвращает отсортированный список прибыльных рецептов:
-- { recipeID, skillLine, name, icon, outItemID, qualityHex, isAlt, ownerName,
--   craftCost, outputValue, profit, margin, source, ageDays, craftNow }
function ns:BuildProfitList(opts)
	opts = opts or {}
	local channel = opts.channel or "all" -- "all" | "safe" | "ah"
	local sortBy = opts.sortBy or "profit" -- "profit" | "margin" | "craftable"
	local profFilter = opts.profFilter or 0
	local onlyOwned = opts.onlyOwned == true
	local includeAlts = opts.includeAlts == true
	local freshOnly = opts.freshOnly == true

	local key = table.concat({
		channel,
		sortBy,
		tostring(profFilter),
		onlyOwned and "1" or "0",
		includeAlts and "1" or "0",
		freshOnly and "1" or "0",
	}, "|")
	local curPriceRev = self.GetPriceRevision and self:GetPriceRevision() or 0
	local curInvRev = self.invRev or 0
	if profitCache and profitCacheKey == key and profitCachePriceRev == curPriceRev and profitCacheInvRev == curInvRev then
		return profitCache
	end

	local collected = {}
	-- 1. Текущий персонаж: все изученные профессии
	for sl in pairs(self.playerProfessions or {}) do
		if profFilter == 0 or profFilter == sl then
			local list = self.RecipesBySkill and self.RecipesBySkill[sl]
			if list then
				for _, recipeID in ipairs(list) do
					if self:IsRecipeLearned(recipeID) then
						collected[recipeID] = {
							recipeID = recipeID,
							skillLine = sl,
							isAlt = false,
						}
					end
				end
			end
		end
	end

	-- 2. Альты на текущем реалме (опционально)
	if includeAlts and self.realmDB and self.realmDB.chars then
		local myKey = self:CharKey()
		for charName, cData in pairs(self.realmDB.chars) do
			if charName ~= myKey and cData and cData.learned then
				for recipeID, isLearned in pairs(cData.learned) do
					if isLearned and not collected[recipeID] then
						local rec = self:GetRecipeRecord(recipeID)
						local sl = rec and rec.skillLine
						if sl and (profFilter == 0 or profFilter == sl) then
							collected[recipeID] = {
								recipeID = recipeID,
								skillLine = sl,
								isAlt = true,
								ownerName = charName,
							}
						end
					end
				end
			end
		end
	end

	local entries = {}
	for recipeID, meta in pairs(collected) do
		local craftCost, outVal, netProfit, breakdown, outSource, alts = self:GetRecipeEconomy(recipeID)
		local evalOut, evalProfit, evalSource = EvalRecipeForChannel(recipeID, craftCost, outVal, netProfit, outSource, alts, channel)
		if evalProfit and evalProfit > 0 then
			local name, icon, outItemID, _, _, hex = self:GetRecipeDisplay(recipeID)
			local ageDays = GetMaxAuctionAgeDays(outItemID, evalSource, breakdown)
			local passFresh = (not freshOnly) or (not ageDays or ageDays <= 3)
			if passFresh then
				local craftNow = 0
				if not meta.isAlt and self.GetRecipeCraftCounts then
					local direct, withCraft, _, _, withBank = self:GetRecipeCraftCounts(recipeID)
					craftNow = math.max(direct or 0, withCraft or 0, withBank or 0)
				end
				if not onlyOwned or craftNow > 0 then
					local margin = (craftCost and craftCost > 0) and math.floor((evalProfit / craftCost) * 100 + 0.5) or 999
					entries[#entries + 1] = {
						recipeID = recipeID,
						skillLine = meta.skillLine,
						name = name,
						icon = icon,
						outItemID = outItemID,
						qualityHex = hex,
						isAlt = meta.isAlt,
						ownerName = meta.ownerName,
						craftCost = craftCost,
						outputValue = evalOut,
						profit = evalProfit,
						margin = margin,
						source = evalSource,
						ageDays = ageDays,
						craftNow = craftNow,
					}
				end
			end
		end
	end

	table.sort(entries, function(a, b)
		if sortBy == "margin" then
			if a.margin ~= b.margin then
				return a.margin > b.margin
			end
		elseif sortBy == "craftable" then
			if a.craftNow ~= b.craftNow then
				return a.craftNow > b.craftNow
			end
		end
		if a.profit ~= b.profit then
			return a.profit > b.profit
		end
		if a.margin ~= b.margin then
			return a.margin > b.margin
		end
		return a.recipeID < b.recipeID
	end)

	profitCache = entries
	profitCacheKey = key
	profitCachePriceRev = curPriceRev
	profitCacheInvRev = curInvRev
	return entries
end
