local ADDON_NAME, ns = ...
local L = ns.L

ns.VERSION = "1.0.0"
ns.ICON = "Interface\\AddOns\\TradeFlow\\Media\\Icon"

-- Сопоставление skillLine <-> базовое заклинание профессии для открытия окна
ns.PROF_SPELLS = {
	[171] = 2259,  -- Alchemy
	[164] = 2018,  -- Blacksmithing
	[185] = 2550,  -- Cooking
	[333] = 7411,  -- Enchanting
	[202] = 4036,  -- Engineering
	[129] = 3273,  -- First Aid
	[165] = 2108,  -- Leatherworking
	[186] = 2575,  -- Mining (2575 Горное дело / 2656 Выплавка металлов)
	[197] = 3908,  -- Tailoring
}

-- Русские и английские названия профессий -> skillLine (на WoW Forever клиент часто возвращает кастомные ID вроде 8167/8175)
ns.PROF_NAME_TO_SKILLLINE = {
	["Alchemy"] = 171,        ["Алхимия"] = 171,
	["Blacksmithing"] = 164,  ["Кузнечное дело"] = 164,
	["Cooking"] = 185,        ["Кулинария"] = 185,
	["Enchanting"] = 333,     ["Наложение чар"] = 333,
	["Engineering"] = 202,    ["Инженерное дело"] = 202,
	["First Aid"] = 129,      ["Первая помощь"] = 129,
	["Leatherworking"] = 165, ["Кожевничество"] = 165,
	["Mining"] = 186,         ["Горное дело"] = 186,
	["Smelting"] = 186,       ["Выплавка металлов"] = 186,
	["Tailoring"] = 197,      ["Портняжное дело"] = 197,
}

