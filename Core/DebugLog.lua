local ADDON_NAME, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Диагностический лог: перехват ADDON_ACTION_BLOCKED / FORBIDDEN, Lua-ошибок
-- TradeFlow и следа последних вызовов для разбора taint и сбоев API.
-------------------------------------------------------------------------------
local MAX_LOG_ENTRIES = 80
local MAX_BREADCRUMBS = 15
local breadcrumbs = {}
local lastChatAlertAt = 0
local logFrame = nil

local function NowStamp()
	return (date and date("%Y-%m-%d %H:%M:%S")) or tostring(math.floor((GetTime and GetTime() or 0) + 0.5))
end

local function ShortStack(skip)
	if not debugstack then
		return ""
	end
	local raw = debugstack(skip or 3, 6, 3)
	if type(raw) ~= "string" then
		return ""
	end
	local lines = {}
	for line in raw:gmatch("[^\r\n]+") do
		local clean = line:gsub("Interface\\AddOns\\", "")
		lines[#lines + 1] = clean
		if #lines >= 6 then
			break
		end
	end
	return table.concat(lines, " <- ")
end

local function AppendEntry(kind, source, message, stack)
	local db = ns.db or TradeFlowDB
	if type(db) ~= "table" then
		return
	end
	db.debugLog = db.debugLog or {}
	local log = db.debugLog

	local trace = {}
	local nowT = GetTime and GetTime() or 0
	for i = math.max(1, #breadcrumbs - 4), #breadcrumbs do
		local b = breadcrumbs[i]
		if b then
			local age = nowT > 0 and string.format("-%.1fs", math.max(0, nowT - b.t)) or "?"
			trace[#trace + 1] = age .. " " .. b.msg
		end
	end

	log[#log + 1] = {
		ts = NowStamp(),
		kind = kind,
		source = source or "",
		msg = tostring(message or ""),
		stack = stack or "",
		trace = table.concat(trace, " | "),
		combat = (InCombatLockdown and InCombatLockdown()) and true or false,
	}
	while #log > MAX_LOG_ENTRIES do
		table.remove(log, 1)
	end
end

function ns:LogTrace(tag, detail)
	local msg = detail and (tostring(tag) .. ": " .. tostring(detail)) or tostring(tag)
	breadcrumbs[#breadcrumbs + 1] = {
		t = GetTime and GetTime() or 0,
		msg = msg,
	}
	while #breadcrumbs > MAX_BREADCRUMBS do
		table.remove(breadcrumbs, 1)
	end
end

function ns:SafeCall(tag, fn, ...)
	if type(fn) ~= "function" then
		return false, "not a function"
	end
	local res = { pcall(fn, ...) }
	if not res[1] then
		AppendEntry("PCALL_ERR", ADDON_NAME, tostring(tag) .. ": " .. tostring(res[2]), ShortStack(3))
		return false, res[2]
	end
	return unpack(res)
end

local function IsLikelyOurs(source, msg, stack)
	if source == ADDON_NAME then
		return true
	end
	if type(msg) == "string" and msg:find(ADDON_NAME, 1, true) then
		return true
	end
	if type(stack) == "string" and stack:find(ADDON_NAME, 1, true) then
		return true
	end
	local last = breadcrumbs[#breadcrumbs]
	local nowT = GetTime and GetTime() or 0
	if last and nowT > 0 and (nowT - last.t) <= 3.0 then
		return true
	end
	return false
end

local function FormatDebugLogText()
	local log = (ns.db and ns.db.debugLog) or (TradeFlowDB and TradeFlowDB.debugLog) or {}
	if #log == 0 then
		return L["DEBUG_LOG_EMPTY"]
	end
	local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "?"
	local out = { string.format("TradeFlow DebugLog (v%s, entries: %d)", tostring(ver), #log) }
	for i = #log, 1, -1 do
		local e = log[i]
		out[#out + 1] = string.format(
			"[%s] %s (%s%s): %s",
			e.ts or "?",
			e.kind or "?",
			e.source ~= "" and e.source or "?",
			e.combat and ", combat" or "",
			e.msg or ""
		)
		if e.trace and e.trace ~= "" then
			out[#out + 1] = "  trace: " .. e.trace
		end
		if e.stack and e.stack ~= "" then
			out[#out + 1] = "  stack: " .. e.stack
		end
	end
	return table.concat(out, "\n")
end

function ns:ShowDebugLogWindow()
	if not logFrame then
		local f = CreateFrame("Frame", "TradeFlowDebugLogFrame", UIParent, "BackdropTemplate")
		f:SetSize(640, 420)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetToplevel(true)
		f:SetClampedToScreen(true)
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		f:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 16, edgeSize = 20,
			insets = { left = 5, right = 5, top = 5, bottom = 5 },
		})
		f:SetBackdropColor(0.06, 0.055, 0.05, 0.98)

		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 14, -12)
		title:SetText("|cffffd100" .. L["DEBUG_LOG_TITLE"] .. "|r")

		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -4, -4)

		local scroll = CreateFrame("ScrollFrame", "TradeFlowDebugLogScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 14, -38)
		scroll:SetPoint("BOTTOMRIGHT", -32, 40)

		local box = CreateFrame("EditBox", nil, scroll)
		box:SetMultiLine(true)
		box:SetAutoFocus(false)
		box:SetFontObject("ChatFontNormal")
		box:SetWidth(585)
		box:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(box)
		f.box = box

		local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		refreshBtn:SetSize(100, 22)
		refreshBtn:SetPoint("BOTTOMLEFT", 14, 10)
		refreshBtn:SetText(L["DEBUG_LOG_REFRESH"])
		refreshBtn:SetScript("OnClick", function()
			box:SetText(FormatDebugLogText())
			box:HighlightText()
			box:SetFocus()
		end)

		local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		clearBtn:SetSize(100, 22)
		clearBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
		clearBtn:SetText(L["QUEUE_CLEAR"])
		clearBtn:SetScript("OnClick", function()
			if ns.db then
				ns.db.debugLog = {}
			end
			box:SetText(FormatDebugLogText())
		end)

		if UISpecialFrames then
			tinsert(UISpecialFrames, "TradeFlowDebugLogFrame")
		end
		logFrame = f
	end

	logFrame.box:SetText(FormatDebugLogText())
	logFrame.box:HighlightText()
	logFrame:Show()
end

local debugFrame = CreateFrame("Frame")
for _, ev in ipairs({
	"PLAYER_LOGIN",
	"ADDON_ACTION_BLOCKED",
	"ADDON_ACTION_FORBIDDEN",
	"MACRO_ACTION_BLOCKED",
	"MACRO_ACTION_FORBIDDEN",
	"LUA_WARNING",
	"UI_ERROR_MESSAGE",
}) do
	pcall(debugFrame.RegisterEvent, debugFrame, ev)
end

debugFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "PLAYER_LOGIN" then
		if geterrorhandler and seterrorhandler and not ns._errHooked then
			ns._errHooked = true
			local prev = geterrorhandler()
			seterrorhandler(function(msg)
				local stack = ShortStack(3)
				if IsLikelyOurs(nil, msg, stack) then
					AppendEntry("LUA_ERR", ADDON_NAME, msg, stack)
				end
				if prev then
					return prev(msg)
				end
			end)
		end
		return
	end

	local stack = ShortStack(3)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		local kind = (event == "ADDON_ACTION_BLOCKED") and "BLOCKED" or "FORBIDDEN"
		AppendEntry(kind, arg1, arg2, stack)
		if IsLikelyOurs(arg1, arg2, stack) then
			local tNow = GetTime and GetTime() or 0
			if (tNow - lastChatAlertAt) > 10 then
				lastChatAlertAt = tNow
				if ns.Print then
					ns:Print(string.format(L["DEBUG_BLOCKED_CHAT"], kind, tostring(arg1 or "?"), tostring(arg2 or "?")))
				end
			end
		end
	elseif event == "MACRO_ACTION_BLOCKED" or event == "MACRO_ACTION_FORBIDDEN" then
		local last = breadcrumbs[#breadcrumbs]
		local nowT = GetTime and GetTime() or 0
		if last and nowT > 0 and (nowT - last.t) <= 3.0 then
			AppendEntry(event, "macro", arg1, stack)
		end
	elseif event == "LUA_WARNING" then
		local msg = tostring(arg2 or arg1 or "")
		if msg:find(ADDON_NAME, 1, true) or stack:find(ADDON_NAME, 1, true) then
			AppendEntry("WARNING", ADDON_NAME, msg, stack)
		end
	elseif event == "UI_ERROR_MESSAGE" then
		local last = breadcrumbs[#breadcrumbs]
		local nowT = GetTime and GetTime() or 0
		if ns.bankWithdrawJob or (last and nowT > 0 and (nowT - last.t) <= 2.0 and last.msg:find("Bank", 1, true)) then
			local errMsg = tostring(arg2 or arg1 or "")
			if errMsg ~= "" then
				AppendEntry("UI_ERROR", ADDON_NAME, errMsg, "")
			end
		end
	end
end)
