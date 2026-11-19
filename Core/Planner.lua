local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Калькулятор шанса скиллапа (SkillUp) и построение оптимального маршрута прокачки
-------------------------------------------------------------------------------

-- Возвращает пороги { orange, yellow, green, grey } для рецепта
function ns:GetRecipeThresholds(recipeID)
	if not recipeID then
		return nil
	end
	return self.Thresholds and self.Thresholds[recipeID] or nil
end

-- Формула шанса скиллапа Classic / WoW Forever:
-- Оранжевый (< yellow): 100%
-- Жёлтый и Зелёный (yellow .. grey-1): (grey - skill) / (grey - yellow)
-- Серый (>= grey): 0%
function ns.CalculateSkillUpChance(skill, th)
	if not th or not skill then
		return 0, "grey"
	end
	local orange, yellow, green, grey = th[1] or 1, th[2] or 1, th[3] or 1, th[4] or 1
	if skill >= grey then
		return 0, "grey"
	end
	if skill < yellow then
		return 1.0, "orange"
	end
	local span = math.max(1, grey - yellow)
	local chance = math.max(0, math.min(1, (grey - skill) / span))
	local color = (skill < green) and "yellow" or "green"
	return chance, color
end

-- Минимальный навык, с которого рецепт можно изучить / крафтить
function ns:GetRecipeRequiredSkill(recipeID)
	local th = self:GetRecipeThresholds(recipeID)
	local fee, trainerSkill, isTrainer = self:GetTrainerFee(recipeID)
	local scroll = self.RecipeScrolls and self.RecipeScrolls[recipeID]
	local scrollSkill = scroll and scroll[2]
	local req = (trainerSkill and trainerSkill > 0 and trainerSkill)
		or (scrollSkill and scrollSkill > 0 and scrollSkill)
		or (th and th[1])
		or 1
	return req, fee, isTrainer
end

-- Метрики рецепта при заданном навыке:
-- colorKey, chance, craftCost, netCost, costPerSkillUp, reqSkill, trainerFee
-- (netCost и costPerSkillUp меньше нуля, если выручка с вещи больше себестоимости)
function ns:GetRecipeSkillMetrics(recipeID, currentSkill, deductVendor)
	local th = self:GetRecipeThresholds(recipeID)
	local reqSkill, trainerFee, isTrainer = self:GetRecipeRequiredSkill(recipeID)
	local learned = self:IsRecipeLearned(recipeID)
	-- Для неизученного рецепта считаем шанс на уровне math.max(currentSkill, reqSkill),
	-- чтобы видеть его реальный цвет/шанс сразу после изучения
	local evalSkill = learned and (currentSkill or 1) or math.max(currentSkill or 1, reqSkill or 1)
	local chance, colorKey = ns.CalculateSkillUpChance(evalSkill, th)

	local live = self.liveRecipes and self.liveRecipes[recipeID]
	if live and live.learned and live.difficulty then
		if live.difficulty == "trivial" then
			chance = 0
			colorKey = "grey"
		elseif live.difficulty == "optimal" and chance < 1 then
			chance = 1.0
			colorKey = "orange"
		end
	end

	local craftCost, _, netProfit, _, _, alts = self:GetRecipeEconomy(recipeID)
	-- вычитаем продажу торговцу (если отмечена) или распыление (если включено), что больше
	local skillUpReturn = ns.GetSkillUpReturn(alts, deductVendor)
	-- Без обрезки по нулю: отрицательная цена значит, что крафт окупается и приносит доход
	-- (показывается зелёным «+», ns.FormatSkillUpCost); прибыльные рецепты в сортировке выше бесплатных.
	local netCost = craftCost and (craftCost - skillUpReturn) or nil
	local costPerSkillUp = (netCost and chance and chance > 0) and math.floor(netCost / chance + 0.5) or nil

	return {
		recipeID = recipeID,
		learned = learned,
		isTrainer = isTrainer or false,
		scrollItemID = (self.RecipeScrolls and self.RecipeScrolls[recipeID] and self.RecipeScrolls[recipeID][1]) or nil,
		reqSkill = reqSkill,
		trainerFee = trainerFee,
		thresholds = th,
		chance = chance,
		colorKey = learned and colorKey or "unlearned",
		bandColor = colorKey,
		craftCost = craftCost,
		netCost = netCost,
		profit = netProfit,
		costPerSkillUp = costPerSkillUp,
	}
end

