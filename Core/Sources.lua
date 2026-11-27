local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Источники неизученных рецептов: свитки/чертежи + QuestieDB / AtlasLoot / TomTom
-------------------------------------------------------------------------------

local scrollSourceCache = {}
local questieZones = nil
local questieZonesChecked = false

local function GetAtlasLootRecipeAPI()
	local data = type(AtlasLoot) == "table" and AtlasLoot.Data
	local recipes = type(data) == "table" and data.Recipe
	if type(recipes) == "table"
		and type(recipes.GetRecipeForSpell) == "function"
		and type(recipes.GetRecipeData) == "function" then
		return recipes
	end
	return nil
end

local function GetAtlasLootDropChance(npcID, itemID)
	local data = type(AtlasLoot) == "table" and AtlasLoot.Data
	local rates = type(data) == "table" and data.Droprate
	if type(rates) == "table" and type(rates.GetData) == "function" then
		local ok, chance = pcall(rates.GetData, rates, npcID, itemID)
		if ok and type(chance) == "number" and chance > 0 then
			return chance
		end
	end
	return nil
end

local function GetQuestieDB()
	local db = _G.LibQuestieDB
	if type(db) ~= "table"
		or type(db.Item) ~= "table" or type(db.Item.GetAll) ~= "function"
		or type(db.Npc) ~= "table" or type(db.Npc.GetAll) ~= "function"
		or type(db.Quest) ~= "table" or type(db.Quest.GetAll) ~= "function" then
		return nil
	end
	return db
end

local function EvalLuaTable(source)
	if type(source) ~= "string" then
		return nil
	end
	local chunk = loadstring(source)
	if not chunk then
		return nil
	end
	setfenv(chunk, {})
	local ok, val = pcall(chunk)
	return ok and type(val) == "table" and val or nil
end

local function GetQuestieZones(db)
	if questieZonesChecked then
		return questieZones
	end
	questieZonesChecked = true
	local zoneDB = type(db.Support) == "table" and type(db.Support.Get) == "function" and db.Support.Get("ZoneDB")
	local priv = type(zoneDB) == "table" and zoneDB.private
	if type(priv) ~= "table" then
		return nil
	end
	local area = EvalLuaTable(priv.areaIdToUiMapId)
	local parent = EvalLuaTable(priv.subZoneToParentZone)
	if not (area and parent) then
		return nil
	end
	questieZones = {
		area = area,
		areaOverride = EvalLuaTable(priv.areaIdToUiMapIdOverride) or {},
		parent = parent,
		parentOverride = EvalLuaTable(priv.subZoneToParentZoneOverride) or {},
	}
	return questieZones
end

local function ResolveMapID(db, areaID)
	if type(areaID) ~= "number" or areaID <= 0 then
		return nil
	end
	local z = GetQuestieZones(db)
	if not z then
		return nil
	end
	local mapID = z.areaOverride[areaID] or z.area[areaID]
	if not mapID then
		local parentID = z.parentOverride[areaID] or z.parent[areaID]
		if parentID then
			mapID = z.areaOverride[parentID] or z.area[parentID]
		end
	end
	return type(mapID) == "number" and mapID or nil
end

local function IsNpcFriendly(friendly)
	if not friendly or friendly == "" or friendly == "AH" then
		return true
	end
	local faction = UnitFactionGroup("player")
	if faction == "Alliance" then
		return friendly == "A"
	elseif faction == "Horde" then
		return friendly == "H"
	end
	return true
end

local function PickSpawnPoint(spawns, homeZone)
	if type(spawns) ~= "table" then
		return homeZone, nil, nil
	end
	local area = (type(homeZone) == "number" and type(spawns[homeZone]) == "table") and homeZone or nil
	if not area then
		for cand in pairs(spawns) do
			if type(cand) == "number" and (not area or cand < area) then
				area = cand
			end
		end
	end
	local coords = area and spawns[area]
	if type(coords) == "table" then
		for _, xy in ipairs(coords) do
			local x, y = tonumber(xy[1]), tonumber(xy[2])
			if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
				return area, x / 100, y / 100
			end
		end
	end
	return area or homeZone, nil, nil
end