ns.PROF_ICONS = {
	[171] = "Interface\\Icons\\Trade_Alchemy",
	[164] = "Interface\\Icons\\Trade_BlackSmithing",
	[185] = "Interface\\Icons\\INV_Misc_Food_15",
	[333] = "Interface\\Icons\\Trade_Engraving",
	[202] = "Interface\\Icons\\Trade_Engineering",
	[129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
	[165] = "Interface\\Icons\\INV_Misc_ArmorKit_17",
	[186] = "Interface\\Icons\\Spell_Fire_FlameBlades",
	[197] = "Interface\\Icons\\Trade_Tailoring",
}

ns.DIFFICULTY_COLORS = {
	optimal   = { r = 1.00, g = 0.50, b = 0.25, hex = "|cffff8040", order = 4 },
	orange    = { r = 1.00, g = 0.50, b = 0.25, hex = "|cffff8040", order = 4 },
	medium    = { r = 1.00, g = 0.88, b = 0.15, hex = "|cffffe026", order = 3 },
	yellow    = { r = 1.00, g = 0.88, b = 0.15, hex = "|cffffe026", order = 3 },
	easy      = { r = 0.25, g = 0.85, b = 0.25, hex = "|cff40d940", order = 2 },
	green     = { r = 0.25, g = 0.85, b = 0.25, hex = "|cff40d940", order = 2 },
	trivial   = { r = 0.58, g = 0.58, b = 0.58, hex = "|cff949494", order = 1 },
	grey      = { r = 0.58, g = 0.58, b = 0.58, hex = "|cff949494", order = 1 },
	unlearned = { r = 0.50, g = 0.62, b = 0.78, hex = "|cff809ec7", order = 0 },
}

local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"

function ns:Print(msg)
	print("|cff33ccffTradeFlow|r: " .. tostring(msg))
end

function ns.FormatMoney(copper, signed)
	if not copper or copper ~= copper or copper == math.huge or copper == -math.huge then
		return "|cff888888-|r"
	end
	local neg = copper < 0
	local absVal = math.floor(math.abs(copper) + 0.5)
	local g = math.floor(absVal / 10000)
	local s = math.floor(absVal / 100) % 100
	local c = absVal % 100
	local parts = {}
	if g > 0 then
		parts[#parts + 1] = g .. GOLD_ICON
	end
	if s > 0 or (g > 0 and c > 0) then
		parts[#parts + 1] = s .. SILVER_ICON
	end
	if (g == 0 and c > 0) or #parts == 0 then
		parts[#parts + 1] = c .. COPPER_ICON
	end
	local text = table.concat(parts, " ")
	if signed then
		if neg then
			return "|cffff5555-" .. text .. "|r"
		else
			return "|cff40ff40+" .. text .. "|r"
		end
	elseif neg then
		return "-" .. text
	end
	return text
end

function ns:RealmKey()
	local realm = GetRealmName and GetRealmName() or "Realm"
	local faction = UnitFactionGroup and UnitFactionGroup("player") or "Neutral"
	return realm .. "-" .. faction
end

function ns:CharKey()
	local name = UnitName and UnitName("player") or "Player"
	return name
end

-------------------------------------------------------------------------------
-- Реальное разрешение предметов и заклинаний по ID через клиент игры
-------------------------------------------------------------------------------
local pendingItemRefresh = false

local function ScheduleItemDataRefresh()
	if pendingItemRefresh then
		return
	end
	pendingItemRefresh = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0.1, function()
			pendingItemRefresh = false
			if ns.RefreshVisibleUI then
				ns:RefreshVisibleUI()
			end
		end)
	end
end

-- Возвращает: name, icon, quality, itemLink, isLoaded
function ns:GetItemDisplay(itemID)
	if not itemID or itemID <= 0 then
		return "?", "Interface\\Icons\\INV_Misc_QuestionMark", 1, nil, false
	end
	local name, itemLink, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
	if not name and C_Item.GetItemNameByID then
		name = C_Item.GetItemNameByID(itemID)
	end
	if not icon and C_Item.GetItemIconByID then
		icon = C_Item.GetItemIconByID(itemID)
	end
	if not quality and C_Item.GetItemQualityByID then
		quality = C_Item.GetItemQualityByID(itemID)
	end
	if not icon and C_Item.GetItemInfoInstant then
		icon = select(5, C_Item.GetItemInfoInstant(itemID))
	end
	icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
	quality = quality or 1
	if not name then
		if C_Item.RequestLoadItemDataByID then
			pcall(C_Item.RequestLoadItemDataByID, itemID)
		end
		return string.format(L["ITEM_LOADING"], itemID), icon, quality, itemLink, false
	end
	local r, g, b, hex = 1, 1, 1, "|cffffffff"
	if C_Item.GetItemQualityColor and quality then
		local qr, qg, qb, qhex = C_Item.GetItemQualityColor(quality)
		if qr then
			r, g, b = qr, qg, qb
			hex = qhex and ("|c" .. qhex) or string.format("|cff%02x%02x%02x", qr * 255, qg * 255, qb * 255)
		end
	end
	return name, icon, quality, itemLink, true, hex, r, g, b
end

-- Возвращает: name, icon, OutputItemID (если рецепт создаёт предмет)
function ns:GetRecipeDisplay(recipeID)
	if not recipeID or recipeID <= 0 then
		return "?", "Interface\\Icons\\INV_Misc_QuestionMark", nil
	end
	local rData = self.RecipeData and self.RecipeData[recipeID]
	local outItemID = rData and rData.output and rData.output.itemID or nil
	local live = self.liveRecipes and self.liveRecipes[recipeID]
	if not outItemID and live and live.outputItemID and live.outputItemID > 0 then
		outItemID = live.outputItemID
	end

	local spellName = (live and live.name)
		or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID))
		or (GetSpellInfo and GetSpellInfo(recipeID))
	local spellIcon = (live and live.icon)
		or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(recipeID))
		or (GetSpellTexture and GetSpellTexture(recipeID))

	if outItemID and outItemID > 0 then
		local itemName, itemIcon, quality, itemLink, loaded, hex = self:GetItemDisplay(outItemID)
		return (loaded and itemName) or spellName or string.format(L["SPELL_LOADING"], recipeID),
			(itemIcon and itemIcon ~= "Interface\\Icons\\INV_Misc_QuestionMark") and itemIcon or spellIcon or "Interface\\Icons\\Trade_BlackSmithing",
			outItemID,
			quality,
			itemLink,
			hex
	end

	return spellName or string.format(L["SPELL_LOADING"], recipeID),
		spellIcon or "Interface\\Icons\\Trade_BlackSmithing",
		nil,
		1,
		nil,
		"|cffffffff"
