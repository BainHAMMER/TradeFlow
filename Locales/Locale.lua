local ADDON_NAME, ns = ...
_G.TradeFlow = ns

ns.LANGS = {
	{ key = "ru", name = "Русский", short = "RU", client = "ruRU" },
	{ key = "en", name = "English", short = "EN", client = "enUS" },
}

ns.Locales = {
	ru = {},
	en = {},
}

function ns.DefaultLanguage()
	local loc = GetLocale and GetLocale() or "enUS"
	if loc == "ruRU" then
		return "ru"
	end
	return "en"
end

ns.lang = ns.DefaultLanguage()

ns.L = setmetatable({}, {
	__index = function(_, key)
		local active = ns.Locales[ns.lang]
		if active and active[key] then
			return active[key]
		end
		local ru = ns.Locales.ru
		if ru and ru[key] then
			return ru[key]
		end
		local en = ns.Locales.en
		if en and en[key] then
			return en[key]
		end
		return key
	end,
})

function ns:SetLanguage(lang)
	if lang ~= "ru" and lang ~= "en" then
		return
	end
	if self.lang == lang then
		return
	end
	self.lang = lang
	if self.db then
		self.db.lang = lang
	end
	if self.RebuildMainFrame then
		self:RebuildMainFrame()
	end
	if self.RefreshVendorBar then
		self:RefreshVendorBar()
	end
end

function ns:ToggleLanguage()
	self:SetLanguage(self.lang == "ru" and "en" or "ru")
end

