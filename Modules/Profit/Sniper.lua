local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Снайпер материалов: целевые пороги цен, пассивный перехват сканов AH и плашка
-------------------------------------------------------------------------------
local MAX_SNIPE_STOCK_AGE = 3600 -- не сигналим по вчерашнему кэшу (> 1 часа)
local snipeBar = nil
local lastSoundAt = -10
local lastAutoScanAt = -30
local lastChatHitAt = {}
local lastSnipeListSig = nil
local pendingUiRefresh = false
local hookedAuctionFrames = {}
local pendingBuy = nil
local buyTokenCounter = 0

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

function ns:AddSnipeTarget(itemID, maxPrice, recipeID, deferSync)
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
	if not deferSync then
		self:SyncSnipeShoppingList(true)
		self:RefreshSnipeUI()
	end
	return true
end

function ns:GetRecipeSnipePreview(recipeID, discountRatio)
	local items = {}
	local newCount = 0
	if not recipeID then
		return items, 0, 0
	end
	local ratio = discountRatio or 0.80
	local _, _, _, breakdown = self:GetRecipeEconomy(recipeID)
	if not breakdown then
		return items, 0, 0
	end
	local targets = EnsureSnipeDB()
	for _, b in ipairs(breakdown) do
		if b.itemID and b.source == "ah" and b.unitPrice and b.unitPrice > 0 then
			local maxP = math.max(1, math.floor(b.unitPrice * ratio + 0.5))
			local watched = targets[b.itemID] ~= nil
			if not watched then
				newCount = newCount + 1
			end
			items[#items + 1] = {
				itemID = b.itemID,
				curPrice = b.unitPrice,
				maxPrice = targets[b.itemID] and targets[b.itemID].maxPrice or maxP,
				watched = watched,
			}
		end
	end
	return items, newCount, #items
end

function ns:AddRecipeReagentsToSnipe(recipeID, discountRatio)
	local items = self:GetRecipeSnipePreview(recipeID, discountRatio)
	local added = 0
	for _, entry in ipairs(items) do
		if not entry.watched then
			if self:AddSnipeTarget(entry.itemID, entry.maxPrice, recipeID, true) then
				added = added + 1
			end
		end
	end
	if added > 0 then
		self:SyncSnipeShoppingList(true)
		self:RefreshSnipeUI()
	end
	return added, #items
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
			if self:AddSnipeTarget(item.itemID, maxP, nil, true) then
				added = added + 1
			end
		end
	end
	if added > 0 then
		self:SyncSnipeShoppingList(true)
		self:RefreshSnipeUI()
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
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
end

function ns:RepriceSnipeTargets(ratio)
	local r = ratio or 0.80
	local targets = EnsureSnipeDB()
	local updated = 0
	for itemID, t in pairs(targets) do
		local cur = self:GetAuctionPrice(itemID)
		if cur and cur > 0 then
			t.maxPrice = math.max(1, math.floor(cur * r + 0.5))
			t.ts = time and time() or 0
			self:EvaluateSnipeItem(itemID, true)
			updated = updated + 1
		end
	end
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
	self:Print(string.format(L["SNIPE_REPRICED_MSG"], updated))
	return updated
end

function ns:RemoveSnipeTarget(itemID)
	local targets = EnsureSnipeDB()
	targets[itemID] = nil
	if self.snipeHits then
		self.snipeHits[itemID] = nil
	end
	lastChatHitAt[itemID] = nil
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
end

function ns:ClearSnipeTargets()
	if self.realmDB then
		self.realmDB.snipeTargets = {}
	end
	self.snipeHits = {}
	wipe(lastChatHitAt)
	self:SyncSnipeShoppingList(true)
	self:RefreshSnipeUI()
end

