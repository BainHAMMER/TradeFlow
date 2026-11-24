local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- 1. Синхронизация списков закупок в Auctionator (как в SkillUp)
-- 2. Панель и кнопка «Докупить по списку» в окне торговца (MERCHANT_SHOW)
-------------------------------------------------------------------------------
local lastSyncedSignature = nil
local shoppingSyncToken = 0
local syncDebounceGen = 0
local syncDebouncePending = false
local syncPendingBgOnly = true
local ahSyncDeferred = false
local vendorBar = nil
local bankBar = nil
local trainerBar = nil

local function IsAuctionHouseOpen()
	return (AuctionHouseFrame and AuctionHouseFrame:IsShown())
		or (AuctionFrame and AuctionFrame:IsShown())
		or false
end

local function IsPlayerCasting()
	if UnitCastingInfo and UnitCastingInfo("player") then
		return true
	end
	if UnitChannelInfo and UnitChannelInfo("player") then
		return true
	end
	return false
end

function ns:GetAuctionatorListName()
	return "TradeFlow: " .. self:CharKey()
end

local function RunSafe(tag, fn, ...)
	if ns.SafeCall then
		return ns:SafeCall(tag, fn, ...)
	end
	return pcall(fn, ...)
end

-- Дебаунс фоновой синхронизации Auctionator, чтобы крафт и сумки успевали синхронизироваться
function ns:ScheduleAuctionatorSync(backgroundOnly)
	if not syncDebouncePending then
		syncPendingBgOnly = (backgroundOnly == true)
	elseif not backgroundOnly then
		syncPendingBgOnly = false
	end
	syncDebouncePending = true
	syncDebounceGen = syncDebounceGen + 1
	local gen = syncDebounceGen
	local delay = backgroundOnly and 0.45 or 0.15
	if C_Timer and C_Timer.After then
		C_Timer.After(delay, function()
			if gen ~= syncDebounceGen then
				return
			end
			local bgOnly = syncPendingBgOnly
			syncDebouncePending = false
			syncPendingBgOnly = true
			ns:SyncAuctionatorShoppingList(true, bgOnly)
		end)
	else
		local bgOnly = syncPendingBgOnly
		syncDebouncePending = false
		syncPendingBgOnly = true
		self:SyncAuctionatorShoppingList(true, bgOnly)
	end
end