end

-- Нативный тултип предмета по его ID (реальный предмет клиента!)
function ns:ShowItemTooltip(owner, itemID, extraLinesFn)
	if not itemID or itemID <= 0 then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(itemID)
	else
		local _, _, _, link = self:GetItemDisplay(itemID)
		if link then
			GameTooltip:SetHyperlink(link)
		end
	end
	if extraLinesFn then
		extraLinesFn(GameTooltip)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["SHIFT_CLICK_HINT"], 0.55, 0.75, 1.0, true)
	GameTooltip:Show()
end

-- Нативный тултип рецепта (или создаваемого им предмета) + инфо о порогах и ценах
function ns:ShowRecipeTooltip(owner, recipeID)
	if not recipeID or recipeID <= 0 then
		return
	end
	local name, _, outItemID = self:GetRecipeDisplay(recipeID)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if outItemID and outItemID > 0 and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(outItemID)
	elseif GameTooltip.SetSpellByID then
		GameTooltip:SetSpellByID(recipeID)
	else
		GameTooltip:SetText(name, 1, 0.82, 0)
	end

	local th = self:GetRecipeThresholds(recipeID)
	if th then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(
			L["THRESHOLDS_LABEL"],
			string.format(
				"|cffff8040%d|r / |cffffe026%d|r / |cff40d940%d|r / |cff949494%d|r",
				th[1] or 1, th[2] or 1, th[3] or 1, th[4] or 1
			),
			0.9, 0.8, 0.5, 1, 1, 1
		)
	end
	local cost, outVal, profit, _, outSource = self:GetRecipeEconomy(recipeID)
	if cost then
		GameTooltip:AddDoubleLine(L["CRAFT_COST"], ns.FormatMoney(cost), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if outVal and outVal > 0 then
		local outLabel = (outSource == "ah" and L["OUTPUT_VALUE_AH"])
			or (outSource == "vendor" and L["OUTPUT_VALUE_VENDOR"])
			or L["OUTPUT_VALUE"]
		GameTooltip:AddDoubleLine(outLabel, ns.FormatMoney(outVal), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	if profit then
		GameTooltip:AddDoubleLine(L["NET_PROFIT"], ns.FormatMoney(profit, true), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	GameTooltip:AddLine(L["SHIFT_CLICK_HINT"], 0.55, 0.75, 1.0, true)
	GameTooltip:Show()
end

-- Обработка Shift+клик (ссылка в чат / поиск на AH) и Ctrl+клик (примерочная)
function ns:HandleItemClick(itemID, recipeID)
	local targetItemID = itemID
	if (not targetItemID or targetItemID <= 0) and recipeID then
		local _, _, outID = self:GetRecipeDisplay(recipeID)
		targetItemID = outID
	end
	if not targetItemID or targetItemID <= 0 then
		return false
	end
	local name, _, _, itemLink = self:GetItemDisplay(targetItemID)
	if IsModifiedClick("CHATLINK") or IsShiftKeyDown() then
		local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
		if editBox and itemLink then
			ChatEdit_InsertLink(itemLink)
			return true
		end
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() and name then
			if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.MultiSearchExact then
				pcall(Auctionator.API.v1.MultiSearchExact, ADDON_NAME, { name })
				return true
			elseif AuctionHouseFrame.SetSearchText then
				pcall(AuctionHouseFrame.SetSearchText, AuctionHouseFrame, name)
				return true
			end
		end
		if BrowseName and BrowseName:IsVisible() and name then
			BrowseName:SetText(name)
			return true
		end
		if itemLink and ChatFrame_OpenChat then
			ChatEdit_InsertLink(itemLink)
			return true
		end
	elseif IsModifiedClick("DRESSUP") or IsControlKeyDown() then
		if itemLink and DressUpItemLink then
			DressUpItemLink(itemLink)
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Определение профессий персонажа и сканирование открытой профессии
-------------------------------------------------------------------------------
ns.playerProfessions = {} -- [skillLine] = { skillLine, name, rank, maxRank, icon, spellID }
ns.liveRecipes = {}       -- [recipeID] = { recipeID, skillLine, name, icon, categoryID, categoryName, learned, relativeDifficulty, outputItemID, numMade, reagents }
ns.categoriesBySkill = {} -- [skillLine] = { [catID] = name }
ns.currentSkillLine = nil
ns.selectedRecipeBySkill = {}

function ns:GetProfessionName(skillLine)
	if not skillLine then
		return "?"
	end
	if self.lang == "ru" or self.lang == "en" then
		local locKey = "PROF_" .. tostring(skillLine)
		if self.Locales[self.lang] and self.Locales[self.lang][locKey] then
			return self.Locales[self.lang][locKey]
		end
	end
	local p = self.playerProfessions[skillLine]
	if p and p.name then
		return p.name
	end
	local spellID = self.PROF_SPELLS[skillLine]
	if spellID and C_Spell and C_Spell.GetSpellName then
		local n = C_Spell.GetSpellName(spellID)
		if n then
			return n
		end
	end
	return L["PROF_" .. tostring(skillLine)] or ("Profession #" .. tostring(skillLine))
end

local SKILLLINE_REMAP = {
	[2937] = 171,
	[2938] = 164,
	[2939] = 185,
	[2940] = 333,
	[2941] = 202,
	[2942] = 129,
	[2943] = 356,
	[2944] = 182,
	[2945] = 165,
	[2946] = 186,
	[2947] = 393,
	[2948] = 197,
}

function ns.NormalizeSkillLine(id, name)
	if name and ns.PROF_NAME_TO_SKILLLINE[name] then
		return ns.PROF_NAME_TO_SKILLLINE[name]
	end
	if name and ns.ProfessionSkillLines and ns.ProfessionSkillLines[name] then
		return ns.ProfessionSkillLines[name]
	end
	if id and SKILLLINE_REMAP[id] then
		return SKILLLINE_REMAP[id]
	end
	if id and ns.PROF_SPELLS[id] then
		return id
	end
	if name then
		for sl, sp in pairs(ns.PROF_SPELLS) do
			local spName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sp)
			if spName and spName == name then
				return sl
			end
		end
		local smeltName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(2656)
		if smeltName and smeltName == name then
			return 186
		end
	end
	return id
end

function ns:ScanPlayerProfessions()
	local found = {}
	if GetProfessions and GetProfessionInfo then
		local p1, p2, p3, p4, p5, p6, p7 = GetProfessions()
		for _, idx in ipairs({ p1, p2, p3, p4, p5, p6, p7 }) do
			if idx then
				local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
				local norm = ns.NormalizeSkillLine(skillLine, name)
				if norm and self.PROF_SPELLS[norm] then
					found[norm] = {
						skillLine = norm,
						professionID = skillLine,
						name = name or self:GetProfessionName(norm),
						rank = rank or 1,
						maxRank = maxRank or 75,
						icon = icon or self.PROF_ICONS[norm],
						spellID = (norm == 186 and IsPlayerSpell and IsPlayerSpell(2656) and 2656) or self.PROF_SPELLS[norm],
					}
				end
			end
		end
	end
	for sl, spellID in pairs(self.PROF_SPELLS) do
		if not found[sl] and IsPlayerSpell and (IsPlayerSpell(spellID) or (sl == 186 and IsPlayerSpell(2656))) then
			found[sl] = {
				skillLine = sl,
				name = self:GetProfessionName(sl),
				rank = (self.playerProfessions[sl] and self.playerProfessions[sl].rank) or 1,
				maxRank = (self.playerProfessions[sl] and self.playerProfessions[sl].maxRank) or 75,
				icon = self.PROF_ICONS[sl],
				spellID = (sl == 186 and IsPlayerSpell(2656) and 2656) or spellID,
			}
		end
	end
	if next(found) then
		self.playerProfessions = found
		if self.charDB then
			self.charDB.professions = self.playerProfessions
		end
	end
end

function ns:IsRecipeLearned(recipeID)
	local live = self.liveRecipes[recipeID]
	if live and live.learned ~= nil then
		return live.learned
	end
	if self.charDB and self.charDB.learned and self.charDB.learned[recipeID] then
		return true
	end
	if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
		local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
		if ok and info and info.learned then
			if self.charDB and self.charDB.learned then
				self.charDB.learned[recipeID] = true
			end
			return true
		end
	end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, recipeID)
		if ok and known then
			return true
		end
	end
	if IsPlayerSpell then
		local ok, known = pcall(IsPlayerSpell, recipeID)
		if ok and known then
			return true
		end
	end
	-- Если у персонажа есть Горное дело (186), но окно выплавки ещё ни разу не открывалось,
	-- считаем базовые рецепты выплавки по текущему навыку Горного дела доступными
	local rData = self.RecipeData and self.RecipeData[recipeID]
	if rData and rData.skillLine == 186 and self.playerProfessions[186] then
		local miningRank = self.playerProfessions[186].rank or 1
		local reqSkill, _, isTrainer = self:GetRecipeRequiredSkill(recipeID)
		local isBasic = self.BasicRecipes and self.BasicRecipes[recipeID]
		if (isBasic or isTrainer) and miningRank >= (reqSkill or 1) then
			return true
		end
	end
	return false
end

function ns:ScanActiveTradeSkill()
	if not C_TradeSkillUI then
		return false
	end
	if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then
		return false
	end
	if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then
		return false
	end

	local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	local childInfo = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	local rawID = (childInfo and childInfo.parentProfessionID) or (baseInfo and baseInfo.professionID)
	local rawName = (childInfo and childInfo.parentProfessionName) or (baseInfo and baseInfo.professionName)
	local rank = (childInfo and childInfo.skillLevel) or (baseInfo and baseInfo.skillLevel) or 0
	local maxRank = (childInfo and childInfo.maxSkillLevel) or (baseInfo and baseInfo.maxSkillLevel) or 0

	local skillLine = ns.NormalizeSkillLine(rawID, rawName)
	if not skillLine or not self.PROF_SPELLS[skillLine] then
		return false
	end

	self.currentSkillLine = skillLine
	local prevProf = self.playerProfessions[skillLine]
	self.playerProfessions[skillLine] = {
		skillLine = skillLine,
		professionID = (rawID and rawID > 0 and rawID) or (prevProf and prevProf.professionID) or skillLine,
		name = rawName or self:GetProfessionName(skillLine),
		rank = rank > 0 and rank or ((prevProf and prevProf.rank) or 1),
		maxRank = maxRank > 0 and maxRank or ((prevProf and prevProf.maxRank) or 75),
		icon = self.PROF_ICONS[skillLine],
		spellID = self.PROF_SPELLS[skillLine],
	}

	self.categoriesBySkill[skillLine] = self.categoriesBySkill[skillLine] or {}
	local learnedMap = self.charDB and self.charDB.learned or {}

	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs() or {}
	for _, recipeID in ipairs(recipeIDs) do
		local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info then
			local catID = info.categoryID or 0
			if catID > 0 and C_TradeSkillUI.GetCategoryInfo and not self.categoriesBySkill[skillLine][catID] then
				local catInfo = C_TradeSkillUI.GetCategoryInfo(catID)
				if catInfo and catInfo.name then
					self.categoriesBySkill[skillLine][catID] = catInfo.name
				end
			end

			local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
			local reagents = nil
			local outItemID = schematic and schematic.outputItemID
			local numMade = 1
			if schematic then
				local qMin = schematic.quantityMin or 1
				local qMax = schematic.quantityMax or qMin
				numMade = (qMin + qMax) / 2
				if schematic.reagentSlotSchematics then
					reagents = {}
					for _, slot in ipairs(schematic.reagentSlotSchematics) do
						if slot.reagents and slot.reagents[1] and slot.reagents[1].itemID and (slot.quantityRequired or 0) > 0 then
							reagents[#reagents + 1] = {
								itemID = slot.reagents[1].itemID,
								quantity = slot.quantityRequired,
							}
						end
					end
				end
			end

			if info.learned then
				learnedMap[recipeID] = true
			end

			local diffKey = "optimal"
			if info.relativeDifficulty == 1 then
				diffKey = "medium"
			elseif info.relativeDifficulty == 2 then
				diffKey = "easy"
			elseif info.relativeDifficulty == 3 then
				diffKey = "trivial"
			end

			self.liveRecipes[recipeID] = {
				recipeID = recipeID,
				skillLine = skillLine,
				name = info.name,
				icon = info.icon,
				categoryID = catID,
				categoryName = self.categoriesBySkill[skillLine][catID],
				learned = info.learned and true or false,
				difficulty = diffKey,
				outputItemID = outItemID,
				numMade = numMade,
				reagents = reagents,
				recipeType = schematic and schematic.recipeType,
			}

			if outItemID and outItemID > 0 and self.RegisterProducedItem then
				self:RegisterProducedItem(outItemID, recipeID)
			end
		end
	end
	if self.charDB then
		self.charDB.learned = learnedMap
		self.charDB.professions = self.playerProfessions
	end
	if self.InvalidateCraftCounts then
		self:InvalidateCraftCounts()
	end
	return true
end

-- Скрывает нативный ProfessionsFrame (уводит за экран и делает прозрачным),
-- сохраняя сессию C_TradeSkillUI открытой для крафта в WoW Forever
function ns:SuppressBlizzardFrame()
	if not ProfessionsFrame or self.bypassIntercept then
		return
	end
	if not self.blizzFrameHooked then
		self.blizzFrameHooked = true
		ProfessionsFrame:HookScript("OnShow", function()
			if not ns.bypassIntercept then
				ns:SuppressBlizzardFrame()
			end
		end)
	end
	ProfessionsFrame:SetAlpha(0)
	if not InCombatLockdown() then
		ProfessionsFrame:ClearAllPoints()
		ProfessionsFrame:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -500, 500)
	end
