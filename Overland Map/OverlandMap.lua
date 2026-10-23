local mod = dmhub.GetModLoading()

-- Overland Map bootstrap: registers the panel and the presentable dialog, and keeps the
-- map's window in step with the game. The in-app window is OverlandMapHost; anything that
-- needs the shared Tabletop goes through OverlandMapTabletop. Overland Map is an opt-in
-- CodeMod; it depends only on public DMHub UI and game services.
local C = OverlandMapConstants
local Hosts = OverlandMapHost
local Adapter = OverlandMapTabletop
local POPOUT_KEY = string.lower(C.panelName)
-- The game the window state belongs to; entering another game starts over.
local currentGameId = dmhub.gameid

--- @return OverlandMapWindowHost|nil
local function ValidHost()
    local host = Hosts.Current()
    if host ~= nil and host:Valid() then return host end
    return nil
end

local OpenInApp

local function PopOut()
    Hosts.UserIntent()
    -- Release first: the popout builds its own content tree, and only one may exist.
    local host = Hosts.Current()
    if host ~= nil then host:SavePlacement() end
    Hosts.SetOutside("native", true)
    PanelDocument.OpenPopout(C.panelName, { width = C.windowWidth, height = C.windowHeight, scale = 1 })
    -- OpenPopout registers the window at once; none means this app cannot pop out.
    if PanelDocument.PopoutHost(POPOUT_KEY) == nil then Hosts.SetOutside("closed", true) end
end

local function PopIn()
    Hosts.UserIntent()
    PanelDocument.PopoutForgetWindow(POPOUT_KEY)
    local popout = PanelDocument.PopoutHost(POPOUT_KEY)
    if popout ~= nil then popout:DestroySelf() end
    OpenInApp(true)
end

--- @param focus nil|boolean
--- @param savedState nil|"open"|"minimized"
OpenInApp = function(focus, savedState)
    if ValidHost() ~= nil then return end
    Hosts.Create { focus = focus, savedState = savedState, popOut = PopOut }
end

-- The app restores a same-session popout on its own; opening an in-app copy would duplicate it.
local function NativePending()
    if PanelDocument.PopoutRestoreRecords == nil or PanelDocument.PopoutSessionId == nil then return false end
    local record = PanelDocument.PopoutRestoreRecords()[POPOUT_KEY]
    return record ~= nil and record.session == PanelDocument.PopoutSessionId()
end

-- A presented or rail-opened map comes to the front wherever it is.
local function ShowMapHost(focus)
    Hosts.UserIntent()
    local popout = PanelDocument.PopoutHost(POPOUT_KEY)
    if popout ~= nil then
        pcall(function() popout:RaiseNativeWindow() end)
        return
    end
    if NativePending() then return end
    local host = ValidHost()
    if host ~= nil then
        host:Restore(true, false)
        return
    end
    OpenInApp(focus)
end

local function ToggleInApp()
    Hosts.UserIntent()
    local host = ValidHost()
    if host ~= nil then
        if host:State() ~= "open" or (host.mode == "window" and not host:Foremost()) then host:Activate() else host:RequestClose() end
    else
        ShowMapHost(true)
    end
end

-- Registration -------------------------------------------------------------------------

-- Close the prior view before replacing its registration on Lua reload.
DockablePanel.LaunchPanelByName(C.panelName, "hide")
DockablePanel.Deregister(C.panelName)
-- An action registration: the rail button, the Game menu and ShowPanelByName run
-- launch instead of opening a window. content is still built for the native popout.
DockablePanel.Register {
    name = C.panelName,
    icon = mod.images["compass-icon"] or C.panelIcon,
    dmonly = false,
    vscroll = false,
    minWidth = C.windowMinWidth,
    maxWidth = C.windowMaxWidth,
    minHeight = C.windowMinHeight,
    maxHeight = C.windowMaxHeight,
    popoutHeight = C.popoutHeight,
    resizableWidth = true,
    resizableHeight = true,
    menu = "game",
    launch = ToggleInApp,
    content = function()
        return OverlandMapPanel.Create { popIn = PopIn, mode = "native" }
    end,
}

-- keeplocal = false: every client, the presenter included, opens its own
-- map; the panel then reads the presentation itself. Show, never toggle:
-- a map that is already open stays open.
GameHud.RegisterPresentableDialog {
    id = C.panelName,
    keeplocal = false,
    create = function()
        ShowMapHost(true)
        local host = ValidHost()
        if host ~= nil then host.content:FireEvent("overlandMapReceivePresentation") end
        return nil
    end,
}