function ns.FormatSnipeHitQty(hit)
	if not hit or not hit.qty then
		return L["SNIPE_LOT_ANY"]
	end
	if hit.totalCheapQty and hit.totalCheapQty > hit.qty then
		return string.format(L["SNIPE_QTY_RANGE"], hit.qty, hit.totalCheapQty)
	end
	return "x" .. hit.qty
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

	local bestQty = nil
	local cheapQty = nil
	local bestPrice = nil
	if stock.isAggregate then
		if stock.price and stock.price > 0 and stock.price <= target.maxPrice then
			bestPrice = stock.price
			bestQty = nil -- сводка BrowseResults / ProcessScan не даёт точное кол-во на минимальной цене
			cheapQty = nil
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
						bestQty = q
					elseif p == bestPrice then
						bestQty = (bestQty or 0) + q
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
		local isPriceAlert = (not prev) or (prev.silentOnly == true) or (bestPrice < prev.bestPrice)
		local alerted = (not silent) and isPriceAlert and IsAuctionHouseOpen()
		local discountPct = (target.maxPrice > 0)
			and math.max(0, math.floor((target.maxPrice - bestPrice) / target.maxPrice * 100 + 0.5))
			or 0
		local hit = {
			itemID = itemID,
			bestPrice = bestPrice,
			qty = bestQty,
			totalCheapQty = cheapQty,
			maxPrice = target.maxPrice,
			discountPct = discountPct,
			ts = stock.ts or now,
			silentOnly = (not alerted) and ((not prev) or prev.silentOnly == true),
		}
		self.snipeHits[itemID] = hit
		if alerted then
			local tNow = GetTime and GetTime() or 0
			if PlaySound and (tNow - lastSoundAt) > 5 then
				lastSoundAt = tNow
				pcall(PlaySound, 8959)
			end
			if (tNow - (lastChatHitAt[itemID] or 0)) > 5 then
				lastChatHitAt[itemID] = tNow
				local name, _, _, link, _, hex = self:GetItemDisplay(itemID)
				local label = link or ((hex or "|cffffffff") .. name .. "|r")
				self:Print(string.format(
					L["SNIPE_HIT_CHAT"],
					label,
					ns.FormatSnipeHitQty(hit),
					ns.FormatMoney(bestPrice),
					ns.FormatMoney(target.maxPrice),
					discountPct
				))
			end
		end
		return hit
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
		if (a.discountPct or 0) ~= (b.discountPct or 0) then
			return (a.discountPct or 0) > (b.discountPct or 0)
		end
		return (a.itemID or 0) < (b.itemID or 0)
	end)
	return res
end

local function SafeAuctionatorMaxPrice(target)
	if not target or target <= 0 then
		return nil
	end
	-- Auctionator раскладывает maxPrice на золото/серебро/медь через /100 и /10000 во float;
	-- проверяем итоговую восстановленную цену против target (обычно до +1..+2c)
	local q = target
	for _ = 1, 10 do
		local g = math.floor(q / 10000)
		local s = math.floor(((q / 10000) - g) * 100)
		local c = math.floor(((q / 100) - math.floor(q / 100)) * 100)
		local remGold = math.floor(((q / 10000) - g) * 10000)
		local rebuilt = g * 10000 + s * 100 + c
		if math.floor((q / 100) * 100) < target
			or math.floor((q / 10000) * 10000) < target
			or (g * 10000 + remGold) < target
			or rebuilt < target
		then
			q = q + 1
		else
			return q
		end
	end
	return q
end

