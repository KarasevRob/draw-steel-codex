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

-- Always unwind a clean previous load before installing this one.
if state.uninstall ~= nil then
    pcall(state.uninstall)
end

-- The first published revision failed after replacing ActivatedAbility.Cast but
-- before registering its uninstall handler. There is no safe way to recover the
-- captured base function from that orphaned closure. Refuse to stack another
-- wrapper over it; restarting DMHub restores the real game-rule function.
local legacyFailedLoad = rawget(state, "currentCastHidden") ~= nil
    or rawget(state, "currentCasterId") ~= nil
if legacyFailedLoad then
    print("Hide Enemy Actions: a failed legacy load is still present. Restart DMHub before loading this version.")
    return
end

state.version = 3
state.installed = false
state.uninstall = nil
state.activeCasts = {}
state.activeTags = {}
state.activeCasterCounts = {}
state.pendingCasterCounts = {}
state.functionHooks = {}
state.rollPanelHooks = {}
state.renderHooks = {}
state.renderHookNames = {}

local function Enabled()
    return dmhub.GetSettingValue(SETTING_ID) == true
end

local function SafeGet(obj, field, defaultValue)
    if obj == nil then
        return defaultValue
    end

    local result = defaultValue
    local ok = pcall(function()
        result = obj:try_get(field, defaultValue)
    end)
    if not ok then
        pcall(function()
            local value = obj[field]
            if value ~= nil then
                result = value
            end
        end)
    end
    return result
end

local function GetToken(tokenid)
    if tokenid == nil or tokenid == "" then
        return nil
    end

    local token = nil
    pcall(function()
        token = dmhub.GetCharacterById(tokenid)
    end)
    if token ~= nil and token.valid then
        return token
    end
    return nil
end

local function TokenIsFriendOfPlayer(token)
    if token == nil or not token.valid then
        return nil
    end

    local value = nil
    pcall(function()
        value = token.isFriendOfPlayer
    end)
    return value
end

local function TokenIsPlayerControlled(token)
    if token == nil or not token.valid then
        return false
    end

    local value = false
    pcall(function()
        value = token.playerControlled == true
    end)
    return value
end

local function IsEnemyTokenForPlayer(token)
    return TokenIsFriendOfPlayer(token) == false
end

-- Follow the same relational notion of hostility used by enemy power-roll
-- modifiers when we have a player-side target. For self/buff/area actions with
-- no such target, fall back to the token's player-friend relationship.
local function ShouldHideCast(casterToken, targets)
    if not Enabled() or casterToken == nil or not casterToken.valid then
        return false
    end

    local sawPlayerSideTarget = false
    for _,target in ipairs(targets or {}) do
        local targetToken = target and target.token or nil
        if targetToken ~= nil and targetToken.valid then
            local targetFriend = TokenIsFriendOfPlayer(targetToken)
            if targetFriend == true or TokenIsPlayerControlled(targetToken) then
                sawPlayerSideTarget = true
                local areFriends = true
                local ok = pcall(function()
                    areFriends = casterToken:IsFriend(targetToken)
                end)
                if ok and not areFriends then
                    return true
                end
            end
        end
    end

    if sawPlayerSideTarget then
        return false
    end
    return IsEnemyTokenForPlayer(casterToken)
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
    return (state.activeCasterCounts[casterid] or 0) > 0
        or (state.pendingCasterCounts[casterid] or 0) > 0
end

local function CastIdIsHidden(castid)
    return castid ~= nil and state.activeCasts[castid] ~= nil
end

local function RegisterTag(tag)
    if tag == nil or tag.finished or tag.registered then
        return
    end

    tag.registered = true
    state.activeTags[tag] = true
    AdjustCount(state.activeCasterCounts, tag.casterid, 1)
    if tag.castid ~= nil then
        state.activeCasts[tag.castid] = tag
    end
end

