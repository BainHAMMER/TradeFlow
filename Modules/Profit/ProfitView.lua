local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Модуль «Заработок»: UI-вкладка профитных рецептов по всем профессиям
-------------------------------------------------------------------------------
local ROW_H = 27
local VISIBLE_ROWS = 8
local CHANNELS = { "all", "safe", "ah" }
local SORTS = { "profit", "margin", "craftable" }

local ProfitMod = {
	id = "profit",
	optionKey = "modProfitEnabled",
	settingsLabelKey = "OPT_MOD_PROFIT",
	tabTitleKey = "TAB_PROFIT",
	tabWidth = 148,
	defaultEnabled = true,
	view = nil,
}

local function Utf8Prefix(str, maxChars)
	local out = {}
	local n = 0
	for ch in (str or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		if n > maxChars then
			break
		end
		out[n] = ch
	end
	return table.concat(out)
end

local function GetShortProfName(skillLine)
	local name = ns:GetProfessionName(skillLine) or ""
	return Utf8Prefix(name, 10)
end

local function CycleValue(list, cur)
	for i, v in ipairs(list) do
		if v == cur then
			return list[(i % #list) + 1]
		end
	end
	return list[1]
end

local function GetAvailableProfFilters(includeAlts)
	local seen = {}
	local list = { 0 }
	for sl in pairs(ns.playerProfessions or {}) do
		if not seen[sl] then
			seen[sl] = true
			list[#list + 1] = sl
		end
	end
	if includeAlts and ns.realmDB and ns.realmDB.chars then
		for _, cData in pairs(ns.realmDB.chars) do
			if cData and cData.professions then
				for sl in pairs(cData.professions) do
					if not seen[sl] then
						seen[sl] = true
						list[#list + 1] = sl
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if a == 0 then return true end
		if b == 0 then return false end
		return a < b
	end)
	return list
end

local function FormatChannelTag(src, ageDays)
	local key = (src == "vendor" and "PROFIT_SRC_VENDOR")
		or (src == "disenchant" and "PROFIT_SRC_DE")
		or "PROFIT_SRC_AH"
	local label = L[key] or src or ""
	if src == "ah" and ageDays and ageDays > 0 then
		return string.format("%s (%d%s)", label, ageDays, L["PROFIT_DAYS_SHORT"])
	end
	return label
end

function ProfitMod:GetFilters()
	local opts = (ns.db and ns.db.options) or {}
	return {
		channel = opts.profitChannel or "all",
		sortBy = opts.profitSort or "profit",
		profFilter = opts.profitProfFilter or 0,
		onlyOwned = opts.profitOnlyOwned == true,
		includeAlts = opts.profitIncludeAlts == true,
		freshOnly = opts.profitFreshOnly ~= false,
	}
end

function ProfitMod:CreateView(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints()
	f.offset = 0
	f.entries = {}
	f.subMode = "profit"
	f:Hide()

	-- Подвкладки модуля: «Профит» | «Снайпер (N)»
	local subBar = CreateFrame("Frame", nil, f)
	subBar:SetPoint("TOPLEFT", 8, -2)
	subBar:SetPoint("TOPRIGHT", -8, -2)
	subBar:SetHeight(24)

	local subProfitBtn = ns.CreateTabButton(subBar, 148, 22, L["PROFIT_SUBTAB_SCAN"])
	subProfitBtn:SetPoint("TOPLEFT", 0, 0)

	local subSniperBtn = ns.CreateTabButton(subBar, 132, 22, string.format(L["PROFIT_SUBTAB_SNIPER"], 0))
	subSniperBtn:SetPoint("LEFT", subProfitBtn, "RIGHT", 6, 0)

	local function SelectSubMode(mode)
		f.subMode = mode
		f.offset = 0
		ns.SetTabButtonActive(subProfitBtn, mode == "profit")
		ns.SetTabButtonActive(subSniperBtn, mode == "sniper")
		ProfitMod:OnRefresh()
	end
	subProfitBtn:SetScript("OnClick", function() SelectSubMode("profit") end)
	subSniperBtn:SetScript("OnClick", function() SelectSubMode("sniper") end)
	f.subProfitBtn = subProfitBtn
	f.subSniperBtn = subSniperBtn
	ns.SetTabButtonActive(subProfitBtn, true)
	ns.SetTabButtonActive(subSniperBtn, false)

	local top = CreateFrame("Frame", nil, f)
	top:SetPoint("TOPLEFT", 8, -28)
	top:SetPoint("TOPRIGHT", -8, -28)
	top:SetHeight(48)
	f.profitTop = top

	local channelBtn = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
	channelBtn:SetSize(160, 20)
	channelBtn:SetPoint("TOPLEFT", 0, -2)
	channelBtn:SetScript("OnClick", function()
		if ns.db and ns.db.options then
			ns.db.options.profitChannel = CycleValue(CHANNELS, ns.db.options.profitChannel or "all")
		end
		f.offset = 0
		ProfitMod:OnRefresh()
	end)
	f.channelBtn = channelBtn

	local sortBtn = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
	sortBtn:SetSize(116, 20)
	sortBtn:SetPoint("LEFT", channelBtn, "RIGHT", 4, 0)
	sortBtn:SetScript("OnClick", function()
		if ns.db and ns.db.options then
			ns.db.options.profitSort = CycleValue(SORTS, ns.db.options.profitSort or "profit")
		end
		f.offset = 0
		ProfitMod:OnRefresh()
	end)
	f.sortBtn = sortBtn

	local function MakeCheck(label, optKey, xAnchor, relativeTo, widthHit)
		local cb = CreateFrame("CheckButton", nil, top, "UICheckButtonTemplate")
		cb:SetSize(20, 20)
		cb:SetPoint("LEFT", relativeTo, "RIGHT", xAnchor, 0)
		cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cb.text:SetPoint("LEFT", cb, "RIGHT", 1, 0)
		cb.text:SetText(label)
		cb:SetHitRectInsets(0, -widthHit, 0, 0)
		cb:SetScript("OnClick", function(self)
			if ns.db and ns.db.options then
				ns.db.options[optKey] = self:GetChecked() and true or false
			end
			f.offset = 0
			ProfitMod:OnRefresh()
		end)
		return cb
	end

	f.cbOwned = MakeCheck(L["PROFIT_ONLY_OWNED"], "profitOnlyOwned", 6, sortBtn, 78)
	f.cbAlts = MakeCheck(L["PROFIT_INCLUDE_ALTS"], "profitIncludeAlts", 80, f.cbOwned, 64)

	local profBtn = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
	profBtn:SetSize(160, 20)
	profBtn:SetPoint("TOPLEFT", 0, -25)
	profBtn:SetScript("OnClick", function()
		if ns.db and ns.db.options then
			local filters = ProfitMod:GetFilters()
			local list = GetAvailableProfFilters(filters.includeAlts)
			ns.db.options.profitProfFilter = CycleValue(list, filters.profFilter)
		end
		f.offset = 0
		ProfitMod:OnRefresh()
	end)
	f.profBtn = profBtn

	local freshBtn = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
	freshBtn:SetSize(116, 20)
	freshBtn:SetPoint("LEFT", profBtn, "RIGHT", 4, 0)
	freshBtn:SetScript("OnClick", function()
		if ns.db and ns.db.options then
			local cur = ns.db.options.profitFreshOnly ~= false
			ns.db.options.profitFreshOnly = not cur
		end
		f.offset = 0
		ProfitMod:OnRefresh()
	end)
	f.freshBtn = freshBtn

	local countText = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	countText:SetPoint("TOPRIGHT", -2, -28)
	countText:SetJustifyH("RIGHT")
	f.countText = countText

	local sniperTop = CreateFrame("Frame", nil, f)
	sniperTop:SetPoint("TOPLEFT", 8, -28)
	sniperTop:SetPoint("TOPRIGHT", -8, -28)
	sniperTop:SetHeight(24)
	sniperTop:Hide()
	f.sniperTop = sniperTop

	local importShopBtn = CreateFrame("Button", nil, sniperTop, "UIPanelButtonTemplate")
	importShopBtn:SetSize(156, 20)
	importShopBtn:SetPoint("LEFT", 0, 0)
	importShopBtn:SetText(L["SNIPE_IMPORT_SHOP"])
	importShopBtn:SetScript("OnClick", function()
		if ns.ImportShoppingToSnipe then
			ns:ImportShoppingToSnipe(0.80)
		end
	end)

	local scanSnipeBtn = CreateFrame("Button", nil, sniperTop, "UIPanelButtonTemplate")
	scanSnipeBtn:SetSize(104, 20)
	scanSnipeBtn:SetPoint("LEFT", importShopBtn, "RIGHT", 4, 0)
	scanSnipeBtn:SetText(L["SNIPE_SCAN_BTN"])
	scanSnipeBtn:SetScript("OnClick", function()
		if ns.SearchSnipeTargetsOnAH then
			ns:SearchSnipeTargetsOnAH()
		end
	end)

	local clearSnipeBtn = CreateFrame("Button", nil, sniperTop, "UIPanelButtonTemplate")
	clearSnipeBtn:SetSize(82, 20)
	clearSnipeBtn:SetPoint("LEFT", scanSnipeBtn, "RIGHT", 4, 0)
	clearSnipeBtn:SetText(L["QUEUE_CLEAR"])
	clearSnipeBtn:SetScript("OnClick", function()
		if ns.ClearSnipeTargets then
			ns:ClearSnipeTargets()
		end
	end)

	local listBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
	listBox:SetPoint("TOPLEFT", 8, -78)
	listBox:SetPoint("BOTTOMRIGHT", -8, 6)
	f.listBox = listBox
	listBox:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	listBox:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
	listBox:SetBackdropBorderColor(0.38, 0.30, 0.16, 0.75)
	listBox:EnableMouseWheel(true)
	listBox:SetScript("OnMouseWheel", function(_, delta)
		local maxOff = math.max(0, #f.entries - VISIBLE_ROWS)
		f.offset = math.max(0, math.min(maxOff, f.offset - delta * 2))
		ProfitMod:RenderRows()
	end)

	local emptyLabel = listBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyLabel:SetPoint("CENTER", 0, 0)
	emptyLabel:SetWidth(420)
	emptyLabel:SetText(L["PROFIT_EMPTY"])
	f.emptyLabel = emptyLabel

	f.rows = {}
	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, listBox)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
		row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * ROW_H)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		row.hl = row:CreateTexture(nil, "HIGHLIGHT")
		row.hl:SetAllPoints()
		row.hl:SetColorTexture(1, 0.85, 0.3, 0.10)

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(22, 22)
		row.icon:SetPoint("LEFT", 4, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		row.snipeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.snipeBtn:SetSize(48, 20)
		row.snipeBtn:SetPoint("RIGHT", -2, 0)
		row.snipeBtn:SetText(L["PROFIT_BTN_SNIPE"])
		row.snipeBtn:SetScript("OnClick", function()
			local e = row.entryData
			if e and e.recipeID and ns.AddRecipeReagentsToSnipe then
				local cnt = ns:AddRecipeReagentsToSnipe(e.recipeID, 0.80)
				if cnt > 0 then
					ns:Print(string.format(L["SNIPE_ADDED_MSG"], cnt))
				end
			end
		end)

		row.queueBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.queueBtn:SetSize(60, 20)
		row.queueBtn:SetPoint("RIGHT", row.snipeBtn, "LEFT", -3, 0)
		row.queueBtn:SetText(L["PLANNER_BTN_QUEUE_STEP"])
		row.queueBtn:SetScript("OnClick", function()
			local e = row.entryData
			if e and not e.isAlt and ns.QueueAddRecipe then
				ns:QueueAddRecipe(e.recipeID, 1)
			end
		end)

		row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.delBtn:SetSize(20, 20)
		row.delBtn:SetPoint("RIGHT", -2, 0)
		row.delBtn:SetText("X")
		row.delBtn:SetScript("OnClick", function()
			local e = row.entryData
			if e and e.itemID and ns.RemoveSnipeTarget then
				ns:RemoveSnipeTarget(e.itemID)
			end
		end)

		row.findBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.findBtn:SetSize(44, 20)
		row.findBtn:SetPoint("RIGHT", row.delBtn, "LEFT", -2, 0)
		row.findBtn:SetText(L["SNIPE_FIND_SHORT"])
		row.findBtn:SetScript("OnClick", function()
			local e = row.entryData
			if e and e.itemID and ns.SearchSnipeTargetsOnAH then
				ns:SearchSnipeTargetsOnAH(e.itemID)
			end
		end)

		row.plusBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.plusBtn:SetSize(32, 20)
		row.plusBtn:SetPoint("RIGHT", row.findBtn, "LEFT", -2, 0)
		row.plusBtn:SetText("+10%")
		row.plusBtn:SetScript("OnClick", function()
			local e = row.entryData
			if e and e.itemID and ns.AdjustSnipeTarget then
				ns:AdjustSnipeTarget(e.itemID, 1.10)
			end
		end)

		row.minusBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.minusBtn:SetSize(32, 20)
		row.minusBtn:SetPoint("RIGHT", row.plusBtn, "LEFT", -2, 0)
		row.minusBtn:SetText("-10%")
		row.minusBtn:SetScript("OnClick", function()
			local e = row.entryData
			if e and e.itemID and ns.AdjustSnipeTarget then
				ns:AdjustSnipeTarget(e.itemID, 0.90)
			end
		end)

		row.profitText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.profitText:SetPoint("RIGHT", row.queueBtn, "LEFT", -8, 6)
		row.profitText:SetJustifyH("RIGHT")

		row.marginText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.marginText:SetPoint("RIGHT", row.queueBtn, "LEFT", -8, -6)
		row.marginText:SetJustifyH("RIGHT")

		row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
		row.title:SetPoint("RIGHT", row.profitText, "LEFT", -8, 0)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)

		row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
		row.sub:SetPoint("RIGHT", row.marginText, "LEFT", -8, 0)
		row.sub:SetJustifyH("LEFT")
		row.sub:SetWordWrap(false)

		row:SetScript("OnClick", function(self, button)
			local e = self.entryData
			if not e then
				return
			end
			if f.subMode == "sniper" then
				ns:HandleItemClick(e.itemID)
				return
			end
			if ns:HandleItemClick(e.outItemID, e.recipeID) then
				return
			end
			if button == "RightButton" then
				if not e.isAlt and ns.QueueAddRecipe then
					ns:QueueAddRecipe(e.recipeID, 1)
				end
				return
			end
			if not e.isAlt and e.skillLine and ns.playerProfessions[e.skillLine] then
				if ns.mainFrame and ns.mainFrame.SelectTopTab then
					ns.mainFrame.SelectTopTab("details")
				end
				if e.skillLine ~= ns.currentSkillLine and ns.SwitchToProfession then
					ns.selectedRecipeBySkill[e.skillLine] = e.recipeID
					ns:SwitchToProfession(e.skillLine)
				elseif ns.SelectRecipeID then
					ns:SelectRecipeID(e.recipeID)
				end
			end
		end)

		row:SetScript("OnEnter", function(self)
			local e = self.entryData
			if not e then
				return
			end
			if f.subMode == "sniper" and e.itemID and ns.ShowItemTooltip then
				ns:ShowItemTooltip(self, e.itemID)
				return
			end
			if e.recipeID and ns.ShowRecipeTooltip then
				ns:ShowRecipeTooltip(self, e.recipeID)
				if e.isAlt and e.ownerName and GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
					GameTooltip:AddLine(" ")
					GameTooltip:AddLine(string.format(L["PROFIT_ALT_TOOLTIP"], e.ownerName), 0.4, 0.8, 1)
					GameTooltip:Show()
				end
			end
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)

		f.rows[i] = row
	end

	self.view = f
	return f
end

function ProfitMod:RenderRows()
	local f = self.view
	if not f then
		return
	end
	local list = f.entries or {}
	local isSniper = (f.subMode == "sniper")
	f.emptyLabel:SetText(isSniper and L["SNIPE_EMPTY"] or L["PROFIT_EMPTY"])
	f.emptyLabel:SetShown(#list == 0)

	for i = 1, VISIBLE_ROWS do
		local row = f.rows[i]
		local e = list[i + f.offset]
		row.entryData = e
		if e then
			row:Show()
			if isSniper then
				local name, icon, _, _, _, hex = ns:GetItemDisplay(e.itemID)
				row.icon:SetTexture(icon)
				local hit = ns.snipeHits and ns.snipeHits[e.itemID]
				local statusTag = hit
					and string.format(" |cff40ff40[%dx @ %s]|r", hit.qty or 0, ns.FormatMoney(hit.bestPrice))
					or ""
				row.title:SetText(string.format("%s%s|r%s", hex or "|cffffffff", name, statusTag))
				local curP = ns:GetAuctionPrice(e.itemID)
				local curStr = curP and ns.FormatMoney(curP) or "|cff888888-|r"
				row.sub:SetText(string.format(L["SNIPE_ROW_SUB"], ns.FormatMoney(e.maxPrice), curStr))
				row.profitText:SetText("")
				row.marginText:SetText("")
				row.snipeBtn:Hide()
				row.queueBtn:Hide()
				row.minusBtn:Show()
				row.plusBtn:Show()
				row.findBtn:Show()
				row.delBtn:Show()
				row.title:ClearAllPoints()
				row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
				row.title:SetPoint("RIGHT", row.minusBtn, "LEFT", -6, 0)
				row.sub:ClearAllPoints()
				row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
				row.sub:SetPoint("RIGHT", row.minusBtn, "LEFT", -6, 0)
			else
				row.icon:SetTexture(e.icon)
				local profTag = string.format("|cff66ccff[%s]|r", GetShortProfName(e.skillLine))
				local altTag = (e.isAlt and e.ownerName) and string.format(" |cffffa040[%s]|r", e.ownerName) or ""
				local cntTag = (e.craftNow and e.craftNow > 0) and string.format(" |cff40ff40[%d]|r", e.craftNow) or ""
				row.title:SetText(string.format("%s%s|r %s%s%s", e.qualityHex or "|cffffffff", e.name, profTag, cntTag, altTag))

				local srcText = FormatChannelTag(e.source, e.ageDays)
				row.sub:SetText(string.format(L["PROFIT_SUB_FMT"], srcText, ns.FormatMoney(e.craftCost), ns.FormatMoney(e.outputValue)))
				row.profitText:SetText("|cff40ff40+" .. ns.FormatMoney(e.profit) .. "|r")
				row.marginText:SetText(string.format("|cffaaaaaa+%d%%|r", e.margin or 0))
				row.snipeBtn:Show()
				row.queueBtn:SetShown(not e.isAlt)
				row.minusBtn:Hide()
				row.plusBtn:Hide()
				row.findBtn:Hide()
				row.delBtn:Hide()
				row.title:ClearAllPoints()
				row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
				row.title:SetPoint("RIGHT", row.profitText, "LEFT", -8, 0)
				row.sub:ClearAllPoints()
				row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
				row.sub:SetPoint("RIGHT", row.marginText, "LEFT", -8, 0)
			end
		else
			row:Hide()
		end
	end
end

function ProfitMod:OnRefresh()
	local f = self.view
	if not f or not f:IsVisible() then
		return
	end
	local targets = ns.GetSnipeTargetList and ns:GetSnipeTargetList() or {}
	f.subSniperBtn:SetText(string.format(L["PROFIT_SUBTAB_SNIPER"], #targets))

	local isSniper = (f.subMode == "sniper")
	f.profitTop:SetShown(not isSniper)
	f.sniperTop:SetShown(isSniper)
	f.listBox:ClearAllPoints()
	f.listBox:SetPoint("TOPLEFT", 8, isSniper and -56 or -78)
	f.listBox:SetPoint("BOTTOMRIGHT", -8, 6)

	if isSniper then
		for _, t in ipairs(targets) do
			if ns.EvaluateSnipeItem then
				ns:EvaluateSnipeItem(t.itemID, true)
			end
		end
		f.entries = targets
		local maxOff = math.max(0, #f.entries - VISIBLE_ROWS)
		if f.offset > maxOff then
			f.offset = maxOff
		end
		self:RenderRows()
		return
	end

	local filters = self:GetFilters()
	local profs = GetAvailableProfFilters(filters.includeAlts)
	local validProf = false
	for _, sl in ipairs(profs) do
		if sl == filters.profFilter then
			validProf = true
			break
		end
	end
	if not validProf then
		filters.profFilter = 0
		if ns.db and ns.db.options then
			ns.db.options.profitProfFilter = 0
		end
	end

	local chKey = (filters.channel == "safe" and "PROFIT_CH_SAFE")
		or (filters.channel == "ah" and "PROFIT_CH_AH")
		or "PROFIT_CH_ALL"
	f.channelBtn:SetText(L[chKey])

	local sortKey = (filters.sortBy == "margin" and "PROFIT_SORT_MARGIN")
		or (filters.sortBy == "craftable" and "PROFIT_SORT_CRAFTABLE")
		or "PROFIT_SORT_PROFIT"
	f.sortBtn:SetText(L[sortKey])

	if filters.profFilter == 0 then
		f.profBtn:SetText(L["PROFIT_PROF_ALL"])
	else
		f.profBtn:SetText(ns:GetProfessionName(filters.profFilter) or tostring(filters.profFilter))
	end
	f.freshBtn:SetText(filters.freshOnly and L["PROFIT_FRESH_ON"] or L["PROFIT_FRESH_OFF"])
	f.cbOwned:SetChecked(filters.onlyOwned)
	f.cbAlts:SetChecked(filters.includeAlts)

	f.entries = ns.BuildProfitList and ns:BuildProfitList(filters) or {}
	f.countText:SetText(string.format(L["PROFIT_FOUND"], #f.entries))
	local maxOff = math.max(0, #f.entries - VISIBLE_ROWS)
	if f.offset > maxOff then
		f.offset = maxOff
	end
	self:RenderRows()
end

function ProfitMod:OnPricesInvalidated()
	if ns.InvalidateProfitCache then
		ns.InvalidateProfitCache()
	end
	if self.view and self.view:IsVisible() then
		self:OnRefresh()
	end
end

function ProfitMod:OnAuctionStockUpdated(itemID)
	if ns.EvaluateSnipeItem then
		ns:EvaluateSnipeItem(itemID, false)
	end
	if ns.RefreshSnipeUI then
		ns:RefreshSnipeUI()
	end
end

function ProfitMod:OnFrameDestroyed()
	self.view = nil
end

function ProfitMod:OnDisable()
	if ns.InvalidateProfitCache then
		ns.InvalidateProfitCache()
	end
	if ns.RefreshSnipeBar then
		ns:RefreshSnipeBar()
	end
end

ns:RegisterModule(ProfitMod)
