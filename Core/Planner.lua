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
	local req = (trainerSkill and trainerSkill > 0 and trainerSkill) or (th and th[1]) or 1
	return req, fee, isTrainer
end

-- Метрики рецепта при заданном навыке:
-- colorKey, chance, craftCost, netCost, costPerSkillUp, reqSkill, trainerFee
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

	local craftCost = self:GetRecipeEconomy(recipeID)
	local rec = self:GetRecipeRecord(recipeID)
	local vendorReturn = 0
	if deductVendor and rec and rec.outputItemID and rec.outputItemID > 0 then
		vendorReturn = self:GetItemSellPrice(rec.outputItemID) * (rec.numMade or 1)
	end
	local netCost = craftCost and math.max(0, craftCost - vendorReturn) or nil
	local costPerSkillUp = (netCost and chance and chance > 0) and math.floor(netCost / chance + 0.5) or nil

	return {
		recipeID = recipeID,
		learned = learned,
		isTrainer = isTrainer or (live and not live.learned) or false,
		reqSkill = reqSkill,
		trainerFee = trainerFee,
		thresholds = th,
		chance = chance,
		colorKey = learned and colorKey or "unlearned",
		bandColor = colorKey,
		craftCost = craftCost,
		netCost = netCost,
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
	local skipped = (self.charDB and self.charDB.skippedRecipes) or {}

	local candidates = {}
	local recipeList = self.RecipesBySkill and self.RecipesBySkill[skillLine] or {}
	for _, recipeID in ipairs(recipeList) do
		if not skipped[recipeID] then
			local learned = self:IsRecipeLearned(recipeID)
			local reqSkill, trainerFee, isTrainer = self:GetRecipeRequiredSkill(recipeID)
			local th = self:GetRecipeThresholds(recipeID)
			-- Базовые стартовые рецепты (оранжевые с 1, без свитка) тоже доступны
			local isBasic = th and th[1] == 1 and not (self.RecipeScrolls and self.RecipeScrolls[recipeID])
			if learned or isBasic or (includeTrainer and isTrainer) then
				local craftCost = self:GetRecipeEconomy(recipeID)
				if craftCost then
					local rec = self:GetRecipeRecord(recipeID)
					local vendorReturn = 0
					if deductVendor and rec and rec.outputItemID and rec.outputItemID > 0 then
						vendorReturn = self:GetItemSellPrice(rec.outputItemID) * (rec.numMade or 1)
					end
					candidates[#candidates + 1] = {
						recipeID = recipeID,
						learned = learned or isBasic,
						reqSkill = learned and 1 or (reqSkill or 1),
						trainerFee = (not learned and not isBasic and trainerFee) or 0,
						th = th,
						craftCost = craftCost,
						netCost = math.max(0, craftCost - vendorReturn),
					}
				end
			end
		end
	end

	local steps = {}
	local totalCost = 0
	local learnedInSim = {}
	-- Нормализуем потолок ранга к стандартным ступеням 75/150/225/300 (на случай расовых бонусов +10/+15)
	local activeCap = 75
	if currentCap >= 225 then
		activeCap = 300
	elseif currentCap >= 150 then
		activeCap = 225
	elseif currentCap >= 75 then
		activeCap = ((currentCap > 95) and 150) or 75
	end
	local prevRecipeID = nil

	for s = startSkill, goalSkill - 1 do
		-- Проверяем, не пора ли поднять потолок ранга профессии (при 50/75, 125/150, 200/225)
		if s >= activeCap - 15 and activeCap < goalSkill then
			local nextCap = activeCap + 75
			if nextCap <= 300 then
				local milestone = GetRankMilestone(skillLine, nextCap)
				if milestone and s >= milestone.reqSkill then
					steps[#steps + 1] = milestone
					totalCost = totalCost + (milestone.fee or 0)
					activeCap = nextCap
				end
			end
		end

		local bestCand = nil
		local bestScore = math.huge
		local bestChance = 0
		local bestColor = "orange"

		for _, c in ipairs(candidates) do
			if s >= c.reqSkill and c.th and s < c.th[4] then
				local chance, color = ns.CalculateSkillUpChance(s, c.th)
				if chance > 0.05 then
					local expectedCost = c.netCost / chance
					-- Амортизируем цену обучения у тренера на ~10 очков, чтобы не учить рецепт ради 1 крафта,
					-- и даём небольшой бонус рецепту предыдущего шага, чтобы не дробить маршрут без выгоды
					if not c.learned and not learnedInSim[c.recipeID] and c.trainerFee > 0 then
						local horizon = math.max(1, math.min(12, c.th[4] - s, goalSkill - s))
						expectedCost = expectedCost + (c.trainerFee / horizon)
					end
					if c.recipeID == prevRecipeID then
						expectedCost = expectedCost * 0.96
					end
					if expectedCost < bestScore then
						bestScore = expectedCost
						bestCand = c
						bestChance = chance
						bestColor = color
					end
				end
			end
		end

		if not bestCand then
			break
		end

		-- Если рецепт нужно выучить у тренера на этом шаге
		local learnFee = 0
		if not bestCand.learned and not learnedInSim[bestCand.recipeID] and bestCand.trainerFee > 0 then
			learnedInSim[bestCand.recipeID] = true
			learnFee = bestCand.trainerFee
			totalCost = totalCost + learnFee
		end

		prevRecipeID = bestCand.recipeID
		local lastStep = steps[#steps]
		if lastStep and lastStep.kind == "craft" and lastStep.recipeID == bestCand.recipeID then
			lastStep.toSkill = s + 1
			lastStep.expectedCrafts = lastStep.expectedCrafts + (1 / bestChance)
			lastStep.chanceSum = lastStep.chanceSum + bestChance
			lastStep.points = lastStep.points + 1
		else
			steps[#steps + 1] = {
				kind = "craft",
				recipeID = bestCand.recipeID,
				fromSkill = s,
				toSkill = s + 1,
				points = 1,
				expectedCrafts = 1 / bestChance,
				chanceSum = bestChance,
				colorKey = bestColor,
				unitNetCost = bestCand.netCost,
				unitCraftCost = bestCand.craftCost,
				learnFee = learnFee,
				reqSkill = bestCand.reqSkill,
			}
		end
	end

	-- Финализируем округление количества крафтов и стоимость каждого шага
	for _, st in ipairs(steps) do
		if st.kind == "craft" then
			st.crafts = math.max(st.points, math.ceil(st.expectedCrafts - 0.05))
			st.avgChance = math.floor((st.chanceSum / st.points) * 100 + 0.5)
			st.stepCost = st.crafts * st.unitNetCost + (st.learnFee or 0)
			totalCost = totalCost + (st.crafts * st.unitNetCost)
		end
	end

	return {
		steps = steps,
		totalCost = totalCost,
		startSkill = startSkill,
		goalSkill = goalSkill,
	}
end

