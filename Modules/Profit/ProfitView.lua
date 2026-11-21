local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Модуль «Заработок»: UI-вкладка профитных рецептов по всем профессиям
-------------------------------------------------------------------------------
local ROW_H = 27
local VISIBLE_ROWS = 8
local PROFIT_VISIBLE_ROWS = 7
local CHANNELS = { "all", "safe", "ah" }
local SORTS = { "profit", "gph", "margin", "craftable" }

local function GetVisibleRows(f)
	return (f and f.subMode == "profit") and PROFIT_VISIBLE_ROWS or VISIBLE_ROWS
end

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
	return (Utf8Prefix(name, 10):gsub("%s+$", ""))
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
		if a == b then return false end
		if a == 0 then return true end
		if b == 0 then return false end
		return a < b
	end)
	return list
end

local function FormatChannelTag(src, ageDays)
	local key = (src == "vendor" and "PROFIT_SRC_VENDOR")
		or (src == "disenchant" and "PROFIT_SRC_DE")
		or (src == "ah" and "PROFIT_SRC_AH")
		or "SOURCE_UNKNOWN"
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
		includeTrainer = opts.profitIncludeTrainer == true,
		includeVendor = opts.profitIncludeVendor == true,
		includeOther = opts.profitIncludeOther == true,
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

	local subSniperBtn = ns.CreateTabButton(subBar, 124, 22, string.format(L["PROFIT_SUBTAB_SNIPER"], 0))
	subSniperBtn:SetPoint("LEFT", subProfitBtn, "RIGHT", 6, 0)

	local subLogBtn = ns.CreateTabButton(subBar, 112, 22, string.format(L["PROFIT_SUBTAB_LOG"], 0))
	subLogBtn:SetPoint("LEFT", subSniperBtn, "RIGHT", 6, 0)

	local function SelectSubMode(mode)
		f.subMode = mode
		f.offset = 0
		if mode ~= "sniper" and ns.HideSniperSettingsFrame then
			ns:HideSniperSettingsFrame("tab")
		end
		ns.SetTabButtonActive(subProfitBtn, mode == "profit")
		ns.SetTabButtonActive(subSniperBtn, mode == "sniper")
		ns.SetTabButtonActive(subLogBtn, mode == "log")
		ProfitMod:OnRefresh()
	end
	subProfitBtn:SetScript("OnClick", function() SelectSubMode("profit") end)
	subSniperBtn:SetScript("OnClick", function() SelectSubMode("sniper") end)
	subLogBtn:SetScript("OnClick", function() SelectSubMode("log") end)
	f.subProfitBtn = subProfitBtn
	f.subSniperBtn = subSniperBtn
	f.subLogBtn = subLogBtn
	f.SelectSubMode = SelectSubMode
	ns.SetTabButtonActive(subProfitBtn, true)
	ns.SetTabButtonActive(subSniperBtn, false)
	ns.SetTabButtonActive(subLogBtn, false)

	local top = CreateFrame("Frame", nil, f)
	top:SetPoint("TOPLEFT", 8, -28)
	top:SetPoint("TOPRIGHT", -8, -28)
	top:SetHeight(68)
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

	local function MakeCheck(label, optKey, xAnchor, relativeTo, widthHit, tipText)
		local cb = CreateFrame("CheckButton", nil, top, "UICheckButtonTemplate")
		cb:SetSize(20, 20)
		cb:SetPoint("LEFT", relativeTo, "RIGHT", xAnchor, 0)
		cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cb.text:SetPoint("LEFT", cb, "RIGHT", 1, 0)
		cb.text:SetText(label)
		local w = math.ceil((cb.text.GetStringWidth and cb.text:GetStringWidth()) or 0)
		if w < 20 then
			w = (widthHit and widthHit > 0) and widthHit or 60
		end
		cb:SetHitRectInsets(0, -(w + 4), 0, 0)
		cb:SetScript("OnClick", function(self)
			if ns.db and ns.db.options then
				ns.db.options[optKey] = self:GetChecked() and true or false
			end
			f.offset = 0
			ProfitMod:OnRefresh()
		end)
		if tipText then
			cb:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(label, 1, 0.82, 0)
				GameTooltip:AddLine(tipText, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			cb:SetScript("OnLeave", GameTooltip_Hide)
		end
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

	-- 3-я строка фильтров: включение неизученных рецептов (Тренер / Вендор / Прочие)
	local sourcesLbl = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sourcesLbl:SetPoint("TOPLEFT", 0, -51)
	sourcesLbl:SetText(L["PLANNER_SOURCES_LABEL"])

	f.cbSrcTrainer = MakeCheck(L["PLANNER_INCLUDE_TRAINER"], "profitIncludeTrainer", 6, sourcesLbl, 62, L["PLANNER_INCLUDE_TRAINER_TIP"])
	f.cbSrcVendor = MakeCheck(L["PLANNER_INCLUDE_VENDOR"], "profitIncludeVendor", 10, f.cbSrcTrainer.text, 140, L["PLANNER_INCLUDE_VENDOR_TIP"])
	f.cbSrcOther = MakeCheck(L["PLANNER_INCLUDE_OTHER"], "profitIncludeOther", 10, f.cbSrcVendor.text, 52, L["PLANNER_INCLUDE_OTHER_TIP"])

	local sniperTop = CreateFrame("Frame", nil, f)
	sniperTop:SetPoint("TOPLEFT", 8, -28)
	sniperTop:SetPoint("TOPRIGHT", -8, -28)
	sniperTop:SetHeight(46)
	sniperTop:Hide()
	f.sniperTop = sniperTop

	local importShopBtn = CreateFrame("Button", nil, sniperTop, "UIPanelButtonTemplate")
	importShopBtn:SetSize(116, 20)
	importShopBtn:SetPoint("TOPLEFT", 0, 0)
	importShopBtn:SetText(L["SNIPE_IMPORT_SHOP"])
	importShopBtn:SetScript("OnClick", function()
		if ns.ImportShoppingToSnipe then
			ns:ImportShoppingToSnipe(0.80)
		end
	end)

	local scanSnipeBtn = CreateFrame("Button", nil, sniperTop, "UIPanelButtonTemplate")
	scanSnipeBtn:SetSize(94, 20)
	scanSnipeBtn:SetPoint("LEFT", importShopBtn, "RIGHT", 4, 0)
	scanSnipeBtn:SetText(L["SNIPE_SCAN_BTN"])
	scanSnipeBtn:SetScript("OnClick", function()
		if ns.SearchSnipeTargetsOnAH then
			ns:SearchSnipeTargetsOnAH()
		end
	end)
	scanSnipeBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["SNIPE_SCAN_BTN"], 1, 0.82, 0)
		GameTooltip:AddLine(L["SNIPE_SCAN_TIP"], 0.85, 0.85, 0.85, true)
		GameTooltip:Show()
	end)
	scanSnipeBtn:SetScript("OnLeave", GameTooltip_Hide)

	local repriceBtn = CreateFrame("Button", nil, sniperTop, "UIPanelButtonTemplate")
	repriceBtn:SetSize(88, 20)
	repriceBtn:SetPoint("LEFT", scanSnipeBtn, "RIGHT", 4, 0)
	repriceBtn:SetText(L["SNIPE_REPRICE_BTN"])
	repriceBtn:SetScript("OnClick", function()
		if ns.RepriceSnipeTargets then
			ns:RepriceSnipeTargets(0.80)
		end
	end)
	repriceBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["SNIPE_REPRICE_BTN"], 1, 0.82, 0)
		GameTooltip:AddLine(L["SNIPE_REPRICE_TIP"], 0.85, 0.85, 0.85, true)
		GameTooltip:Show()
	end)
	repriceBtn:SetScript("OnLeave", GameTooltip_Hide)

	local clearSnipeBtn = CreateFrame("Button", nil, sniperTop, "UIPanelButtonTemplate")
	clearSnipeBtn:SetSize(72, 20)
	clearSnipeBtn:SetPoint("LEFT", repriceBtn, "RIGHT", 4, 0)
	clearSnipeBtn:SetText(L["QUEUE_CLEAR"])
	clearSnipeBtn:SetScript("OnClick", function()
		if ns.ClearSnipeTargets then
			ns:ClearSnipeTargets()
		end
	end)

	local snipeSettingsBtn = CreateFrame("Button", nil, sniperTop, "UIPanelButtonTemplate")
	snipeSettingsBtn:SetSize(94, 20)
	snipeSettingsBtn:SetPoint("LEFT", clearSnipeBtn, "RIGHT", 4, 0)
	snipeSettingsBtn:SetText(L["SNIPE_SETTINGS_BTN"])
	snipeSettingsBtn:SetScript("OnClick", function(self)
		if ns.ToggleSniperSettingsFrame then
			ns:ToggleSniperSettingsFrame(self, "tab")
		end
	end)
	snipeSettingsBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["SNIPE_SETTINGS_TITLE"], 1, 0.82, 0)
		GameTooltip:AddLine(L["SNIPE_SETTINGS_TIP"], 0.85, 0.85, 0.85, true)
		if ns.FormatSnipeLimitsSummary then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(string.format(L["SNIPE_LIMIT_SUMMARY_FMT"], ns:FormatSnipeLimitsSummary()), 0.4, 0.9, 1, true)
		end
		GameTooltip:Show()
	end)
	snipeSettingsBtn:SetScript("OnLeave", GameTooltip_Hide)
	f.snipeSettingsBtn = snipeSettingsBtn

	local cbAutoScan = CreateFrame("CheckButton", nil, sniperTop, "UICheckButtonTemplate")
	cbAutoScan:SetSize(20, 20)
	cbAutoScan:SetPoint("TOPLEFT", 0, -24)
	cbAutoScan.text = cbAutoScan:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cbAutoScan.text:SetPoint("LEFT", cbAutoScan, "RIGHT", 2, 0)
	cbAutoScan.text:SetText(L["SNIPE_AUTOSCAN_CB"])
	cbAutoScan:SetHitRectInsets(0, -math.max(60, math.ceil((cbAutoScan.text:GetStringWidth() or 80) + 4)), 0, 0)
	cbAutoScan:SetScript("OnClick", function(self)
		if ns.db and ns.db.options then
			ns.db.options.snipeAutoScan = self:GetChecked() and true or false
		end
	end)
	cbAutoScan:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["SNIPE_AUTOSCAN_CB"], 1, 0.82, 0)
		GameTooltip:AddLine(L["SNIPE_AUTOSCAN_TIP"], 0.85, 0.85, 0.85, true)
		GameTooltip:Show()
	end)
	cbAutoScan:SetScript("OnLeave", GameTooltip_Hide)
	f.cbAutoScan = cbAutoScan

	local snipeAddBox = CreateFrame("EditBox", nil, sniperTop, "InputBoxTemplate")
	snipeAddBox:SetSize(184, 20)
	snipeAddBox:SetPoint("TOPLEFT", 112, -24)
	snipeAddBox:SetAutoFocus(false)
	snipeAddBox.placeholder = snipeAddBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	snipeAddBox.placeholder:SetPoint("LEFT", 4, 0)
	snipeAddBox.placeholder:SetText(L["SNIPE_ADD_PLACEHOLDER"])

	local snipePriceBox = CreateFrame("EditBox", nil, sniperTop, "InputBoxTemplate")
	snipePriceBox:SetSize(92, 20)
	snipePriceBox:SetPoint("LEFT", snipeAddBox, "RIGHT", 8, 0)
	snipePriceBox:SetAutoFocus(false)
	snipePriceBox.placeholder = snipePriceBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	snipePriceBox.placeholder:SetPoint("LEFT", 4, 0)
	snipePriceBox.placeholder:SetText(L["SNIPE_PRICE_PLACEHOLDER"])

	local function PickCursorItemID()
		if not (CursorHasItem and CursorHasItem()) then
			return nil, nil
		end
		local itemID, displayName
		if GetCursorInfo then
			local kind, id, link = GetCursorInfo()
			if kind == "item" and id and id > 0 then
				itemID = id
				displayName = link and link:match("|h%[(.-)%]|h")
			end
		end
		if not itemID and C_Cursor and C_Cursor.GetCursorItem and C_Item and C_Item.GetItemID then
			local loc = C_Cursor.GetCursorItem()
			if loc and loc.IsValid and loc:IsValid() then
				itemID = C_Item.GetItemID(loc)
				displayName = C_Item.GetItemName and C_Item.GetItemName(loc)
			end
		end
		if itemID and ClearCursor then
			ClearCursor()
		end
		if itemID and (not displayName or displayName == "") and ns.GetItemDisplay then
			local dName, _, _, _, loaded = ns:GetItemDisplay(itemID)
			if loaded and dName then
				displayName = dName
			end
		end
		return itemID, displayName
	end

	local function FillItemIntoAddBox(itemID, displayName, focusPrice)
		snipeAddBox.pickedItemID = itemID
		local txt = (displayName and displayName ~= "") and displayName or tostring(itemID)
		snipeAddBox:SetText(txt)
		snipeAddBox.placeholder:SetShown(false)
		if focusPrice then
			snipePriceBox:SetFocus()
			if snipePriceBox.HighlightText then
				snipePriceBox:HighlightText()
			end
		end
	end

	local function SubmitManualSnipe()
		if ns.AddManualSnipeTarget and ns:AddManualSnipeTarget(snipeAddBox:GetText(), snipePriceBox:GetText(), snipeAddBox.pickedItemID) then
			snipeAddBox.pickedItemID = nil
			snipeAddBox:SetText("")
			snipePriceBox:SetText("")
			snipeAddBox:ClearFocus()
			snipePriceBox:ClearFocus()
		end
	end

	snipeAddBox:SetScript("OnTextChanged", function(self, userInput)
		self.placeholder:SetShown((self:GetText() or "") == "")
		if userInput then
			self.pickedItemID = nil
		end
	end)
	if snipeAddBox.HasScript and snipeAddBox:HasScript("OnReceiveDrag") then
		snipeAddBox:SetScript("OnReceiveDrag", function()
			local id, itemName = PickCursorItemID()
			if id then
				FillItemIntoAddBox(id, itemName, true)
			end
		end)
	end
	snipeAddBox:SetScript("OnMouseDown", function()
		if CursorHasItem and CursorHasItem() then
			local id, itemName = PickCursorItemID()
			if id then
				FillItemIntoAddBox(id, itemName, true)
			end
		end
	end)
	snipeAddBox:SetScript("OnTabPressed", function() snipePriceBox:SetFocus() end)
	snipeAddBox:SetScript("OnEnterPressed", SubmitManualSnipe)
	snipeAddBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	snipeAddBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["SNIPE_ADD_BTN"], 1, 0.82, 0)
		GameTooltip:AddLine(L["SNIPE_ADD_TIP"], 0.85, 0.85, 0.85, true)
		GameTooltip:Show()
	end)
	snipeAddBox:SetScript("OnLeave", GameTooltip_Hide)

	snipePriceBox:SetScript("OnTextChanged", function(self)
		self.placeholder:SetShown((self:GetText() or "") == "")
	end)
	snipePriceBox:SetScript("OnTabPressed", function() snipeAddBox:SetFocus() end)
	snipePriceBox:SetScript("OnEnterPressed", SubmitManualSnipe)
	snipePriceBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	snipePriceBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["SNIPE_PRICE_PLACEHOLDER"], 1, 0.82, 0)
		GameTooltip:AddLine(L["SNIPE_PRICE_TIP"], 0.85, 0.85, 0.85, true)
		GameTooltip:Show()
	end)
	snipePriceBox:SetScript("OnLeave", GameTooltip_Hide)

	local snipeAddBtn = CreateFrame("Button", nil, sniperTop, "UIPanelButtonTemplate")
	snipeAddBtn:SetSize(76, 20)
	snipeAddBtn:SetPoint("LEFT", snipePriceBox, "RIGHT", 5, 0)
	snipeAddBtn:SetText(L["SNIPE_ADD_BTN"])
	local function TryAddCursorOrBox()
		local id = PickCursorItemID()
		if id and ns.AddManualSnipeTarget then
			if ns:AddManualSnipeTarget(nil, snipePriceBox:GetText(), id) then
				snipeAddBox.pickedItemID = nil
				snipeAddBox:SetText("")
				snipePriceBox:SetText("")
			end
			return
		end
		SubmitManualSnipe()
	end
	snipeAddBtn:SetScript("OnClick", TryAddCursorOrBox)
	snipeAddBtn:SetScript("OnReceiveDrag", TryAddCursorOrBox)

	f.snipeAddBox = snipeAddBox
	f.snipePriceBox = snipePriceBox
	ns.snipeAddBox = snipeAddBox

	if not ns.snipeInsertLinkHooked and hooksecurefunc and ChatEdit_InsertLink then
		ns.snipeInsertLinkHooked = true
		hooksecurefunc("ChatEdit_InsertLink", function(link)
			local box = ns.snipeAddBox
			if type(link) == "string" and box and box:IsVisible() and box:HasFocus() then
				local itemID = tonumber(link:match("item:(%d+)"))
				if itemID and itemID > 0 then
					box.pickedItemID = itemID
					local txt = link:match("|h%[(.-)%]|h") or link
					box:SetText(txt)
					if box.SetCursorPosition then
						box:SetCursorPosition(#txt)
					end
				end
			end
		end)
	end

	local logTop = CreateFrame("Frame", nil, f)
	logTop:SetPoint("TOPLEFT", 8, -28)
	logTop:SetPoint("TOPRIGHT", -8, -28)
	logTop:SetHeight(24)
	logTop:Hide()
	f.logTop = logTop
	f.logPeriod = "today"

	local modeBtn = CreateFrame("Button", nil, logTop, "UIPanelButtonTemplate")
	modeBtn:SetSize(106, 20)
	modeBtn:SetPoint("LEFT", 0, 0)
	modeBtn:SetScript("OnClick", function()
		if ns.db and ns.db.options then
			local cur = ns.GetProfitLogMode and ns:GetProfitLogMode() or "craft"
			ns.db.options.profitLogMode = (cur == "cashflow") and "craft" or "cashflow"
		end
		f.offset = 0
		ProfitMod:OnRefresh()
	end)
	modeBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self:GetText(), 1, 0.82, 0)
		GameTooltip:AddLine(L["PROFIT_LOG_MODE_TIP"], 1, 1, 1, true)
		if ns.HasAuctionatorForLog and not ns:HasAuctionatorForLog() then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(L["PROFIT_LOG_MODE_NO_ATR"], 1, 0.45, 0.25, true)
		end
		GameTooltip:Show()
	end)
	modeBtn:SetScript("OnLeave", GameTooltip_Hide)
	f.modeBtn = modeBtn

	local periodBtn = CreateFrame("Button", nil, logTop, "UIPanelButtonTemplate")
	periodBtn:SetSize(84, 20)
	periodBtn:SetPoint("LEFT", modeBtn, "RIGHT", 4, 0)
	periodBtn:SetScript("OnClick", function()
		f.logPeriod = (f.logPeriod == "today") and "all" or "today"
		f.offset = 0
		ProfitMod:OnRefresh()
	end)
	f.periodBtn = periodBtn

	local logSummaryText = logTop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	logSummaryText:SetPoint("LEFT", periodBtn, "RIGHT", 6, 0)
	logSummaryText:SetPoint("RIGHT", -2, 0)
	logSummaryText:SetJustifyH("RIGHT")
	logSummaryText:SetWordWrap(false)
	if logSummaryText.SetMaxLines then
		logSummaryText:SetMaxLines(1)
	end
	f.logSummaryText = logSummaryText

	local summaryHit = CreateFrame("Frame", nil, logTop)
	summaryHit:SetAllPoints(logSummaryText)
	summaryHit:EnableMouse(true)
	summaryHit:SetScript("OnEnter", function(self)
		local s = f.logSummary
		if not s then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(f.modeBtn and f.modeBtn:GetText() or L["PROFIT_LOG_MODE_CRAFT"], 1, 0.82, 0)
		GameTooltip:AddLine(string.format(L["PROFIT_LOG_SUMMARY_TIP_SPENT"], ns.FormatMoney(s.spent or s.cost or 0)), 1, 0.45, 0.45)
		GameTooltip:AddLine(string.format(L["PROFIT_LOG_SUMMARY_TIP_EARNED"], ns.FormatMoney(s.earned or s.revenue or 0)), 0.4, 1, 0.4)
		GameTooltip:AddLine(string.format(L["PROFIT_LOG_SUMMARY_TIP_NET"], ns.FormatMoney(s.profit or 0, true)), 1, 1, 1)
		GameTooltip:Show()
	end)
	summaryHit:SetScript("OnLeave", GameTooltip_Hide)

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
		local maxOff = math.max(0, #f.entries - GetVisibleRows(f))
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
		row.snipeBtn:SetSize(52, 20)
		row.snipeBtn:SetPoint("RIGHT", -2, 0)
		row.snipeBtn:SetText(L["PROFIT_BTN_SNIPE"])
		row.snipeBtn:SetScript("OnClick", function()
			local e = row.entryData
			if e and e.recipeID and ns.AddRecipeReagentsToSnipe then
				local added, total = ns:AddRecipeReagentsToSnipe(e.recipeID, 0.80, e.gphCraftPlan)
				if added > 0 then
					ns:Print(string.format(L["SNIPE_ADDED_MSG"], added))
				elseif total > 0 then
					ns:Print(L["SNIPE_ALREADY_MSG"])
				else
					ns:Print(L["SNIPE_NO_AH_MSG"])
				end
			end
		end)
		row.snipeBtn:SetScript("OnEnter", function(self)
			local e = row.entryData
			if not (e and e.recipeID) then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["SNIPE_BTN_TITLE"], 1, 0.82, 0)
			GameTooltip:AddLine(L["SNIPE_BTN_DESC"], 0.85, 0.85, 0.85, true)
			if ns.GetRecipeSnipePreview then
				local items = ns:GetRecipeSnipePreview(e.recipeID, 0.80, e.gphCraftPlan)
				if #items == 0 then
					GameTooltip:AddLine(L["SNIPE_NO_AH_MSG"], 1, 0.5, 0.3, true)
				else
					GameTooltip:AddLine(" ")
					for _, it in ipairs(items) do
						local iName, _, _, _, _, iHex = ns:GetItemDisplay(it.itemID)
						local tag = it.watched and L["SNIPE_WATCHED_TAG"] or ""
						GameTooltip:AddDoubleLine(
							(iHex or "|cffffffff") .. iName .. "|r" .. tag,
							string.format("<= %s (%s)", ns.FormatMoney(it.maxPrice), ns.FormatMoney(it.curPrice)),
							1, 1, 1, 0.4, 1, 0.4
						)
					end
				end
			end
			GameTooltip:Show()
		end)
		row.snipeBtn:SetScript("OnLeave", GameTooltip_Hide)

		row.queueBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.queueBtn:SetSize(76, 20)
		row.queueBtn:SetPoint("RIGHT", row.snipeBtn, "LEFT", -3, 0)
		row.queueBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.queueBtn:SetText(L["PLANNER_BTN_QUEUE_STEP"])
		row.queueBtn:SetScript("OnClick", function(_, button)
			local e = row.entryData
			if e and not e.isAlt and ns.QueueAddRecipe then
				local qty = 1
				local isShiftAll = false
				if button == "RightButton" then
					qty = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 5
				elseif IsShiftKeyDown and IsShiftKeyDown() then
					isShiftAll = true
					local rem = ns.GetRemainingCraftableCount and ns:GetRemainingCraftableCount(e.recipeID, true) or nil
					if rem and rem > 0 then
						qty = rem
					elseif rem ~= nil and (e.craftNow or 0) > 0 then
						ns:Print(L["QUEUE_ALL_RESERVED"])
						return
					else
						qty = math.max(1, e.craftNow or 1)
					end
				end
				local filters = ProfitMod:GetFilters()
				local craftPlan = (filters.sortBy == "gph" and not filters.onlyOwned and not isShiftAll) and e.gphCraftPlan or nil
				ns:QueueAddRecipe(e.recipeID, qty, nil, nil, craftPlan)
			end
		end)
		row.queueBtn:SetScript("OnEnter", function(self)
			local e = row.entryData
			if not e then
				return
			end
			local avail = (ns.GetRemainingCraftableCount and ns:GetRemainingCraftableCount(e.recipeID, true)) or (e.craftNow or 0)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["PLANNER_BTN_QUEUE_STEP"], 1, 0.82, 0)
			GameTooltip:AddLine(string.format(L["PROFIT_QUEUE_TOOLTIP"], math.max(0, avail)), 0.9, 0.9, 0.9, true)
			GameTooltip:Show()
		end)
		row.queueBtn:SetScript("OnLeave", GameTooltip_Hide)

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
				ns:SearchSnipeTargetsOnAH(e.itemID, true)
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
		if row.title.SetMaxLines then row.title:SetMaxLines(1) end

		row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
		row.sub:SetPoint("RIGHT", row.marginText, "LEFT", -8, 0)
		row.sub:SetJustifyH("LEFT")
		row.sub:SetWordWrap(false)
		if row.sub.SetMaxLines then row.sub:SetMaxLines(1) end

		row:SetScript("OnClick", function(self, button)
			local e = self.entryData
			if not e then
				return
			end
			if f.subMode == "sniper" then
				if ns:HandleItemClick(e.itemID) then
					return
				end
				if f.snipeAddBox and f.snipePriceBox and e.itemID then
					local name, _, _, _, loaded = ns:GetItemDisplay(e.itemID)
					f.snipeAddBox.pickedItemID = e.itemID
					f.snipeAddBox:SetText((loaded and name) or tostring(e.itemID))
					f.snipePriceBox:SetText(ns.FormatMoneyPlain and ns.FormatMoneyPlain(e.maxPrice) or "")
					f.snipePriceBox:SetFocus()
					if f.snipePriceBox.HighlightText then
						f.snipePriceBox:HighlightText()
					end
				end
				return
			elseif f.subMode == "log" and not e.recipeID and e.itemID then
				ns:HandleItemClick(e.itemID)
				return
			end
			if ns:HandleItemClick(e.outItemID, e.recipeID) then
				return
			end
			local isOwnChar = (not e.isAlt) and (not e.charKey or e.charKey == ns:CharKey())
			local canOpenDetails = isOwnChar and (ns:IsRecipeLearned(e.recipeID) or e.unlearnedSource ~= nil)
			if button == "RightButton" then
				if e.recipeID and ns.ToggleRecipeFavorite then
					ns:ToggleRecipeFavorite(e.recipeID)
				end
				return
			end
			local sl = e.skillLine or (ns.GetRecipeRecord and (ns:GetRecipeRecord(e.recipeID) or {}).skillLine)
			if canOpenDetails and sl and ns.playerProfessions[sl] then
				if ns.mainFrame and ns.mainFrame.SelectTopTab then
					ns.mainFrame.SelectTopTab("details", true)
				end
				if sl ~= ns.currentSkillLine and ns.SwitchToProfession then
					ns.preserveSelectedRecipe = true
					ns:SwitchToProfession(sl, e.recipeID)
					ns.preserveSelectedRecipe = false
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
				if GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown() then
					local addedGap = false
					if e.gph and e.gph > 0 then
						GameTooltip:AddLine(" ")
						addedGap = true
						GameTooltip:AddLine(string.format(
							L["PROFIT_GPH_TOOLTIP"],
							ns.FormatMoney(e.gph),
							ns.FormatDuration(e.gphTime),
							ns.FormatMoney(e.gphProfit or e.profit)
						), 0.4, 1, 0.4, true)
						if e.gphBuyInstead and #e.gphBuyInstead > 0 then
							local names = {}
							for _, itemID in ipairs(e.gphBuyInstead) do
								local n, _, _, _, _, hex = ns:GetItemDisplay(itemID)
								names[#names + 1] = (hex or "|cffffffff") .. (n or ("#" .. itemID)) .. "|r"
							end
							GameTooltip:AddLine(string.format(L["PROFIT_GPH_BUY_SUB"], table.concat(names, ", ")), 1, 0.85, 0.4, true)
						end
					end
					if e.unlearnedSource then
						if not addedGap then
							GameTooltip:AddLine(" ")
							addedGap = true
						end
						local tagKey = (e.unlearnedSource == "trainer" and "PROFIT_UNLEARNED_TRAINER")
							or (e.unlearnedSource == "vendor" and "PROFIT_UNLEARNED_VENDOR")
							or "PROFIT_UNLEARNED_OTHER"
						local srcLabel = string.format(L[tagKey], e.reqSkill or 1)
						if e.acquireFee and e.acquireFee > 0 then
							GameTooltip:AddLine(string.format(L["PROFIT_UNLEARNED_TIP_FEE"], srcLabel, ns.FormatMoney(e.acquireFee)), 1, 0.82, 0, true)
						else
							GameTooltip:AddLine(string.format(L["PROFIT_UNLEARNED_TIP_NOFEE"], srcLabel), 0.7, 0.85, 1, true)
						end
					end
					if e.isAlt and e.ownerName then
						if not addedGap then
							GameTooltip:AddLine(" ")
						end
						GameTooltip:AddLine(string.format(L["PROFIT_ALT_TOOLTIP"], e.ownerName), 0.4, 0.8, 1)
					end
					GameTooltip:Show()
				end
			elseif e.itemID and ns.ShowItemTooltip then
				ns:ShowItemTooltip(self, e.itemID)
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
	local isLog = (f.subMode == "log")
	local logMode = isLog and (ns.GetProfitLogMode and ns:GetProfitLogMode() or "craft") or nil
	f.emptyLabel:SetText(isSniper and L["SNIPE_EMPTY"] or (isLog and ((logMode == "cashflow") and L["PROFIT_LOG_CASH_EMPTY"] or L["PROFIT_LOG_EMPTY"]) or L["PROFIT_EMPTY"]))
	f.emptyLabel:SetShown(#list == 0)

	local visRows = GetVisibleRows(f)
	for i = 1, VISIBLE_ROWS do
		local row = f.rows[i]
		local e = (i <= visRows) and list[i + f.offset] or nil
		row.entryData = e
		if e then
			row:Show()
			if isLog then
				local timeStr = (date and e.ts and e.ts > 0) and date("%H:%M", e.ts) or ""
				local charTag = (e.charKey and e.charKey ~= "" and e.charKey ~= ns:CharKey())
					and (" |cff66ccff[" .. e.charKey .. "]|r") or ""
				if logMode == "cashflow" then
					local name, icon, hex
					if e.kind == "trainer" or not e.itemID then
						name = e.name or (e.recipeID and select(1, ns:GetRecipeDisplay(e.recipeID))) or "?"
						icon = "Interface\\Icons\\INV_Misc_Book_11"
						hex = "|cffffd100"
					else
						local dName, dIcon, _, _, _, dHex = ns:GetItemDisplay(e.itemID)
						name = dName or e.name or ("#" .. e.itemID)
						icon = dIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
						hex = dHex or "|cffffffff"
					end
					row.icon:SetTexture(icon)
					local cnt = math.max(1, math.floor((e.count or 1) + 0.5))
					local cntTag = (cnt > 1) and string.format(" |cffffd100x%d|r", cnt) or ""
					row.title:SetText(string.format("%s%s|r%s |cff888888%s|r%s", hex, name, cntTag, timeStr, charTag))
					local kindKey = "PROFIT_LOG_KIND_" .. string.upper(e.kind or "ah_buy")
					local kindTag = L[kindKey] or e.kind or ""
					local amt = e.amount or 0
					if cnt > 1 then
						local unitP = math.floor(math.abs(amt) / cnt + 0.5)
						row.sub:SetText(string.format(L["PROFIT_LOG_UNIT_FMT"], kindTag, ns.FormatMoney(unitP)))
					else
						row.sub:SetText(kindTag)
					end
					row.profitText:ClearAllPoints()
					row.profitText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
					row.profitText:SetText(ns.FormatMoney(amt, true))
				elseif e.kind == "trainer" then
					local name = e.name or (e.recipeID and select(1, ns:GetRecipeDisplay(e.recipeID))) or "?"
					row.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
					row.title:SetText(string.format("|cffffd100%s|r |cff888888%s|r%s", name, timeStr, charTag))
					row.sub:SetText(L["PROFIT_LOG_KIND_TRAINER"])
					row.profitText:ClearAllPoints()
					row.profitText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
					row.profitText:SetText(ns.FormatMoney(e.profit or 0, true))
				else
					local name, icon, _, _, _, hex = ns:GetRecipeDisplay(e.recipeID)
					row.icon:SetTexture(icon)
					local cnt = e.count or 1
					local cntStr
					if math.abs(cnt - math.floor(cnt + 0.5)) >= 0.01 then
						cntStr = (cnt < 0.1) and string.format("x%.2f", cnt) or string.format("x%.1f", cnt)
					else
						cntStr = string.format("x%d", math.floor(cnt + 0.5))
					end
					row.title:SetText(string.format("%s%s|r |cffffd100%s|r |cff888888%s|r%s", hex or "|cffffffff", name, cntStr, timeStr, charTag))
					local costStr = ns.FormatMoney(e.cost) .. (e.usedRealCost and L["PROFIT_LOG_REAL_COST_TAG"] or "")
					row.sub:SetText(string.format(L["PROFIT_LOG_SUB_FMT"], FormatChannelTag(e.source, nil), costStr, ns.FormatMoney(e.revenue)))
					row.profitText:ClearAllPoints()
					row.profitText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
					row.profitText:SetText(ns.FormatMoney(e.profit or 0, true))
				end
				row.marginText:SetText("")
				row.snipeBtn:Hide()
				row.queueBtn:Hide()
				row.minusBtn:Hide()
				row.plusBtn:Hide()
				row.findBtn:Hide()
				row.delBtn:Hide()
				row.title:ClearAllPoints()
				row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
				row.title:SetPoint("RIGHT", row.profitText, "LEFT", -8, 0)
				row.sub:ClearAllPoints()
				row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
				row.sub:SetPoint("RIGHT", row.profitText, "LEFT", -8, 0)
			elseif isSniper then
				local name, icon, _, _, _, hex = ns:GetItemDisplay(e.itemID)
				row.icon:SetTexture(icon)
				local hit = ns.snipeHits and ns.snipeHits[e.itemID]
				local qtyStr = hit and (ns.FormatSnipeHitQty and ns.FormatSnipeHitQty(hit) or L["SNIPE_LOT_ANY"]) or nil
				local statusTag = hit
					and string.format(" |cff40ff40[%s @ %s (-%d%%)]|r", qtyStr, ns.FormatMoney(hit.bestPrice), hit.discountPct or 0)
					or ""
				row.title:SetText(string.format("%s%s|r%s", hex or "|cffffffff", name, statusTag))
				local curP = ns:GetAuctionPrice(e.itemID)
				local curStr = curP and ns.FormatMoney(curP) or "|cff888888-|r"
				if curP and curP > 0 and e.maxPrice and e.maxPrice > 0 then
					local diffPct = math.floor((curP - e.maxPrice) / e.maxPrice * 100 + 0.5)
					if diffPct <= 0 then
						curStr = curStr .. string.format(" |cff40ff40(%d%%)|r", diffPct)
					else
						curStr = curStr .. string.format(" |cffaaaaaa(+%d%%)|r", diffPct)
					end
				end
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
				local srcBadge = ""
				if e.unlearnedSource then
					local tagKey, colorHex
					if e.unlearnedSource == "trainer" then
						tagKey = "PROFIT_UNLEARNED_TRAINER"
						colorHex = e.canLearnNow and "|cffffd100" or "|cffff8840"
					elseif e.unlearnedSource == "vendor" then
						tagKey = "PROFIT_UNLEARNED_VENDOR"
						colorHex = e.canLearnNow and "|cff66d9ff" or "|cff8899aa"
					else
						tagKey = "PROFIT_UNLEARNED_OTHER"
						colorHex = e.canLearnNow and "|cff88ccff" or "|cff888899"
					end
					srcBadge = string.format(" %s[%s]|r", colorHex, string.format(L[tagKey], e.reqSkill or 1))
				end
				local favPrefix = (e.recipeID and ns.IsRecipeFavorite and ns:IsRecipeFavorite(e.recipeID) and ns.GetFavoriteIconMarkup)
					and ns:GetFavoriteIconMarkup() or ""
				row.title:SetText(string.format("%s%s%s|r %s%s%s%s", favPrefix, e.qualityHex or "|cffffffff", e.name, profTag, srcBadge, cntTag, altTag))

				local filters = self:GetFilters()
				local useGph = (filters.sortBy == "gph") and e.gph and e.gph > 0
				local dispCost = useGph and (e.gphCost or e.craftCost) or e.craftCost
				local dispProfit = useGph and (e.gphProfit or e.profit) or e.profit

				local srcText = FormatChannelTag(e.source, e.ageDays)
				row.sub:SetText(string.format(L["PROFIT_SUB_FMT"], srcText, ns.FormatMoney(dispCost), ns.FormatMoney(e.outputValue)))
				local anchorRight = (not e.isAlt) and row.queueBtn or row.snipeBtn
				row.profitText:ClearAllPoints()
				row.profitText:SetPoint("RIGHT", anchorRight, "LEFT", -8, 6)
				row.marginText:ClearAllPoints()
				row.marginText:SetPoint("RIGHT", anchorRight, "LEFT", -8, -6)
				if useGph then
					row.profitText:SetText("|cff40ff40+" .. ns.FormatMoney(e.gph) .. L["PROFIT_GPH_SUFFIX"] .. "|r")
					row.marginText:SetText(string.format("|cff88ccff%s|r |cffaaaaaa(+%s)|r", ns.FormatDuration(e.gphTime), ns.FormatMoney(dispProfit)))
				else
					row.profitText:SetText("|cff40ff40+" .. ns.FormatMoney(e.profit) .. "|r")
					row.marginText:SetText(string.format("|cffaaaaaa+%d%%|r", e.margin or 0))
				end
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
	local logMode = ns.GetProfitLogMode and ns:GetProfitLogMode() or "craft"
	local activeLog = (ns.realmDB and ((logMode == "cashflow") and ns.realmDB.cashflowLog or ns.realmDB.profitLog)) or {}
	f.subLogBtn:SetText(string.format(L["PROFIT_SUBTAB_LOG"], #activeLog))

	local isSniper = (f.subMode == "sniper")
	local isLog = (f.subMode == "log")
	f.profitTop:SetShown(not isSniper and not isLog)
	f.sniperTop:SetShown(isSniper)
	f.logTop:SetShown(isLog)
	f.listBox:ClearAllPoints()
	f.listBox:SetPoint("TOPLEFT", 8, isLog and -56 or (isSniper and -78 or -98))
	f.listBox:SetPoint("BOTTOMRIGHT", -8, 6)

	if isLog then
		local summary = ns.GetProfitLogSummary and ns:GetProfitLogSummary(f.logPeriod or "today", logMode) or { entries = {}, craftsTotal = 0, opsTotal = 0, profit = 0 }
		f.logSummary = summary
		f.modeBtn:SetText((logMode == "cashflow") and L["PROFIT_LOG_MODE_CASH"] or L["PROFIT_LOG_MODE_CRAFT"])
		f.periodBtn:SetText((f.logPeriod == "today") and L["PROFIT_LOG_TODAY"] or L["PROFIT_LOG_ALL"])
		if logMode == "cashflow" then
			f.logSummaryText:SetText(string.format(L["PROFIT_LOG_CASH_SUMMARY"], ns.FormatMoney(summary.profit or 0, true), summary.opsTotal or 0))
		else
			f.logSummaryText:SetText(string.format(L["PROFIT_LOG_SUMMARY"], ns.FormatMoney(summary.profit or 0, true), summary.craftsTotal or 0))
		end
		f.entries = summary.entries or {}
		local maxOff = math.max(0, #f.entries - VISIBLE_ROWS)
		if f.offset > maxOff then
			f.offset = maxOff
		end
		self:RenderRows()
		return
	end

	if isSniper then
		if f.cbAutoScan then
			f.cbAutoScan:SetChecked(ns.db and ns.db.options and ns.db.options.snipeAutoScan == true)
		end
		for _, t in ipairs(targets) do
			if ns.EvaluateSnipeItem then
				ns:EvaluateSnipeItem(t.itemID, true)
			end
		end
		-- Сработавшие хиты всегда наверху списка, отсортированные по величине скидки
		table.sort(targets, function(a, b)
			local ha = ns.snipeHits and ns.snipeHits[a.itemID]
			local hb = ns.snipeHits and ns.snipeHits[b.itemID]
			if (ha ~= nil) ~= (hb ~= nil) then
				return ha ~= nil
			end
			if ha and hb and (ha.discountPct or 0) ~= (hb.discountPct or 0) then
				return (ha.discountPct or 0) > (hb.discountPct or 0)
			end
			return (a.itemID or 0) < (b.itemID or 0)
		end)
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

	local sortKey = (filters.sortBy == "gph" and "PROFIT_SORT_GPH")
		or (filters.sortBy == "margin" and "PROFIT_SORT_MARGIN")
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
	f.cbSrcTrainer:SetChecked(filters.includeTrainer)
	f.cbSrcVendor:SetChecked(filters.includeVendor)
	f.cbSrcOther:SetChecked(filters.includeOther)

	f.entries = ns.BuildProfitList and ns:BuildProfitList(filters) or {}
	f.countText:SetText(string.format(L["PROFIT_FOUND"], #f.entries))
	local maxOff = math.max(0, #f.entries - GetVisibleRows(f))
	if f.offset > maxOff then
		f.offset = maxOff
	end
	self:RenderRows()
end

function ProfitMod:OnPricesInvalidated(noRefresh)
	if ns.InvalidateProfitCache then
		ns.InvalidateProfitCache()
	end
	if not noRefresh and self.view and self.view:IsVisible() then
		self:OnRefresh()
	end
end

function ProfitMod:OnAuctionStockUpdated(itemID)
	local targets = ns.GetSnipeTargets and ns:GetSnipeTargets()
	if not (targets and targets[itemID]) then
		return
	end
	if ns.EvaluateSnipeItem then
		ns:EvaluateSnipeItem(itemID, false)
	end
	if ns.RefreshSnipeUI then
		ns:RefreshSnipeUI()
	end
end

function ProfitMod:OnCraftSucceeded(spellID, isSubcraft)
	if ns.RecordCraftProfit then
		ns:RecordCraftProfit(spellID, isSubcraft)
	end
end

function ProfitMod:OnFrameDestroyed()
	self.view = nil
	ns.snipeAddBox = nil
end

function ProfitMod:OnLanguageChanged()
	if ns.ResetSniperSettingsFrame then
		ns:ResetSniperSettingsFrame()
	end
	if ns.InvalidateProfitCache then
		ns.InvalidateProfitCache()
	end
	if ns.SyncSnipeShoppingList then
		ns:SyncSnipeShoppingList(true)
	end
	if ns.RefreshSnipeBar then
		ns:RefreshSnipeBar()
	end
end

function ProfitMod:OnEnable()
	if ns.InvalidateProfitCache then
		ns.InvalidateProfitCache()
	end
	if ns.GetSnipeTargetList and ns.EvaluateSnipeItem then
		for _, t in ipairs(ns:GetSnipeTargetList()) do
			ns:EvaluateSnipeItem(t.itemID, true)
		end
	end
	if ns.RefreshSnipeBar then
		ns:RefreshSnipeBar()
	end
end

function ProfitMod:OnDisable()
	if ns.HideSniperSettingsFrame then
		ns:HideSniperSettingsFrame()
	end
	if ns.InvalidateProfitCache then
		ns.InvalidateProfitCache()
	end
	ns.snipeHits = {}
	if ns.RefreshSnipeBar then
		ns:RefreshSnipeBar()
	end
end

ns:RegisterModule(ProfitMod)
