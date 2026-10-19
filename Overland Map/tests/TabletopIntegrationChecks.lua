-- Production Tabletop contracts and Overland host in an isolated GUI, without a live game.
local checks = {}
local Base = dofile("Overland Map/tests/WindowHostChecks.lua")

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("a")
    file:close()
    return text
end

local function Between(source, first, last)
    local start = assert(source:find(first, 1, true))
    local finish = assert(source:find(last, start + #first, true))
    return source:sub(start, finish - 1)
end

-- Extract complete production sections: the rest of Tabletop requires tactical-map engine services.
local function Shared(f, env)
    local source = Read("DMHub Game Hud/Tabletop.lua")
    env.Tabletop = { windowProviders = {}, IsActive = function() return f.tabletop ~= false end }
    env.g_chrome, env.g_sharing = {}, {}
    env.cond = function(test, yes, no) if test then return yes else return no end end
    f.slots, f.purged = {}, {}
    env.IconRailKeySlot = function(key) return f.slots[key] end
    env.IconRailKeyPurge = function(key) f.slots[key] = nil; f.purged[key] = true end
    env.IconRailKeyAdd = function(key, side) f.slots[key] = side end
    env.IconRailKeyDrop = function(key) f.slots[key] = "left"; return true end
    env.IconRailDocDragging = function() end
    env.ChatItemLinks = { Dragging = function() end, Dropped = function() return false end }
    env.DirectorScreen = { ItemDragging = function() end, ItemDropped = function() end }
    env.g_sharing.ScreenKey = function() end
    env.SaveSoon = function() end
    -- Tabletop is another CodeMod: reloading Overland must not mark it unloaded.
    local prefix = [[
local mod = { unloaded = false }
local function DocumentsLayer() return GameHud.instance and GameHud.instance.documentsPanel end
local function LayerSize() local p = DocumentsLayer(); return p.renderedWidth, p.renderedHeight end
]]
    local registry = Between(source, "-- Providers survive", "--This user's window layout")
    local rail = Between(source, "local function RailKey(rec)", "--A caption control")
    local guards = Between(source, "local g_controlClickTime", "local function WindowControl")
    local buttons = Between(source, "local BUTTON_SIZE = 40", "--Takes the live map status")
    local coordinates = Between(source, "local function ScreenToLayer", "local function IsHeroToken")
    assert(load(prefix .. registry .. rail .. guards .. buttons .. coordinates .. [[
Tabletop.TestSetLayer = function(panel) g_buttonLayer = panel end
]], "Tabletop shared contracts", "t", env))()
    f.buttonLayer = f.Panel { width = 1600, height = 1000 }
    env.Tabletop.TestSetLayer(f.buttonLayer)
    env.Tabletop.SwitcherMapWindows = function() return {} end
    env.Tabletop.SwitcherSceneWindows = function() return {} end
    env.Tabletop.LiveWindowState = function() end
    env.CustomDocument = { tableName = "docs", JournalViewers = function() return {} end }
    env.dmhub.GetTable = function() return {} end
    env.dmhub.modKeys = { ctrl = true }
    assert(loadfile("DMHub Game Hud/WindowSwitcher.lua", "t", env))()
    env.g_sharing.TakePendingPings = function() return {} end
    env.g_sharing.SceneWindowStates = function() return {} end
    env.g_sharing.DocItemEntryIds = function() return {} end
    env.g_windows, env.g_cards = {}, {}
    env.dmhub.isDM = true
    assert(load("local mod = dmhub.GetModLoading()\nlocal function GuardClicks() end\n" ..
        Between(source, "g_sharing.DefineWindowsMenu = function()", "g_sharing.DefineWindowsMenu()") ..
        "g_sharing.DefineWindowsMenu()", "Tabletop Windows menu", "t", env))()
end

local function Fixture(preferences, setup)
    return Base.Fixture { preferences = preferences, setup = function(f, env)
        Shared(f, env)
        f.maps.a = { id = "a", name = "Alpha", imageId = "alpha-image" }
        f.maps.b = { id = "b", name = "Beta", imageId = "beta-image" }
        f.errors = {}
        env.print = function(message)
            if tostring(message):find("reconciliation failed", 1, true) then f.errors[#f.errors + 1] = message end
        end
        f.pendingNative = {}
        env.PanelDocument.PopoutSessionId = function() return "session" end
        env.PanelDocument.PopoutRestoreRecords = function() return f.pendingNative end
        env.PanelDocument.PopoutForgetWindow = function(key) f.pendingNative[key] = nil end
        if setup then setup(f, env) end
    end }
end

local function CheckNoErrors(f) assert(#f.errors == 0, table.concat(f.errors, "\n")) end
local function Near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local function FinishAnimation(f, rec)
    if rec.externalGhost and rec.externalGhost.valid then rec.externalGhost:FireEvent("think") end
end

function checks.Run()
    local count = 0
    local function Check(name, run)
        run(); count = count + 1; print("TABLETOP PASS: " .. name)
    end
    Check("screen coordinates wait for layout and remove the title bar", function()
        local f = Fixture()
        local api = f.env.Tabletop
        local x, y = api.ScreenToLayer(800, 530)
        Near(x, 800); Near(y, 500)
        f.layer.height = 0; assert(api.ScreenToLayer(800, 530) == nil)
        f.layer.height = 1000; f.env.dmhub.screenDimensions.x = 0
        assert(api.ScreenToLayer(800, 530) == nil)
    end)
    Check("provider snapshots deduplicate, isolate errors and reject obsolete activations", function()
        local f = Fixture()
        local api, panel, calls = f.env.Tabletop, f.Panel {}, 0
        local owner = { unloaded = false }
        local entry = { key = "external:test", name = "Test", panel = panel, activate = function() calls = calls + 1 end }
        local old = api.RegisterWindowProvider("test", owner, function() return { entry, entry } end)
        api.RegisterWindowProvider("bad", owner, function() error("fixture provider") end)
        local snapshot = api.ExternalWindows()
        assert(#snapshot == 1 and snapshot[1].kind == "external")
        entry.name = "Changed"; assert(snapshot[1].name == "Test")
        snapshot[1].activate(); assert(calls == 1)
        api.RegisterWindowProvider("test", owner, function() return { entry } end)
        old(); snapshot[1].activate(); assert(calls == 1 and #api.ExternalWindows() == 1)
        snapshot = api.ExternalWindows(); f.env.dmhub.gameid = "other"
        snapshot[1].activate(); assert(calls == 1)
        snapshot = api.ExternalWindows(); panel.valid = false
        snapshot[1].activate(); assert(calls == 1)
        owner.unloaded = true; assert(#api.ExternalWindows() == 0 and api.windowProviders.test == nil)
    end)
    Check("Ctrl+Tab uses a stable snapshot and commits through the guarded provider", function()
        local f = Fixture()
        local h = f.Window()
        local switcher = f.env.WindowSwitcher.CreateLayer()
        switcher:FireEvent("switchwindow")
        local activation = h.data.Activate
        local calls = 0
        h.data.Activate = function(self) calls = calls + 1; activation(self) end
        f.env.dmhub.modKeys.ctrl = false; switcher:FireEvent("think")
        assert(calls == 1)
        f.env.dmhub.modKeys.ctrl = true; switcher:FireEvent("switchwindowback")
        f.env.Tabletop.RegisterWindowProvider("overland-map", f.mod, function() return {} end)
        f.env.dmhub.modKeys.ctrl = false; switcher:FireEvent("think")
        assert(calls == 1)
    end)
    Check("Windows menu uses external icons, alphabetical names and minimized checks", function()
        local f = Fixture()
        local h = f.Window()
        h.data:OpenOnTabletop("b")
        local menu = f.env.Tabletop.WindowsMenuEntries()
        assert(#menu == 1 and menu[1].text == "Beta" and menu[1].check and menu[1].icon)
        h.data:Minimize(); FinishAnimation(f, h.data.external)
        menu = f.env.Tabletop.WindowsMenuEntries(); assert(not menu[1].check)
        menu[1].click(); FinishAnimation(f, h.data.external)
        assert(h.data:State() == "open")
        f.env.Tabletop.RegisterWindowProvider("second", f.mod, function()
            return { { key = "external:second", name = "Alpha", panel = f.Panel {}, icon = "other", activate = function() end } }
        end)
        menu = f.env.Tabletop.WindowsMenuEntries()
        assert(menu[1].text == "Alpha" and menu[1].icon == "other" and menu[2].text == "Beta")
    end)
    Check("switcher orders visible windows before minimized windows, then by activation", function()
        local f = Fixture()
        local chosen
        f.env.Tabletop.RegisterWindowProvider("fixture", f.mod, function()
            local entries = {}
            for _, item in ipairs({ { "older", 3, false }, { "minimized", 100, true }, { "recent", 5, false } }) do
                entries[#entries + 1] = { key = "external:" .. item[1], name = item[1],
                    panel = f.Panel { activationOrder = item[2] }, minimized = item[3],
                    activate = function() chosen = item[1] end }
            end
            return entries
        end)
        local switcher = f.env.WindowSwitcher.CreateLayer()
        switcher:FireEvent("switchwindow"); f.env.dmhub.modKeys.ctrl = false; switcher:FireEvent("think")
        assert(chosen == "older")
        f.env.dmhub.modKeys.ctrl = true; switcher:FireEvent("switchwindowback")
        f.env.dmhub.modKeys.ctrl = false; switcher:FireEvent("think"); assert(chosen == "minimized")
    end)
    Check("minimize preserves drafts and restores fullscreen action-bar ownership", function()
        local f = Fixture()
        local h = f.Open()
        local data = h.data.content.data
        h.data:Minimize(); FinishAnimation(f, h.data.external)
        assert(h.data:State() == "minimized" and not h.enabled and not f.settings.hideactionbar)
        assert(not h.data:Engaged() and f.suspends == 1 and f.focus == nil)
        f.Events(); assert(f.focus == nil)
        h.data.external.button:FireEvent("click"); FinishAnimation(f, h.data.external)
        assert(h.enabled and h.data:State() == "open" and f.settings.hideactionbar)
        assert(h.data.content.data == data and data.draft == "unsaved JSON" and #data.pathDraft == 1 and f.builds == 1)
    end)
    Check("cancelled close from minimized leaves a visible host", function()
        local f = Fixture()
        local h = f.Window()
        h.data:Minimize(); f.blockClose = true; h.data:RequestClose()
        assert(h.enabled and h.data:State() == "open" and f.pendingClose)
        assert(not h.data.external.button and not h.data.external.externalGhost)
        f.pendingClose(); assert(not h.valid and f.env.OverlandMapPreferences.HostState() == "closed")
    end)
    Check("restore completion cannot undo a newer minimize, close or game change", function()
        for _, action in ipairs({ "minimize", "close", "game", "unload" }) do
            local f = Fixture()
            local h = f.Window()
            h.data:Minimize(); FinishAnimation(f, h.data.external)
            h.data:Restore(true)
            local ghost = assert(h.data.external.externalGhost)
            if action == "minimize" then h.data:Minimize()
            elseif action == "close" then h.data:Close()
            elseif action == "game" then f.env.dmhub.gameid = "other"; f.Tick()
            else f.mod.unloaded = true; for _, fn in ipairs(f.mod.unloadHandlers) do fn() end end
            ghost:FireEvent("think")
            if action == "minimize" then
                -- The newer minimize is still flying into its button, then lands.
                assert(h.data:State() == "minimizing" and not h.enabled)
                FinishAnimation(f, h.data.external)
                assert(h.data:State() == "minimized" and not h.enabled)
            else assert(not h.valid) end
            CheckNoErrors(f)
        end
    end)
    Check("button movement, scale, viewport and rail changes preserve personal placement", function()
        local f = Fixture()
        local h = f.Window()
        local rec, api = h.data.external, f.env.Tabletop
        h.data:Minimize(); FinishAnimation(f, rec)
        rec.button.xdrag, rec.button.ydrag = 700, 550
        rec.button:FireEvent("drag", nil)
        local position = f.env.OverlandMapPreferences.MinimizedPosition()
        Near(position.x, 700); Near(position.y, 550)
        f.layer.width, f.layer.height, f.scale = 400, 300, 1.4
        api.RefreshExternal(rec); Near(rec.iconX, 344); Near(rec.iconY, 244); Near(rec.button.selfStyle.uiscale, 1.4)
        f.slots[rec.railKey] = "left"
        api.RefreshExternal(rec); assert(rec.button and rec.button.valid)
        local rail = f.Panel { classes = { "iconRail" }, f.Panel { data = { key = rec.railKey }, width = 40, height = 40 } }
        f.layer:AddChild(rail); api.RefreshExternal(rec); assert(rec.button == nil)
        f.rail = false; api.RefreshExternal(rec); assert(rec.button and rec.button.valid)
        f.rail = true; f.slots[rec.railKey] = nil; api.UndockExternal(rec); assert(rec.button)
        f.slots[rec.railKey] = "left"; api.ReleaseExternal(rec)
        assert(f.slots[rec.railKey] == "left" and not f.purged[rec.railKey])
        api.CloseExternal(rec); assert(f.purged[rec.railKey])
    end)
    Check("button layer replacement rebuilds the button without losing its rail slot", function()
        local f = Fixture()
        local h = f.Window(); h.data:Minimize(); FinishAnimation(f, h.data.external)
        local rec, old = h.data.external, h.data.external.button
        local layer = f.Panel { width = 1000, height = 800 }
        f.env.Tabletop.TestSetLayer(layer); f.env.Tabletop.RefreshExternal(rec)
        assert(not old.valid and rec.button.parent == layer)
    end)
    Check("preview and final placement agree at all supported scales", function()
        for _, scale in ipairs({ 0.8, 1, 1.4 }) do
            local f = Fixture()
            f.scale, f.layer.width, f.layer.height = scale, 2200, 1600
            local h = f.Window()
            f.env.dmhub.panelDropSurface = "table"
            local card = f.Panel {}
            h.data:AtlasDragging(card, "a")
            local preview = assert(h.data.atlasDrag.preview)
            local x, y, w, height = preview.x, preview.y, preview.selfStyle.width, preview.selfStyle.height
            h.data:OpenOnTabletop("a", true)
            Near(h.x, x); Near(h.y, y); Near(h.selfStyle.width, w); Near(h.selfStyle.height, height)
            assert(not preview.valid and h.data.content.data.mapId == "a" and f.builds == 1)
        end
    end)
    Check("invalid UI/map drops and revoked maps cannot navigate or move the host", function()
        local f = Fixture()
        local h = f.Window()
        local x, y = h.x, h.y
        for _, surface in ipairs({ "ui", "map" }) do
            f.env.dmhub.panelDropSurface = surface == "ui" and nil or surface
            h.data:OpenOnTabletop("a", true)
            Near(h.x, x); Near(h.y, y); assert(h.data.content.data.mapId == "atlas")
        end
        f.env.dmhub.panelDropSurface = "table"
        local card = f.Panel {}; h.data:AtlasDragging(card, "a")
        local preview = h.data.atlasDrag.preview
        preview:FireEvent("escape")
        assert(card.data.placementCancelled and not preview.valid and h.data.atlasDrag == nil)
        f.maps.a.permitted = false; h.data:OpenOnTabletop("a", true)
        Near(h.x, x); Near(h.y, y); assert(h.data.content.data.mapId == "atlas")
        f.maps.a = nil; h.data:OpenOnTabletop("a"); assert(h.data.content.data.mapId == "atlas")
    end)
    Check("saved state restores without focus, animations or an intermediate visible host", function()
        for _, state in ipairs({ "open", "minimized" }) do
            local f = Fixture({ hostState = state, selectionKind = "atlas", inAppView = "window" })
            local other = f.Panel {}; f.env.gui.SetFocus(other)
            f.Tick(); f.Events(); CheckNoErrors(f)
            local h = assert(f.layer:Get("overland-map-fullscreen"))
            assert(h.data:State() == state and f.focus == other and h.data.external.externalGhost == nil)
            assert(h.enabled == (state == "open"))
            assert(f.env.OverlandMapPreferences.SelectionKind() == "atlas")
        end
    end)
    Check("legacy and deliberately closed preferences do not automatically open", function()
        for _, prefs in ipairs({ {}, { selectedMapId = "a" }, { hostState = "closed" }, { hostState = "native" } }) do
            local f = Fixture(prefs); f.Tick(); CheckNoErrors(f)
            assert(f.layer:Get("overland-map-fullscreen") == nil)
        end
    end)
    Check("a presentation delivered during construction supersedes automatic minimization", function()
        local f = Fixture({ hostState = "minimized", selectionKind = "atlas" }, function(_, env)
            local create = env.OverlandMapPanel.Create
            env.OverlandMapPanel.Create = function(options)
                options.preparePresentation()
                return create(options)
            end
        end)
        f.Tick(); CheckNoErrors(f)
        local h = assert(f.layer:Get("overland-map-fullscreen"))
        assert(h.data:State() == "open" and h.enabled and not h.data.external.minimized)
        assert(f.env.OverlandMapPreferences.HostState() == "open")
    end)
    Check("reload preserves accepted restore intent and generic destruction preserves minimized state", function()
        local f = Fixture()
        local h = f.Window(); h.data:Minimize(); FinishAnimation(f, h.data.external)
        h.data:Restore(true)
        local old = h.data.external.externalGhost
        f.ReloadHost(); f.Tick(); CheckNoErrors(f)
        local restored = assert(f.layer:Get("overland-map-fullscreen"))
        old:FireEvent("think")
        assert(restored.data:State() == "open" and not h.valid)
        restored.data:Minimize(); FinishAnimation(f, restored.data.external)
        local key = restored.data.external.railKey
        f.slots[key] = "right"
        restored:DestroySelf(); f.Tick(); CheckNoErrors(f)
        local minimized = assert(f.layer:Get("overland-map-fullscreen"))
        assert(minimized.data:State() == "minimized" and f.slots[key] == "right" and not f.purged[key])
    end)
    Check("restoration waits for readable preferences and map data", function()
        local f = Fixture()
        f.Tick(); assert(f.builds == 0)
        f.settings["overlandmap:preferences"] = { hostState = "open", selectionKind = "atlas" }
        f.env.dmhub.GetTable = function() return nil end
        f.Tick(); assert(f.builds == 0)
        f.env.dmhub.GetTable = function() return {} end
        f.env.dmhub.gameLoadingProgress = 0.97
        f.Tick(); CheckNoErrors(f); assert(f.builds == 1)
    end)
    Check("delayed map restoration yields permanently to a user choice", function()
        for _, user in ipairs({ false, true }) do
            local f = Fixture({ hostState = "open", selectionKind = "map", selectedMapId = "late" })
            f.Tick(); CheckNoErrors(f)
            local h = assert(f.layer:Get("overland-map-fullscreen"))
            assert(f.env.OverlandMapPreferences.LastMapId() == "late")
            if user then h.data:OpenOnTabletop("a") end
            f.maps.late = { id = "late", name = "Late", imageId = "late-image" }
            f.Tick(); CheckNoErrors(f)
            assert(h.data.content.data.mapId == (user and "a" or "late"))
            if not user then assert(f.focus == nil) end
        end
    end)
    Check("presentation and launcher restore the retained minimized host", function()
        for _, action in ipairs({ "presentation", "launcher" }) do
            local f = Fixture()
            local h = f.Window(); h.data:Minimize(); FinishAnimation(f, h.data.external)
            if action == "presentation" then f.presentation.create() else f.registration.launch() end
            FinishAnimation(f, h.data.external)
            assert(h.valid and h.enabled and h.data:State() == "open" and f.builds == 1)
        end
    end)
    Check("same-session native ownership blocks an in-app duplicate", function()
        local f = Fixture({ hostState = "open" }, function(f)
            f.pendingNative["overland map"] = { session = "session" }
        end)
        f.Tick(); f.Open(); CheckNoErrors(f); assert(f.builds == 0)
        f.pendingNative["overland map"] = nil
        f.Open(); assert(f.builds == 1)
    end)
    Check("missing Tabletop keeps a minimized preference recoverable without overwriting it", function()
        local f = Base.Fixture { preferences = { hostState = "minimized", selectionKind = "atlas" } }
        f.Tick()
        local h = assert(f.layer:Get("overland-map-fullscreen"))
        assert(h.enabled and h.data:State() == "open" and f.env.OverlandMapPreferences.HostState() == "minimized")
    end)
    Check("legacy PDF callers still complete without options and stale restores cancel", function()
        local f = Fixture()
        local api = f.env.Tabletop
        local calls = 0
        local rec = { id = "pdf", railKey = "pdfwindow:fixture", buttonOps = {
            icon = "pdf", image = function() return "cover", false end,
            restore = function() end, close = function() end, hover = function() end,
            chatItems = function() return {} end, badge = { icon = "pdf", color = "clear" }, badgeShown = function() return false end,
        } }
        local rect = { x = 100, y = 100, w = 600, h = 400 }
        api.MinimizeExternal(rec, rect); FinishAnimation(f, rec); assert(rec.button)
        api.RestoreExternal(rec, rect, function() calls = calls + 1 end); FinishAnimation(f, rec); assert(calls == 1)
        api.MinimizeExternal(rec, rect, { animate = false }); assert(rec.button)
        api.RestoreExternal(rec, rect, function() calls = calls + 1 end)
        local old = rec.externalGhost; api.CloseExternal(rec); old:FireEvent("think")
        assert(calls == 1)
    end)
    Check("a dropped landing callback still settles minimized, and stale hosts cannot move the state", function()
        local f = Fixture()
        local h = f.Window()
        h.data:Minimize()
        -- Tabletop cancels the flight without calling back (as on its own reload).
        local rec = h.data.external
        rec.externalGhost:DestroySelf(); rec.externalGhost, rec.externalAnimating = nil, false
        assert(h.data:State() == "minimizing")
        f.Tick(); CheckNoErrors(f)
        assert(h.data:State() == "minimized" and f.env.OverlandMapHost.State() == "minimized")
        h.data:Restore(true); FinishAnimation(f, rec)
        assert(h.data:State() == "open")
        h.data:Close()
        assert(f.env.OverlandMapHost.State() == "closed" and h.data:State() == "closed")
        h.data:Minimize(); h.data:Restore(true)
        assert(f.env.OverlandMapHost.State() == "closed" and f.env.OverlandMapPreferences.HostState() == "closed")
    end)
    Check("each Tabletop feature switches off on its own", function()
        local f = Fixture()
        f.env.Tabletop.MinimizeExternal = nil
        local h = f.Window()
        local adapter = f.env.OverlandMapTabletop
        assert(adapter.Has("provider") and adapter.Has("place") and not adapter.Has("minimize"))
        assert(h:Get("overland-map-window-minimize"):HasClass("collapsed"))
        h.data:Minimize(); assert(h.data:State() == "open" and h.enabled)
        f.Tick(); CheckNoErrors(f)
        assert(#f.env.Tabletop.ExternalWindows() == 1)
        f.env.dmhub.panelDropSurface = "table"
        h.data:OpenOnTabletop("b", true); assert(h.data.content.data.mapId == "b")
        f.env.Tabletop.ScreenToLayer = nil
        assert(not adapter.Has("place") and not h.data:CanPlace())
    end)
    Check("native popout and return move through the state machine", function()
        local f = Fixture()
        local h = f.Window()
        h.data.content.data.options.popOut()
        assert(f.env.OverlandMapHost.State() == "native" and f.env.OverlandMapPreferences.HostState() == "native")
        f.Tick(); assert(f.env.OverlandMapHost.State() == "native")
        f.popout:DestroySelf(); f.Tick(); CheckNoErrors(f)
        assert(f.env.OverlandMapHost.State() == "closed" and f.env.OverlandMapPreferences.HostState() == "closed")
        assert(f.layer:Get("overland-map-fullscreen") == nil)
    end)
    print(string.format("TABLETOP CHECKS: %d passed", count))
    return true
end

checks.Fixture = Fixture
return checks
