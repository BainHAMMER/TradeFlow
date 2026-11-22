local ADDON_NAME, ns = ...
local L = ns.L

ns.VERSION = "1.0.10"
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
	[186] = "Interface\\Icons\\Trade_Mining",
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

-- Цена за +1 навык: расход как обычная сумма, доход (цена меньше нуля) — зелёным «+сумма»
function ns.FormatSkillUpCost(copper)
	if copper and copper < 0 then
		return ns.FormatMoney(-copper, true)
	end
	return ns.FormatMoney(copper)
end

-- Компактное форматирование длительности в ч/м/с
function ns.FormatDuration(seconds)
	if type(seconds) ~= "number" or seconds < 0 then
		return "-"
	end
	if seconds < 10 then
		local rounded = math.floor(seconds + 0.5)
		if math.abs(seconds - rounded) >= 0.05 then
			return string.format("%.1f%s", seconds, L["TIME_SEC"])
		end
		return string.format("%d%s", rounded, L["TIME_SEC"])
	end
	local total = math.floor(seconds + 0.5)
	local h = math.floor(total / 3600)
	local m = math.floor((total % 3600) / 60)
	local s = total % 60
	if h > 0 then
		if m > 0 then
			return string.format("%d%s %d%s", h, L["TIME_HOUR"], m, L["TIME_MIN"])
		end
		return string.format("%d%s", h, L["TIME_HOUR"])
	end
	if m > 0 then
		if s > 0 then
			return string.format("%d%s %d%s", m, L["TIME_MIN"], s, L["TIME_SEC"])
		end
		return string.format("%d%s", m, L["TIME_MIN"])
	end
	return string.format("%d%s", s, L["TIME_SEC"])
end

local requestedSpellLoads = {}

-- Время изготовления одной единицы рецепта в секундах (по данным клиента)
function ns:GetRecipeCastTime(recipeID)
	if not recipeID or recipeID <= 0 then
		return nil
	end
	local castMs
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(recipeID)
		if info then
			castMs = info.castTime
		end
	end
	if castMs == nil and GetSpellInfo then
		local _, _, _, ct = GetSpellInfo(recipeID)
		castMs = ct
	end
	if type(castMs) ~= "number" or castMs < 0 then
		if not requestedSpellLoads[recipeID] and C_Spell and C_Spell.RequestLoadSpellData then
			requestedSpellLoads[recipeID] = true
			pcall(C_Spell.RequestLoadSpellData, recipeID)
		end
		return nil
	end
	return castMs / 1000
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
local requestedItemLoads = {}
local failedItemLoads = {}

function ns:RequestItemData(itemID)
	if not itemID or itemID <= 0 or requestedItemLoads[itemID] or failedItemLoads[itemID] then
		return
	end
	requestedItemLoads[itemID] = true
	if C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
end

-- Гарантирует загрузку данных предметов по itemID перед вызовом Auctionator API
function ns:WithLoadedItems(items, callback)
	if not items or #items == 0 then
		callback()
		return
	end
	if ContinuableContainer and Item and Item.CreateFromItemID then
		local container = ContinuableContainer:Create()
		for _, entry in ipairs(items) do
			if entry.itemID and entry.itemID > 0 then
				container:AddContinuable(Item:CreateFromItemID(entry.itemID))
			end
		end
		container:ContinueOnLoad(callback)
		return
	end
	local allLoaded = true
	for _, entry in ipairs(items) do
		local _, _, _, _, loaded = self:GetItemDisplay(entry.itemID)
		if not loaded then
			allLoaded = false
		end
	end
	if allLoaded then
		callback()
	elseif C_Timer and C_Timer.After then
		C_Timer.After(0.25, callback)
	else
		callback()
	end
end

local function ScheduleItemDataRefresh()
	if pendingItemRefresh or not (ns.mainFrame and ns.mainFrame:IsShown()) then
		return
	end
	pendingItemRefresh = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0.5, function()
			pendingItemRefresh = false
			if ns.mainFrame and ns.mainFrame:IsShown() then
				if ns.InvalidatePrices then
					ns:InvalidatePrices()
				elseif ns.RefreshVisibleUI then
					ns:RefreshVisibleUI()
				end
			end
		end)
	end
end

local pendingTradeSkillRefresh = false
local function ScheduleTradeSkillRefresh()
	if pendingTradeSkillRefresh or not (ns.mainFrame and ns.mainFrame:IsShown()) then
		return
	end
	pendingTradeSkillRefresh = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0.15, function()
			pendingTradeSkillRefresh = false
			if ns.mainFrame and ns.mainFrame:IsShown() then
				ns:ScanActiveTradeSkill(true)
				-- ScanPlayerProfessions читает актуальный rank/maxRank из GetProfessionInfo
				-- (C_TradeSkillUI на 1.60.1 может отдавать устаревший skillLevel до переоткрытия)
				ns:ScanPlayerProfessions()
				if ns.RefreshVisibleUI then
					ns:RefreshVisibleUI()
				end
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
		self:RequestItemData(itemID)
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

