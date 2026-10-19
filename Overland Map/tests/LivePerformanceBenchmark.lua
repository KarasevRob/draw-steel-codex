-- Live engine timings with isolated records. This helper is not a registered mod file.
local benchmark = {}
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = assert(source:match("^(.*)/tests/[^/]+$"))
local Fixtures = dofile(directory .. "/tests/PerformanceFixture.lua")
local Renderer = dofile(directory .. "/tests/LiveRendererFixture.lua")

local extraModules = {
    "Journal", "Log", "Editors", "Travel", "Styles", "Controls", "PinText", "Drawing", "CanvasTools",
    "PathLayer", "LabelLayer", "PathTool", "Aids", "AidLayer", "AidEditor", "Gestures", "PinLayer",
    "PartyLayer", "Camera", "GuideLayer", "Canvas", "Artwork", "SidePanel", "PathPanel", "LabelPanel",
    "PartyPanel", "Atlas", "Popovers", "Import", "LogPanel", "Present", "Panel",
}

local function PanelCounts()
    local value = dmhub.debugPropertyOutput
    return {
        live = tonumber(value:match("Sheets live: (%d+)")),
        active = tonumber(value:match("Sheets active: (%d+)")),
        created = tonumber(value:match("Sheets created %(fresh%): (%d+)")),
    }
end

local function TreeCounts(panel)
    local result = { panels = 0, pathPieces = 0, visiblePathPieces = 0 }
    local function Visit(element, visible)
        visible = visible and not element:HasClass("collapsed") and not element:HasClass("hidden")
        result.panels = result.panels + 1
        if element:HasClass("overlandMapPathPiece") then
            result.pathPieces = result.pathPieces + 1
            if visible then result.visiblePathPieces = result.visiblePathPieces + 1 end
        end
        for _, child in ipairs(element.children) do Visit(child, visible) end
    end
    Visit(panel, true)
    return result
end

