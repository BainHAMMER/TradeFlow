local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Вкладка «Калькулятор прокачки» (в стиле SkillUp) с отправкой шагов в очередь
-------------------------------------------------------------------------------
local ROW_H = 34
local VISIBLE_ROWS = 5

function ns:CreateRouteView(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints()
	f:Hide()

	-- Верхняя панель управления целью и опциями маршрута
	local top = CreateFrame("Frame", nil, f)
	top:SetPoint("TOPLEFT", 8, -6)
	top:SetPoint("TOPRIGHT", -8, -6)
	top:SetHeight(64)

	local targetLbl = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	targetLbl:SetPoint("TOPLEFT", 2, -5)
	targetLbl:SetText(L["PLANNER_TARGET"])

	local targetBox = CreateFrame("EditBox", nil, top, "InputBoxTemplate")
	targetBox:SetSize(42, 20)
	targetBox:SetPoint("LEFT", targetLbl, "RIGHT", 8, 0)
	targetBox:SetAutoFocus(false)
	targetBox:SetNumeric(true)
	targetBox:SetMaxLetters(3)
	targetBox:SetJustifyH("CENTER")
	f.targetBox = targetBox

	local function SetTarget(val)
		local sl = ns.currentSkillLine
		if not sl or not ns.charDB then
			return
		end
		val = math.max(1, math.min(300, tonumber(val) or 300))
		ns.charDB.targets[sl] = val
		targetBox:SetText(tostring(val))
		ns:RefreshRouteView()
	end

	targetBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		SetTarget(self:GetText())
	end)
	targetBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)

	local presets = {
		{ label = "+25", fn = function()
			local p = ns.playerProfessions[ns.currentSkillLine]
			SetTarget(((p and p.rank) or 1) + 25)
		end },
		{ label = "150", fn = function() SetTarget(150) end },
		{ label = "225", fn = function() SetTarget(225) end },
		{ label = "300", fn = function() SetTarget(300) end },
	}
	local prevBtn = targetBox
	for _, pr in ipairs(presets) do
		local b = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
		b:SetSize(38, 20)
		b:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
		b:SetText(pr.label)
		b:SetScript("OnClick", pr.fn)
		prevBtn = b
	end

	-- Переключатель приоритета маршрута в правом верхнем углу (над «Затраты» / «Возврат»)
	local priorityBtn = CreateFrame("Button", nil, top, "UIPanelButtonTemplate")
	priorityBtn:SetSize(148, 20)
	priorityBtn:SetPoint("TOPRIGHT", -2, -1)
	priorityBtn:SetScript("OnClick", function()
		if ns.db and ns.db.options then
			local cur = ns.db.options.routePriority or "speed"
			ns.db.options.routePriority = (cur == "profit") and "speed" or "profit"
		end
		ns:RefreshRouteView()
	end)
	f.priorityBtn = priorityBtn

	-- Источники неизученных рецептов в две компактные строки слева (на уровне Затрат/Возврата)
	local sourcesLbl = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	sourcesLbl:SetPoint("TOPLEFT", 2, -28)
	sourcesLbl:SetText(L["PLANNER_SOURCES_LABEL"])

	local function MakeCheck(label, optKey, fallbackHitW, tipText)
		local cb = CreateFrame("CheckButton", nil, top, "UICheckButtonTemplate")
		cb:SetSize(20, 20)
		cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		cb.text:SetText(label)
		local w = math.ceil((cb.text.GetStringWidth and cb.text:GetStringWidth()) or 0)
		if w < 20 then
			w = fallbackHitW or 60
		end
		cb:SetHitRectInsets(0, -(w + 4), 0, 0)
		cb:SetScript("OnClick", function(self)
			if ns.db and ns.db.options then
				ns.db.options[optKey] = self:GetChecked() and true or false
			end
			ns:RefreshRouteView()
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

	f.cbTrainer = MakeCheck(L["PLANNER_INCLUDE_TRAINER"], "includeTrainerInRoute", 62, L["PLANNER_INCLUDE_TRAINER_TIP"])
	f.cbTrainer:SetPoint("LEFT", sourcesLbl, "RIGHT", 6, 0)

	f.cbOtherRecipes = MakeCheck(L["PLANNER_INCLUDE_OTHER"], "includeOtherRecipesInRoute", 52, L["PLANNER_INCLUDE_OTHER_TIP"])
	f.cbOtherRecipes:SetPoint("LEFT", f.cbTrainer.text, "RIGHT", 12, 0)

	f.cbVendorScrolls = MakeCheck(L["PLANNER_INCLUDE_VENDOR"], "includeVendorRecipesInRoute", 140, L["PLANNER_INCLUDE_VENDOR_TIP"])
	f.cbVendorScrolls:SetPoint("TOPLEFT", f.cbTrainer, "BOTTOMLEFT", 0, 0)

	-- Кнопка сброса скрытых (исключённых) рецептов (размещена по центру внизу, чтобы не теснить переключатель режима)
	local resetSkips = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	resetSkips:SetSize(96, 20)
	resetSkips:SetPoint("BOTTOM", -4, 7)
	resetSkips:SetScript("OnClick", function()
		if ns.charDB then
			ns.charDB.skippedRecipes = {}
		end
		ns:RefreshRouteView()
	end)
	f.resetSkipsBtn = resetSkips

	-- Отдельные поля справа под приоритетом: 1) Затраты и 2) Расчётный возврат
	f.summaryText = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.summaryText:SetPoint("TOPRIGHT", -6, -28)
	f.summaryText:SetJustifyH("RIGHT")

	f.returnText = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.returnText:SetPoint("TOPRIGHT", -6, -48)
	f.returnText:SetJustifyH("RIGHT")

	-- Список шагов маршрута
	local listBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
	listBox:SetPoint("TOPLEFT", 8, -72)
	listBox:SetPoint("BOTTOMRIGHT", -8, 34)
	listBox:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	listBox:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
	listBox:SetBackdropBorderColor(0.42, 0.35, 0.22, 0.9)
	listBox:EnableMouseWheel(true)

	f.offset = 0
	f.steps = {}
	f.rows = {}

	listBox:SetScript("OnMouseWheel", function(_, delta)
		local maxOff = math.max(0, #f.steps - VISIBLE_ROWS)
		f.offset = math.max(0, math.min(maxOff, f.offset - delta))
		ns:RenderRouteRows()
	end)

	f.emptyLabel = listBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.emptyLabel:SetPoint("CENTER", 0, 0)
	f.emptyLabel:SetWidth(420)
	f.emptyLabel:SetText(L["PLANNER_EMPTY"])

	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Button", nil, listBox)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
		row:SetPoint("TOPRIGHT", -6, -4 - (i - 1) * ROW_H)

		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.bg:SetColorTexture(0.14, 0.12, 0.09, (i % 2 == 0) and 0.45 or 0.22)

		row.hl = row:CreateTexture(nil, "HIGHLIGHT")
		row.hl:SetAllPoints()
		row.hl:SetColorTexture(1, 0.82, 0.2, 0.14)

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(26, 26)
		row.icon:SetPoint("LEFT", 4, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		row.skipBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.skipBtn:SetSize(20, 20)
		row.skipBtn:SetPoint("RIGHT", -4, 0)
		row.skipBtn:SetText("X")
		row.skipBtn:SetScript("OnClick", function(self)
			local st = self:GetParent().stepData
			if st and st.recipeID and ns.charDB then
				ns.charDB.skippedRecipes[st.recipeID] = true
				ns:RefreshRouteView()
			end
		end)
		row.skipBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["PLANNER_BTN_SKIP"], 1, 0.82, 0, 1, true)
			GameTooltip:Show()
		end)
		row.skipBtn:SetScript("OnLeave", GameTooltip_Hide)

		row.queueBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.queueBtn:SetSize(66, 20)
		row.queueBtn:SetPoint("RIGHT", row.skipBtn, "LEFT", -3, 0)
		row.queueBtn:SetText(L["PLANNER_BTN_QUEUE_STEP"])
		row.queueBtn:SetScript("OnClick", function(self)
			local st = self:GetParent().stepData
			if st and st.kind == "craft" and st.recipeID then
				ns:QueueAddRecipe(st.recipeID, st.crafts or 1)
			end
		end)

		row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.cost:SetPoint("TOPRIGHT", row.queueBtn, "TOPLEFT", -6, 1)
		row.cost:SetJustifyH("RIGHT")

		row.ret = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.ret:SetPoint("BOTTOMRIGHT", row.queueBtn, "BOTTOMLEFT", -6, -1)
		row.ret:SetJustifyH("RIGHT")

		row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
		row.title:SetPoint("RIGHT", row.cost, "LEFT", -8, 0)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)

		row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
		row.sub:SetPoint("RIGHT", row.ret, "LEFT", -8, 0)
		row.sub:SetJustifyH("LEFT")
		row.sub:SetWordWrap(false)

		row:SetScript("OnClick", function(self)
			local st = self.stepData
			if not st then
				return
			end
			if st.recipeID and ns:HandleItemClick(nil, st.recipeID) then
				return
			end
			if st.itemID and ns:HandleItemClick(st.itemID, nil) then
				return
			end
			if st.recipeID and ns.SelectRecipeID then
				ns:SelectRecipeID(st.recipeID)
			end
		end)
		row:SetScript("OnEnter", function(self)
			local st = self.stepData
			if not st then
				return
			end
			if st.recipeID then
				ns:ShowRecipeTooltip(self, st.recipeID)
			elseif st.itemID then
				ns:ShowItemTooltip(self, st.itemID)
			end
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)

		f.rows[i] = row
	end

	-- Нижние кнопки массового добавления маршрута в очередь крафта
	local queueUntilBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	queueUntilBtn:SetSize(165, 24)
	queueUntilBtn:SetPoint("BOTTOMLEFT", 8, 5)
	queueUntilBtn:SetText(L["PLANNER_QUEUE_UNTIL_TRAIN"])
	queueUntilBtn:SetScript("OnClick", function()
		for _, st in ipairs(f.steps) do
			if st.kind ~= "craft" or (st.learnFee and st.learnFee > 0) or st.scrollItemID then
				break
			end
			ns:QueueAddRecipe(st.recipeID, st.crafts or 1, nil, true)
		end
		ns:OnQueueUpdated()
	end)

	local queueAllBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	queueAllBtn:SetSize(175, 24)
	queueAllBtn:SetPoint("BOTTOMRIGHT", -8, 5)
	queueAllBtn:SetText(L["PLANNER_QUEUE_ALL"])
	queueAllBtn:SetScript("OnClick", function()
		for _, st in ipairs(f.steps) do
			if st.kind == "craft" and st.recipeID then
				ns:QueueAddRecipe(st.recipeID, st.crafts or 1, nil, true)
			end
		end
		ns:OnQueueUpdated()
	end)

	self.routeView = f
	return f