function ns:SyncSnipeShoppingList(silent)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
		return
	end
	local targets = self:GetSnipeTargetList()
	local listName = L["SNIPE_LIST_NAME"]
	local parts = {}
	for _, t in ipairs(targets) do
		parts[#parts + 1] = (t.itemID or 0) .. ":" .. (t.maxPrice or 0)
	end
	local sig = listName .. "|" .. table.concat(parts, ",")
	if silent and sig == lastSnipeListSig then
		return
	end

	if #targets == 0 then
		lastSnipeListSig = sig
		if api.GetShoppingListItems and api.DeleteShoppingList then
			local ok, existing = pcall(api.GetShoppingListItems, ADDON_NAME, listName)
			if ok and existing then
				pcall(api.DeleteShoppingList, ADDON_NAME, listName)
			end
		end
		return
	end

	self:WithLoadedItems(targets, function()
		local searches = {}
		for _, t in ipairs(targets) do
			local name, _, _, _, loaded = self:GetItemDisplay(t.itemID)
			if loaded and name then
				local ok, str = pcall(api.ConvertToSearchString, ADDON_NAME, {
					searchString = name,
					isExact = true,
					maxPrice = SafeAuctionatorMaxPrice(t.maxPrice),
				})
				if ok and str then
					searches[#searches + 1] = str
				end
			end
		end
		if #searches > 0 then
			lastSnipeListSig = sig
			pcall(api.CreateShoppingList, ADDON_NAME, listName, searches)
		end
	end)
end

function ns:SearchSnipeTargetsOnAH(targetOrFilter, ignorePrice)
	if not IsAuctionHouseOpen() then
		self:Print(L["AH_NOT_OPEN"])
		return
	end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if not (api and (api.MultiSearchAdvanced or api.MultiSearchExact)) then
		self:Print(L["ATR_NOT_FOUND"])
		return
	end
	if self.LogTrace then
		self:LogTrace("SnipeSearchAH", tostring(targetOrFilter or "all"))
	end

	self:SyncSnipeShoppingList(true)
	local targets = EnsureSnipeDB()
	local items = {}
	local skipPriceFilter = (ignorePrice == true) or (targetOrFilter == "hits")
	if targetOrFilter == "hits" then
		for _, h in ipairs(self:GetSnipeHitList()) do
			if targets[h.itemID] then
				items[#items + 1] = targets[h.itemID]
			end
		end
	elseif type(targetOrFilter) == "number" then
		if targets[targetOrFilter] then
			items[1] = targets[targetOrFilter]
		end
	else
		items = self:GetSnipeTargetList()
	end
	if #items == 0 then
		return
	end

	self:WithLoadedItems(items, function()
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
				-- При общем скане передаём SafeAuctionatorMaxPrice; для уже найденных хитов открываем стакан целиком
				if not skipPriceFilter and t.maxPrice and t.maxPrice > 0 then
					q.maxPrice = SafeAuctionatorMaxPrice(t.maxPrice)
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

local function ClearStaleSnipeHit(itemID, newMinPrice)
	if itemID and ns.snipeHits then
		ns.snipeHits[itemID] = nil
	end
	if itemID and ns.realmDB and ns.realmDB.ahStock and ns.realmDB.ahStock[itemID] then
		if newMinPrice and newMinPrice > 0 then
			local s = ns.realmDB.ahStock[itemID]
			s.minPrice = newMinPrice
			s.tiers = { { price = newMinPrice, qty = s.total or 1 } }
			s.isAggregate = true
			s.ts = (time and time()) or s.ts
		else
			ns.realmDB.ahStock[itemID] = nil
		end
	end
end

local function CancelPendingCommodity(reasonText, dropItemID, newMinPrice)
	if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
		pcall(C_AuctionHouse.CancelCommoditiesPurchase)
	end
	pendingBuy = nil
	if dropItemID then
		ClearStaleSnipeHit(dropItemID, newMinPrice)
	end
	if reasonText and ns.Print then
		ns:Print(reasonText)
	end
	ns:RefreshSnipeUI()
end

local function IsCommodityItem(itemID)
	if C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults then
		local ok, n = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
		if ok and type(n) == "number" and n > 0 then
			return true
		end
	end
	if C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
		local ok, st = pcall(C_AuctionHouse.GetItemCommodityStatus, itemID)
		if ok and st ~= nil then
			if st == Enum.ItemCommodityStatus.Commodity then
				return true
			elseif st == Enum.ItemCommodityStatus.NonCommodity then
				return false
			end
		end
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
		if classID == 0 or classID == 3 or classID == 7 then
			return true
		elseif classID == 2 or classID == 4 or classID == 9 then
			return false
		end
	end
	return true
end

local function ComputeCommodityBuyQty(itemID, maxPrice, hit)
	local money = (GetMoney and GetMoney()) or 0
	if C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetCommoditySearchResultInfo then
		local ok, n = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
		if ok and type(n) == "number" and n > 0 then
			local buyQty, spent, liveMin = 0, 0, nil
			local sawAffordableCheap = false
			for i = 1, math.min(n, 200) do
				local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
				local p = info and info.unitPrice
				local q = info and info.quantity
				if p and p > 0 and q and q > 0 then
					if not liveMin or p < liveMin then
						liveMin = p
					end
					if p <= maxPrice then
						local canAfford = math.floor((money - spent) / p)
						if canAfford > 0 then
							sawAffordableCheap = true
							local take = math.min(q, canAfford)
							buyQty = buyQty + take
							spent = spent + take * p
							if take < q then
								break
							end
						elseif buyQty == 0 then
							return 0, "nomoney", liveMin
						end
					end
				end
			end
			if buyQty > 0 then
				return buyQty, nil, liveMin
			end
			return 0, sawAffordableCheap and "nomoney" or "gone", liveMin
		end
	end

	local stock = ns.GetAuctionTiers and ns:GetAuctionTiers(itemID)
	if stock and not stock.isAggregate and stock.tiers and #stock.tiers > 0 then
		local buyQty, spent = 0, 0
		for _, t in ipairs(stock.tiers) do
			if t.price <= maxPrice and (t.qty or 0) > 0 then
				local canAfford = math.floor((money - spent) / t.price)
				if canAfford > 0 then
					local take = math.min(t.qty, canAfford)
					buyQty = buyQty + take
					spent = spent + take * t.price
					if take < t.qty then
						break
					end
				elseif buyQty == 0 then
					return 0, "nomoney", t.price
				end
			end
		end
		if buyQty > 0 then
			return buyQty, nil, stock.tiers[1] and stock.tiers[1].price
		end
		return 0, "gone", stock.tiers[1] and stock.tiers[1].price
	end

	if hit and hit.bestPrice and hit.bestPrice <= maxPrice then
		if money < hit.bestPrice then
			return 0, "nomoney", hit.bestPrice
		end
		local desired = (hit.totalCheapQty and hit.totalCheapQty > 0) and hit.totalCheapQty or (hit.qty or 1)
		local qty = math.min(desired, math.floor(money / math.max(1, hit.bestPrice)))
		if qty > 0 then
			return qty, nil, hit.bestPrice
		end
	end
	return 0, "gone", nil
end

function ns:BuyFirstSnipeHit()
	if not IsAuctionHouseOpen() then
		return
	end
	if pendingBuy and pendingBuy.state == "confirm" then
		local money = (GetMoney and GetMoney()) or 0
		if (pendingBuy.totalPrice or 0) > money then
			CancelPendingCommodity(L["SNIPE_BUY_NOMONEY"], nil)
			return
		end
		if (pendingBuy.unitPrice or 0) > pendingBuy.maxPrice then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_GONE_PRICE"], pendingBuy.label, ns.FormatMoney(pendingBuy.unitPrice), ns.FormatMoney(pendingBuy.maxPrice)), pendingBuy.itemID, pendingBuy.unitPrice)
			return
		end
		if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
			pendingBuy.state = "buying"
			local ok = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, pendingBuy.itemID, pendingBuy.qty)
			if not ok then
				CancelPendingCommodity(string.format(L["SNIPE_BUY_FAILED"], pendingBuy.label), pendingBuy.itemID, nil)
			else
				self:RefreshSnipeBar()
			end
		end
		return
	end
	if pendingBuy and pendingBuy.state == "awaiting" then
		return
	end

	local hits = self:GetSnipeHitList()
	local first = hits[1]
	if not first then
		return
	end
	local itemID = first.itemID
	local maxPrice = first.maxPrice or 0
	if maxPrice <= 0 then
		return
	end
	local name, _, _, link, _, hex = self:GetItemDisplay(itemID)
	local label = link or ((hex or "|cffffffff") .. (name or ("#" .. itemID)) .. "|r")

	if IsCommodityItem(itemID) and C_AuctionHouse and C_AuctionHouse.StartCommoditiesPurchase then
		local qty, errKind, liveMin = ComputeCommodityBuyQty(itemID, maxPrice, first)
		if qty <= 0 then
			if errKind == "nomoney" then
				self:Print(L["SNIPE_BUY_NOMONEY"])
			else
				CancelPendingCommodity(string.format(L["SNIPE_BUY_GONE"], label), itemID, liveMin)
			end
			return
		end
		buyTokenCounter = buyTokenCounter + 1
		local tok = buyTokenCounter
		pendingBuy = {
			itemID = itemID,
			qty = qty,
			maxPrice = maxPrice,
			state = "awaiting",
			token = tok,
			label = label,
		}
		self:RefreshSnipeBar()
		local ok = pcall(C_AuctionHouse.StartCommoditiesPurchase, itemID, qty)
		if not ok then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_FAILED"], label), nil)
			return
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(4.0, function()
				if pendingBuy and pendingBuy.token == tok and (pendingBuy.state == "awaiting" or pendingBuy.state == "buying") then
					CancelPendingCommodity(string.format(L["SNIPE_BUY_TIMEOUT"], label), nil)
				end
			end)
		end
	elseif C_AuctionHouse and C_AuctionHouse.MakeItemKey and C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetItemSearchResultInfo and C_AuctionHouse.PlaceBid then
		local key = C_AuctionHouse.MakeItemKey(itemID)
		local n = C_AuctionHouse.GetNumItemSearchResults(key) or 0
		if n == 0 then
			self:SearchSnipeTargetsOnAH(itemID, true)
			self:Print(string.format(L["SNIPE_BUY_LOADING"], label))
			return
		end
		local bestAuction = nil
		for i = 1, n do
			local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
			if info and info.auctionID and info.buyoutAmount and info.buyoutAmount > 0 then
				if not bestAuction or info.buyoutAmount < bestAuction.buyoutAmount then
					bestAuction = info
				end
			end
		end
		if not bestAuction or bestAuction.buyoutAmount > maxPrice then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_GONE"], label), itemID, bestAuction and bestAuction.buyoutAmount)
			return
		end
		local money = (GetMoney and GetMoney()) or 0
		if bestAuction.buyoutAmount > money then
			self:Print(L["SNIPE_BUY_NOMONEY"])
			return
		end
		local ok = pcall(C_AuctionHouse.PlaceBid, bestAuction.auctionID, bestAuction.buyoutAmount)
		if ok then
			self:Print(string.format(L["SNIPE_BUY_DONE"], label, 1, ns.FormatMoney(bestAuction.buyoutAmount), ns.FormatMoney(maxPrice)))
			ClearStaleSnipeHit(itemID, nil)
			self:RefreshSnipeUI()
		else
			CancelPendingCommodity(string.format(L["SNIPE_BUY_FAILED"], label), itemID, nil)
		end
	end
end

function ns:RefreshSnipeBar()
	local ah = GetActiveAuctionFrame()
	local enabled = self.IsModuleEnabled and self:IsModuleEnabled("profit")
	local targets = self:GetSnipeTargetList()
	local hits = self:GetSnipeHitList()
	if not (ah and enabled and (#targets > 0 or pendingBuy)) then
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
		snipeBar.scanBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["SNIPE_SCAN_BTN"], 1, 0.82, 0)
			GameTooltip:AddLine(L["SNIPE_SCAN_TIP"], 0.85, 0.85, 0.85, true)
			GameTooltip:Show()
		end)
		snipeBar.scanBtn:SetScript("OnLeave", GameTooltip_Hide)

		snipeBar.openBtn = CreateFrame("Button", nil, snipeBar, "UIPanelButtonTemplate")
		snipeBar.openBtn:SetSize(110, 24)
		snipeBar.openBtn:SetPoint("RIGHT", snipeBar.scanBtn, "LEFT", -6, 0)
		snipeBar.openBtn:SetScript("OnClick", function()
			local hits = ns:GetSnipeHitList()
			if #hits > 0 then
				ns:SearchSnipeTargetsOnAH("hits")
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
					string.format("%s%s|r %s (-%d%%)", hex or "|cffffffff", name, ns.FormatSnipeHitQty(h), h.discountPct or 0),
					string.format("%s (<= %s)", ns.FormatMoney(h.bestPrice), ns.FormatMoney(h.maxPrice)),
					1, 1, 1, 0.4, 1, 0.4
				)
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(L["SNIPE_FIND_HIT_TIP"], 0.75, 0.9, 1, true)
			GameTooltip:Show()
		end)
		snipeBar.openBtn:SetScript("OnLeave", GameTooltip_Hide)

		snipeBar.buyBtn = CreateFrame("Button", "TradeFlowSnipeBuyBtn", snipeBar, "UIPanelButtonTemplate")
		snipeBar.buyBtn:SetSize(142, 24)
		snipeBar.buyBtn:SetPoint("RIGHT", snipeBar.openBtn, "LEFT", -6, 0)
		snipeBar.buyBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		snipeBar.buyBtn:SetScript("OnClick", function(_, button)
			if button == "RightButton" then
				if pendingBuy then
					CancelPendingCommodity(nil, nil)
				end
				return
			end
			ns:BuyFirstSnipeHit()
		end)
		if AuctionHouseFrame and AuctionHouseFrame.BuyDialog and not hookedAuctionFrames[AuctionHouseFrame.BuyDialog] then
			hookedAuctionFrames[AuctionHouseFrame.BuyDialog] = true
			pcall(AuctionHouseFrame.BuyDialog.HookScript, AuctionHouseFrame.BuyDialog, "OnHide", function()
				if pendingBuy and pendingBuy.state == "confirm" then
					if C_Timer and C_Timer.After then
						C_Timer.After(0.05, function()
							if pendingBuy and pendingBuy.state == "confirm" then
								CancelPendingCommodity(nil, nil)
							end
						end)
					else
						CancelPendingCommodity(nil, nil)
					end
				end
			end)
		end
		snipeBar.buyBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if pendingBuy and pendingBuy.state == "confirm" then
				GameTooltip:SetText(string.format(L["SNIPE_BUY_CONFIRM"], pendingBuy.qty), 0.25, 1, 0.25)
				GameTooltip:AddLine(string.format(
					L["SNIPE_BUY_CONFIRM_TIP"],
					pendingBuy.qty,
					ns.FormatMoney(pendingBuy.unitPrice or 0),
					ns.FormatMoney(pendingBuy.totalPrice or 0)
				), 0.9, 0.9, 0.9, true)
			else
				GameTooltip:SetText(string.format(L["SNIPE_BUY_BTN"], 1):gsub("%s*x%d+", ""), 1, 0.82, 0)
				GameTooltip:AddLine(L["SNIPE_BUY_TIP"], 0.85, 0.85, 0.85, true)
			end
			GameTooltip:Show()
		end)
		snipeBar.buyBtn:SetScript("OnLeave", GameTooltip_Hide)
	end

	snipeBar:SetParent(ah)
	snipeBar:ClearAllPoints()
	local ahScale = (ah.GetEffectiveScale and ah:GetEffectiveScale()) or 1
	local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
	local ahTop = (ah.GetTop and ah:GetTop() or 0) * ahScale
	local screenTop = (UIParent and UIParent.GetTop and UIParent:GetTop() or 768) * uiScale
	if ahTop > 0 and (ahTop + 42 * ahScale) > screenTop then
		snipeBar:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 0, -2)
		snipeBar:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", 0, -2)
	else
		snipeBar:SetPoint("BOTTOMLEFT", ah, "TOPLEFT", 0, 2)
		snipeBar:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", 0, 2)
	end

	snipeBar.scanBtn:SetText(L["SNIPE_SCAN_BTN"])

	local hits = self:GetSnipeHitList()
	snipeBar.openBtn:SetText(string.format(L["SNIPE_FIND_HIT_BTN"], #hits))
	if #hits > 0 or pendingBuy then
		local first = hits[1]
		if pendingBuy and pendingBuy.state == "awaiting" then
			snipeBar.buyBtn:SetText(L["SNIPE_BUY_WAIT"])
			snipeBar.buyBtn:SetEnabled(false)
		elseif pendingBuy and pendingBuy.state == "confirm" then
			snipeBar.buyBtn:SetText(string.format(L["SNIPE_BUY_CONFIRM"], pendingBuy.qty or 1))
			snipeBar.buyBtn:SetEnabled(true)
		elseif pendingBuy and pendingBuy.state == "buying" then
			snipeBar.buyBtn:SetText(L["SNIPE_BUY_WAIT"])
			snipeBar.buyBtn:SetEnabled(false)
		elseif first then
			local qty = ComputeCommodityBuyQty(first.itemID, first.maxPrice or 0, first)
			if qty <= 0 then
				qty = (first.totalCheapQty and first.totalCheapQty > 0) and first.totalCheapQty or (first.qty or 1)
			end
			snipeBar.buyBtn:SetText(string.format(L["SNIPE_BUY_BTN"], qty))
			snipeBar.buyBtn:SetEnabled(true)
		end
		snipeBar.buyBtn:Show()
		snipeBar.label:ClearAllPoints()
		snipeBar.label:SetPoint("LEFT", 10, 0)
		snipeBar.label:SetPoint("RIGHT", snipeBar.buyBtn, "LEFT", -8, 0)
	else
		snipeBar.buyBtn:Hide()
		snipeBar.label:ClearAllPoints()
		snipeBar.label:SetPoint("LEFT", 10, 0)
		snipeBar.label:SetPoint("RIGHT", snipeBar.scanBtn, "LEFT", -8, 0)
	end
	if #hits > 0 then
		local first = hits[1]
		local name = self:GetItemDisplay(first.itemID)
		snipeBar:SetBackdropBorderColor(0.25, 0.90, 0.35, 1)
		snipeBar.label:SetText(string.format(
			L["SNIPE_BAR_HIT"],
			#hits,
			name,
			ns.FormatSnipeHitQty(first),
			ns.FormatMoney(first.bestPrice),
			first.discountPct or 0
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
	"COMMODITY_PRICE_UPDATED",
	"COMMODITY_PRICE_UNAVAILABLE",
	"COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED",
}) do
	pcall(snipeEventFrame.RegisterEvent, snipeEventFrame, ev)
end
snipeEventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if not (ns.IsModuleEnabled and ns:IsModuleEnabled("profit")) then
		if snipeBar then
			snipeBar:Hide()
		end
		return
	end
	if event == "AUCTION_HOUSE_SHOW" then
		HookAuctionFrameShow(AuctionHouseFrame)
		HookAuctionFrameShow(AuctionFrame)
		local targets = ns:GetSnipeTargetList()
		for _, t in ipairs(targets) do
			ns:EvaluateSnipeItem(t.itemID, true)
		end
		ns:SyncSnipeShoppingList(true)
		ns:RefreshSnipeBar()
		if C_Timer and C_Timer.After then
			C_Timer.After(0, function() ns:RefreshSnipeBar() end)
			C_Timer.After(0.15, function() ns:RefreshSnipeBar() end)
			if #targets > 0 and ns.db and ns.db.options and ns.db.options.snipeAutoScan == true then
				local tNow = GetTime and GetTime() or 0
				if (tNow - lastAutoScanAt) >= 30 then
					C_Timer.After(0.45, function()
						local cbNow = GetTime and GetTime() or 0
						if IsAuctionHouseOpen() and ns.IsModuleEnabled and ns:IsModuleEnabled("profit") and (cbNow - lastAutoScanAt) >= 30 then
							lastAutoScanAt = cbNow
							ns:SearchSnipeTargetsOnAH()
						end
					end)
				end
			end
		end
	elseif event == "COMMODITY_PRICE_UPDATED" then
		if pendingBuy and pendingBuy.state == "awaiting" then
			local unitP = tonumber(arg1)
			local totalP = tonumber(arg2)
			local effUnit = (unitP and pendingBuy.qty > 0 and totalP) and math.ceil(totalP / pendingBuy.qty) or unitP
			if not unitP or unitP <= 0 or unitP > pendingBuy.maxPrice or (effUnit and effUnit > pendingBuy.maxPrice) then
				CancelPendingCommodity(
					string.format(L["SNIPE_BUY_GONE_PRICE"], pendingBuy.label, ns.FormatMoney(unitP or effUnit or 0), ns.FormatMoney(pendingBuy.maxPrice)),
					pendingBuy.itemID,
					unitP or effUnit
				)
			elseif totalP and GetMoney and totalP > GetMoney() then
				CancelPendingCommodity(L["SNIPE_BUY_NOMONEY"], nil)
			else
				pendingBuy.state = "confirm"
				pendingBuy.unitPrice = unitP
				pendingBuy.totalPrice = totalP or (unitP * pendingBuy.qty)
				ns:RefreshSnipeBar()
			end
		end
	elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
		if pendingBuy then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_GONE"], pendingBuy.label), pendingBuy.itemID, nil)
		end
	elseif event == "COMMODITY_PURCHASE_FAILED" then
		if pendingBuy then
			CancelPendingCommodity(string.format(L["SNIPE_BUY_FAILED"], pendingBuy.label), pendingBuy.itemID, nil)
		end
	elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
		if pendingBuy then
			local bought = pendingBuy
			pendingBuy = nil
			local totalSpent = bought.totalPrice or ((bought.unitPrice or 0) * bought.qty)
			ns:Print(string.format(L["SNIPE_BUY_DONE"], bought.label, bought.qty, ns.FormatMoney(totalSpent), ns.FormatMoney(bought.maxPrice)))
			ClearStaleSnipeHit(bought.itemID, nil)
			ns:RefreshSnipeUI()
		end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if pendingBuy then
			CancelPendingCommodity(nil, nil)
		end
		if snipeBar then
			snipeBar:Hide()
		end
	elseif next(ns:GetSnipeTargets()) ~= nil then
		ns:RefreshSnipeUI()
	end
end)
