local mod = dmhub.GetModLoading()

local SETTING_ID = "enemyactionprivacy:hideenemyactions"
local MESSAGE_MARKER = "enemyActionDirectorOnly"
local STATE_KEY = "g_hideEnemyActionsModState"
local CLEANUP_DELAY = 1.0

setting{
    id = SETTING_ID,
    description = "Hide Enemy Actions from Players",
    editor = "check",
    default = true,
    storage = "game",
    section = "game",
    classes = {"dmonly"},
}

local state = rawget(_G, STATE_KEY)
if state == nil then
    state = {}
    rawset(_G, STATE_KEY, state)
end

-- A hot reload can leave wrappers installed until the old unload handler runs.
-- Remove those wrappers before installing this version.
if state.uninstall ~= nil then
    state.uninstall()
end

state.installed = false
state.uninstall = nil
state.activeCasts = {}
state.hiddenCasterCounts = {}
state.pendingCasterCounts = {}
state.seenMessageKeys = {}
state.scannerRunning = false

local function Enabled()
    return dmhub.GetSettingValue(SETTING_ID) == true
end

local function SafeTryGet(obj, field, defaultValue)
    if obj == nil then
        return defaultValue
    end

    local result = defaultValue
    pcall(function()
        result = obj:try_get(field, defaultValue)
    end)
    return result
end

local function SafeMessageField(message, field, defaultValue)
    local result = defaultValue
    pcall(function()
        result = message[field]
    end)
    return result
end

local function IsEnemyToken(token)
    if token == nil or not token.valid then
        return false
    end

    local isFriend = true
    local ok = pcall(function()
        isFriend = token.isFriendOfPlayer
    end)

    -- Fail open if relationship data cannot be read from a stale token.
    return ok and isFriend == false
end

local function IsEnemyCastMessage(properties)
    local casterid = SafeTryGet(properties, "casterid", nil)
    if casterid == nil then
        return false
    end

    local token = nil
    pcall(function()
        token = dmhub.GetCharacterById(casterid)
    end)
    return IsEnemyToken(token)
end

local function AdjustCount(t, key, delta)
    if key == nil then
        return
    end

    local value = (t[key] or 0) + delta
    if value <= 0 then
        t[key] = nil
    else
        t[key] = value
    end
end

local function CasterIsHidden(casterid)
    if casterid == nil then
        return false
    end
    return (state.hiddenCasterCounts[casterid] or 0) > 0
        or (state.pendingCasterCounts[casterid] or 0) > 0
end

local function AnyHiddenCast()
    return next(state.activeCasts) ~= nil or next(state.pendingCasterCounts) ~= nil
end

local function BaselineMessages()
    for _,message in ipairs(chat.messages) do
        local key = SafeMessageField(message, "key", nil)
        if key ~= nil then
            state.seenMessageKeys[key] = true
        end
    end
end

local function MarkMessageDirectorOnly(message)
    if not dmhub.isDM then
        return
    end
    pcall(function()
        message.gmonly = true
    end)
end

local function MessageBelongsToHiddenAction(message)
    if not Enabled() or not dmhub.isDM then
        return false
    end

    local userid = SafeMessageField(message, "userid", nil)
    if userid ~= dmhub.userid then
        return false
    end

    local messageType = SafeMessageField(message, "messageType", nil)
    local properties = SafeMessageField(message, "properties", nil)

    if messageType == "roll" then
        local castid = SafeTryGet(properties, "castid", nil)
        if castid ~= nil and state.activeCasts[castid] ~= nil then
            return true
        end

        local tokenid = SafeMessageField(message, "tokenid", nil)
        return CasterIsHidden(tokenid)
    end

    if messageType ~= "custom" then
        return false
    end

    -- Normal chat-channel custom messages are never ability-log output.
    if SafeTryGet(properties, "channel", nil) == "chat" then
        return false
    end

    local castid = SafeTryGet(properties, "castid", nil)
    if castid ~= nil and state.activeCasts[castid] ~= nil then
        return true
    end

    local casterid = SafeTryGet(properties, "casterid", nil)
    if casterid ~= nil then
        return CasterIsHidden(casterid)
    end

    -- Some ability result cards identify only the target, not the caster. The
    -- scanner sees only NEW local messages, so while a hidden cast is active
    -- these un-attributed Action Log cards are treated as part of that action.
    return AnyHiddenCast()
