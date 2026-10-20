-- Real shell, canvas input and camera against isolated records and passive render layers.
local checks = {}
local Shell = dofile("Overland Map/tests/LazyPanelChecks.lua")

local function CanvasFixture()
    local f = Shell.Fixture()
    local env, ctx = f.env, f.ctx
    local Panel = env.gui.Panel
    local function Nothing() end
    local function Layer()
        return { layer = Panel {}, top = Panel {}, handles = Panel {}, route = Panel {}, ruler = Panel {}, label = Panel {},
            Bind = Nothing, Layout = Nothing, Tick = Nothing, SetFocus = Nothing, SetHandles = Nothing,
            SetPreview = Nothing, Metrics = Nothing, HandleAt = Nothing, HitTest = Nothing }
    end
    env.OverlandMapControls.SetClassIf = function(p, key, value) p:SetClass(key, value) end
    env.dmhub.KeyPressed = function() return false end
    env.OverlandMapGuideLayer = { Create = Layer }
    env.OverlandMapPathLayer = { Create = Layer }
    env.OverlandMapLabelLayer = { Create = function()
        f.labels = Layer()
        f.labels.HitTest = function() return f.labelHit end
        return f.labels
    end }
    env.OverlandMapAidLayer = { Create = function()
        f.aids = Layer()
        f.aids.HitTest = function() return f.aidHit end
        return f.aids
    end }
    env.OverlandMapPinLayer = { Create = function(_, _, handlers)
        f.pinHandlers = handlers
        local layer = Layer()
        layer.items, layer.SnapTarget, layer.SetPreview = {}, Nothing, Nothing
        return layer
    end }
    env.OverlandMapPartyLayer = { Create = Layer }
    env.OverlandMapArtwork.MapLayer = function(_, state)
        f.state = state
        local layer = Layer()
        layer.Bind = function(map)
            state.mapId, state.imageId, state.imageRevision = map.id, map.imageId, map.imageRevision
            state.imageWidth, state.imageHeight = 1000, 600
        end
        layer.Clear = Nothing
        return layer
    end
    for _, name in ipairs({ "Drawing", "CanvasTools", "PathTool", "Aids", "Gestures", "Camera", "Canvas" }) do
        assert(loadfile("Overland Map/OverlandMap" .. name .. ".lua", "t", env))()
    end
    f.canvas = env.OverlandMapCanvas.Create(ctx)
    f.root:AddChild(f.canvas)
    f.canvas.renderedWidth, f.canvas.renderedHeight = 1000, 600
    f.canvas.mousePoint = { x = 0.5, y = 0.5 }
    f.buttons, f.saves = {}, 0
    f.canvas.GetMouseButton = function(_, button) return f.buttons[button] == true end
    f.canvas.ScheduleEvent = function(_, name)
        if name == "overlandMapSaveCamera" then f.saves = f.saves + 1 end
    end
    ctx.data.mapId = f.map
    f.canvas:FireEvent("bind")
    function f.Tick(seconds)
        f.Advance(seconds)
        f.canvas:FireEvent("think")
    end
    function f.Press(button)
        f.buttons[button or 0] = true
        f.canvas:FireEvent("press")
    end
    function f.Release(button)
        f.buttons[button or 0] = false
        f.canvas:FireEvent(button == 1 and "rightClick" or "click")
    end
    return f
end

local function Near(a, b) assert(math.abs(a - b) < 1e-8, tostring(a) .. " != " .. tostring(b)) end

local function Find(panel, test)
    if test(panel) then return panel end
    for _, child in ipairs(panel.children) do local found = Find(child, test); if found then return found end end
end