function ns:AddDisenchantTooltipLines(tooltip, deNet, yields, reqEnch)
	if not (tooltip and yields and #yields > 0) then
		return
	end
	tooltip:AddDoubleLine(
		string.format(L["DE_TOOLTIP_HEADER"], reqEnch or 1),
		deNet and ns.FormatMoney(deNet) or "-",
		0.75, 0.65, 1.0, 1, 1, 1
	)
	for _, y in ipairs(yields) do
		local yName, _, _, _, _, yHex = self:GetItemDisplay(y.itemID)
		local p = self:GetAuctionPrice(y.itemID)
		tooltip:AddDoubleLine(
			string.format("  %s%s|r %s", yHex or "|cffffffff", yName, ns.FormatDisenchantCount(y)),
			string.format("%.1f%% (%s)", y.chance * 100, p and ns.FormatMoney(p) or "-"),
			0.85, 0.85, 0.85, 0.8, 0.8, 0.8
		)
	end
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
	if self.db and self.db.options and self.db.options.tooltipExtraInfo == true then
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
				or (outSource == "disenchant" and L["OUTPUT_VALUE_DE"])
				or (outSource == "vendor" and L["OUTPUT_VALUE_VENDOR"])
				or L["OUTPUT_VALUE"]
			GameTooltip:AddDoubleLine(outLabel, ns.FormatMoney(outVal), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		if profit then
			GameTooltip:AddDoubleLine(L["NET_PROFIT"], ns.FormatMoney(profit, true), 0.8, 0.8, 0.8, 1, 1, 1)
		end
		local rec = self:GetRecipeRecord(recipeID)
		if rec and rec.outputItemID and self.GetItemDisenchantInfo then
			local deNet, yields, reqEnch = self:GetItemDisenchantInfo(rec.outputItemID)
			if yields and #yields > 0 then
				GameTooltip:AddLine(" ")
				self:AddDisenchantTooltipLines(GameTooltip, deNet, yields, reqEnch)
			end
		end
	end
	GameTooltip:AddLine(L["SHIFT_CLICK_HINT"], 0.55, 0.75, 1.0, true)
	GameTooltip:AddLine(L["FAVORITE_RCLICK_HINT"], 0.65, 0.90, 0.65, true)
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
		if self.snipeAddBox and self.snipeAddBox:IsVisible() and self.snipeAddBox:HasFocus() then
			local label = (name and name ~= "" and not name:find("#%d+")) and name or tostring(targetItemID)
			self.snipeAddBox.pickedItemID = targetItemID
			self.snipeAddBox:SetText(label)
			if self.snipeAddBox.SetCursorPosition then
				self.snipeAddBox:SetCursorPosition(#label)
			end
			return true
		end
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
		local changed = false
		local prev = self.playerProfessions or {}
		for sl, cur in pairs(found) do
			local p = prev[sl]
			if not p or p.rank ~= cur.rank or p.maxRank ~= cur.maxRank then
				changed = true
				break
			end
		end
		if not changed then
			for sl in pairs(prev) do
				if not found[sl] then
					changed = true
					break
				end
			end
		end
		self.playerProfessions = found
		if self.charDB then
			self.charDB.professions = self.playerProfessions
		end
		if changed and self.InvalidateProfitCache then
			self.InvalidateProfitCache()
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

local favIconMarkup = nil
function ns:GetFavoriteIconMarkup()
	if favIconMarkup then
		return favIconMarkup
	end
	if C_Texture and C_Texture.GetAtlasInfo then
		if C_Texture.GetAtlasInfo("auctionhouse-icon-favorite") then
			favIconMarkup = "|A:auctionhouse-icon-favorite:13:13:0:0|a "
			return favIconMarkup
		elseif C_Texture.GetAtlasInfo("tradeskills-star") then
			favIconMarkup = "|A:tradeskills-star:13:13:0:0|a "
			return favIconMarkup
		end
	end
	favIconMarkup = "|TInterface\\Common\\FavoritesIcon:14:14:0:0:32:32:0:26:0:26|t "
	return favIconMarkup
end

function ns:IsRecipeFavorite(recipeID)
	if not recipeID or recipeID <= 0 then
		return false
	end
	local p = self.pendingBlizzFavorites and self.pendingBlizzFavorites[recipeID]
	if type(p) == "table" and p.target ~= nil then
		return p.target == true
	end
	if self.charDB and self.charDB.favorites and self.charDB.favorites[recipeID] ~= nil then
		return self.charDB.favorites[recipeID] == true
	end
	if self.liveRecipes and self.liveRecipes[recipeID] and self.liveRecipes[recipeID].favorite ~= nil then
		return self.liveRecipes[recipeID].favorite == true
	end
	return false
end

local function ResolveBlizzFavoriteState(recipeID, blizzFav, pending, now)
	local p = pending and pending[recipeID]
	if type(p) ~= "table" or p.target == nil then
		return blizzFav
	end
	if blizzFav == p.target then
		pending[recipeID] = nil
		return blizzFav
	end
	if not p.sent and C_TradeSkillUI and C_TradeSkillUI.SetRecipeFavorite then
		pcall(C_TradeSkillUI.SetRecipeFavorite, recipeID, p.target)
		p.sent = true
		p.ts = now
		return p.target
	end
	if (now - (p.ts or 0)) <= 3.0 then
		return p.target
	end
	pending[recipeID] = nil
	return blizzFav
end

function ns:SyncFavoritesFromBlizzard()
	if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs or not self:GetActiveClientSkillLine() then
		return false
	end
	local favMap = (self.charDB and self.charDB.favorites) or {}
	local pending = self.pendingBlizzFavorites
	local now = GetTime and GetTime() or 0
	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs() or {}
	for _, recipeID in ipairs(recipeIDs) do
		local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
		local blizzFav = (info and info.favorite == true)
			or (C_TradeSkillUI.IsRecipeFavorite and select(2, pcall(C_TradeSkillUI.IsRecipeFavorite, recipeID)) == true)
			or false
		local isFav = ResolveBlizzFavoriteState(recipeID, blizzFav, pending, now)
		favMap[recipeID] = isFav and true or nil
		if self.liveRecipes and self.liveRecipes[recipeID] then
			self.liveRecipes[recipeID].favorite = isFav
		end
	end
	if self.charDB then
		self.charDB.favorites = favMap
	end
	return true
end

function ns:ToggleRecipeFavorite(recipeID)
	if not recipeID or recipeID <= 0 then
		return false
	end
	local newFav = not self:IsRecipeFavorite(recipeID)
	if self.charDB then
		self.charDB.favorites = self.charDB.favorites or {}
		self.charDB.favorites[recipeID] = newFav and true or nil
	end
	if self.liveRecipes and self.liveRecipes[recipeID] then
		self.liveRecipes[recipeID].favorite = newFav
	end

	local sent = false
	local rec = self:GetRecipeRecord(recipeID)
	local activeSL = self.GetActiveClientSkillLine and self:GetActiveClientSkillLine() or nil
	if C_TradeSkillUI and C_TradeSkillUI.SetRecipeFavorite and (not rec or not rec.skillLine or activeSL == rec.skillLine) then
		local canFav = true
		if C_TradeSkillUI.CanFavoriteRecipe then
			local okC, resC = pcall(C_TradeSkillUI.CanFavoriteRecipe, recipeID)
			if okC and resC == false then
				canFav = false
			end
		end
		if canFav then
			local ok = pcall(C_TradeSkillUI.SetRecipeFavorite, recipeID, newFav)
			if ok then
				sent = true
			end
		end
	end
	self.pendingBlizzFavorites = self.pendingBlizzFavorites or {}
	self.pendingBlizzFavorites[recipeID] = {
		target = newFav,
		sent = sent,
		ts = GetTime and GetTime() or 0,
	}

	if self.RefreshRecipeList then
		self:RefreshRecipeList()
	end
	if self.RefreshDetailsView then
		self:RefreshDetailsView()
	end
	local mod = self.modules and self.modules.byId and self.modules.byId["profit"]
	if mod and mod.view and mod.view:IsVisible() and mod.OnRefresh then
		mod:OnRefresh()
	end
	return newFav
end

local function NonZero(v)
	return (v and v ~= 0) and v or nil
end

local function NonEmpty(s)
	return (type(s) == "string" and s ~= "") and s or nil
end

function ns:ScanActiveTradeSkill(preserveSkillLine)
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
	local rawID = NonZero(childInfo and childInfo.parentProfessionID)
		or NonZero(childInfo and childInfo.professionID)
		or NonZero(baseInfo and baseInfo.professionID)
	local rawName = NonEmpty(childInfo and childInfo.parentProfessionName)
		or NonEmpty(baseInfo and baseInfo.professionName)
		or NonEmpty(childInfo and childInfo.professionName)
	local rank = NonZero(childInfo and childInfo.skillLevel) or NonZero(baseInfo and baseInfo.skillLevel) or 0
	local maxRank = NonZero(childInfo and childInfo.maxSkillLevel) or NonZero(baseInfo and baseInfo.maxSkillLevel) or 0

	local skillLine = ns.NormalizeSkillLine(rawID, rawName)
	if not skillLine or not self.PROF_SPELLS[skillLine] then
		return false
	end

	if not (preserveSkillLine and self.currentSkillLine and self.PROF_SPELLS[self.currentSkillLine]) then
		self.currentSkillLine = skillLine
	end
	local prevProf = self.playerProfessions[skillLine]
	local addedProf = (prevProf == nil)
	self.playerProfessions[skillLine] = {
		skillLine = skillLine,
		professionID = (rawID and rawID > 0 and rawID) or (prevProf and prevProf.professionID) or skillLine,
		name = rawName or self:GetProfessionName(skillLine),
		rank = rank > 0 and rank or ((prevProf and prevProf.rank) or 1),
		maxRank = maxRank > 0 and maxRank or ((prevProf and prevProf.maxRank) or 75),
		-- Значок из GetProfessionInfo (ScanPlayerProfessions) не заменяем: у горного дела
		-- открывается «Выплавка металлов», и значок в шапке менялся с кирки на выплавку
		icon = (prevProf and prevProf.icon) or self.PROF_ICONS[skillLine],
		spellID = self.PROF_SPELLS[skillLine],
	}

	self.categoriesBySkill[skillLine] = self.categoriesBySkill[skillLine] or {}
	local learnedMap = self.charDB and self.charDB.learned or {}
	local favMap = (self.charDB and self.charDB.favorites) or {}
	local pendingFav = self.pendingBlizzFavorites
	local now = GetTime and GetTime() or 0
	local newlyLearned = false

	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs() or {}
	for _, recipeID in ipairs(recipeIDs) do
		local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info then
			local blizzFav = (info.favorite == true)
				or (C_TradeSkillUI.IsRecipeFavorite and select(2, pcall(C_TradeSkillUI.IsRecipeFavorite, recipeID)) == true)
				or false
			local isFav = ResolveBlizzFavoriteState(recipeID, blizzFav, pendingFav, now)
			favMap[recipeID] = isFav and true or nil
			local catID = info.categoryID or 0
			if catID > 0 and C_TradeSkillUI.GetCategoryInfo and not self.categoriesBySkill[skillLine][catID] then
				local catInfo = C_TradeSkillUI.GetCategoryInfo(catID)
				if catInfo and catInfo.name then
					self.categoriesBySkill[skillLine][catID] = catInfo.name
				end
			end

			local prevLive = self.liveRecipes[recipeID]
			local reagents = prevLive and prevLive.reagents
			local outItemID = prevLive and prevLive.outputItemID
			local numMade = (prevLive and prevLive.numMade) or 1
			local recipeType = prevLive and prevLive.recipeType
			if not (prevLive and prevLive.reagents) then
				local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
				if schematic then
					outItemID = schematic.outputItemID
					local qMin = schematic.quantityMin or 1
					local qMax = schematic.quantityMax or qMin
					numMade = (qMin + qMax) / 2
					recipeType = schematic.recipeType
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
			end

			if info.learned then
				if not learnedMap[recipeID] then
					newlyLearned = true
				end
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

			local bundledSL = self.RecipeData and self.RecipeData[recipeID] and self.RecipeData[recipeID].skillLine
			self.liveRecipes[recipeID] = {
				recipeID = recipeID,
				skillLine = bundledSL or skillLine,
				name = info.name,
				icon = info.icon,
				categoryID = catID,
				categoryName = self.categoriesBySkill[skillLine][catID],
				learned = info.learned and true or false,
				favorite = isFav,
				difficulty = diffKey,
				outputItemID = outItemID,
				numMade = numMade,
				reagents = reagents,
				recipeType = recipeType,
				sourceText = (type(info.sourceText) == "string" and info.sourceText ~= "") and info.sourceText or nil,
			}

			if outItemID and outItemID > 0 and self.RegisterProducedItem then
				self:RegisterProducedItem(outItemID, recipeID)
			end
		end
	end
	if self.charDB then
		self.charDB.learned = learnedMap
		self.charDB.favorites = favMap
		self.charDB.professions = self.playerProfessions
	end
	if self.InvalidateCraftCounts then
		self:InvalidateCraftCounts()
	end
	if (newlyLearned or addedProf) and self.InvalidatePrices then
		self:InvalidatePrices(true)
	end
	return true
end

-- Скрывает нативный ProfessionsFrame (уводит за экран и делает прозрачным),
-- сохраняя сессию C_TradeSkillUI открытой для крафта в WoW Forever
-- WoW Forever: внутри ProfessionsFrame есть общая вкладка профессий (BookPage), на неё окно
-- открывается по K, если последней была она. Профессии, которых нет в TradeFlow (рыбалка),
-- тоже открываются в окне Blizzard. В обоих случаях TradeFlow своё окно не показывает,
-- поэтому окно Blizzard прятать нельзя. ns.blizzardOwnsTradeSkill ставится на
-- TRADE_SKILL_SHOW такой профессии. На TRADE_SKILL_SHOW профессии TradeFlow передаётся
-- force: Blizzard сама убирает BookPage при открытии профессии.
local function IsBlizzardBookPageShown()
	local page = ProfessionsFrame and ProfessionsFrame.BookPage
	return page and page:IsShown() or false
end

-- Открытая сейчас профессия (как Professions.GetEffectiveSkillLineID у Blizzard), nil если нет
local function GetOpenTradeSkillID()
	if not C_TradeSkillUI then
		return nil
	end
	-- Поля бывают равны 0 (в Lua это истина), поэтому каждое проверяется отдельно
	local function nonzero(v)
		if v and v ~= 0 then
			return v
		end
	end
	local child = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	return nonzero(child and child.parentProfessionID) or nonzero(child and child.professionID)
		or nonzero(base and base.professionID)
end

function ns:SuppressBlizzardFrame(force)
	if not ProfessionsFrame or self.bypassIntercept then
		return
	end
	if not self.blizzFrameHooked then
		self:HookBlizzardFrame()
	end
	if not force and not self.preferTradeFlow and (IsBlizzardBookPageShown() or self.blizzardOwnsTradeSkill) then
		self:RestoreBlizzardFrame()
		return
	end
	ProfessionsFrame:SetAlpha(0)
	if not InCombatLockdown() then
		ProfessionsFrame:ClearAllPoints()
		ProfessionsFrame:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -500, 500)
	end
end

function ns:HookBlizzardFrame()
	if not self.blizzFrameHooked then
		self.blizzFrameHooked = true
		ProfessionsFrame:HookScript("OnShow", function()
			if not ns.bypassIntercept then
				ns:SuppressBlizzardFrame()
			end
			ns:EnsureBlizzardReturnButton()
		end)
		ProfessionsFrame:HookScript("OnHide", function()
			if not ns.bypassIntercept and not ns.isSwitchingProfession and not ns.isHidingMain then
				if ns.mainFrame and ns.mainFrame:IsShown() and ns.HideMainWindow then
					ns.isClosingFromBlizz = true
					ns:HideMainWindow()
					ns.isClosingFromBlizz = false
				end
			end
		end)
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
	local rawID = NonZero(childInfo and childInfo.parentProfessionID)
		or NonZero(childInfo and childInfo.professionID)
		or NonZero(baseInfo and baseInfo.professionID)
	local rawName = NonEmpty(childInfo and childInfo.parentProfessionName)
		or NonEmpty(baseInfo and baseInfo.professionName)
		or NonEmpty(childInfo and childInfo.professionName)
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
	-- В WoW 1.60.1 вызов OpenTradeSkill / CastSpellByName из обычного скрипта блокируется Blizzard (ADDON_ACTION_BLOCKED).
	-- Переключение профессии в клиенте выполняется только через SecureActionButtonTemplate.
	return self:GetActiveClientSkillLine() == skillLine
end

function ns:GetProfessionSpellAttr(skillLine)
	if not skillLine then
		return nil
	end
	local profInfo = self.playerProfessions and self.playerProfessions[skillLine]
	local spellID = (skillLine == 186 and 2656)
		or (profInfo and profInfo.spellID)
		or (self.PROF_SPELLS and self.PROF_SPELLS[skillLine])
	if not spellID then
		return nil
	end
	local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
		or (GetSpellInfo and GetSpellInfo(spellID))
	return spellName or spellID
end

local profSwitchToken = 0
function ns:PrepareSecureProfSwitch()
	profSwitchToken = profSwitchToken + 1
	local tok = profSwitchToken
	self.isSwitchingProfession = true
	self.preferTradeFlow = true
	self.bypassIntercept = false
	if C_Timer and C_Timer.After then
		C_Timer.After(0.35, function()
			if profSwitchToken == tok then
				ns.isSwitchingProfession = false
			end
		end)
	end
end

-------------------------------------------------------------------------------
-- Наложение чар: автоопределение цели (CraftEnchant) и подтверждение замены Пробелом
-------------------------------------------------------------------------------
local ENCHANT_RECIPE_TYPE = (Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Enchant) or 2
local ENCHANT_VELLUM_ID = 38682

ns.enchantTargets = ns.enchantTargets or {}

local ENCHANT_SLOT_PATTERNS = {
	{ pattern = "нагрудник", slots = { 5 } },
	{ pattern = "chest",     slots = { 5 } },
	{ pattern = "наруч",     slots = { 9 } },
	{ pattern = "браслет",   slots = { 9 } },
	{ pattern = "bracer",    slots = { 9 } },
	{ pattern = "wrist",     slots = { 9 } },
	{ pattern = "плащ",      slots = { 15 } },
	{ pattern = "cloak",     slots = { 15 } },
	{ pattern = "back",      slots = { 15 } },
	{ pattern = "обув",      slots = { 8 } },
	{ pattern = "сапог",     slots = { 8 } },
	{ pattern = "ботин",     slots = { 8 } },
	{ pattern = "boots",     slots = { 8 } },
	{ pattern = "feet",      slots = { 8 } },
	{ pattern = "перчат",    slots = { 10 } },
	{ pattern = "gloves",    slots = { 10 } },
	{ pattern = "ожерел",    slots = { 2 } },
	{ pattern = "necklace",  slots = { 2 } },
	{ pattern = "щит",       slots = { 17 }, invTypes = { INVTYPE_SHIELD = true } },
	{ pattern = "shield",    slots = { 17 }, invTypes = { INVTYPE_SHIELD = true } },
	{ pattern = "левой рук", slots = { 17 }, invTypes = { INVTYPE_HOLDABLE = true } },
	{ pattern = "off-hand",  slots = { 17 }, invTypes = { INVTYPE_HOLDABLE = true } },
	{ pattern = "offhand",   slots = { 17 }, invTypes = { INVTYPE_HOLDABLE = true } },
	{ pattern = "двуруч",    slots = { 16 }, invTypes = { INVTYPE_2HWEAPON = true } },
	{ pattern = "2h weapon", slots = { 16 }, invTypes = { INVTYPE_2HWEAPON = true } },
	{ pattern = "оружи",     slots = { 16 } },
	{ pattern = "weapon",    slots = { 16 } },
	{ pattern = "кольц",     slots = { 11, 12 } },
	{ pattern = "ring",      slots = { 11, 12 } },
}

local function IsValidTargetLoc(loc, expectedItemID)
	if not (loc and loc.IsValid and loc:IsValid()) then
		return false
	end
	if C_Item and C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then
		return false
	end
	if expectedItemID and C_Item and C_Item.GetItemID and C_Item.GetItemID(loc) ~= expectedItemID then
		return false
	end
	return true
end

local function BuildItemLocationFromSaved(entry)
	if not (entry and ItemLocation) then
		return nil
	end
	if entry.guid and C_Item and C_Item.GetItemLocation then
		local loc = C_Item.GetItemLocation(entry.guid)
		if IsValidTargetLoc(loc, entry.itemID) then
			return loc
		end
		return nil
	end
	local loc = nil
	if entry.equipSlot and ItemLocation.CreateFromEquipmentSlot then
		loc = ItemLocation:CreateFromEquipmentSlot(entry.equipSlot)
	elseif entry.bag ~= nil and entry.slot ~= nil and ItemLocation.CreateFromBagAndSlot then
		loc = ItemLocation:CreateFromBagAndSlot(entry.bag, entry.slot)
	end
	if IsValidTargetLoc(loc, entry.itemID) then
		return loc
	end
	return nil
end

local function BuildTargetMeta(loc, isManual)
	if not loc then
		return nil
	end
	local itemID = C_Item and C_Item.GetItemID and C_Item.GetItemID(loc) or nil
	local itemLink = C_Item and C_Item.GetItemLink and C_Item.GetItemLink(loc) or nil
	local icon = C_Item and C_Item.GetItemIcon and C_Item.GetItemIcon(loc) or nil
	local name = C_Item and C_Item.GetItemName and C_Item.GetItemName(loc) or nil
	if (not name or not icon) and itemID and ns.GetItemDisplay then
		local dName, dIcon, _, dLink = ns:GetItemDisplay(itemID)
		name = name or dName
		icon = icon or dIcon
		itemLink = itemLink or dLink
	end
	return {
		itemID = itemID,
		itemLink = itemLink,
		icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
		name = name or (itemID and ("#" .. itemID)) or "?",
		isManual = isManual and true or false,
		isEquipped = loc.IsEquipmentSlot and loc:IsEquipmentSlot() or false,
	}
end

function ns:IsEnchantRecipe(recipeID)
	if not recipeID then
		return false
	end
	local live = self.liveRecipes and self.liveRecipes[recipeID]
	if live and live.recipeType ~= nil then
		return live.recipeType == ENCHANT_RECIPE_TYPE
	end
	if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
		local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
		if ok and sch and sch.recipeType ~= nil then
			return sch.recipeType == ENCHANT_RECIPE_TYPE
		end
	end
	local rec = self:GetRecipeRecord(recipeID)
	return rec ~= nil and rec.skillLine == 333 and not rec.outputItemID
end

function ns:SetEnchantTargetFromCursor(recipeID)
	if not (recipeID and CursorHasItem and CursorHasItem()) then
		return false
	end
	local loc = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem() or nil
	if not (loc and loc.IsValid and loc:IsValid()) then
		return false
	end
	local guid = C_Item and C_Item.GetItemGUID and C_Item.GetItemGUID(loc) or nil
	local itemID = C_Item and C_Item.GetItemID and C_Item.GetItemID(loc) or nil
	local saved = {
		guid = guid,
		itemID = itemID,
	}
	if loc.IsEquipmentSlot and loc:IsEquipmentSlot() and loc.GetEquipmentSlot then
		saved.equipSlot = loc:GetEquipmentSlot()
	elseif loc.IsBagAndSlot and loc:IsBagAndSlot() and loc.GetBagAndSlot then
		saved.bag, saved.slot = loc:GetBagAndSlot()
	end
	if not (saved.guid or saved.equipSlot or (saved.bag ~= nil and saved.slot ~= nil)) then
		return false
	end
	self.enchantTargets[recipeID] = saved
	if ClearCursor then
		ClearCursor()
	end
	return true
end

function ns:ClearEnchantTarget(recipeID)
	if recipeID then
		self.enchantTargets[recipeID] = nil
	end
end

function ns:ResolveEnchantTarget(recipeID)
	if not recipeID then
		return nil, nil
	end
	local manualEntry = self.enchantTargets and self.enchantTargets[recipeID]
	if manualEntry then
		local loc = BuildItemLocationFromSaved(manualEntry)
		if loc then
			return loc, BuildTargetMeta(loc, true)
		end
		self.enchantTargets[recipeID] = nil
	end

	-- 1. Штатный список целей от Blizzard (предпочитаем надетую экипировку, затем вещи в сумках, затем свиток)
	if C_TradeSkillUI and C_TradeSkillUI.GetEnchantItems and C_Item and C_Item.GetItemLocation then
		local ok, items = pcall(C_TradeSkillUI.GetEnchantItems, recipeID)
		if ok and type(items) == "table" and #items > 0 then
			local eqLoc, bagLoc, vellumLoc = nil, nil, nil
			for _, entry in ipairs(items) do
				local guid = (type(entry) == "string" and entry) or (type(entry) == "table" and entry.itemGUID)
				if guid then
					local loc = C_Item.GetItemLocation(guid)
					if loc and loc.IsValid and loc:IsValid() then
						if loc.IsEquipmentSlot and loc:IsEquipmentSlot() then
							eqLoc = eqLoc or loc
						else
							local itemID = C_Item.GetItemID and C_Item.GetItemID(loc)
							if itemID == ENCHANT_VELLUM_ID then
								vellumLoc = vellumLoc or loc
							else
								bagLoc = bagLoc or loc
							end
						end
					end
				end
			end
			local chosen = eqLoc or bagLoc or vellumLoc
			if chosen then
				return chosen, BuildTargetMeta(chosen, false)
			end
		end
	end

	-- 2. Резерв по названию рецепта -> подходящий надетый слот экипировки
	if ItemLocation and ItemLocation.CreateFromEquipmentSlot then
		local name = self.GetRecipeDisplay and self:GetRecipeDisplay(recipeID) or ""
		local lower = tostring(name or ""):lower()
		for _, rule in ipairs(ENCHANT_SLOT_PATTERNS) do
			if lower:find(rule.pattern, 1, true) then
				for _, slotID in ipairs(rule.slots) do
					local loc = ItemLocation:CreateFromEquipmentSlot(slotID)
					if IsValidTargetLoc(loc) then
						local matched = true
						if rule.invTypes then
							local itemID = C_Item and C_Item.GetItemID and C_Item.GetItemID(loc)
							local invType = itemID and (
								(C_Item.GetItemInfoInstant and select(4, C_Item.GetItemInfoInstant(itemID)))
								or (C_Item.GetItemInfo and select(9, C_Item.GetItemInfo(itemID)))
							)
							matched = (invType ~= nil and rule.invTypes[invType] == true)
						end
						if matched then
							return loc, BuildTargetMeta(loc, false)
						end
					end
				end
				break
			end
		end
	end

	return nil, nil
end

local popupBindOwner = CreateFrame("Frame", "TradeFlowPopupBindOwner", UIParent)
local popupConfirmProxy = CreateFrame("Button", "TradeFlowPopupConfirmBtn", UIParent, "SecureActionButtonTemplate")
popupConfirmProxy:SetAttribute("type", "click")
popupConfirmProxy:RegisterForClicks("AnyDown", "AnyUp")
local hookedPopups = {}

local function ClearReplaceEnchantSpace()
	if not (InCombatLockdown and InCombatLockdown()) then
		if ClearOverrideBindings then
			ClearOverrideBindings(popupBindOwner)
		end
		if popupConfirmProxy and popupConfirmProxy.SetAttribute then
			popupConfirmProxy:SetAttribute("clickbutton", nil)
		end
	end
end
ns.ClearReplaceEnchantSpace = ClearReplaceEnchantSpace

local function FindReplaceEnchantPopup()
	local dlg = StaticPopup_FindVisible and StaticPopup_FindVisible("REPLACE_ENCHANT")
	if not dlg then
		local maxN = STATICPOPUP_NUMDIALOGS or 4
		for i = 1, maxN do
			local f = _G["StaticPopup" .. i]
			if f and f:IsShown() and f.which == "REPLACE_ENCHANT" then
				dlg = f
				break
			end
		end
	end
	if not dlg then
		return nil, nil
	end
	local btn = (dlg.GetButton and dlg:GetButton(1)) or dlg.button1
	if not btn and dlg.GetName and dlg:GetName() then
		btn = _G[dlg:GetName() .. "Button1"]
	end
	return dlg, btn
end

local function IsDescendantOf(widget, ancestor)
	if not (widget and ancestor) then
		return false
	end
	if RegionUtil and RegionUtil.IsDescendantOf then
		return RegionUtil.IsDescendantOf(widget, ancestor)
	end
	local p = widget
	while p do
		if p == ancestor then
			return true
		end
		p = p.GetParent and p:GetParent() or nil
	end
	return false
end

local function BindReplaceEnchantSpace()
	if InCombatLockdown and InCombatLockdown() then
		return
	end
	local now = GetTime and GetTime() or 0
	if not (ns.mainFrame and ns.mainFrame:IsShown() and ns._lastEnchantCraftAt and (now - ns._lastEnchantCraftAt) <= 15) then
		ClearReplaceEnchantSpace()
		return
	end
	local dlg, btn = FindReplaceEnchantPopup()
	if not (dlg and btn and btn.IsEnabled and btn:IsEnabled()) then
		ClearReplaceEnchantSpace()
		return
	end
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	if focus then
		if IsDescendantOf(focus, ns.mainFrame) then
			focus:ClearFocus()
		else
			ClearReplaceEnchantSpace()
			return
		end
	end
	if not hookedPopups[dlg] then
		hookedPopups[dlg] = true
		dlg:HookScript("OnHide", ClearReplaceEnchantSpace)
	end
	if ClearOverrideBindings then
		ClearOverrideBindings(popupBindOwner)
	end
	if SetOverrideBindingClick then
		local btnName = btn.GetName and btn:GetName()
		if btnName and btnName ~= "" then
			SetOverrideBindingClick(popupBindOwner, true, "SPACE", btnName)
		else
			popupConfirmProxy:SetAttribute("clickbutton", btn)
			SetOverrideBindingClick(popupBindOwner, true, "SPACE", "TradeFlowPopupConfirmBtn")
		end
		ns._lastEnchantCraftAt = now
	end
end

if hooksecurefunc and StaticPopup_Show then
	hooksecurefunc("StaticPopup_Show", function(which)
		if which == "REPLACE_ENCHANT" then
			BindReplaceEnchantSpace()
		end
	end)
end

function ns:ExecuteCraftRecipe(recipeID, count)
	if not recipeID or (InCombatLockdown and InCombatLockdown()) then
		return false
	end
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	if IsDescendantOf(focus, self.mainFrame) then
		focus:ClearFocus()
	end
	if self.LogTrace then
		self:LogTrace("CraftRecipe", tostring(recipeID) .. "x" .. tostring(count or 1))
	end
	count = math.max(1, count or 1)
	local rec = self:GetRecipeRecord(recipeID)
	local skillLine = (rec and rec.skillLine) or self.currentSkillLine

	self.bypassIntercept = false
	self:SuppressBlizzardFrame()

	if not self:IsClientRecipeReady(recipeID) then
		if self.Print and skillLine then
			self:Print(string.format(L["CRAFT_OPEN_PROF_MSG"], self:GetProfessionName(skillLine)))
		end
		return false
	end
	self:SuppressBlizzardFrame()

	local isEnchant = self.IsEnchantRecipe and self:IsEnchantRecipe(recipeID)
	self._lastEnchantCraftAt = isEnchant and (GetTime and GetTime() or 0) or nil
	if C_TradeSkillUI and C_TradeSkillUI.CraftEnchant and isEnchant then
		local targetLoc = self:ResolveEnchantTarget(recipeID)
		if targetLoc then
			local ok
			if ns.SafeCall then
				ok = ns:SafeCall("CraftEnchant", C_TradeSkillUI.CraftEnchant, recipeID, count, {}, targetLoc)
			else
				ok = pcall(C_TradeSkillUI.CraftEnchant, recipeID, count, {}, targetLoc)
			end
			if ok then
				return true
			end
		end
	end

	if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
		local ok
		if ns.SafeCall then
			ok = ns:SafeCall("CraftRecipe", C_TradeSkillUI.CraftRecipe, recipeID, count)
		else
			ok = pcall(C_TradeSkillUI.CraftRecipe, recipeID, count)
		end
		if not ok then
			self._lastEnchantCraftAt = nil
		end
		return ok and true or false
	end
	self._lastEnchantCraftAt = nil
	return false
end

function ns:SwitchToProfession(skillLine, recipeID)
	if not skillLine then
		return
	end
	self.currentSkillLine = skillLine
	if recipeID then
		self.selectedRecipeBySkill[skillLine] = recipeID
		self.pinnedRecipeBySkill = self.pinnedRecipeBySkill or {}
		self.pinnedRecipeBySkill[skillLine] = recipeID
		self.scrollToSelectedRecipe = true
	end
	self.bypassIntercept = false
	self:SuppressBlizzardFrame()
	if self.RefreshMainWindow then
		self:RefreshMainWindow()
	end
	self.scrollToSelectedRecipe = false
end

function ns:EnsureBlizzardReturnButton()
	if not ProfessionsFrame then
		return
	end
	if not self.blizzReturnBtn then
		local btn = CreateFrame("Button", "TradeFlowReturnButton", ProfessionsFrame, "UIPanelButtonTemplate")
		btn:SetSize(92, 20)
		btn:SetText(L["ADDON_TITLE"] or "TradeFlow")
		local closeBtn = ProfessionsFrame.CloseButton or _G.ProfessionsFrameCloseButton
		if closeBtn then
			btn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
		else
			btn:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", -30, -2)
		end
		btn:SetFrameStrata(ProfessionsFrame:GetFrameStrata())
		btn:SetFrameLevel(((closeBtn and closeBtn:GetFrameLevel()) or ProfessionsFrame:GetFrameLevel()) + 5)
		btn:SetScript("OnClick", function()
			ns.bypassIntercept = false
			-- Окно Blizzard прячется, но не закрывается: на общей вкладке или с рыбалкой
			-- «Окно Blizzard» вернёт его как было (открыть заново аддону игра не даёт).
			-- preferTradeFlow не даёт событиям вернуть окно Blizzard на экран.
			ns.preferTradeFlow = true
			ns:ScanActiveTradeSkill()
			ns:SuppressBlizzardFrame(true)
			local sl = ns:GetActiveClientSkillLine() or ns.currentSkillLine
			if sl then
				ns.currentSkillLine = sl
			end
			if ns.ShowMainWindow then
				ns:ShowMainWindow()
			end
		end)
		self.blizzReturnBtn = btn
	end
	self.blizzReturnBtn:Show()
end

function ns:OpenBlizzardProfessions()
	-- WoW Forever: C_TradeSkillUI.OpenTradeSkill защищена, вызов из аддона блокируется
	-- (ADDON_ACTION_BLOCKED). Окно Blizzard можно только показать для уже открытой
	-- профессии: при открытой профессии ProfessionsFrame:OnShow ничего не произносит заново.
	local shown = ProfessionsFrame and ProfessionsFrame:IsShown()
	if not shown and not (ProfessionsFrame and GetOpenTradeSkillID() and not InCombatLockdown()) then
		self:Print(L["BLIZZARD_UI_NEED_PROF"])
		return
	end
	self.preferTradeFlow = false
	self.bypassIntercept = true
	if self.HideMainWindow then
		self:HideMainWindow()
	end
	self:RestoreBlizzardFrame()
	if not shown then
		ShowUIPanel(ProfessionsFrame)
	end
	self:EnsureBlizzardReturnButton()
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
	"TRADE_SKILL_FAVORITES_CHANGED",
	"TRADE_SKILL_UPDATE",
	"TRADE_SKILL_CLOSE",
	"SKILL_LINES_CHANGED",
	"CHAT_MSG_SKILL",
	"NEW_RECIPE_LEARNED",
	"GET_ITEM_INFO_RECEIVED",
	"ITEM_DATA_LOAD_RESULT",
	"SPELL_DATA_LOAD_RESULT",
	"REPLACE_ENCHANT",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"PLAYER_EQUIPMENT_CHANGED",
}) do
	pcall(eventFrame.RegisterEvent, eventFrame, ev)
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		TradeFlowDB = TradeFlowDB or {}
		ns.db = TradeFlowDB
		if ns.db.lang ~= "ru" and ns.db.lang ~= "en" then
			ns.db.lang = ns.DefaultLanguage()
		end
		ns.lang = ns.db.lang
		ns.db.options = ns.db.options or {
			autoSubcrafts = true,
			includeTrainerInRoute = true,
			includeVendorRecipesInRoute = true,
			includeOtherRecipesInRoute = false,
			deductVendorInRoute = true,
			includeDisenchant = true,
			tooltipExtraInfo = false,
			checkAuctionStock = false,
			profitLogMode = "craft",
			profitIncludeTrainer = false,
			profitIncludeVendor = false,
			profitIncludeOther = false,
			routePriority = "speed",
			filterCraftable = false,
			filterSkillUp = false,
			showUnlearned = false,
			sortMode = "difficulty",
			snipeMaxSpend = 100000,
			snipeMinReserve = 0,
			snipeMaxQty = 200,
			uiScale = 1.0,
			leftCollapsed = false,
			windowMinimized = false,
		}
		ns.db.vendorPrices = ns.db.vendorPrices or {}
		ns.db.trainerFees = ns.db.trainerFees or {}
		ns.db.realms = ns.db.realms or {}

		local rKey = ns:RealmKey()
		ns.db.realms[rKey] = ns.db.realms[rKey] or { chars = {} }
		ns.realmDB = ns.db.realms[rKey]
		ns.realmDB.ahStock = ns.realmDB.ahStock or {}

		local cKey = ns:CharKey()
		ns.realmDB.chars[cKey] = ns.realmDB.chars[cKey] or {
			bags = {},
			bank = {},
			learned = {},
			favorites = {},
			professions = {},
			queue = {},
			skippedRecipes = {},
			targets = {},
		}
		ns.charDB = ns.realmDB.chars[cKey]
		ns.charDB.favorites = ns.charDB.favorites or {}
		if ns.charDB.professions then
			for sl, p in pairs(ns.charDB.professions) do
				ns.playerProfessions[sl] = p
			end
		end
		if ns.InitInventoryIndex then
			ns:InitInventoryIndex()
		end
		if ns.InitModules then
			ns:InitModules()
		end
	elseif event == "ADDON_LOADED" and arg1 == "Blizzard_Professions" then
		-- Окно профессий Blizzard грузится по требованию: хуки ставим сразу, иначе при первом
		-- открытии по K (на общую вкладку) нет кнопки TradeFlow
		if ProfessionsFrame then
			ns:HookBlizzardFrame()
		end
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		if ProfessionsFrame then
			ns:HookBlizzardFrame()
		end
		ns:ScanPlayerProfessions()
		if ns.ScanBagsNow then
			ns:ScanBagsNow()
		end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
		ns:ScanPlayerProfessions()
		local ok = ns:ScanActiveTradeSkill()
		if ok then
			ns.isSwitchingProfession = false
			ns.blizzardOwnsTradeSkill = false
		elseif event == "TRADE_SKILL_SHOW" and not ns.isSwitchingProfession and not ns.bypassIntercept then
			-- Профессия, которой нет в TradeFlow (рыбалка): её показывает окно Blizzard.
			-- Окно TradeFlow закрываем без CloseTradeSkill, иначе закроется и рыбалка.
			ns.blizzardOwnsTradeSkill = true
			ns.preferTradeFlow = false
			ns:RestoreBlizzardFrame()
			if ns.mainFrame and ns.mainFrame:IsShown() and ns.HideMainWindow then
				ns.isClosingFromBlizz = true
				ns:HideMainWindow()
				ns.isClosingFromBlizz = false
			end
		end
		if ok and not ns.bypassIntercept then
			ns:SuppressBlizzardFrame(true)
			if C_Timer and C_Timer.After then
				C_Timer.After(0, function()
					if not ns.bypassIntercept and ProfessionsFrame and ProfessionsFrame:IsShown() then
						ns:SuppressBlizzardFrame()
					end
				end)
			end
			if ns.ShowMainWindow then
				ns:ShowMainWindow()
			end
		end
	elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" or event == "TRADE_SKILL_UPDATE" then
		ns:ScanPlayerProfessions()
		if ns.mainFrame and ns.mainFrame:IsShown() then
			if ns.RefreshRankBarOnly then
				ns:RefreshRankBarOnly()
			end
			ScheduleTradeSkillRefresh()
		end
	elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DETAILS_UPDATE" or event == "TRADE_SKILL_FAVORITES_CHANGED" then
		if event == "TRADE_SKILL_FAVORITES_CHANGED" and ns.SyncFavoritesFromBlizzard then
			ns:SyncFavoritesFromBlizzard()
		end
		if not ns.bypassIntercept then
			ns:SuppressBlizzardFrame()
		end
		if ns.mainFrame and ns.mainFrame:IsShown() then
			ScheduleTradeSkillRefresh()
		end
	elseif event == "NEW_RECIPE_LEARNED" then
		local learnedID = tonumber(arg1)
		if learnedID and learnedID > 0 then
			if ns.charDB and ns.charDB.learned then
				ns.charDB.learned[learnedID] = true
			end
			if ns.liveRecipes and ns.liveRecipes[learnedID] then
				ns.liveRecipes[learnedID].learned = true
			end
		end
		if ns.InvalidateCraftCounts then
			ns:InvalidateCraftCounts()
		end
		if ns.InvalidatePrices then
			ns:InvalidatePrices(not (ns.mainFrame and ns.mainFrame:IsShown()))
		end
		if ns.mainFrame and ns.mainFrame:IsShown() then
			ScheduleTradeSkillRefresh()
		end
	elseif event == "TRADE_SKILL_CLOSE" then
		ns.blizzardOwnsTradeSkill = false
		ns.preferTradeFlow = false
		-- Если окно Blizzard закрыто (Esc или повторное нажатие бинда профессии K), закрываем и TradeFlow
		if ns.bypassIntercept then
			ns.bypassIntercept = false
		elseif not ns.isSwitchingProfession and not ns.isHidingMain and ns.mainFrame and ns.mainFrame:IsShown() and ns.HideMainWindow then
			ns.isClosingFromBlizz = true
			ns:HideMainWindow()
			ns.isClosingFromBlizz = false
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if arg1 and arg2 == false then
			failedItemLoads[arg1] = true
			return
		end
		ScheduleItemDataRefresh()
	elseif event == "ITEM_DATA_LOAD_RESULT" then
		if arg1 and arg2 == false then
			failedItemLoads[arg1] = true
			return
		end
		ScheduleItemDataRefresh()
	elseif event == "SPELL_DATA_LOAD_RESULT" then
		if arg1 and requestedSpellLoads[arg1] and arg2 ~= false then
			if ns.mainFrame and ns.mainFrame:IsShown() then
				ScheduleItemDataRefresh()
			elseif ns.InvalidateProfitCache then
				ns.InvalidateProfitCache()
			end
		end
	elseif event == "REPLACE_ENCHANT" then
		BindReplaceEnchantSpace()
		if C_Timer and C_Timer.After then
			C_Timer.After(0, BindReplaceEnchantSpace)
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		ClearReplaceEnchantSpace()
		if ns.DetachSecureProfProxy then
			ns:DetachSecureProfProxy()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.OnCombatEnded then
			ns:OnCombatEnded()
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		if ns.detailsView and ns.detailsView:IsVisible() and ns.detailsView.currentRecipeID
			and ns.IsEnchantRecipe and ns:IsEnchantRecipe(ns.detailsView.currentRecipeID)
			and ns.RefreshDetailsView
		then
			ns:RefreshDetailsView()
		end
	end
