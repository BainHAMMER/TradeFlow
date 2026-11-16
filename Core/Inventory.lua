local _, ns = ...

-------------------------------------------------------------------------------
-- Быстрый индекс рецептов и реактивный кэш инвентаря (сумки, банк, альты)
-- Без строковой сериализации ("a b c d") и без обхода тысяч лишних предметов
-------------------------------------------------------------------------------
ns.ItemProducedBy = {}   -- [itemID] = { recipeID1, recipeID2, ... }
ns.RecipesBySkill = {}   -- [skillLine] = { recipeID1, recipeID2, ... }
ns.invRev = 1            -- Ревизия инвентаря для мгновенной инвалидации кэша крафтов

local craftCountCache = {}
local craftCountCacheRev = 0
local bagScanPending = false
local bankOpen = false

function ns:RegisterProducedItem(itemID, recipeID)
	if not itemID or itemID <= 0 or not recipeID then
		return
	end
	local list = self.ItemProducedBy[itemID]
	if not list then
		list = {}
		self.ItemProducedBy[itemID] = list
	end
	for i = 1, #list do
		if list[i] == recipeID then
			return
		end
	end
	list[#list + 1] = recipeID
end

function ns:InitInventoryIndex()
	self.ItemProducedBy = {}
	self.RecipesBySkill = {}
	for recipeID, data in pairs(self.RecipeData or {}) do
		local sl = data.skillLine
		if sl then
			self.RecipesBySkill[sl] = self.RecipesBySkill[sl] or {}
			table.insert(self.RecipesBySkill[sl], recipeID)
		end
		if data.output and data.output.itemID and data.output.itemID > 0 then
			self:RegisterProducedItem(data.output.itemID, recipeID)
		end
	end
	for _, list in pairs(self.RecipesBySkill) do
		table.sort(list)
	end
end

function ns:InvalidateCraftCounts()
	self.invRev = self.invRev + 1
end

-- Возвращает структуру рецепта (с приоритетом живых данных клиента над статической базой)
function ns:GetRecipeRecord(recipeID)
	if not recipeID then
		return nil
	end
	local bundled = self.RecipeData and self.RecipeData[recipeID]
	local live = self.liveRecipes and self.liveRecipes[recipeID]
	if not bundled and not live then
		return nil
	end
	local reagents = (live and live.reagents and #live.reagents > 0 and live.reagents)
		or (bundled and bundled.reagents)
		or {}
	local outItemID = (live and live.outputItemID and live.outputItemID > 0 and live.outputItemID)
		or (bundled and bundled.output and bundled.output.itemID)
		or nil
	local outQty = (live and live.numMade and live.numMade > 0 and live.numMade)
		or (bundled and bundled.output and bundled.output.quantity)
		or 1
	local skillLine = (live and live.skillLine) or (bundled and bundled.skillLine)
	return {
		recipeID = recipeID,
		skillLine = skillLine,
		reagents = reagents,
		outputItemID = outItemID,
		numMade = outQty,
	}
end

-- Сканирование сумок (0..4) и, если открыт банк, банковских сумок
function ns:ScanBagsNow()
	if not self.charDB then
		return
	end
	local bags = {}
	local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local GetInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
	local GetID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	local maxBag = NUM_BAG_SLOTS or 4

	if GetNumSlots then
		for bag = 0, maxBag do
			local slots = GetNumSlots(bag) or 0
			for slot = 1, slots do
				local itemID = GetID and GetID(bag, slot)
				if itemID then
					local count = 1
					if C_Container and C_Container.GetContainerItemInfo then
						local info = C_Container.GetContainerItemInfo(bag, slot)
						count = (info and info.stackCount) or 1
					elseif GetInfo then
						local _, c = GetInfo(bag, slot)
						count = c or 1
					end
					bags[itemID] = (bags[itemID] or 0) + count
				end
			end
		end
	end
	self.charDB.bags = bags

	if bankOpen and GetNumSlots then
		local bank = {}
		local bankContainers = { -1 }
		for b = maxBag + 1, maxBag + (NUM_BANKBAGSLOTS or 7) do
			bankContainers[#bankContainers + 1] = b
		end
		for _, bag in ipairs(bankContainers) do
			local slots = GetNumSlots(bag) or 0
			for slot = 1, slots do
				local itemID = GetID and GetID(bag, slot)
				if itemID then
					local count = 1
					if C_Container and C_Container.GetContainerItemInfo then
						local info = C_Container.GetContainerItemInfo(bag, slot)
						count = (info and info.stackCount) or 1
					elseif GetInfo then
						local _, c = GetInfo(bag, slot)
						count = c or 1
					end
					bank[itemID] = (bank[itemID] or 0) + count
				end
			end
		end
		self.charDB.bank = bank
	end

	self:InvalidateCraftCounts()
	if self.OnInventoryUpdated then
		self:OnInventoryUpdated()
	end
end

-- Количество предмета в сумках текущего персонажа (на WoW Forever крафт идёт только из сумок)
function ns:GetBagCount(itemID)
	if not itemID or itemID <= 0 then
		return 0
	end
	local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
	if getCount then
		local ok, c = pcall(getCount, itemID, false)
		if ok and type(c) == "number" then
			if self.charDB and self.charDB.bags then
				self.charDB.bags[itemID] = c > 0 and c or nil
			end
			return c
		end
	end
	if self.charDB and self.charDB.bags and self.charDB.bags[itemID] ~= nil then
		return self.charDB.bags[itemID]
	end
	return 0
end

-- Количество предмета в банке текущего персонажа
function ns:GetBankCount(itemID)
	if not itemID or itemID <= 0 then
		return 0
	end
	local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
	if getCount then
		local okAll, both = pcall(getCount, itemID, true)
		local okBags, bags = pcall(getCount, itemID, false)
		if okAll and okBags and type(both) == "number" and type(bags) == "number" and both >= bags then
			local diff = both - bags
			if diff > 0 or bankOpen then
				if self.charDB and self.charDB.bank then
					self.charDB.bank[itemID] = diff > 0 and diff or nil
				end
				return diff
			end
		end
	end
	if self.charDB and self.charDB.bank and self.charDB.bank[itemID] then
		return self.charDB.bank[itemID]
	end
	return 0
end

-- Количество предмета на всех альтах реалма (из нашей БД + Syndicator, если установлен)
function ns:GetAltCounts(itemID)
	if not itemID or itemID <= 0 then
		return 0, {}
	end
	local total = 0
	local byAlt = {}
	local seenAlt = {}
	local myName = self:CharKey()

	-- 1. Syndicator API, если установлен
	local syn = Syndicator and Syndicator.API
	if syn and syn.IsReady and syn.IsReady() and syn.GetInventoryInfoByItemID then
		local ok, info = pcall(syn.GetInventoryInfoByItemID, itemID, true, true)
		if ok and info and info.characters then
			for _, ch in ipairs(info.characters) do
				if ch.character and ch.character ~= myName then
					local count = (ch.bags or 0) + (ch.bank or 0) + (ch.mail or 0)
					if count > 0 then
						seenAlt[ch.character] = true
						total = total + count
						byAlt[#byAlt + 1] = { name = ch.character, count = count }
					end
				end
			end
		end
	end

	-- 2. Собственная БД TradeFlowDB по реалму
	if self.realmDB and self.realmDB.chars then
		for charName, data in pairs(self.realmDB.chars) do
			if charName ~= myName and not seenAlt[charName] then
				local c = ((data.bags and data.bags[itemID]) or 0) + ((data.bank and data.bank[itemID]) or 0)
				if c > 0 then
					total = total + c
					byAlt[#byAlt + 1] = { name = charName, count = c }
				end
			end
		end
	end

	table.sort(byAlt, function(a, b)
		return a.count > b.count
	end)
	return total, byAlt
end

-- Сколько единиц промежуточного реагента можно докрафтить из сумок / с банком (рекурсивно, без циклов)
function ns:GetCraftableReagentCount(itemID, visiting)
	if not itemID or itemID <= 0 then
		return 0, 0, 0
	end
	visiting = visiting or {}
	if visiting[itemID] then
		return 0, 0, 0
	end
	local producers = self.ItemProducedBy[itemID]
	if not producers or #producers == 0 then
		return 0, 0, 0
	end

	visiting[itemID] = true
	local bestBagMade = 0
	local bestVendorMade = 0
	local bestBankMade = 0

	for _, childRecipeID in ipairs(producers) do
		if self:IsRecipeLearned(childRecipeID) then
			local rec = self:GetRecipeRecord(childRecipeID)
			if rec and #rec.reagents > 0 then
				local maxCraftsBag = 99999
				local maxCraftsVendor = 99999
				local maxCraftsBank = 99999
				local allVendorChild = true
				for _, r in ipairs(rec.reagents) do
					local inBags = self:GetBagCount(r.itemID)
					local inBank = self:GetBankCount(r.itemID)
					local subCraftBag, subCraftVendor, subCraftBank = self:GetCraftableReagentCount(r.itemID, visiting)
					maxCraftsBag = math.min(maxCraftsBag, math.floor((inBags + subCraftBag) / r.quantity))
					if self:IsVendorItem(r.itemID) then
						-- Вендорский реагент не ограничивает счётчик "с вендором" / "с банком" (если есть основные маты)
					else
						allVendorChild = false
						maxCraftsVendor = math.min(maxCraftsVendor, math.floor((inBags + subCraftVendor) / r.quantity))
						maxCraftsBank = math.min(maxCraftsBank, math.floor((inBags + inBank + subCraftBank) / r.quantity))
					end
				end
				if allVendorChild then
					maxCraftsVendor = maxCraftsBag
					maxCraftsBank = maxCraftsBag
				end
				if maxCraftsBag < 99999 then
					bestBagMade = math.max(bestBagMade, maxCraftsBag * rec.numMade)
				end
				if maxCraftsVendor < 99999 then
					bestVendorMade = math.max(bestVendorMade, maxCraftsVendor * rec.numMade)
				end
				if maxCraftsBank < 99999 then
					bestBankMade = math.max(bestBankMade, maxCraftsBank * rec.numMade)
				end
			end
		end
	end

	visiting[itemID] = nil
	return bestBagMade, bestVendorMade, bestBankMade
end

-- Возвращает: direct, withCraft, withVendor, withAlts, withBank (количество КРАФТОВ рецепта)
function ns:GetRecipeCraftCounts(recipeID)
	if not recipeID then
		return 0, 0, 0, 0, 0
	end
	if craftCountCacheRev ~= self.invRev then
		craftCountCache = {}
		craftCountCacheRev = self.invRev
	end
	local cached = craftCountCache[recipeID]
	if cached then
		return cached[1], cached[2], cached[3], cached[4], cached[5]
	end

	local rec = self:GetRecipeRecord(recipeID)
	if not rec or #rec.reagents == 0 then
		craftCountCache[recipeID] = { 0, 0, 0, 0, 0 }
		return 0, 0, 0, 0, 0
	end

	local direct = 99999
	local withCraft = 99999
	local withVendor = 99999
	local withAlts = 99999
	local withBank = 99999
	local allVendor = true

	for _, r in ipairs(rec.reagents) do
		local inBags = self:GetBagCount(r.itemID)
		local inBank = self:GetBankCount(r.itemID)
		local altTotal = self:GetAltCounts(r.itemID)
		local subBag, subVendor, subBank = self:GetCraftableReagentCount(r.itemID)

		direct = math.min(direct, math.floor(inBags / r.quantity))
		withCraft = math.min(withCraft, math.floor((inBags + subBag) / r.quantity))
		withAlts = math.min(withAlts, math.floor((inBags + inBank + altTotal + subBag) / r.quantity))

		if not self:IsVendorItem(r.itemID) then
			allVendor = false
			withVendor = math.min(withVendor, math.floor((inBags + subVendor) / r.quantity))
			withBank = math.min(withBank, math.floor((inBags + inBank + subBank) / r.quantity))
		end
	end

	if allVendor then
		-- Если рецепт состоит ТОЛЬКО из вендорских реагентов, которых сейчас нет в сумке,
		-- не ставим искусственные 999 (чтобы не засорять список и не ставить 999 по кнопке «В очередь все»)
		withVendor = direct
		withBank = direct
	end
	if direct >= 99999 then direct = 0 end
	if withCraft >= 99999 then withCraft = 0 end
	if withVendor >= 99999 then withVendor = 0 end
	if withAlts >= 99999 then withAlts = 0 end
	if withBank >= 99999 then withBank = 0 end

	craftCountCache[recipeID] = { direct, withCraft, withVendor, withAlts, withBank }
	return direct, withCraft, withVendor, withAlts, withBank
end

-- Дебаунс событий сумок и банка (0.08 сек — мгновенный отклик без лагов Skillet)
local invFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"BAG_UPDATE_DELAYED",
	"BAG_UPDATE",
	"BANKFRAME_OPENED",
	"BANKFRAME_CLOSED",
	"PLAYERBANKSLOTS_CHANGED",
}) do
	pcall(invFrame.RegisterEvent, invFrame, ev)
end

invFrame:SetScript("OnEvent", function(_, event)
	if event == "BANKFRAME_OPENED" then
		bankOpen = true
	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
	end
	if bagScanPending then
		return
	end
	bagScanPending = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0.08, function()
			bagScanPending = false
			ns:ScanBagsNow()
		end)
	else
		bagScanPending = false
		ns:ScanBagsNow()
	end
end)