-- Автоматическое создание / обновление / удаление Shopping List в Auctionator
function ns:SyncAuctionatorShoppingList(silent, backgroundOnly)
	if not silent then
		syncDebounceGen = syncDebounceGen + 1
		syncDebouncePending = false
		syncPendingBgOnly = true
		ahSyncDeferred = false
	end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
		if not silent then
			self:Print(L["ATR_NOT_FOUND"])
		end
		return
	end

	if silent and backgroundOnly then
		if IsAuctionHouseOpen() then
			ahSyncDeferred = true
			return
		end
		if IsPlayerCasting() then
			self:ScheduleAuctionatorSync(true)
			return
		end
	end

	local shopping = self:GetShoppingList()
	local ahItems = {}
	local sigParts = {}
	for _, item in ipairs(shopping) do
		local buyQty = item.toBuy ~= nil and item.toBuy or item.missing
		if item.source ~= "vendor" and buyQty > 0 then
			ahItems[#ahItems + 1] = item
			sigParts[#sigParts + 1] = item.itemID .. ":" .. buyQty
		end
	end

	local sig = table.concat(sigParts, ",")
	shoppingSyncToken = shoppingSyncToken + 1
	local token = shoppingSyncToken
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

	self:WithLoadedItems(ahItems, function()
		if token ~= shoppingSyncToken then
			return
		end
		if silent and backgroundOnly and IsAuctionHouseOpen() then
			ahSyncDeferred = true
			return
		end
		local searches = {}
		for _, item in ipairs(ahItems) do
			local name, _, _, _, loaded = self:GetItemDisplay(item.itemID)
			if loaded and name then
				local ok, str = pcall(api.ConvertToSearchString, ADDON_NAME, {
					searchString = name,
					isExact = true,
					quantity = item.toBuy ~= nil and item.toBuy or item.missing,
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
	if not IsAuctionHouseOpen() then
		self:Print(L["AH_NOT_OPEN"])
		return
	end

	local shopping = self:GetShoppingList()
	local ahItems = {}
	for _, item in ipairs(shopping) do
		local buyQty = item.toBuy ~= nil and item.toBuy or item.missing
		if item.source ~= "vendor" and buyQty > 0 then
			ahItems[#ahItems + 1] = item
		end
	end
	if #ahItems == 0 then
		return
	end

	self:WithLoadedItems(ahItems, function()
		local advanced, names = {}, {}
		for _, item in ipairs(ahItems) do
			local name, _, _, _, loaded = self:GetItemDisplay(item.itemID)
			if loaded and name then
				names[#names + 1] = name
				advanced[#advanced + 1] = {
					searchString = name,
					isExact = true,
					quantity = item.toBuy ~= nil and item.toBuy or item.missing,
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
	local vendorChanged = false
	for slot = 1, numMerchant do
		local itemID = GetMerchantSlotItemID(slot)
		local price, stackSize, numAvailable, canBuy = GetMerchantSlotInfo(slot)
		if itemID and price and price > 0 and canBuy and numAvailable == -1 and ns.db and ns.db.vendorPrices then
			local unit = math.floor(price / math.max(1, stackSize) + 0.5)
			if ns.db.vendorPrices[itemID] ~= unit then
				ns.db.vendorPrices[itemID] = unit
				vendorChanged = true
			end
		end
	end
	if vendorChanged and ns.SchedulePriceInvalidation then
		ns:SchedulePriceInvalidation()
	end

	local shopping = ns:GetShoppingList()
	local needByItem = {}
	for _, item in ipairs(shopping) do
		local buyQty = item.toBuy ~= nil and item.toBuy or item.missing
		if buyQty > 0 then
			needByItem[item.itemID] = buyQty
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

local function DistributeProRataSpend(actualSpent, items, getCost, onAlloc)
	if not (actualSpent and actualSpent > 0 and items and #items > 0) then
		return
	end
	local totalEst = 0
	for _, item in ipairs(items) do
		totalEst = totalEst + (getCost(item) or 0)
	end
	if totalEst <= 0 then
		return
	end
	local remSpent = math.min(actualSpent, math.ceil(totalEst * 1.05))
	local remEst = totalEst
	for _, item in ipairs(items) do
		if remSpent <= 0 then
			break
		end
		local c = getCost(item) or 0
		if c > 0 then
			local share = (remEst <= c) and remSpent or math.floor(remSpent * c / remEst + 0.5)
			share = math.min(share, remSpent)
			remSpent = remSpent - share
			remEst = remEst - c
			if share > 0 then
				onAlloc(item, share)
			end
		end
	end
end

local vendorBuyInFlight = false

function ns:BuyVendorShoppingList(onlyItemID)
	if vendorBuyInFlight then
		return
	end
	local matches = CollectMerchantMatches()
	if #matches == 0 then
		return
	end
	if self.ScanBagsNow then
		self:ScanBagsNow()
	end
	local attempted = {}
	local attemptedByItem = {}
	local maxStackFn = GetMerchantItemMaxStack
	for _, m in ipairs(matches) do
		if not onlyItemID or m.itemID == onlyItemID then
			local entry = attemptedByItem[m.itemID]
			if not entry then
				entry = {
					itemID = m.itemID,
					units = 0,
					beforeBag = self:GetBagCount(m.itemID),
				}
				attemptedByItem[m.itemID] = entry
				attempted[#attempted + 1] = entry
			end
			entry.units = entry.units + m.batches * m.stackSize
		end
	end
	if #attempted == 0 then
		return
	end
	vendorBuyInFlight = true
	if vendorBar and vendorBar.btn then
		vendorBar.btn:SetEnabled(false)
	end
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
		end
	end
	local tries = 0
	local function Finish()
		tries = tries + 1
		if ns.ScanBagsNow then
			ns:ScanBagsNow(true)
		end
		if tries < 5 and C_Timer and C_Timer.After then
			local allArrived = true
			for _, a in ipairs(attempted) do
				local gained = math.max(0, ns:GetBagCount(a.itemID) - a.beforeBag)
				if gained < a.units then
					allArrived = false
					break
				end
			end
			if not allArrived then
				C_Timer.After(0.25, Finish)
				return
			end
		end
		vendorBuyInFlight = false
		if vendorBar and vendorBar.btn then
			vendorBar.btn:SetEnabled(true)
		end
		if ns.ScanBagsNow then
			ns:ScanBagsNow()
		end
		if ns.FlushPendingMerchantBuys then
			ns:FlushPendingMerchantBuys()
		end
		for _, a in ipairs(attempted) do
			local gained = math.max(0, ns:GetBagCount(a.itemID) - a.beforeBag)
			if gained > 0 then
				local name = ns:GetItemDisplay(a.itemID)
				ns:Print(string.format(L["VENDOR_BOUGHT_MSG"], name, gained))
			end
		end
		ns:RefreshVendorBar()
		if ns.RefreshQueueAndShoppingView then
			ns:RefreshQueueAndShoppingView()
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.25, Finish)
	else
		Finish()
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
	"AUCTION_HOUSE_CLOSED",
}) do
	pcall(merchantEventFrame.RegisterEvent, merchantEventFrame, ev)
end
merchantEventFrame:SetScript("OnEvent", function(_, event)
	if event == "AUCTION_HOUSE_CLOSED" then
		if ahSyncDeferred then
			ahSyncDeferred = false
			ns:ScheduleAuctionatorSync(true)
		end
	elseif event == "MERCHANT_CLOSED" then
		if vendorBar then
			vendorBar:Hide()
		end
		if ns.RefreshQueueAndShoppingView then
			ns:RefreshQueueAndShoppingView()
		end
	elseif event == "BANKFRAME_CLOSED" then
		ns.bankWithdrawJob = nil
		if bankBar then
			if bankBar.btn then
				bankBar.btn:SetEnabled(true)
			end
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
		if C_Timer and C_Timer.After then
			C_Timer.After(0.1, function()
				ns:RefreshTrainerBar()
				if ns.RefreshQueueAndShoppingView then
					ns:RefreshQueueAndShoppingView()
				end
			end)
		end
	elseif event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
		if BankFrame and not ns.bankOnShowHooked then
			ns.bankOnShowHooked = true
			BankFrame:HookScript("OnShow", function()
				ns:RefreshBankBar()
				if ns.RefreshQueueAndShoppingView then
					ns:RefreshQueueAndShoppingView()
				end
			end)
		end
		ns:RefreshBankBar()
		if ns.RefreshQueueAndShoppingView then
			ns:RefreshQueueAndShoppingView()
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(0.15, function()
				ns:RefreshBankBar()
				if ns.RefreshQueueAndShoppingView then
					ns:RefreshQueueAndShoppingView()
				end
			end)
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
local function ReadContainerSlot(bag, slot, GetInfo)
	local count, locked = 1, false
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		count = (info and info.stackCount) or 1
		locked = (info and info.isLocked) == true
	elseif GetInfo then
		local _, c, l = GetInfo(bag, slot)
		count = c or 1
		locked = l == true
	end
	return count, locked
end

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

	local bankContainers = ns:GetBankContainerIDs()

	local rawByItem = {}
	local order = {}
	for _, bag in ipairs(bankContainers) do
		local slots = GetNumSlots(bag) or 0
		for slot = 1, slots do
			local itemID = GetID and GetID(bag, slot)
			local need = itemID and needByItem[itemID]
			if need and need > 0 then
				local count, locked = ReadContainerSlot(bag, slot, GetInfo)
				if not rawByItem[itemID] then
					rawByItem[itemID] = { itemID = itemID, need = need, totalTake = 0, slots = {} }
					order[#order + 1] = rawByItem[itemID]
				end
				local slotsList = rawByItem[itemID].slots
				slotsList[#slotsList + 1] = { bag = bag, slot = slot, count = count, locked = locked }
			end
		end
	end

	-- Подбираем стаки с минимальным перебором: сначала берём наибольшие стаки <= остатка
	-- (чтобы закрывать ровные стаки без лишних хвостов), а на финальный остаток — наименьший стак >= остатка
	for _, entry in ipairs(order) do
		local pool = {}
		for _, s in ipairs(entry.slots) do
			pool[#pool + 1] = s
		end
		local picked = {}
		local rem = entry.need
		while rem > 0 and #pool > 0 do
			local bestIdx = nil
			local bestCount = -1
			for i, s in ipairs(pool) do
				if s.count <= rem and s.count > bestCount then
					bestIdx = i
					bestCount = s.count
				end
			end
			if not bestIdx then
				bestCount = math.huge
				for i, s in ipairs(pool) do
					if s.count < bestCount then
						bestIdx = i
						bestCount = s.count
					end
				end
			end
			if not bestIdx then
				break
			end
			local s = table.remove(pool, bestIdx)
			local take = math.min(rem, s.count)
			s.take = take
			picked[#picked + 1] = s
			entry.totalTake = entry.totalTake + take
			rem = rem - take
		end
		entry.slots = picked
	end
	return order
end

function ns:GetBankShoppingMatches()
	return CollectBankMatches()
end

local function FindFreePlayerBagSlot(itemID, reservedSlots)
	local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local GetID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	local GetInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
	local GetFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	if not GetID then
		return nil, nil
	end
	local reagentBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
	local itemFamily = (itemID and C_Item and C_Item.GetItemFamily and C_Item.GetItemFamily(itemID))
		or (itemID and GetItemFamily and GetItemFamily(itemID))
		or 0
	-- Обходим сумки и слоты с конца, чтобы сплит не сталкивался с UseContainerItem (который заполняет с сумки 0, слота 1)
	local bags = ns:GetPlayerContainerIDs()
	for bi = #bags, 1, -1 do
		local bag = bags[bi]
		if bag ~= reagentBag then
			local free, family
			if GetFree then
				free, family = GetFree(bag)
			end
			local bagOk = (not family or family == 0)
				or (itemFamily and itemFamily > 0 and bit and bit.band and bit.band(itemFamily, family) ~= 0)
			if bagOk and (not free or free > 0) then
				local slots = GetNumSlots and GetNumSlots(bag) or 0
				for slot = slots, 1, -1 do
					local key = bag .. ":" .. slot
					if not (reservedSlots and reservedSlots[key]) and not GetID(bag, slot) then
						local _, locked = ReadContainerSlot(bag, slot, GetInfo)
						if not locked then
							return bag, slot
						end
					end
				end
			end
		end
	end
	return nil, nil
end

local function FinishBankWithdraw(job)
	if ns.bankWithdrawJob ~= job then
		return
	end
	ns.bankWithdrawJob = nil
	if bankBar and bankBar.btn then
		bankBar.btn:SetEnabled(true)
	end
	local tries = 0
	local function ReportActual()
		tries = tries + 1
		ns:ScanBagsNow(tries < 4)
		if tries < 4 and C_Timer and C_Timer.After then
			local allArrived = true
			for _, itemID in ipairs(job.order) do
				local gained = ns:GetBagCount(itemID) - (job.beforeBags[itemID] or 0)
				if gained < (job.expectedByItem[itemID] or 1) then
					allArrived = false
					break
				end
			end
			if not allArrived then
				C_Timer.After(0.25, ReportActual)
				return
			end
		end
		ns:ScanBagsNow()
		for _, itemID in ipairs(job.order) do
			local gained = ns:GetBagCount(itemID) - (job.beforeBags[itemID] or 0)
			if gained > 0 then
				local name = ns:GetItemDisplay(itemID)
				ns:Print(string.format(L["BANK_WITHDRAWN_MSG"], name, gained))
			end
		end
		ns:RefreshBankBar()
		if ns.RefreshQueueAndShoppingView then
			ns:RefreshQueueAndShoppingView()
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.25, ReportActual)
	else
		ReportActual()
	end
end

function ns:WithdrawBankShoppingList()
	if self.bankWithdrawJob then
		return
	end
	local matches = CollectBankMatches()
	if #matches == 0 then
		return
	end
	if self.LogTrace then
		self:LogTrace("WithdrawBank", #matches .. " items")
	end
	local UseItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
	local SplitItem = (C_Container and C_Container.SplitContainerItem) or SplitContainerItem
	local PickupItem = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
	local GetID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	local GetInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
	if not UseItem then
		return
	end
	if ClearCursor then
		ClearCursor()
	end

	local _, bankSet = self:GetBankContainerIDs()
	local job = {
		order = {},
		beforeBags = {},
		expectedByItem = {},
		slotQueue = {},
		reservedSlots = {},
		steps = 0,
	}
	for _, m in ipairs(matches) do
		job.order[#job.order + 1] = m.itemID
		job.beforeBags[m.itemID] = self:GetBagCount(m.itemID)
		job.expectedByItem[m.itemID] = m.totalTake or m.need or 1
		for _, s in ipairs(m.slots or {}) do
			if not bankSet or bankSet[s.bag] then
				job.slotQueue[#job.slotQueue + 1] = {
					itemID = m.itemID,
					bag = s.bag,
					slot = s.slot,
					count = s.count,
					take = s.take or s.count,
					retries = 0,
				}
			end
		end
	end
	if #job.slotQueue == 0 then
		return
	end
	self.bankWithdrawJob = job
	if bankBar and bankBar.btn then
		bankBar.btn:SetEnabled(false)
	end

	local function StepNext()
		if ns.bankWithdrawJob ~= job then
			return
		end
		if not (BankFrame and BankFrame:IsShown()) or #job.slotQueue == 0 or job.steps >= 45 then
			FinishBankWithdraw(job)
			return
		end
		if CursorHasItem and CursorHasItem() then
			if ClearCursor then
				ClearCursor()
			end
			if CursorHasItem() then
				FinishBankWithdraw(job)
				return
			end
		end

		local s = table.remove(job.slotQueue, 1)
		if not s then
			FinishBankWithdraw(job)
			return
		end
		local curID = GetID and GetID(s.bag, s.slot)
		if not curID or curID ~= s.itemID then
			if #job.slotQueue > 0 and C_Timer and C_Timer.After then
				C_Timer.After(0.05, StepNext)
			else
				FinishBankWithdraw(job)
			end
			return
		end
		local curCount, curLocked = ReadContainerSlot(s.bag, s.slot, GetInfo)
		if curLocked then
			if (s.retries or 0) < 4 and C_Timer and C_Timer.After then
				s.retries = (s.retries or 0) + 1
				table.insert(job.slotQueue, 1, s)
				C_Timer.After(0.15, StepNext)
				return
			end
			if #job.slotQueue > 0 and C_Timer and C_Timer.After then
				C_Timer.After(0.05, StepNext)
			else
				FinishBankWithdraw(job)
			end
			return
		end

		local wantTake = math.min(s.take or curCount, curCount)
		if ns.LogTrace then
			ns:LogTrace("BankStep", "bag=" .. tostring(s.bag) .. " slot=" .. tostring(s.slot) .. " " .. tostring(wantTake) .. "/" .. tostring(curCount))
		end

		job.steps = job.steps + 1
		local movedAny = false
		if wantTake > 0 and wantTake < curCount and SplitItem and PickupItem then
			local dstBag, dstSlot = FindFreePlayerBagSlot(s.itemID, job.reservedSlots)
			if dstBag and dstSlot then
				local okSplit = RunSafe("BankSplitItem", SplitItem, s.bag, s.slot, wantTake)
				if okSplit and (not CursorHasItem or CursorHasItem()) then
					local okPickup = RunSafe("BankPickupItem", PickupItem, dstBag, dstSlot)
					movedAny = okPickup and not (CursorHasItem and CursorHasItem())
					if movedAny then
						job.reservedSlots[dstBag .. ":" .. dstSlot] = true
					end
				end
				if CursorHasItem and CursorHasItem() and ClearCursor then
					ClearCursor()
				end
			end
			if not movedAny then
				movedAny = RunSafe("BankUseItem", UseItem, s.bag, s.slot)
			end
		else
			movedAny = RunSafe("BankUseItem", UseItem, s.bag, s.slot)
		end
		if not movedAny then
			FinishBankWithdraw(job)
			return
		end
		if #job.slotQueue == 0 then
			FinishBankWithdraw(job)
			return
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(0.18, StepNext)
		else
			FinishBankWithdraw(job)
		end
	end

	StepNext()
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
	bankBar.btn:SetEnabled(not ns.bankWithdrawJob)
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

local function CollectTrainerMatches(includeUnavailable)
	local tf = GetActiveTrainerFrame()
	if not (tf and GetNumTrainerServices and GetTrainerServiceInfo) then
		return {}, 0, 0
	end

	local queue = ns:GetQueue()
	local needLearn = {}
	local needByName = {}
	local needByOutItem = {}
	for _, step in ipairs(queue) do
		if step.recipeID and not ns:IsRecipeLearned(step.recipeID) and not needLearn[step.recipeID] then
			needLearn[step.recipeID] = true
			local rName, _, outItemID = ns:GetRecipeDisplay(step.recipeID)
			if rName then
				needByName[rName:lower()] = step.recipeID
			end
			local spName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(step.recipeID))
				or (GetSpellInfo and GetSpellInfo(step.recipeID))
			if spName then
				needByName[spName:lower()] = step.recipeID
			end
			if outItemID and outItemID > 0 then
				needByOutItem[outItemID] = step.recipeID
			end
		end
	end
	if not next(needLearn) then
		return {}, 0, GetNumTrainerServices() or 0
	end

	local matches = {}
	local totalCopper = 0
	local num = GetNumTrainerServices() or 0
	for i = 1, num do
		local name, arg2, arg3 = GetTrainerServiceInfo(i)
		local category = (type(arg2) == "string" and (arg2 == "available" or arg2 == "unavailable" or arg2 == "used" or arg2 == "header")) and arg2 or arg3
		if category == "available" or (includeUnavailable and category == "unavailable") then
			local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
			local spellID = link and tonumber(link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
			if not spellID and C_TooltipInfo and C_TooltipInfo.GetTrainerService then
				local ok, tip = pcall(C_TooltipInfo.GetTrainerService, i)
				if ok and tip and tip.id and needLearn[tip.id] then
					spellID = tip.id
				end
			end
			if not spellID and link then
				local itemID = tonumber(link:match("item:(%d+)"))
				if itemID and needByOutItem[itemID] then
					spellID = needByOutItem[itemID]
				end
			end
			if not spellID and name then
				local clean = name:gsub("^.-:%s*", ""):lower()
				spellID = needByName[name:lower()] or needByName[clean]
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
	return matches, totalCopper, num
end

function ns:GetTrainerQueueMatches()
	return CollectTrainerMatches()
end

local trainerLearnInFlight = false

function ns:LearnQueuedTrainerRecipes()
	if trainerLearnInFlight then
		return
	end
	local matches = CollectTrainerMatches()
	if #matches == 0 or not BuyTrainerService then
		return
	end
	trainerLearnInFlight = true
	if trainerBar and trainerBar.btn then
		trainerBar.btn:SetEnabled(false)
	end
	local beforeMoney = (GetMoney and GetMoney()) or 0
	local attempted = {}
	-- Покупаем с конца списка, чтобы скрытие выученных строк не сдвигало индексы оставшихся
	for i = #matches, 1, -1 do
		local m = matches[i]
		attempted[#attempted + 1] = m
		pcall(BuyTrainerService, m.index)
	end
	local function Finish()
		trainerLearnInFlight = false
		if trainerBar and trainerBar.btn then
			trainerBar.btn:SetEnabled(true)
		end
		if ns.ScanPlayerProfessions then
			ns:ScanPlayerProfessions()
		end
		local trainerOpen = (GetActiveTrainerFrame() ~= nil)
		local stillNotLearned = {}
		local trainerReadable = false
		if trainerOpen then
			local remaining, _, numServices = CollectTrainerMatches(true)
			trainerReadable = (numServices or 0) > 0
			for _, cm in ipairs(remaining) do
				stillNotLearned[cm.recipeID] = true
			end
		end
		local learnedAny = false
		local learnedPriced = {}
		for _, m in ipairs(attempted) do
			local learned = (ns.IsRecipeLearned and ns:IsRecipeLearned(m.recipeID)) or (trainerReadable and not stillNotLearned[m.recipeID])
			if learned then
				learnedAny = true
				if ns.charDB and ns.charDB.learned then
					ns.charDB.learned[m.recipeID] = true
				end
				if ns.liveRecipes and ns.liveRecipes[m.recipeID] then
					ns.liveRecipes[m.recipeID].learned = true
				end
				ns:Print(string.format(L["TRAINER_LEARNED_MSG"], m.name or tostring(m.recipeID)))
				if (m.cost or 0) > 0 then
					learnedPriced[#learnedPriced + 1] = m
				end
			end
		end
		local afterMoney = (GetMoney and GetMoney()) or beforeMoney
		local actualSpent = math.max(0, beforeMoney - afterMoney)
		if ns.RecordTrainerExpense then
			DistributeProRataSpend(actualSpent, learnedPriced, function(m) return m.cost end, function(m, amt)
				ns:RecordTrainerExpense(m.recipeID, m.name, amt)
			end)
		end
		if learnedAny then
			if ns.InvalidateCraftCounts then
				ns:InvalidateCraftCounts()
			end
			if ns.InvalidatePrices then
				ns:InvalidatePrices(true)
			end
		end
		ns:RefreshTrainerBar()
		if ns.RefreshVisibleUI then
			ns:RefreshVisibleUI()
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.25, Finish)
	else
		Finish()
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

if hooksecurefunc and ClassTrainerFrame_Update then
	hooksecurefunc("ClassTrainerFrame_Update", function()
		if ns.RefreshTrainerBar then
			ns:RefreshTrainerBar()
		end
	end)
end