-- Возвращает шаг обучения следующему рангу профессии (75 -> 150 -> 225 -> 300)
local function GetRankMilestone(skillLine, targetCap)
	local side = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"

	for _, q in ipairs((ns.RankQuests and ns.RankQuests[skillLine]) or {}) do
		if q[1] == targetCap and (q[5] == side or not q[5]) then
			return {
				kind = "quest",
				cap = targetCap,
				questID = q[2],
				reqSkill = q[3] or (targetCap - 75),
				fee = 0,
				title = string.format(L["PLANNER_STEP_QUEST"], L["RANK_" .. targetCap] or tostring(targetCap), q[3] or (targetCap - 75)),
			}
		end
	end

	for _, b in ipairs((ns.RankBooks and ns.RankBooks[skillLine]) or {}) do
		if b[1] == targetCap then
			local bookID = b[2]
			local fee = b[3] or 10000
			local bookName = ns:GetItemDisplay(bookID)
			return {
				kind = "book",
				cap = targetCap,
				itemID = bookID,
				reqSkill = b[4] or (targetCap - 75),
				fee = fee,
				title = string.format(L["PLANNER_STEP_BOOK"], bookName, b[4] or (targetCap - 75), ns.FormatMoney(fee)),
			}
		end
	end

	for _, r in ipairs((ns.TrainerRanks and ns.TrainerRanks[skillLine]) or {}) do
		if r[1] == targetCap then
			local fee = r[2] or 500
			return {
				kind = "rank",
				cap = targetCap,
				reqSkill = r[3] or (targetCap - 75),
				fee = fee,
				title = string.format(L["PLANNER_STEP_TRAIN_RANK"], L["RANK_" .. targetCap] or tostring(targetCap), r[3] or (targetCap - 75), ns.FormatMoney(fee)),
			}
		end
	end
	return nil
end

-- Классифицирует неизученный рецепт по источнику получения для игрока заданной фракции:
-- "trainer" | "vendor" (всегда в наличии) | "other" (прочие свитки/лимит/дроп/АХ) | nil (базовый/без источника)
function ns:ClassifyUnlearnedRecipe(recipeID, playerFaction)
	if not recipeID then
		return nil
	end
	if self.BasicRecipes and self.BasicRecipes[recipeID] then
		return nil
	end
	if not playerFaction then
		local rawFaction = UnitFactionGroup and UnitFactionGroup("player") or nil
		playerFaction = (rawFaction == "Alliance" and "A") or (rawFaction == "Horde" and "H") or nil
	end
	local reqSkill, trainerFee, isTrainer = self:GetRecipeRequiredSkill(recipeID)
	if isTrainer then
		return "trainer", reqSkill or 1, trainerFee or 0, nil
	end
	local scroll = self.RecipeScrolls and self.RecipeScrolls[recipeID]
	local scrollItemID = scroll and scroll[1] or nil
	local vendorRec = self.VendorRecipeScrolls and self.VendorRecipeScrolls[recipeID] or nil
	if vendorRec then
		local vFac = vendorRec[3]
		if not vFac or vFac == "" or (playerFaction and vFac == playerFaction) then
			return "vendor", reqSkill or 1, vendorRec[2] or 0, scrollItemID or vendorRec[1]
		end
	end
	if scrollItemID then
		return "other", reqSkill or 1, nil, scrollItemID
	end
	return nil
end