local function FinishTag(tag)
    if tag == nil or tag.finished then
        return
    end

    tag.finished = true
    if not tag.registered then
        return
    end

    tag.registered = false
    state.activeTags[tag] = nil
    AdjustCount(state.activeCasterCounts, tag.casterid, -1)
    if tag.castid ~= nil and state.activeCasts[tag.castid] == tag then
        state.activeCasts[tag.castid] = nil
    end
end

local function CastIdFromOptions(options)
    if type(options) ~= "table" then
        return nil
    end

    if type(options.symbols) == "table" then
        local castid = options.symbols.castid
        if castid ~= nil then
            return castid
        end
    end

    local properties = options.rollProperties or options.properties
    return SafeGet(properties, "castid", nil)
end

local function CasterIdFromRollOptions(options)
    if type(options) ~= "table" then
        return nil
    end

    if options.tokenid ~= nil then
        return options.tokenid
    end

    if options.creature ~= nil then
        local tokenid = nil
        pcall(function()
            tokenid = dmhub.LookupTokenId(options.creature)
        end)
        if tokenid ~= nil then
            return tokenid
        end
    end

    return nil
end

local function ShouldHideRollOptions(options)
    if not Enabled() or type(options) ~= "table" then
        return false
    end

    local casterid = CasterIdFromRollOptions(options)
    if CasterIsHidden(casterid) then
        return true
    end

    return CastIdIsHidden(CastIdFromOptions(options))
end

local function CopyTable(t)
    local result = {}
    for k,v in pairs(t or {}) do
        result[k] = v
    end
    return result
end

-- DSRollDialog has an early deterministic shortcut that calls dmhub.Roll before
-- RollDialog.OnBeforeRoll. Disable only that shortcut for hidden enemy rolls so
-- every networked roll reaches the normal privacy hook below.
local function PrepareShowDialogOptions(options)
    if not ShouldHideRollOptions(options) then
        return options
    end

    local result = CopyTable(options)
    result.skipDeterministic = false
    result._tmp_enemyActionDirectorOnly = true
    return result
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

local function ShouldHideRollHook(args)
    if not Enabled() or type(args) ~= "table" then
        return false
    end

    local rollArgs = args.rollArgs
    local casterid = args.tokenid
    if casterid == nil and type(rollArgs) == "table" then
        casterid = rollArgs.tokenid
    end
    if casterid == nil and args.creature ~= nil then
        pcall(function()
            casterid = dmhub.LookupTokenId(args.creature)
        end)
    end
    if CasterIsHidden(casterid) then
        return true
    end

    local properties = args.properties
    if properties == nil and type(rollArgs) == "table" then
        properties = rollArgs.properties
    end
    return CastIdIsHidden(SafeGet(properties, "castid", nil))
end

local function HiddenPanel(properties, preserveCastId)
    local data = {}
    if preserveCastId then
        data.castid = SafeGet(properties, "castid", nil)
    end

    return gui.Panel{
        classes = {"collapsed"},
        width = 0,
        height = 0,
        data = data,
    }
end

local function ShouldHideRenderedCaster(properties, field)
    if dmhub.isDM or not Enabled() then
        return false
    end
    local token = GetToken(SafeGet(properties, field, nil))
    return IsEnemyTokenForPlayer(token)
end

local function ShouldHideRenderedTarget(properties, field)
    if dmhub.isDM or not Enabled() then
        return false
    end
    local token = GetToken(SafeGet(properties, field, nil))
    return IsEnemyTokenForPlayer(token)
end

local function InstallRenderHook(spec)
    if state.renderHookNames[spec.name] then
        return true
    end

    local messageType = rawget(_G, spec.name)
    if messageType == nil then
        return false
    end

    local baseRender = messageType.Render
    if type(baseRender) ~= "function" then
        return false
    end

    local wrappedRender
    wrappedRender = function(properties, message)
        local hide = false
        if spec.casterField ~= nil then
            hide = ShouldHideRenderedCaster(properties, spec.casterField)
        elseif spec.targetField ~= nil then
            hide = ShouldHideRenderedTarget(properties, spec.targetField)
        end

        if SafeGet(properties, MESSAGE_MARKER, false) == true and not dmhub.isDM and Enabled() then
            hide = true
        end

        if hide then
            return HiddenPanel(properties, spec.preserveCastId == true)
        end
        return baseRender(properties, message)
    end

    messageType.Render = wrappedRender
    state.renderHookNames[spec.name] = true
    state.renderHooks[#state.renderHooks+1] = {
        messageType = messageType,
        base = baseRender,
        wrapped = wrappedRender,
    }
    return true