end

function ns:RestoreBlizzardFrame()
	if not ProfessionsFrame then
		return
	end
	ProfessionsFrame:SetAlpha(1)
	if not InCombatLockdown() then
		ProfessionsFrame:ClearAllPoints()
		ProfessionsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	end
end

function ns:GetActiveClientSkillLine()
	if not C_TradeSkillUI then
		return nil
	end
	local frameShown = (ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown())
	if not frameShown then
		return nil
	end
	local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	local childInfo = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	local rawID = (childInfo and childInfo.parentProfessionID) or (baseInfo and baseInfo.professionID)
	local rawName = (childInfo and childInfo.parentProfessionName) or (baseInfo and baseInfo.professionName)
	local norm = ns.NormalizeSkillLine(rawID, rawName)
	if norm and self.PROF_SPELLS[norm] then
		return norm
	end
	if C_TradeSkillUI.GetAllRecipeIDs then
		local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
		if ok and type(ids) == "table" then
			for _, id in ipairs(ids) do
				local r = self.RecipeData and self.RecipeData[id]
				if r and r.skillLine then
					return r.skillLine
				end
			end
		end
	end
	return nil
end

function ns:IsClientRecipeReady(recipeID)
	if not recipeID or not C_TradeSkillUI then
		return false
	end
	local frameShown = (ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown())
	if not frameShown then
		return false
	end
	if C_TradeSkillUI.IsTradeSkillReady then
		local ok, ready = pcall(C_TradeSkillUI.IsTradeSkillReady)
		if ok and ready == false then
			return false
		end
	end
	local rec = self:GetRecipeRecord(recipeID)
	local activeSL = self:GetActiveClientSkillLine()
	if rec and rec.skillLine and activeSL and rec.skillLine ~= activeSL then
		return false
	end
	if C_TradeSkillUI.GetRecipeInfo then
		local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
		return ok and type(info) == "table"
	end
	return activeSL ~= nil
