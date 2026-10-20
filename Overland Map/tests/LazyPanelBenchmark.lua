-- Matched full-shell benchmark; fixtures and all saves stay in the isolated transport.
local benchmark = {}
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = assert(source:match("^(.*)/tests/[^/]+$"))
local Base = dofile(directory .. "/tests/LivePerformanceBenchmark.lua")
local componentNames = { "SidePanel", "PathPanel", "LabelPanel", "PartyPanel", "LogPanel", "Import", "QuickAdd" }

local function Counts(root)
    local counts = { panels = 0, pathPanels = 0, activePathPanels = 0 }
    local function Visit(panel, visible)
        visible = visible and not panel:HasClass("collapsed") and not panel:HasClass("hidden")
        counts.panels = counts.panels + 1
        if panel:HasClass("overlandMapPathPiece") then
            counts.pathPanels = counts.pathPanels + 1
            if visible then counts.activePathPanels = counts.activePathPanels + 1 end
        end
        for _, child in ipairs(panel.children) do Visit(child, visible) end
    end
    Visit(root, true)
    local debugOutput = dmhub.debugPropertyOutput
    counts.live = tonumber(debugOutput:match("Sheets live: (%d+)"))
    counts.active = tonumber(debugOutput:match("Sheets active: (%d+)"))
    return counts
end

