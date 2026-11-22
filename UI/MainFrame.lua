local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Главное окно TradeFlow (полная замена окна профессий в стиле Skillet + SkillUp)
-------------------------------------------------------------------------------
local WIN_W, WIN_H = 980, 640
local LEFT_W = 445
local TOP_RIGHT_H = 342
local RECIPE_ROW_H = 24
local RECIPE_VISIBLE_ROWS = 20

local secureProfProxy = nil

function ns:IsSecureProfProxyOwner(btn)
	return secureProfProxy ~= nil and secureProfProxy:IsShown() and secureProfProxy.targetBtn == btn
end

function ns:SyncHoveredProfProxy()
	if not self.mainFrame or not self.mainFrame:IsShown() or (InCombatLockdown and InCombatLockdown()) then
		return
	end
	if self.queueView and self.queueView.processBtn and self.queueView.processBtn:IsVisible() and self.queueView.processBtn:IsMouseOver() then
		local pBtn = self.queueView.processBtn
		if pBtn.pendingSkillLine then
			self:AttachSecureProfProxy(pBtn, pBtn.pendingSkillLine)
		elseif self:IsSecureProfProxyOwner(pBtn) then
			self:DetachSecureProfProxy()
		end
		return
	end
	if self.detailsView and self.detailsView.craftNowBtn and self.detailsView.craftNowBtn:IsVisible() and self.detailsView.craftNowBtn:IsMouseOver() then
		local cBtn = self.detailsView.craftNowBtn
		if cBtn.pendingSkillLine then
			self:AttachSecureProfProxy(cBtn, cBtn.pendingSkillLine)
		elseif self:IsSecureProfProxyOwner(cBtn) then
			self:DetachSecureProfProxy()
		end
		return
	end
	if self.mainFrame.profButtons then
		for _, pb in ipairs(self.mainFrame.profButtons) do
			if pb:IsVisible() and pb.skillLine and pb:IsMouseOver() then
				if not self:AttachSecureProfProxy(pb, pb.skillLine) and self:IsSecureProfProxyOwner(pb) then
					self:DetachSecureProfProxy()
				end
				return
			end
		end
	end
end

function ns:DetachSecureProfProxy()
	if not secureProfProxy then
		return
	end
	local prev = secureProfProxy.targetBtn
	secureProfProxy.targetBtn = nil
	secureProfProxy.skillLine = nil
	if prev and prev.UnlockHighlight then
		prev:UnlockHighlight()
	end
	GameTooltip_Hide()
	if not (InCombatLockdown and InCombatLockdown()) then
		secureProfProxy:SetAttribute("type", nil)
		secureProfProxy:SetAttribute("spell", nil)
		secureProfProxy:ClearAllPoints()
		secureProfProxy:Hide()
	end
end

function ns:AttachSecureProfProxy(btn, skillLine)
	if not (btn and skillLine) or (InCombatLockdown and InCombatLockdown()) then
		return false
	end
	local activeClientSL = self.GetActiveClientSkillLine and self:GetActiveClientSkillLine() or nil
	if activeClientSL == skillLine then
		return false
	end
	local spellAttr = self.GetProfessionSpellAttr and self:GetProfessionSpellAttr(skillLine) or nil
	if not spellAttr then
		return false
	end
	local l, b, w, h = btn:GetLeft(), btn:GetBottom(), btn:GetWidth(), btn:GetHeight()
	if not (l and b and w and h and w > 0 and h > 0) then
		return false
	end
	if not secureProfProxy then
		secureProfProxy = CreateFrame("Button", "TradeFlowSecureProfProxy", UIParent, "SecureActionButtonTemplate")
		secureProfProxy:RegisterForClicks("AnyUp")
		secureProfProxy:SetAttribute("useOnKeyDown", false)
		secureProfProxy:SetScript("PreClick", function(self)
			if self.skillLine and ns.PrepareSecureProfSwitch then
				ns:PrepareSecureProfSwitch()
			end
		end)
		secureProfProxy:SetScript("PostClick", function(self)
			local sl = self.skillLine
			ns:DetachSecureProfProxy()
			if sl then
				ns:SwitchToProfession(sl)
			end
		end)
		secureProfProxy:SetScript("OnLeave", function()
			ns:DetachSecureProfProxy()
		end)
	end
	local prev = secureProfProxy.targetBtn
	if prev and prev ~= btn and prev.UnlockHighlight then
		prev:UnlockHighlight()
	end
	local ratio = (btn:GetEffectiveScale() or 1) / ((UIParent and UIParent:GetEffectiveScale()) or 1)
	secureProfProxy.targetBtn = btn
	secureProfProxy.skillLine = skillLine
	secureProfProxy:SetFrameStrata(btn:GetFrameStrata() or "MEDIUM")
	secureProfProxy:SetFrameLevel((btn:GetFrameLevel() or 1) + 15)
	secureProfProxy:ClearAllPoints()
	secureProfProxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * ratio, b * ratio)
	secureProfProxy:SetSize(w * ratio, h * ratio)
	secureProfProxy:SetAttribute("type", "spell")
	secureProfProxy:SetAttribute("spell", spellAttr)
	secureProfProxy:Show()
	if btn.LockHighlight then
		btn:LockHighlight()
	end
	return true
end

function ns:GetUIScale()
	local s = self.db and self.db.options and tonumber(self.db.options.uiScale)
	if not s or s < 0.6 or s > 1.4 then
		return 1.0
	end
	return math.floor(s * 20 + 0.5) / 20
end

function ns:ApplyUIScale()
	if not self.mainFrame then
		return
	end
	self:DetachSecureProfProxy()
	local scale = self:GetUIScale()
	local right, top = self.mainFrame:GetRight(), self.mainFrame:GetTop()
	local oldScale = self.mainFrame:GetScale() or 1.0
	self.mainFrame:SetScale(scale)
	if right and top and math.abs(scale - oldScale) > 0.001 then
		local absRight = right * oldScale
		local absTop = top * oldScale
		self.mainFrame:ClearAllPoints()
		self.mainFrame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", absRight / scale, absTop / scale)
	end
end

function ns:ApplyWindowLayout(keepTopRight)
	local f = self.mainFrame
	if not f then
		return
	end
	self:DetachSecureProfProxy()
	local right, top
	if keepTopRight then
		right, top = f:GetRight(), f:GetTop()
	end
	local opts = (self.db and self.db.options) or {}
	local isMin = (opts.windowMinimized == true)
	local isCol = (opts.leftCollapsed == true)
	local compact = isMin or isCol

	if f.collapseLeftBtn then
		f.collapseLeftBtn:SetShown(not isMin)
		f.collapseLeftBtn:SetText(isCol and "<<" or ">>")
	end
	if f.minBtn then
		f.minBtn:SetText(isMin and "+" or "-")
	end
	if f.rankBar then
		f.rankBar:SetShown(not compact)
	end
	if f.cbVendor then
		f.cbVendor:SetShown(not compact)
	end
	if f.blizzBtn then
		f.blizzBtn:SetShown(not compact)
	end

	local compactW = WIN_W - LEFT_W - 8
	local minH = WIN_H - TOP_RIGHT_H - 8
	if isMin then
		f:SetSize(compactW, minH)
		f.leftPane:Hide()
		f.topRight:Hide()
		f.bottomRight:ClearAllPoints()
		f.bottomRight:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -54)
		f.bottomRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
		f.bottomRight:Show()
	elseif isCol then
		f:SetSize(compactW, WIN_H)
		f.leftPane:Hide()
		f.topRight:ClearAllPoints()
		f.topRight:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -54)
		f.topRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -54)
		f.topRight:SetHeight(TOP_RIGHT_H)
		f.topRight:Show()
		f.bottomRight:ClearAllPoints()
		f.bottomRight:SetPoint("TOPLEFT", f.topRight, "BOTTOMLEFT", 0, -8)
		f.bottomRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
		f.bottomRight:Show()
	else
		f:SetSize(WIN_W, WIN_H)
		f.leftPane:Show()
		f.topRight:ClearAllPoints()
		f.topRight:SetPoint("TOPLEFT", f.leftPane, "TOPRIGHT", 8, 0)
		f.topRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -54)
		f.topRight:SetHeight(TOP_RIGHT_H)
		f.topRight:Show()
		f.bottomRight:ClearAllPoints()
		f.bottomRight:SetPoint("TOPLEFT", f.topRight, "BOTTOMLEFT", 0, -8)
		f.bottomRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
		f.bottomRight:Show()
	end

	if keepTopRight and right and top then
		f:ClearAllPoints()
		f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
	end