end

function ns:FindFirstLearnedRecipe(skillLine)
	local list = self.RecipesBySkill and self.RecipesBySkill[skillLine]
	if list then
		for _, rID in ipairs(list) do
			if self:IsRecipeLearned(rID) then
				return rID
			end
		end
		return list[1]
	end
	return nil
end

function ns:OpenClientTradeSkill(skillLine, recipeID)
	if not skillLine or (InCombatLockdown and InCombatLockdown()) then
		return false
	end
	self:SuppressBlizzardFrame()
	local profInfo = self.playerProfessions[skillLine]
	local opened = false

	-- 1. C_TradeSkillUI.OpenTradeSkill с родным professionID Forever или классическим skillLine
	if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
		if profInfo and profInfo.professionID then
			local ok, res = pcall(C_TradeSkillUI.OpenTradeSkill, profInfo.professionID)
			if ok and res then
				opened = true
			end
		end
		if not opened and (not profInfo or profInfo.professionID ~= skillLine) then
			local ok, res = pcall(C_TradeSkillUI.OpenTradeSkill, skillLine)
			if ok and res then
				opened = true
			end
		end
	end

	-- 2. C_TradeSkillUI.OpenRecipe открывает окно нужной профессии напрямую по рецепту в WoW Forever
	local targetRecipe = recipeID or self.selectedRecipeBySkill[skillLine] or self:FindFirstLearnedRecipe(skillLine)
	if not opened and targetRecipe and C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
		local ok = pcall(C_TradeSkillUI.OpenRecipe, targetRecipe)
		if ok and self:GetActiveClientSkillLine() == skillLine then
			opened = true
		end
	end

	-- 3. Fallback через заклинание профессии (для Горного дела 186 — Выплавка металлов 2656)
	if not opened and self:GetActiveClientSkillLine() ~= skillLine then
		local spellID = (skillLine == 186 and 2656) or (profInfo and profInfo.spellID) or self.PROF_SPELLS[skillLine]
		if spellID then
			local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
				or (profInfo and profInfo.name)
			if spellName and CastSpellByName then
				pcall(CastSpellByName, spellName)
			elseif CastSpellByID then
				pcall(CastSpellByID, spellID)
			end
		end
	end

	self:SuppressBlizzardFrame()
	return self:GetActiveClientSkillLine() == skillLine
