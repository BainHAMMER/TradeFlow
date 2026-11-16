local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- 1. Синхронизация списков закупок в Auctionator (как в SkillUp)
-- 2. Панель и кнопка «Докупить по списку» в окне торговца (MERCHANT_SHOW)
-------------------------------------------------------------------------------
local lastSyncedSignature = nil
local vendorBar = nil
local bankBar = nil
local trainerBar = nil

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
-- Панель и кнопка «Докупить по списку» у торговца (MERCHANT_SHOW / C_MerchantFrame)
-------------------------------------------------------------------------------
local function GetMerchantSlotItemID(slot)
	if GetMerchantItemID then
		local id = GetMerchantItemID(slot)
		if id and id > 0 then
			return id
		end
	end
	if GetMerchantItemLink then
		local link = GetMerchantItemLink(slot)
		local id = link and tonumber(link:match("item:(%d+)"))
		if id and id > 0 then
			return id
		end
	end
	return nil
end

local function GetMerchantSlotInfo(slot)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(slot)
		if info then
			local canBuy = (info.isPurchasable ~= false) and not info.hasExtendedCost
			return info.price or 0, math.max(1, info.stackCount or 1), info.numAvailable or -1, canBuy
		end
	elseif GetMerchantItemInfo then
		local _, _, price, stackSize, numAvailable, isPurchasable, _, extendedCost = GetMerchantItemInfo(slot)
		local canBuy = (isPurchasable ~= false) and not extendedCost
		return price or 0, math.max(1, stackSize or 1), numAvailable or -1, canBuy
	end
	return nil
end

local function CollectMerchantMatches()
	if not (MerchantFrame and MerchantFrame:IsShown() and GetMerchantNumItems) then
		return {}, 0
	end
	local numMerchant = GetMerchantNumItems() or 0
	if numMerchant <= 0 then
		return {}, 0
	end

	-- Записываем живые цены вендора в базу при посещении торговца
	for slot = 1, numMerchant do
		local itemID = GetMerchantSlotItemID(slot)
		local price, stackSize, numAvailable, canBuy = GetMerchantSlotInfo(slot)
		if itemID and price and price > 0 and canBuy and numAvailable == -1 and ns.db and ns.db.vendorPrices then
			ns.db.vendorPrices[itemID] = math.floor(price / math.max(1, stackSize) + 0.5)
		end
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

	for slot = 1, numMerchant do
		local itemID = GetMerchantSlotItemID(slot)
		local missing = itemID and needByItem[itemID]
		if missing and missing > 0 then
			local price, stackSize, numAvailable, canBuy = GetMerchantSlotInfo(slot)
			if price and canBuy and numAvailable ~= 0 then
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
						cost = batches * price,
					}
					totalCopper = totalCopper + batches * price
				end
			end
		end
	end

	return matches, totalCopper
end

function ns:GetMerchantShoppingMatches()
	return CollectMerchantMatches()
end

function ns:BuyVendorShoppingList(onlyItemID)
	local matches = CollectMerchantMatches()
	if #matches == 0 then
		return
	end
	local maxStackFn = GetMerchantItemMaxStack
	for _, m in ipairs(matches) do
		if not onlyItemID or m.itemID == onlyItemID then
			if m.stackSize > 1 then
				-- Для предметов, продающихся пачками (напр. по 5 шт), BuyMerchantItem(slot) без аргумента покупает 1 пачку
				for _ = 1, m.batches do
					BuyMerchantItem(m.slot)
				end
			else
				local remainingBatches = m.batches
				local maxBatch = (maxStackFn and maxStackFn(m.slot)) or 20
				maxBatch = math.max(1, maxBatch)
				while remainingBatches > 0 do
					local buyNow = math.min(remainingBatches, maxBatch)
					BuyMerchantItem(m.slot, buyNow)
					remainingBatches = remainingBatches - buyNow
				end
			end
			local name = self:GetItemDisplay(m.itemID)
			self:Print(string.format(L["VENDOR_BOUGHT_MSG"], name, m.batches * m.stackSize))
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.3, function()
			ns:ScanBagsNow()
			ns:RefreshVendorBar()
			if ns.RefreshQueueAndShoppingView then
				ns:RefreshQueueAndShoppingView()
			end
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
		vendorBar:SetHeight(38)
		vendorBar:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 0, -2)
		vendorBar:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", 0, -2)
		vendorBar:SetFrameStrata("DIALOG")
		vendorBar:SetToplevel(true)
		vendorBar:SetClampedToScreen(true)
		vendorBar:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		vendorBar:SetBackdropColor(0.08, 0.07, 0.05, 0.96)
		vendorBar:SetBackdropBorderColor(0.85, 0.68, 0.22, 1)

		vendorBar.label = vendorBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		vendorBar.label:SetPoint("LEFT", 10, 0)
		vendorBar.label:SetPoint("RIGHT", -150, 0)
		vendorBar.label:SetJustifyH("LEFT")
		vendorBar.label:SetWordWrap(false)

		vendorBar.btn = CreateFrame("Button", nil, vendorBar, "UIPanelButtonTemplate")
		vendorBar.btn:SetSize(140, 24)
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
	if self.RefreshQueueAndShoppingView then
		self:RefreshQueueAndShoppingView()
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.15, function()
			ns:RefreshVendorBar()
			if ns.RefreshQueueAndShoppingView then
				ns:RefreshQueueAndShoppingView()
			end
		end)
	end
