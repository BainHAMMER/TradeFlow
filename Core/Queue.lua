local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Умная DAG-очередь крафта (без багов Skillet) + расчёт Shopping List + ProcessQueue
-------------------------------------------------------------------------------
ns.activeCastRecipeID = nil

function ns:GetQueue()
	if not self.charDB then
		return {}
	end
	self.charDB.queue = self.charDB.queue or {}
	return self.charDB.queue
end

-- Вычисляет виртуальный баланс предметов в сумках с учётом уже стоящих в очереди шагов
local function BuildSimulatedInventory(queue)
	local sim = {}
	setmetatable(sim, {
		__index = function(t, itemID)
			local v = ns:GetBagCount(itemID) + (ns.GetBankCount and ns:GetBankCount(itemID) or 0)
			rawset(t, itemID, v)
			return v
		end,
	})
	for _, cmd in ipairs(queue) do
		local rec = ns:GetRecipeRecord(cmd.recipeID)
		if rec then
			for _, r in ipairs(rec.reagents) do
				sim[r.itemID] = math.max(0, sim[r.itemID] - (r.quantity * cmd.count))
			end
			if rec.outputItemID and rec.outputItemID > 0 then
				sim[rec.outputItemID] = sim[rec.outputItemID] + ((rec.numMade or 1) * cmd.count)
			end
		end
	end
	return sim
end

-- Выбирает лучший изученный персонажем рецепт для крафта промежуточного реагента
function ns:FindBestProducerRecipe(itemID, visiting)
	local producers = self.ItemProducedBy and self.ItemProducedBy[itemID]
	if not producers or #producers == 0 then
		return nil
	end
	local bestID = nil
	local bestCost = math.huge
	for _, recipeID in ipairs(producers) do
		if not visiting[recipeID] and self:IsRecipeLearned(recipeID) then
			local rec = self:GetRecipeRecord(recipeID)
			-- Предпочитаем рецепт текущей профессии, затем второй профессии персонажа
			if rec and (rec.skillLine == self.currentSkillLine or self.playerProfessions[rec.skillLine]) then
				local cost = self:GetRecipeEconomy(recipeID) or 999999
				if rec.skillLine == self.currentSkillLine then
					cost = cost * 0.95
				end
				if cost < bestCost then
					bestCost = cost
					bestID = recipeID
				end
			end
		end
	end
	return bestID
end