end

function ns:ExecuteCraftRecipe(recipeID, count)
	if not recipeID or (InCombatLockdown and InCombatLockdown()) then
		return false
	end
	count = math.max(1, count or 1)
	local rec = self:GetRecipeRecord(recipeID)
	local skillLine = (rec and rec.skillLine) or self.currentSkillLine

	self.bypassIntercept = false
	self:SuppressBlizzardFrame()

	if not self:IsClientRecipeReady(recipeID) then
		self:OpenClientTradeSkill(skillLine, recipeID)
	end
	if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
		pcall(C_TradeSkillUI.OpenRecipe, recipeID)
	end
	self:SuppressBlizzardFrame()

	if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
		pcall(C_TradeSkillUI.CraftRecipe, recipeID, count)
		return true
	end
	return false
end

function ns:SwitchToProfession(skillLine, recipeID)
	if not skillLine then
		return
	end
	self.currentSkillLine = skillLine
	self.bypassIntercept = false
	self:SuppressBlizzardFrame()

	if self:GetActiveClientSkillLine() ~= skillLine then
		self:OpenClientTradeSkill(skillLine, recipeID)
	end
	self:SuppressBlizzardFrame()
	if self.RefreshMainWindow then
		self:RefreshMainWindow()
	end
end

function ns:OpenBlizzardProfessions()
	self.bypassIntercept = true
	if self.HideMainWindow then
		self:HideMainWindow()
	end
	self:RestoreBlizzardFrame()
	local activeClientSL = self:GetActiveClientSkillLine()
	if not activeClientSL and self.currentSkillLine then
		local spellID = (self.currentSkillLine == 186 and 2656) or self.PROF_SPELLS[self.currentSkillLine]
		local spellName = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
		if spellName and CastSpellByName then
			pcall(CastSpellByName, spellName)
		end
	end
	if ProfessionsFrame then
		ShowUIPanel(ProfessionsFrame)
	end