end)

SLASH_TRADEFLOW1 = "/tradeflow"
SLASH_TRADEFLOW2 = "/tf"
SlashCmdList.TRADEFLOW = function(msg)
	local rawMsg = strtrim(msg or "")
	local low = rawMsg:lower()
	if low == "lang" then
		ns:ToggleLanguage()
	elseif low == "blizz" or low == "blizzard" then
		ns:OpenBlizzardProfessions()
	elseif low == "log" or low == "errors" or low == "debug" then
		if ns.ShowDebugLogWindow then
			ns:ShowDebugLogWindow()
		end
	elseif low == "snipe" or low:sub(1, 6) == "snipe " then
		local rest = strtrim(rawMsg:sub(7))
		if rest == "" then
			if ns.ShowMainWindow then
				ns:ShowMainWindow()
			end
			if ns.mainFrame and ns.mainFrame.SelectTopTab then
				ns.mainFrame.SelectTopTab("profit")
			end
			local mod = ns.modules and ns.modules.byId and ns.modules.byId["profit"]
			if mod and mod.view and mod.view.SelectSubMode then
				mod.view.SelectSubMode("sniper")
			end
			if ns.Print then
				ns:Print(L["SNIPE_CMD_USAGE"])
			end
		elseif ns.AddManualSnipeTarget then
			local itemPart, pricePart = rest:match("^(|c%x+|Hitem:%d+.-|h%[.-%]|h|r)%s*(.*)$")
			if not itemPart then
				itemPart, pricePart = rest:match("^(|Hitem:%d+.-|h%[.-%]|h)%s*(.*)$")
			end
			if not itemPart then
				itemPart, pricePart = rest:match("^(%d+)%s*(.*)$")
			end
			if not itemPart then
				local words = {}
				for w in rest:gmatch("%S+") do
					words[#words + 1] = w
				end
				local splitIdx = #words
				while splitIdx >= 2 and ns.ParseMoneyInput and ns.ParseMoneyInput(words[splitIdx]) do
					splitIdx = splitIdx - 1
				end
				if splitIdx < #words then
					local candidatePrice = table.concat(words, " ", splitIdx + 1)
					if ns.ParseMoneyInput and ns.ParseMoneyInput(candidatePrice) then
						itemPart = table.concat(words, " ", 1, splitIdx)
						pricePart = candidatePrice
					end
				end
			end
			ns:AddManualSnipeTarget(itemPart or rest, pricePart)
		end
	else
		if ns.ToggleMainWindow then
			ns:ToggleMainWindow()
		end
	end
end

