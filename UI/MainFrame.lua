local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Главное окно TradeFlow (полная замена окна профессий в стиле Skillet + SkillUp)
-------------------------------------------------------------------------------
local WIN_W, WIN_H = 980, 640
local LEFT_W = 445
local RECIPE_ROW_H = 24
local RECIPE_VISIBLE_ROWS = 20

local SORT_MODES = {
	{ key = "difficulty",   labelKey = "SORT_DIFFICULTY" },
	{ key = "chance",       labelKey = "SORT_CHANCE" },
	{ key = "cost_skillup", labelKey = "SORT_COST_SKILLUP" },
	{ key = "profit",       labelKey = "SORT_PROFIT" },
	{ key = "name",         labelKey = "SORT_NAME" },
}

local function StylePanel(frame, bgR, bgG, bgB, bgA)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(bgR or 0.08, bgG or 0.07, bgB or 0.06, bgA or 0.94)
	frame:SetBackdropBorderColor(0.55, 0.44, 0.22, 0.95)
end

-- Форматирование счётчика крафтов рецепта: [в сумках / +крафт / +вендор / Б:банк]
local function FormatCraftCounts(direct, withCraft, withVendor, withBank)
	local parts = {}
	if direct > 0 then
		parts[#parts + 1] = "|cff40ff40" .. direct .. "|r"
	end
	if withCraft > direct then
		parts[#parts + 1] = "|cff66ccff" .. withCraft .. "|r"
	end
	if withVendor > math.max(direct, withCraft) then
		parts[#parts + 1] = "|cffffd100" .. withVendor .. "|r"
	end
	if (withBank or 0) > math.max(direct, withCraft, withVendor) then
		parts[#parts + 1] = "|cffc080ff" .. L["BANK_SHORT"] .. withBank .. "|r"
	end
	if #parts == 0 then
		return ""
	end
	return " |cff888888[" .. table.concat(parts, "/") .. "]|r"
end

-- Сбор и сортировка списка рецептов выбранной профессии
function ns:BuildFilteredRecipeList()
	local sl = self.currentSkillLine
	if not sl then
		for k in pairs(self.playerProfessions) do
			sl = k
			self.currentSkillLine = k
			break
		end
		sl = sl or 171
		self.currentSkillLine = sl
	end

	local prof = self.playerProfessions[sl]
	local curSkill = (prof and prof.rank) or 1
	local opts = (self.db and self.db.options) or {}
	local search = strtrim((self.searchQuery or "")):lower()
	local onlyCraftable = opts.filterCraftable == true
	local onlySkillUp = opts.filterSkillUp == true
	local showUnlearned = opts.showUnlearned == true
	local deductVendor = opts.deductVendorInRoute ~= false
	local sortMode = opts.sortMode or "difficulty"

	local rawIDs = (self.RecipesBySkill and self.RecipesBySkill[sl]) or {}
	local entries = {}

	for _, recipeID in ipairs(rawIDs) do
		local learned = self:IsRecipeLearned(recipeID)
		local metrics = self:GetRecipeSkillMetrics(recipeID, curSkill, deductVendor)
		-- При включённой галочке показываем неизученные рецепты (в первую очередь доступные сейчас или в ближайшие +40 очков навыка)
		local unlearnedRelevant = showUnlearned and not learned and ((metrics.reqSkill or 1) <= curSkill + 40)
		if learned or unlearnedRelevant then
			local direct, withCraft, withVendor, _, withBank = self:GetRecipeCraftCounts(recipeID)
			local canCraft = (direct > 0 or withCraft > 0 or withVendor > 0 or (withBank or 0) > 0)
			local givesSkill = (metrics.chance and metrics.chance > 0)

			local passFilter = true
			if onlyCraftable and not canCraft then
				passFilter = false
			end
			if onlySkillUp and not givesSkill then
				passFilter = false
			end

			if passFilter and search ~= "" then
				local rName = self:GetRecipeDisplay(recipeID):lower()
				local matched = rName:find(search, 1, true) ~= nil
				if not matched then
					local rec = self:GetRecipeRecord(recipeID)
					for _, rg in ipairs((rec and rec.reagents) or {}) do
						local iName = self:GetItemDisplay(rg.itemID):lower()
						if iName:find(search, 1, true) then
							matched = true
							break
						end
					end
				end
				passFilter = matched
			end

			if passFilter then
				local name, icon, outItemID = self:GetRecipeDisplay(recipeID)
				local live = self.liveRecipes and self.liveRecipes[recipeID]
				entries[#entries + 1] = {
					recipeID = recipeID,
					name = name,
					icon = icon,
					outItemID = outItemID,
					categoryName = (live and live.categoryName) or L["CAT_OTHER"],
					learned = learned,
					direct = direct,
					withCraft = withCraft,
					withVendor = withVendor,
					withBank = withBank,
					metrics = metrics,
					profit = metrics.profit,
				}
			end
		end
	end

	table.sort(entries, function(a, b)
		if sortMode == "name" then
			return a.name < b.name
		elseif sortMode == "chance" then
			local ca, cb = a.metrics.chance or 0, b.metrics.chance or 0
			if ca ~= cb then return ca > cb end
		elseif sortMode == "cost_skillup" then
			local ca = a.metrics.costPerSkillUp or math.huge
			local cb = b.metrics.costPerSkillUp or math.huge
			if ca ~= cb then return ca < cb end
		elseif sortMode == "profit" then
			local pa = a.profit or -math.huge
			local pb = b.profit or -math.huge
			if pa ~= pb then return pa > pb end
		else
			-- Сортируем по реальному цвету диапазона (bandColor), чтобы неизученные рецепты
			-- актуального уровня стояли рядом с изученными оранжевыми/жёлтыми, а не в самом конце после серых
			local da = (ns.DIFFICULTY_COLORS[a.metrics.bandColor] and ns.DIFFICULTY_COLORS[a.metrics.bandColor].order) or 0
			local db = (ns.DIFFICULTY_COLORS[b.metrics.bandColor] and ns.DIFFICULTY_COLORS[b.metrics.bandColor].order) or 0
			if da ~= db then return da > db end
			if a.learned ~= b.learned then return a.learned end
			local ra, rb = a.metrics.reqSkill or 1, b.metrics.reqSkill or 1
			if ra ~= rb then return ra > rb end
		end
		return a.recipeID < b.recipeID
	end)

	if opts.groupByCategory == true and #entries > 0 then
		self.collapsedCategories = self.collapsedCategories or {}
		local byCat, catOrder = {}, {}
		for _, e in ipairs(entries) do
			local c = e.categoryName or L["CAT_OTHER"]
			if not byCat[c] then
				byCat[c] = {}
				catOrder[#catOrder + 1] = c
			end
			byCat[c][#byCat[c] + 1] = e
		end
		table.sort(catOrder, function(a, b)
			if a == L["CAT_OTHER"] then return false end
			if b == L["CAT_OTHER"] then return true end
			return a < b
		end)
		local grouped = {}
		for _, c in ipairs(catOrder) do
			local list = byCat[c]
			local collapsed = self.collapsedCategories[c] == true
			grouped[#grouped + 1] = {
				isHeader = true,
				categoryName = c,
				count = #list,
				collapsed = collapsed,
			}
			if not collapsed then
				for _, e in ipairs(list) do
					grouped[#grouped + 1] = e
				end
			end
		end
		entries = grouped
	end

	self.filteredRecipes = entries
	if #entries > 0 then
		local sel = self.selectedRecipeBySkill[sl]
		local found = false
		local firstRecipeID = nil
		for _, e in ipairs(entries) do
			if not e.isHeader then
				firstRecipeID = firstRecipeID or e.recipeID
				if e.recipeID == sel then
					found = true
					break
				end
			end
		end
		if not found and firstRecipeID and not self.preserveSelectedRecipe then
			self.selectedRecipeBySkill[sl] = firstRecipeID
		end
	end
	return entries
end

function ns:SelectRecipeID(recipeID)
	if not recipeID then
		return
	end
	local rec = self:GetRecipeRecord(recipeID)
	if rec and rec.skillLine and rec.skillLine ~= self.currentSkillLine then
		self.currentSkillLine = rec.skillLine
	end
	if self.currentSkillLine then
		self.selectedRecipeBySkill[self.currentSkillLine] = recipeID
	end
	if self.mainFrame and self.mainFrame:IsShown() then
		if self.mainFrame.SelectTopTab and self.mainFrame.topTab ~= "details" then
			self.mainFrame.SelectTopTab("details")
		end
		self.preserveSelectedRecipe = true
		self.scrollToSelectedRecipe = true
		self:RefreshMainWindow()
		self.scrollToSelectedRecipe = false
		self.preserveSelectedRecipe = false
	end
end

function ns:CreateMainFrame()
	if self.mainFrame then
		return self.mainFrame
	end

	local f = CreateFrame("Frame", "TradeFlowMainFrame", UIParent, "BackdropTemplate")
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({
		bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 16, edgeSize = 24,
		insets = { left = 6, right = 6, top = 6, bottom = 6 },
	})
	f:SetBackdropColor(0.05, 0.045, 0.04, 0.98)
	f:SetScript("OnHide", function()
		if not ns.bypassIntercept and not ns.isRebuildingFrame and not ns.isClosingFromBlizz then
			ns.isHidingMain = true
			if C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill then
				pcall(C_TradeSkillUI.CloseTradeSkill)
			end
			if ProfessionsFrame and ProfessionsFrame:IsShown() and not InCombatLockdown() then
				pcall(HideUIPanel, ProfessionsFrame)
			end
			ns.isHidingMain = false
		end
	end)
	if not self.specialFrameRegistered then
		self.specialFrameRegistered = true
		tinsert(UISpecialFrames, "TradeFlowMainFrame")
	end
	f:Hide()

	---------------------------------------------------------------------------
	-- Шапка окна
	---------------------------------------------------------------------------
	local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
	header:SetPoint("TOPLEFT", 12, -10)
	header:SetPoint("TOPRIGHT", -12, -10)
	header:SetHeight(38)
	StylePanel(header, 0.13, 0.10, 0.06, 0.96)

	local icon = header:CreateTexture(nil, "ARTWORK")
	icon:SetSize(26, 26)
	icon:SetPoint("LEFT", 8, 0)
	icon:SetTexture(self.ICON)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.headerIcon = icon

	local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetText("|cffffd100" .. L["ADDON_TITLE"] .. "|r")
	f.headerTitle = title

	-- Кнопки переключения профессий персонажа
	f.profButtons = {}
	for i = 1, 6 do
		local pb = CreateFrame("Button", nil, header, "BackdropTemplate")
		pb:SetSize(28, 28)
		pb:SetPoint("LEFT", title, "RIGHT", 14 + (i - 1) * 32, 0)
		StylePanel(pb, 0.10, 0.10, 0.10, 0.95)
		pb.tex = pb:CreateTexture(nil, "ARTWORK")
		pb.tex:SetPoint("TOPLEFT", 3, -3)
		pb.tex:SetPoint("BOTTOMRIGHT", -3, 3)
		pb.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		pb:SetScript("OnClick", function(self)
			if self.skillLine then
				ns:SwitchToProfession(self.skillLine)
			end
		end)
		pb:SetScript("OnEnter", function(self)
			if self.skillLine then
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				local p = ns.playerProfessions[self.skillLine]
				GameTooltip:AddLine(ns:GetProfessionName(self.skillLine), 1, 0.82, 0)
				if p then
					GameTooltip:AddLine(string.format("%d / %d", p.rank or 1, p.maxRank or 75), 1, 1, 1)
				end
				GameTooltip:Show()
			end
		end)
		pb:SetScript("OnLeave", GameTooltip_Hide)
		f.profButtons[i] = pb
	end

	-- Полоса прогресса навыка текущей профессии
	local rankBar = CreateFrame("StatusBar", nil, header, "BackdropTemplate")
	rankBar:SetSize(195, 18)
	rankBar:SetPoint("CENTER", header, "CENTER", -15, 0)
	rankBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	rankBar:SetStatusBarColor(0.20, 0.55, 0.90, 0.9)
	rankBar.bg = rankBar:CreateTexture(nil, "BACKGROUND")
	rankBar.bg:SetAllPoints()
	rankBar.bg:SetColorTexture(0.04, 0.04, 0.04, 0.85)
	rankBar.text = rankBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rankBar.text:SetPoint("CENTER", 0, 0)
	f.rankBar = rankBar

	-- Глобальная галка учёта продажи торговцу (для списка рецептов, деталей и калькулятора)
	local cbVendor = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
	cbVendor:SetSize(20, 20)
	cbVendor:SetPoint("LEFT", rankBar, "RIGHT", 12, 0)
	cbVendor.text = cbVendor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cbVendor.text:SetPoint("LEFT", cbVendor, "RIGHT", 2, 0)
	cbVendor.text:SetText(L["PLANNER_DEDUCT_VENDOR"])
	cbVendor:SetHitRectInsets(0, -115, 0, 0)
	cbVendor:SetScript("OnClick", function(self)
		ns.db.options.deductVendorInRoute = self:GetChecked() and true or false
		if ns.InvalidatePrices then
			ns:InvalidatePrices()
		else
			ns:RefreshMainWindow()
		end
	end)
	f.cbVendor = cbVendor

	local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
	closeBtn:SetPoint("RIGHT", -2, 0)
	closeBtn:SetScript("OnClick", function()
		ns:HideMainWindow()
	end)

	local langBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	langBtn:SetSize(38, 22)
	langBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
	langBtn:SetText(self.lang == "ru" and "RU" or "EN")
	langBtn:SetScript("OnClick", function()
		ns:ToggleLanguage()
	end)
	langBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["LANG_TOOLTIP"], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	langBtn:SetScript("OnLeave", GameTooltip_Hide)
	f.langBtn = langBtn

	local settingsBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	settingsBtn:SetSize(82, 22)
	settingsBtn:SetPoint("RIGHT", langBtn, "LEFT", -4, 0)
	settingsBtn:SetText(L["SETTINGS_BTN"])
	settingsBtn:SetScript("OnClick", function()
		ns:ToggleSettingsFrame()
	end)
	f.settingsBtn = settingsBtn

	local blizzBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	blizzBtn:SetSize(104, 22)
	blizzBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -4, 0)
	blizzBtn:SetText(L["BLIZZARD_UI"])
	blizzBtn:SetScript("OnClick", function()
		ns:OpenBlizzardProfessions()
	end)
	blizzBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["BLIZZARD_UI_DESC"], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	blizzBtn:SetScript("OnLeave", GameTooltip_Hide)

	---------------------------------------------------------------------------
	-- Левая панель: Поиск, Фильтры, Сортировка и Список рецептов
	---------------------------------------------------------------------------
	local leftPane = CreateFrame("Frame", nil, f, "BackdropTemplate")
	leftPane:SetPoint("TOPLEFT", 12, -54)
	leftPane:SetPoint("BOTTOMLEFT", 12, 12)
	leftPane:SetWidth(LEFT_W)
	StylePanel(leftPane, 0.07, 0.065, 0.055, 0.95)
	f.leftPane = leftPane

	local searchBox = CreateFrame("EditBox", nil, leftPane, "InputBoxTemplate")
	searchBox:SetSize(172, 20)
	searchBox:SetPoint("TOPLEFT", 14, -10)
	searchBox:SetAutoFocus(false)
	searchBox:SetText(self.searchQuery or "")
	searchBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			ns.searchQuery = self:GetText()
			f.recipeOffset = 0
			ns:RefreshRecipeList()
		end
	end)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	searchBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	f.searchBox = searchBox

	local clearSearch = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
	clearSearch:SetSize(22, 20)
	clearSearch:SetPoint("LEFT", searchBox, "RIGHT", 4, 0)
	clearSearch:SetText("X")
	clearSearch:SetScript("OnClick", function()
		ns.searchQuery = ""
		searchBox:SetText("")
		searchBox:ClearFocus()
		f.recipeOffset = 0
		ns:RefreshRecipeList()
	end)

	local sortBtn = CreateFrame("Button", nil, leftPane, "UIPanelButtonTemplate")
	sortBtn:SetSize(145, 22)
	sortBtn:SetPoint("TOPRIGHT", -8, -9)
	local function UpdateSortButtonLabel()
		local cur = (ns.db and ns.db.options and ns.db.options.sortMode) or "difficulty"
		for _, m in ipairs(SORT_MODES) do
			if m.key == cur then
				sortBtn:SetText(L[m.labelKey] .. " v")
				return
			end
		end
		sortBtn:SetText(L["SORT_DIFFICULTY"] .. " v")
	end

	local sortMenu = CreateFrame("Frame", nil, leftPane, "BackdropTemplate")
	sortMenu:SetSize(156, #SORT_MODES * 22 + 8)
	sortMenu:SetPoint("TOPLEFT", sortBtn, "BOTTOMLEFT", 0, -2)
	sortMenu:SetFrameStrata("DIALOG")
	sortMenu:SetFrameLevel(leftPane:GetFrameLevel() + 20)
	StylePanel(sortMenu, 0.08, 0.07, 0.06, 0.98)
	sortMenu:Hide()
	f.sortMenu = sortMenu

	local sortMenuButtons = {}
	for i, m in ipairs(SORT_MODES) do
		local item = CreateFrame("Button", nil, sortMenu)
		item:SetHeight(20)
		item:SetPoint("TOPLEFT", 5, -4 - (i - 1) * 22)
		item:SetPoint("TOPRIGHT", -5, -4 - (i - 1) * 22)
		item.hl = item:CreateTexture(nil, "HIGHLIGHT")
		item.hl:SetAllPoints()
		item.hl:SetColorTexture(1, 0.82, 0.2, 0.16)
		item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		item.text:SetPoint("LEFT", 6, 0)
		item.text:SetPoint("RIGHT", -6, 0)
		item.text:SetJustifyH("LEFT")
		item.modeKey = m.key
		item:SetScript("OnClick", function(self)
			ns.db.options.sortMode = self.modeKey
			UpdateSortButtonLabel()
			sortMenu:Hide()
			f.recipeOffset = 0
			ns:RefreshRecipeList()
		end)
		sortMenuButtons[i] = item
	end

	local function RefreshSortMenuHighlight()
		local cur = (ns.db and ns.db.options and ns.db.options.sortMode) or "difficulty"
		for idx, item in ipairs(sortMenuButtons) do
			local label = L[SORT_MODES[idx].labelKey]
			if item.modeKey == cur then
				item.text:SetText("|cffffd100* " .. label .. "|r")
			else
				item.text:SetText("  " .. label)
			end
		end
	end

	sortBtn:SetScript("OnClick", function()
		if sortMenu:IsShown() then
			sortMenu:Hide()
		else
			RefreshSortMenuHighlight()
			sortMenu:Show()
		end
	end)
	f:HookScript("OnHide", function()
		sortMenu:Hide()
	end)
	f.sortBtn = sortBtn
	UpdateSortButtonLabel()

	local catBtn = ns.CreateTabButton(leftPane, 74, 22, L["GROUP_BY_CATEGORY"])
	catBtn:SetPoint("RIGHT", sortBtn, "LEFT", -4, 0)
	catBtn:SetScript("OnClick", function()
		ns.db.options.groupByCategory = not (ns.db.options.groupByCategory == true)
		ns.SetTabButtonActive(catBtn, ns.db.options.groupByCategory == true)
		f.recipeOffset = 0
		ns:RefreshRecipeList()
	end)
	f.catBtn = catBtn

	local function CreateFilterCheck(label, optKey, xOff, maxHitWidth)
		local cb = CreateFrame("CheckButton", nil, leftPane, "UICheckButtonTemplate")
		cb:SetSize(20, 20)
		cb:SetPoint("TOPLEFT", xOff, -34)
		cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cb.text:SetPoint("LEFT", cb, "RIGHT", 1, 0)
		cb.text:SetText(label)
		cb:SetHitRectInsets(0, -math.min(maxHitWidth or 115, math.floor((cb.text:GetStringWidth() or 90) + 6)), 0, 0)
		cb:SetScript("OnClick", function(self)
			ns.db.options[optKey] = self:GetChecked() and true or false
			f.recipeOffset = 0
			ns:RefreshRecipeList()
		end)
		return cb
	end

	f.cbCraftable = CreateFilterCheck(L["FILTER_CRAFTABLE"], "filterCraftable", 8, 105)
	f.cbSkillUp   = CreateFilterCheck(L["FILTER_SKILLUP"], "filterSkillUp", 136, 125)
	f.cbUnlearned = CreateFilterCheck(L["FILTER_UNLEARNED"], "showUnlearned", 285, 130)

	local recipeListBox = CreateFrame("Frame", nil, leftPane, "BackdropTemplate")
	recipeListBox:SetPoint("TOPLEFT", 8, -58)
	recipeListBox:SetPoint("BOTTOMRIGHT", -8, 8)
	StylePanel(recipeListBox, 0.04, 0.04, 0.04, 0.90)
	recipeListBox:EnableMouseWheel(true)

	f.recipeOffset = 0
	f.recipeRows = {}

	recipeListBox:SetScript("OnMouseWheel", function(_, delta)
		local total = #(ns.filteredRecipes or {})
		local maxOff = math.max(0, total - RECIPE_VISIBLE_ROWS)
		f.recipeOffset = math.max(0, math.min(maxOff, f.recipeOffset - delta * 2))
		ns:RenderRecipeListRows()
	end)

	for i = 1, RECIPE_VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, recipeListBox)
		row:SetHeight(RECIPE_ROW_H)
		row:SetPoint("TOPLEFT", 4, -5 - (i - 1) * RECIPE_ROW_H)
		row:SetPoint("TOPRIGHT", -6, -5 - (i - 1) * RECIPE_ROW_H)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		row.sel = row:CreateTexture(nil, "BACKGROUND")
		row.sel:SetAllPoints()
		row.sel:SetColorTexture(0.85, 0.65, 0.15, 0.28)
		row.sel:Hide()

		row.headerBg = row:CreateTexture(nil, "BACKGROUND")
		row.headerBg:SetAllPoints()
		row.headerBg:SetColorTexture(0.18, 0.15, 0.08, 0.75)
		row.headerBg:Hide()

		row.hl = row:CreateTexture(nil, "HIGHLIGHT")
		row.hl:SetAllPoints()
		row.hl:SetColorTexture(1, 0.85, 0.3, 0.14)

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("LEFT", 4, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.rightText:SetPoint("RIGHT", -4, 0)
		row.rightText:SetJustifyH("RIGHT")

		row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -8, 0)
		row.nameText:SetHeight(16)
		row.nameText:SetJustifyH("LEFT")
		row.nameText:SetWordWrap(false)
		if row.nameText.SetMaxLines then row.nameText:SetMaxLines(1) end

		row:SetScript("OnClick", function(self, button)
			local e = self.entryData
			if not e then
				return
			end
			if e.isHeader then
				ns.collapsedCategories = ns.collapsedCategories or {}
				ns.collapsedCategories[e.categoryName] = not (ns.collapsedCategories[e.categoryName] == true)
				ns:RefreshRecipeList()
				return
			end
			if ns:HandleItemClick(e.outItemID, e.recipeID) then
				return
			end
			if button == "RightButton" then
				ns:QueueAddRecipe(e.recipeID, 1)
				return
			end
			ns:SelectRecipeID(e.recipeID)
		end)
		row:SetScript("OnDoubleClick", function(self, button)
			local e = self.entryData
			if e and not e.isHeader and button == "LeftButton" then
				ns:QueueAddRecipe(e.recipeID, 1)
			end
		end)
		row:SetScript("OnEnter", function(self)
			if self.entryData and not self.entryData.isHeader then
				ns:ShowRecipeTooltip(self, self.entryData.recipeID)
			end
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)

		f.recipeRows[i] = row
	end

	---------------------------------------------------------------------------
	-- Правая верхняя панель: «Детали рецепта» | «Калькулятор прокачки»
	---------------------------------------------------------------------------
	local topRight = CreateFrame("Frame", nil, f, "BackdropTemplate")
	topRight:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 8, 0)
	topRight:SetPoint("TOPRIGHT", -12, -54)
	topRight:SetHeight(312)
	StylePanel(topRight, 0.07, 0.065, 0.055, 0.95)
	f.topRight = topRight

	local tabDetailsBtn = ns.CreateTabButton(topRight, 175, 22, L["TAB_DETAILS"])
	tabDetailsBtn:SetPoint("TOPLEFT", 8, -6)

	local tabPlannerBtn = ns.CreateTabButton(topRight, 185, 22, L["TAB_PLANNER"])
	tabPlannerBtn:SetPoint("LEFT", tabDetailsBtn, "RIGHT", 6, 0)

	local topContent = CreateFrame("Frame", nil, topRight)
	topContent:SetPoint("TOPLEFT", 4, -30)
	topContent:SetPoint("BOTTOMRIGHT", -4, 4)

	local detailsView = self:CreateDetailsView(topContent)
	local routeView = self:CreateRouteView(topContent)

	f.topTab = "details"
	local function SelectTopTab(tabKey)
		f.topTab = tabKey
		ns.SetTabButtonActive(tabDetailsBtn, tabKey == "details")
		ns.SetTabButtonActive(tabPlannerBtn, tabKey == "planner")
		detailsView:SetShown(tabKey == "details")
		routeView:SetShown(tabKey == "planner")
		if tabKey == "details" then
			ns:RefreshDetailsView()
		else
			ns:RefreshRouteView()
		end
	end
	ns.SetTabButtonActive(tabDetailsBtn, true)
	ns.SetTabButtonActive(tabPlannerBtn, false)
	f.SelectTopTab = SelectTopTab
	tabDetailsBtn:SetScript("OnClick", function() SelectTopTab("details") end)
	tabPlannerBtn:SetScript("OnClick", function() SelectTopTab("planner") end)

	---------------------------------------------------------------------------
	-- Правая нижняя панель: «Очередь крафта» | «Список покупок»
	---------------------------------------------------------------------------
	local bottomRight = CreateFrame("Frame", nil, f, "BackdropTemplate")
	bottomRight:SetPoint("TOPLEFT", topRight, "BOTTOMLEFT", 0, -8)
	bottomRight:SetPoint("BOTTOMRIGHT", -12, 12)
	StylePanel(bottomRight, 0.07, 0.065, 0.055, 0.95)
	f.bottomRight = bottomRight

	self:CreateQueueAndShoppingView(bottomRight)

	self.mainFrame = f
	return f
end

-------------------------------------------------------------------------------
-- Вкладка «Детали рецепта» (с реальными предметами по ID, порогами и ценами)
-------------------------------------------------------------------------------
function ns:CreateDetailsView(parent)
	local d = CreateFrame("Frame", nil, parent)
	d:SetAllPoints()

	local outBtn = CreateFrame("Button", nil, d, "BackdropTemplate")
	outBtn:SetSize(42, 42)
	outBtn:SetPoint("TOPLEFT", 8, -4)
	StylePanel(outBtn, 0.05, 0.05, 0.05, 1)
	outBtn.icon = outBtn:CreateTexture(nil, "ARTWORK")
	outBtn.icon:SetPoint("TOPLEFT", 3, -3)
	outBtn.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	outBtn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	outBtn:SetScript("OnClick", function(self)
		ns:HandleItemClick(self.itemID, self.recipeID)
	end)
	outBtn:SetScript("OnEnter", function(self)
		if self.recipeID then
			ns:ShowRecipeTooltip(self, self.recipeID)
		end
	end)
	outBtn:SetScript("OnLeave", GameTooltip_Hide)
	d.outBtn = outBtn

	d.recipeTitle = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	d.recipeTitle:SetPoint("TOPLEFT", outBtn, "TOPRIGHT", 10, -2)
	d.recipeTitle:SetPoint("RIGHT", -10, 0)
	d.recipeTitle:SetJustifyH("LEFT")
	d.recipeTitle:SetWordWrap(false)

	d.thresholdLine = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	d.thresholdLine:SetPoint("TOPLEFT", d.recipeTitle, "BOTTOMLEFT", 0, -5)
	d.thresholdLine:SetPoint("RIGHT", -10, 0)
	d.thresholdLine:SetJustifyH("LEFT")

	d.reagentsHeader = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	d.reagentsHeader:SetPoint("TOPLEFT", 10, -52)
	d.reagentsHeader:SetText(L["REAGENTS_HEADER"])

	-- Список реагентов (до 6 слотов)
	d.reagentRows = {}
	for i = 1, 6 do
		local rRow = CreateFrame("Button", nil, d)
		rRow:SetHeight(22)
		rRow:SetPoint("TOPLEFT", 8, -68 - (i - 1) * 22)
		rRow:SetPoint("TOPRIGHT", -200, -68 - (i - 1) * 22)

		rRow.hl = rRow:CreateTexture(nil, "HIGHLIGHT")
		rRow.hl:SetAllPoints()
		rRow.hl:SetColorTexture(1, 0.82, 0.2, 0.14)

		rRow.icon = rRow:CreateTexture(nil, "ARTWORK")
		rRow.icon:SetSize(18, 18)
		rRow.icon:SetPoint("LEFT", 2, 0)
		rRow.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		rRow.countText = rRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		rRow.countText:SetPoint("RIGHT", -4, 0)
		rRow.countText:SetJustifyH("RIGHT")

		rRow.nameText = rRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		rRow.nameText:SetPoint("LEFT", rRow.icon, "RIGHT", 5, 0)
		rRow.nameText:SetPoint("RIGHT", rRow.countText, "LEFT", -6, 0)
		rRow.nameText:SetHeight(16)
		rRow.nameText:SetJustifyH("LEFT")
		rRow.nameText:SetWordWrap(false)
		if rRow.nameText.SetMaxLines then rRow.nameText:SetMaxLines(1) end

		rRow:SetScript("OnClick", function(self)
			if self.itemID and IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP") or IsShiftKeyDown() or IsControlKeyDown()) then
				if ns:HandleItemClick(self.itemID, nil) then
					return
				end
			end
			-- Клик по крафтовому реагенту переводит сразу к рецепту, который его производит
			if self.subRecipeID then
				ns:SelectRecipeID(self.subRecipeID)
			elseif self.itemID then
				local prods = ns.ItemProducedBy and ns.ItemProducedBy[self.itemID]
				if prods and prods[1] then
					ns:SelectRecipeID(prods[1])
				end
			end
		end)
		rRow:SetScript("OnEnter", function(self)
			if self.itemID then
				ns:ShowItemTooltip(self, self.itemID)
			end
		end)
		rRow:SetScript("OnLeave", GameTooltip_Hide)

		d.reagentRows[i] = rRow
	end

	-- Блок экономики справа от реагентов
	local econBox = CreateFrame("Frame", nil, d, "BackdropTemplate")
	econBox:SetSize(185, 130)
	econBox:SetPoint("TOPRIGHT", -8, -66)
	StylePanel(econBox, 0.05, 0.05, 0.05, 0.85)

	local function EconLine(yOff, label)
		local l = econBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l:SetPoint("TOPLEFT", 8, yOff)
		l:SetText(label)
		local v = econBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		v:SetPoint("TOPRIGHT", -8, yOff - 14)
		v:SetJustifyH("RIGHT")
		return v, l
	end

	d.valCraftCost                  = EconLine(-8,  L["CRAFT_COST"])
	d.valOutput, d.lblOutput        = EconLine(-38, L["OUTPUT_VALUE"])
	d.valProfit                     = EconLine(-68, L["NET_PROFIT"])
	d.valCostSkillUp                = EconLine(-98, L["COST_PER_SKILLUP"])

	-- Галочка авто-разворачивания промежуточных крафтов
	local cbSub = CreateFrame("CheckButton", nil, d, "UICheckButtonTemplate")
	cbSub:SetSize(20, 20)
	cbSub:SetPoint("BOTTOMLEFT", 8, 32)
	cbSub.text = cbSub:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cbSub.text:SetPoint("LEFT", cbSub, "RIGHT", 2, 0)
	cbSub.text:SetText(L["AUTO_SUBCRAFTS"])
	cbSub:SetScript("OnClick", function(self)
		ns.db.options.autoSubcrafts = self:GetChecked() and true or false
	end)
	d.cbAutoSub = cbSub

	local tomtomBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	tomtomBtn:SetSize(66, 18)
	tomtomBtn:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -8, 54)
	tomtomBtn:SetText(L["WAYPOINT_BTN"])
	tomtomBtn:SetScript("OnClick", function(self)
		if self.waypoint then
			ns:SetSourceWaypoint(self.waypoint, self.itemName)
		end
	end)
	tomtomBtn:Hide()
	d.tomtomBtn = tomtomBtn

	-- Строка источника для неизученных рецептов (свиток + цена на аукционе / ближайший источник)
	local sourceBtn = CreateFrame("Button", nil, d)
	sourceBtn:SetHeight(16)
	sourceBtn:SetPoint("BOTTOMLEFT", cbSub, "TOPLEFT", 0, 2)
	sourceBtn:SetPoint("RIGHT", -8, 0)
	sourceBtn.text = sourceBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sourceBtn.text:SetAllPoints()
	sourceBtn.text:SetJustifyH("LEFT")
	sourceBtn.text:SetWordWrap(false)
	if sourceBtn.text.SetMaxLines then sourceBtn.text:SetMaxLines(1) end
	sourceBtn:SetScript("OnClick", function(self)
		if self.itemID then
			ns:HandleItemClick(self.itemID, nil)
		end
	end)
	sourceBtn:SetScript("OnEnter", function(self)
		if self.itemID then
			ns:ShowItemTooltip(self, self.itemID, function(tip)
				if self.sourceDetail and self.sourceDetail ~= "" then
					tip:AddLine(" ")
					tip:AddLine(self.sourceDetail, 0.85, 0.85, 0.85, true)
				end
			end)
		elseif self.fullText and self.fullText ~= "" then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:SetText(self.fullText, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	sourceBtn:SetScript("OnLeave", GameTooltip_Hide)
	sourceBtn:Hide()
	d.sourceBtn = sourceBtn

	-- Строка распыления (если изучено Наложение чар и предмет распыляется)
	local deBtn = CreateFrame("Button", nil, d)
	deBtn:SetHeight(16)
	deBtn:SetPoint("BOTTOMLEFT", cbSub, "TOPLEFT", 0, 2)
	deBtn:SetPoint("RIGHT", -8, 0)
	deBtn.text = deBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	deBtn.text:SetAllPoints()
	deBtn.text:SetJustifyH("LEFT")
	deBtn.text:SetWordWrap(false)
	if deBtn.text.SetMaxLines then deBtn.text:SetMaxLines(1) end
	deBtn:SetScript("OnEnter", function(self)
		if self.yields and #self.yields > 0 then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:AddDoubleLine(
				string.format(L["DE_TOOLTIP_HEADER"], self.reqEnch or 1),
				self.deNet and ns.FormatMoney(self.deNet) or "-",
				0.75, 0.65, 1.0, 1, 1, 1
			)
			for _, y in ipairs(self.yields) do
				local yName, _, _, _, _, yHex = ns:GetItemDisplay(y.itemID)
				local p = ns:GetAuctionPrice(y.itemID)
				GameTooltip:AddDoubleLine(
					string.format("  %s%s|r x%.1f", yHex or "|cffffffff", yName, y.avg),
					string.format("%.1f%% (%s)", y.chance * 100, p and ns.FormatMoney(p) or "-"),
					0.85, 0.85, 0.85, 0.8, 0.8, 0.8
				)
			end
			GameTooltip:Show()
		end
	end)
	deBtn:SetScript("OnLeave", GameTooltip_Hide)
	deBtn:Hide()
	d.deBtn = deBtn

	-- Ввод количества и кнопки «В очередь», «В очередь все», «Создать»
	local minusBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	minusBtn:SetSize(24, 24)
	minusBtn:SetPoint("BOTTOMLEFT", 8, 5)
	minusBtn:SetText("-")

	local qtyBox = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
	qtyBox:SetSize(42, 22)
	qtyBox:SetPoint("LEFT", minusBtn, "RIGHT", 6, 0)
	qtyBox:SetAutoFocus(false)
	qtyBox:SetNumeric(true)
	qtyBox:SetMaxLetters(4)
	qtyBox:SetJustifyH("CENTER")
	qtyBox:SetText("1")
	qtyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	qtyBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	d.qtyBox = qtyBox

	local plusBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	plusBtn:SetSize(24, 24)
	plusBtn:SetPoint("LEFT", qtyBox, "RIGHT", 4, 0)
	plusBtn:SetText("+")

	minusBtn:SetScript("OnClick", function()
		local v = math.max(1, (tonumber(qtyBox:GetText()) or 1) - 1)
		qtyBox:SetText(tostring(v))
	end)
	plusBtn:SetScript("OnClick", function()
		local v = math.min(999, (tonumber(qtyBox:GetText()) or 1) + 1)
		qtyBox:SetText(tostring(v))
	end)

	local queueBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	queueBtn:SetSize(115, 24)
	queueBtn:SetPoint("LEFT", plusBtn, "RIGHT", 8, 0)
	queueBtn:SetText(L["BTN_QUEUE_ADD"])
	queueBtn:SetScript("OnClick", function()
		local rID = d.currentRecipeID
		if rID then
			local count = math.max(1, tonumber(qtyBox:GetText()) or 1)
			ns:QueueAddRecipe(rID, count)
		end
	end)

	local queueAllBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	queueAllBtn:SetSize(125, 24)
	queueAllBtn:SetPoint("LEFT", queueBtn, "RIGHT", 6, 0)
	queueAllBtn:SetText(L["BTN_QUEUE_ALL"])
	queueAllBtn:SetScript("OnClick", function()
		local rID = d.currentRecipeID
		if rID then
			local direct, withCraft, withVendor = ns:GetRecipeCraftCounts(rID)
			local best = math.max(1, direct, withCraft, withVendor)
			ns:QueueAddRecipe(rID, best)
		end
	end)

	local craftNowBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	craftNowBtn:SetSize(115, 24)
	craftNowBtn:SetPoint("BOTTOMRIGHT", -8, 5)
	craftNowBtn:SetText(L["BTN_CRAFT_NOW"])
	craftNowBtn:SetScript("OnClick", function()
		local rID = d.currentRecipeID
		if not rID then
			return
		end
		local count = math.max(1, tonumber(qtyBox:GetText()) or 1)
		ns:ExecuteCraftRecipe(rID, count)
	end)
	d.craftNowBtn = craftNowBtn

	self.detailsView = d
	return d
end

function ns:RefreshDetailsView()
	local d = self.detailsView
	if not d or not d:IsVisible() then
		return
	end
	local sl = self.currentSkillLine
	local recipeID = sl and self.selectedRecipeBySkill[sl]
	d.currentRecipeID = recipeID
	d.cbAutoSub:SetChecked(self.db.options.autoSubcrafts ~= false)

	if not recipeID then
		d.outBtn.recipeID = nil
		d.outBtn.itemID = nil
		d.outBtn.icon:SetTexture(nil)
		d.recipeTitle:SetText(L["NO_RECIPE_SELECTED"])
		d.thresholdLine:SetText("")
		if d.sourceBtn then
			d.sourceBtn.itemID = nil
			d.sourceBtn.sourceDetail = nil
			d.sourceBtn.fullText = nil
			d.sourceBtn:Hide()
		end
		if d.tomtomBtn then
			d.tomtomBtn.waypoint = nil
			d.tomtomBtn.itemName = nil
			d.tomtomBtn:Hide()
		end
		if d.deBtn then
			d.deBtn.yields = nil
			d.deBtn:Hide()
		end
		for i = 1, 6 do d.reagentRows[i]:Hide() end
		d.valCraftCost:SetText("-")
		d.valOutput:SetText("-")
		d.valProfit:SetText("-")
		d.valCostSkillUp:SetText("-")
		d.craftNowBtn:SetEnabled(false)
		return
	end

	local prof = self.playerProfessions[sl]
	local curSkill = (prof and prof.rank) or 1
	local rec = self:GetRecipeRecord(recipeID)
	local name, icon, outItemID, _, _, hex = self:GetRecipeDisplay(recipeID)
	local metrics = self:GetRecipeSkillMetrics(recipeID, curSkill, self.db.options.deductVendorInRoute ~= false)
	local craftCost, outVal, profit, breakdown, outSource = self:GetRecipeEconomy(recipeID)

	d.outBtn.recipeID = recipeID
	d.outBtn.itemID = outItemID
	d.outBtn.icon:SetTexture(icon)

	local qtySuffix = (rec and (rec.numMade or 1) > 1) and (" |cffffd100x" .. rec.numMade .. "|r") or ""
	d.recipeTitle:SetText((hex or "|cffffffff") .. name .. "|r" .. qtySuffix)

	local th = metrics.thresholds
	local thParts = {}
	if th then
		thParts[#thParts + 1] = string.format(
			"%s |cffff8040%d|r / |cffffe026%d|r / |cff40d940%d|r / |cff949494%d|r",
			L["THRESHOLDS_LABEL"], th[1] or 1, th[2] or 1, th[3] or 1, th[4] or 1
		)
	end
	if metrics.learned then
		local pct = math.floor((metrics.chance or 0) * 100 + 0.5)
		local dc = self.DIFFICULTY_COLORS[metrics.colorKey] or self.DIFFICULTY_COLORS.grey
		thParts[#thParts + 1] = string.format("%s %s%d%%|r", L["CHANCE_LABEL"], dc.hex, pct)
		if d.sourceBtn then
			d.sourceBtn.itemID = nil
			d.sourceBtn.sourceDetail = nil
			d.sourceBtn.fullText = nil
			d.sourceBtn:Hide()
		end
		if d.tomtomBtn then
			d.tomtomBtn.waypoint = nil
			d.tomtomBtn.itemName = nil
			d.tomtomBtn:Hide()
		end
		if d.deBtn then
			local deNet, yields, reqEnch = outItemID and self.GetItemDisenchantInfo and self:GetItemDisenchantInfo(outItemID)
			if yields and #yields > 0 then
				local parts = {}
				for _, y in ipairs(yields) do
					local yName, _, _, _, _, yHex = self:GetItemDisplay(y.itemID)
					parts[#parts + 1] = string.format("%.0f%% %s%s|r", y.chance * 100, yHex or "|cffffffff", yName)
				end
				d.deBtn.deNet = deNet
				d.deBtn.yields = yields
				d.deBtn.reqEnch = reqEnch
				d.deBtn.text:SetText(string.format(L["DE_LINE_FMT"], reqEnch or 1, deNet and ns.FormatMoney(deNet) or "-", table.concat(parts, ", ")))
				d.deBtn:Show()
			else
				d.deBtn.yields = nil
				d.deBtn:Hide()
			end
		end
	else
		if d.deBtn then
			d.deBtn.yields = nil
			d.deBtn:Hide()
		end
		local src = self.GetRecipeSourceInfo and self:GetRecipeSourceInfo(recipeID)
		if src and src.isTrainer then
			thParts[#thParts + 1] = "|cff809ec7" .. string.format(
				L["RECIPE_UNLEARNED_TAG"],
				ns.FormatMoney(src.trainerFee or 0),
				src.reqSkill or 1
			) .. "|r"
		elseif src and src.scrollItemID then
			thParts[#thParts + 1] = "|cff809ec7" .. string.format(
				L["RECIPE_UNLEARNED_SCROLL"],
				src.reqSkill or 1
			) .. "|r"
		else
			thParts[#thParts + 1] = "|cff809ec7" .. string.format(
				L["RECIPE_UNLEARNED_UNKNOWN"],
				(src and src.reqSkill) or metrics.reqSkill or 1
			) .. "|r"
		end

		if d.sourceBtn then
			local srcParts = {}
			local scrollDisplayName = nil
			if src and src.scrollItemID then
				local sName, _, _, sLink, _, sHex = self:GetItemDisplay(src.scrollItemID)
				scrollDisplayName = sName
				srcParts[#srcParts + 1] = sLink or ((sHex or "|cffffffff") .. sName .. "|r")
				if src.scrollPrice and src.scrollPrice > 0 then
					srcParts[#srcParts + 1] = "|cff88ccff(" .. string.format(L["SOURCE_AH_PRICE"], ns.FormatMoney(src.scrollPrice)) .. ")|r"
				end
			end
			local summaryText = (src and src.sourceText and src.sourceText ~= "") and src.sourceText or nil
			local detailText = (src and src.detailText and src.detailText ~= "") and src.detailText or summaryText
			if summaryText then
				srcParts[#srcParts + 1] = "|cffd0d0d0" .. summaryText .. "|r"
			end
			local wp = src and src.waypoint
			local canTomTom = wp and self.HasTomTom and self:HasTomTom()
			if d.tomtomBtn then
				if canTomTom then
					d.tomtomBtn.waypoint = wp
					d.tomtomBtn.itemName = scrollDisplayName or name
					d.tomtomBtn:Show()
				else
					d.tomtomBtn.waypoint = nil
					d.tomtomBtn.itemName = nil
					d.tomtomBtn:Hide()
				end
			end
			if #srcParts > 0 then
				local full = "|cffffd100" .. L["SOURCE_PREFIX"] .. "|r " .. table.concat(srcParts, " - ")
				d.sourceBtn.itemID = src and src.scrollItemID or nil
				d.sourceBtn.sourceDetail = detailText
				d.sourceBtn.fullText = full
				d.sourceBtn:ClearAllPoints()
				d.sourceBtn:SetPoint("BOTTOMLEFT", d.cbAutoSub, "TOPLEFT", 0, 2)
				if wp and d.tomtomBtn and d.tomtomBtn:IsShown() then
					d.sourceBtn:SetPoint("RIGHT", d.tomtomBtn, "LEFT", -6, 0)
				else
					d.sourceBtn:SetPoint("RIGHT", -8, 0)
				end
				d.sourceBtn.text:SetText(full)
				d.sourceBtn:Show()
			else
				d.sourceBtn.itemID = nil
				d.sourceBtn.sourceDetail = nil
				d.sourceBtn.fullText = nil
				d.sourceBtn:Hide()
			end
		end
	end
	d.thresholdLine:SetText(table.concat(thParts, "   |   "))

	for i = 1, 6 do
		local rRow = d.reagentRows[i]
		local b = breakdown[i]
		if b then
			rRow:Show()
			rRow.itemID = b.itemID
			rRow.subRecipeID = b.subRecipeID
			local iName, iIcon, _, _, _, iHex = self:GetItemDisplay(b.itemID)
			local have = self:GetBagCount(b.itemID)
			local inBank = self.GetBankCount and self:GetBankCount(b.itemID) or 0
			local countColor = (have >= b.quantity) and "|cff40ff40" or "|cffff5555"
			local bankTag = (inBank > 0) and (" |cff66ccff(" .. L["BANK_SHORT"] .. inBank .. ")|r") or ""
			local srcTag = (b.source == "vendor" and L["SOURCE_VENDOR"])
				or (b.source == "craft" and ("|cff66ccff" .. L["SOURCE_CRAFT"] .. "|r"))
				or (b.source == "ah" and L["SOURCE_AH"])
				or L["SOURCE_UNKNOWN"]

			rRow.icon:SetTexture(iIcon)
			rRow.nameText:SetText((iHex or "|cffffffff") .. iName .. "|r |cff999999(" .. srcTag .. ")|r")
			rRow.countText:SetText(string.format("%s%d/%d|r%s  %s", countColor, have, b.quantity, bankTag, ns.FormatMoney(b.lineCost)))
		else
			rRow:Hide()
		end
	end

	if d.lblOutput then
		d.lblOutput:SetText(
			(outSource == "ah" and L["OUTPUT_VALUE_AH"])
			or (outSource == "disenchant" and L["OUTPUT_VALUE_DE"])
			or (outSource == "vendor" and L["OUTPUT_VALUE_VENDOR"])
			or L["OUTPUT_VALUE"]
		)
	end
	d.valCraftCost:SetText(ns.FormatMoney(craftCost))
	d.valOutput:SetText(ns.FormatMoney(outVal))
	d.valProfit:SetText(ns.FormatMoney(profit, true))
	d.valCostSkillUp:SetText(ns.FormatMoney(metrics.costPerSkillUp))
	d.craftNowBtn:SetEnabled(metrics.learned and (self:GetRecipeCraftCounts(recipeID) > 0))
end

-------------------------------------------------------------------------------
-- Отрисовка списка рецептов слева
-------------------------------------------------------------------------------
function ns:RenderRecipeListRows()
	local f = self.mainFrame
	if not f then
		return
	end
	local list = self.filteredRecipes or {}
	local sl = self.currentSkillLine
	local selectedID = sl and self.selectedRecipeBySkill[sl]

	for i = 1, RECIPE_VISIBLE_ROWS do
		local row = f.recipeRows[i]
		local entry = list[i + f.recipeOffset]
		row.entryData = entry
		if entry then
			row:Show()
			if entry.isHeader then
				row.sel:Hide()
				row.headerBg:Show()
				row.icon:Hide()
				row.nameText:ClearAllPoints()
				row.nameText:SetPoint("LEFT", 6, 0)
				row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -8, 0)
				local sign = entry.collapsed and "+" or "-"
				row.nameText:SetText(string.format("|cffffd100[%s] %s (%d)|r", sign, entry.categoryName, entry.count or 0))
				row.rightText:SetText("")
			else
				row.headerBg:Hide()
				row.sel:SetShown(entry.recipeID == selectedID)
				row.icon:Show()
				row.icon:SetTexture(entry.icon)
				row.nameText:ClearAllPoints()
				row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
				row.nameText:SetPoint("RIGHT", row.rightText, "LEFT", -8, 0)

				local dc = self.DIFFICULTY_COLORS[entry.metrics.colorKey] or self.DIFFICULTY_COLORS.grey
				local countsStr = FormatCraftCounts(entry.direct, entry.withCraft, entry.withVendor, entry.withBank)
				local trainerTag = (not entry.learned) and string.format(" |cff809ec7[%d]|r", entry.metrics.reqSkill or 1) or ""
				row.nameText:SetText(dc.hex .. entry.name .. "|r" .. trainerTag .. countsStr)

				local pct = math.floor((entry.metrics.chance or 0) * 100 + 0.5)
				local sortMode = (self.db and self.db.options and self.db.options.sortMode) or "difficulty"
				if sortMode == "profit" then
					local profStr = entry.profit and ns.FormatMoney(entry.profit, true) or ""
					if pct > 0 and profStr ~= "" then
						row.rightText:SetText(string.format("%s%d%%|r  %s", dc.hex, pct, profStr))
					else
						row.rightText:SetText(profStr)
					end
				elseif pct > 0 then
					local costStr = entry.metrics.costPerSkillUp and ns.FormatMoney(entry.metrics.costPerSkillUp) or ""
					row.rightText:SetText(string.format("%s%d%%|r  %s", dc.hex, pct, costStr))
				else
					row.rightText:SetText(entry.profit and ns.FormatMoney(entry.profit, true) or "")
				end
			end
		else
			row:Hide()
		end
	end
end

function ns:RefreshRecipeList()
	local f = self.mainFrame
	if not f or not f:IsShown() then
		return
	end
	f.cbCraftable:SetChecked(self.db.options.filterCraftable == true)
	f.cbSkillUp:SetChecked(self.db.options.filterSkillUp == true)
	f.cbUnlearned:SetChecked(self.db.options.showUnlearned == true)
	if f.catBtn then
		ns.SetTabButtonActive(f.catBtn, self.db.options.groupByCategory == true)
	end

	local list = self:BuildFilteredRecipeList()
	local maxOff = math.max(0, #list - RECIPE_VISIBLE_ROWS)
	if self.scrollToSelectedRecipe then
		local sl = self.currentSkillLine
		local sel = sl and self.selectedRecipeBySkill[sl]
		if sel then
			for idx, e in ipairs(list) do
				if e.recipeID == sel then
					if idx <= f.recipeOffset or idx > f.recipeOffset + RECIPE_VISIBLE_ROWS then
						f.recipeOffset = math.max(0, math.min(maxOff, idx - math.floor(RECIPE_VISIBLE_ROWS / 2)))
					end
					break
				end
			end
		end
	end
	if f.recipeOffset > maxOff then
		f.recipeOffset = maxOff
	end
	self:RenderRecipeListRows()
	self:RefreshDetailsView()
	if f.topTab == "planner" then
		self:RefreshRouteView()
	end
end

function ns:RefreshMainWindow()
	local f = self:CreateMainFrame()
	if not f:IsShown() then
		return
	end

	-- Обновляем кнопки профессий в шапке
	local profList = {}
	for sl, p in pairs(self.playerProfessions) do
		profList[#profList + 1] = p
	end
	if #profList == 0 then
		for sl, sp in pairs(self.PROF_SPELLS) do
			profList[#profList + 1] = {
				skillLine = sl,
				name = self:GetProfessionName(sl),
				rank = 1,
				maxRank = 75,
				icon = self.PROF_ICONS[sl],
				spellID = sp,
			}
		end
	end
	table.sort(profList, function(a, b) return a.skillLine < b.skillLine end)

	if not self.currentSkillLine and profList[1] then
		self.currentSkillLine = profList[1].skillLine
	end

	for i = 1, #f.profButtons do
		local btn = f.profButtons[i]
		local p = profList[i]
		if p then
			btn.skillLine = p.skillLine
			btn.tex:SetTexture(p.icon or self.PROF_ICONS[p.skillLine])
			if p.skillLine == self.currentSkillLine then
				btn:SetBackdropBorderColor(1.0, 0.82, 0.20, 1)
			else
				btn:SetBackdropBorderColor(0.45, 0.38, 0.22, 0.8)
			end
			btn:Show()
		else
			btn:Hide()
		end
	end

	local curProf = self.currentSkillLine and self.playerProfessions[self.currentSkillLine]
	local rank = (curProf and curProf.rank) or 1
	local maxRank = (curProf and curProf.maxRank) or 75
	local profName = self:GetProfessionName(self.currentSkillLine or 171)
	f.headerIcon:SetTexture(self.ICON)
	f.rankBar:SetMinMaxValues(0, math.max(1, maxRank))
	f.rankBar:SetValue(rank)
	f.rankBar.text:SetText(string.format("%s  %d / %d", profName, rank, maxRank))
	f.langBtn:SetText(self.lang == "ru" and "RU" or "EN")
	if f.cbVendor then
		f.cbVendor:SetChecked(self.db.options.deductVendorInRoute ~= false)
	end

	self:RefreshRecipeList()
	self:RefreshQueueAndShoppingView()
end

function ns:RefreshVisibleUI()
	if self.mainFrame and self.mainFrame:IsShown() then
		self:RefreshMainWindow()
	end
end

function ns:ShowMainWindow()
	local f = self:CreateMainFrame()
	f:Show()
	self:RefreshMainWindow()
end

function ns:HideMainWindow()
	if self.settingsFrame and self.settingsFrame:IsShown() then
		self.settingsFrame:Hide()
	end
	if self.mainFrame and self.mainFrame:IsShown() then
		self.mainFrame:Hide()
	end
end

function ns:ToggleSettingsFrame()
	if not self.settingsFrame then
		local sf = CreateFrame("Frame", "TradeFlowSettingsFrame", UIParent, "BackdropTemplate")
		sf:SetSize(310, 196)
		sf:SetFrameStrata("DIALOG")
		sf:SetToplevel(true)
		sf:SetClampedToScreen(true)
		sf:SetMovable(true)
		sf:EnableMouse(true)
		sf:RegisterForDrag("LeftButton")
		sf:SetScript("OnDragStart", sf.StartMoving)
		sf:SetScript("OnDragStop", sf.StopMovingOrSizing)
		StylePanel(sf, 0.07, 0.065, 0.055, 0.98)
		sf:Hide()

		local title = sf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 12, -10)
		title:SetText("|cffffd100" .. L["SETTINGS_TITLE"] .. "|r")

		local close = CreateFrame("Button", nil, sf, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
		close:SetScript("OnClick", function() sf:Hide() end)

		local opts = {
			{ key = "includeDisenchant",    label = L["OPT_INCLUDE_DE"],          defaultTrue = true,  invalidatePrices = true },
			{ key = "deductVendorInRoute",  label = L["PLANNER_DEDUCT_VENDOR"],   defaultTrue = true,  invalidatePrices = true },
			{ key = "includeTrainerInRoute",label = L["PLANNER_INCLUDE_TRAINER"], defaultTrue = true,  invalidatePrices = false },
			{ key = "autoSubcrafts",        label = L["AUTO_SUBCRAFTS"],          defaultTrue = true,  invalidatePrices = false },
			{ key = "groupByCategory",      label = L["GROUP_BY_CATEGORY"],       defaultTrue = false, invalidatePrices = false },
		}

		sf.checks = {}
		for i, o in ipairs(opts) do
			local cb = CreateFrame("CheckButton", nil, sf, "UICheckButtonTemplate")
			cb:SetSize(22, 22)
			cb:SetPoint("TOPLEFT", 12, -34 - (i - 1) * 28)
			cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
			cb.text:SetText(o.label)
			cb:SetHitRectInsets(0, -240, 0, 0)
			cb:SetScript("OnClick", function(self)
				ns.db.options[o.key] = self:GetChecked() and true or false
				if o.invalidatePrices and ns.InvalidatePrices then
					ns:InvalidatePrices()
				elseif ns.RefreshMainWindow then
					ns:RefreshMainWindow()
				end
			end)
			sf.checks[i] = { cb = cb, opt = o }
		end

		tinsert(UISpecialFrames, "TradeFlowSettingsFrame")
		self.settingsFrame = sf
	end

	local sf = self.settingsFrame
	if sf:IsShown() then
		sf:Hide()
		return
	end
	if self.mainFrame and self.mainFrame.settingsBtn then
		sf:ClearAllPoints()
		sf:SetPoint("TOPRIGHT", self.mainFrame.settingsBtn, "BOTTOMRIGHT", 0, -4)
	else
		sf:ClearAllPoints()
		sf:SetPoint("CENTER")
	end
	for _, entry in ipairs(sf.checks) do
		local val = self.db and self.db.options and self.db.options[entry.opt.key]
		if entry.opt.defaultTrue then
			entry.cb:SetChecked(val ~= false)
		else
			entry.cb:SetChecked(val == true)
		end
	end
	sf:Show()
end

function ns:ToggleMainWindow()
	local f = self:CreateMainFrame()
	if f:IsShown() then
		f:Hide()
	else
		self:ShowMainWindow()
	end
end

function ns:RebuildMainFrame()
	local wasShown = self.mainFrame and self.mainFrame:IsShown()
	local topTab = self.mainFrame and self.mainFrame.topTab or "details"
	local bottomMode = self.queueView and self.queueView.activeMode or "queue"
	if self.mainFrame then
		self.isRebuildingFrame = true
		self.mainFrame:Hide()
		self.isRebuildingFrame = false
		self.mainFrame = nil
		self.detailsView = nil
		self.routeView = nil
		self.queueView = nil
	end
	if wasShown then
		local f = self:CreateMainFrame()
		f.topTab = topTab
		self.detailsView:SetShown(topTab == "details")
		self.routeView:SetShown(topTab == "planner")
		if self.queueView then
			self.queueView.activeMode = bottomMode
		end
		self:ShowMainWindow()
	end
end

-- Кнопка в меню аддонов у миникарты (Addon Compartment)
function TradeFlow_OnAddonCompartmentClick()
	ns:ToggleMainWindow()
end

