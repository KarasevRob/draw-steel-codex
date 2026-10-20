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
    for _, name in ipairs({ "Drawing", "CanvasTools", "PathTool", "Gestures", "Camera", "Canvas" }) do
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
    print(string.format("AUTHORING CHECKS: %d passed", passed))
    return true
end

checks.CanvasFixture = CanvasFixture
return checks