end

local function ScanNewMessages()
    if mod.unloaded then
        state.scannerRunning = false
        return
    end

    for _,message in ipairs(chat.messages) do
        local key = SafeMessageField(message, "key", nil)
        if key ~= nil and not state.seenMessageKeys[key] then
            state.seenMessageKeys[key] = true
            if MessageBelongsToHiddenAction(message) then
                MarkMessageDirectorOnly(message)
            end
        end
    end

    if AnyHiddenCast() then
        dmhub.Schedule(0.05, ScanNewMessages)
    else
        state.scannerRunning = false
    end
end

local function EnsureScanner()
    if not dmhub.isDM or state.scannerRunning then
        return
    end
    state.scannerRunning = true
    dmhub.Schedule(0.05, ScanNewMessages)
end

local function TryMarkMessageKeyDirectorOnly(key)
    if key == nil then
        return true
    end

    for _,message in ipairs(chat.messages) do
        if SafeMessageField(message, "key", nil) == key then
            MarkMessageDirectorOnly(message)
            return true
        end
    end

    return false
end

local function MarkMessageKeyDirectorOnly(key, attempt)
    if not dmhub.isDM or mod.unloaded or key == nil then
        return
    end

    if TryMarkMessageKeyDirectorOnly(key) then
        return
    end

    attempt = attempt or 1
    if attempt >= 30 then
        return
    end

    dmhub.Schedule(0.05, function()
        if not mod.unloaded then
            MarkMessageKeyDirectorOnly(key, attempt + 1)
        end
    end)
end

local function RegisterHiddenCast(castid, casterid)
    if castid == nil or casterid == nil then
        return
    end

    if state.activeCasts[castid] == nil then
        state.activeCasts[castid] = casterid
        AdjustCount(state.hiddenCasterCounts, casterid, 1)
    end
    EnsureScanner()
end

local function CleanupHiddenCast(castid)
    if castid ~= nil and state.activeCasts[castid] ~= nil then
        local storedCaster = state.activeCasts[castid]
        state.activeCasts[castid] = nil
        AdjustCount(state.hiddenCasterCounts, storedCaster, -1)
    end
end

local function ScheduleHiddenCastCleanup(castid)
    dmhub.Schedule(CLEANUP_DELAY, function()
        if not mod.unloaded then
            CleanupHiddenCast(castid)
        end
    end)
end

local function ForceRollDirectorOnly(args)
    if type(args) ~= "table" then
        return
    end

    args.dmonly = true
    if type(args.rollArgs) == "table" then
        args.rollArgs.dmonly = true
    end
end

local function ShouldHideRoll(args)
    if not Enabled() or type(args) ~= "table" then
        return false
    end

    local tokenid = args.tokenid
    if tokenid == nil and type(args.rollArgs) == "table" then
        tokenid = args.rollArgs.tokenid
    end
    if CasterIsHidden(tokenid) then
        return true
    end

    local properties = args.properties
    if properties == nil and type(args.rollArgs) == "table" then
        properties = args.rollArgs.properties
    end
    local castid = SafeTryGet(properties, "castid", nil)
    return castid ~= nil and state.activeCasts[castid] ~= nil
end

local function CreateHiddenCastPanel(properties)
    return gui.Panel{
        classes = {"collapsed"},
        width = 0,
        height = 0,
        data = {
            -- Preserve castid so ActionLogPanel can adopt a linked roll into
            -- this collapsed parent if visibility synchronization races.
            castid = SafeTryGet(properties, "castid", nil),
        },
    }
end