end

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

-- Форматирование счётчика крафтов рецепта: [в сумках / +крафт / +вендор / Б:банк] (остаток с учётом очереди)
local function FormatCraftCounts(direct, withCraft, withVendor, withBank, remaining)
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
	local baseStr = " |cff888888[" .. table.concat(parts, "/") .. "]|r"
	local rawMax = math.max(direct or 0, withCraft or 0, withVendor or 0, withBank or 0)
	if remaining ~= nil and remaining < rawMax then
		local remColor = (remaining > 0) and "|cff00ff99" or "|cffff6666"
		return baseStr .. " |cff888888(|r" .. remColor .. remaining .. "|r|cff888888)|r"
	end
	return baseStr
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
	local sel = self.selectedRecipeBySkill[sl]
	local pinned = self.pinnedRecipeBySkill and self.pinnedRecipeBySkill[sl]

	for _, recipeID in ipairs(rawIDs) do
		local learned = self:IsRecipeLearned(recipeID)
		local metrics = self:GetRecipeSkillMetrics(recipeID, curSkill, deductVendor)
		-- При включённой галочке показываем неизученные рецепты (в первую очередь доступные сейчас или в ближайшие +40 очков навыка).
		-- Рецепт, выбранный явно (например, из калькулятора прокачки или очереди), удерживается и выделяется слева, игнорируя галку.
		local isPinned = (pinned ~= nil and pinned == recipeID and sel == recipeID)
		local unlearnedRelevant = showUnlearned and not learned and ((metrics.reqSkill or 1) <= curSkill + 40)
		if learned or unlearnedRelevant or isPinned then
			local direct, withCraft, withVendor, _, withBank = self:GetRecipeCraftCounts(recipeID)
			local canCraft = (direct > 0 or withCraft > 0 or withVendor > 0 or (withBank or 0) > 0)
			local givesSkill = (metrics.chance and metrics.chance > 0)

			local passFilter = true
			if not isPinned then
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
			end

			if passFilter then
				local name, icon, outItemID = self:GetRecipeDisplay(recipeID)
				local live = self.liveRecipes and self.liveRecipes[recipeID]
				local isFav = self.IsRecipeFavorite and self:IsRecipeFavorite(recipeID) or false
				local remCount = nil
				if canCraft and self.GetQueue and #self:GetQueue() > 0 and self.GetRemainingCraftableCount then
					local rawBagBest = math.max(direct or 0, withCraft or 0, withVendor or 0)
					local useBank = (withBank or 0) > rawBagBest
					remCount = self:GetRemainingCraftableCount(recipeID, useBank)
				end
				entries[#entries + 1] = {
					recipeID = recipeID,
					name = name,
					icon = icon,
					outItemID = outItemID,
					categoryName = (live and live.categoryName) or L["CAT_OTHER"],
					learned = learned,
					favorite = isFav,
					direct = direct,
					withCraft = withCraft,
					withVendor = withVendor,
					withBank = withBank,
					remaining = remCount,
					metrics = metrics,
					profit = metrics.profit,
				}
			end
		end
	end

	table.sort(entries, function(a, b)
		if opts.groupByCategory ~= true and a.favorite ~= b.favorite then
			return a.favorite
		end
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
			local c = e.favorite and L["CAT_FAVORITES"] or (e.categoryName or L["CAT_OTHER"])
			if not byCat[c] then
				byCat[c] = {}
				catOrder[#catOrder + 1] = c
			end
			byCat[c][#byCat[c] + 1] = e
		end
		table.sort(catOrder, function(a, b)
			if a == L["CAT_FAVORITES"] then return true end
			if b == L["CAT_FAVORITES"] then return false end
			if a == L["CAT_OTHER"] then return false end
			if b == L["CAT_OTHER"] then return true end
			return a < b
		end)
		local grouped = {}
		for _, c in ipairs(catOrder) do
			local list = byCat[c]
			local hasPinned = false
			if pinned then
				for _, e in ipairs(list) do
					if e.recipeID == pinned and e.recipeID == sel then
						hasPinned = true
						break
					end
				end
			end
			local collapsed = (self.collapsedCategories[c] == true) and not hasPinned
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
	self.pinnedRecipeBySkill = self.pinnedRecipeBySkill or {}
	if self.currentSkillLine then
		self.selectedRecipeBySkill[self.currentSkillLine] = recipeID
		self.pinnedRecipeBySkill[self.currentSkillLine] = recipeID
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
	-- Новый фрейм видим: прячем до установки OnHide, иначе f:Hide() ниже вызовет его,
	-- и CloseTradeSkill закроет профессию, из которой окно TradeFlow сейчас открывается
	f:Hide()
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
		ns._lastEnchantCraftAt = nil
		if ns.DetachSecureProfProxy then
			ns:DetachSecureProfProxy()
		end
		if ns.HideSniperSettingsFrame then
			ns:HideSniperSettingsFrame("tab")
		end
		if ns.ClearReplaceEnchantSpace then
			ns.ClearReplaceEnchantSpace()
		end
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

	local collapseLeftBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	collapseLeftBtn:SetSize(24, 22)
	collapseLeftBtn:SetPoint("LEFT", 6, 0)
	collapseLeftBtn:SetText(">>")
	collapseLeftBtn:SetScript("OnClick", function()
		if not (ns.db and ns.db.options) then
			return
		end
		ns.db.options.leftCollapsed = not (ns.db.options.leftCollapsed == true)
		if f.sortMenu then
			f.sortMenu:Hide()
		end
		ns:ApplyWindowLayout(true)
		if not ns.db.options.leftCollapsed then
			ns:RefreshRecipeList()
		end
	end)
	collapseLeftBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		local isCol = ns.db and ns.db.options and ns.db.options.leftCollapsed == true
		GameTooltip:SetText(isCol and L["BTN_EXPAND_RECIPES_TIP"] or L["BTN_COLLAPSE_RECIPES_TIP"], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	collapseLeftBtn:SetScript("OnLeave", GameTooltip_Hide)
	f.collapseLeftBtn = collapseLeftBtn

	local icon = header:CreateTexture(nil, "ARTWORK")
	icon:SetSize(24, 24)
	icon:SetPoint("LEFT", collapseLeftBtn, "RIGHT", 4, 0)
	icon:SetTexture(self.ICON)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.headerIcon = icon

	local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	title:SetText("|cffffd100" .. L["ADDON_TITLE"] .. "|r")
	f.headerTitle = title

	-- Кнопки переключения профессий персонажа (обычные Button; безопасный каст профессии вешается через TradeFlowSecureProfProxy на UIParent)
	local profStartX = 142
	f.profButtons = {}
	for i = 1, 6 do
		local pb = CreateFrame("Button", nil, header, "BackdropTemplate")
		pb:SetSize(26, 26)
		pb:SetPoint("LEFT", header, "LEFT", profStartX + (i - 1) * 30, 0)
		StylePanel(pb, 0.10, 0.10, 0.10, 0.95)
		pb:RegisterForClicks("AnyUp")
		pb.tex = pb:CreateTexture(nil, "ARTWORK")
		pb.tex:SetPoint("TOPLEFT", 3, -3)
		pb.tex:SetPoint("BOTTOMRIGHT", -3, 3)
		pb.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		pb:SetScript("OnClick", function(self)
			if self.skillLine then
				ns:SwitchToProfession(self.skillLine)
				if ns.GetActiveClientSkillLine and ns:GetActiveClientSkillLine() ~= self.skillLine then
					ns:AttachSecureProfProxy(self, self.skillLine)
				end
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
				ns:AttachSecureProfProxy(self, self.skillLine)
			end
		end)
		pb:SetScript("OnLeave", function(self)
			if not ns:IsSecureProfProxyOwner(self) then
				GameTooltip_Hide()
			end
		end)
		f.profButtons[i] = pb
	end

	-- Полоса прогресса навыка текущей профессии
	local rankBar = CreateFrame("StatusBar", nil, header, "BackdropTemplate")
	rankBar:SetSize(180, 18)
	rankBar:SetPoint("CENTER", header, "CENTER", -44, 0)
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
	cbVendor:SetPoint("LEFT", rankBar, "RIGHT", 10, 0)
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

	local minBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	minBtn:SetSize(22, 22)
	minBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
	minBtn:SetText("-")
	minBtn:SetScript("OnClick", function()
		if not (ns.db and ns.db.options) then
			return
		end
		ns.db.options.windowMinimized = not (ns.db.options.windowMinimized == true)
		if f.sortMenu then
			f.sortMenu:Hide()
		end
		ns:ApplyWindowLayout(true)
		ns:RefreshMainWindow()
	end)
	minBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		local isMin = ns.db and ns.db.options and ns.db.options.windowMinimized == true
		GameTooltip:SetText(isMin and L["BTN_RESTORE_WINDOW_TIP"] or L["BTN_MINIMIZE_QUEUE_TIP"], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	minBtn:SetScript("OnLeave", GameTooltip_Hide)
	f.minBtn = minBtn

	local langBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	langBtn:SetSize(34, 22)
	langBtn:SetPoint("RIGHT", minBtn, "LEFT", -4, 0)
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
	settingsBtn:SetSize(80, 22)
	settingsBtn:SetPoint("RIGHT", langBtn, "LEFT", -4, 0)
	settingsBtn:SetText(L["SETTINGS_BTN"])
	settingsBtn:SetScript("OnClick", function()
		ns:ToggleSettingsFrame()
	end)
	f.settingsBtn = settingsBtn

	local blizzBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	blizzBtn:SetSize(100, 22)
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
	f.blizzBtn = blizzBtn

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
	searchBox:SetSize(250, 20)
	searchBox:SetPoint("TOPLEFT", 14, -10)
	searchBox:SetAutoFocus(false)
	searchBox:SetText(self.searchQuery or "")
	searchBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			ns.searchQuery = self:GetText()
			if ns.pinnedRecipeBySkill and ns.currentSkillLine then
				ns.pinnedRecipeBySkill[ns.currentSkillLine] = nil
			end
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
		if ns.pinnedRecipeBySkill and ns.currentSkillLine then
			ns.pinnedRecipeBySkill[ns.currentSkillLine] = nil
		end
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
	sortMenu:SetFrameLevel(leftPane:GetFrameLevel() + 50)
	sortMenu:SetToplevel(true)
	sortMenu:EnableMouse(true)
	StylePanel(sortMenu, 0.08, 0.07, 0.06, 0.98)
	sortMenu:Hide()
	f.sortMenu = sortMenu

	local sortMenuButtons = {}
	for i, m in ipairs(SORT_MODES) do
		local item = CreateFrame("Button", nil, sortMenu)
		item:SetHeight(22)
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
			if ns.pinnedRecipeBySkill and ns.currentSkillLine then
				ns.pinnedRecipeBySkill[ns.currentSkillLine] = nil
			end
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

	local function ScrollRecipesByDelta(delta)
		local total = #(ns.filteredRecipes or {})
		local maxOff = math.max(0, total - RECIPE_VISIBLE_ROWS)
		f.recipeOffset = math.max(0, math.min(maxOff, f.recipeOffset - delta * 2))
		ns:RenderRecipeListRows()
	end

	recipeListBox:SetScript("OnMouseWheel", function(_, delta)
		ScrollRecipesByDelta(delta)
	end)

	local recipeScrollBar = CreateFrame("Slider", nil, recipeListBox, "BackdropTemplate")
	recipeScrollBar:SetPoint("TOPRIGHT", recipeListBox, "TOPRIGHT", -4, -6)
	recipeScrollBar:SetPoint("BOTTOMRIGHT", recipeListBox, "BOTTOMRIGHT", -4, 6)
	recipeScrollBar:SetWidth(10)
	recipeScrollBar:SetOrientation("VERTICAL")
	recipeScrollBar:SetValueStep(1)
	if recipeScrollBar.SetObeyStepOnDrag then
		recipeScrollBar:SetObeyStepOnDrag(true)
	end
	recipeScrollBar:SetMinMaxValues(0, 0)
	recipeScrollBar:SetValue(0)
	recipeScrollBar:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	recipeScrollBar:SetBackdropColor(0.02, 0.02, 0.02, 0.85)
	recipeScrollBar:SetBackdropBorderColor(0.45, 0.36, 0.18, 0.8)
	local thumb = recipeScrollBar:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(0.85, 0.68, 0.22, 0.85)
	thumb:SetSize(6, 28)
	recipeScrollBar:SetThumbTexture(thumb)
	recipeScrollBar:EnableMouseWheel(true)
	recipeScrollBar:SetScript("OnMouseWheel", function(_, delta)
		ScrollRecipesByDelta(delta)
	end)
	recipeScrollBar:SetScript("OnValueChanged", function(_, value)
		if f._updatingRecipeScroll then
			return
		end
		local total = #(ns.filteredRecipes or {})
		local maxOff = math.max(0, total - RECIPE_VISIBLE_ROWS)
		local newOff = math.max(0, math.min(maxOff, math.floor((value or 0) + 0.5)))
		if newOff ~= f.recipeOffset then
			f.recipeOffset = newOff
			ns:RenderRecipeListRows()
		end
	end)
	f.recipeScrollBar = recipeScrollBar

	for i = 1, RECIPE_VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, recipeListBox)
		row:SetHeight(RECIPE_ROW_H)
		row:SetPoint("TOPLEFT", 4, -5 - (i - 1) * RECIPE_ROW_H)
		row:SetPoint("TOPRIGHT", -16, -5 - (i - 1) * RECIPE_ROW_H)
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
			if f.sortMenu then
				f.sortMenu:Hide()
			end
			local e = self.entryData
			if not e then
				return
			end
			if e.isHeader then
				ns.collapsedCategories = ns.collapsedCategories or {}
				ns.collapsedCategories[e.categoryName] = not (ns.collapsedCategories[e.categoryName] == true)
				if ns.collapsedCategories[e.categoryName] and ns.pinnedRecipeBySkill and ns.currentSkillLine then
					ns.pinnedRecipeBySkill[ns.currentSkillLine] = nil
				end
				ns:RefreshRecipeList()
				return
			end
			if ns:HandleItemClick(e.outItemID, e.recipeID) then
				return
			end
			if button == "RightButton" then
				if ns.ToggleRecipeFavorite then
					ns:ToggleRecipeFavorite(e.recipeID)
				end
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
	topRight:SetHeight(342)
	StylePanel(topRight, 0.07, 0.065, 0.055, 0.95)
	f.topRight = topRight

	local tabDetailsBtn = ns.CreateTabButton(topRight, 146, 22, L["TAB_DETAILS"])
	local tabPlannerBtn = ns.CreateTabButton(topRight, 170, 22, L["TAB_PLANNER"])

	local topContent = CreateFrame("Frame", nil, topRight)
	topContent:SetPoint("TOPLEFT", 4, -30)
	topContent:SetPoint("BOTTOMRIGHT", -4, 4)

	local detailsView = self:CreateDetailsView(topContent)
	local routeView = self:CreateRouteView(topContent)

	local topTabs = {
		{ key = "details", btn = tabDetailsBtn, view = detailsView, width = 146 },
		{ key = "planner", btn = tabPlannerBtn, view = routeView, width = 170 },
	}
	local modTabsByKey = {}
	for _, mod in ipairs((self.GetTopTabModules and self:GetTopTabModules()) or {}) do
		local w = mod.tabWidth or 148
		local btn = ns.CreateTabButton(topRight, w, 22, L[mod.tabTitleKey] or mod.id)
		local entry = { key = mod.id, btn = btn, view = nil, width = w, mod = mod }
		topTabs[#topTabs + 1] = entry
		modTabsByKey[mod.id] = entry
	end

	f.topTab = "details"
	local function SelectTopTab(tabKey, skipRefresh)
		if modTabsByKey[tabKey] and not ns:IsModuleEnabled(tabKey) then
			tabKey = "details"
		end
		f.topTab = tabKey
		if tabKey ~= "profit" and ns.HideSniperSettingsFrame then
			ns:HideSniperSettingsFrame("tab")
		end
		for _, t in ipairs(topTabs) do
			local active = (t.key == tabKey)
			if active and t.mod and not t.view then
				t.view = t.mod:CreateView(topContent)
			end
			ns.SetTabButtonActive(t.btn, active)
			if t.view then
				t.view:SetShown(active)
			end
		end
		if skipRefresh then
			return
		end
		if tabKey == "details" then
			ns:RefreshDetailsView()
		elseif tabKey == "planner" then
			ns:RefreshRouteView()
		elseif modTabsByKey[tabKey] and modTabsByKey[tabKey].mod.OnRefresh then
			modTabsByKey[tabKey].mod:OnRefresh()
		end
	end

	local function RefreshTopTabs(skipRefresh)
		local prevBtn = nil
		for _, t in ipairs(topTabs) do
			local shown = (not t.mod) or ns:IsModuleEnabled(t.mod.id)
			t.btn:SetShown(shown)
			if shown then
				t.btn:ClearAllPoints()
				if not prevBtn then
					t.btn:SetPoint("TOPLEFT", 8, -6)
				else
					t.btn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
				end
				prevBtn = t.btn
			end
		end
		SelectTopTab(f.topTab or "details", skipRefresh)
	end

	for _, t in ipairs(topTabs) do
		local key = t.key
		t.btn:SetScript("OnClick", function() SelectTopTab(key) end)
	end
	f.SelectTopTab = SelectTopTab
	f.RefreshTopTabs = RefreshTopTabs
	RefreshTopTabs(true)

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
	self:ApplyUIScale()
	self:ApplyWindowLayout(false)
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
	outBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	outBtn:SetScript("OnClick", function(self, button)
		if ns:HandleItemClick(self.itemID, self.recipeID) then
			return
		end
		if button == "RightButton" and self.recipeID and ns.ToggleRecipeFavorite then
			ns:ToggleRecipeFavorite(self.recipeID)
		end
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
		rRow:SetHeight(18)
		rRow:SetPoint("TOPLEFT", 8, -64 - (i - 1) * 18)
		rRow:SetPoint("TOPRIGHT", -244, -64 - (i - 1) * 18)

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

	-- Блок экономики справа от реагентов (без внутренней рамки, отделён вертикальным разделителем)
	local econDivider = d:CreateTexture(nil, "ARTWORK")
	econDivider:SetWidth(1)
	econDivider:SetPoint("TOPRIGHT", d, "TOPRIGHT", -238, -66)
	econDivider:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -238, 56)
	econDivider:SetColorTexture(0.55, 0.44, 0.22, 0.45)

	local econBox = CreateFrame("Frame", nil, d)
	econBox:SetSize(226, 122)
	econBox:SetPoint("TOPRIGHT", -8, -66)

	-- Строки «подпись — сумма» в одну линию: себестоимость, выручка по каждому источнику (тот, по
	-- которому считается прибыль, ярко, остальные серым), чистая прибыль, цена за +1. Заполняет UpdateEconBox.
	d.econRows = {}
	for i = 1, 6 do
		local yOff = -8 - (i - 1) * 18
		local v = econBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		v:SetPoint("TOPRIGHT", -8, yOff)
		v:SetJustifyH("RIGHT")
		local l = econBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l:SetPoint("TOPLEFT", 8, yOff)
		l:SetPoint("RIGHT", v, "LEFT", -6, 0)
		l:SetJustifyH("LEFT")
		l:SetWordWrap(false)
		d.econRows[i] = { label = l, value = v }
	end

	-- Галочка авто-разворачивания промежуточных крафтов
	local cbSub = CreateFrame("CheckButton", nil, d, "UICheckButtonTemplate")
	cbSub:SetSize(20, 20)
	cbSub:SetPoint("BOTTOMLEFT", 8, 30)
	cbSub.text = cbSub:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cbSub.text:SetPoint("LEFT", cbSub, "RIGHT", 2, 0)
	cbSub.text:SetText(L["AUTO_SUBCRAFTS"])
	cbSub:SetScript("OnClick", function(self)
		ns.db.options.autoSubcrafts = self:GetChecked() and true or false
	end)
	d.cbAutoSub = cbSub

	local tomtomBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	tomtomBtn:SetSize(66, 18)
	tomtomBtn:SetPoint("TOPRIGHT", -8, -203)
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
	sourceBtn:SetHeight(18)
	sourceBtn:SetPoint("TOPLEFT", 8, -203)
	sourceBtn:SetPoint("TOPRIGHT", -8, -203)
	sourceBtn.text = sourceBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sourceBtn.text:SetPoint("LEFT", 2, 0)
	sourceBtn.text:SetPoint("RIGHT", -2, 0)
	sourceBtn.text:SetJustifyH("LEFT")
	sourceBtn.text:SetWordWrap(false)
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

	-- Блок распыления под реагентами (рецепт изучен, распыл включён и вещь распыляется): материалы с количеством,
	-- шансом и ценой на аукционе, ниже средняя выручка с одной вещи. Место по высоте задаёт UpdateDisenchantBlock.
	local DE_BLOCK_ROWS = 3
	local deBlock = CreateFrame("Frame", nil, d)
	deBlock:SetHeight(14 + DE_BLOCK_ROWS * 16 + 16)
	deBlock.header = deBlock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	deBlock.header:SetPoint("TOPLEFT", 2, 0)
	deBlock.header:SetJustifyH("LEFT")
	deBlock.rows = {}
	for i = 1, DE_BLOCK_ROWS do
		local r = CreateFrame("Button", nil, deBlock)
		r:SetHeight(16)
		r:SetPoint("TOPLEFT", 0, -14 - (i - 1) * 16)
		r:SetPoint("TOPRIGHT", 0, -14 - (i - 1) * 16)

		r.hl = r:CreateTexture(nil, "HIGHLIGHT")
		r.hl:SetAllPoints()
		r.hl:SetColorTexture(1, 0.82, 0.2, 0.14)

		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16)
		r.icon:SetPoint("LEFT", 3, 0)
		r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		r.priceText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.priceText:SetPoint("RIGHT", -4, 0)
		r.priceText:SetJustifyH("RIGHT")

		r.chanceText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.chanceText:SetPoint("RIGHT", -44, 0)
		r.chanceText:SetWidth(28)
		r.chanceText:SetJustifyH("RIGHT")

		r.countText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.countText:SetPoint("RIGHT", r.chanceText, "LEFT", -4, 0)
		r.countText:SetWidth(26)
		r.countText:SetJustifyH("RIGHT")
		r.countText:SetTextColor(0.6, 0.6, 0.6)

		r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		r.nameText:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r.nameText:SetPoint("RIGHT", r.countText, "LEFT", -4, 0)
		r.nameText:SetHeight(16)
		r.nameText:SetJustifyH("LEFT")
		r.nameText:SetWordWrap(false)
		if r.nameText.SetMaxLines then r.nameText:SetMaxLines(1) end

		r:SetScript("OnClick", function(self)
			if self.itemID then
				ns:HandleItemClick(self.itemID, nil)
			end
		end)
		r:SetScript("OnEnter", function(self)
			if self.itemID then
				ns:ShowItemTooltip(self, self.itemID)
			end
		end)
		r:SetScript("OnLeave", GameTooltip_Hide)
		deBlock.rows[i] = r
	end
	deBlock.totalLabel = deBlock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	deBlock.totalLabel:SetJustifyH("LEFT")
	deBlock.totalValue = deBlock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	deBlock.totalValue:SetJustifyH("RIGHT")
	deBlock:Hide()
	d.deBlock = deBlock

	-- Цель для наложения чар (CraftEnchant): автоподбор экипировки или перетаскивание предмета
	local etBar = CreateFrame("Frame", nil, d)
	etBar:SetHeight(32)
	local etSlot = CreateFrame("Button", nil, etBar, "BackdropTemplate")
	etSlot:SetSize(26, 26)
	etSlot:SetPoint("LEFT", 2, 0)
	etSlot:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	etSlot:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
	etSlot:SetBackdropBorderColor(0.55, 0.45, 0.20, 0.9)
	etSlot.icon = etSlot:CreateTexture(nil, "ARTWORK")
	etSlot.icon:SetPoint("TOPLEFT", 2, -2)
	etSlot.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	etSlot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	etSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local function HandleTargetDrop(_, btn)
		local rID = d.currentRecipeID
		if not rID then
			return
		end
		if btn == "RightButton" then
			if ns.ClearEnchantTarget then
				ns:ClearEnchantTarget(rID)
				ns:RefreshDetailsView()
			end
			return
		end
		if CursorHasItem and CursorHasItem() and ns.SetEnchantTargetFromCursor and ns:SetEnchantTargetFromCursor(rID) then
			ns:RefreshDetailsView()
		end
	end
	etSlot:SetScript("OnReceiveDrag", HandleTargetDrop)
	etSlot:SetScript("OnClick", HandleTargetDrop)
	etSlot:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		if self.itemLink and GameTooltip.SetHyperlink then
			pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink)
			GameTooltip:AddLine(" ")
		elseif self.itemID then
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:AddLine(" ")
		end
		GameTooltip:AddLine(L["ENCHANT_TARGET_TIP"], 0.85, 0.85, 0.85, true)
		GameTooltip:Show()
	end)
	etSlot:SetScript("OnLeave", GameTooltip_Hide)

	etBar.titleText = etBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	etBar.titleText:SetPoint("TOPLEFT", etSlot, "TOPRIGHT", 6, -1)
	etBar.titleText:SetPoint("RIGHT", -4, 0)
	etBar.titleText:SetJustifyH("LEFT")
	etBar.titleText:SetWordWrap(false)

	etBar.hintText = etBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	etBar.hintText:SetPoint("BOTTOMLEFT", etSlot, "BOTTOMRIGHT", 6, 1)
	etBar.hintText:SetPoint("RIGHT", -4, 0)
	etBar.hintText:SetJustifyH("LEFT")
	etBar.hintText:SetWordWrap(false)
	etBar.hintText:SetText("|cff888888" .. L["ENCHANT_TARGET_HINT"] .. "|r")

	etBar.slotBtn = etSlot
	etBar:Hide()
	d.enchantTargetBar = etBar

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
			local rem = ns.GetRemainingCraftableCount and ns:GetRemainingCraftableCount(rID, false) or nil
			if rem and rem > 0 then
				ns:QueueAddRecipe(rID, rem)
			else
				local direct, withCraft, withVendor = ns:GetRecipeCraftCounts(rID)
				local rawBest = math.max(direct or 0, withCraft or 0, withVendor or 0)
				if rem ~= nil and rawBest > 0 then
					ns:Print(L["QUEUE_ALL_RESERVED"])
				else
					ns:QueueAddRecipe(rID, math.max(1, rawBest))
				end
			end
		end
	end)

	local craftNowBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
	craftNowBtn:SetSize(115, 24)
	craftNowBtn:SetPoint("BOTTOMRIGHT", -8, 5)
	craftNowBtn:SetText(L["BTN_CRAFT_NOW"])
	craftNowBtn:RegisterForClicks("AnyUp")
	craftNowBtn:SetScript("OnEnter", function(self)
		if self.pendingSkillLine then
			ns:AttachSecureProfProxy(self, self.pendingSkillLine)
		end
	end)
	craftNowBtn:SetScript("OnClick", function(self)
		if not self.pendingSkillLine and self.skillLine and ns.GetActiveClientSkillLine and ns:GetActiveClientSkillLine() ~= self.skillLine then
			self.pendingSkillLine = self.skillLine
		end
		if self.pendingSkillLine then
			ns:SwitchToProfession(self.pendingSkillLine)
			if ns.AttachSecureProfProxy then
				ns:AttachSecureProfProxy(self, self.pendingSkillLine)
			end
			if ns.Print then
				ns:Print(string.format(L["CRAFT_OPEN_PROF_MSG"], ns:GetProfessionName(self.pendingSkillLine)))
			end
			return
		end
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
		if d.deBlock then
			d.deBlock:Hide()
		end
		if d.enchantTargetBar then
			d.enchantTargetBar:Hide()
		end
		for i = 1, 6 do d.reagentRows[i]:Hide() end
		self:UpdateEconBox(d, nil)
		d.craftNowBtn:SetText(L["BTN_CRAFT_NOW"])
		d.craftNowBtn.pendingSkillLine = nil
		d.craftNowBtn:SetEnabled(false)
		return
	end

	local prof = self.playerProfessions[sl]
	local curSkill = (prof and prof.rank) or 1
	local rec = self:GetRecipeRecord(recipeID)
	local name, icon, outItemID, _, _, hex = self:GetRecipeDisplay(recipeID)
	local metrics = self:GetRecipeSkillMetrics(recipeID, curSkill, self.db.options.deductVendorInRoute ~= false)
	local craftCost, _, profit, breakdown, outSource, alts = self:GetRecipeEconomy(recipeID)

	d.outBtn.recipeID = recipeID
	d.outBtn.itemID = outItemID
	d.outBtn.icon:SetTexture(icon)

	local favPrefix = (self.IsRecipeFavorite and self:IsRecipeFavorite(recipeID) and self.GetFavoriteIconMarkup)
		and self:GetFavoriteIconMarkup() or ""
	local qtySuffix = (rec and (rec.numMade or 1) > 1) and (" |cffffd100x" .. rec.numMade .. "|r") or ""
	d.recipeTitle:SetText(favPrefix .. (hex or "|cffffffff") .. name .. "|r" .. qtySuffix)

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
	else
		local src = self.GetRecipeSourceInfo and self:GetRecipeSourceInfo(recipeID)
		local reqSkill = (src and src.reqSkill) or metrics.reqSkill or 1
		local isBasic = self.BasicRecipes and self.BasicRecipes[recipeID]
		local hasKnownSkillReq = (reqSkill > 1) or isBasic or (src and (src.isTrainer or src.scrollItemID))
		if src and src.isTrainer then
			thParts[#thParts + 1] = "|cff809ec7" .. string.format(
				L["RECIPE_UNLEARNED_TAG"],
				ns.FormatMoney(src.trainerFee or 0),
				reqSkill
			) .. "|r"
		elseif src and src.scrollItemID then
			thParts[#thParts + 1] = "|cff809ec7" .. string.format(
				L["RECIPE_UNLEARNED_SCROLL"],
				reqSkill
			) .. "|r"
		elseif hasKnownSkillReq then
			thParts[#thParts + 1] = "|cff809ec7" .. string.format(
				L["RECIPE_UNLEARNED_UNKNOWN"],
				reqSkill
			) .. "|r"
		else
			thParts[#thParts + 1] = "|cff809ec7" .. L["RECIPE_UNLEARNED_SPECIAL"] .. "|r"
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
			elseif not (src and src.isTrainer) and not isBasic and not (src and src.scrollItemID) then
				srcParts[#srcParts + 1] = "|cff999999" .. L["RECIPE_SOURCE_SPECIAL"] .. "|r"
				detailText = L["RECIPE_SOURCE_SPECIAL"]
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
				d.sourceBtn:SetPoint("TOPLEFT", 8, -203)
				if canTomTom and d.tomtomBtn and d.tomtomBtn:IsShown() then
					d.sourceBtn:SetPoint("TOPRIGHT", d.tomtomBtn, "TOPLEFT", -6, 0)
				else
					d.sourceBtn:SetPoint("TOPRIGHT", -8, -203)
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
			if b.source == "ah" and self.db and self.db.options and self.db.options.checkAuctionStock and self.GetAuctionSeenQty then
				local ahQty, ahTotal = self:GetAuctionSeenQty(b.itemID, b.unitPrice)
				if ahQty then
					if ahTotal and ahTotal > ahQty then
						srcTag = srcTag .. ": " .. ahQty .. "/" .. ahTotal
					else
						srcTag = srcTag .. ": " .. ahQty
					end
				end
			end

			rRow.icon:SetTexture(iIcon)
			rRow.nameText:SetText((iHex or "|cffffffff") .. iName .. "|r |cff999999(" .. srcTag .. ")|r")
			rRow.countText:SetText(string.format("%s%d/%d|r%s  %s", countColor, have, b.quantity, bankTag, ns.FormatMoney(b.lineCost)))
		else
			rRow:Hide()
		end
	end
	-- Только для изученных: у неизученных на этом месте строка источника и кнопка TomTom (y = -203)
	self:UpdateDisenchantBlock(d, metrics.learned and outItemID or nil, math.min(#breakdown, 6))
	if d.enchantTargetBar then
		if metrics.learned and self.IsEnchantRecipe and self:IsEnchantRecipe(recipeID) then
			local nReag = math.min(#breakdown, 6)
			local topY = -64 - nReag * 18 - 6
			d.enchantTargetBar:ClearAllPoints()
			d.enchantTargetBar:SetPoint("TOPLEFT", d, "TOPLEFT", 8, topY)
			d.enchantTargetBar:SetPoint("TOPRIGHT", d, "TOPRIGHT", -244, topY)
			local _, meta = self:ResolveEnchantTarget(recipeID)
			if meta then
				d.enchantTargetBar.slotBtn.itemID = meta.itemID
				d.enchantTargetBar.slotBtn.itemLink = meta.itemLink
				d.enchantTargetBar.slotBtn.icon:SetTexture(meta.icon)
				d.enchantTargetBar.slotBtn:SetBackdropBorderColor(meta.isManual and 0.25 or 0.55, meta.isManual and 0.90 or 0.45, meta.isManual and 0.35 or 0.20, 0.95)
				local fmtKey = meta.isManual and "ENCHANT_TARGET_MANUAL" or "ENCHANT_TARGET_AUTO"
				d.enchantTargetBar.titleText:SetText(string.format(L[fmtKey], meta.itemLink or meta.name))
			else
				d.enchantTargetBar.slotBtn.itemID = nil
				d.enchantTargetBar.slotBtn.itemLink = nil
				d.enchantTargetBar.slotBtn.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
				d.enchantTargetBar.slotBtn:SetBackdropBorderColor(0.65, 0.30, 0.25, 0.9)
				d.enchantTargetBar.titleText:SetText("|cffff8866" .. L["ENCHANT_TARGET_NONE"] .. "|r")
			end
			d.enchantTargetBar:Show()
		else
			d.enchantTargetBar:Hide()
		end
	end

	self:UpdateEconBox(d, {
		craftCost = craftCost,
		outSource = outSource,
		alts = alts,
		profit = profit,
		costPerSkillUp = metrics.costPerSkillUp,
	})
	local canCraft = metrics.learned and (self:GetRecipeCraftCounts(recipeID) > 0)
	local recipeSL = (rec and rec.skillLine) or self.currentSkillLine
	local activeClientSL = self.GetActiveClientSkillLine and self:GetActiveClientSkillLine() or nil
	local needSwitch = canCraft and recipeSL and (activeClientSL ~= recipeSL)
	if needSwitch then
		d.craftNowBtn:SetText(L["BTN_OPEN_PROF"])
		d.craftNowBtn.pendingSkillLine = recipeSL
		d.craftNowBtn:SetEnabled(true)
	else
		d.craftNowBtn:SetText(L["BTN_CRAFT_NOW"])
		d.craftNowBtn.pendingSkillLine = nil
		d.craftNowBtn:SetEnabled(canCraft)
	end
	if self.SyncHoveredProfProxy then
		self:SyncHoveredProfProxy()
	end
end

-------------------------------------------------------------------------------
-- Блок экономики в деталях. e = nil — рецепт не выбран (прочерки)
-------------------------------------------------------------------------------
local OUTPUT_LABEL_KEYS = { vendor = "OUTPUT_VALUE_VENDOR", ah = "OUTPUT_VALUE_AH", disenchant = "OUTPUT_VALUE_DE" }
local DASH = "|cff888888-|r"

function ns:UpdateEconBox(d, e)
	local rows = d.econRows
	if not rows then
		return
	end
	local lines = {}
	local function Add(label, text, dim)
		lines[#lines + 1] = { label, text, dim }
	end
	if e then
		Add(L["CRAFT_COST"], ns.FormatMoney(e.craftCost))
		local anyOutput = false
		for _, src in ipairs(ns.OUTPUT_SOURCES) do
			local v = e.alts and e.alts[src]
			if v then
				anyOutput = true
				Add(L[OUTPUT_LABEL_KEYS[src]], ns.FormatMoney(v), src ~= e.outSource)
			end
		end
		if not anyOutput then
			Add(L["OUTPUT_VALUE"], DASH)
		end
		Add(L["NET_PROFIT"], ns.FormatMoney(e.profit, true))
		Add(L["COST_PER_SKILLUP"], ns.FormatSkillUpCost(e.costPerSkillUp))
	else
		Add(L["CRAFT_COST"], DASH)
		Add(L["OUTPUT_VALUE"], DASH)
		Add(L["NET_PROFIT"], DASH)
		Add(L["COST_PER_SKILLUP"], DASH)
	end
	for i, row in ipairs(rows) do
		local ln = lines[i]
		if ln then
			row.label:SetText(ln[1])
			row.value:SetText(ln[2])
			if ln[3] then
				row.label:SetTextColor(0.5, 0.5, 0.5)
				row.value:SetTextColor(0.5, 0.5, 0.5)
			else
				row.label:SetTextColor(1, 1, 1)
				row.value:SetTextColor(1, 0.82, 0)
			end
			row.label:Show()
			row.value:Show()
		else
			row.label:Hide()
			row.value:Hide()
		end
	end
end

-------------------------------------------------------------------------------
-- Блок распыления в деталях: под последним реагентом, шириной как строки реагентов
-------------------------------------------------------------------------------
local function FormatDisenchantChance(chance)
	local pct = chance * 100
	if math.abs(pct - math.floor(pct + 0.5)) < 0.05 then
		return string.format("%d%%", math.floor(pct + 0.5))
	end
	return string.format("%.1f%%", pct)
end

function ns:UpdateDisenchantBlock(d, outItemID, numReagents)
	local b = d.deBlock
	if not b then
		return
	end
	local deNet, yields, reqEnch
	if outItemID and self.GetItemDisenchantInfo then
		deNet, yields, reqEnch = self:GetItemDisenchantInfo(outItemID)
	end
	if not (yields and #yields > 0) then
		b:Hide()
		return
	end

	local top = -64 - (numReagents or 0) * 18 - 4
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", d, "TOPLEFT", 8, top)
	b:SetPoint("TOPRIGHT", d, "TOPRIGHT", -244, top)
	b.header:SetText(string.format(L["DE_BLOCK_HEADER"], reqEnch or 1))

	local shown = 0
	for i, r in ipairs(b.rows) do
		local y = yields[i]
		if y then
			shown = i
			local yName, yIcon, _, _, _, yHex = self:GetItemDisplay(y.itemID)
			local price = self:GetAuctionPrice(y.itemID)
			r.itemID = y.itemID
			r.icon:SetTexture(yIcon)
			r.nameText:SetText((yHex or "|cffffffff") .. yName .. "|r")
			r.countText:SetText(ns.FormatDisenchantCount(y))
			r.chanceText:SetText(FormatDisenchantChance(y.chance))
			r.priceText:SetText((price and price > 0) and ns.FormatMoney(price) or "|cff888888-|r")
			r:Show()
		else
			r.itemID = nil
			r:Hide()
		end
	end

	-- Колонка цены по самой широкой цене в блоке («1с 25м» шире «90м»): шанс и количество стоят
	-- левее неё, ровно во всех строках, и не налезают на цену
	local priceW = 24
	for i = 1, shown do
		priceW = math.max(priceW, b.rows[i].priceText:GetStringWidth() or 0)
	end
	for i = 1, shown do
		local r = b.rows[i]
		r.chanceText:ClearAllPoints()
		r.chanceText:SetPoint("RIGHT", r, "RIGHT", -(4 + math.ceil(priceW) + 8), 0)
	end

	local totalTop = -14 - shown * 16 - 2
	b:SetHeight(14 + shown * 16 + 16)
	b.totalLabel:ClearAllPoints()
	b.totalLabel:SetPoint("TOPLEFT", b, "TOPLEFT", 25, totalTop)
	b.totalLabel:SetText(L["DE_AVG_LABEL"])
	b.totalValue:ClearAllPoints()
	b.totalValue:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, totalTop)
	b.totalValue:SetText(deNet and ns.FormatMoney(deNet) or "|cff888888-|r")
	b:Show()
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

	if f.recipeScrollBar then
		local maxOff = math.max(0, #list - RECIPE_VISIBLE_ROWS)
		f._updatingRecipeScroll = true
		f.recipeScrollBar:SetMinMaxValues(0, maxOff)
		f.recipeScrollBar:SetValue(math.min(f.recipeOffset or 0, maxOff))
		f.recipeScrollBar:SetShown(maxOff > 0)
		f._updatingRecipeScroll = false
	end

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
				local countsStr = FormatCraftCounts(entry.direct, entry.withCraft, entry.withVendor, entry.withBank, entry.remaining)
				local trainerTag = ""
				if not entry.learned then
					local req = entry.metrics.reqSkill or 1
					local isKnownReq = (req > 1) or entry.metrics.isTrainer or entry.metrics.scrollItemID or (self.BasicRecipes and self.BasicRecipes[entry.recipeID])
					trainerTag = isKnownReq and string.format(" |cff809ec7[%d]|r", req) or " |cff809ec7[?]|r"
				end
				local favPrefix = (entry.favorite and self.GetFavoriteIconMarkup) and self:GetFavoriteIconMarkup() or ""
				row.nameText:SetText(favPrefix .. dc.hex .. entry.name .. "|r" .. trainerTag .. countsStr)

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
					local costStr = entry.metrics.costPerSkillUp and ns.FormatSkillUpCost(entry.metrics.costPerSkillUp) or ""
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
	elseif f.topTab ~= "details" and self.modules and self.modules.byId[f.topTab] then
		local mod = self.modules.byId[f.topTab]
		if self:IsModuleEnabled(f.topTab) and mod.OnRefresh then
			mod:OnRefresh()
		end
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
			btn.skillLine = nil
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
	self:ApplyUIScale()
	self:ApplyWindowLayout(false)
	local opts = (self.db and self.db.options) or {}
	if opts.windowMinimized == true then
		self:RefreshQueueAndShoppingView()
		if self.SyncHoveredProfProxy then
			self:SyncHoveredProfProxy()
		end
		return
	end
	if f.RefreshTopTabs then
		f.RefreshTopTabs(true)
	end

	self:RefreshRecipeList()
	self:RefreshQueueAndShoppingView()
	if self.SyncHoveredProfProxy then
		self:SyncHoveredProfProxy()
	end
end

function ns:RefreshRankBarOnly()
	local f = self.mainFrame
	if not (f and f:IsShown() and f.rankBar) then
		return
	end
	local curProf = self.currentSkillLine and self.playerProfessions[self.currentSkillLine]
	local rank = (curProf and curProf.rank) or 1
	local maxRank = (curProf and curProf.maxRank) or 75
	local profName = self:GetProfessionName(self.currentSkillLine or 171)
	f.rankBar:SetMinMaxValues(0, math.max(1, maxRank))
	f.rankBar:SetValue(rank)
	f.rankBar.text:SetText(string.format("%s  %d / %d", profName, rank, maxRank))
end

local pendingVisibleRefresh = false
function ns:RefreshVisibleUI()
	if not (self.mainFrame and self.mainFrame:IsShown()) then
		return
	end
	if pendingVisibleRefresh then
		return
	end
	if C_Timer and C_Timer.After then
		pendingVisibleRefresh = true
		C_Timer.After(0.05, function()
			pendingVisibleRefresh = false
			if ns.mainFrame and ns.mainFrame:IsShown() then
				ns:RefreshMainWindow()
			end
		end)
	else
		self:RefreshMainWindow()
	end
end

function ns:OnCombatEnded()
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
	if self.DetachSecureProfProxy then
		self:DetachSecureProfProxy()
	end
	if self.HideSniperSettingsFrame then
		self:HideSniperSettingsFrame("tab")
	end
	if self.settingsFrame and self.settingsFrame:IsShown() then
		self.settingsFrame:Hide()
	end
	if self.mainFrame and self.mainFrame:IsShown() then
		self.mainFrame:Hide()
	end
end

function ns:ToggleSettingsFrame()
	if not self.settingsFrame then
		local opts = {
			{ key = "includeDisenchant", label = L["OPT_INCLUDE_DE"],    defaultTrue = true,  invalidatePrices = true },
			{ key = "tooltipExtraInfo",  label = L["OPT_TOOLTIP_EXTRA"], defaultTrue = false, invalidatePrices = false },
			{ key = "groupByCategory",   label = L["GROUP_BY_CATEGORY"], defaultTrue = false, invalidatePrices = false },
			{ key = "checkAuctionStock", label = L["OPT_AH_STOCK"],      defaultTrue = false, invalidatePrices = false },
		}
		for _, mSpec in ipairs((self.GetModuleSettingsSpecs and self:GetModuleSettingsSpecs()) or {}) do
			opts[#opts + 1] = mSpec
		end

		local sf = CreateFrame("Frame", "TradeFlowSettingsFrame", UIParent, "BackdropTemplate")
		sf:SetSize(310, 158 + #opts * 28)
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
				local checked = self:GetChecked() and true or false
				if o.moduleId and ns.SetModuleEnabled then
					ns:SetModuleEnabled(o.moduleId, checked)
				else
					ns.db.options[o.key] = checked
					if o.invalidatePrices and ns.InvalidatePrices then
						ns:InvalidatePrices()
					elseif ns.RefreshMainWindow then
						ns:RefreshMainWindow()
					end
				end
			end)
			sf.checks[i] = { cb = cb, opt = o }
		end

		local scaleTopY = -36 - #opts * 28
		local scaleLabel = sf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		scaleLabel:SetPoint("TOPLEFT", 14, scaleTopY)
		sf.scaleLabel = scaleLabel

		local scaleResetBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
		scaleResetBtn:SetSize(46, 18)
		scaleResetBtn:SetPoint("TOPRIGHT", -12, scaleTopY + 2)
		scaleResetBtn:SetText(L["OPT_UI_SCALE_RESET"])

		local scaleSlider = CreateFrame("Slider", nil, sf, "BackdropTemplate")
		scaleSlider:SetPoint("TOPLEFT", 12, scaleTopY - 18)
		scaleSlider:SetSize(286, 14)
		scaleSlider:SetOrientation("HORIZONTAL")
		scaleSlider:SetMinMaxValues(60, 140)
		scaleSlider:SetValueStep(5)
		if scaleSlider.SetObeyStepOnDrag then
			scaleSlider:SetObeyStepOnDrag(true)
		end
		scaleSlider:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 8, edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		scaleSlider:SetBackdropColor(0.03, 0.03, 0.03, 0.9)
		scaleSlider:SetBackdropBorderColor(0.55, 0.44, 0.22, 0.9)
		local sThumb = scaleSlider:CreateTexture(nil, "ARTWORK")
		sThumb:SetColorTexture(0.90, 0.72, 0.22, 0.95)
		sThumb:SetSize(14, 10)
		scaleSlider:SetThumbTexture(sThumb)
		scaleSlider:SetScript("OnValueChanged", function(_, value)
			local pct = math.floor(((value or 100) + 2.5) / 5) * 5
			pct = math.max(60, math.min(140, pct))
			scaleLabel:SetText(string.format(L["OPT_UI_SCALE_FMT"], pct))
			if sf._updatingScale then
				return
			end
			local l, t = sf:GetLeft(), sf:GetTop()
			if l and t then
				sf:ClearAllPoints()
				sf:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
			end
			if ns.db and ns.db.options then
				ns.db.options.uiScale = pct / 100
			end
			ns:ApplyUIScale()
		end)
		scaleResetBtn:SetScript("OnClick", function()
			scaleSlider:SetValue(100)
		end)
		sf.scaleSlider = scaleSlider

		local clearProfitBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
		clearProfitBtn:SetSize(286, 22)
		clearProfitBtn:SetPoint("BOTTOMLEFT", 12, 36)
		clearProfitBtn:SetText(L["OPT_CLEAR_PROFIT_LOG_BTN"])
		clearProfitBtn:SetScript("OnClick", function()
			sf:Hide()
			if ns.ClearProfitLog then
				ns:ClearProfitLog("all")
			end
		end)

		local logBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
		logBtn:SetSize(286, 22)
		logBtn:SetPoint("BOTTOMLEFT", 12, 10)
		logBtn:SetText(L["OPT_DEBUG_LOG_BTN"])
		logBtn:SetScript("OnClick", function()
			sf:Hide()
			if ns.ShowDebugLogWindow then
				ns:ShowDebugLogWindow()
			end
		end)

		if not self.settingsSpecialRegistered then
			self.settingsSpecialRegistered = true
			tinsert(UISpecialFrames, "TradeFlowSettingsFrame")
		end
		self.settingsFrame = sf
	end

	if self.mainFrame and self.mainFrame.sortMenu then
		self.mainFrame.sortMenu:Hide()
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
	if sf.scaleSlider then
		local pct = math.floor(self:GetUIScale() * 100 + 0.5)
		sf._updatingScale = true
		sf.scaleSlider:SetValue(pct)
		if sf.scaleLabel then
			sf.scaleLabel:SetText(string.format(L["OPT_UI_SCALE_FMT"], pct))
		end
		sf._updatingScale = false
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
	if self.settingsFrame then
		self.settingsFrame:Hide()
		self.settingsFrame = nil
	end
	if self.ResetDebugLogWindow then
		self:ResetDebugLogWindow()
	end
	if self.mainFrame then
		self.isRebuildingFrame = true
		self.mainFrame:Hide()
		self.isRebuildingFrame = false
		self.mainFrame = nil
		self.detailsView = nil
		self.routeView = nil
		self.queueView = nil
		if self.NotifyAllModules then
			self:NotifyAllModules("OnFrameDestroyed")
		end
	end
	if self.NotifyModules then
		self:NotifyModules("OnLanguageChanged")
	end
	if wasShown then
		local f = self:CreateMainFrame()
		if f.SelectTopTab then
			f.SelectTopTab(topTab, true)
		end
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

