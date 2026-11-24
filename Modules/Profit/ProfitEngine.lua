local _, ns = ...

-------------------------------------------------------------------------------
-- Движок сканера профита по всем изученным профессиям персонажа (и альтов)
-------------------------------------------------------------------------------
local AUCTION_CUT = ns.AUCTION_CUT or 0.05
local MIN_CRAFT_TIME = 1.0 -- минимальное время каста для защиты от деления на 0 при мгновенных крафтах
local DISENCHANT_SPELL_ID = 13262
local DEFAULT_DISENCHANT_TIME = 3.0

local function GetDisenchantCastTime()
	local ct = ns.GetRecipeCastTime and ns:GetRecipeCastTime(DISENCHANT_SPELL_ID)
	if type(ct) == "number" and ct > 0 then
		return ct
	end
	return DEFAULT_DISENCHANT_TIME
end
local profitCache = nil
local profitCacheKey = nil
local profitCachePriceRev = -1
local profitCacheInvRev = -1

local function EvalRecipeForChannel(rec, craftCost, alts, channel)
	if not craftCost then
		return nil
	end
	local vendorVal = (alts and alts.vendor) or 0
	local deVal = (alts and alts.disenchant) or 0
	local ahVal = (alts and alts.ah) or 0
	if ahVal == 0 and rec and rec.outputItemID and rec.outputItemID > 0 then
		local ahUnit = ns:GetAuctionPrice(rec.outputItemID)
		if ahUnit and ahUnit > 0 then
			ahVal = math.floor(ahUnit * (rec.numMade or 1) * (1 - AUCTION_CUT) + 0.5)
		end
	end

	if channel == "safe" then
		-- При равенстве побеждает торговец (как в GetRecipeEconomy)
		if deVal > vendorVal and deVal > 0 then
			return deVal, deVal - craftCost, "disenchant"
		elseif vendorVal > 0 then
			return vendorVal, vendorVal - craftCost, "vendor"
		end
		return nil
	elseif channel == "ah" then
		if ahVal > 0 then
			return ahVal, ahVal - craftCost, "ah"
		end
		return nil
	end

	local bestVal = 0
	local bestSrc = nil
	if vendorVal > bestVal then
		bestVal = vendorVal
		bestSrc = "vendor"
	end
	if ahVal > bestVal then
		bestVal = ahVal
		bestSrc = "ah"
	end
	if deVal > bestVal then
		bestVal = deVal
		bestSrc = "disenchant"
	end
	if bestSrc then
		return bestVal, bestVal - craftCost, bestSrc
	end
	return nil
end
ns.EvalRecipeChannel = EvalRecipeForChannel

local function MergeAge(curMax, itemID)
	if not itemID then
		return curMax
	end
	local _, _, age = ns:GetAuctionPrice(itemID)
	if age and (not curMax or age > curMax) then
		return age
	end
	return curMax
end

local function CollectBreakdownMaxAge(curMax, breakdown, visiting)
	if not breakdown then
		return curMax
	end
	for _, b in ipairs(breakdown) do
		if b.source == "ah" and b.itemID then
			curMax = MergeAge(curMax, b.itemID)
		elseif b.source == "craft" and b.subRecipeID and not visiting[b.subRecipeID] then
			visiting[b.subRecipeID] = true
			local _, _, _, subBreakdown = ns:GetRecipeEconomy(b.subRecipeID)
			curMax = CollectBreakdownMaxAge(curMax, subBreakdown, visiting)
			visiting[b.subRecipeID] = nil
		end
	end
	return curMax
end

local function GetMaxAuctionAgeDays(outItemID, outSource, breakdown)
	local maxAge = nil
	if outSource == "ah" and outItemID then
		maxAge = MergeAge(maxAge, outItemID)
	elseif outSource == "disenchant" and outItemID and ns.GetItemDisenchantInfo then
		local _, yields = ns:GetItemDisenchantInfo(outItemID)
		if yields then
			for _, y in ipairs(yields) do
				maxAge = MergeAge(maxAge, y.itemID)
			end
		end
	end
	return CollectBreakdownMaxAge(maxAge, breakdown, {})
end

