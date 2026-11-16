local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Нижняя правая панель: вкладки «Очередь крафта» и «Список покупок»
-------------------------------------------------------------------------------
local ROW_H = 30
local VISIBLE_ROWS = 6

function ns:CreateQueueAndShoppingView(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints()

	-- Кнопки переключения вкладок (Очередь крафта / Список покупок)
	local tabQueue = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	tabQueue:SetSize(175, 22)
	tabQueue:SetPoint("TOPLEFT", 8, -6)
	f.tabQueue = tabQueue

	local tabShop = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	tabShop:SetSize(175, 22)
	tabShop:SetPoint("LEFT", tabQueue, "RIGHT", 6, 0)
	f.tabShop = tabShop

	f.activeMode = "queue" -- "queue" | "shopping"

	local function SelectMode(mode)
		f.activeMode = mode
		f.offset = 0
		ns:RefreshQueueAndShoppingView()
	end
	tabQueue:SetScript("OnClick", function() SelectMode("queue") end)
	tabShop:SetScript("OnClick", function() SelectMode("shopping") end)

	-- Область прокрутки строк
	local listBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
	listBox:SetPoint("TOPLEFT", 8, -32)
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
	f.rows = {}

	listBox:SetScript("OnMouseWheel", function(_, delta)
		local count = (f.activeMode == "queue") and #ns:GetQueue() or #(f.shoppingCache or {})
		local maxOff = math.max(0, count - VISIBLE_ROWS)
		f.offset = math.max(0, math.min(maxOff, f.offset - delta))
		ns:RenderQueueOrShoppingRows()
	end)

	f.emptyLabel = listBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	f.emptyLabel:SetPoint("CENTER", 0, 0)
	f.emptyLabel:SetWidth(420)

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
		row.icon:SetSize(24, 24)
		row.icon:SetPoint("LEFT", 4, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
		row.title:SetPoint("RIGHT", -130, 0)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)

		row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
		row.sub:SetPoint("RIGHT", -90, 0)
		row.sub:SetJustifyH("LEFT")
		row.sub:SetWordWrap(false)

		row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.delBtn:SetSize(20, 20)
		row.delBtn:SetPoint("RIGHT", -4, 0)
		row.delBtn:SetText("X")
		row.delBtn:SetScript("OnClick", function(self)
			local idx = self:GetParent().queueIndex
			if idx then
				ns:QueueRemoveIndex(idx)
			end
		end)

		row.downBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.downBtn:SetSize(20, 20)
		row.downBtn:SetPoint("RIGHT", row.delBtn, "LEFT", -2, 0)
		row.downBtn:SetText("v")
		row.downBtn:SetScript("OnClick", function(self)
			local idx = self:GetParent().queueIndex
			if idx then
				ns:QueueMove(idx, 1)
			end
		end)

		row.upBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.upBtn:SetSize(20, 20)
		row.upBtn:SetPoint("RIGHT", row.downBtn, "LEFT", -2, 0)
		row.upBtn:SetText("^")
		row.upBtn:SetScript("OnClick", function(self)
			local idx = self:GetParent().queueIndex
			if idx then
				ns:QueueMove(idx, -1)
			end
		end)

		row.rightText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.rightText:SetPoint("RIGHT", row.upBtn, "LEFT", -6, 0)
		row.rightText:SetJustifyH("RIGHT")

		row:SetScript("OnClick", function(self)
			if IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP") or IsShiftKeyDown() or IsControlKeyDown()) then
				if self.itemID and ns:HandleItemClick(self.itemID, self.recipeID) then
					return
				end
				if self.recipeID and ns:HandleItemClick(nil, self.recipeID) then
					return
				end
			end
			if self.recipeID and ns.SelectRecipeID then
				ns:SelectRecipeID(self.recipeID)
			elseif self.itemID and f.activeMode == "shopping" and MerchantFrame and MerchantFrame:IsShown() and ns.BuyVendorShoppingList then
				ns:BuyVendorShoppingList(self.itemID)
			end
		end)
		row:SetScript("OnEnter", function(self)
			if self.recipeID then
				ns:ShowRecipeTooltip(self, self.recipeID)
			elseif self.itemID then
				ns:ShowItemTooltip(self, self.itemID)
			end
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)

		f.rows[i] = row
	end

	-- Нижняя панель кнопок режима «Очередь»
	local processBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	processBtn:SetSize(180, 24)
	processBtn:SetPoint("BOTTOMLEFT", 8, 5)
	processBtn:SetScript("OnClick", function()
		ns:ProcessQueue()
	end)
	f.processBtn = processBtn

	local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	clearBtn:SetSize(110, 24)
	clearBtn:SetPoint("LEFT", processBtn, "RIGHT", 6, 0)
	clearBtn:SetText(L["QUEUE_CLEAR"])
	clearBtn:SetScript("OnClick", function()
		ns:QueueClear()
	end)
	f.clearBtn = clearBtn

	-- Нижняя панель кнопок режима «Список покупок»
	local shopTotal = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	shopTotal:SetPoint("BOTTOMLEFT", 10, 11)
	shopTotal:SetJustifyH("LEFT")
	f.shopTotal = shopTotal

	local searchAHBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	searchAHBtn:SetSize(110, 24)
	searchAHBtn:SetPoint("BOTTOMRIGHT", -8, 5)
	searchAHBtn:SetText(L["BTN_SEARCH_AH"])
	searchAHBtn:SetScript("OnClick", function()
		ns:SearchShoppingListOnAH()
	end)
	f.searchAHBtn = searchAHBtn

	local syncAtrBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	syncAtrBtn:SetSize(145, 24)
	syncAtrBtn:SetPoint("RIGHT", searchAHBtn, "LEFT", -4, 0)
	syncAtrBtn:SetText(L["BTN_SYNC_ATR"])
	syncAtrBtn:SetScript("OnClick", function()
		ns:SyncAuctionatorShoppingList(false)
	end)
	f.syncAtrBtn = syncAtrBtn

	local buyVendorBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	buyVendorBtn:SetSize(145, 24)
	buyVendorBtn:SetPoint("RIGHT", syncAtrBtn, "LEFT", -4, 0)
	buyVendorBtn:SetText(L["VENDOR_BUY_BTN"])
	buyVendorBtn:SetScript("OnClick", function()
		if ns.BuyVendorShoppingList then
			ns:BuyVendorShoppingList()
		end
	end)
	buyVendorBtn:Hide()
	f.buyVendorBtn = buyVendorBtn

	local withdrawBankBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	withdrawBankBtn:SetSize(145, 24)
	withdrawBankBtn:SetPoint("RIGHT", syncAtrBtn, "LEFT", -4, 0)
	withdrawBankBtn:SetText(L["BANK_WITHDRAW_BTN"])
	withdrawBankBtn:SetScript("OnClick", function()
		if ns.WithdrawBankShoppingList then
			ns:WithdrawBankShoppingList()
		end
	end)
	withdrawBankBtn:Hide()
	f.withdrawBankBtn = withdrawBankBtn

	local learnTrainerBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	learnTrainerBtn:SetSize(155, 24)
	learnTrainerBtn:SetPoint("BOTTOMRIGHT", -8, 5)
	learnTrainerBtn:SetText(L["TRAINER_LEARN_BTN"])
	learnTrainerBtn:SetScript("OnClick", function()
		if ns.LearnQueuedTrainerRecipes then
			ns:LearnQueuedTrainerRecipes()
		end
	end)
	learnTrainerBtn:Hide()
	f.learnTrainerBtn = learnTrainerBtn

	self.queueView = f
	return f
end

function ns:RenderQueueOrShoppingRows()
	local f = self.queueView
	if not f then
		return
	end

	if f.activeMode == "queue" then
		local queue = self:GetQueue()
		f.emptyLabel:SetText(L["QUEUE_EMPTY"])
		f.emptyLabel:SetShown(#queue == 0)

		for i = 1, VISIBLE_ROWS do
			local row = f.rows[i]
			local qIdx = i + f.offset
			local step = queue[qIdx]
			row.queueIndex = step and qIdx or nil
			row.recipeID = step and step.recipeID or nil
			row.itemID = nil

			if step then
				row:Show()
				row.upBtn:Show()
				row.downBtn:Show()
				row.delBtn:Show()
				row.rightText:ClearAllPoints()
				row.rightText:SetPoint("RIGHT", row.upBtn, "LEFT", -6, 0)

				local name, icon, outItemID, _, _, hex = self:GetRecipeDisplay(step.recipeID)
				row.itemID = outItemID
				row.icon:SetTexture(icon)

				local prefix = step.isSubcraft and L["QUEUE_SUBCRAFT_BADGE"] or ""
				row.title:SetText(string.format("%s%s%s|r |cffffd100x%d|r", prefix, hex or "|cffffffff", name, step.count or 1))

				local rec = self:GetRecipeRecord(step.recipeID)
				local stepSL = (rec and rec.skillLine) or step.skillLine
				if stepSL then
					step.skillLine = stepSL
				end
				local readyCrafts, state = self:GetQueueStepStatus(step)
				local statusStr
				if state == "ready" then
					statusStr = string.format(L["QUEUE_STATUS_READY"], readyCrafts)
				elseif state == "partial" then
					statusStr = string.format(L["QUEUE_STATUS_PARTIAL"], readyCrafts, step.count)
				elseif state == "other_prof" then
					statusStr = string.format(L["QUEUE_STATUS_OTHER_PROF"], self:GetProfessionName(stepSL))
				elseif state == "unlearned" then
					statusStr = L["QUEUE_STATUS_UNLEARNED"]
				else
					statusStr = L["QUEUE_STATUS_WAIT"]
				end
				row.sub:SetText(statusStr)
				row.rightText:SetText(self:GetProfessionName(stepSL))
			else
				row:Hide()
			end
		end
	else
		local list = f.shoppingCache or {}
		f.emptyLabel:SetText(L["SHOPPING_EMPTY"])
		f.emptyLabel:SetShown(#list == 0)

		for i = 1, VISIBLE_ROWS do
			local row = f.rows[i]
			local item = list[i + f.offset]
			row.queueIndex = nil
			row.recipeID = nil
			row.itemID = item and item.itemID or nil

			if item then
				row:Show()
				row.upBtn:Hide()
				row.downBtn:Hide()
				row.delBtn:Hide()
				row.rightText:ClearAllPoints()
				row.rightText:SetPoint("RIGHT", -8, 0)

				-- Отображение реального предмета из клиента по его itemID
				local name, icon, _, _, _, hex = self:GetItemDisplay(item.itemID)
				row.icon:SetTexture(icon)
				row.title:SetText(string.format("%s%s|r |cffff6666x%d|r", hex or "|cffffffff", name, item.missing))

				local altText = ""
				if item.altTotal and item.altTotal > 0 and item.alts and item.alts[1] then
					altText = string.format(L["SHOPPING_ALT_INFO"], item.altTotal, item.alts[1].name)
				end
				local srcLabel = (item.source == "vendor" and ("|cff40ff40" .. L["SOURCE_VENDOR"] .. "|r"))
					or (item.source == "ah" and ("|cffffd100" .. L["SOURCE_AH"] .. "|r"))
					or ("|cffaaaaaa" .. L["SOURCE_UNKNOWN"] .. "|r")

				row.sub:SetText(string.format(
					L["SHOPPING_ROW_DETAIL"],
					item.need,
					item.inBags,
					item.inBank,
					altText,
					srcLabel,
					ns.FormatMoney(item.unitPrice)
				))
				row.rightText:SetText(ns.FormatMoney(item.totalCost))
			else
				row:Hide()
			end
		end
	end
end

function ns:RefreshQueueAndShoppingView()
	local f = self.queueView
	if not f or not f:IsVisible() then
		return
	end

	local queue = self:GetQueue()
	local shopping, totalShopCost = self:GetShoppingList()
	f.shoppingCache = shopping

	f.tabQueue:SetText(string.format(L["TAB_QUEUE"], #queue))
	f.tabShop:SetText(string.format(L["TAB_SHOPPING"], #shopping))

	local isQueue = (f.activeMode == "queue")
	local vendorMatches = (self.GetMerchantShoppingMatches and self:GetMerchantShoppingMatches()) or {}
	local hasVendorMatches = (#vendorMatches > 0)
	local bankMatches = (self.GetBankShoppingMatches and self:GetBankShoppingMatches()) or {}
	local hasBankMatches = (#bankMatches > 0)
	local trainerMatches = (self.GetTrainerQueueMatches and self:GetTrainerQueueMatches()) or {}
	local hasTrainerMatches = (#trainerMatches > 0)

	f.processBtn:SetShown(isQueue)
	f.clearBtn:SetShown(isQueue)
	f.shopTotal:SetShown(not isQueue)
	f.syncAtrBtn:SetShown(not isQueue)
	f.searchAHBtn:SetShown(not isQueue)

	if f.buyVendorBtn then
		f.buyVendorBtn:ClearAllPoints()
		if isQueue then
			f.buyVendorBtn:SetPoint("BOTTOMRIGHT", -8, 5)
		else
			f.buyVendorBtn:SetPoint("RIGHT", f.syncAtrBtn, "LEFT", -4, 0)
		end
		f.buyVendorBtn:SetShown(hasVendorMatches)
	end

	if f.withdrawBankBtn then
		f.withdrawBankBtn:ClearAllPoints()
		if isQueue then
			f.withdrawBankBtn:SetPoint("BOTTOMRIGHT", -8, 5)
		else
			f.withdrawBankBtn:SetPoint("RIGHT", f.syncAtrBtn, "LEFT", -4, 0)
		end
		f.withdrawBankBtn:SetShown(hasBankMatches and not hasVendorMatches)
	end

	if f.learnTrainerBtn then
		f.learnTrainerBtn:ClearAllPoints()
		if isQueue then
			f.learnTrainerBtn:SetPoint("BOTTOMRIGHT", -8, 5)
		else
			f.learnTrainerBtn:SetPoint("RIGHT", f.syncAtrBtn, "LEFT", -4, 0)
		end
		f.learnTrainerBtn:SetShown(hasTrainerMatches and not hasVendorMatches and not hasBankMatches)
	end

	if isQueue then
		local switchProf = nil
		local canCraftAny = false
		for _, step in ipairs(queue) do
			local ready, state = self:GetQueueStepStatus(step)
			if ready > 0 then
				if state == "other_prof" then
					switchProf = step.skillLine
				elseif state == "ready" or state == "partial" then
					canCraftAny = true
				end
				break
			end
		end
		if switchProf then
			f.processBtn:SetText(string.format(L["QUEUE_SWITCH_PROF"], self:GetProfessionName(switchProf)))
			f.processBtn:SetEnabled(true)
		else
			f.processBtn:SetText(L["QUEUE_PROCESS"])
			f.processBtn:SetEnabled(canCraftAny)
		end
		f.clearBtn:SetEnabled(#queue > 0)
	else
		f.shopTotal:SetText(string.format(L["SHOPPING_TOTAL"], ns.FormatMoney(totalShopCost)))
	end

	self:RenderQueueOrShoppingRows()
end

