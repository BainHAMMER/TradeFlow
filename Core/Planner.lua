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
	local deductVendor = opts.deductVendorInRoute ~= false
	local priority = opts.routePriority or "speed"
	local checkAhStock = opts.checkAuctionStock == true
	local skipped = (self.charDB and self.charDB.skippedRecipes) or {}

	local candidates = {}
	local recipeList = self.RecipesBySkill and self.RecipesBySkill[skillLine] or {}
	for _, recipeID in ipairs(recipeList) do
		if not skipped[recipeID] then
			local learned = self:IsRecipeLearned(recipeID)
			local reqSkill, trainerFee, isTrainer = self:GetRecipeRequiredSkill(recipeID)
			local th = self:GetRecipeThresholds(recipeID)
			-- Базовые стартовые рецепты (оранжевые с 1, без свитка и тренера) тоже доступны
			local isBasic = self.BasicRecipes and self.BasicRecipes[recipeID]
			if learned or isBasic or (includeTrainer and isTrainer) then
				local craftCost, outVal, _, breakdown, _, alts = self:GetRecipeEconomy(recipeID)
				if craftCost then
					local vendorSell = (alts and alts.vendor) or 0
					-- вычет в маршруте: торговец (если отмечен) или распыление (если включено), что больше
					local effectiveDeduct = ns.GetSkillUpReturn(alts, deductVendor)
					local unitReturn = deductVendor and effectiveDeduct or math.max(outVal or 0, vendorSell)
					candidates[#candidates + 1] = {
						recipeID = recipeID,
						learned = learned or isBasic,
						reqSkill = learned and 1 or (reqSkill or 1),
						trainerFee = (not learned and not isBasic and trainerFee) or 0,
						th = th,
						craftCost = craftCost,
						unitReturn = unitReturn,
						vendorDeduct = effectiveDeduct,
						reagents = breakdown or {},
						netCost = math.max(0, craftCost - effectiveDeduct),
					}
				end
			end
		end
	end

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
			local have = math.max(0, GetBaseHave(b.itemID) - (state.used[b.itemID] or 0))
			local need = b.quantity * n
			if have < need then
				local toBuy = need - have
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
	local recipesAtSkill = {}
	for _, c in ipairs(candidates) do
		if c.th and c.th[4] then
			local lo = math.max(startSkill, c.reqSkill or 1)
			local hi = math.min(goalSkill - 1, c.th[4] - 1)
			for sk = lo, hi do
				local chance, color = ns.CalculateSkillUpChance(sk, c.th)
				if chance > 0.05 then
					local bucket = recipesAtSkill[sk]
					if not bucket then
						bucket = {}
						recipesAtSkill[sk] = bucket
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
		{ score = 0, used = {}, ahBought = {}, learned = {}, prevID = nil, tail = nil },
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
		if not bucket or #bucket == 0 then
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
				local rngPenalty
				if priority == "profit" then
					rngPenalty = (chance < 0.999) and ((craftsPerPoint - 1) * 500 + 100) or 0
				else
					rngPenalty = (chance < 0.999) and ((craftsPerPoint - 1) * 20000 + 5000) or 0
				end
				local stepScore
				if netTotal <= 0 then
					stepScore = (netTotal / craftsPerPoint) + rngPenalty
				else
					stepScore = netTotal + rngPenalty
				end
				local learnFee = (not c.learned and not state.learned[c.recipeID] and c.trainerFee > 0) and c.trainerFee or 0
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
			local newAhBought = prevState.ahBought
			local ahCopied = false
			for _, b in ipairs(cand.reagents) do
				local avail = math.max(0, GetBaseHave(b.itemID) - (newUsed[b.itemID] or 0))
				local need = b.quantity * tr.craftsPerPoint
				if avail > 0 then
					if not usedCopied then
						newUsed = CopyMap(prevState.used)
						usedCopied = true
					end
					local consume = math.min(avail, need)
					newUsed[b.itemID] = (newUsed[b.itemID] or 0) + consume
				end
				if checkAhStock and b.source == "ah" and need > avail then
					if not ahCopied then
						newAhBought = CopyMap(prevState.ahBought)
						ahCopied = true
					end
					newAhBought[b.itemID] = (newAhBought[b.itemID] or 0) + (need - avail)
				end
			end
			local newLearned = prevState.learned
			if tr.learnFee > 0 then
				newLearned = CopyMap(prevState.learned)
				newLearned[cand.recipeID] = true
			end
			nextBeams[#nextBeams + 1] = {
				score = tr.score,
				used = newUsed,
				ahBought = newAhBought,
				learned = newLearned,
				prevID = cand.recipeID,
				tail = {
					parent = prevState.tail,
					s = s,
					cand = cand,
					chance = tr.chance,
					color = tr.color,
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
			if p.learnFee > 0 then
				totalCost = totalCost + p.learnFee
				totalGrossCost = totalGrossCost + p.learnFee
			end
			local lastStep = steps[#steps]
			if lastStep and lastStep.kind == "craft" and lastStep.recipeID == c.recipeID then
				lastStep.toSkill = p.s + 1
				lastStep.expectedCrafts = lastStep.expectedCrafts + (1 / p.chance)
				lastStep.chanceSum = lastStep.chanceSum + p.chance
				lastStep.points = lastStep.points + 1
			else
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
					vendorDeduct = c.vendorDeduct or 0,
					reagents = c.reagents,
					learnFee = p.learnFee,
					reqSkill = c.reqSkill,
				}
			end
		end
	end

	-- Финализируем округление количества крафтов и стоимость каждого шага с учётом имеющихся материалов
	local finalPool = {}
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
				local have = finalPool[b.itemID]
				local need = b.quantity * st.crafts
				local take = math.min(have, need)
				finalPool[b.itemID] = have - take
				local toBuy = need - take
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
			st.grossCost = stepBuyCost + (st.learnFee or 0)
			st.returnVal = st.crafts * (st.unitReturn or 0)
			local stepNet = math.max(0, stepBuyCost - st.crafts * (st.unitReturn or 0))
			st.stepCost = stepNet + (st.learnFee or 0)
			totalCost = totalCost + stepNet
			totalGrossCost = totalGrossCost + stepBuyCost
			totalReturn = totalReturn + st.returnVal
		end
	end

	return {
		steps = steps,
		totalCost = totalCost,
		grossCost = totalGrossCost,
		totalReturn = totalReturn,
		startSkill = startSkill,
		goalSkill = goalSkill,
	}
end

