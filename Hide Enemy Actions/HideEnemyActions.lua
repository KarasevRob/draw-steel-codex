local mod = dmhub.GetModLoading()

local SETTING_ID = "enemyactionprivacy:hideenemyactions"
local MESSAGE_MARKER = "enemyActionDirectorOnly"
local STATE_KEY = "g_hideEnemyActionsModState"

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

-- A hot reload can leave the previous wrappers installed until its unload
-- handler runs. Remove them first so this load always wraps the real functions.
if state.uninstall ~= nil then
    state.uninstall()
end

state.currentEnemyCastDepth = 0
state.currentEnemyCasterId = nil
state.installed = false
state.uninstall = nil

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

local function IsEnemyToken(token)
    if token == nil or not token.valid then
        return false
    end

    local isFriend = true
    local ok = pcall(function()
        isFriend = token.isFriendOfPlayer
    end)

    -- Fail open if the relationship cannot be read. A broken or stale token
    -- should not make an otherwise valid action disappear from the log.
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

local function ShouldHideCurrentCast()
    return Enabled() and (state.currentEnemyCastDepth or 0) > 0
end

local function MarkPropertiesForPlayerFallback(properties)
    if properties == nil then
        return
    end

    -- This serialized marker is only a race fallback. The Director also marks
    -- the ChatMessageInfo GM-only, which is the authoritative visibility state.
    pcall(function()
        properties[MESSAGE_MARKER] = true
    end)
end

local function TryMarkChatMessageDirectorOnly(key)
    if key == nil then
        return true
    end

    for _,message in ipairs(chat.messages) do
        local messageKey = nil
        pcall(function()
            messageKey = message.key
        end)

        if messageKey == key then
            local ok = pcall(function()
                message.gmonly = true
            end)
            return ok
        end
    end

    return false
end

local function MarkChatMessageDirectorOnly(key, attempt)
    if not dmhub.isDM or mod.unloaded then
        return
    end

    if TryMarkChatMessageDirectorOnly(key) then
        return
    end

    -- SendCustom can return before the local chat list receives its server
    -- echo. Retry briefly so the visibility flag is applied as soon as it exists.
    attempt = attempt or 1
    if attempt >= 20 then
        return
    end

    dmhub.Schedule(0.05, function()
        if mod.unloaded then
            return
        end
        MarkChatMessageDirectorOnly(key, attempt + 1)
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

local function CreateHiddenCastPanel(properties)
    return gui.Panel{
        classes = {"collapsed"},
        width = 0,
        height = 0,
        data = {
            -- Keep castid even while collapsed. ActionLogPanel can still adopt
            -- a linked roll into this hidden parent if one races visibility sync.
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
    local chatApi = rawget(_G, "chat")

    if activatedAbility == nil or castMessageType == nil or rollDialog == nil or chatApi == nil then
        dmhub.Schedule(0.1, InstallHooks)
        return
    end

    local baseCast = activatedAbility.Cast
    local baseSendCustom = chatApi.SendCustom
    local baseOnBeforeRoll = rollDialog.OnBeforeRoll
    local baseCastRender = castMessageType.Render

    if type(baseCast) ~= "function" or type(baseSendCustom) ~= "function" or type(baseCastRender) ~= "function" then
        dmhub.Schedule(0.1, InstallHooks)
        return
    end

    local wrappedCast
    local wrappedSendCustom
    local wrappedOnBeforeRoll
    local wrappedCastRender

    wrappedCast = function(self, casterToken, ...)
        if not Enabled() or not IsEnemyToken(casterToken) then
            return baseCast(self, casterToken, ...)
        end

        local previousDepth = state.currentEnemyCastDepth or 0
        local previousCasterId = state.currentEnemyCasterId
        state.currentEnemyCastDepth = previousDepth + 1
        state.currentEnemyCasterId = casterToken.charid

        -- Lua 5.4 close variables restore the cast state even if the underlying
        -- cast errors. The guard stays alive while a coroutine yields mid-cast.
        local guard <close> = setmetatable({}, {
            __close = function()
                state.currentEnemyCastDepth = previousDepth
                state.currentEnemyCasterId = previousCasterId
            end,
        })

        return baseCast(self, casterToken, ...)
    end

    wrappedSendCustom = function(properties, ...)
        local hide = ShouldHideCurrentCast()
        if hide then
            MarkPropertiesForPlayerFallback(properties)
        end

        local key = baseSendCustom(properties, ...)
        if hide and dmhub.isDM then
            MarkChatMessageDirectorOnly(key, 1)
        end
        return key
    end

    wrappedOnBeforeRoll = function(args)
        local hide = ShouldHideCurrentCast()
        if hide then
            ForceRollDirectorOnly(args)
        end

        if type(baseOnBeforeRoll) == "function" then
            local results = table.pack(baseOnBeforeRoll(args))
            if hide then
                -- Another roll hook may mutate rollArgs, so enforce privacy
                -- again after it returns.
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
    chatApi.SendCustom = wrappedSendCustom
    rollDialog.OnBeforeRoll = wrappedOnBeforeRoll
    castMessageType.Render = wrappedCastRender

    state.installed = true

    local function UninstallHooks()
        if rawget(_G, "ActivatedAbility") == activatedAbility and activatedAbility.Cast == wrappedCast then
            activatedAbility.Cast = baseCast
        end
        if rawget(_G, "chat") == chatApi and chatApi.SendCustom == wrappedSendCustom then
            chatApi.SendCustom = baseSendCustom
        end
        if rawget(_G, "RollDialog") == rollDialog and rollDialog.OnBeforeRoll == wrappedOnBeforeRoll then
            rollDialog.OnBeforeRoll = baseOnBeforeRoll
        end
        if rawget(_G, "CastActivatedAbilityChatMessage") == castMessageType and castMessageType.Render == wrappedCastRender then
            castMessageType.Render = baseCastRender
        end

        state.currentEnemyCastDepth = 0
        state.currentEnemyCasterId = nil
        state.installed = false
        if state.uninstall == UninstallHooks then
            state.uninstall = nil
        end
    end

    state.uninstall = UninstallHooks
    mod.unloadHandlers[#mod.unloadHandlers + 1] = UninstallHooks
end

InstallHooks()