end

local merchantEventFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"MERCHANT_SHOW",
	"MERCHANT_UPDATE",
	"MERCHANT_CLOSED",
	"BAG_UPDATE_DELAYED",
	"BANKFRAME_OPENED",
	"BANKFRAME_CLOSED",
	"PLAYERBANKSLOTS_CHANGED",
	"TRAINER_SHOW",
	"TRAINER_UPDATE",
	"TRAINER_CLOSED",
}) do
	pcall(merchantEventFrame.RegisterEvent, merchantEventFrame, ev)
end
merchantEventFrame:SetScript("OnEvent", function(_, event)
	if event == "MERCHANT_CLOSED" then
		if vendorBar then
			vendorBar:Hide()
		end
		if ns.RefreshQueueAndShoppingView then
			ns:RefreshQueueAndShoppingView()
		end
	elseif event == "BANKFRAME_CLOSED" then
		if bankBar then
			bankBar:Hide()
		end
		if ns.RefreshQueueAndShoppingView then
			ns:RefreshQueueAndShoppingView()
		end
	elseif event == "TRAINER_CLOSED" then
		if trainerBar then
			trainerBar:Hide()
		end
		if ns.RefreshQueueAndShoppingView then
			ns:RefreshQueueAndShoppingView()
		end
	elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
		ns:RefreshTrainerBar()
		if ns.RefreshQueueAndShoppingView then
			ns:RefreshQueueAndShoppingView()
		end
	elseif event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
		ns:RefreshBankBar()
		if ns.RefreshQueueAndShoppingView then
			ns:RefreshQueueAndShoppingView()
		end
	else
		ns:OnMerchantShow()
		if BankFrame and BankFrame:IsShown() then
			ns:RefreshBankBar()
		end
	end
end)