local function InstallHooks()
    if mod.unloaded or state.installed then
        return
    end

    local activatedAbility = rawget(_G, "ActivatedAbility")
    local castMessageType = rawget(_G, "CastActivatedAbilityChatMessage")
    local rollDialog = rawget(_G, "RollDialog")

    if activatedAbility == nil or castMessageType == nil or rollDialog == nil then
        dmhub.Schedule(0.1, InstallHooks)
        return
    end

    local baseCast = activatedAbility.Cast
    local baseFinishCast = activatedAbility.FinishCast
    local baseOnBeforeRoll = rollDialog.OnBeforeRoll
    local baseCastRender = castMessageType.Render

    if type(baseCast) ~= "function" or type(baseFinishCast) ~= "function" or type(baseCastRender) ~= "function" then
        dmhub.Schedule(0.1, InstallHooks)
        return
    end

    local wrappedCast
    local wrappedFinishCast
    local wrappedOnBeforeRoll
    local wrappedCastRender

    wrappedCast = function(self, casterToken, targets, options)
        options = options or {}
        local hideThisCast = Enabled() and IsEnemyToken(casterToken)

        if not hideThisCast then
            return baseCast(self, casterToken, targets, options)
        end

        local casterid = casterToken.charid
        options._tmp_enemyActionDirectorOnly = true
        options._tmp_enemyActionCasterId = casterid

        if not AnyHiddenCast() then
            BaselineMessages()
        end
        AdjustCount(state.pendingCasterCounts, casterid, 1)
        EnsureScanner()

        local pendingGuard <close> = setmetatable({}, {
            __close = function()
                AdjustCount(state.pendingCasterCounts, casterid, -1)
            end,
        })

        local results = table.pack(baseCast(self, casterToken, targets, options))

        local castid = nil
        if type(options.symbols) == "table" then
            castid = options.symbols.castid
        end
        RegisterHiddenCast(castid, casterid)

        if options.chatMessage ~= nil then
            pcall(function()
                options.chatMessage[MESSAGE_MARKER] = true
            end)
            if options.chatMessageKey ~= nil then
                pcall(function()
                    chat.UpdateCustom(options.chatMessageKey, options.chatMessage)
                end)
            end
        end
        MarkMessageKeyDirectorOnly(options.chatMessageKey, 1)

        return table.unpack(results, 1, results.n)
    end

    wrappedFinishCast = function(self, casterToken, options, ...)
        if type(options) == "table" and options._tmp_enemyActionDirectorOnly == true then
            local castid = nil
            if type(options.symbols) == "table" then
                castid = options.symbols.castid
            end
            ScheduleHiddenCastCleanup(castid)
        end
        return baseFinishCast(self, casterToken, options, ...)
    end

    wrappedOnBeforeRoll = function(args)
        local hide = ShouldHideRoll(args)
        if hide then
            ForceRollDirectorOnly(args)
        end

        if type(baseOnBeforeRoll) == "function" then
            local results = table.pack(baseOnBeforeRoll(args))
            if hide then
                -- A pre-existing roll hook may mutate rollArgs, so enforce the
                -- Director-only flag again after it returns.
                ForceRollDirectorOnly(args)
            end
            return table.unpack(results, 1, results.n)
        end

        return nil
    end

    wrappedCastRender = function(properties, message)
        if not dmhub.isDM and Enabled() then
            local marked = SafeTryGet(properties, MESSAGE_MARKER, false) == true
            if marked or IsEnemyCastMessage(properties) then
                return CreateHiddenCastPanel(properties)
            end
        end

        return baseCastRender(properties, message)
    end

    activatedAbility.Cast = wrappedCast
    activatedAbility.FinishCast = wrappedFinishCast
    rollDialog.OnBeforeRoll = wrappedOnBeforeRoll
    castMessageType.Render = wrappedCastRender
    state.installed = true

    local function UninstallHooks()
        if rawget(_G, "ActivatedAbility") == activatedAbility then
            if activatedAbility.Cast == wrappedCast then
                activatedAbility.Cast = baseCast
            end
            if activatedAbility.FinishCast == wrappedFinishCast then
                activatedAbility.FinishCast = baseFinishCast
            end
        end
        if rawget(_G, "RollDialog") == rollDialog and rollDialog.OnBeforeRoll == wrappedOnBeforeRoll then
            rollDialog.OnBeforeRoll = baseOnBeforeRoll
        end
        if rawget(_G, "CastActivatedAbilityChatMessage") == castMessageType and castMessageType.Render == wrappedCastRender then
            castMessageType.Render = baseCastRender
        end

        state.activeCasts = {}
        state.hiddenCasterCounts = {}
        state.pendingCasterCounts = {}
        state.scannerRunning = false
        state.installed = false
        if state.uninstall == UninstallHooks then
            state.uninstall = nil
        end
    end

    state.uninstall = UninstallHooks
    mod.unloadHandlers[#mod.unloadHandlers + 1] = UninstallHooks
end

InstallHooks()
