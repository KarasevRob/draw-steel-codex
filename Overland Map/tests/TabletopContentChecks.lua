local checks = {}
local Shell = dofile("Overland Map/tests/LazyPanelChecks.lua")
local Host = dofile("Overland Map/tests/TabletopIntegrationChecks.lua")

local function AtlasFixture()
    local f = Host.Fixture()
    local h = f.Window()
    local env = f.env
    env.gui.IconEditor = f.Panel
    env.OverlandMapImages = { Request = function() return { Cancel = function() end } end }
    env.OverlandMapModel.IsDirector = function() return f.director ~= false end
    env.OverlandMapModel.IsPointCrawl = function() return false end
    env.OverlandMapModel.Party = function() return {} end
    env.OverlandMapReaders = { Atlas = function()
        local rows = {}
        for _, row in pairs(f.maps) do
            if env.OverlandMapModel.CanOpenMap(row) then rows[#rows + 1] = { row = row, count = 0 } end
        end
        return rows
    end }
    local options = h.data.content.data.options
    local ctx = {
        data = {}, IsAlive = function() return h.valid end, ImageHint = function() return "fixture" end,
        OpenMap = function(id) f.clicked = id end,
        OpenOnTabletop = options.openOnTabletop, AtlasDragging = options.atlasDragging,
        CancelAtlasDrag = options.cancelAtlasDrag,
        TabletopAvailable = function(drag) return h.data:CanPlace() and (not drag or h.data.mode == "window") end,
    }
    assert(loadfile("Overland Map/OverlandMapAtlas.lua", "t", env))()
    f.atlas = env.OverlandMapAtlas.Create(ctx)
    h.data.content:AddChild(f.atlas)
    f.atlas:SetClass("collapsed", false)
    f.atlas:FireEvent("bind")
    f.host = h
    return f
end

function checks.Run()
    local count = 0
    local function Check(name, run)
        run(); count = count + 1; print("TABLETOP CONTENT PASS: " .. name)
    end
    Check("explicit Atlas selection survives reopening with maps available", function()
        local f = Shell.Fixture()
        f.ctx.GoAtlas()
        local prefs = f.env.OverlandMapPreferences
        assert(prefs.SelectionKind() == "atlas" and prefs.LastMapId() == nil)
        f.root:DestroySelf(); f.Open(); assert(f.ctx.data.mapId == nil)
    end)
    Check("legacy preferences retain first-map fallback while unavailable explicit targets stay Atlas", function()
        local f = Shell.Fixture()
        assert(f.ctx.data.mapId == f.map and f.env.OverlandMapPreferences.SelectionKind() == nil)
        f.root:DestroySelf()
        f.env.OverlandMapPreferences.SaveLastMap("missing")
        f.Open()
        assert(f.ctx.data.mapId == nil and f.env.OverlandMapPreferences.LastMapId() == "missing")
    end)
    Check("automatic navigation never focuses and explicit interaction supersedes it", function()
        local f = Shell.Fixture()
        f.root:DestroySelf()
        local actions, allowed = 0, false
        f.Open { mode = "window", canFocus = function() return allowed end,
            userAction = function() actions = actions + 1; allowed = true end }
        f.focus = nil
        f.root:FireEvent("overlandMapNavigate", f.map, true)
        assert(f.ctx.data.mapId == f.map and actions == 0 and f.focus == nil)
        f.ctx.GoAtlas(); assert(actions == 1)
        f.root:FireEvent("overlandMapNavigate", f.map, false)
        assert(actions == 2 and f.focus ~= nil)
    end)
    Check("minimization flushes participants, keeps path/import drafts and releases Escape", function()
        local f = Shell.Fixture()
        f.R.LocationsTable()[f.map].mode = "pointcrawl"; f.M.InvalidateIndex()
        f.ctx.SetTool("path"); f.ctx.ImportLocations()
        local draft = { mapId = f.map, bends = { { u = 0.2, v = 0.3 } } }
        f.ctx.data.pathDraft = draft
        local import = f.panels.import
        import.data.text = "unfinished JSON"
        local flushes = f.flushes or 0
        f.focus = nil
        f.root:FireEvent("overlandMapHostVisibility", false)
        f.root:FireEvent("overlandMapSuspend")
        f.root:FireEvent("overlandMapReconcile")
        assert(f.flushes > flushes and f.ctx.data.pathDraft == draft)
        assert(f.panels.import == import and import.data.text == "unfinished JSON")
        assert(not f.root.captureEscape and f.focus == nil)
        f.root:FireEvent("overlandMapHostVisibility", true)
        f.root:FireEvent("overlandMapHostActive", true)
        assert(f.root.captureEscape)
    end)
    Check("permission reconciliation clears restricted selection without replacing the saved target", function()
        local f = Shell.Fixture()
        f.ctx.OpenMap(f.map)
        f.env.dmhub.isDM = false
        f.R.LocationsTable()[f.map].mapShared = false; f.M.InvalidateIndex()
        f.root:FireEvent("overlandMapHostVisibility", false)
        f.root:FireEvent("overlandMapReconcile")
        assert(f.ctx.data.mapId == nil and f.env.OverlandMapPreferences.LastMapId() == f.map)
    end)
    Check("Escape cancels a placement drag before ordinary Atlas navigation", function()
        local f = Shell.Fixture()
        f.root:DestroySelf()
        local cancelled = 0
        f.Open { mode = "window", cancelAtlasDrag = function() cancelled = cancelled + 1; return true end }
        f.root:FireEvent("escape")
        assert(cancelled == 1 and f.ctx.data.mapId == f.map)
    end)
    Check("Atlas placement controls are focusable for players and do not open the Director menu", function()
        local f = AtlasFixture()
        f.director = false; f.atlas:FireEvent("bind")
        local card = f.atlas:Get("overland-map-atlas-card-a")
        local control = card.data.openOnTabletop
        assert(control.canFocus and control.swallowPress and control.data.tooltip == "Open Alpha on tabletop")
        assert(not card.data.placementControl:HasClass("collapsed") and card.data.actions:HasClass("collapsed"))
        control:FireEvent("click")
        assert(f.host.data.content.data.mapId == "a" and f.clicked == nil)
    end)
    Check("the Atlas suppresses release-click after valid, invalid and cancelled drags", function()
        for _, outcome in ipairs({ "valid", "invalid", "cancelled", "deleted", "revoked" }) do
            local f = AtlasFixture()
            local card = f.atlas:Get("overland-map-atlas-card-a")
            f.env.dmhub.panelDropSurface = outcome == "invalid" and "map" or "table"
            card:FireEvent("press"); card:FireEvent("dragging")
            if outcome == "cancelled" then f.host.data.atlasDrag.preview:FireEvent("escape")
            elseif outcome == "deleted" then f.maps.a = nil
            elseif outcome == "revoked" then f.maps.a.permitted = false end
            card:FireEvent("drag"); card:FireEvent("click")
            assert(f.clicked == nil and f.host.data.atlasDrag == nil)
            assert(f.host.data.content.data.mapId == (outcome == "valid" and "a" or "atlas"))
        end
    end)
    Check("fullscreen retains the keyboard placement action but disables native card dragging", function()
        local f = AtlasFixture()
        f.host.data:ToggleView(); f.atlas:FireEvent("bind")
        local card = f.atlas:Get("overland-map-atlas-card-a")
        assert(not card.draggable and not card.data.placementControl:HasClass("collapsed"))
        card.data.openOnTabletop:FireEvent("click")
        assert(f.host.data.mode == "window" and f.host.data.content.data.mapId == "a")
    end)
    Check("minimum-size rejection retains the current view and selection", function()
        local f = AtlasFixture()
        f.env.OverlandMapUndo = { Notify = function(id) f.notice = id end }
        f.layer.width, f.layer.height = 500, 300
        f.host:FireEvent("monitor")
        f.atlas:Get("overland-map-atlas-card-a").data.openOnTabletop:FireEvent("click")
        assert(f.notice == "window.tooSmall" and f.host.data.mode == "fullscreen" and f.host.data.content.data.mapId == "atlas")
    end)
    Check("presentation preparation precedes delayed sharing and nonce delivery stays one-shot", function()
        local f = Shell.Fixture()
        local env = f.env
        local raw = { data = { timestamp = 0, dialog = { args = {
            nonce = "fixture", overlandMapLocationId = "late", ttl = f.C.presentTtl,
        } } } }
        env.GameHud.GetPresentDialogDoc = function() return raw end
        env.TimestampAgeInSeconds = function() return 0 end
        local prepared, jumped, permitted = 0, 0, false
        local ctx = {
            PreparePresentation = function() prepared = prepared + 1 end,
            IsAlive = function() return true end,
            FlushEdits = function() end,
            OpenMap = function(id) assert(id == "late" and prepared == 1); jumped = jumped + 1 end,
        }
        env.OverlandMapModel.GetLocation = function(id) if id == "late" and permitted then return { id = id, name = "Late" } end end
        env.OverlandMapModel.CanOpenMap = function(row) return row ~= nil end
        env.OverlandMapModel.DisplayName = function(row) return row.name end
        assert(loadfile("Overland Map/OverlandMapPresent.lua", "t", env))()
        local controller = env.OverlandMapPresent.Create(ctx)
        controller.Receive(); assert(prepared == 1 and jumped == 0)
        permitted = true; controller.Receive(); controller.Receive()
        assert(prepared == 1 and jumped == 1)
    end)
    print(string.format("TABLETOP CONTENT CHECKS: %d passed", count))
    return true
end

return checks
