local mod = dmhub.GetModLoading()

--Hero modules: modules of hero options (classes, ancestries, kits) that a
--player keeps in their inventory and switches on or off from the titlescreen.
--An enabled one is installed into the lobby game, where heroes are built,
--through ModuleLua:InstallAsHeroModule, which only uses versions whose code an
--admin approved. A disabled one is uninstalled from the lobby so its code stops
--running too.
--
--The inventory is an account setting, so it follows the player between
--machines (the lobby game itself is stored locally on each machine):
--  { [moduleid] = { enabled = boolean, added = unix time } }
--A free module is in the inventory once added. A premium Hero module the player
--owns is always in it, enabled unless its entry says otherwise.
local g_heroModulesSetting = setting{
	id = "heromodules",
	description = "Hero Modules",
	storage = "account",
	default = {},
}

--- @class HeroModuleEntry
--- @field enabled boolean
--- @field added number

--- @class HeroModuleItem
--- @field module ModuleLua
--- @field enabled boolean
--- @field added boolean True if the player added it; false for an owned premium module.

--- @return table<string, HeroModuleEntry>
local function GetEntries()
	local result = {}
	local stored = g_heroModulesSetting:Get()
	if type(stored) == "table" then
		for k, v in pairs(stored) do
			if type(k) == "string" and type(v) == "table" then
				result[k] = { enabled = v.enabled ~= false, added = tonumber(v.added) or 0 }
			end
		end
	end
	return result
end

--- @param entries table<string, HeroModuleEntry>
local function SetEntries(entries)
	--a fresh table every time: the setting layer compares by identity.
	g_heroModulesSetting:Set(entries)
end

--Shared with the titlescreen and the shop (other files of the core codex).
HeroModules = {}

--- True if the player added this module to their inventory.
--- @param moduleid string
--- @return boolean
function HeroModules.IsAdded(moduleid)
	return GetEntries()[moduleid] ~= nil
end

--- True unless the player switched this module off. Only meaningful for a
--- module in the inventory.
--- @param moduleid string
--- @return boolean
function HeroModules.IsEnabled(moduleid)
	local entry = GetEntries()[moduleid]
	return entry == nil or entry.enabled
end

--- Adds a module to the inventory, enabled, and brings it into the lobby.
--- @param moduleid string
function HeroModules.Add(moduleid)
	local entries = GetEntries()
	entries[moduleid] = { enabled = true, added = os.time() }
	SetEntries(entries)
	HeroModules.SyncLobby()
end

--- Removes a module the player added. An owned premium module stays in the
--- inventory; use SetEnabled to switch it off.
--- @param moduleid string
function HeroModules.Remove(moduleid)
	local entries = GetEntries()
	entries[moduleid] = nil
	SetEntries(entries)
	HeroModules.SyncLobby()
end

--- @param moduleid string
--- @param enabled boolean
function HeroModules.SetEnabled(moduleid, enabled)
	local entries = GetEntries()
	local existing = entries[moduleid]
	entries[moduleid] = { enabled = enabled, added = existing ~= nil and existing.added or os.time() }
	SetEntries(entries)
	HeroModules.SyncLobby()
end

--- Downloads fresh records for every module in the inventory: the ones the
--- player added, plus the premium Hero modules they own. Calls back once with
--- the list, sorted by name. A module whose record can't be downloaded is left
--- out of this list but stays in the inventory.
--- @param callback fun(items: HeroModuleItem[])
function HeroModules.CollectInventory(callback)
	local entries = GetEntries()

	--moduleid -> true if the player added it.
	local ids = {}
	for id, _ in pairs(entries) do
		ids[id] = true
	end
	for _, list in ipairs({ module.GetOurPurchasedModules(), module.GetOurPatreonModules() }) do
		for _, id in ipairs(list) do
			if ids[id] == nil then
				ids[id] = false
			end
		end
	end

	local items = {}
	local pending = 0
	local finished = false

	local Finish = function()
		if pending > 0 or finished then
			return
		end
		finished = true
		table.sort(items, function(a, b)
			return string.lower(a.module.name or "") < string.lower(b.module.name or "")
		end)
		callback(items)
	end

	for id, added in pairs(ids) do
		pending = pending + 1
		module.DownloadModuleInfo{
			moduleid = id,
			success = function(info)
				--a purchased module counts only if it is a Hero module the player
				--may use; a module they added is listed even if it can't be used
				--yet, so the inventory can say why.
				if info.isHeroModule and (added or info.owned) then
					local entry = entries[id]
					items[#items+1] = {
						module = info,
						enabled = entry == nil or entry.enabled,
						added = added,
					}
				end
				pending = pending - 1
				Finish()
			end,
			failure = function(message)
				print(string.format("HeroModules: could not download module %s: %s", id, tostring(message)))
				pending = pending - 1
				Finish()
			end,
		}
	end

	Finish()
end

--moduleid -> the last error installing it into the lobby, for the inventory
--UI to show (e.g. "waiting for review by an admin").
local g_lastErrors = {}

--- The last error from bringing this module into the lobby, or nil.
--- @param moduleid string
--- @return nil|string
function HeroModules.GetError(moduleid)
	return g_lastErrors[moduleid]
end

local g_syncing = false
local g_syncAgain = false

--- Brings the lobby game in line with the inventory: installs each enabled
--- Hero module the player may use and uninstalls the rest. Only acts in the
--- lobby game. Installs run one at a time; a call made while a sync is running
--- queues one more pass.
function HeroModules.SyncLobby()
	if not dmhub.isLobbyGame then
		return
	end
	if g_syncing then
		g_syncAgain = true
		return
	end
	g_syncing = true

	HeroModules.CollectInventory(function(items)
		if mod.unloaded or not dmhub.isLobbyGame then
			g_syncing = false
			return
		end

		--each step is a function(next) that calls next() when done.
		local steps = {}
		local wanted = {}
		for _, item in ipairs(items) do
			local info = item.module
			local fullid = info.fullid
			local usable = (not info.premium) or info.owned
			if item.enabled and usable then
				wanted[fullid] = true
				steps[#steps+1] = function(nextStep)
					if info.isdisabled then
						info:SetDisabled(false)
					end
					info:InstallAsHeroModule{
						success = function()
							g_lastErrors[fullid] = nil
							nextStep()
						end,
						error = function(message)
							g_lastErrors[fullid] = message
							print(string.format("HeroModules: %s not installed in the lobby: %s", fullid, message))
							nextStep()
						end,
					}
				end
			end
		end

		--Hero modules installed in the lobby that the inventory no longer wants.
		for _, info in ipairs(module.GetLoadedModules()) do
			local fullid = info.fullid
			if info.isHeroModule and info.installedVersion ~= nil and not wanted[fullid] then
				steps[#steps+1] = function(nextStep)
					g_lastErrors[fullid] = nil
					info:Uninstall{}
					nextStep()
				end
			end
		end

		local index = 0
		local RunNext
		RunNext = function()
			if mod.unloaded then
				g_syncing = false
				return
			end
			index = index + 1
			local step = steps[index]
			if step ~= nil then
				step(RunNext)
				return
			end

			g_syncing = false
			if g_syncAgain then
				g_syncAgain = false
				HeroModules.SyncLobby()
			end
		end
		RunNext()
	end)
end