end

local g_renderSpecs = {
    {name = "CastActivatedAbilityChatMessage", casterField = "casterid", preserveCastId = true},
    {name = "ActivatedAbilityDamageChatMessage", casterField = "casterid"},
    {name = "ActivatedAbilityPurgeEffectsChatMessage", casterField = "casterid"},
    {name = "ActivatedAbilityTemporaryStaminaChatMessage", casterField = "casterid"},
    -- HealChatMessage is created only by the activated-ability heal behavior and
    -- carries its affected token rather than the caster. Enemy-target healing is
    -- therefore still suppressible without using timing heuristics.
    {name = "HealChatMessage", targetField = "tokenid"},
}

local function InstallOptionalRenderHooks(attempt)
    if mod.unloaded then
        return
    end

    local complete = true
    for _,spec in ipairs(g_renderSpecs) do
        if not InstallRenderHook(spec) then
            complete = false
        end
    end

    attempt = attempt or 1
    if not complete and attempt < 50 then
        dmhub.Schedule(0.2, function()
            InstallOptionalRenderHooks(attempt + 1)
        end)
    end
end

local function RecordFunctionHook(owner, key, base, wrapped)
    state.functionHooks[#state.functionHooks+1] = {
        owner = owner,
        key = key,
        base = base,
        wrapped = wrapped,
    }
end

local function WrapRollPanel(panel)
    if panel == nil then
        return
    end

    local valid = true
    pcall(function()
        valid = panel.valid
    end)
    if valid == false then
        return
    end

    local data = nil
    pcall(function()
        data = panel.data
    end)
    if type(data) ~= "table" or type(data.ShowDialog) ~= "function" then
        return
    end

    for _,entry in ipairs(state.rollPanelHooks) do
        if entry.panel == panel then
            return
        end
    end

    local baseShowDialog = data.ShowDialog
    local wrappedShowDialog
    wrappedShowDialog = function(options)
        return baseShowDialog(PrepareShowDialogOptions(options))
    end

    data.ShowDialog = wrappedShowDialog
    state.rollPanelHooks[#state.rollPanelHooks+1] = {
        panel = panel,
        data = data,
        base = baseShowDialog,
        wrapped = wrappedShowDialog,
    }
end

local function WrapRollDialogFactory(owner, key)
    if owner == nil then
        return
    end

    local base = rawget(owner, key)
    if type(base) ~= "function" then
        return
    end

    local wrapped
    wrapped = function(...)
        local results = table.pack(base(...))
        WrapRollPanel(results[1])
        return table.unpack(results, 1, results.n)
    end

    owner[key] = wrapped
    RecordFunctionHook(owner, key, base, wrapped)
end

local function WrapExistingRollDialog()
    local gh = rawget(_G, "gamehud")
    if gh == nil then
        return
    end

    local panel = nil
    pcall(function()
        panel = gh.rollDialog
    end)
    WrapRollPanel(panel)
end