-- Оценивает минимальный score = cost + lambda * time для 1 ед. предмета itemID
-- при заданной ставке lambda (меди/сек). Возвращает: score, cost, time, subRecipeID (nil = покупка)
local function EvalItemForRate(itemID, lambda, visiting, memo)
	local canMemo = (next(visiting) == nil)
	if canMemo and memo[itemID] then
		local m = memo[itemID]
		return m[1], m[2], m[3], m[4]
	end

	local vendorPrice = ns:GetVendorPrice(itemID)
	if vendorPrice then
		if canMemo then
			memo[itemID] = { vendorPrice, vendorPrice, 0, nil }
		end
		return vendorPrice, vendorPrice, 0, nil
	end

	local buyPrice = ns:GetAuctionPrice(itemID)
	local bestScore = buyPrice
	local bestCost = buyPrice
	local bestTime = 0
	local bestRecipeID = nil

	if not visiting[itemID] then
		local producers = ns.ItemProducedBy and ns.ItemProducedBy[itemID]
		if producers and #producers > 0 then
			visiting[itemID] = true
			for _, childRecipeID in ipairs(producers) do
				if ns:IsRecipeLearned(childRecipeID) then
					local rec = ns:GetRecipeRecord(childRecipeID)
					if rec and #rec.reagents > 0 and (rec.numMade or 1) > 0 then
						local childCast = ns.GetRecipeCastTime and ns:GetRecipeCastTime(childRecipeID)
						if childCast ~= nil then
							local sumCost, sumTime, okAll = 0, childCast, true
							for _, r in ipairs(rec.reagents) do
								if visiting[r.itemID] then
									okAll = false
									break
								end
								local _, rCost, rTime = EvalItemForRate(r.itemID, lambda, visiting, memo)
								if not rCost then
									okAll = false
									break
								end
								sumCost = sumCost + rCost * r.quantity
								sumTime = sumTime + rTime * r.quantity
							end
							if okAll then
								local unitCost = sumCost / rec.numMade
								local unitTime = sumTime / rec.numMade
								local score = unitCost + lambda * unitTime
								if not bestScore or score < bestScore then
									bestScore = score
									bestCost = unitCost
									bestTime = unitTime
									bestRecipeID = childRecipeID
								end
							end
						end
					end
				end
			end
			visiting[itemID] = nil
		end
	end

	if canMemo then
		memo[itemID] = { bestScore, bestCost, bestTime, bestRecipeID }
	end
	return bestScore, bestCost, bestTime, bestRecipeID
end

