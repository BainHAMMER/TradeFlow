local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Снайпер материалов: целевые пороги цен, пассивный перехват сканов AH и плашка
-------------------------------------------------------------------------------
local snipeBar = nil
local lastSoundAt = 0

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
	callback()
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
	local added = 0
	for _, b in ipairs(breakdown) do
		if b.itemID and b.source ~= "vendor" and b.unitPrice and b.unitPrice > 0 then
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
	local added = 0
	for _, item in ipairs(shopping) do
		local buyQty = (item.toBuy ~= nil) and item.toBuy or item.missing
		if item.itemID and item.source ~= "vendor" and (buyQty or 0) > 0 and item.unitPrice and item.unitPrice > 0 then
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

-- Сверяем текущий снимок ahStock для itemID со снайп-целью
function ns:EvaluateSnipeItem(itemID, silent)
	if not (self.IsModuleEnabled and self:IsModuleEnabled("profit")) then
		return nil
	end
	local targets = EnsureSnipeDB()
	local target = targets[itemID]
	self.snipeHits = self.snipeHits or {}
	if not target then
		self.snipeHits[itemID] = nil
		return nil
	end
	local stock = self.realmDB and self.realmDB.ahStock and self.realmDB.ahStock[itemID]
	if not stock then
		return self.snipeHits[itemID]
	end
	local tiers = (stock.tiers and #stock.tiers > 0 and stock.tiers)
		or (stock.price and { { stock.price, stock.total or stock.qty or 0 } })
	if not tiers then
		return nil
	end

	local cheapQty = 0
	local bestPrice = nil
	for _, tier in ipairs(tiers) do
		local p, q = tier[1] or 0, tier[2] or 0
		if p > 0 and q > 0 and p <= target.maxPrice then
			cheapQty = cheapQty + q
			if not bestPrice or p < bestPrice then
				bestPrice = p
			end
		end
	end

	if cheapQty > 0 and bestPrice then
		local prev = self.snipeHits[itemID]
		local isNewHit = not prev or prev.bestPrice ~= bestPrice or prev.qty ~= cheapQty
		self.snipeHits[itemID] = {
			itemID = itemID,
			bestPrice = bestPrice,
			qty = cheapQty,
			maxPrice = target.maxPrice,
			ts = stock.ts or (time and time() or 0),
		}
		if not silent and isNewHit and IsAuctionHouseOpen() and PlaySound then
			local now = GetTime and GetTime() or 0
			if (now - lastSoundAt) > 5 then
				lastSoundAt = now
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
		local advanced, names = {}, {}
		for _, t in ipairs(items) do
			local name, _, _, _, loaded = self:GetItemDisplay(t.itemID)
			if loaded and name then
				names[#names + 1] = name
				advanced[#advanced + 1] = {
					searchString = name,
					isExact = true,
					maxPrice = t.maxPrice,
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

	if not snipeBar then
		snipeBar = CreateFrame("Frame", "TradeFlowSnipeBar", ah, "BackdropTemplate")
		snipeBar:SetHeight(38)
		snipeBar:SetPoint("BOTTOMLEFT", ah, "TOPLEFT", 0, 2)
		snipeBar:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", 0, 2)
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
		snipeBar.scanBtn:SetText(L["SNIPE_SCAN_BTN"])
		snipeBar.scanBtn:SetScript("OnClick", function()
			ns:SearchSnipeTargetsOnAH()
		end)

		snipeBar.openBtn = CreateFrame("Button", nil, snipeBar, "UIPanelButtonTemplate")
		snipeBar.openBtn:SetSize(110, 24)
		snipeBar.openBtn:SetPoint("RIGHT", snipeBar.scanBtn, "LEFT", -6, 0)
		snipeBar.openBtn:SetText(L["SNIPE_FIND_HIT_BTN"])
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
				GameTooltip:AddDoubleLine(
					string.format("%s%s|r x%d", hex or "|cffffffff", name, h.qty or 0),
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
	snipeBar:SetPoint("BOTTOMLEFT", ah, "TOPLEFT", 0, 2)
	snipeBar:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", 0, 2)

	local hits = self:GetSnipeHitList()
	if #hits > 0 then
		local first = hits[1]
		local name = self:GetItemDisplay(first.itemID)
		snipeBar:SetBackdropBorderColor(0.25, 0.90, 0.35, 1)
		snipeBar.label:SetText(string.format(
			L["SNIPE_BAR_HIT"],
			#hits,
			name,
			first.qty or 0,
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

function ns:RefreshSnipeUI()
	self:RefreshSnipeBar()
	if self.modules and self.modules.byId and self.modules.byId["profit"] then
		local mod = self.modules.byId["profit"]
		if self:IsModuleEnabled("profit") and mod.view and mod.view:IsVisible() and mod.OnRefresh then
			mod:OnRefresh()
		end
	end
end

local snipeEventFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_CLOSED",
	"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
	"COMMODITY_SEARCH_RESULTS_UPDATED",
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
		for _, t in ipairs(ns:GetSnipeTargetList()) do
			ns:EvaluateSnipeItem(t.itemID, true)
		end
		ns:RefreshSnipeBar()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if snipeBar then
			snipeBar:Hide()
		end
	else
		ns:RefreshSnipeBar()
	end
end)