local function Summary(values)
    local sorted, sum = {}, 0
    for i, value in ipairs(values) do sorted[i], sum = value, sum + value end
    table.sort(sorted)
    return { samples = #values, meanMs = sum / math.max(1, #values), p50Ms = sorted[math.ceil(#sorted * 0.5)] or 0,
        p95Ms = sorted[math.ceil(#sorted * 0.95)] or 0, maxMs = sorted[#sorted] or 0 }
end

function benchmark.CreateView(options)
    local f = Base.CreateData(options.dense == true, options.compass)
    local env = f.env
    if options.baseline then
        for _, name in ipairs({ "LabelPanel", "Panel" }) do
            assert(loadfile(options.baseline .. "/OverlandMap" .. name .. ".lua.source", "t", env))()
        end
    end
    f.factoryCalls, f.factories, f.editorPanels = {}, {}, {}
    for _, name in ipairs(componentNames) do
        local owner = env["OverlandMap" .. name]
        local create = owner.Create
        owner.Create = function(ctx)
            f.factoryCalls[name] = (f.factoryCalls[name] or 0) + 1
            local watch = dmhub.Stopwatch()
            local panel = create(ctx)
            watch:Stop()
            f.factories[name] = { milliseconds = watch.milliseconds, panels = Counts(panel).panels }
            f.editorPanels[name] = panel
            return panel
        end
    end
    local canvas = env.OverlandMapCanvas.Create
    env.OverlandMapCanvas.Create = function(ctx) f.ctx = ctx; f.canvas = canvas(ctx); return f.canvas end
    local state = env.OverlandMapSession.CanvasState
    env.OverlandMapSession.CanvasState = function() f.state = state(); return f.state end
    local paths = env.OverlandMapPathLayer.Create
    env.OverlandMapPathLayer.Create = function() f.paths = paths(); return f.paths end
    f.R.LocationsTable()[f.map].imageId = options.image
    f.M.InvalidateIndex()
    f.pin = assert(f.M.Children(f.map)[1]).id
    f.path = assert(env.OverlandMapPaths.Paths(f.map)[1]).id
    f.label = assert(f.L.ForMap(f.map)[1]).id
    assert(f.M.WriteParty { mapId = f.map, locationId = f.pin, noLog = true })
    f.writesBefore = #f.writes
    local watch = dmhub.Stopwatch()
    f.panel = env.OverlandMapPanel.Create { mode = "window" }
    options.parent:AddChild(f.panel)
    watch:Stop(); f.constructionMs = watch.milliseconds
    return f
end

local editors = {
    { name = "QuickAdd", open = function(f) f.ctx.QuickAdd("location", f.pin) end, close = function(f) f.ctx.CloseQuickAdd() end },
    { name = "SidePanel", open = function(f) f.ctx.Select(f.pin, "edit") end, close = function(f) f.ctx.Select(nil) end },
    { name = "PathPanel", open = function(f) f.ctx.SelectPath(f.path, "pathEdit") end, close = function(f) f.ctx.SelectPath(nil) end },
    { name = "LabelPanel", open = function(f) f.ctx.SelectLabel(f.label, true) end, close = function(f) f.ctx.SelectLabel(nil) end },
    { name = "PartyPanel", open = function(f) f.ctx.ShowParty() end, close = function(f) f.ctx.data.panelMode = "none"; f.ctx.Refresh("selection") end },
    { name = "LogPanel", open = function(f) f.ctx.ToggleLog() end, close = function(f) f.ctx.ToggleLog() end },
    { name = "Import", open = function(f) f.ctx.ImportLocations() end, close = function(f) f.editorPanels.Import.data.close() end },
}

-- Each run uses the same foreground window, fixture data, viewport and source variant.
function benchmark.Start(options)
    local result = { done = false, progress = "starting", runs = {}, variant = options.baseline and "baseline" or "lazy",
        dense = options.dense == true, font = dmhub.GetSettingValue("fontsize"),
        scheme = dmhub.GetSettingValue("themeengine.activecolorscheme"), before = Counts(options.parent) }
    local stage, f, step, fail, beginRun, finishRun, phases, editorPhase
    local run, lastFrame = 0, -1
    local window = "overland-lazy-benchmark"
    local clock = dmhub.Stopwatch()
    local function Drop()
        if f then
            if f.panel.valid then f.panel:DestroySelf() end
            f.mod.unloaded = true
            f = nil
        end
    end
    function result.Cancel()
        step = nil; dmhub.EndPerfWindow(window); Drop()
        result.done, result.progress = true, "cancelled"
        if stage and stage.valid then stage:DestroySelf() end
    end
    function result.Active() return f end
    fail = function(message)
        result.error = tostring(message); result.Cancel(); result.progress = "failed"
    end
    finishRun = function(record)
        record.after = Counts(f.panel)
        record.factories, record.factoryCalls = f.factories, f.factoryCalls
        record.writesAfter, record.writesBefore = #f.writes, f.writesBefore
        assert(record.writesAfter == record.writesBefore, "Benchmark interaction wrote fixture data")
        if run == 0 then result.warmup = record else result.runs[#result.runs + 1] = record end
        Drop()
        local frames = 0
        step = function()
            frames = frames + 1
            if frames < 30 then return end
            record.cleanup = Counts(stage)
            run = run + 1
            if run <= (options.runs or 5) then beginRun()
            else
                result.done, result.progress, result.after = true, "complete", Counts(stage)
                step = nil; stage:DestroySelf()
            end
        end
    end
    editorPhase = function(record)
        local index, pass = 0, 1
        record.editors = {}
        local function Next()
            index = index + 1
            if index > #editors then
                if pass == 1 then pass, index = 2, 1 else finishRun(record); return end
            end
            local item = editors[index]
            result.progress = "run " .. run .. ", " .. item.name .. " open " .. pass
            local started, frames = clock.milliseconds, 0
            local intervals, last = {}, started
            dmhub.BeginPerfWindow(window)
            local watch = dmhub.Stopwatch()
            item.open(f)
            watch:Stop()
            local synchronous = watch.milliseconds
            step = function()
                local now = clock.milliseconds; intervals[#intervals + 1] = now - last; last = now
                frames = frames + 1
                if frames < 5 then return end
                record.editors[item.name] = record.editors[item.name] or {}
                record.editors[item.name][pass] = { synchronousMs = synchronous, readyMs = now - started,
                    wall = Summary(intervals), intervals = intervals, engine = dmhub.EndPerfWindow(window),
                    panels = Counts(f.editorPanels[item.name]).panels }
                local same = f.editorPanels[item.name]
                item.close(f)
                assert(f.editorPanels[item.name] == same and same.valid)
                local settle = 0
                step = function() settle = settle + 1; if settle >= 5 then Next() end end
            end
        end
        Next()
    end
    phases = function(record)
        local definitions = {
            { "idle", 60 }, { "refresh", 30 }, { "shortPan", 60 }, { "longPan", 60 },
            { "zoom", 72 }, { "settledZoom", 24 }, { "bend", 60 },
        }
        local index = 0
        record.phases = {}
        local function Next()
            index = index + 1
            local definition = definitions[index]
            if definition == nil then
                f.paths.SetHandles(nil)
                if options.editors then editorPhase(record) else finishRun(record) end
                return
            end
            local name, count = definition[1], definition[2]
            result.progress = "run " .. run .. ", " .. name
            local frame, intervals, work, last, startedFrame = 0, {}, {}, clock.milliseconds, dmhub.FrameCount()
            dmhub.BeginPerfWindow(window)
            step = function()
                local now = clock.milliseconds
                intervals[#intervals + 1] = now - last; last = now
                if frame == count then
                    local engine = dmhub.EndPerfWindow(window)
                    local actual = dmhub.FrameCount() - startedFrame
                    record.phases[name] = { engine = engine, actualFrames = actual, wall = Summary(intervals),
                        intervals = intervals, lua = Summary(work), tree = Counts(f.panel) }
                    if engine == nil or engine.frames < actual - 2 then
                        fail("Incomplete focus/engine coverage during " .. result.progress); return
                    end
                    Next(); return
                end
                frame = frame + 1
                local watch = dmhub.Stopwatch()
                local camera = f.ctx.data.camera
                if name == "refresh" then f.ctx.Refresh("records")
                elseif name == "shortPan" then camera.zoom, camera.centerX = 1, 0.5 + math.sin(frame / 12) * 0.03
                elseif name == "longPan" then camera.zoom, camera.centerX = 1, 0.1 + frame / count * 0.8
                elseif name == "zoom" then
                    camera.zoom, camera.centerX = 1 + math.sin(math.min(1, frame / 60) * math.pi) * 19, 0.5
                    f.state.lastWheel = frame <= 60 and dmhub.Time() or -1000
                elseif name == "settledZoom" and (frame - 1) % 6 == 0 then
                    camera.zoom, camera.centerX = ({ 2, 5, 20, 1 })[math.floor((frame - 1) / 6) + 1], 0.5
                    f.state.lastWheel = -1000
                elseif name == "bend" then
                    f.paths.SetHandles(f.path, { index = 1, u = 0.4 + frame / count * 0.3, v = 0.4 })
                end
                if name ~= "idle" and name ~= "refresh" then f.canvas:FireEvent("relayout") end
                watch:Stop(); work[#work + 1] = watch.milliseconds
            end
        end
        Next()
    end
    beginRun = function()
        result.progress = "run " .. run .. ", opening"
        local started, intervals, last = clock.milliseconds, {}, clock.milliseconds
        dmhub.BeginPerfWindow(window)
        f = benchmark.CreateView { parent = stage, image = options.image, compass = options.compass,
            dense = options.dense, baseline = options.baseline }
        local record = { constructionMs = f.constructionMs, factoryCallsOnConstruction = {} }
        for key, count in pairs(f.factoryCalls) do record.factoryCallsOnConstruction[key] = count end
        result.current = record
        local readyFrame, settle = nil, 0
        step = function()
            local now = clock.milliseconds; intervals[#intervals + 1] = now - last; last = now
            local state = f.state
            local ready = state and state.imageStatus == "ready" and state.layout
                and state.layout.viewWidth == 1200 and state.layout.viewHeight == 720
                and f.canvas.data.aidLayer.Availability("compass") == "ready"
            if not ready and now - started > 90000 then fail("Opening readiness timed out"); return end
            if not ready then return end
            readyFrame = readyFrame or dmhub.FrameCount()
            if dmhub.FrameCount() < readyFrame + 2 then return end
            if record.readyMs == nil then
                record.readyMs, record.openingIntervals, record.openingWall = now - started, intervals, Summary(intervals)
                record.openingEngine, record.tree = dmhub.EndPerfWindow(window), Counts(f.panel)
                record.openingFactories = {}
                for name, value in pairs(f.factories) do record.openingFactories[name] = value end
            end
            settle = settle + 1
            if settle < 30 then return end
            if options.interactions ~= false then phases(record)
            elseif options.editors then editorPhase(record) else finishRun(record) end
        end
    end
    stage = gui.Panel { id = "overland-lazy-stage", width = 1200, height = 720, floating = true,
        halign = "center", valign = "center", clip = true, swallowPress = true, thinkTime = 0.001,
        think = function()
            if not step or lastFrame == dmhub.FrameCount() then return end
            lastFrame = dmhub.FrameCount()
            local ok, message = xpcall(step, debug.traceback)
            if not ok then fail(message) end
        end,
        destroy = function() if not result.done then result.Cancel() end end,
    }
    options.parent:AddChild(stage)
    local warm = 0
    step = function()
        warm = warm + 1
        if warm == 30 then dmhub.BeginPerfWindow(window) end
        if warm < 90 then return end
        result.idle = dmhub.EndPerfWindow(window)
        if not result.idle or result.idle.frames < 58 then fail("Benchmark requires foreground focus"); return end
        beginRun()
    end
    return result
end

return benchmark