-- Находит точный план «купить vs крафтить» для максимизации прибыли в час (алгоритм Динкельбаха).
-- Учитывает суммарное время крафта самого рецепта и всех выбранных промежуточных этапов.
local function EvaluateGoldPerHour(recipeID, evalOut, outItemID, outSource)
	local rec = ns:GetRecipeRecord(recipeID)
	local rootCast = ns.GetRecipeCastTime and ns:GetRecipeCastTime(recipeID)
	if not rec or not rec.reagents or #rec.reagents == 0 or rootCast == nil then
		return nil
	end

	local baseTime = rootCast
	if outSource == "disenchant" then
		baseTime = baseTime + GetDisenchantCastTime() * math.max(1, rec.numMade or 1)
	end

	local lambda = 0
	local bestLambda = 0
	local bestCost, bestTime, bestChoices

	for _ = 1, 6 do
		local memo = {}
		local choices = {}
		local sumCost, sumTime, okAll = 0, baseTime, true
		for _, r in ipairs(rec.reagents) do
			local _, rCost, rTime, rSub = EvalItemForRate(r.itemID, lambda, {}, memo)
			if not rCost then
				okAll = false
				break
			end
			sumCost = sumCost + rCost * r.quantity
			sumTime = sumTime + rTime * r.quantity
			choices[r.itemID] = rSub
		end
		if not okAll then
			return nil
		end

		local effTime = math.max(MIN_CRAFT_TIME, sumTime)
		local profit = evalOut - sumCost
		bestCost = sumCost
		bestTime = effTime
		bestChoices = choices
		bestLambda = lambda

		if profit <= 0 then
			break
		end
		local newLambda = profit / effTime
		if math.abs(newLambda - lambda) <= 0.01 then
			break
		end
		lambda = newLambda
	end

	local gphCost = math.floor(bestCost + 0.5)
	local gphProfit = evalOut - gphCost
	if gphProfit <= 0 then
		return nil
	end

	-- Собираем полный план решений для QueueAddRecipe и список реагентов, которые выгоднее купить вместо крафта
	local craftPlan = {}
	local buyInstead = {}
	local maxAge = nil
	if outSource == "ah" and outItemID then
		maxAge = MergeAge(maxAge, outItemID)
	elseif outSource == "disenchant" and outItemID and ns.GetItemDisenchantInfo then
		local _, yields = ns:GetItemDisenchantInfo(outItemID)
		if yields then
			for _, y in ipairs(yields) do
				maxAge = MergeAge(maxAge, y.itemID)
			end
		end
	end

	local seenPlan = {}
	local function CollectPlan(rList, visiting)
		for _, r in ipairs(rList) do
			local itemID = r.itemID
			if not seenPlan[itemID] then
				seenPlan[itemID] = true
				local chosenSub = bestChoices[itemID]
				if chosenSub == nil then
					local memoTmp = {}
					local _, _, _, sub = EvalItemForRate(itemID, bestLambda, {}, memoTmp)
					chosenSub = sub
				end
				local producers = ns.ItemProducedBy and ns.ItemProducedBy[itemID]
				local hasLearnedProducer = false
				if producers then
					for _, pID in ipairs(producers) do
						if ns:IsRecipeLearned(pID) then
							hasLearnedProducer = true
							break
						end
					end
				end
				if chosenSub then
					craftPlan[itemID] = chosenSub
					local subRec = ns:GetRecipeRecord(chosenSub)
					if subRec and subRec.reagents and not visiting[chosenSub] then
						visiting[chosenSub] = true
						CollectPlan(subRec.reagents, visiting)
						visiting[chosenSub] = nil
					end
				else
					if hasLearnedProducer and not ns:IsVendorItem(itemID) then
						craftPlan[itemID] = false
						buyInstead[#buyInstead + 1] = itemID
					end
					if not ns:IsVendorItem(itemID) then
						maxAge = MergeAge(maxAge, itemID)
					end
				end
			end
		end
	end
	CollectPlan(rec.reagents, { [recipeID] = true })

	local gph = math.floor((gphProfit / bestTime) * 3600 + 0.5)
	local gphMargin = (gphCost > 0) and math.floor((gphProfit / gphCost) * 100 + 0.5) or 999
	return {
		gph = gph,
		gphCost = gphCost,
		gphProfit = gphProfit,
		gphTime = bestTime,
		gphMargin = gphMargin,
		craftPlan = craftPlan,
		buyInstead = buyInstead,
		ageDays = maxAge,
	}
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
	local includeTrainer = opts.includeTrainer == true
	local includeVendor = opts.includeVendor == true
	local includeOther = opts.includeOther == true
	local rawFaction = UnitFactionGroup and UnitFactionGroup("player") or nil
	local playerFaction = (rawFaction == "Alliance" and "A") or (rawFaction == "Horde" and "H") or nil

	local key = table.concat({
		tostring(self.lang or "ru"),
		channel,
		sortBy,
		tostring(profFilter),
		onlyOwned and "1" or "0",
		includeAlts and "1" or "0",
		freshOnly and "1" or "0",
		includeTrainer and "1" or "0",
		includeVendor and "1" or "0",
		includeOther and "1" or "0",
		tostring(playerFaction or ""),
	}, "|")
	local curPriceRev = self.GetPriceRevision and self:GetPriceRevision() or 0
	local curInvRev = self.invRev or 0
	if profitCache and profitCacheKey == key and profitCachePriceRev == curPriceRev and profitCacheInvRev == curInvRev then
		return profitCache
	end

	local includeAnyUnlearned = includeTrainer or includeVendor or includeOther
	local collected = {}
	-- 1. Текущий персонаж: изученные (+ выбранные неизученные) рецепты активных профессий
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
					elseif includeAnyUnlearned and self.ClassifyUnlearnedRecipe then
						local srcKind, reqSkill, baseFee, scrollItemID = self:ClassifyUnlearnedRecipe(recipeID, playerFaction)
						if (srcKind == "trainer" and includeTrainer)
							or (srcKind == "vendor" and includeVendor)
							or (srcKind == "other" and includeOther)
						then
							collected[recipeID] = {
								recipeID = recipeID,
								skillLine = sl,
								isAlt = false,
								unlearnedSource = srcKind,
								reqSkill = reqSkill or 1,
								acquireFee = baseFee,
								scrollItemID = scrollItemID,
							}
						end
					end
				end
			end
		end
	end
	for recipeID, live in pairs(self.liveRecipes or {}) do
		if live and live.learned and not collected[recipeID] then
			local sl = live.skillLine
			if sl and self.playerProfessions and self.playerProfessions[sl] and (profFilter == 0 or profFilter == sl) then
				collected[recipeID] = {
					recipeID = recipeID,
					skillLine = sl,
					isAlt = false,
				}
			end
		end
	end

	-- 2. Альты на текущем реалме (детерминированный обход)
	if includeAlts and self.realmDB and self.realmDB.chars then
		local myKey = self:CharKey()
		local charNames = {}
		for charName in pairs(self.realmDB.chars) do
			if charName ~= myKey then
				charNames[#charNames + 1] = charName
			end
		end
		table.sort(charNames)
		for _, charName in ipairs(charNames) do
			local cData = self.realmDB.chars[charName]
			if cData and cData.learned then
				for recipeID, isLearned in pairs(cData.learned) do
					if isLearned and (not collected[recipeID] or collected[recipeID].unlearnedSource) then
						local rec = self:GetRecipeRecord(recipeID)
						local sl = rec and rec.skillLine
						local hasProf = not cData.professions or (sl and cData.professions[sl] ~= nil)
						if sl and hasProf and (profFilter == 0 or profFilter == sl) then
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
		local rec = self:GetRecipeRecord(recipeID)
		local craftCost, _, _, breakdown, _, alts = self:GetRecipeEconomy(recipeID)
		local evalOut, evalProfit, evalSource = EvalRecipeForChannel(rec, craftCost, alts, channel)
		if evalProfit and evalProfit > 0 then
			local name, icon, outItemID, _, _, hex = self:GetRecipeDisplay(recipeID)
			local gphInfo = (sortBy == "gph") and EvaluateGoldPerHour(recipeID, evalOut, outItemID, evalSource) or nil
			if sortBy == "gph" and evalSource == "disenchant" and (channel == "all" or channel == "safe") and alts then
				local altOut, altSrc = 0, nil
				if (alts.vendor or 0) > altOut then
					altOut = alts.vendor
					altSrc = "vendor"
				end
				if channel == "all" then
					local ahVal = alts.ah or 0
					if ahVal == 0 and outItemID and outItemID > 0 then
						local ahUnit = self:GetAuctionPrice(outItemID)
						if ahUnit and ahUnit > 0 then
							ahVal = math.floor(ahUnit * (rec.numMade or 1) * (1 - AUCTION_CUT) + 0.5)
						end
					end
					if ahVal > altOut then
						altOut = ahVal
						altSrc = "ah"
					end
				end
				if altSrc and altOut > 0 then
					local altGph = EvaluateGoldPerHour(recipeID, altOut, outItemID, altSrc)
					if altGph and altGph.gph and (not gphInfo or not gphInfo.gph or altGph.gph > gphInfo.gph) then
						gphInfo = altGph
						evalOut = altOut
						evalProfit = altOut - craftCost
						evalSource = altSrc
					end
				end
			end
			local ageDays = gphInfo and gphInfo.ageDays or GetMaxAuctionAgeDays(outItemID, evalSource, breakdown)
			local passFresh = (not freshOnly) or (not ageDays or ageDays <= 3)
			if passFresh then
				local craftNow = 0
				if not meta.isAlt and not meta.unlearnedSource and self.GetRecipeCraftCounts then
					local direct, withCraft, _, _, withBank = self:GetRecipeCraftCounts(recipeID)
					craftNow = math.max(direct or 0, withCraft or 0, withBank or 0)
				end
				if not onlyOwned or craftNow > 0 then
					local profRank = (self.playerProfessions and self.playerProfessions[meta.skillLine] and self.playerProfessions[meta.skillLine].rank) or 0
					local canLearnNow = (not meta.unlearnedSource) or (profRank >= (meta.reqSkill or 1))
					local acquireFee = meta.acquireFee
					if meta.unlearnedSource == "other" and meta.scrollItemID and self.GetAuctionPrice then
						acquireFee = self:GetAuctionPrice(meta.scrollItemID)
					end
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
						unlearnedSource = meta.unlearnedSource,
						reqSkill = meta.reqSkill,
						acquireFee = acquireFee,
						scrollItemID = meta.scrollItemID,
						canLearnNow = canLearnNow,
						craftCost = craftCost,
						outputValue = evalOut,
						profit = evalProfit,
						margin = margin,
						source = evalSource,
						ageDays = ageDays,
						craftNow = craftNow,
						gph = gphInfo and gphInfo.gph or nil,
						gphCost = gphInfo and gphInfo.gphCost or nil,
						gphProfit = gphInfo and gphInfo.gphProfit or nil,
						gphTime = gphInfo and gphInfo.gphTime or nil,
						gphMargin = gphInfo and gphInfo.gphMargin or nil,
						gphCraftPlan = gphInfo and gphInfo.craftPlan or nil,
						gphBuyInstead = gphInfo and gphInfo.buyInstead or nil,
					}
				end
			end
		end
	end

	table.sort(entries, function(a, b)
		if sortBy == "gph" then
			local ga, gb = a.gph or -1, b.gph or -1
			if ga ~= gb then
				return ga > gb
			end
		elseif sortBy == "margin" then
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