local function InstallHooks()
    if mod.unloaded or state.installed then
        return
    end

    local activatedAbility = rawget(_G, "ActivatedAbility")
    local rollDialog = rawget(_G, "RollDialog")
    local gameHudType = rawget(_G, "GameHud")
    if activatedAbility == nil or rollDialog == nil or gameHudType == nil then
        dmhub.Schedule(0.1, InstallHooks)
        return
    end

    local baseCast = activatedAbility.Cast
    if type(baseCast) ~= "function" then
        dmhub.Schedule(0.1, InstallHooks)
        return
    end

    local wrappedCast
    wrappedCast = function(self, casterToken, targets, options)
        options = options or {}
        if not ShouldHideCast(casterToken, targets) then
            return baseCast(self, casterToken, targets, options)
        end

        local tag = {
            casterid = casterToken.charid,
            castid = nil,
            registered = false,
            finished = false,
        }

        local handlers = options.OnFinishCastHandlers
        if type(handlers) ~= "table" then
            handlers = {}
            options.OnFinishCastHandlers = handlers
        end
        handlers[#handlers+1] = function()
            FinishTag(tag)
        end

        AdjustCount(state.pendingCasterCounts, tag.casterid, 1)
        local pendingGuard <close> = setmetatable({}, {
            __close = function()
                AdjustCount(state.pendingCasterCounts, tag.casterid, -1)
            end,
        })

        local results = table.pack(baseCast(self, casterToken, targets, options))
        tag.castid = CastIdFromOptions(options)
        RegisterTag(tag)

        -- The main cast card can be classified from casterid immediately on a
        -- player client. Persist a marker too so it remains hidden if the token
        -- despawns before the Action Log is reopened later.
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

        return table.unpack(results, 1, results.n)
    end

    activatedAbility.Cast = wrappedCast
    RecordFunctionHook(activatedAbility, "Cast", baseCast, wrappedCast)

    local baseOnBeforeRoll = rollDialog.OnBeforeRoll
    local wrappedOnBeforeRoll
    wrappedOnBeforeRoll = function(args)
        local hide = ShouldHideRollHook(args)
        if hide then
            ForceRollDirectorOnly(args)
        end

        if type(baseOnBeforeRoll) == "function" then
            local results = table.pack(baseOnBeforeRoll(args))
            if hide then
                ForceRollDirectorOnly(args)
            end
            return table.unpack(results, 1, results.n)
        end
        return nil
    end
    rollDialog.OnBeforeRoll = wrappedOnBeforeRoll
    RecordFunctionHook(rollDialog, "OnBeforeRoll", baseOnBeforeRoll, wrappedOnBeforeRoll)

    -- Cover both the existing global dialog and dialogs created later. Ability
    -- behaviors primarily acquire embedded dialogs through CharacterPanel, so
    -- those factories are wrapped as well.
    WrapExistingRollDialog()
    WrapRollDialogFactory(gameHudType, "CreateRollDialog")

    local characterPanel = rawget(_G, "CharacterPanel")
    if characterPanel ~= nil then
        WrapRollDialogFactory(characterPanel, "AcquireAbilityRollDialog")
        WrapRollDialogFactory(characterPanel, "EmbedDialogStandalone")
        WrapRollDialogFactory(characterPanel, "EmbedDialog")
    end

    InstallOptionalRenderHooks(1)
    state.installed = true

    local function UninstallHooks()
        for i = #state.renderHooks, 1, -1 do
            local entry = state.renderHooks[i]
            if entry.messageType.Render == entry.wrapped then
                entry.messageType.Render = entry.base
            end
        end

        for i = #state.rollPanelHooks, 1, -1 do
            local entry = state.rollPanelHooks[i]
            local panelValid = true
            pcall(function()
                panelValid = entry.panel.valid
            end)
            if panelValid ~= false and entry.data.ShowDialog == entry.wrapped then
                entry.data.ShowDialog = entry.base
            end
        end

        for i = #state.functionHooks, 1, -1 do
            local entry = state.functionHooks[i]
            if rawget(entry.owner, entry.key) == entry.wrapped then
                entry.owner[entry.key] = entry.base
            end
        end

        state.activeCasts = {}
        state.activeTags = {}
        state.activeCasterCounts = {}
        state.pendingCasterCounts = {}
        state.functionHooks = {}
        state.rollPanelHooks = {}
        state.renderHooks = {}
        state.renderHookNames = {}
        state.installed = false
        if state.uninstall == UninstallHooks then
            state.uninstall = nil
        end
    end

    state.uninstall = UninstallHooks
    mod.unloadHandlers[#mod.unloadHandlers+1] = UninstallHooks
end

InstallHooks()