-- Строит пошаговый маршрут прокачки от currentSkill до targetSkill
function ns:BuildLevelingRoute(skillLine, currentSkill, targetSkill)
	if not skillLine then
		return { steps = {}, totalCost = 0 }
	end
	local prof = self.playerProfessions[skillLine]
	local startSkill = currentSkill or (prof and prof.rank) or 1
	local currentCap = (prof and prof.maxRank) or 75
	local goalSkill = math.min(300, math.max(startSkill, targetSkill or 300))

	if startSkill >= goalSkill then
		return { steps = {}, totalCost = 0, startSkill = startSkill, goalSkill = goalSkill }
	end

	local opts = (self.db and self.db.options) or {}
	local includeTrainer = opts.includeTrainerInRoute ~= false
	local includeVendor = opts.includeVendorRecipesInRoute ~= false
	local includeOther = opts.includeOtherRecipesInRoute == true
	local deductVendor = opts.deductVendorInRoute ~= false
	local priority = opts.routePriority or "speed"
	local checkAhStock = opts.checkAuctionStock == true
	local skipped = (self.charDB and self.charDB.skippedRecipes) or {}
	local rawFaction = UnitFactionGroup and UnitFactionGroup("player") or nil
	local playerFaction = (rawFaction == "Alliance" and "A") or (rawFaction == "Horde" and "H") or nil

	local candidates = {}
	local recipeList = self.RecipesBySkill and self.RecipesBySkill[skillLine] or {}
	for _, recipeID in ipairs(recipeList) do
		if not skipped[recipeID] then
			local learned = self:IsRecipeLearned(recipeID)
			local isBasic = self.BasicRecipes and self.BasicRecipes[recipeID]
			local srcKind, reqSkill, baseFee, scrollItemID = nil, 1, 0, nil
			if learned then
				reqSkill = 1
			elseif isBasic then
				reqSkill = select(1, self:GetRecipeRequiredSkill(recipeID)) or 1
			else
				srcKind, reqSkill, baseFee, scrollItemID = self:ClassifyUnlearnedRecipe(recipeID, playerFaction)
			end
			local isTrainer = (srcKind == "trainer")
			local isVendorScroll = (srcKind == "vendor")
			local isOtherScroll = (srcKind == "other")
			local scrollPrice = (isOtherScroll and includeOther and scrollItemID) and self:GetAuctionPrice(scrollItemID) or nil
			local th = self:GetRecipeThresholds(recipeID)
			local hasKnownAcquisition = learned
				or isBasic
				or (includeTrainer and isTrainer)
				or (includeVendor and isVendorScroll)
				or (includeOther and isOtherScroll and scrollPrice and scrollPrice > 0)
			local isFallbackScroll = (not hasKnownAcquisition) and includeOther and isOtherScroll
			if hasKnownAcquisition or isFallbackScroll then
				local craftCost, outVal, _, breakdown, _, alts = self:GetRecipeEconomy(recipeID)
				if breakdown and #breakdown > 0 then
					local rec = self:GetRecipeRecord(recipeID)
					local vendorSell = (alts and alts.vendor) or 0
					-- вычет в маршруте: торговец (если отмечен) или распыление (если включено), что больше
					local effectiveDeduct = ns.GetSkillUpReturn(alts, deductVendor)
					local unitReturn = deductVendor and effectiveDeduct or math.max(outVal or 0, vendorSell)
					local acquireFee = 0
					if not learned and not isBasic then
						if isTrainer or isVendorScroll then
							acquireFee = baseFee or 0
						elseif scrollPrice and scrollPrice > 0 then
							acquireFee = scrollPrice
						end
					end
					local realReqSkill = select(1, self:GetRecipeRequiredSkill(recipeID)) or reqSkill or 1
					candidates[#candidates + 1] = {
						recipeID = recipeID,
						learned = learned or isBasic,
						isTrainer = isTrainer,
						reqSkill = learned and 1 or (reqSkill or 1),
						realReqSkill = realReqSkill,
						trainerFee = acquireFee,
						scrollItemID = (not learned and not isBasic and not isTrainer) and scrollItemID or nil,
						isVendorScroll = isVendorScroll,
						isFallback = isFallbackScroll,
						th = th,
						craftCost = craftCost,
						effectiveDeduct = effectiveDeduct,
						unitReturn = unitReturn,
						outputItemID = rec and rec.outputItemID or nil,
						numMade = (rec and rec.numMade and rec.numMade > 0) and rec.numMade or 1,
						reagents = breakdown,
						netCost = craftCost and math.max(0, craftCost - effectiveDeduct) or nil,
					}
				end
			end
		end
	end

	-- В калькуляторе учитываем себестоимость полуфабрикатов (напр. рулона шёлка) по доступным рецептам маршрута,
	-- если их крафт дешевле покупки готового полуфабриката на аукционе (не мутируя кэш GetRecipeEconomy)
	local routeCraftUnit = {}
	local function ConsiderRouteProducer(c)
		if c.isFallback or not c.outputItemID or c.outputItemID <= 0 or not c.craftCost or c.craftCost <= 0 then
			return
		end
		if not (c.learned or c.isTrainer) then
			return
		end
		local unitPrice = math.floor(c.craftCost / (c.numMade or 1) + 0.5)
		local req = c.reqSkill or 1
		local prev = routeCraftUnit[c.outputItemID]
		if not prev or unitPrice < prev.unitPrice or (unitPrice == prev.unitPrice and req < prev.reqSkill) then
			routeCraftUnit[c.outputItemID] = {
				unitPrice = unitPrice,
				reqSkill = req,
				recipeID = c.recipeID,
				learned = c.learned and true or false,
			}
		end
	end
	for _, c in ipairs(candidates) do
		ConsiderRouteProducer(c)
	end
	for _ = 1, 4 do
		local updatedAny = false
		for _, c in ipairs(candidates) do
			if c.reagents and #c.reagents > 0 then
				local effectiveReq = math.max(startSkill, c.reqSkill or 1, c.realReqSkill or 1)
				local improved = false
				for _, b in ipairs(c.reagents) do
					local prod = b.itemID and routeCraftUnit[b.itemID]
					if prod and prod.recipeID ~= c.recipeID and (prod.learned or not c.learned) and (prod.reqSkill or 1) <= effectiveReq and prod.unitPrice < (b.unitPrice or math.huge) then
						improved = true
						break
					end
				end
				if improved then
					local newReagents = {}
					local newCost = 0
					local allPriced = true
					for idx, b in ipairs(c.reagents) do
						local prod = b.itemID and routeCraftUnit[b.itemID]
						if prod and prod.recipeID ~= c.recipeID and (prod.learned or not c.learned) and (prod.reqSkill or 1) <= effectiveReq and prod.unitPrice < (b.unitPrice or math.huge) then
							newReagents[idx] = {
								itemID = b.itemID,
								quantity = b.quantity,
								unitPrice = prod.unitPrice,
								source = "craft",
							}
							newCost = newCost + prod.unitPrice * b.quantity
						else
							newReagents[idx] = b
							if b.unitPrice then
								newCost = newCost + b.unitPrice * b.quantity
							else
								allPriced = false
							end
						end
					end
					c.reagents = newReagents
					if allPriced then
						c.craftCost = newCost
						c.netCost = math.max(0, newCost - (c.effectiveDeduct or 0))
						ConsiderRouteProducer(c)
					end
					updatedAny = true
				end
			end
		end
		if not updatedAny then
			break
		end
	end
	local pricedCandidates = {}
	for _, c in ipairs(candidates) do
		if c.craftCost ~= nil then
			pricedCandidates[#pricedCandidates + 1] = c
		end
	end
	candidates = pricedCandidates

	local steps = {}
	local totalCost = 0
	local totalGrossCost = 0
	local totalReturn = 0
	local baseHaveCache = {}
	local function GetBaseHave(itemID)
		if baseHaveCache[itemID] == nil then
			baseHaveCache[itemID] = self:GetBagCount(itemID) + self:GetBankCount(itemID)
		end
		return baseHaveCache[itemID]
	end
	local function CopyMap(src)
		local dst = {}
		for k, v in pairs(src) do
			dst[k] = v
		end
		return dst
	end
	local function EvalStateBuyCost(state, cand, craftsCount)
		local n = craftsCount or 1
		local cost = 0
		local ahPenalty = 0
		for _, b in ipairs(cand.reagents) do
			local baseAvail = math.max(0, GetBaseHave(b.itemID) - (state.used[b.itemID] or 0))
			local prodAvail = (state.produced and state.produced[b.itemID]) or 0
			local need = b.quantity * n
			local fromBase = math.min(baseAvail, need)
			local rem = need - fromBase
			local fromProd = math.min(prodAvail, rem)
			if fromProd > 0 then
				-- Потреблённый полуфабрикат не уйдёт вендору: снимаем его авансовую выручку
				cost = cost + fromProd * ((state.prodReturn and state.prodReturn[b.itemID]) or 0)
			end
			local toBuy = rem - fromProd
			if toBuy > 0 then
				local unitPrice = b.unitPrice or 0
				if checkAhStock and b.source == "ah" and self.EvalAuctionBuyCost then
					local lineCost, shortage = self:EvalAuctionBuyCost(b.itemID, state.ahBought[b.itemID] or 0, toBuy, unitPrice)
					cost = cost + lineCost
					if shortage > 0 then
						ahPenalty = ahPenalty + shortage * math.max(500, unitPrice * 0.5)
					end
				else
					cost = cost + toBuy * unitPrice
				end
			end
		end
		return cost, ahPenalty
	end

	-- Нормализуем потолок ранга к стандартным ступеням 75/150/225/300 (учитывая расовый бонус до +15)
	local activeCap = 75
	if currentCap > 240 then
		activeCap = 300
	elseif currentCap > 165 then
		activeCap = 225
	elseif currentCap > 90 then
		activeCap = 150
	end

	-- Предварительно индексируем активных кандидатов по очкам навыка [startSkill .. goalSkill-1]
	-- и отмечаем только те outputItemID, которые реально используются как реагенты другим кандидатом
	local consumedByAny = {}
	for _, c in ipairs(candidates) do
		for _, b in ipairs(c.reagents or {}) do
			if b.itemID then
				consumedByAny[b.itemID] = true
			end
		end
	end

	local recipesAtSkill = {}
	local fallbackAtSkill = {}
	for _, c in ipairs(candidates) do
		if c.th and c.th[4] then
			local targetMap = c.isFallback and fallbackAtSkill or recipesAtSkill
			local lo = math.max(startSkill, c.reqSkill or 1)
			local hi = math.min(goalSkill - 1, c.th[4] - 1)
			for sk = lo, hi do
				local chance, color = ns.CalculateSkillUpChance(sk, c.th)
				if chance > 0.05 then
					local bucket = targetMap[sk]
					if not bucket then
						bucket = {}
						targetMap[sk] = bucket
					end
					bucket[#bucket + 1] = {
						cand = c,
						chance = chance,
						color = color,
						craftsPerPoint = 1 / chance,
					}
				end
			end
		end
	end

	-- Лучевой поиск (Beam Search) по [startSkill .. goalSkill-1] с сохранением разнообразия по последнему рецепту,
	-- чтобы стоимость обучения у тренера оценивалась по всему отрезку, а не жадно по 1 очку
	local BEAM_WIDTH = ((goalSkill - startSkill) > 120) and 8 or 10
	local STARTER_SLOTS = 3
	local MAIN_SLOTS = BEAM_WIDTH - STARTER_SLOTS
	local beams = {
		{ score = 0, used = {}, produced = {}, prodReturn = {}, ahBought = {}, learned = {}, prevID = nil, tail = nil },
	}
	local milestonesAtSkill = {}

	local function CompareTransitions(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end
		if a.chance ~= b.chance then
			return a.chance > b.chance
		end
		return a.cand.recipeID < b.cand.recipeID
	end

	local stoppedAt = nil
	for s = startSkill, goalSkill - 1 do
		if s >= activeCap - 15 and activeCap < goalSkill then
			local nextCap = activeCap + 75
			if nextCap <= 300 then
				local milestone = GetRankMilestone(skillLine, nextCap)
				if milestone and s >= milestone.reqSkill then
					milestonesAtSkill[s] = milestone
					activeCap = nextCap
				end
			end
		end

		local bucket = recipesAtSkill[s]
		if (not bucket or #bucket == 0) and fallbackAtSkill[s] then
			bucket = fallbackAtSkill[s]
		end
		if not bucket or #bucket == 0 then
			stoppedAt = s
			break
		end

		local transitions = {}
		local starters = {}
		for _, state in ipairs(beams) do
			for _, entry in ipairs(bucket) do
				local c = entry.cand
				local chance = entry.chance
				local craftsPerPoint = entry.craftsPerPoint
				local buyCostForPoint, ahPenalty = EvalStateBuyCost(state, c, craftsPerPoint)
				local returnForPoint = (c.unitReturn or 0) * craftsPerPoint
				local netTotal = buyCostForPoint - returnForPoint
				local rngPenalty = 0
				if priority ~= "profit" then
					rngPenalty = (chance < 0.999) and ((craftsPerPoint - 1) * 20000 + 5000) or 0
				end
				local stepScore
				if netTotal <= 0 then
					stepScore = (netTotal / craftsPerPoint) + rngPenalty
				else
					stepScore = netTotal + rngPenalty
				end
				local needsLearn = (not c.learned and not state.learned[c.recipeID])
				local learnFee = (needsLearn and c.trainerFee > 0) and c.trainerFee or 0
				stepScore = stepScore + (ahPenalty or 0) + learnFee
				if c.recipeID == state.prevID then
					stepScore = stepScore - math.max(20, math.abs(stepScore) * 0.01)
				end
				local totalScore = state.score + stepScore
				local tr = {
					score = totalScore,
					state = state,
					cand = c,
					chance = chance,
					color = entry.color,
					needsLearn = needsLearn,
					learnFee = learnFee,
					craftsPerPoint = craftsPerPoint,
				}
				transitions[#transitions + 1] = tr
				if learnFee > 0 then
					local horizon = math.max(1, math.min(10, c.th[4] - s, goalSkill - s))
					tr.starterScore = totalScore - learnFee + (learnFee / horizon)
					starters[#starters + 1] = tr
				end
			end
		end

		if #transitions == 0 then
			break
		end

		table.sort(transitions, CompareTransitions)

		local chosen = {}
		local pickedTr = {}
		local seenRecipe = {}
		-- Основные слоты: лучший точный путь для каждого уникального рецепта (уже изученный путь всегда выигрывает)
		for _, tr in ipairs(transitions) do
			local rid = tr.cand.recipeID
			if not seenRecipe[rid] then
				seenRecipe[rid] = true
				pickedTr[tr] = true
				chosen[#chosen + 1] = tr
				if #chosen >= MAIN_SLOTS then
					break
				end
			end
		end
		-- Резервные слоты для новых рецептов тренера (чтобы дорогой рецепт получил шанс окупиться на следующих шагах)
		if #starters > 0 and #chosen < BEAM_WIDTH then
			table.sort(starters, function(a, b)
				if a.starterScore ~= b.starterScore then
					return a.starterScore < b.starterScore
				end
				return CompareTransitions(a, b)
			end)
			for _, tr in ipairs(starters) do
				local rid = tr.cand.recipeID
				if not seenRecipe[rid] and not pickedTr[tr] then
					seenRecipe[rid] = true
					pickedTr[tr] = true
					chosen[#chosen + 1] = tr
					if #chosen >= BEAM_WIDTH then
						break
					end
				end
			end
		end
		if #chosen < BEAM_WIDTH then
			for _, tr in ipairs(transitions) do
				if not pickedTr[tr] then
					chosen[#chosen + 1] = tr
					if #chosen >= BEAM_WIDTH then
						break
					end
				end
			end
		end

		local nextBeams = {}
		for _, tr in ipairs(chosen) do
			local prevState = tr.state
			local cand = tr.cand
			local newUsed = prevState.used
			local usedCopied = false
			local newProduced = prevState.produced
			local prodCopied = false
			local newProdReturn = prevState.prodReturn
			local newAhBought = prevState.ahBought
			local ahCopied = false
			for _, b in ipairs(cand.reagents) do
				local baseAvail = math.max(0, GetBaseHave(b.itemID) - (newUsed[b.itemID] or 0))
				local prodAvail = (newProduced and newProduced[b.itemID]) or 0
				local need = b.quantity * tr.craftsPerPoint
				local fromBase = math.min(baseAvail, need)
				if fromBase > 0 then
					if not usedCopied then
						newUsed = CopyMap(prevState.used)
						usedCopied = true
					end
					newUsed[b.itemID] = (newUsed[b.itemID] or 0) + fromBase
				end
				local rem = need - fromBase
				local fromProd = math.min(prodAvail, rem)
				if fromProd > 0 then
					if not prodCopied then
						newProduced = CopyMap(prevState.produced or {})
						prodCopied = true
					end
					newProduced[b.itemID] = prodAvail - fromProd
				end
				local toBuy = rem - fromProd
				if checkAhStock and b.source == "ah" and toBuy > 0 then
					if not ahCopied then
						newAhBought = CopyMap(prevState.ahBought)
						ahCopied = true
					end
					newAhBought[b.itemID] = (newAhBought[b.itemID] or 0) + toBuy
				end
			end
			if cand.outputItemID and consumedByAny[cand.outputItemID] then
				if not prodCopied then
					newProduced = CopyMap(prevState.produced or {})
					prodCopied = true
				end
				local madeQty = (cand.numMade or 1) * tr.craftsPerPoint
				newProduced[cand.outputItemID] = (newProduced[cand.outputItemID] or 0) + madeQty
				local unitRet = (cand.unitReturn or 0) / (cand.numMade or 1)
				if (newProdReturn and newProdReturn[cand.outputItemID]) ~= unitRet then
					newProdReturn = CopyMap(prevState.prodReturn or {})
					newProdReturn[cand.outputItemID] = unitRet
				end
			end
			local newLearned = prevState.learned
			if tr.needsLearn then
				newLearned = CopyMap(prevState.learned)
				newLearned[cand.recipeID] = true
			end
			nextBeams[#nextBeams + 1] = {
				score = tr.score,
				used = newUsed,
				produced = newProduced,
				prodReturn = newProdReturn,
				ahBought = newAhBought,
				learned = newLearned,
				prevID = cand.recipeID,
				tail = {
					parent = prevState.tail,
					s = s,
					cand = cand,
					chance = tr.chance,
					color = tr.color,
					needsLearn = tr.needsLearn,
					learnFee = tr.learnFee,
				},
			}
		end
		beams = nextBeams
	end

	-- Выбираем лучший финишный путь строго по точному итоговому score
	table.sort(beams, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end
		return (a.prevID or 0) < (b.prevID or 0)
	end)
	local bestState = beams[1]
	if bestState and bestState.tail then
		local path = {}
		local node = bestState.tail
		while node do
			path[#path + 1] = node
			node = node.parent
		end
		for i = #path, 1, -1 do
			local p = path[i]
			local ms = milestonesAtSkill[p.s]
			if ms then
				steps[#steps + 1] = ms
				totalCost = totalCost + (ms.fee or 0)
				totalGrossCost = totalGrossCost + (ms.fee or 0)
			end
			local c = p.cand
			local lastStep = steps[#steps]
			if lastStep and lastStep.kind == "craft" and lastStep.recipeID == c.recipeID and not p.needsLearn then
				lastStep.toSkill = p.s + 1
				lastStep.expectedCrafts = lastStep.expectedCrafts + (1 / p.chance)
				lastStep.chanceSum = lastStep.chanceSum + p.chance
				lastStep.points = lastStep.points + 1
			else
				local stepNeedsLearn = p.needsLearn and true or false
				steps[#steps + 1] = {
					kind = "craft",
					recipeID = c.recipeID,
					fromSkill = p.s,
					toSkill = p.s + 1,
					points = 1,
					expectedCrafts = 1 / p.chance,
					chanceSum = p.chance,
					colorKey = p.color,
					unitNetCost = c.netCost,
					unitCraftCost = c.craftCost,
					unitReturn = c.unitReturn or 0,
					outputItemID = c.outputItemID,
					numMade = c.numMade or 1,
					th = c.th,
					reagents = c.reagents,
					needsLearn = stepNeedsLearn,
					learnFee = stepNeedsLearn and (p.learnFee or 0) or 0,
					scrollItemID = stepNeedsLearn and c.scrollItemID or nil,
					isVendorScroll = stepNeedsLearn and c.isVendorScroll or false,
					isTrainer = stepNeedsLearn and c.isTrainer or false,
					reqSkill = c.reqSkill,
				}
			end
		end
	end

	-- Упорядочиваем зависимые шаги: если позже крафтится полуфабрикат для более раннего рецепта
	-- (например, рулон ткани перед сумками), ставим полуфабрикат раньше и склеиваем одинаковые шаги.
	local function StepConsumesItem(step, itemID)
		if not (itemID and step and step.reagents) then
			return false
		end
		for _, b in ipairs(step.reagents) do
			if b.itemID == itemID then
				return true
			end
		end
		return false
	end

	local function EvalStepRange(step, sStart, points)
		if not (step.th and step.th[4]) or sStart < (step.reqSkill or 1) then
			return nil
		end
		local expC, chSum, firstColor = 0, 0, nil
		for sk = sStart, sStart + points - 1 do
			if sk >= step.th[4] then
				return nil
			end
			local ch, col = ns.CalculateSkillUpChance(sk, step.th)
			if ch <= 0.05 then
				return nil
			end
			if not firstColor then
				firstColor = col
			end
			expC = expC + (1 / ch)
			chSum = chSum + ch
		end
		return { expectedCrafts = expC, chanceSum = chSum, colorKey = firstColor }
	end

	local changed = true
	local guard = 0
	while changed and guard < 64 do
		changed = false
		guard = guard + 1
		for i = 1, #steps - 1 do
			local a, b = steps[i], steps[i + 1]
			if a.kind == "craft" and b.kind == "craft"
				and b.outputItemID and StepConsumesItem(a, b.outputItemID)
				and not StepConsumesItem(b, a.outputItemID)
				and not a.needsLearn
				and not b.needsLearn
				and a.fromSkill >= (b.reqSkill or 1)
			then
				local evB = EvalStepRange(b, a.fromSkill, b.points)
				local evA = evB and EvalStepRange(a, a.fromSkill + b.points, a.points) or nil
				if evA and (evB.expectedCrafts + evA.expectedCrafts) <= ((a.expectedCrafts or 0) + (b.expectedCrafts or 0) + 1.0) then
					b.fromSkill = a.fromSkill
					b.toSkill = a.fromSkill + b.points
					b.expectedCrafts = evB.expectedCrafts
					b.chanceSum = evB.chanceSum
					b.colorKey = evB.colorKey
					a.fromSkill = b.toSkill
					a.toSkill = b.toSkill + a.points
					a.expectedCrafts = evA.expectedCrafts
					a.chanceSum = evA.chanceSum
					a.colorKey = evA.colorKey
					steps[i], steps[i + 1] = b, a
					changed = true
				end
			end
		end
		local merged = {}
		for _, st in ipairs(steps) do
			local prev = merged[#merged]
			if prev and prev.kind == "craft" and st.kind == "craft"
				and prev.recipeID == st.recipeID and prev.toSkill == st.fromSkill
				and not st.needsLearn
			then
				prev.toSkill = st.toSkill
				prev.points = prev.points + st.points
				prev.expectedCrafts = prev.expectedCrafts + st.expectedCrafts
				prev.chanceSum = prev.chanceSum + st.chanceSum
				changed = true
			else
				merged[#merged + 1] = st
			end
		end
		steps = merged
	end

	-- Финализируем округление количества крафтов, учёт произведённых полуфабрикатов и стоимость шагов
	local finalPool = {}
	local producedLots = {}
	local finalAhBought = {}
	for _, st in ipairs(steps) do
		if st.kind == "craft" then
			st.crafts = math.max(st.points, math.ceil(st.expectedCrafts - 0.05))
			st.avgChance = math.floor((st.chanceSum / st.points) * 100 + 0.5)
			local stepBuyCost = 0
			for _, b in ipairs(st.reagents or {}) do
				if finalPool[b.itemID] == nil then
					finalPool[b.itemID] = self:GetBagCount(b.itemID) + self:GetBankCount(b.itemID)
				end
				local haveBase = finalPool[b.itemID]
				local need = b.quantity * st.crafts
				local takeBase = math.min(haveBase, need)
				finalPool[b.itemID] = haveBase - takeBase
				local rem = need - takeBase
				if rem > 0 and producedLots[b.itemID] then
					for _, lot in ipairs(producedLots[b.itemID]) do
						if rem <= 0 then
							break
						end
						if lot.avail > 0 then
							local takeProd = math.min(lot.avail, rem)
							lot.avail = lot.avail - takeProd
							rem = rem - takeProd
							lot.step.returnVal = math.max(0, (lot.step.returnVal or 0) - takeProd * lot.perUnitReturn)
						end
					end
				end
				local toBuy = rem
				if checkAhStock and b.source == "ah" and toBuy > 0 and self.EvalAuctionBuyCost then
					local lineCost, shortage = self:EvalAuctionBuyCost(b.itemID, finalAhBought[b.itemID] or 0, toBuy, b.unitPrice)
					stepBuyCost = stepBuyCost + lineCost
					finalAhBought[b.itemID] = (finalAhBought[b.itemID] or 0) + toBuy
					if shortage > 0 then
						st.lowStock = true
					end
				else
					stepBuyCost = stepBuyCost + toBuy * (b.unitPrice or 0)
				end
			end
			st._stepBuyCost = stepBuyCost
			st.returnVal = st.crafts * (st.unitReturn or 0)
			if st.outputItemID and st.outputItemID > 0 then
				local madeTotal = st.crafts * (st.numMade or 1)
				if madeTotal > 0 then
					producedLots[st.outputItemID] = producedLots[st.outputItemID] or {}
					producedLots[st.outputItemID][#producedLots[st.outputItemID] + 1] = {
						step = st,
						avail = madeTotal,
						perUnitReturn = (st.unitReturn or 0) / (st.numMade or 1),
					}
				end
			end
		end
	end

	totalCost = 0
	totalGrossCost = 0
	totalReturn = 0
	for _, st in ipairs(steps) do
		if st.kind == "craft" then
			local buyCost = st._stepBuyCost or 0
			st._stepBuyCost = nil
			st.returnVal = math.max(0, math.floor((st.returnVal or 0) + 0.5))
			st.grossCost = buyCost + (st.learnFee or 0)
			local stepNet = math.max(0, buyCost - st.returnVal)
			st.stepCost = stepNet + (st.learnFee or 0)
			totalCost = totalCost + stepNet + (st.learnFee or 0)
			totalGrossCost = totalGrossCost + buyCost + (st.learnFee or 0)
			totalReturn = totalReturn + st.returnVal
		else
			totalCost = totalCost + (st.fee or 0)
			totalGrossCost = totalGrossCost + (st.fee or 0)
		end
	end

	return {
		steps = steps,
		totalCost = totalCost,
		grossCost = totalGrossCost,
		totalReturn = totalReturn,
		startSkill = startSkill,
		goalSkill = goalSkill,
		stoppedAt = stoppedAt,
	}
end