local function GetNpcLocation(db, npcID)
	local ok, vals = pcall(db.Npc.GetAll, npcID, { "name", "spawns", "zoneID", "friendlyToFaction" })
	if not ok or type(vals) ~= "table" or not vals[1] then
		return nil
	end
	local name = vals[1]
	local areaID, x, y = PickSpawnPoint(vals[2], vals[3])
	local mapID = ResolveMapID(db, areaID)
	local zoneName
	if mapID and C_Map and C_Map.GetMapInfo then
		local mOk, info = pcall(C_Map.GetMapInfo, mapID)
		if mOk and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
			zoneName = info.name
		end
	end
	if not zoneName and type(areaID) == "number" and areaID > 0 and C_Map and C_Map.GetAreaInfo then
		local zOk, zName = pcall(C_Map.GetAreaInfo, areaID)
		if zOk and type(zName) == "string" and zName ~= "" then
			zoneName = zName
		end
	end
	local text = zoneName and (name .. " (" .. zoneName .. ")") or name
	return {
		id = npcID,
		name = name,
		zone = zoneName,
		map = mapID,
		x = x,
		y = y,
		text = text,
		friendly = IsNpcFriendly(vals[4]),
	}
end

local function DistanceToNpc(loc)
	if not (loc and loc.map and loc.x and loc.y and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and UnitPosition) then
		return math.huge
	end
	local px, py, _, pInst = UnitPosition("player")
	if issecretvalue and (issecretvalue(px) or issecretvalue(py) or issecretvalue(pInst)) then
		return math.huge
	end
	if type(px) ~= "number" or type(py) ~= "number" then
		return math.huge
	end
	local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, loc.map, CreateVector2D(loc.x, loc.y))
	if not ok or not pos or inst ~= pInst then
		return math.huge
	end
	local wx, wy = pos:GetXY()
	return (px - wx) ^ 2 + (py - wy) ^ 2
end

