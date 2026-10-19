-- The production shell runs against real records/session queues and recording factories.
local checks = {}
local Base = dofile("Overland Map/tests/LabelChecks.lua")

local function Fixture()
    local f = Base.Fixture()
    local env = f.env
    f.made, f.binds, f.panels, f.releases = {}, {}, {}, 0
    local methods = {}
    function methods:SetClass(key, on) self.classSet[key] = on end
    function methods:HasClass(key) return self.classSet[key] == true end
    function methods:AddChild(child) self.children[#self.children + 1] = child; child.parent = self end
    function methods:FireEvent(name, ...)
        if self.events[name] then return self.events[name](self, ...) end
    end
    function methods:ScheduleEvent() end
    function methods:GetMouseButton() return false end
    function methods:DestroySelf()
        self:FireEvent("destroy")
        for _, child in ipairs(self.children) do child:DestroySelf() end
        self.valid = false
    end
    function methods:Get(id)
        if self.id == id then return self end
        for _, child in ipairs(self.children) do local found = child:Get(id); if found then return found end end
    end
    local function Panel(args)
        local p = setmetatable({ valid = true, children = {}, events = {}, classSet = {},
            selfStyle = {}, data = args.data or {}, renderedWidth = 1200, renderedHeight = 720 }, { __index = methods })
        for key, value in pairs(args) do
            if type(value) == "function" then p.events[key] = value
            elseif type(key) ~= "number" and key ~= "children" then p[key] = value end
        end
        for _, class in ipairs(args.classes or {}) do p.classSet[class] = true end
        for _, child in ipairs(args.children or args) do p:AddChild(child) end
        return p
    end
    env.gui = { Panel = Panel, Label = Panel, Button = Panel, SetFocus = function(p) f.focus = p end,
        Tooltip = function() return function() end end }
    env.ThemeEngine = { MergeStyles = function(s) return s end }
    env.EscapePriority = { EXIT_DIALOG = 20, EXIT_CHARACTER_SHEET = 10 }
    env.GameHud = { PresentDialogPath = function() return "fixture-present" end }
    env.OverlandMapStyles = { Build = function() return {} end, Subscribe = function() end, Unsubscribe = function() end }
    env.OverlandMapControls = {
        SetText = function(p, text) p.text = text end, UIScale = function() return 1 end,
        IconButton = function(id, _, text, click) return Panel { id = id, text = text, click = click } end,
        SetIconButton = function() end, CloseContextMenu = function() end,
    }
    env.OverlandMapArtwork = { ActiveReader = function() end }
    env.OverlandMapPathTool = { Hint = function() end, Escape = function() return false end }
    env.OverlandMapLog = { EnforceCap = function() end }
    env.OverlandMapPresent = { Create = function() return { Receive = function() end } end }
    env.OverlandMapCanvas = { Create = function(ctx)
        f.ctx = ctx
        return Panel { data = { hasGesture = function() return false end } }
    end }
    env.OverlandMapAtlas = { Create = function() return Panel {} end }
    env.OverlandMapPopovers = { Create = function() return Panel {} end }
    env.OverlandMapAids = { CanEdit = function() return false end }
    local modes = {
        location = { read = true, edit = true, pickMode = true, pickImage = true, pickMap = true, pickJournal = true },
        path = { path = true, pathEdit = true, pickPathEnd = true }, label = { labelEdit = true },
        party = { party = true }, log = { log = true }, import = {},
    }
    local function Factory(key)
        return function(ctx)
            f.made[key] = (f.made[key] or 0) + 1
            if f.onBuild then f.onBuild(key, ctx) end
            if f.fail == key then error("intentional factory failure") end
            local release
            local panel = Panel { id = "fixture-" .. key, classes = { "collapsed" },
                bind = function(p)
                    local active = modes[key][ctx.data.panelMode] == true
                    p:SetClass("collapsed", not active)
                    f.binds[#f.binds + 1] = { key = key, active = active, mode = ctx.data.panelMode,
                        id = ctx.data.selectedId, director = f.M.IsDirector() }
                    if not active and p.data.editing then p.data.editing = false; f.noteClosed = (f.noteClosed or 0) + 1 end
                end,
                destroy = function() if release then release() end; f.releases = f.releases + 1 end,
            }
            release = env.OverlandMapSession.Register { scope = ctx, valid = function() return panel.valid end,
                flush = function() f.flushes = (f.flushes or 0) + 1 end }
            panel.data.start = function() panel:SetClass("collapsed", false); panel.data.target = ctx.data.mapId end
            panel.data.close = function() panel:SetClass("collapsed", true) end
            panel.data.requestClose = function(continue)
                f.closeRequested = (f.closeRequested or 0) + 1
                f.continue = continue
                if not f.discardPending then continue() end
            end
            f.panels[key] = panel
            return panel
        end
    end
    for key, name in pairs({ location = "SidePanel", path = "PathPanel", label = "LabelPanel",
        party = "PartyPanel", log = "LogPanel", import = "Import" }) do
        env["OverlandMap" .. name] = { Create = Factory(key) }
    end
    env.OverlandMapPathPanel.CanConnect = function() return f.canConnect ~= false and f.M.IsDirector() end
    env.OverlandMapPartyPanel.Available = function() return f.partyAvailable == true end
    env.OverlandMapPartyPanel.CreateStopCard = function() return Panel { classes = { "collapsed" } } end
    env.OverlandMapImport.IsRunning = function() return f.importRunning == true end
    assert(loadfile("Overland Map/OverlandMapPanel.lua", "t", env))()
    function f.Open()
        f.root = env.OverlandMapPanel.Create { close = function() f.closed = true end, mode = "window" }
        f.root:FireEvent("create")
        return f.root
    end
    f.Open()
    return f
end

function checks.Run()
    local passed = 0
    local function Check(name, run)
        run(Fixture()); passed = passed + 1; print("LAZY PASS: " .. name)
    end
    Check("opening, ordinary refresh, camera layout and closing build no editors", function(f)
        assert(next(f.made) == nil)
        for _, domain in ipairs({ "records", "party", "assets", "layout", "preferences", "permissions" }) do f.ctx.Refresh(domain) end
        f.root:FireEvent("rendered"); f.root:FireEvent("overlandMapRefresh"); f.root:FireEvent("think")
        f.ctx.FlushEdits(); f.ctx.Transition("reconcile"); f.ctx.Transition("undo")
        f.root:FireEvent("requestClose", function() f.closed = true end)
        f.root:DestroySelf()
        assert(f.closed and next(f.made) == nil and f.releases == 0)
    end)
    for _, mode in ipairs({ "read", "edit", "pickMode", "pickImage", "pickMap", "pickJournal" }) do
        Check("Location first use in " .. mode .. " retains identity", function(f)
            f.ctx.Select(f.map, mode)
            local panel = assert(f.panels.location)
            assert(panel.parent and panel.parent.parent == f.root and panel.parent.interactable == false)
            assert(panel.parent.styles == nil and panel.parent.clip == nil and panel.parent.pad == nil)
            f.ctx.Select(nil); f.ctx.Select(f.map, mode)
            assert(f.made.location == 1 and panel == f.panels.location)
            for key in pairs(f.made) do assert(key == "location") end
            assert(f.binds[1].id == f.map and f.binds[1].mode == mode)
        end)
    end
    Check("path reader/editor and permitted endpoint picker share one retained panel", function(f)
        f.R.LocationsTable()[f.map].mode = "pointcrawl"; f.M.InvalidateIndex()
        local _, _, _, a = f.M.CreateLocation(f.map, 0.2, 0.3)
        local _, _, _, b = f.M.CreateLocation(f.map, 0.8, 0.7)
        local _, _, _, id = f.env.OverlandMapPaths.CreatePath(f.map, a, b, {})
        f.ctx.SelectPath(id, "path"); local panel = f.panels.path
        f.ctx.SelectPath(id, "pathEdit"); f.ctx.Select(a, "pickPathEnd")
        assert(panel and f.panels.path == panel and f.made.path == 1 and not f.made.location)
    end)
    Check("invalid selections and revoked picker never create their rejected editor", function(f)
        f.ctx.SelectPath("missing", "pathEdit"); f.ctx.Select("missing", "edit")
        f.ctx.data.panelMode = "labelEdit"; f.ctx.Refresh("selection")
        assert(next(f.made) == nil)
        f.canConnect = false; f.ctx.Select(f.map, "pickPathEnd")
        assert(not f.made.path and f.made.location == 1 and f.ctx.data.panelMode == "read")
    end)
    Check("editable labels build once and blank drafts still disappear on leave", function(f)
        f.ctx.CreateLabel(0.2, 0.3)
        local id = f.ctx.data.selectedLabelId
        assert(f.made.label == 1 and f.L.Snapshot(id))
        f.ctx.SelectLabel(nil); assert(f.L.Snapshot(id) == nil)
        f.ctx.CreateLabel(0.6, 0.7); assert(f.made.label == 1)
    end)
    Check("saved-format listener works before the label editor exists", function(f)
        local id = f.L.NewDraft(f.map, 0.2, 0.3)
        assert(f.L.Stage(id, { text = "Remember", bold = true })); f.L.Flush(id); f.Advance(0)
        assert(f.env.OverlandMapPreferences.LastLabelFormat().bold == true and not f.made.label)
    end)
    Check("Party availability gates first use", function(f)
        f.ctx.ShowParty(); assert(not f.made.party)
        f.partyAvailable = true; f.ctx.ShowParty(); local panel = f.panels.party
        f.partyAvailable = false; f.ctx.Refresh("party"); assert(panel:HasClass("collapsed"))
        f.partyAvailable = true; f.ctx.ShowParty(); assert(f.made.party == 1)
    end)
    Check("switching editors delivers the outgoing closing bind including log notes", function(f)
        f.ctx.ToggleLog(); f.panels.log.data.editing = true
        f.ctx.Select(f.map, "read")
        assert(f.noteClosed == 1 and f.panels.log:HasClass("collapsed"))
        f.ctx.ToggleLog(); assert(f.panels.location:HasClass("collapsed") and f.made.log == 1)
    end)
    Check("Import requires explicit allowed action and retains its original target", function(f)
        f.importRunning = true; f.ctx.ImportLocations(); assert(not f.made.import)
        f.importRunning = false; f.M.SetViewAsPlayer(true); f.ctx.ImportLocations(); assert(not f.made.import)
        f.M.SetViewAsPlayer(false); f.ctx.GoAtlas(); f.ctx.ImportLocations(); assert(not f.made.import)
        f.ctx.OpenMap(f.map); f.ctx.ImportLocations()
        assert(f.made.import == 1 and f.panels.import.data.target == f.map)
        local parent = f.panels.import.parent
        assert(parent.parent == f.root)
        local _, _, _, other = f.M.CreateMap("Other", "map-image")
        f.ctx.OpenMap(other); assert(f.panels.import.data.target == f.map)
    end)
    Check("Import cancel preserves host and stale discard continuation cannot close a replacement", function(f)
        f.ctx.ImportLocations(); f.discardPending = true
        f.root:FireEvent("requestClose", function() f.closed = true end)
        assert(not f.closed and f.closeRequested == 1)
        local oldContinue = f.continue
        f.root:DestroySelf(); f.Open(); oldContinue()
        assert(not f.closed and f.root.valid and f.made.import == 1)
    end)
    Check("Import confirmation continues the guarded host flush", function(f)
        f.ctx.ImportLocations(); f.discardPending = true
        f.root:FireEvent("requestClose", function() f.closed = true end)
        local before = f.flushes or 0; f.continue()
        assert(f.closed and f.flushes > before)
    end)
    Check("host mode changes preserve the component and its slot", function(f)
        f.ctx.Select(f.map, "edit"); local panel, parent = f.panels.location, f.panels.location.parent
        for _, mode in ipairs({ "fullscreen", "window", "native" }) do
            f.root:FireEvent("overlandMapHostMode", mode); f.root:FireEvent("overlandMapRefresh")
            assert(f.panels.location == panel and panel.parent == parent)
        end
        assert(f.made.location == 1)
    end)
    Check("status uses intended width before a newly constructed panel has laid out", function(f)
        f.ctx.Select(f.map, "read")
        assert(f.root:Get("overland-map-status").selfStyle.rmargin == f.C.sidePanelWidth + 8)
        f.root.renderedWidth = f.C.narrowWidth - 1; f.ctx.Refresh("layout")
        assert(f.root:Get("overland-map-status").selfStyle.rmargin == f.root.renderedWidth + 8)
    end)
    Check("first use binds current records and permissions", function(f)
        f.M.SetViewAsPlayer(true); f.ctx.Select(f.map, "read")
        assert(f.binds[1].director == false and f.binds[1].id == f.map)
        f.M.SetViewAsPlayer(false)
        f.R.LocationsTable()[f.map].hidden = true; f.M.InvalidateIndex(); f.ctx.Refresh("records")
        assert(f.panels.location:HasClass("collapsed") and f.made.location == 1)
    end)
    Check("re-entrant first use constructs once", function(f)
        f.onBuild = function(key, ctx) if key == "import" then ctx.ImportLocations() end end
        f.ctx.ImportLocations(); assert(f.made.import == 1)
    end)
    Check("failed construction is not retried by refresh", function(f)
        f.fail = "log"; assert(not pcall(f.ctx.ToggleLog)); assert(f.made.log == 1)
        f.fail = nil; f.ctx.Refresh("selection"); assert(f.made.log == 1 and not f.panels.log)
    end)
    Check("game change and destroyed owners cannot construct from stale callbacks", function(f)
        local old = f.ctx
        f.env.dmhub.gameid = "replacement-game"
        old.ImportLocations(); old.ToggleLog(); assert(next(f.made) == nil)
        f.root:DestroySelf(); f.Open(); old.ImportLocations()
        assert(next(f.made) == nil)
    end)
    Check("repeated open and close releases each constructed participant once", function(f)
        for _ = 1, 3 do
            f.ctx.Select(f.map, "read"); f.ctx.ToggleLog(); f.ctx.ImportLocations()
            f.root:DestroySelf(); f.Open()
        end
        assert(f.releases == 9 and f.made.location == 3 and f.made.log == 3 and f.made.import == 3)
    end)
    print(string.format("LAZY CHECKS: %d passed", passed))
    return true
end

return checks
