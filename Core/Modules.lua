local _, ns = ...
local L = ns.L

-------------------------------------------------------------------------------
-- Лёгкий реестр подключаемых модулей (вкладки, настройки и жизненный цикл)
-------------------------------------------------------------------------------
ns.modules = {
	byId = {},
	order = {},
}

function ns:RegisterModule(mod)
	if not mod or not mod.id or self.modules.byId[mod.id] then
		return
	end
	self.modules.byId[mod.id] = mod
	self.modules.order[#self.modules.order + 1] = mod.id
	if self.db and self.db.options and mod.optionKey and self.db.options[mod.optionKey] == nil then
		self.db.options[mod.optionKey] = (mod.defaultEnabled ~= false)
	end
end

function ns:InitModules()
	if not (self.db and self.db.options) then
		return
	end
	for _, id in ipairs(self.modules.order) do
		local mod = self.modules.byId[id]
		if mod and mod.optionKey and self.db.options[mod.optionKey] == nil then
			self.db.options[mod.optionKey] = (mod.defaultEnabled ~= false)
		end
		if mod and self:IsModuleEnabled(id) and mod.OnEnable then
			mod:OnEnable()
		end
	end
end

function ns:IsModuleEnabled(id)
	local mod = id and self.modules.byId[id]
	if not mod then
		return false
	end
	if not mod.optionKey then
		return mod.defaultEnabled ~= false
	end
	local opts = self.db and self.db.options
	if not opts or opts[mod.optionKey] == nil then
		return mod.defaultEnabled ~= false
	end
	return opts[mod.optionKey] == true
end

function ns:SetModuleEnabled(id, enabled)
	local mod = id and self.modules.byId[id]
	if not mod then
		return
	end
	if self.db and self.db.options and mod.optionKey then
		self.db.options[mod.optionKey] = enabled and true or false
	end
	if enabled then
		if mod.OnEnable then
			mod:OnEnable()
		end
	else
		if mod.OnDisable then
			mod:OnDisable()
		end
	end
	if self.mainFrame and self.mainFrame.RefreshTopTabs then
		self.mainFrame.RefreshTopTabs()
	end
end

function ns:GetTopTabModules()
	local res = {}
	for _, id in ipairs(self.modules.order) do
		local mod = self.modules.byId[id]
		if mod and mod.CreateView and mod.tabTitleKey then
			res[#res + 1] = mod
		end
	end
	return res
end

function ns:GetModuleSettingsSpecs()
	local res = {}
	for _, id in ipairs(self.modules.order) do
		local mod = self.modules.byId[id]
		if mod and mod.optionKey and mod.settingsLabelKey then
			res[#res + 1] = {
				key = mod.optionKey,
				label = L[mod.settingsLabelKey] or id,
				defaultTrue = (mod.defaultEnabled ~= false),
				moduleId = id,
			}
		end
	end
	return res
end

function ns:NotifyModules(hookName, ...)
	for _, id in ipairs(self.modules.order) do
		local mod = self.modules.byId[id]
		if mod and self:IsModuleEnabled(id) and type(mod[hookName]) == "function" then
			mod[hookName](mod, ...)
		end
	end
end

function ns:NotifyAllModules(hookName, ...)
	for _, id in ipairs(self.modules.order) do
		local mod = self.modules.byId[id]
		if mod and type(mod[hookName]) == "function" then
			mod[hookName](mod, ...)
		end
	end
end
