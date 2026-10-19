-- Load the complete production module so geometry helpers cannot hide tool dispatch.
local checks = {}
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = source:match("^(.*)/tests/[^/]+$") or "Overland Map"
local Base = dofile(directory .. "/tests/LabelChecks.lua")

local function Fixture()
    local f = Base.Fixture()
    f.env.OverlandMapPreferences = { LastPinStyle = function() return "icon" end }
    assert(loadfile(directory .. "/OverlandMapDrawing.lua", "t", f.env))()
    assert(loadfile(directory .. "/OverlandMapCanvasTools.lua", "t", f.env))()
    f.T = f.env.OverlandMapCanvasTools
    local ctx = { data = { mapId = f.map, tool = "none" } }
    ctx.CurrentMap = function() return f.M.GetLocation(f.map) end
    ctx.IsAlive = function() return true end
    ctx.FlushEdits = function() end
    ctx.SetTool = function(tool) ctx.data.tool = tool end
    ctx.SetPopover = function(popover) ctx.data.popover = popover end
    ctx.Report = function(ok, reason) assert(ok, tostring(reason)); return ok end
    ctx.Select = function(id) ctx.data.selectedId = id end
    ctx.Push = function() end
    ctx.CreateLabel = function(u, v) f.draft = f.L.NewDraft(f.map, u, v) end
    f.ctx = ctx
    return f
end

function checks.Run()
    local passed = 0
    local function Check(name, fn) fn(Fixture()); passed = passed + 1; print("CANVAS TOOLS PASS: " .. name) end
    Check("add Location dispatch persists the clicked point", function(f)
        f.ctx.data.tool = "add"
        f.T.PlaceAt(f.ctx, 0.31, 0.67); f.Advance(0)
        local children = f.M.Children(f.map)
        assert(#children == 1)
        assert(children[1].u == 0.31 and children[1].v == 0.67)
        assert(f.ctx.data.selectedId == children[1].id)
        assert(f.ctx.x == nil and f.ctx.y == nil)
    end)
    Check("late creation receipt saves its pin without reclaiming selection", function(f)
        f.mode = "pending"
        f.T.AddAt(f.ctx, 0.31, 0.67)
        local write = f.writes[#f.writes]
        f.env.OverlandMapSession.Transition("selection", f.ctx)
        f.ctx.data.selectedId = "newer-selection"
        write.callbacks.success()
        assert(f.M.GetLocation(write.row.id) ~= nil and f.ctx.data.selectedId == "newer-selection")
    end)
    Check("add label dispatch creates an editable draft at the clicked point", function(f)
        f.ctx.data.tool = "labelAdd"
        f.T.PlaceAt(f.ctx, 0.42, 0.61)
        assert(f.draft ~= nil)
        assert(f.L.Stage(f.draft, { text = "Placed label" }))
        f.L.Flush(f.draft); f.Advance(0)
        local row = f.L.Get(f.draft)
        assert(row and row.u == 0.42 and row.v == 0.61)
    end)
    Check("ruler and scale use two clicked points", function(f)
        for _, tool in ipairs({ "ruler", "scale" }) do
            f.ctx.data.tool = tool
            f.T.PlaceAt(f.ctx, 0.2, 0.3); f.T.PlaceAt(f.ctx, 0.7, 0.8)
            local measure = tool == "ruler" and f.ctx.data.ruler or f.ctx.data.scaleDraft
            assert(measure and measure.u1 == 0.2 and measure.v1 == 0.3 and measure.u2 == 0.7 and measure.v2 == 0.8)
        end
        assert(f.ctx.data.tool == "none" and f.ctx.data.popover == "settings")
    end)
    Check("letterbox clicks and an inactive tool create nothing", function(f)
        local before = #f.writes
        f.T.PlaceAt(f.ctx, 0.2, 0.3)
        f.ctx.data.tool = "add"
        f.T.PlaceAt(f.ctx, nil, nil)
        assert(#f.writes == before)
    end)
    Check("pointcrawl ruler ignores a stored daily pace while free travel still uses it", function(f)
        local map = { scale = { u1 = 0, v1 = 0, u2 = 1, v2 = 0, distance = 30, unit = "mi" }, pace = 30 }
        local measure = { u1 = 0, v1 = 0, u2 = 1, v2 = 0 }
        local text = f.T.MeasureText(map, 1000, 500, measure)
        assert(text == "30 mi - 1 day")
        map.mode = "pointcrawl"
        text = f.T.MeasureText(map, 1000, 500, measure)
        assert(text == "30 mi")
    end)
    Check("panel positioning and centered placement remain independent", function(f)
        local panel = {}
        f.env.OverlandMapDrawing.PositionPanel(panel, 12, -7)
        assert(panel.x == 12 and panel.y == -7)
        f.env.OverlandMapDrawing.PlaceCentered(panel, { viewWidth = 200, viewHeight = 100 }, 130, 70)
        assert(panel.x == 30 and panel.y == 20)
    end)
    print(string.format("CANVAS TOOLS: %d checks passed", passed))
    return true
end

if ... == "run" then checks.Run() end
return checks
