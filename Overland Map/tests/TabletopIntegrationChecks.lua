-- Overland's Tabletop integration in an isolated GUI, without a live game. Core Tabletop
-- does not provide these functions today, so a stand-in models the contract the adapter
-- (OverlandMapTabletop) feature-detects; nothing here loads or tests core code.
local checks = {}
local Base = dofile("Overland Map/tests/WindowHostChecks.lua")

--- Minimal Tabletop: window lists, minimize/restore with a flight that finishes on its
--- think event (or at once with animate = false), and table placement coordinates.
local function FakeTabletop(f, env)
    local api = { providers = {} }
    f.purged = {}
    api.IsActive = function() return f.tabletop ~= false end
    api.CanMinimizeExternal = function() return api.IsActive() end
    api.PanelRect = function(panel)
        return { x = panel.x, y = panel.y, w = panel.selfStyle.width, h = panel.selfStyle.height }
    end
    -- The screen is 30 pixels taller than the documents layer (the title bar).
    api.ScreenToLayer = function(x, y)
        if f.layer.renderedWidth <= 0 or f.layer.renderedHeight <= 0 then return nil, nil end
        return x, y - 30
    end
    api.RegisterWindowProvider = function(id, owner, collect)
        local registration = { owner = owner, collect = collect }
        api.providers[id] = registration
        return function() if api.providers[id] == registration then api.providers[id] = nil end end
    end
    api.ExternalWindows = function()
        local result = {}
        for _, registration in pairs(api.providers) do
            if not registration.owner.unloaded then
                for _, entry in ipairs(registration.collect()) do result[#result + 1] = entry end
            end
        end
        return result
    end
    local function Cancel(rec)
        if rec.externalGhost ~= nil then rec.externalGhost.valid = false end
        rec.externalGhost, rec.externalAnimating = nil, false
    end
    local function Animate(rec, done, options)
        Cancel(rec)
        if options ~= nil and options.animate == false then done(); return end
        local ghost = { valid = true }
        function ghost:FireEvent(name)
            if name ~= "think" or not self.valid then return end
            self.valid = false
            rec.externalGhost, rec.externalAnimating = nil, false
            if not rec.closed then done() end
        end
        rec.externalGhost, rec.externalAnimating = ghost, true
    end
    local function ShowButton(rec)
        if rec.minimized and not rec.closed and not rec.externalAnimating and rec.button == nil then
            rec.button = f.Panel { click = function() rec.buttonOps.restore(rec) end }
        end
    end
    api.MinimizeExternal = function(rec, _, options)
        if rec.minimized then return end
        rec.minimized, rec.closed = true, nil
        Animate(rec, function() ShowButton(rec) end, options)
    end
    api.RestoreExternal = function(rec, _, done, options)
        if not rec.minimized then Cancel(rec); done(); return end
        rec.minimized, rec.button, rec.closed = false, nil, nil
        Animate(rec, done, options)
    end
    api.RefreshExternal = function(rec) if not rec.closed then ShowButton(rec) end end
    api.ReleaseExternal = function(rec) Cancel(rec); rec.closed, rec.button = true, nil end
    api.CloseExternal = function(rec)
        api.ReleaseExternal(rec)
        rec.minimized = false
        f.purged[rec.railKey] = true
    end
    api.UndockExternal = api.RefreshExternal
    env.Tabletop = api
end

local function Fixture(preferences, setup)
    return Base.Fixture { preferences = preferences, setup = function(f, env)
        FakeTabletop(f, env)
        f.maps.a = { id = "a", name = "Alpha", imageId = "alpha-image" }
        f.maps.b = { id = "b", name = "Beta", imageId = "beta-image" }
        f.errors = {}
        env.print = function(message)
            local text = tostring(message)
            if text:find("reconciliation failed", 1, true) or text:find("ignored window transition", 1, true) then
                f.errors[#f.errors + 1] = text
            end
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
-- Land the flight, then run one lifecycle tick: that is when the host notices it landed.
local function FinishAnimation(f, rec)
    if rec.externalGhost and rec.externalGhost.valid then rec.externalGhost:FireEvent("think") end
    f.Tick()
end

function checks.Run()
    local count = 0
    local function Check(name, run)
        run(); count = count + 1; print("TABLETOP PASS: " .. name)
    end
    Check("window lists show the current map, its minimized state and activate it", function()
        local f = Fixture()
        local h = f.Window()
        h.data:OpenOnTabletop("b")
        local entries = f.env.Tabletop.ExternalWindows()
        assert(#entries == 1 and entries[1].name == "Beta" and not entries[1].minimized and entries[1].panel == h)
        h.data:Minimize(); FinishAnimation(f, h.data.external)
        entries = f.env.Tabletop.ExternalWindows()
        assert(entries[1].minimized)
        entries[1].activate(); FinishAnimation(f, h.data.external)
        assert(h.data:State() == "open" and h.enabled)
        f.ReloadHost(); f.Tick(); CheckNoErrors(f)
        assert(#f.env.Tabletop.ExternalWindows() <= 1)
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
        assert(f.purged[h.data.external.railKey])
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
    Check("a moved button saves its position as a personal preference", function()
        local f = Fixture()
        local h = f.Window()
        local rec = h.data.external
        h.data:Minimize(); FinishAnimation(f, rec)
        rec.iconX, rec.iconY = 700, 550
        rec.buttonOps.placementChanged(rec)
        local position = f.env.OverlandMapPreferences.MinimizedPosition()
        Near(position.x, 700); Near(position.y, 550)
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
        restored:DestroySelf(); f.Tick(); CheckNoErrors(f)
        local minimized = assert(f.layer:Get("overland-map-fullscreen"))
        assert(minimized.data:State() == "minimized" and not f.purged[key])
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
    Check("minimizing settles once the flight is over, and stale hosts cannot move the state", function()
        local f = Fixture()
        local h = f.Window()
        local rec = h.data.external
        h.data:Minimize()
        assert(h.data:State() == "minimizing")
        rec.externalGhost:FireEvent("think")
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
        f.env.Tabletop.RegisterWindowProvider = nil
        assert(not adapter.Has("provider"))
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