local function EditorFixture()
    local f = Shell.Fixture()
    local env, Panel = f.env, f.env.gui.Panel
    for _, name in ipairs({ "Input", "TextEditor", "Dropdown", "Check", "ColorPicker", "ExpandoArrow", "IconEditor", "SearchInput" }) do env.gui[name] = Panel end
    env.OverlandMapJournal.Available = function() return false end
    env.OverlandMapJournal.ResolveForViewer = function() return { status = "empty" } end
    env.OverlandMapArtwork.Create = function() return Panel {} end
    env.OverlandMapPathLayer = { Sample = function() return Panel { data = { set = function() end } } end,
        LookOfType = function() return {} end }
    for _, name in ipairs({ "Controls", "Editors", "PathPanel", "SidePanel", "LabelPanel" }) do
        assert(loadfile("Overland Map/OverlandMap" .. name .. ".lua", "t", env))()
    end
    env.OverlandMapControls.ScaleColorPopup = function() end
    env.OverlandMapControls.AppearanceEditor = function()
        return Panel { data = { bind = function() end, suspend = function() end, invalid = function() return false end } }
    end
    function f.Button(panel, text)
        return assert(Find(panel, function(p) return p.text == text and p.events.click ~= nil end), text)
    end
    function f.Scroll(panel)
        return assert(Find(panel, function(p) return p.vscroll == true end))
    end
    f.root:DestroySelf(); f.Open()
    return f
end

local function QuickFixture()
    local f = Shell.Fixture()
    local env = f.env
    env.gui.Input = env.gui.Panel
    for _, name in ipairs({ "Controls", "Drawing", "Editors", "QuickAdd" }) do
        assert(loadfile("Overland Map/OverlandMap" .. name .. ".lua", "t", env))()
    end
    f.root:DestroySelf(); f.Open()
    function f.Place(kind, u, v)
        if kind == "label" then f.ctx.CreateLabel(u, v)
        else
            local _, _, _, id = f.M.CreateLocation(f.map, u, v)
            f.ctx.QuickAdd("location", id)
        end
        f.quick = f.root:Get("overland-map-quick")
        f.quick.renderedHeight = 80
        f.ctx.CanvasLayout { x = 0, y = 0, width = 1000, height = 600, viewWidth = 1000, viewHeight = 600 }
        f.input = f.quick:Get("overland-map-quick-input")
        return f.ctx.data.quick.id
    end
    function f.Type(text)
        f.input.text = text; f.input:FireEvent("edit")
    end
    return f
end