-- Lifecycle reconciliation ---------------------------------------------------------------

local function EnterGame()
    currentGameId = dmhub.gameid
    Hosts.Reset()
end

--- Reopen the window the viewer had (saved hostState) until they act themselves.
local function RestoreSavedLayout()
    local intent = Hosts.Intent()
    if not intent.automatic or type(dmhub.GetSettingValue(C.preferencesSettingId)) ~= "table" then return end
    local generation = intent.generation
    if dmhub.GetTable(C.locationTableName) == nil then return end
    local state = OverlandMapPreferences.HostState()
    if Hosts.Current() == nil and (state == "open" or state == "minimized") then
        OpenInApp(false, state --[[@as "open"|"minimized"]])
    end
    if generation ~= intent.generation or not intent.automatic then return end
    local host = ValidHost()
    if host == nil then return end
    if state == "minimized" and host:State() == "open" then host:Minimize(true) end
    if OverlandMapPreferences.SelectionKind() == "map" then
        local id = OverlandMapPreferences.LastMapId()
        local map = OverlandMapModel.GetLocation(id)
        if map ~= nil and OverlandMapModel.CanOpenMap(map) and host.selectedMapId ~= id then
            host.content:FireEvent("overlandMapNavigate", id, true)
        end
    end
end

-- This timer lives outside the host: collapsed panels do not think.
local function ReconcileLifecycle()
    if currentGameId ~= dmhub.gameid then EnterGame() end
    Adapter.SyncProvider()
    local layer = GameHud.instance and GameHud.instance.documentsPanel or nil
    local stale = Hosts.Current()
    if stale ~= nil and (not stale:Valid() or stale.panel.parent ~= layer) then
        stale:Release()
        Hosts.AllowAutomatic()
    end
    if PanelDocument.PopoutHost(POPOUT_KEY) ~= nil then
        if Hosts.State() ~= "native" then Hosts.SetOutside("native", true) end
        return
    end
    if NativePending() then return end
    -- The popout closed: that was the viewer closing the map.
    if Hosts.State() == "native" then
        Hosts.UserIntent()
        Hosts.SetOutside("closed", true)
    end
    if layer == nil or not layer.valid or layer.renderedWidth <= 100 or layer.renderedHeight <= 100
        or dmhub.gameid == nil or dmhub.gameid == "" then return end
    -- Wait for the table's button layer; restoring a minimized window needs it.
    if Adapter.Has("minimize") and not Adapter.CanMinimize() then return end
    RestoreSavedLayout()
    local host = ValidHost()
    if host == nil then return end
    OverlandMapControls.SetClassIf(host.minimizeButton, "collapsed", not Adapter.Has("minimize"))
    host.content:FireEvent("overlandMapIntegrationChanged")
    if host:State() == "minimizing" and not Adapter.Animating(host.external) then host:FinishMinimize() end
    local state = host:State()
    if state == "minimizing" or state == "minimized" then
        host.content:FireEvent("overlandMapReconcile")
        -- Without Tabletop there is no button to restore from: show the window instead.
        if Adapter.Has("minimize") then Adapter.Refresh(host.external) else host:Restore(false, false) end
    elseif state == "restoring" and Adapter.Has("minimize") then
        Adapter.Refresh(host.external)
        if not Adapter.Animating(host.external) then host:Restore(host.restoreFocus, false) end
    end
    local drag = host.atlasDrag
    if drag ~= nil then
        if not drag.card.valid or not drag.card.dragging then host:CancelAtlasDrag()
        else host:AtlasDragging(drag.card, drag.id) end
    end
end

local function LifecycleTick()
    if mod.unloaded then return end
    local ok, err = pcall(ReconcileLifecycle)
    if not ok then print("OVERLAND_MAP: layout reconciliation failed: " .. tostring(err)) end
    dmhub.Schedule(C.canvasThinkIdle, LifecycleTick)
end
mod.enterGameHandlers[#mod.enterGameHandlers + 1] = EnterGame
mod.unloadHandlers[#mod.unloadHandlers + 1] = function()
    local host = Hosts.Current()
    if host ~= nil then host:Release() end
end
dmhub.Schedule(C.canvasThinkIdle, LifecycleTick)

print("OVERLAND_MAP: addon loaded")