end

function ns:RenderRouteRows()
	local f = self.routeView
	if not f then
		return
	end
	local steps = f.steps or {}
	f.emptyLabel:SetShown(#steps == 0)

	for i = 1, VISIBLE_ROWS do
		local row = f.rows[i]
		local st = steps[i + f.offset]
		row.stepData = st
		if st then
			row:Show()
			if st.kind == "craft" then
				local name, icon = self:GetRecipeDisplay(st.recipeID)
				local dc = self.DIFFICULTY_COLORS[st.colorKey or "orange"] or self.DIFFICULTY_COLORS.orange
				row.icon:SetTexture(icon)
				row.title:SetText(dc.hex .. name .. "|r")
				local subText = string.format(L["PLANNER_STEP_CRAFT"], st.fromSkill, st.toSkill, st.crafts or 1, st.avgChance or 100)
				if st.isVendorScroll and st.learnFee and st.learnFee > 0 then
					subText = subText .. " | |cff66d9ff" .. string.format(L["PLANNER_STEP_VENDOR_SCROLL"], st.reqSkill or 1, ns.FormatMoney(st.learnFee)) .. "|r"
				elseif st.isVendorScroll then
					subText = subText .. " | |cff66d9ff" .. string.format(L["PLANNER_STEP_VENDOR_SCROLL_FREE"], st.reqSkill or 1) .. "|r"
				elseif st.scrollItemID and st.learnFee and st.learnFee > 0 then
					subText = subText .. " | |cffffd100" .. string.format(L["PLANNER_STEP_SCROLL_AH"], st.reqSkill or 1, ns.FormatMoney(st.learnFee)) .. "|r"
				elseif st.scrollItemID then
					subText = subText .. " | |cff88ccff" .. string.format(L["PLANNER_STEP_SCROLL"], st.reqSkill or 1) .. "|r"
				elseif st.learnFee and st.learnFee > 0 then
					subText = subText .. " | |cffffd100" .. string.format(L["PLANNER_STEP_LEARN"], st.reqSkill or 1, ns.FormatMoney(st.learnFee)) .. "|r"
				end
				if st.lowStock then
					subText = subText .. " | " .. L["PLANNER_LOW_STOCK"]
				end
				row.sub:SetText(subText)
				row.cost:SetText(ns.FormatMoney(st.grossCost or st.stepCost))
				if st.returnVal and st.returnVal > 0 then
					row.ret:SetText("|cff40ff40+" .. ns.FormatMoney(st.returnVal) .. "|r")
				else
					row.ret:SetText("")
				end
				row.queueBtn:Show()
				row.skipBtn:Show()
			else
				row.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
				row.title:SetText("|cffffd100" .. (st.title or "") .. "|r")
				row.sub:SetText("")
				row.cost:SetText(st.fee and st.fee > 0 and ns.FormatMoney(st.fee) or "")
				row.ret:SetText("")
				row.queueBtn:Hide()
				row.skipBtn:Hide()
			end
		else
			row:Hide()
		end
	end
end

function ns:RefreshRouteView()
	local f = self.routeView
	if not f or not f:IsVisible() then
		return
	end
	local sl = self.currentSkillLine
	local prof = sl and self.playerProfessions[sl]
	local curRank = (prof and prof.rank) or 1
	local maxCap = (prof and prof.maxRank) or 75
	local defaultGoal = (curRank < maxCap and maxCap) or math.min(300, maxCap + 75)
	local target = (sl and self.charDB and self.charDB.targets and self.charDB.targets[sl]) or defaultGoal
	if target <= curRank and curRank < 300 then
		target = math.min(300, defaultGoal)
	end

	if not f.targetBox:HasFocus() then
		f.targetBox:SetText(tostring(target))
	end
	local opts = (self.db and self.db.options) or {}
	f.cbTrainer:SetChecked(opts.includeTrainerInRoute ~= false)
	f.cbVendorScrolls:SetChecked(opts.includeVendorRecipesInRoute ~= false)
	f.cbOtherRecipes:SetChecked(opts.includeOtherRecipesInRoute == true)
	local prio = opts.routePriority or "speed"
	f.priorityBtn:SetText(prio == "profit" and L["PLANNER_PRIORITY_PROFIT"] or L["PLANNER_PRIORITY_SPEED"])

	local skipCount = 0
	local skipParts = {}
	for rid in pairs((self.charDB and self.charDB.skippedRecipes) or {}) do
		skipCount = skipCount + 1
		skipParts[skipCount] = tostring(rid)
	end
	if skipCount > 1 then
		table.sort(skipParts)
	end
	f.resetSkipsBtn:SetText(string.format(L["PLANNER_RESET_SKIPS"], skipCount))
	f.resetSkipsBtn:SetShown(skipCount > 0)

	local routeKey = table.concat({
		tostring(sl or 0),
		tostring(curRank),
		tostring(maxCap),
		tostring(target),
		tostring(self.GetPriceRevision and self:GetPriceRevision() or 0),
		tostring(self.invRev or 0),
		tostring(opts.includeTrainerInRoute ~= false),
		tostring(opts.includeVendorRecipesInRoute ~= false),
		tostring(opts.includeOtherRecipesInRoute == true),
		tostring(UnitFactionGroup and UnitFactionGroup("player") or ""),
		tostring(opts.deductVendorInRoute ~= false),
		tostring(prio),
		tostring(opts.checkAuctionStock == true),
		table.concat(skipParts, ","),
	}, "|")
	local route = f._cachedRoute
	if f._cachedRouteKey ~= routeKey or not route then
		route = self:BuildLevelingRoute(sl, curRank, target)
		f._cachedRouteKey = routeKey
		f._cachedRoute = route
	end
	f.steps = route.steps or {}
	local maxOff = math.max(0, #f.steps - VISIBLE_ROWS)
	if f.offset > maxOff then
		f.offset = maxOff
	end
	local sumTxt = string.format(L["PLANNER_TOTAL_COST"], ns.FormatMoney(route.grossCost or route.totalCost or 0))
	if route.stoppedAt and route.stoppedAt < target then
		sumTxt = sumTxt .. " |cffff8040(" .. string.format(L["PLANNER_INCOMPLETE"], route.stoppedAt, target) .. ")|r"
	end
	f.summaryText:SetText(sumTxt)
	if f.returnText then
		f.returnText:SetText(string.format(L["PLANNER_TOTAL_RETURN"], ns.FormatMoney(route.totalReturn or 0)))
	end
	self:RenderRouteRows()
end

