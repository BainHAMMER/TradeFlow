local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- 1. Синхронизация списков закупок в Auctionator (как в SkillUp)
-- 2. Панель и кнопка «Докупить по списку» в окне торговца (MERCHANT_SHOW)
-------------------------------------------------------------------------------
local lastSyncedSignature = nil
local vendorBar = nil

function ns:GetAuctionatorListName()
	return "TradeFlow: " .. self:CharKey()
end

-- Гарантирует загрузку реальных названий предметов по itemID перед вызовом Auctionator API
local function WithLoadedItemNames(items, callback)
	if #items == 0 then
		callback()
		return
	end
	if ContinuableContainer and Item and Item.CreateFromItemID then
		local container = ContinuableContainer:Create()
		for _, entry in ipairs(items) do
			container:AddContinuable(Item:CreateFromItemID(entry.itemID))
		end
		container:ContinueOnLoad(callback)
		return
	end
	local allLoaded = true
	for _, entry in ipairs(items) do
		local _, _, _, _, loaded = ns:GetItemDisplay(entry.itemID)
		if not loaded then
			allLoaded = false
		end
	end
	if allLoaded then
		callback()
	elseif C_Timer and C_Timer.After then
		C_Timer.After(0.25, callback)
	end
end

-- Автоматическое создание / обновление / удаление Shopping List в Auctionator
function ns:SyncAuctionatorShoppingList(silent)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
		if not silent then
			self:Print(L["ATR_NOT_FOUND"])
		end
		return
	end

	local shopping = self:GetShoppingList()
	local ahItems = {}
	local sigParts = {}
	for _, item in ipairs(shopping) do
		if item.source ~= "vendor" and item.missing > 0 then
			ahItems[#ahItems + 1] = item
			sigParts[#sigParts + 1] = item.itemID .. ":" .. item.missing
		end
	end

	local sig = table.concat(sigParts, ",")
	if silent and sig == lastSyncedSignature then
		return
	end

	local listName = self:GetAuctionatorListName()
	if #ahItems == 0 then
		lastSyncedSignature = sig
		if api.GetShoppingListItems and api.DeleteShoppingList then
			local ok, existing = pcall(api.GetShoppingListItems, ADDON_NAME, listName)
			if ok and existing then
				pcall(api.DeleteShoppingList, ADDON_NAME, listName)
			end
		end
		return
	end

	WithLoadedItemNames(ahItems, function()
		local searches = {}
		for _, item in ipairs(ahItems) do
			local name, _, _, _, loaded = self:GetItemDisplay(item.itemID)
			if loaded and name then
				local ok, str = pcall(api.ConvertToSearchString, ADDON_NAME, {
					searchString = name,
					isExact = true,
					quantity = item.missing,
				})
				if ok and str then
					searches[#searches + 1] = str
				end
			end
		end
		if #searches > 0 then
			lastSyncedSignature = sig
			pcall(api.CreateShoppingList, ADDON_NAME, listName, searches)
			if not silent then
				self:Print(string.format(L["ATR_SYNCED_MSG"], listName, #searches))
			end
		end
	end)
end

-- Живой поиск недостающих реагентов в открытом окне аукциона через Auctionator
function ns:SearchShoppingListOnAH()
	self:SyncAuctionatorShoppingList(false)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not api then
		return
	end
	local ahOpen = (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
	if not ahOpen then
		self:Print(L["AH_NOT_OPEN"])
		return
	end

	local shopping = self:GetShoppingList()
	local ahItems = {}
	for _, item in ipairs(shopping) do
		if item.source ~= "vendor" and item.missing > 0 then
			ahItems[#ahItems + 1] = item
		end
	end
	if #ahItems == 0 then
		return
	end

	WithLoadedItemNames(ahItems, function()
		local advanced, names = {}, {}
		for _, item in ipairs(ahItems) do
			local name, _, _, _, loaded = self:GetItemDisplay(item.itemID)
			if loaded and name then
				names[#names + 1] = name
				advanced[#advanced + 1] = {
					searchString = name,
					isExact = true,
					quantity = item.missing,
				}
			end
		end
		if api.MultiSearchAdvanced and #advanced > 0 then
			pcall(api.MultiSearchAdvanced, ADDON_NAME, advanced)
		elseif api.MultiSearchExact and #names > 0 then
			pcall(api.MultiSearchExact, ADDON_NAME, names)
		end
	end)
end

-------------------------------------------------------------------------------
-- Панель и кнопка «Докупить по списку» у торговца (MERCHANT_SHOW)
-------------------------------------------------------------------------------
local function CollectMerchantMatches()
	if not (MerchantFrame and MerchantFrame:IsShown() and GetMerchantNumItems and GetMerchantItemInfo) then
		return {}, 0
	end
	local shopping = ns:GetShoppingList()
	local needByItem = {}
	for _, item in ipairs(shopping) do
		if item.missing > 0 then
			needByItem[item.itemID] = item.missing
		end
	end
	if not next(needByItem) then
		return {}, 0
	end

	local matches = {}
	local totalCopper = 0
	local numMerchant = GetMerchantNumItems() or 0

	for slot = 1, numMerchant do
		local link = GetMerchantItemLink and GetMerchantItemLink(slot)
		local itemID = link and tonumber(link:match("item:(%d+)"))
		local missing = itemID and needByItem[itemID]
		if missing and missing > 0 then
			local _, _, price, stackSize, numAvailable = GetMerchantItemInfo(slot)
			stackSize = math.max(1, stackSize or 1)
			if numAvailable ~= 0 then
				local canBuyUnits = missing
				if numAvailable and numAvailable > 0 then
					canBuyUnits = math.min(missing, numAvailable * stackSize)
				end
				local batches = math.ceil(canBuyUnits / stackSize)
				if batches > 0 then
					matches[#matches + 1] = {
						slot = slot,
						itemID = itemID,
						units = canBuyUnits,
						batches = batches,
						stackSize = stackSize,
						cost = batches * (price or 0),
					}
					totalCopper = totalCopper + batches * (price or 0)
				end
			end
		end
	end

	return matches, totalCopper
end

function ns:BuyVendorShoppingList()
	local matches = CollectMerchantMatches()
	if #matches == 0 then
		return
	end
	local maxStackFn = GetMerchantItemMaxStack
	for _, m in ipairs(matches) do
		local remainingBatches = m.batches
		local maxBatch = (maxStackFn and maxStackFn(m.slot)) or 20
		maxBatch = math.max(1, maxBatch)
		while remainingBatches > 0 do
			local buyNow = math.min(remainingBatches, maxBatch)
			BuyMerchantItem(m.slot, buyNow)
			remainingBatches = remainingBatches - buyNow
		end
		local name = self:GetItemDisplay(m.itemID)
		self:Print(string.format(L["VENDOR_BOUGHT_MSG"], name, m.batches * m.stackSize))
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.3, function()
			ns:ScanBagsNow()
			ns:RefreshVendorBar()
		end)
	end
end

function ns:RefreshVendorBar()
	if not (MerchantFrame and MerchantFrame:IsShown()) then
		if vendorBar then
			vendorBar:Hide()
		end
		return
	end

	local matches, totalCopper = CollectMerchantMatches()
	if #matches == 0 then
		if vendorBar then
			vendorBar:Hide()
		end
		return
	end

	if not vendorBar then
		vendorBar = CreateFrame("Frame", "TradeFlowVendorBar", MerchantFrame, "BackdropTemplate")
		vendorBar:SetHeight(36)
		vendorBar:SetPoint("BOTTOMLEFT", MerchantFrame, "TOPLEFT", 0, 4)
		vendorBar:SetPoint("BOTTOMRIGHT", MerchantFrame, "TOPRIGHT", 0, 4)
		vendorBar:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		vendorBar:SetBackdropColor(0.08, 0.07, 0.05, 0.96)
		vendorBar:SetBackdropBorderColor(0.78, 0.60, 0.22, 1)

		vendorBar.label = vendorBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		vendorBar.label:SetPoint("LEFT", 10, 0)
		vendorBar.label:SetJustifyH("LEFT")

		vendorBar.btn = CreateFrame("Button", nil, vendorBar, "UIPanelButtonTemplate")
		vendorBar.btn:SetSize(150, 24)
		vendorBar.btn:SetPoint("RIGHT", -8, 0)
		vendorBar.btn:SetScript("OnClick", function()
			ns:BuyVendorShoppingList()
		end)
		vendorBar.btn:SetScript("OnEnter", function(self)
			local curMatches = CollectMerchantMatches()
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["VENDOR_BUY_BTN"], 1, 0.82, 0)
			for _, m in ipairs(curMatches) do
				local name, _, _, _, _, hex = ns:GetItemDisplay(m.itemID)
				GameTooltip:AddDoubleLine(
					(hex or "|cffffffff") .. name .. "|r x" .. (m.batches * m.stackSize),
					ns.FormatMoney(m.cost),
					1, 1, 1, 1, 1, 1
				)
			end
			GameTooltip:Show()
		end)
		vendorBar.btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	vendorBar.label:SetText(string.format(L["VENDOR_BAR_TITLE"], #matches, ns.FormatMoney(totalCopper)))
	vendorBar.btn:SetText(L["VENDOR_BUY_BTN"])
	vendorBar:Show()
end

function ns:OnMerchantShow()
	self:RefreshVendorBar()
end