-------------------------------------------------------------------------------
-- Панель и кнопка «Забрать материалы» в окне банка (BANKFRAME_OPENED)
-------------------------------------------------------------------------------
local function CollectBankMatches()
	if not (BankFrame and BankFrame:IsShown()) then
		return {}
	end
	local shopping = ns:GetShoppingList()
	local needByItem = {}
	for _, item in ipairs(shopping) do
		if item.missing > 0 and item.inBank > 0 then
			needByItem[item.itemID] = math.min(item.missing, item.inBank)
		end
	end
	if not next(needByItem) then
		return {}
	end

	local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local GetID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	local GetInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
	if not GetNumSlots then
		return {}
	end

	local maxBag = NUM_BAG_SLOTS or 4
	local bankContainers = { -1 }
	for b = maxBag + 1, maxBag + (NUM_BANKBAGSLOTS or 7) do
		bankContainers[#bankContainers + 1] = b
	end

	local matchesByItem = {}
	local order = {}
	for _, bag in ipairs(bankContainers) do
		local slots = GetNumSlots(bag) or 0
		for slot = 1, slots do
			local itemID = GetID and GetID(bag, slot)
			local need = itemID and needByItem[itemID]
			if need and need > 0 then
				local count = 1
				if C_Container and C_Container.GetContainerItemInfo then
					local info = C_Container.GetContainerItemInfo(bag, slot)
					count = (info and info.stackCount) or 1
				elseif GetInfo then
					local _, c = GetInfo(bag, slot)
					count = c or 1
				end
				if not matchesByItem[itemID] then
					matchesByItem[itemID] = { itemID = itemID, need = need, totalTake = 0, slots = {} }
					order[#order + 1] = matchesByItem[itemID]
				end
				local entry = matchesByItem[itemID]
				local rem = entry.need - entry.totalTake
				if rem > 0 then
					local take = math.min(rem, count)
					entry.slots[#entry.slots + 1] = { bag = bag, slot = slot, count = count, take = take }
					entry.totalTake = entry.totalTake + take
				end
			end
		end
	end
	return order
end

function ns:GetBankShoppingMatches()
	return CollectBankMatches()
end

local function FindFreePlayerBagSlot()
	local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local GetID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	local GetFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	local maxBag = NUM_BAG_SLOTS or 4
	for bag = 0, maxBag do
		local free = GetFree and GetFree(bag)
		if not free or free > 0 then
			local slots = GetNumSlots and GetNumSlots(bag) or 0
			for slot = 1, slots do
				if not (GetID and GetID(bag, slot)) then
					return bag, slot
				end
			end
		end
	end
	return nil, nil
end

function ns:WithdrawBankShoppingList()
	local matches = CollectBankMatches()
	if #matches == 0 then
		return
	end
	local UseItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
	local SplitItem = (C_Container and C_Container.SplitContainerItem) or SplitContainerItem
	local PickupItem = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
	if not UseItem then
		return
	end
	if ClearCursor then
		ClearCursor()
	end

	for _, m in ipairs(matches) do
		local moved = 0
		for _, s in ipairs(m.slots) do
			if s.take >= s.count then
				pcall(UseItem, s.bag, s.slot)
				moved = moved + s.count
			elseif SplitItem and PickupItem then
				local dstBag, dstSlot = FindFreePlayerBagSlot()
				if dstBag and dstSlot then
					pcall(SplitItem, s.bag, s.slot, s.take)
					pcall(PickupItem, dstBag, dstSlot)
					moved = moved + s.take
				else
					pcall(UseItem, s.bag, s.slot)
					moved = moved + s.count
				end
			else
				pcall(UseItem, s.bag, s.slot)
				moved = moved + s.count
			end
		end
		if moved > 0 then
			local name = self:GetItemDisplay(m.itemID)
			self:Print(string.format(L["BANK_WITHDRAWN_MSG"], name, moved))
		end
	end

	if C_Timer and C_Timer.After then
		C_Timer.After(0.25, function()
			ns:ScanBagsNow()
			ns:RefreshBankBar()
			if ns.RefreshQueueAndShoppingView then
				ns:RefreshQueueAndShoppingView()
			end
		end)
	end
end

function ns:RefreshBankBar()
	if not (BankFrame and BankFrame:IsShown()) then
		if bankBar then
			bankBar:Hide()
		end
		return
	end

	local matches = CollectBankMatches()
	if #matches == 0 then
		if bankBar then
			bankBar:Hide()
		end
		return
	end

	if not bankBar then
		bankBar = CreateFrame("Frame", "TradeFlowBankBar", BankFrame, "BackdropTemplate")
		bankBar:SetHeight(38)
		bankBar:SetPoint("TOPLEFT", BankFrame, "BOTTOMLEFT", 0, -2)
		bankBar:SetPoint("TOPRIGHT", BankFrame, "BOTTOMRIGHT", 0, -2)
		bankBar:SetFrameStrata("DIALOG")
		bankBar:SetToplevel(true)
		bankBar:SetClampedToScreen(true)
		bankBar:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		bankBar:SetBackdropColor(0.08, 0.07, 0.05, 0.96)
		bankBar:SetBackdropBorderColor(0.45, 0.72, 0.95, 1)

		bankBar.label = bankBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		bankBar.label:SetPoint("LEFT", 10, 0)
		bankBar.label:SetPoint("RIGHT", -155, 0)
		bankBar.label:SetJustifyH("LEFT")
		bankBar.label:SetWordWrap(false)

		bankBar.btn = CreateFrame("Button", nil, bankBar, "UIPanelButtonTemplate")
		bankBar.btn:SetSize(145, 24)
		bankBar.btn:SetPoint("RIGHT", -8, 0)
		bankBar.btn:SetScript("OnClick", function()
			ns:WithdrawBankShoppingList()
		end)
		bankBar.btn:SetScript("OnEnter", function(self)
			local curMatches = CollectBankMatches()
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["BANK_WITHDRAW_BTN"], 1, 0.82, 0)
			for _, m in ipairs(curMatches) do
				local name, _, _, _, _, hex = ns:GetItemDisplay(m.itemID)
				GameTooltip:AddDoubleLine(
					(hex or "|cffffffff") .. name .. "|r",
					"x" .. m.totalTake,
					1, 1, 1, 0.4, 0.85, 1
				)
			end
			GameTooltip:Show()
		end)
		bankBar.btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	bankBar.label:SetText(string.format(L["BANK_BAR_TITLE"], #matches))
	bankBar.btn:SetText(L["BANK_WITHDRAW_BTN"])
	bankBar:Show()
end

-------------------------------------------------------------------------------
-- Панель и кнопка «Изучить из очереди» у тренера (TRAINER_SHOW)
-------------------------------------------------------------------------------
local function GetActiveTrainerFrame()
	if ClassTrainerFrame and ClassTrainerFrame:IsShown() then
		return ClassTrainerFrame
	end
	if TrainerFrame and TrainerFrame:IsShown() then
		return TrainerFrame
	end
	return nil
end

local function CollectTrainerMatches()
	local tf = GetActiveTrainerFrame()
	if not (tf and GetNumTrainerServices and GetTrainerServiceInfo) then
		return {}, 0
	end

	local queue = ns:GetQueue()
	local needLearn = {}
	local needByName = {}
	for _, step in ipairs(queue) do
		if step.recipeID and not ns:IsRecipeLearned(step.recipeID) and not needLearn[step.recipeID] then
			needLearn[step.recipeID] = true
			local rName = ns:GetRecipeDisplay(step.recipeID)
			if rName then
				needByName[rName] = step.recipeID
			end
		end
	end
	if not next(needLearn) then
		return {}, 0
	end

	local matches = {}
	local totalCopper = 0
	local num = GetNumTrainerServices() or 0
	for i = 1, num do
		local name, _, category = GetTrainerServiceInfo(i)
		if category == "available" then
			local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
			local spellID = link and tonumber(link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
			if not spellID and name and needByName[name] then
				spellID = needByName[name]
			end
			if spellID and needLearn[spellID] then
				local cost = (GetTrainerServiceCost and GetTrainerServiceCost(i)) or 0
				matches[#matches + 1] = {
					index = i,
					recipeID = spellID,
					name = name or ns:GetRecipeDisplay(spellID),
					cost = cost,
				}
				totalCopper = totalCopper + cost
			end
		end
	end
	return matches, totalCopper
end

function ns:GetTrainerQueueMatches()
	return CollectTrainerMatches()
end

function ns:LearnQueuedTrainerRecipes()
	local matches = CollectTrainerMatches()
	if #matches == 0 or not BuyTrainerService then
		return
	end
	-- Покупаем с конца списка, чтобы скрытие выученных строк не сдвигало индексы оставшихся
	for i = #matches, 1, -1 do
		local m = matches[i]
		pcall(BuyTrainerService, m.index)
		self:Print(string.format(L["TRAINER_LEARNED_MSG"], m.name or tostring(m.recipeID)))
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.25, function()
			if ns.ScanPlayerProfessions then
				ns:ScanPlayerProfessions()
			end
			ns:RefreshTrainerBar()
			if ns.RefreshVisibleUI then
				ns:RefreshVisibleUI()
			end
		end)
	end
end

function ns:RefreshTrainerBar()
	local tf = GetActiveTrainerFrame()
	if not tf then
		if trainerBar then
			trainerBar:Hide()
		end
		return
	end

	local matches, totalCopper = CollectTrainerMatches()
	if #matches == 0 then
		if trainerBar then
			trainerBar:Hide()
		end
		return
	end

	if not trainerBar then
		trainerBar = CreateFrame("Frame", "TradeFlowTrainerBar", tf, "BackdropTemplate")
		trainerBar:SetHeight(38)
		trainerBar:SetFrameStrata("DIALOG")
		trainerBar:SetToplevel(true)
		trainerBar:SetClampedToScreen(true)
		trainerBar:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		trainerBar:SetBackdropColor(0.08, 0.07, 0.05, 0.96)
		trainerBar:SetBackdropBorderColor(0.95, 0.78, 0.28, 1)

		trainerBar.label = trainerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		trainerBar.label:SetPoint("LEFT", 10, 0)
		trainerBar.label:SetPoint("RIGHT", -165, 0)
		trainerBar.label:SetJustifyH("LEFT")
		trainerBar.label:SetWordWrap(false)

		trainerBar.btn = CreateFrame("Button", nil, trainerBar, "UIPanelButtonTemplate")
		trainerBar.btn:SetSize(155, 24)
		trainerBar.btn:SetPoint("RIGHT", -8, 0)
		trainerBar.btn:SetScript("OnClick", function()
			ns:LearnQueuedTrainerRecipes()
		end)
		trainerBar.btn:SetScript("OnEnter", function(self)
			local curMatches = CollectTrainerMatches()
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["TRAINER_LEARN_BTN"], 1, 0.82, 0)
			for _, m in ipairs(curMatches) do
				GameTooltip:AddDoubleLine(m.name or ("#" .. m.recipeID), ns.FormatMoney(m.cost), 1, 1, 1, 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		trainerBar.btn:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	trainerBar:SetParent(tf)
	trainerBar:ClearAllPoints()
	trainerBar:SetPoint("TOPLEFT", tf, "BOTTOMLEFT", 0, -2)
	trainerBar:SetPoint("TOPRIGHT", tf, "BOTTOMRIGHT", 0, -2)
	trainerBar.label:SetText(string.format(L["TRAINER_BAR_TITLE"], #matches, ns.FormatMoney(totalCopper)))
	trainerBar.btn:SetText(L["TRAINER_LEARN_BTN"])
	trainerBar:Show()
end

