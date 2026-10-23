-- Called with PerformanceFixture's isolated data and renderer modules loaded into that environment.
local fixture = {}

function fixture.Create(f, engineGui, engineDmhub, engineAssets, compassImage, options)
    options = options or {}
    local env = f.env
    env.gui, env.assets = engineGui, engineAssets
    setmetatable(env.dmhub, { __index = function(_, key) return engineDmhub[key] end })
    env.dmhub.Time = engineDmhub.Time
    env.dmhub.Schedule = engineDmhub.Schedule
    local map = f.M.GetLocation(f.map)
    map.mapAids.compass.imageId = compassImage
    f.mod.images = options.modImages or {}
    local alive, root = true, nil
    local data = env.OverlandMapSession.ViewState()
    data.mapId = f.map
    local ctx = { data = data, IsAlive = function() return alive end, CurrentMap = function() return map end }
    local state = env.OverlandMapSession.CanvasState()
    state.mapId, state.showNames = f.map, true
    local pins = env.OverlandMapPinLayer.Create(ctx, state, {})
    local paths = env.OverlandMapPathLayer.Create()
    local labels = env.OverlandMapLabelLayer.Create(ctx)
    local aids = env.OverlandMapAidLayer.Create(ctx)
    local function Layout(zoom, x, y, moving)
        data.camera = { zoom = zoom, centerX = x, centerY = y }
        local layout = env.OverlandMapGeometry.CalculateImageLayout(1200, 720, 4000, 2000, data.camera, 0)
        local ref = state.pinRef
        if state.pinsDirty or ref == nil or ref.width ~= layout.width or ref.height ~= layout.height then
            ref, state.pinRef, state.pinsDirty = layout, layout, false
            pins.Layout(ref)
        end
        pins.layer.x, pins.layer.y = layout.x - ref.x, layout.y - ref.y
        paths.Layout(layout, 1, moving == true)
        labels.Layout(layout)
        aids.Metrics(4000, 2000)
        aids.Layout(layout)
    end
    local function Bind()
        if options.pins ~= false then pins.Bind() end
        if options.paths ~= false then paths.Bind(f.map) end
        if options.labels ~= false then labels.Bind(f.map) end
        if options.aids ~= false then aids.Bind(map) end
    end
    root = engineGui.Panel {
        id = "overland-map-renderer-fixture", width = 1200, height = 720, floating = true,
        bgimage = "panels/square.png", bgcolor = "#303f35ff", clip = true,
        styles = ThemeEngine.MergeStyles(OverlandMapStyles.Build()),
        data = { fixture = f, Layout = Layout, Bind = Bind, paths = paths, pins = pins,
            labels = labels, aids = aids, state = state },
        thinkTime = 0.001,
        think = function(element) if element.data.Step then element.data.Step() end end,
        destroy = function() alive = false end,
        pins.layer, paths.layer, paths.top, labels.layer, labels.handles, aids.layer, aids.handles,
    }
    ctx.root = root
    return root
end

-- One warm-up and five measured runs. Construction excludes map texture download and shell controls.
function fixture.Run(parent, f, engineGui, engineDmhub, engineAssets, compassImage, done)
    local results, run = {}, 0
    local function Start()
        if not parent.valid then return end
        local timer = engineDmhub.Stopwatch()
        local panel = fixture.Create(f, engineGui, engineDmhub, engineAssets, compassImage)
        parent:AddChild(panel)
        panel.data.Bind(); panel.data.Layout(1, 0.5, 0.5)
        timer:Stop()
        local cold = timer.milliseconds
        local frame, work = 0, {}
        engineDmhub.BeginPerfWindow("overland-renderer-fixture")
        panel.data.Step = function()
            frame = frame + 1
            local watch = engineDmhub.Stopwatch()
            if frame <= 30 then panel.data.Bind(); panel.data.Layout(1, 0.5, 0.5)
            elseif frame <= 60 then panel.data.Layout(1, 0.5 + math.sin(frame / 5) * 0.03, 0.5)
            elseif frame <= 90 then panel.data.Layout(1, 0.1 + (frame - 60) / 30 * 0.8, 0.5)
            elseif frame <= 140 then
                local t = (frame - 90) / 50
                panel.data.Layout(1 + math.sin(t * math.pi) * 19, 0.5, 0.5, true)
            elseif frame <= 170 then
                local path = f.env.OverlandMapPaths.Paths(f.map)[1]
                panel.data.paths.SetHandles(path.id, { index = 1, u = 0.4 + (frame - 140) / 100, v = 0.4 })
                panel.data.Layout(1, 0.5, 0.5)
            else panel.data.paths.SetHandles(nil); panel.data.Layout(1, 0.5, 0.5) end
            watch:Stop(); work[#work + 1] = watch.milliseconds
            if frame < 180 then return end
            local frames = engineDmhub.EndPerfWindow("overland-renderer-fixture")
            table.sort(work)
            if run > 0 then results[#results + 1] = { run = run, constructionMs = cold, frames = frames,
                luaP95Ms = work[math.ceil(#work * 0.95)], luaMaxMs = work[#work],
                livePanels = tonumber(engineDmhub.debugPropertyOutput:match("Sheets live: (%d+)")) } end
            panel.data.Step = nil
            panel:DestroySelf()
            run = run + 1
            if run <= 5 then engineDmhub.Schedule(0.2, Start) else done(results) end
        end
    end
    Start()
end

return fixture
