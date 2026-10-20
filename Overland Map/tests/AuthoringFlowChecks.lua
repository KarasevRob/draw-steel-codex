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
    for _, kind in ipairs({ "pin", "label", "aid" }) do
        Check("a locked " .. kind .. " drag notifies once and its action unlocks positions", function()
            local f = CanvasFixture()
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
            local unlock = assert(action)
            assert(count == 1 and unlock.copyId == "toast.locked.unlock" and #f.writes == before)
            Near(f.ctx.data.camera.centerX, 0.5)
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
    print(string.format("AUTHORING CHECKS: %d passed", passed))
    return true
end

checks.CanvasFixture = CanvasFixture
checks.EditorFixture = EditorFixture
return checks