-- Добавление или слияние команды в очередь со строгим сохранением топологического порядка (DAG)
local function InsertOrMergeStep(queue, step)
	local rec = ns:GetRecipeRecord(step.recipeID)
	local neededItems = {}
	if rec then
		for _, r in ipairs(rec.reagents) do
			neededItems[r.itemID] = true
		end
	end
	local outItemID = rec and rec.outputItemID

	-- 1. Шаг не может стоять раньше тех шагов очереди, которые производят его реагенты
	local minIndex = 1
	for i = 1, #queue do
		local qRec = ns:GetRecipeRecord(queue[i].recipeID)
		if qRec and qRec.outputItemID and neededItems[qRec.outputItemID] then
			minIndex = i + 1
		end
	end

	-- 2. Если это промежуточный крафт, желательно поставить его до первого потребителя (после minIndex)
	local maxIndex = #queue
	if step.isSubcraft and outItemID and outItemID > 0 then
		for i = minIndex, #queue do
			local qRec = ns:GetRecipeRecord(queue[i].recipeID)
			if qRec then
				for _, r in ipairs(qRec.reagents) do
					if r.itemID == outItemID then
						maxIndex = i - 1
						break
					end
				end
			end
			if maxIndex < #queue then
				break
			end
		end
	end

	-- 3. Если в допустимом диапазоне [minIndex .. maxIndex] уже есть такой же рецепт — сливаем с ним
	for i = maxIndex, minIndex, -1 do
		if queue[i] and queue[i].recipeID == step.recipeID then
			queue[i].count = queue[i].count + step.count
			return
		end
	end

	-- 4. Иначе вставляем в позицию maxIndex + 1 (перед потребителем или в конец очереди)
	local insertPos = math.min(#queue + 1, math.max(minIndex, maxIndex + 1))
	table.insert(queue, insertPos, step)
end

-- Главная функция добавления рецепта в очередь с DAG-разворачиванием промежуточных реагентов
function ns:QueueAddRecipe(recipeID, count, autoSubcrafts, silent)
	count = math.max(1, math.floor(tonumber(count) or 1))
	local rec = self:GetRecipeRecord(recipeID)
	if not rec then
		return
	end
	if autoSubcrafts == nil then
		autoSubcrafts = not (self.db and self.db.options and self.db.options.autoSubcrafts == false)
	end

	local queue = self:GetQueue()
	local simHave = BuildSimulatedInventory(queue)
	local staged = {}
	local visiting = {}

	local function Expand(rID, craftsNeeded, isSub)
		if craftsNeeded <= 0 or visiting[rID] then
			return
		end
		local rRecord = self:GetRecipeRecord(rID)
		if not rRecord then
			return
		end
		visiting[rID] = true

		for _, reagent in ipairs(rRecord.reagents) do
			local totalNeed = reagent.quantity * craftsNeeded
			local avail = math.max(0, simHave[reagent.itemID])
			local useFromAvail = math.min(avail, totalNeed)
			simHave[reagent.itemID] = avail - useFromAvail
			local deficit = totalNeed - useFromAvail

			if autoSubcrafts and deficit > 0 and not self:IsVendorItem(reagent.itemID) then
				local prodRecipeID = self:FindBestProducerRecipe(reagent.itemID, visiting)
				if prodRecipeID then
					local prodRec = self:GetRecipeRecord(prodRecipeID)
					if prodRec and (prodRec.numMade or 1) > 0 then
						local subCrafts = math.ceil(deficit / prodRec.numMade)
						Expand(prodRecipeID, subCrafts, true)
						-- Вычитаем потреблённый дефицит из только что произведённой партии полуфабриката
						simHave[reagent.itemID] = math.max(0, simHave[reagent.itemID] - deficit)
					end
				end
			end
		end

		if rRecord.outputItemID and rRecord.outputItemID > 0 then
			simHave[rRecord.outputItemID] = simHave[rRecord.outputItemID] + (craftsNeeded * (rRecord.numMade or 1))
		end

		staged[#staged + 1] = {
			recipeID = rID,
			skillLine = rRecord.skillLine or self.currentSkillLine,
			count = craftsNeeded,
			isSubcraft = isSub and true or false,
		}

		visiting[rID] = nil
	end

	Expand(recipeID, count, false)

	for _, step in ipairs(staged) do
		InsertOrMergeStep(queue, step)
	end

	if not silent then
		self:OnQueueUpdated()
	end
end

function ns:QueueRemoveIndex(index)
	local queue = self:GetQueue()
	if queue[index] then
		table.remove(queue, index)
		self:OnQueueUpdated()
	end
end

function ns:QueueMove(index, delta)
	local queue = self:GetQueue()
	local target = index + delta
	if index >= 1 and index <= #queue and target >= 1 and target <= #queue then
		queue[index], queue[target] = queue[target], queue[index]
		self:OnQueueUpdated()
	end
end

function ns:QueueClear()
	if self.charDB then
		self.charDB.queue = {}
	end
	self.activeCastRecipeID = nil
	self:OnQueueUpdated()
end

-- Статус конкретного шага очереди: readyCrafts, state ("ready" | "partial" | "other_prof" | "unlearned" | "wait")
function ns:GetQueueStepStatus(step)
	if not step then
		return 0, "wait"
	end
	if not self:IsRecipeLearned(step.recipeID) then
		return 0, "unlearned"
	end
	local rec = self:GetRecipeRecord(step.recipeID)
	if not rec then
		return 0, "wait"
	end
	local maxCrafts = 99999
	for _, r in ipairs(rec.reagents) do
		local inBags = self:GetBagCount(r.itemID)
		maxCrafts = math.min(maxCrafts, math.floor(inBags / r.quantity))
	end
	if maxCrafts >= 99999 or maxCrafts <= 0 then
		return 0, "wait"
	end
	local stepSL = (rec and rec.skillLine) or step.skillLine
	if stepSL then
		step.skillLine = stepSL
	end
	if stepSL and self.currentSkillLine and stepSL ~= self.currentSkillLine then
		return maxCrafts, "other_prof"
	end
	if maxCrafts >= step.count then
		return maxCrafts, "ready"
	elseif maxCrafts > 0 then
		return maxCrafts, "partial"
	end
	return 0, "wait"
end

-- Расчёт списка покупок (Shopping List) для всей очереди:
-- Учитывает промежуточные выходы более ранних шагов очереди!
function ns:GetShoppingList()
	local queue = self:GetQueue()
	if #queue == 0 then
		return {}, 0
	end

	local virtualPool = {}
	local grossRequired = {}
	local itemOrder = {}
	local seenOrder = {}

	for _, cmd in ipairs(queue) do
		local rec = self:GetRecipeRecord(cmd.recipeID)
		if rec then
			for _, r in ipairs(rec.reagents) do
				local id = r.itemID
				local need = r.quantity * cmd.count
				if virtualPool[id] == nil then
					virtualPool[id] = self:GetBagCount(id)
				end
				local take = math.min(math.max(0, virtualPool[id]), need)
				virtualPool[id] = virtualPool[id] - take
				local short = need - take
				if short > 0 then
					grossRequired[id] = (grossRequired[id] or 0) + short
					if not seenOrder[id] then
						seenOrder[id] = true
						itemOrder[#itemOrder + 1] = id
					end
				end
			end
			if rec.outputItemID and rec.outputItemID > 0 then
				local outID = rec.outputItemID
				if virtualPool[outID] == nil then
					virtualPool[outID] = self:GetBagCount(outID)
				end
				virtualPool[outID] = virtualPool[outID] + (cmd.count * (rec.numMade or 1))
			end
		end
	end

	local list = {}
	local totalCost = 0

	for _, itemID in ipairs(itemOrder) do
		local missing = grossRequired[itemID] or 0
		if missing > 0 then
			local inBags = self:GetBagCount(itemID)
			local inBank = self:GetBankCount(itemID)
			local altTotal, alts = self:GetAltCounts(itemID)
			local isVendor = self:IsVendorItem(itemID)
			local unitPrice = isVendor and self:GetVendorPrice(itemID) or self:GetAuctionPrice(itemID)
			local source = isVendor and "vendor" or (unitPrice and "ah" or "unknown")
			local toBuy = math.max(0, missing - inBank)
			local cost = (unitPrice and toBuy > 0) and (unitPrice * toBuy) or nil
			if cost then
				totalCost = totalCost + cost
			end

			list[#list + 1] = {
				itemID = itemID,
				need = inBags + missing,
				missing = missing,
				toBuy = toBuy,
				inBags = inBags,
				inBank = inBank,
				altTotal = altTotal,
				alts = alts,
				source = source,
				unitPrice = unitPrice,
				totalCost = cost,
			}
		end
	end

	-- Сортируем: сначала вендорские реагенты, затем аукцион
	table.sort(list, function(a, b)
		if a.source ~= b.source then
			if a.source == "vendor" then return true end
			if b.source == "vendor" then return false end
		end
		return a.itemID < b.itemID
	end)

	return list, totalCost
end

-- Запуск / продолжение выполнения очереди крафта
function ns:ProcessQueue()
	local queue = self:GetQueue()
	if #queue == 0 then
		return
	end

	-- Идём строго по порядку очереди: выполняем первый шаг, для которого в сумках есть реагенты
	-- (или переключаемся на его профессию, если он в смежной профессии)
	for idx, step in ipairs(queue) do
		local readyCrafts, state = self:GetQueueStepStatus(step)
		if readyCrafts > 0 then
			local activeClientSL = self.GetActiveClientSkillLine and self:GetActiveClientSkillLine() or nil
			if state == "other_prof" and step.skillLine and activeClientSL ~= step.skillLine then
				self:SwitchToProfession(step.skillLine, step.recipeID)
				return
			elseif state == "ready" or state == "partial" or (state == "other_prof" and step.skillLine and activeClientSL == step.skillLine) then
				if state == "other_prof" and step.skillLine then
					self.currentSkillLine = step.skillLine
				end
				local toCraft = math.min(step.count, readyCrafts)
				self.activeCastRecipeID = step.recipeID
				self.activeCastQueueIndex = idx
				self:ExecuteCraftRecipe(step.recipeID, toCraft)
				return
			end
		end
	end
end

function ns:OnQueueUpdated()
	if self.SyncAuctionatorShoppingList then
		self:SyncAuctionatorShoppingList(true)
	end
	if self.RefreshVendorBar then
		self:RefreshVendorBar()
	end
	if self.RefreshVisibleUI then
		self:RefreshVisibleUI()
	end
end

function ns:OnInventoryUpdated()
	if self.SyncAuctionatorShoppingList then
		self:SyncAuctionatorShoppingList(true)
	end
	if self.RefreshVendorBar then
		self:RefreshVendorBar()
	end
	if self.RefreshBankBar then
		self:RefreshBankBar()
	end
	if self.RefreshVisibleUI then
		self:RefreshVisibleUI()
	end
end

-- Отслеживание успешного крафта предмета по UNIT_SPELLCAST_SUCCEEDED (без потери остатка заказа!)
local castFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED",
}) do
	pcall(castFrame.RegisterEvent, castFrame, ev)
end

castFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
	if unit ~= "player" then
		return
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" and spellID then
		local queue = ns:GetQueue()
		for i, step in ipairs(queue) do
			if step.recipeID == spellID then
				step.count = (step.count or 1) - 1
				if step.count <= 0 then
					table.remove(queue, i)
				end
				ns:OnQueueUpdated()
				break
			end
		end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		if spellID == ns.activeCastRecipeID then
			ns.activeCastRecipeID = nil
		end
	end
end)