local function CollectSortedNpcs(db, npcIDs)
	if type(npcIDs) ~= "table" or #npcIDs == 0 then
		return {}
	end
	local friendlyList, fallbackList = {}, {}
	for _, npcID in ipairs(npcIDs) do
		if type(npcID) == "number" then
			local loc = GetNpcLocation(db, npcID)
			if loc then
				if loc.friendly then
					friendlyList[#friendlyList + 1] = loc
				else
					fallbackList[#fallbackList + 1] = loc
				end
			end
		end
	end
	local list = (#friendlyList > 0) and friendlyList or fallbackList
	for _, loc in ipairs(list) do
		loc.dist = DistanceToNpc(loc)
	end
	table.sort(list, function(a, b)
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return a.id < b.id
	end)
	return list
end

-- Возвращает itemID свитка/чертежа и требуемый навык (если рецепт учится с предмета)
function ns:GetRecipeScroll(recipeID)
	local entry = self.RecipeScrolls and self.RecipeScrolls[recipeID]
	if entry then
		return entry[1], entry[2]
	end
	local al = GetAtlasLootRecipeAPI()
	if al then
		local ok, itemID = pcall(al.GetRecipeForSpell, recipeID)
		if ok and type(itemID) == "number" and itemID > 0 then
			local dOk, row = pcall(al.GetRecipeData, itemID)
			if dOk and type(row) == "table" and row[3] == recipeID then
				return itemID, tonumber(row[2])
			end
		end
	end
	return nil, nil
end

-- Возвращает данные об источнике свитка из QuestieDB / AtlasLoot:
-- summaryText (ближайший), detailText (полный список для тултипа), waypoint ({ map, x, y, title })
function ns:GetScrollItemSourceData(scrollItemID)
	if not scrollItemID then
		return nil
	end
	local db = GetQuestieDB()
	if not db then
		return nil
	end

	local cached = scrollSourceCache[scrollItemID]
	if not cached then
		local ok, vals = pcall(db.Item.GetAll, scrollItemID, { "vendors", "questRewards", "npcDrops" })
		if not ok or type(vals) ~= "table" then
			return nil
		end
		cached = {
			vendors = vals[1],
			quests = vals[2],
			drops = vals[3],
		}
		scrollSourceCache[scrollItemID] = cached
	end

	local summaryParts, detailParts = {}, {}
	local waypoint = nil

	local vendors = CollectSortedNpcs(db, cached.vendors)
	if #vendors > 0 then
		local closest = vendors[1]
		summaryParts[#summaryParts + 1] = string.format(L["SOURCE_VENDOR_FMT"], closest.text)
		local vNames = {}
		for _, v in ipairs(vendors) do
			vNames[#vNames + 1] = v.text
		end
		detailParts[#detailParts + 1] = string.format(L["SOURCE_VENDOR_FMT"], table.concat(vNames, ", "))
		if closest.map and closest.x and closest.y then
			waypoint = { map = closest.map, x = closest.x, y = closest.y, name = closest.name }
		end
	end

	if type(cached.quests) == "table" and #cached.quests > 0 then
		local qNames = {}
		for i = 1, math.min(3, #cached.quests) do
			local qOk, qVals = pcall(db.Quest.GetAll, cached.quests[i], { "name" })
			if qOk and type(qVals) == "table" and type(qVals[1]) == "string" and qVals[1] ~= "" then
				qNames[#qNames + 1] = qVals[1]
			end
		end
		if #qNames > 0 then
			summaryParts[#summaryParts + 1] = string.format(L["SOURCE_QUEST"], qNames[1])
			detailParts[#detailParts + 1] = string.format(L["SOURCE_QUEST"], table.concat(qNames, ", "))
		end
	end

	if #summaryParts == 0 then
		local drops = CollectSortedNpcs(db, cached.drops)
		if #drops > 0 then
			local closest = drops[1]
			local cChance = GetAtlasLootDropChance(closest.id, scrollItemID)
			local cText = cChance and string.format("%s %.1f%%", closest.text, cChance) or closest.text
			summaryParts[#summaryParts + 1] = string.format(L["SOURCE_DROP"], cText)

			local dNames = {}
			for i = 1, math.min(5, #drops) do
				local d = drops[i]
				local chance = GetAtlasLootDropChance(d.id, scrollItemID)
				dNames[#dNames + 1] = chance and string.format("%s %.1f%%", d.text, chance) or d.text
			end
			detailParts[#detailParts + 1] = string.format(L["SOURCE_DROP"], table.concat(dNames, ", "))
			if not waypoint and closest.map and closest.x and closest.y then
				waypoint = { map = closest.map, x = closest.x, y = closest.y, name = closest.name }
			end
		end
	end

	if #summaryParts == 0 then
		return nil
	end
	return {
		summaryText = table.concat(summaryParts, "; "),
		detailText = table.concat(detailParts, "\n"),
		waypoint = waypoint,
	}
end

function ns:HasTomTom()
	return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
end

function ns:SetSourceWaypoint(wp, label)
	if not (wp and wp.map and wp.x and wp.y) then
		return false
	end
	local title = label and (wp.name .. " - " .. label) or wp.name
	if self:HasTomTom() then
		local ok = pcall(TomTom.AddWaypoint, TomTom, wp.map, wp.x, wp.y, {
			title = title,
			persistent = false,
			minimap = true,
			world = true,
		})
		if ok then
			print("|cff00ff96TradeFlow:|r " .. string.format(L["WAYPOINT_SET"], title, wp.x * 100, wp.y * 100))
			return true
		end
	elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(wp.map, wp.x, wp.y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
		print("|cff00ff96TradeFlow:|r " .. string.format(L["WAYPOINT_SET"], title, wp.x * 100, wp.y * 100))
		return true
	end
	print("|cffff5555TradeFlow:|r " .. L["WAYPOINT_NO_ADDON"])
	return false
end

function ns:GetRecipeSourceInfo(recipeID)
	local reqSkill, trainerFee, isTrainer = self:GetRecipeRequiredSkill(recipeID)
	local scrollItemID, scrollSkill = self:GetRecipeScroll(recipeID)
	if scrollSkill and scrollSkill > 0 and (not reqSkill or reqSkill <= 1) then
		reqSkill = scrollSkill
	end
	local scrollPrice = scrollItemID and self:GetAuctionPrice(scrollItemID) or nil
	local data = scrollItemID and self:GetScrollItemSourceData(scrollItemID) or nil
	local sourceText = data and data.summaryText or nil
	local detailText = data and data.detailText or nil
	if not sourceText then
		local live = self.liveRecipes and self.liveRecipes[recipeID]
		if live and type(live.sourceText) == "string" and live.sourceText ~= "" then
			sourceText = live.sourceText
			detailText = live.sourceText
		end
	end
	return {
		isTrainer = isTrainer and true or false,
		trainerFee = trainerFee or 0,
		reqSkill = reqSkill or 1,
		scrollItemID = scrollItemID,
		scrollPrice = scrollPrice,
		sourceText = sourceText,
		detailText = detailText,
		waypoint = data and data.waypoint or nil,
	}
end