function checks.Run()
    local passed = 0
    local function Check(name, run)
        run(); passed = passed + 1; print("AUTHORING PASS: " .. name)
    end
    Check("selection leaves the camera where the viewer put it", function()
        local f = Shell.Fixture()
        local _, _, _, id = f.M.CreateLocation(f.map, 0.95, 0.4)
        f.ctx.data.camera = { zoom = 2, centerX = 0.7, centerY = 0.4 }
        f.ctx.Select(id, "edit")
        Near(f.ctx.data.camera.zoom, 2); Near(f.ctx.data.camera.centerX, 0.7); Near(f.ctx.data.camera.centerY, 0.4)
    end)
    Check("closing a panel eases the clamp and saves only the settled camera", function()
        local f = CanvasFixture()
        f.ctx.data.panelInset = 320
        f.canvas:FireEvent("relayout")
        assert(f.canvas.thinkTime == f.C.canvasThinkActive)
        f.Tick(f.C.transitionSeconds)
        Near(f.ctx.data.camera.centerX, 0.5); assert(f.saves == 0)
        f.ctx.data.camera.centerX = 0.82
        f.canvas:FireEvent("relayout")
        f.ctx.data.panelInset = 0
        f.canvas:FireEvent("relayout")
        Near(f.ctx.data.camera.centerX, 0.82)
        f.Tick(f.C.transitionSeconds / 2)
        Near(f.state.inset, 80); Near(f.ctx.data.camera.centerX, 0.58); assert(f.saves == 0)
        f.Tick(f.C.transitionSeconds / 2)
        Near(f.state.inset, 0); Near(f.ctx.data.camera.centerX, 0.5); assert(f.saves == 1)
        f.Tick(f.C.transitionSeconds); assert(f.saves == 1)
    end)
    Check("Reduce Motion applies the inset immediately", function()
        local f = CanvasFixture()
        f.env.OverlandMapPreferences.ReduceMotion = function() return true end
        f.ctx.data.panelInset = 320; f.canvas:FireEvent("relayout")
        Near(f.state.inset, 320)
        f.ctx.data.camera.centerX = 0.82
        f.ctx.data.panelInset = 0; f.canvas:FireEvent("relayout")
        Near(f.state.inset, 0); Near(f.ctx.data.camera.centerX, 0.5); assert(f.saves == 1)
    end)
    Check("retargeted fractional insets finish exactly, release camera saves and return to idle", function()
        local f = CanvasFixture()
        f.ctx.data.panelInset = 448; f.canvas:FireEvent("relayout")
        f.ctx.data.camera.centerX = 1
        f.Tick(f.C.transitionSeconds * 0.0011)
        assert(f.state.insetClamped)
        f.ctx.data.panelInset = 320 * 0.83; f.canvas:FireEvent("relayout")
        f.Tick(f.C.transitionSeconds + 0.01)
        assert(f.state.inset == f.ctx.data.panelInset)
        assert(f.saves == 1 and f.canvas.thinkTime == f.C.canvasThinkIdle)
        f.canvas:FireEvent("overlandMapSaveCamera")
        assert(not f.state.cameraSaveScheduled and not f.state.cameraDirty)
        f.Tick(1); assert(f.saves == 1 and f.state.inset == f.ctx.data.panelInset)
    end)
    Check("stray releases cannot place objects or reuse a canvas press", function()
        local f = CanvasFixture()
        f.ctx.SetTool("add")
        local before = #f.M.Children(f.map)
        f.canvas:FireEvent("click")
        assert(#f.M.Children(f.map) == before)
        f.Press(); f.Release()
        f.Advance(0)
        assert(#f.M.Children(f.map) == before + 1)
        f.canvas:FireEvent("click")
        assert(#f.M.Children(f.map) == before + 1)
    end)
    Check("location Done saves and deselects, with a pinned Delete action", function()
        local f = EditorFixture()
        local _, _, _, id = f.M.CreateLocation(f.map, 0.4, 0.3)
        f.ctx.Select(id, "edit")
        local panel = f.root:Get("overland-map-side-panel")
        local footer = assert(panel:Get("overland-map-location-footer"))
        assert(footer.parent == panel and f.Scroll(panel).height == "100% available")
        local name = panel:Get("overland-map-location-name")
        name.text = "Saved by Done"; name:FireEvent("edit")
        f.Button(footer, "Done"):FireEvent("click"); f.Advance(0)
        assert(f.ctx.data.selectedId == nil and f.ctx.data.panelMode == "none")
        assert(f.M.GetLocation(id).name == "Saved by Done")
        f.ctx.Select(id, "edit")
        local requested
        f.env.OverlandMapSidePanel.RequestDelete = function(_, selected) requested = selected end
        f.Button(footer, "Delete"):FireEvent("click"); assert(requested == id)
    end)
    Check("location editor keeps its header and reuses read actions, resetting scroll on selection", function()
        local f = EditorFixture()
        local _, _, _, a = f.M.CreateLocation(f.map, 0.2, 0.3)
        local _, _, _, b = f.M.CreateLocation(f.map, 0.7, 0.3)
        f.ctx.Select(a, "read")
        local panel = f.root:Get("overland-map-side-panel")
        local more, close = panel:Get("overland-map-panel-more"), panel:Get("overland-map-panel-close")
        f.ctx.Select(a, "edit")
        assert(panel:Get("overland-map-panel-more") == more and panel:Get("overland-map-panel-close") == close)
        f.Scroll(panel).vscrollPosition = 0
        f.ctx.Select(b, "edit"); assert(f.Scroll(panel).vscrollPosition == 1)
        f.ctx.Select(b, "read"); assert(panel:Get("overland-map-panel-more") == more)
    end)
    Check("Escape closes location and path editors, while pickers return", function()
        local f = Shell.Fixture()
        f.ctx.Select(f.map, "edit"); f.root:FireEvent("escape")
        assert(f.ctx.data.selectedId == nil and f.ctx.data.panelMode == "none")
        f.ctx.Select(f.map, "pickJournal"); f.root:FireEvent("escape")
        assert(f.ctx.data.selectedId == f.map and f.ctx.data.panelMode == "read")
        f.ctx.Select(nil)
        f.ctx.data.panelMode, f.ctx.data.selectedPathId = "pathEdit", "selected-path"
        f.root:FireEvent("escape"); assert(f.ctx.data.selectedPathId == nil and f.ctx.data.panelMode == "none")
    end)
    Check("label and path footers stay outside the scroll area and Done closes them", function()
        local f = EditorFixture()
        local label = f.Create("First")
        f.ctx.SelectLabel(label, true)
        local panel = f.root:Get("overland-map-label-panel")
        local footer = assert(panel:Get("overland-map-label-footer"))
        assert(footer.parent == panel and f.Scroll(panel).height == "100% available")
        f.Scroll(panel).vscrollPosition = 0
        f.ctx.SelectLabel(f.Create("Second"), true); assert(f.Scroll(panel).vscrollPosition == 1)
        f.Button(footer, "Done"):FireEvent("click"); assert(f.ctx.data.selectedLabelId == nil)
        f.R.LocationsTable()[f.map].mode = "pointcrawl"; f.M.InvalidateIndex()
        local _, _, _, a = f.M.CreateLocation(f.map, 0.2, 0.3)
        local _, _, _, b = f.M.CreateLocation(f.map, 0.7, 0.3)
        local _, _, _, path = f.env.OverlandMapPaths.CreatePath(f.map, a, b, {})
        f.ctx.SelectPath(path, "pathEdit")
        panel = f.root:Get("overland-map-path-panel"); footer = assert(panel:Get("overland-map-path-footer"))
        assert(footer.parent == panel and f.Scroll(panel).height == "100% available")
        f.Button(footer, "Done"):FireEvent("click")
        assert(f.ctx.data.selectedPathId == nil and f.ctx.data.panelMode == "none")
    end)
    Check("an unselected label drags while unlocked", function()
        local f = CanvasFixture()
        local id = f.Create("Drag me")
        f.labelHit, f.ctx.data.locked = id, false
        assert(f.ctx.data.selectedLabelId == nil)
        f.Press(); f.canvas.mousePoint.x = 0.6; f.Tick(0.02); f.Release()
        f.Advance(0)
        Near(f.L.Snapshot(id).u, 0.5); Near(f.ctx.data.camera.centerX, 0.5)
    end)
    Check("locked label and aid clicks still select their editors", function()
        local f = CanvasFixture()
        local id = f.Create("Locked")
        f.labelHit = id; f.Press(); f.Release()
        assert(f.ctx.data.selectedLabelId == id and f.ctx.data.panelMode == "labelEdit")
        assert(f.ctx.data.locked); Near(f.L.Snapshot(id).u, 0.4)
        assert(f.M.SetMapAid(f.map, "compass", {}, "add"))
        f.labelHit, f.aidHit = nil, "compass"
        f.Press(); f.Release()
        assert(f.ctx.data.selectedAid == "compass" and f.ctx.data.popover == "aids" and f.ctx.data.locked)
    end)
    Check("empty map clicks clear pin and label selections without leaving the map", function()
        local f = CanvasFixture()
        local _, _, _, pin = f.M.CreateLocation(f.map, 0.2, 0.3)
        for _, mode in ipairs({ "none", "edit", "read" }) do
            f.ctx.Select(pin, mode); f.Press(); f.Release()
            assert(f.ctx.data.selectedId == nil and f.ctx.data.panelMode == "none" and f.ctx.data.mapId == f.map)
        end
        f.ctx.SelectLabel(f.Create("Selected"), true); f.Press(); f.Release()
        assert(f.ctx.data.selectedLabelId == nil and f.ctx.data.panelMode == "none" and f.ctx.data.mapId == f.map)
    end)
    for _, kind in ipairs({ "pin", "label", "aid" }) do
        local title = kind == "pin" and "a locked pin drag notifies once and its action unlocks positions"
            or ("a locked " .. kind .. " drag pans without moving it or notifying")
        Check(title, function()
            local f = CanvasFixture()
            f.ctx.data.camera.zoom = 2; f.canvas:FireEvent("relayout")
            local count = 0
            local action = nil --- @type {copyId: string, click: fun()}?
            f.env.OverlandMapUndo.Notify = function(copy, _, _, button)
                assert(copy == "toast.locked"); count, action = count + 1, button
            end
            if kind == "label" then f.labelHit = f.Create("Locked")
            elseif kind == "aid" then assert(f.M.SetMapAid(f.map, "compass", {}, "add")); f.aidHit = "compass" end
            if kind == "pin" then
                local _, _, _, id = f.M.CreateLocation(f.map, 0.4, 0.3)
                f.buttons[0] = true
                f.pinHandlers.press { data = { id = id }, GetMouseButton = function() return true end }
            else f.Press() end
            local before = #f.writes
            f.canvas.mousePoint.x = 0.6; f.Tick(0.02); f.Tick(0.02)
            assert(#f.writes == before and count == (kind == "pin" and 1 or 0))
            Near(f.ctx.data.camera.centerX, kind == "pin" and 0.5 or 0.45)
            f.Release(); f.Advance(0)
            assert(#f.writes == before and f.ctx.data.selectedLabelId == nil and f.ctx.data.selectedAid == nil)
            if kind ~= "pin" then
                assert(f.saves == 1 and f.ctx.data.locked)
                return
            end
            local unlock = assert(action)
            assert(unlock.copyId == "toast.locked.unlock")
            unlock.click(); assert(not f.ctx.data.locked and not f.root:Get("overland-map-lock"):HasClass("on"))
        end)
    end
    Check("placing labels keeps the tool active and map open re-locks positions", function()
        local f = Shell.Fixture()
        assert(f.root:Get("overland-map-lock"):HasClass("on"))
        f.ctx.SetTool("labelAdd"); f.ctx.CreateLabel(0.3, 0.4)
        assert(f.ctx.data.tool == "labelAdd")
        f.ctx.SetLocked(false); f.ctx.GoAtlas(); f.ctx.OpenMap(f.map)
        assert(f.ctx.data.locked and f.root:Get("overland-map-lock"):HasClass("on"))
    end)
    Check("HiddenCount totals this map's pins, labels and paths without leaking player data", function()
        local f = Shell.Fixture()
        f.R.LocationsTable()[f.map].mode = "pointcrawl"; f.M.InvalidateIndex()
        local _, _, _, a = f.M.CreateLocation(f.map, 0.2, 0.3)
        local _, _, _, b = f.M.CreateLocation(f.map, 0.7, 0.3)
        assert(f.M.SetVisibility(b, "revealed"))
        f.Create("Hidden label")
        assert(f.env.OverlandMapPaths.CreatePath(f.map, a, b, { visibility = "hidden" }))
        local _, _, _, other = f.M.CreateMap("Other", "map-image")
        f.Create("Elsewhere", other)
        assert(f.env.OverlandMapReaders.HiddenCount(f.map) == 3)
        f.ctx.Refresh("records")
        local chip = assert(f.root:Get("overland-map-visibility"))
        assert(chip.text == "3 hidden from players" and not chip:HasClass("on"))
        chip:FireEvent("click")
        assert(f.env.OverlandMapPreferences.ShowVisibility() and f.root:Get("overland-map-visibility"):HasClass("on"))
        f.M.SetViewAsPlayer(true); f.ctx.Refresh("permissions")
        assert(f.env.OverlandMapReaders.HiddenCount(f.map) == 0 and f.root:Get("overland-map-visibility") == nil)
    end)
    Check("hidden counts reuse unchanged records and invalidate across maps, writes and viewer changes", function()
        local f = Shell.Fixture()
        local reads, original = 0, f.L.ForMap
        f.L.ForMap = function(id) reads = reads + 1; return original(id) end
        local _, _, _, pin = f.M.CreateLocation(f.map, 0.2, 0.3)
        local _, _, _, other = f.M.CreateMap("Other", "map-image")
        local count = f.env.OverlandMapReaders.HiddenCount
        assert(count(f.map) == 1 and reads == 1)
        for _ = 1, 20 do f.ctx.RefreshAll() end
        assert(reads == 1)
        assert(count(other) == 0 and count(f.map) == 1 and reads == 2)
        assert(f.M.SetVisibility(pin, "revealed"))
        assert(count(f.map) == 0 and reads == 3)
        f.R.LocationsTable()[pin].visibility = "hidden"
        f.env.dmhub.tablesUpdateId = (f.env.dmhub.tablesUpdateId or 0) + 1
        assert(count(f.map) == 1 and reads == 4)
        f.M.SetViewAsPlayer(true); assert(count(f.map) == 0)
        f.M.SetViewAsPlayer(false); assert(count(f.map) == 1)
    end)
    Check("visibility overlay rebinds all layers, leaves text opaque and attaches label eyes to corners", function()
        local f = EditorFixture()
        local env = f.env
        env.ThemeEngine.MergeTokens = function() return { { fontFace = "berling", color = "#ffffffff", bgcolor = "#111111ff" } } end
        env.ThemeEngine.OnThemeChanged = function() end
        for _, name in ipairs({ "Drawing", "PinText", "PinLayer", "LabelLayer", "PathLayer" }) do
            assert(loadfile("Overland Map/OverlandMap" .. name .. ".lua", "t", env))()
        end
        f.R.LocationsTable()[f.map].mode = "pointcrawl"; f.M.InvalidateIndex()
        local _, _, _, a = f.M.CreateLocation(f.map, 0.2, 0.3)
        local _, _, _, b = f.M.CreateLocation(f.map, 0.7, 0.3)
        local labelId = f.Create("Lettering")
        assert(env.OverlandMapPaths.CreatePath(f.map, a, b, { visibility = "hidden", name = "Route" }))
        local state = env.OverlandMapSession.CanvasState(); state.mapId = f.map
        local pins = env.OverlandMapPinLayer.Create(f.ctx, state, {})
        local labels = env.OverlandMapLabelLayer.Create(f.ctx)
        local paths = env.OverlandMapPathLayer.Create()
        local layout = { x = 0, y = 0, width = 1000, height = 600, viewWidth = 1000, viewHeight = 600 }
        local function Bind()
            pins.Bind(); labels.Bind(f.map); paths.Bind(f.map); paths.Layout(layout, 1)
        end
        assert(not env.OverlandMapPreferences.ShowVisibility())
        Bind()
        assert(pins.items[a].data.hiddenBadge == nil and not pins.items[a]:HasClass("hiddenPin"))
        local eye = assert(Find(labels.layer, function(p) return p:HasClass("overlandMapPinBadge") end))
        assert(eye:HasClass("collapsed"))
        assert(Find(paths.layer, function(p) return p:HasClass("overlandMapPathBadge") and not p:HasClass("collapsed") end) == nil)
        env.OverlandMapPreferences.SetShowVisibility(true); Bind()
        assert(not pins.items[a].data.hiddenBadge:HasClass("collapsed") and not eye:HasClass("collapsed"))
        assert(Find(paths.layer, function(p) return p:HasClass("overlandMapPathBadge") and not p:HasClass("collapsed") end))
        local text = assert(Find(labels.layer, function(p) return p:HasClass("overlandMapLettering") end))
        assert(not text:HasClass("hiddenForPlayers"))
        text.renderedWidth, text.renderedHeight = 100, 40; text:FireEvent("rendered"); labels.Layout(layout)
        local row = f.L.Snapshot(labelId)
        Near(eye.x, row.u * 1000 - 50 * row.size * 1000 / 64 - 500)
        Near(eye.y, row.v * 600 - 20 * row.size * 1000 / 64 - 300)
        Near(eye.selfStyle.width, f.C.pinBadgeSize)
        env.OverlandMapPreferences.SetShowVisibility(false); Bind()
        assert(pins.items[a].data.hiddenBadge:HasClass("collapsed") and eye:HasClass("collapsed"))
        assert(Find(paths.layer, function(p) return p:HasClass("overlandMapPathPiece") and p.selfStyle.opacity == f.C.pathHiddenOpacity end) == nil)
    end)
    Check("quick location Enter saves without a side editor or camera movement and retains the tool", function()
        local f = QuickFixture()
        f.ctx.SetTool("add")
        local id = f.Place("location", 0.95, 0.4)
        assert(not f.made.location and f.ctx.data.panelMode == "none" and f.ctx.data.panelInset == 0)
        Near(f.ctx.data.camera.centerX, 0.5)
        assert(f.quick.x + 500 + 130 < 950)
        f.Type("Right edge"); f.input:FireEvent("submit"); f.Advance(0)
        assert(f.M.GetLocation(id).name == "Right edge" and f.ctx.data.quick == nil)
        assert(f.ctx.data.tool == "add" and f.ctx.data.selectedId == nil and f.focus ~= f.input)
        assert(f.quick:HasClass("collapsed"))
    end)
    Check("All options flushes quick text and opens the full editor on the same item", function()
        local f = QuickFixture()
        local id = f.Place("location", 0.2, 0.3)
        f.Type("Full details")
        f.quick:Get("overland-map-quick-more"):FireEvent("click"); f.Advance(0)
        assert(f.made.location == 1 and f.ctx.data.selectedId == id and f.ctx.data.panelMode == "edit")
        assert(f.ctx.data.focusName and f.ctx.data.quick == nil and f.M.GetLocation(id).name == "Full details")
        local label = f.Place("label", 0.4, 0.3)
        f.quick:Get("overland-map-quick-more"):FireEvent("click")
        assert(f.ctx.data.panelMode == "labelEdit" and f.ctx.data.selectedLabelId == label and f.L.Snapshot(label))
    end)
    Check("quick Escape commits first, then stops the placement tool", function()
        local f = QuickFixture()
        f.ctx.SetTool("add")
        local id = f.Place("location", 0.2, 0.3)
        f.Type("Escape name"); f.root:FireEvent("escape"); f.Advance(0)
        assert(f.M.GetLocation(id).name == "Escape name" and f.ctx.data.quick == nil and f.ctx.data.tool == "add")
        assert(f.ctx.data.selectedId == nil)
        f.root:FireEvent("escape"); assert(f.ctx.data.tool == "none" and f.ctx.data.mapId == f.map)
    end)
    Check("quick labels discard empty drafts and save text while keeping placement active", function()
        local f = QuickFixture()
        f.ctx.SetTool("labelAdd")
        local empty = f.Place("label", 0.2, 0.3)
        f.input:FireEvent("submit"); assert(f.L.Snapshot(empty) == nil and f.ctx.data.tool == "labelAdd")
        local id = f.Place("label", 0.4, 0.5)
        f.Type("Forest"); f.input:FireEvent("submit"); f.Advance(0)
        assert(f.L.Get(id).text == "Forest" and not f.made.label and f.ctx.data.tool == "labelAdd")
        assert(f.ctx.data.selectedLabelId == nil)
    end)
    Check("placing the next item and navigating flush the previous quick edit", function()
        local f = QuickFixture()
        local first = f.Place("location", 0.2, 0.3); f.Type("First")
        local second = f.Place("location", 0.4, 0.5); f.Type("Second")
        f.ctx.GoAtlas(); f.Advance(0)
        assert(f.M.GetLocation(first).name == "First" and f.M.GetLocation(second).name == "Second")
        assert(f.ctx.data.quick == nil and f.quick:HasClass("collapsed"))
    end)
    Check("quick placement follows the anchor, clamps below chrome, and hides off-screen", function()
        local f = QuickFixture()
        f.Place("location", 0.02, 0.01)
        assert(f.quick.x + 500 - 130 >= 0 and f.quick.y + 300 - 40 >= f.C.belowChromeBar)
        f.ctx.CanvasLayout { x = -100, y = 0, width = 1000, height = 600, viewWidth = 1000, viewHeight = 600 }
        assert(f.quick:HasClass("collapsed"))
        f.ctx.CanvasLayout(nil); assert(f.quick:HasClass("collapsed"))
        f.ctx.CanvasLayout { x = 0, y = 0, width = 1000, height = 600, viewWidth = 1000, viewHeight = 600 }
        assert(not f.quick:HasClass("collapsed"))
    end)
    Check("quick layout changes classes only on visibility changes and stops when closed", function()
        local f = QuickFixture()
        f.Place("location", 0.5, 0.5)
        local changes, layouts = 0, 0
        local setClass, onLayout = f.quick.SetClass, f.quick.events.layout
        f.quick.SetClass = function(p, key, on) changes = changes + 1; setClass(p, key, on) end
        f.quick.events.layout = function(...) layouts = layouts + 1; onLayout(...) end
        local layout = { x = 0, y = 0, width = 1000, height = 600, viewWidth = 1000, viewHeight = 600 }
        for _ = 1, 20 do f.ctx.CanvasLayout(layout) end
        assert(changes == 0 and layouts == 20)
        layout.x = -1000
        for _ = 1, 20 do f.ctx.CanvasLayout(layout) end
        assert(changes == 1 and f.quick:HasClass("collapsed"))
        layout.x = 0; f.ctx.CanvasLayout(layout)
        assert(changes == 2 and not f.quick:HasClass("collapsed"))
        f.ctx.CloseQuickAdd()
        assert(f.quick:HasClass("collapsed"))
        changes, layouts = 0, 0
        for _ = 1, 20 do f.ctx.CanvasLayout(layout); f.quick:FireEvent("rendered") end
        assert(changes == 0 and layouts == 0)
    end)
    Check("permission reconciliation preserves quick typing while undo discards it", function()
        local f = QuickFixture()
        local id = f.Place("location", 0.2, 0.3); f.Type("Still typing")
        f.ctx.Transition("reconcile")
        assert(f.input.text == "Still typing" and f.ctx.data.quick.id == id)
        f.env.OverlandMapSession.Transition("undo", f.ctx, f.map)
        assert(f.input.text == f.M.GetLocation(id).name)
        f.input:FireEvent("submit"); f.Advance(0)
        assert(f.M.GetLocation(id).name ~= "Still typing")
    end)
    Check("deleted items and revoked permissions close quick editing without a stale write", function()
        local f = QuickFixture()
        local id = f.Place("location", 0.2, 0.3); f.Type("Unsent")
        f.R.LocationsTable()[id].hidden = true; f.M.InvalidateIndex(); f.ctx.Refresh("records"); f.Advance(0)
        assert(f.ctx.data.quick == nil and f.quick:HasClass("collapsed"))
        assert(f.R.LocationsTable()[id].name ~= "Unsent")
        local label = f.Place("label", 0.4, 0.5)
        f.env.dmhub.isDM = false; f.env.dmhub.loginUserid = "player"
        f.ctx.Transition("permission"); f.ctx.Refresh("permissions"); f.Advance(0)
        assert(f.ctx.data.quick == nil and f.L.Snapshot(label) == nil)
    end)
    print(string.format("AUTHORING CHECKS: %d passed", passed))
    return true
end

checks.CanvasFixture = CanvasFixture
checks.EditorFixture = EditorFixture
return checks