end

-------------------------------------------------------------------------------
-- Инициализация и обработка событий
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"PLAYER_ENTERING_WORLD",
	"TRADE_SKILL_SHOW",
	"TRADE_SKILL_DATA_SOURCE_CHANGED",
	"TRADE_SKILL_LIST_UPDATE",
	"TRADE_SKILL_DETAILS_UPDATE",
	"TRADE_SKILL_CLOSE",
	"SKILL_LINES_CHANGED",
	"NEW_RECIPE_LEARNED",
	"GET_ITEM_INFO_RECEIVED",
	"ITEM_DATA_LOAD_RESULT",
}) do
	pcall(eventFrame.RegisterEvent, eventFrame, ev)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		TradeFlowDB = TradeFlowDB or {}
		ns.db = TradeFlowDB
		ns.db.lang = ns.db.lang or ns.DefaultLanguage()
		ns.lang = ns.db.lang
		ns.db.options = ns.db.options or {
			autoSubcrafts = true,
			includeTrainerInRoute = true,
			deductVendorInRoute = true,
			filterCraftable = false,
			filterSkillUp = false,
			showUnlearned = false,
			sortMode = "difficulty",
		}
		ns.db.vendorPrices = ns.db.vendorPrices or {}
		ns.db.trainerFees = ns.db.trainerFees or {}
		ns.db.realms = ns.db.realms or {}

		local rKey = ns:RealmKey()
		ns.db.realms[rKey] = ns.db.realms[rKey] or { chars = {} }
		ns.realmDB = ns.db.realms[rKey]

		local cKey = ns:CharKey()
		ns.realmDB.chars[cKey] = ns.realmDB.chars[cKey] or {
			bags = {},
			bank = {},
			learned = {},
			professions = {},
			queue = {},
			skippedRecipes = {},
			targets = {},
		}
		ns.charDB = ns.realmDB.chars[cKey]
		if ns.charDB.professions then
			for sl, p in pairs(ns.charDB.professions) do
				ns.playerProfessions[sl] = p
			end
		end
		if ns.InitInventoryIndex then
			ns:InitInventoryIndex()
		end
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		ns:ScanPlayerProfessions()
		if ns.ScanBagsNow then
			ns:ScanBagsNow()
		end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
		ns:ScanPlayerProfessions()
		local ok = ns:ScanActiveTradeSkill()
		if ok and not ns.bypassIntercept then
			ns:SuppressBlizzardFrame()
			if ns.ShowMainWindow then
				ns:ShowMainWindow()
			end
		end
	elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DETAILS_UPDATE" or event == "SKILL_LINES_CHANGED" or event == "NEW_RECIPE_LEARNED" then
		if not ns.bypassIntercept then
			ns:SuppressBlizzardFrame()
		end
		if ns.mainFrame and ns.mainFrame:IsShown() then
			ns:ScanActiveTradeSkill()
			if ns.RefreshVisibleUI then
				ns:RefreshVisibleUI()
			end
		end
	elseif event == "TRADE_SKILL_CLOSE" then
		-- Не возвращаем ProfessionsFrame при переключении профессии, пока открыто окно TradeFlow
		if ns.bypassIntercept then
			ns.bypassIntercept = false
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
		ScheduleItemDataRefresh()
	end
end)

SLASH_TRADEFLOW1 = "/tradeflow"
SLASH_TRADEFLOW2 = "/tf"
SlashCmdList.TRADEFLOW = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "lang" then
		ns:ToggleLanguage()
	elseif msg == "blizz" or msg == "blizzard" then
		ns:OpenBlizzardProfessions()
	else
		if ns.ToggleMainWindow then
			ns:ToggleMainWindow()
		end
	end
end

