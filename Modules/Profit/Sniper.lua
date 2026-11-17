local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Снайпер материалов: целевые пороги цен, пассивный перехват сканов AH и плашка
-------------------------------------------------------------------------------
local MAX_SNIPE_STOCK_AGE = 3600 -- не сигналим по вчерашнему кэшу (> 1 часа)
local snipeBar = nil
local lastSoundAt = 0
local pendingUiRefresh = false
local hookedAuctionFrames = {}

local function EnsureSnipeDB()
	if not ns.realmDB then
		return {}
	end
	ns.realmDB.snipeTargets = ns.realmDB.snipeTargets or {}
	return ns.realmDB.snipeTargets
end

local function IsAuctionHouseOpen()
	return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
end

local function GetActiveAuctionFrame()
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		return AuctionHouseFrame
	end
	if AuctionFrame and AuctionFrame:IsShown() then
		return AuctionFrame
	end
	return nil
end

local function WithLoadedItems(items, callback)
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
	else
		callback()
	end
end

function ns:GetSnipeTargets()
	return EnsureSnipeDB()
end

function ns:GetSnipeTargetList()
	local targets = EnsureSnipeDB()
	local list = {}
	for _, t in pairs(targets) do
		list[#list + 1] = t
	end
	table.sort(list, function(a, b)
		return (a.itemID or 0) < (b.itemID or 0)
	end)
	return list
end

function ns:AddSnipeTarget(itemID, maxPrice, recipeID)
	if not itemID or itemID <= 0 or not maxPrice or maxPrice <= 0 then
		return false
	end
	local targets = EnsureSnipeDB()
	targets[itemID] = {
		itemID = itemID,
		maxPrice = math.max(1, math.floor(maxPrice + 0.5)),
		recipeID = recipeID,
		ts = time and time() or 0,
	}
	self:EvaluateSnipeItem(itemID, true)
	self:RefreshSnipeUI()
	return true
end

function ns:AddRecipeReagentsToSnipe(recipeID, discountRatio)
	if not recipeID then
		return 0
	end
	local ratio = discountRatio or 0.80
	local _, _, _, breakdown = self:GetRecipeEconomy(recipeID)
	if not breakdown then
		return 0
	end
	local targets = EnsureSnipeDB()
	local added = 0
	for _, b in ipairs(breakdown) do
		if b.itemID and b.source == "ah" and b.unitPrice and b.unitPrice > 0 and not targets[b.itemID] then
			local maxP = math.max(1, math.floor(b.unitPrice * ratio + 0.5))
			if self:AddSnipeTarget(b.itemID, maxP, recipeID) then
				added = added + 1
			end
		end
	end
	return added
end

function ns:ImportShoppingToSnipe(discountRatio)
	local ratio = discountRatio or 0.80
	local shopping = self.GetShoppingList and self:GetShoppingList() or {}
	local targets = EnsureSnipeDB()
	local added = 0
	for _, item in ipairs(shopping) do
		local buyQty = (item.toBuy ~= nil) and item.toBuy or item.missing
		if item.itemID and item.source == "ah" and (buyQty or 0) > 0 and item.unitPrice and item.unitPrice > 0 and not targets[item.itemID] then
			local maxP = math.max(1, math.floor(item.unitPrice * ratio + 0.5))
			if self:AddSnipeTarget(item.itemID, maxP, nil) then
				added = added + 1
			end
		end
	end
	return added
end

function ns:AdjustSnipeTarget(itemID, factor)
	local targets = EnsureSnipeDB()
	local t = targets[itemID]
	if not t then
		return
	end
	t.maxPrice = math.max(1, math.floor((t.maxPrice or 1) * factor + 0.5))
	self:EvaluateSnipeItem(itemID, true)
	self:RefreshSnipeUI()
end

function ns:RemoveSnipeTarget(itemID)
	local targets = EnsureSnipeDB()
	targets[itemID] = nil
	if self.snipeHits then
		self.snipeHits[itemID] = nil
	end
	self:RefreshSnipeUI()
end

function ns:ClearSnipeTargets()
	if self.realmDB then
		self.realmDB.snipeTargets = {}
	end
	self.snipeHits = {}
	self:RefreshSnipeUI()
end

-- Сверяем актуальный снимок ahStock для itemID со снайп-целью
function ns:EvaluateSnipeItem(itemID, silent)
	self.snipeHits = self.snipeHits or {}
	if not (self.IsModuleEnabled and self:IsModuleEnabled("profit")) then
		self.snipeHits[itemID] = nil
		return nil
	end
	local targets = EnsureSnipeDB()
	local target = targets[itemID]
	if not target then
		self.snipeHits[itemID] = nil
		return nil
	end
	local stock = self.realmDB and self.realmDB.ahStock and self.realmDB.ahStock[itemID]
	local now = time and time() or 0
	if not stock or (stock.ts and stock.ts > 0 and now > 0 and (now - stock.ts) > MAX_SNIPE_STOCK_AGE) then
		self.snipeHits[itemID] = nil
		return nil
	end

	local cheapQty = nil
	local bestPrice = nil
	if stock.isAggregate then
		if stock.price and stock.price > 0 and stock.price <= target.maxPrice then
			bestPrice = stock.price
			cheapQty = nil -- сводка BrowseResults не даёт точное кол-во на минимальной цене
		end
	else
		local tiers = (stock.tiers and #stock.tiers > 0 and stock.tiers)
			or (stock.price and { { stock.price, stock.total or stock.qty or 0 } })
		if tiers then
			local sumQty = 0
			for _, tier in ipairs(tiers) do
				local p, q = tier[1] or 0, tier[2] or 0
				if p > 0 and q > 0 and p <= target.maxPrice then
					sumQty = sumQty + q
					if not bestPrice or p < bestPrice then
						bestPrice = p
					end
				end
			end
			if sumQty > 0 then
				cheapQty = sumQty
			end
		end
	end

	if bestPrice then
		local prev = self.snipeHits[itemID]
		local isNewHit = not prev or prev.bestPrice ~= bestPrice or prev.qty ~= cheapQty
		self.snipeHits[itemID] = {
			itemID = itemID,
			bestPrice = bestPrice,
			qty = cheapQty,
			maxPrice = target.maxPrice,
			ts = stock.ts or now,
		}
		if not silent and isNewHit and IsAuctionHouseOpen() and PlaySound then
			local tNow = GetTime and GetTime() or 0
			if (tNow - lastSoundAt) > 5 then
				lastSoundAt = tNow
				pcall(PlaySound, 8959)
			end
		end
		return self.snipeHits[itemID]
	end

	self.snipeHits[itemID] = nil
	return nil
end

function ns:GetSnipeHitList()
	local res = {}
	for _, hit in pairs(self.snipeHits or {}) do
		res[#res + 1] = hit
	end
	table.sort(res, function(a, b)
		return (a.itemID or 0) < (b.itemID or 0)
	end)
	return res
end

function ns:SearchSnipeTargetsOnAH(onlyItemID)
	if not IsAuctionHouseOpen() then
		self:Print(L["AH_NOT_OPEN"])
		return
	end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and (api.MultiSearchAdvanced or api.MultiSearchExact)) then
		self:Print(L["ATR_NOT_FOUND"])
		return
	end

	local items = {}
	if onlyItemID then
		local t = EnsureSnipeDB()[onlyItemID]
		if t then
			items[1] = t
		end
	else
		items = self:GetSnipeTargetList()
	end
	if #items == 0 then
		return
	end

	WithLoadedItems(items, function()
		if not IsAuctionHouseOpen() then
			return
		end
		local advanced, names = {}, {}
		for _, t in ipairs(items) do
			local name, _, _, _, loaded = self:GetItemDisplay(t.itemID)
			if loaded and name then
				names[#names + 1] = name
				local q = {
					searchString = name,
					isExact = true,
				}
				-- Фильтруем по maxPrice только для лота с активным хитом; иначе запрашиваем все лоты для обновления цены рынка
				if onlyItemID and self.snipeHits and self.snipeHits[t.itemID] and t.maxPrice and t.maxPrice > 0 then
					q.maxPrice = t.maxPrice
				end
				advanced[#advanced + 1] = q
			end
		end
		local searched = false
		if api.MultiSearchAdvanced and #advanced > 0 then
			local ok = pcall(api.MultiSearchAdvanced, ADDON_NAME, advanced)
			searched = ok
		end
		if not searched and api.MultiSearchExact and #names > 0 then
			pcall(api.MultiSearchExact, ADDON_NAME, names)
		end
	end)
end

local function HookAuctionFrameShow(ah)
	if ah and not hookedAuctionFrames[ah] and ah.HookScript then
		hookedAuctionFrames[ah] = true
		ah:HookScript("OnShow", function()
			if ns.RefreshSnipeBar then
				ns:RefreshSnipeBar()
			end
		end)
		ah:HookScript("OnHide", function()
			if snipeBar then
				snipeBar:Hide()
			end
		end)
	end
end

function ns:RefreshSnipeBar()
	local ah = GetActiveAuctionFrame()
	local enabled = self.IsModuleEnabled and self:IsModuleEnabled("profit")
	local targets = self:GetSnipeTargetList()
	if not (ah and enabled and #targets > 0) then
		if snipeBar then
			snipeBar:Hide()
		end
		return
	end

	HookAuctionFrameShow(ah)

	if not snipeBar then
		snipeBar = CreateFrame("Frame", "TradeFlowSnipeBar", ah, "BackdropTemplate")
		snipeBar:SetHeight(38)
		snipeBar:SetFrameStrata("DIALOG")
		snipeBar:SetToplevel(true)
		snipeBar:SetClampedToScreen(true)
		snipeBar:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		snipeBar:SetBackdropColor(0.08, 0.07, 0.05, 0.96)

		snipeBar.label = snipeBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		snipeBar.label:SetPoint("LEFT", 10, 0)
		snipeBar.label:SetPoint("RIGHT", -240, 0)
		snipeBar.label:SetJustifyH("LEFT")
		snipeBar.label:SetWordWrap(false)

		snipeBar.scanBtn = CreateFrame("Button", nil, snipeBar, "UIPanelButtonTemplate")
		snipeBar.scanBtn:SetSize(112, 24)
		snipeBar.scanBtn:SetPoint("RIGHT", -8, 0)
		snipeBar.scanBtn:SetScript("OnClick", function()
			ns:SearchSnipeTargetsOnAH()
		end)

		snipeBar.openBtn = CreateFrame("Button", nil, snipeBar, "UIPanelButtonTemplate")
		snipeBar.openBtn:SetSize(110, 24)
		snipeBar.openBtn:SetPoint("RIGHT", snipeBar.scanBtn, "LEFT", -6, 0)
		snipeBar.openBtn:SetScript("OnClick", function()
			local hits = ns:GetSnipeHitList()
			if hits[1] then
				ns:SearchSnipeTargetsOnAH(hits[1].itemID)
			end
		end)
		snipeBar.openBtn:SetScript("OnEnter", function(self)
			local hits = ns:GetSnipeHitList()
			if #hits == 0 then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["SNIPE_HITS_HEADER"], 0.25, 1, 0.25)
			for _, h in ipairs(hits) do
				local name, _, _, _, _, hex = ns:GetItemDisplay(h.itemID)
				local qtyStr = h.qty and ("x" .. h.qty) or L["SNIPE_LOT_ANY"]
				GameTooltip:AddDoubleLine(
					string.format("%s%s|r %s", hex or "|cffffffff", name, qtyStr),
					string.format("%s (<= %s)", ns.FormatMoney(h.bestPrice), ns.FormatMoney(h.maxPrice)),
					1, 1, 1, 0.4, 1, 0.4
				)
			end
			GameTooltip:Show()
		end)
		snipeBar.openBtn:SetScript("OnLeave", GameTooltip_Hide)
	end

	snipeBar:SetParent(ah)
	snipeBar:ClearAllPoints()
	local ahTop = ah.GetTop and ah:GetTop() or 0
	local screenTop = UIParent and UIParent.GetTop and UIParent:GetTop() or 768
	if ahTop > 0 and (ahTop + 42) > screenTop then
		snipeBar:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 0, -2)
		snipeBar:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", 0, -2)
	else
		snipeBar:SetPoint("BOTTOMLEFT", ah, "TOPLEFT", 0, 2)
		snipeBar:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", 0, 2)
	end

	snipeBar.scanBtn:SetText(L["SNIPE_SCAN_BTN"])
	snipeBar.openBtn:SetText(L["SNIPE_FIND_HIT_BTN"])

	local hits = self:GetSnipeHitList()
	if #hits > 0 then
		local first = hits[1]
		local name = self:GetItemDisplay(first.itemID)
		local qtyStr = first.qty and ("x" .. first.qty) or L["SNIPE_LOT_ANY"]
		snipeBar:SetBackdropBorderColor(0.25, 0.90, 0.35, 1)
		snipeBar.label:SetText(string.format(
			L["SNIPE_BAR_HIT"],
			#hits,
			name,
			qtyStr,
			ns.FormatMoney(first.bestPrice)
		))
		snipeBar.openBtn:Show()
	else
		snipeBar:SetBackdropBorderColor(0.85, 0.65, 0.20, 1)
		snipeBar.label:SetText(string.format(L["SNIPE_BAR_IDLE"], #targets))
		snipeBar.openBtn:Hide()
	end
	snipeBar:Show()
end

local function ApplySnipeUIRefresh()
	ns:RefreshSnipeBar()
	if ns.modules and ns.modules.byId and ns.modules.byId["profit"] then
		local mod = ns.modules.byId["profit"]
		if ns:IsModuleEnabled("profit") and mod.view and mod.view:IsVisible() and mod.OnRefresh then
			mod:OnRefresh()
		end
	end
end

function ns:RefreshSnipeUI()
	if pendingUiRefresh then
		return
	end
	if C_Timer and C_Timer.After then
		pendingUiRefresh = true
		C_Timer.After(0.05, function()
			pendingUiRefresh = false
			ApplySnipeUIRefresh()
		end)
	else
		ApplySnipeUIRefresh()
	end
end

local snipeEventFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_CLOSED",
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"AUCTION_ITEM_LIST_UPDATE",
}) do
	pcall(snipeEventFrame.RegisterEvent, snipeEventFrame, ev)
end
snipeEventFrame:SetScript("OnEvent", function(_, event)
	if not (ns.IsModuleEnabled and ns:IsModuleEnabled("profit")) then
		if snipeBar then
			snipeBar:Hide()
		end
		return
	end
	if event == "AUCTION_HOUSE_SHOW" then
		HookAuctionFrameShow(AuctionHouseFrame)
		HookAuctionFrameShow(AuctionFrame)
		for _, t in ipairs(ns:GetSnipeTargetList()) do
			ns:EvaluateSnipeItem(t.itemID, true)
		end
		ns:RefreshSnipeBar()
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function() ns:RefreshSnipeBar() end)
			C_Timer.After(0.15, function() ns:RefreshSnipeBar() end)
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if snipeBar then
			snipeBar:Hide()
		end
	else
		ns:RefreshSnipeUI()
	end
end)