local function Summarize(values)
    local sorted, sum = {}, 0
    for i, value in ipairs(values) do sorted[i], sum = value, sum + value end
    table.sort(sorted)
    return { samples = #values, meanMs = sum / math.max(1, #values),
        p50Ms = sorted[math.ceil(#sorted * 0.5)] or 0,
        p95Ms = sorted[math.ceil(#sorted * 0.95)] or 0, maxMs = sorted[#sorted] or 0 }
end

local function Data(dense, compass)
    local f = Fixtures.Create(dense)
    local env = f.env
    local journal = env.OverlandMapJournal
    env.gui, env.assets = gui, assets
    setmetatable(env.dmhub, { __index = function(_, key) return dmhub[key] end })
    env.dmhub.Time = dmhub.Time
    env.dmhub.Schedule = function(delay, fn)
        dmhub.Schedule(delay, function() if not f.mod.unloaded then fn() end end)
    end
    local preferences = env.dmhub.GetSettingValue
    env.dmhub.GetSettingValue = function(key)
        if key == f.C.preferencesSettingId then return preferences(key) end
        return dmhub.GetSettingValue(key)
    end
    f.mod.images = { ["compass-icon"] = compass }
    f.mod.GetDocumentSnapshot().path = OverlandMapModel.StatePath()
    env.GameHud = setmetatable({
        GetPresentDialogDocRaw = function() return nil end,
        PresentDialogToUsers = function() error("Benchmark cannot present to a game") end,
    }, { __index = GameHud })
    setmetatable(env.PanelDocument, { __index = PanelDocument })
    for _, name in ipairs(extraModules) do
        assert(loadfile(directory .. "/OverlandMap" .. name .. ".lua", "t", env))()
    end
    -- Model captured this adapter before the live Journal module was loaded.
    for key, value in pairs(env.OverlandMapJournal) do journal[key] = value end
    env.OverlandMapPreferences.SetShowNames(true)
    f.U.Dismiss()
    return f
end

benchmark.CreateData = Data

local function CaptureFactory(owner, key, capture)
    local original = owner[key]
    owner[key] = function(...)
        local value = original(...)
        capture(value)
        return value
    end
end

local function FullView(f, image)
    local env = f.env
    f.R.LocationsTable()[f.map].imageId = image
    f.M.InvalidateIndex()
    CaptureFactory(env.OverlandMapSession, "CanvasState", function(value) f.canvasState = value end)
    CaptureFactory(env.OverlandMapAidLayer, "Create", function(value) f.aidLayer = value end)
    return env.OverlandMapPanel.Create { mode = "window" }
end

local phaseDefinitions = {
    { name = "idle", count = 120 },
    { name = "unchangedBind", count = 60 },
    { name = "shortPan", count = 120 },
    { name = "longPan", count = 120 },
    { name = "zoom", count = 132 },
    { name = "settledZoom", count = 120 },
    { name = "bend", count = 120 },
}

-- Run after one warm-up; repeat each case five times. Poll result.progress outside timed windows.
-- Full-view opening ends two frames after artwork, canvas geometry and compass report ready.
function benchmark.Start(options)
    assert(options.parent and options.parent.valid, "A mounted parent is required")
    assert(type(options.compass) == "string" and type(options.image) == "string")
    local result = { cases = {}, progress = "starting", done = false,
        timingLimits = { framePercentileCapMs = 2000, discardedFrameThresholdMs = 10000,
            openingNeedsExternalFocusCheck = true },
        settings = { font = dmhub.GetSettingValue("fontsize"),
            scheme = dmhub.GetSettingValue("themeengine.activecolorscheme"),
            version = dmhub.version, viewportWidth = 1200, viewportHeight = 720 },
        before = PanelCounts() }
    local cases = options.cases or {
        { name = "pins250", pins = true, paths = false, labels = false, aids = false },
        { name = "paths150", pins = false, paths = true, labels = false, aids = false },
        { name = "normal" }, { name = "dense", dense = true },
        { name = "openNormal", opening = true }, { name = "openDense", opening = true, dense = true },
    }
    ---@type Panel?
    local stage
    ---@type Panel?
    local panel
    ---@type table?
    local f
    local step, caseIndex, run = nil, 0, 0
    local windowKey = "overland-performance-phase"
    local lastFrame, cancelled, cleanupFrames, activeRecord = -1, false, 0, nil
    local StartRun, NextCase, Fail

    local function DropView()
        if panel and panel.valid then panel:DestroySelf() end
        panel = nil
        if f then f.mod.unloaded = true end
        f = nil
    end

    function result.Cancel()
        if result.done then return end
        cancelled, result.done, result.progress = true, true, "cancelled"
        dmhub.EndPerfWindow(windowKey)
        DropView()
        if stage and stage.valid then stage:DestroySelf() end
    end

    Fail = function(message)
        result.error = tostring(message)
        result.interruptedRecord = activeRecord
        result.Cancel()
        result.progress = "failed"
    end

    local function FinishRun(record)
        local bucket = result.cases[caseIndex]
        local current = assert(f)
        record.panels = PanelCounts()
        record.fixtureWritesAfter = #current.writes
        assert(record.fixtureWritesAfter == record.fixtureWritesBefore, "Rendering wrote fixture records")
        if run > 0 then bucket.runs[#bucket.runs + 1] = record else bucket.warmup = record end
        DropView()
        cleanupFrames = 0
        step = function()
            cleanupFrames = cleanupFrames + 1
            if cleanupFrames < 30 then return end
            record.afterCleanup = PanelCounts()
            run = run + 1
            if run <= (options.runs or 5) then StartRun() else NextCase() end
        end
    end

    local function Phases(record, spec)
        local current, view = assert(f), assert(panel)
        local phases, phaseIndex = {}, 0
        for _, value in ipairs(options.phases or phaseDefinitions) do
            if value.name ~= "bend" or spec.paths ~= false then phases[#phases + 1] = value end
        end
        local path = current.env.OverlandMapPaths.Paths(current.map)[1]
        local function NextPhase()
            phaseIndex = phaseIndex + 1
            local phase = phases[phaseIndex]
            if phase == nil then FinishRun(record); return end
            result.progress = spec.name .. ": run " .. run .. ", " .. phase.name
            local frame, work, events, startFrame = 0, {}, {}, dmhub.FrameCount()
            dmhub.BeginPerfWindow(windowKey)
            step = function()
                -- End on the frame after the last action, so its deferred engine work is counted.
                if frame == phase.count then
                    local frames = dmhub.EndPerfWindow(windowKey)
                    local actualFrames = dmhub.FrameCount() - startFrame
                    record.phases[phase.name] = { frames = frames, lua = Summarize(work),
                        events = Summarize(events), steps = frame, actualFrames = actualFrames, panels = PanelCounts() }
                    if not frames or frames.frames < actualFrames - 2 then
                        Fail("Incomplete timing coverage (focus loss or discarded long frames) during " .. result.progress); return
                    end
                    NextPhase()
                    return
                end
                frame = frame + 1
                local watch = dmhub.Stopwatch()
                if phase.name == "unchangedBind" then
                    view.data.Bind(); view.data.Layout(1, 0.5, 0.5)
                elseif phase.name == "shortPan" then
                    view.data.Layout(1, 0.5 + math.sin(frame / 12) * 0.03, 0.5)
                elseif phase.name == "longPan" then
                    view.data.Layout(1, 0.1 + frame / phase.count * 0.8, 0.5)
                elseif phase.name == "zoom" then
                    local t = math.min(1, frame / 120)
                    view.data.Layout(1 + math.sin(t * math.pi) * 19, 0.5, 0.5, frame <= 120)
                elseif phase.name == "settledZoom" and (frame - 1) % 10 == 0 then
                    local levels = { 2, 5, 20, 1 }
                    view.data.Layout(levels[math.floor((frame - 1) / 10) % 4 + 1], 0.5, 0.5)
                elseif phase.name == "bend" then
                    view.data.paths.SetHandles(path.id, { index = 1,
                        u = 0.4 + frame / phase.count * 0.3, v = 0.4 })
                    view.data.Layout(1, 0.5, 0.5)
                end
                watch:Stop(); work[#work + 1] = watch.milliseconds
                if phase.name == "settledZoom" and (frame - 1) % 10 == 0 then
                    events[#events + 1] = watch.milliseconds
                end
            end
        end
        NextPhase()
    end

    StartRun = function()
        local spec = cases[caseIndex]
        result.progress = spec.name .. ": run " .. run .. ", preparing"
        f = Data(spec.dense == true, options.compass)
        result.cases[caseIndex].fixture = f.fixture
        local record = { run = run, phases = {}, fixtureWritesBefore = #f.writes }
        activeRecord = record
        dmhub.BeginPerfWindow(windowKey)
        local watch = dmhub.Stopwatch()
        local startedFrame = dmhub.FrameCount()
        if spec.opening then panel = FullView(f, options.image)
        else
            panel = Renderer.Create(f, gui, dmhub, assets, "", {
                pins = spec.pins, paths = spec.paths, labels = spec.labels, aids = spec.aids,
                modImages = { ["compass-icon"] = options.compass },
            })
        end
        assert(stage):AddChild(panel)
        if not spec.opening then panel.data.Bind(); panel.data.Layout(1, 0.5, 0.5) end
        record.constructionMs = watch.milliseconds
        local readyFrame, settling = nil, 0
        step = function()
            local ready
            if spec.opening then
                local state = f.canvasState
                ready = state and state.imageStatus == "ready" and state.layout ~= nil
                    and state.layout.viewWidth == 1200 and state.layout.viewHeight == 720
                    and f.aidLayer.Availability("compass") == "ready"
            else ready = spec.aids == false or panel.data.aids.Availability("compass") == "ready" end
            if watch.milliseconds > 30000 and not ready then Fail("Image/layout readiness timed out"); return end
            if not ready then return end
            if readyFrame == nil then readyFrame = dmhub.FrameCount() end
            if dmhub.FrameCount() < readyFrame + 2 then return end
            if record.readyMs == nil then
                record.readyMs = watch.milliseconds
                record.readyFrames = dmhub.FrameCount() - startedFrame
                record.openingFrames = dmhub.EndPerfWindow(windowKey)
                -- The engine omits frames >=10 seconds. Check foreground externally for opening;
                -- incomplete histogram coverage cannot distinguish a slow frame from focus loss.
                record.uncountedOpeningFrames = record.readyFrames
                    - (record.openingFrames and record.openingFrames.frames or 0)
                record.readyPanels = PanelCounts()
                record.viewport = { panel.renderedWidth, panel.renderedHeight }
                record.tree = TreeCounts(panel)
            end
            settling = settling + 1
            if settling < 30 then return end
            if spec.opening then FinishRun(record) else Phases(record, spec) end
        end
    end

    NextCase = function()
        caseIndex, run = caseIndex + 1, 0
        local spec = cases[caseIndex]
        if spec == nil then
            result.done, result.progress, result.after = true, "complete", PanelCounts()
            step = nil
            if stage and stage.valid then stage:DestroySelf() end
            if options.done then options.done(result) end
            return
        end
        result.cases[caseIndex] = { name = spec.name, dense = spec.dense == true,
            opening = spec.opening == true, runs = {} }
        StartRun()
    end

    stage = gui.Panel {
        id = "overland-performance-stage", width = 1200, height = 720, floating = true,
        halign = "center", valign = "center", clip = true, swallowPress = true,
        bgimage = "panels/square.png", bgcolor = "#303f35ff", thinkTime = 0.001,
        think = function()
            if cancelled or not step or lastFrame == dmhub.FrameCount() then return end
            lastFrame = dmhub.FrameCount()
            local ok, err = xpcall(step, debug.traceback)
            if not ok then Fail(err) end
        end,
        destroy = function() if not result.done then result.Cancel() end end,
    }
    options.parent:AddChild(stage)
    local probeFrames = 0
    step = function()
        probeFrames = probeFrames + 1
        if probeFrames == 60 then dmhub.BeginPerfWindow(windowKey) end
        if probeFrames < 180 then return end
        result.idleBefore = dmhub.EndPerfWindow(windowKey)
        if not result.idleBefore or result.idleBefore.frames < 118 then
            Fail("The benchmark requires foreground focus"); return
        end
        NextCase()
    end
    return result
end

return benchmark
