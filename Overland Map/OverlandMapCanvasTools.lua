--- Canvas tools: the Soft fade border, what a click places for the active tool
--- (Add, Move, ruler, scale, label, map aid), the ruler's text and the map's
--- right-click menu. The canvas calls these; they report through the context.
--- @class OverlandMapCanvasTools: GameType
--- @field new fun(o?: table): OverlandMapCanvasTools
OverlandMapCanvasTools = RegisterGameType("OverlandMapCanvasTools")
local C = OverlandMapConstants
local Model = OverlandMapModel
local Session = OverlandMapControls
local ClipSegment = OverlandMapGeometry.ClipSegment
local Pool = OverlandMapDrawing.Pool
local Stretch = OverlandMapDrawing.Stretch
local PositionPanel = OverlandMapDrawing.PositionPanel
local PlaceCentered = OverlandMapDrawing.PlaceCentered

local Clamp = Model.Clamp
local IsFinite = Model.IsFinite

--- The Soft fade border (K1): four strips over a map image's edges that shade from
--- the canvas color to clear, so the art melts into the background. Size the panel
--- like the image, then call SetFadeBand. It never takes the pointer, and the
--- canvas draws pins, paths and the Party above it (Q23).
--- @return Panel
function OverlandMapCanvasTools.CreateFade()
    local edges = {} --- @type Panel[]
    for _, side in ipairs({ "Left", "Right", "Top", "Bottom" }) do
        edges[#edges + 1] = gui.Panel {
            classes = { "overlandMapFadeEdge", "overlandMapFade" .. side }, floating = true, interactable = false,
            data = { side = side },
        }
    end
    return gui.Panel {
        classes = { "overlandMapFade" }, floating = true, interactable = false, halign = "left", valign = "top",
        data = { band = nil }, children = edges,
    }
end

--- Set how deep the fade reaches into the image, in pixels.
--- @param fade Panel from CreateFade
--- @param band number
function OverlandMapCanvasTools.SetFadeBand(fade, band)
    band = math.floor(band + 0.5)
    if fade.data.band == band then return end
    fade.data.band = band
    for _, edge in ipairs(fade.children) do
        if edge.data.side == "Left" or edge.data.side == "Right" then
            edge.selfStyle.width = band
        else
            edge.selfStyle.height = band
        end
    end
end

--- Create a Location at a point of the open map, copying the last pin style
--- (R10), and open its compact name editor once the server has it.
--- @param ctx OverlandMapContext
--- @param u number
--- @param v number
function OverlandMapCanvasTools.AddAt(ctx, u, v)
    local map = ctx.CurrentMap()
    if map == nil then return end
    ctx.Transition("placement")
    local valid = OverlandMapSession.Guard(ctx, function() return Model.CanAdd(map.id) end)
    local result = OverlandMapCommands.CreateLocation(map.id, u, v, OverlandMapPreferences.LastPinStyle(), {
        success = function(write)
            local newId = write.record.id
            if not valid() or ctx.data.mapId ~= map.id or not Model.CanEdit(Model.GetLocation(newId)) then return end
            ctx.QuickAdd("location", newId)
        end,
        failure = function() if valid() then ctx.Report(false, "unavailable") end end,
    })
    local ok, reason = OverlandMapCommands.Accepted(result), result.reason
    if not ctx.Report(ok, reason) then ctx.SetTool("none") end
end

--- Put the Location the Move tool carries at a point of the open map.
--- @param ctx OverlandMapContext
--- @param u number
--- @param v number
function OverlandMapCanvasTools.MoveTo(ctx, u, v)
    local location = Model.GetLocation(ctx.data.toolTargetId)
    if location == nil then
        ctx.SetTool("none")
        return
    end
    local result = OverlandMapCommands.MoveLocation(location.id, u, v)
    local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
    -- SetTool redraws the canvas, so it goes after the write or the pin stays put.
    ctx.SetTool("none")
    if ctx.Report(ok, reason) then
        ctx.Push(entry, "toast.moved", { name = Model.DisplayName(location) })
    end
end

-- Ruler (R7): click a start, then an end; a third click starts over. Local only.
local function RulerClick(ctx, map, u, v)
    local ruler = ctx.data.ruler
    if ruler == nil or ruler.mapId ~= map.id or ruler.u2 ~= nil then
        ctx.data.ruler = { mapId = map.id, u1 = u, v1 = v }
    else
        ruler.u2, ruler.v2 = u, v
    end
end

-- Set scale: two clicks pick the points, then Settings asks for the distance.
local function ScaleClick(ctx, map, u, v)
    local draft = ctx.data.scaleDraft
    if draft == nil or draft.mapId ~= map.id or draft.u2 ~= nil then
        ctx.data.scaleDraft = { mapId = map.id, u1 = u, v1 = v }
        return
    end
    draft.u2, draft.v2 = u, v
    ctx.SetTool("none")
    ctx.SetPopover("settings")
end

--- A left click on the map while a tool is active. Letterbox clicks (u nil)
--- are ignored (V1 rule).
--- @param ctx OverlandMapContext
--- @param u nil|number
--- @param v nil|number
function OverlandMapCanvasTools.PlaceAt(ctx, u, v)
    if u == nil or v == nil then return end
    local map = ctx.CurrentMap()
    if map == nil then return end
    if ctx.data.tool == "add" then
        OverlandMapCanvasTools.AddAt(ctx, u, v)
    elseif ctx.data.tool == "labelAdd" then
        ctx.CreateLabel(u, v)
    elseif ctx.data.tool == "move" then
        OverlandMapCanvasTools.MoveTo(ctx, u, v)
    elseif ctx.data.tool == "ruler" then
        RulerClick(ctx, map, u, v)
    elseif ctx.data.tool == "scale" then
        ScaleClick(ctx, map, u, v)
    elseif ctx.data.tool == "aidPlace" then
        local kind = ctx.data.selectedAid
        if kind and ctx.data.aidMapId == map.id then
            OverlandMapAids.Commit(map.id, kind, { u = u, v = v })
            ctx.data.tool = "none"
            ctx.SetPopover("aids")
        end
    end
end

-- Measuring ---------------------------------------------------------------------------------

-- "9", "2.5", "14": one decimal below 10, whole numbers above.
local function FormatNumber(value)
    if value >= 10 then return string.format("%d", math.floor(value + 0.5)) end
    local text = string.format("%.1f", value)
    return (text:gsub("%.0$", ""))
end
OverlandMapCanvasTools.FormatNumber = FormatNumber

-- Length between two map points in image pixels, so a non-square map measures true.
local function ImageDistance(width, height, u1, v1, u2, v2)
    return math.sqrt(((u2 - u1) * width) ^ 2 + ((v2 - v1) * height) ^ 2)
end

--- The ruler label for two points on a map (manifest section 14): distance
--- and travel time from the map's scale and pace, or a percent of the map's
--- width when no scale is set.
--- @param map OverlandMapLocationRecord
--- @param imageWidth number
--- @param imageHeight number
--- @param m OverlandMapMeasure a complete measure (u2/v2 set)
--- @return string text
--- @return boolean calibrated
function OverlandMapCanvasTools.MeasureText(map, imageWidth, imageHeight, m)
    local T = OverlandMapCopy.T
    local pixels = ImageDistance(imageWidth, imageHeight, m.u1, m.v1, m.u2 or m.u1, m.v2 or m.v1)
    local scale = Model.Field(map, "scale", nil) --[[@as nil|OverlandMapScale]]
    local reference = scale and ImageDistance(imageWidth, imageHeight, scale.u1, scale.v1, scale.u2, scale.v2) or 0
    if scale == nil or reference <= 0 then
        return T("ruler.uncalibrated", { percent = math.floor(pixels / imageWidth * 100 + 0.5) }), false
    end
    local distance = pixels / reference * scale.distance
    local args = { distance = FormatNumber(distance), unitShort = T("ruler.unitShort." .. scale.unit) }
    local pace = Model.Field(map, "pace", nil)
    if Model.IsPointCrawl(map) or not IsFinite(pace) or pace <= 0 then return T("ruler.distance", args), true end
    local days = distance / pace
    if days < 0.5 then
        args.time = T("ruler.time.under")
    else
        local rounded = math.floor(days * 2 + 0.5) / 2
        args.time = T("ruler.time.days", { days = FormatNumber(rounded), count = rounded == 1 and 1 or 2 })
    end
    return T("ruler.withTime", args), true
end

--- The map's right-click menu entries at a point (manifest section 6).
--- @param ctx OverlandMapContext
--- @param u number
--- @param v number
--- @param snapId nil|string a pin within the Party snap radius of the click
--- @return table[] gui.ContextMenu entries
function OverlandMapCanvasTools.MapMenu(ctx, u, v, snapId)
    local map = ctx.CurrentMap()
    local entries = {}
    if map == nil then return entries end
    if Model.CanAdd(map.id) then
        entries[#entries + 1] = {
            text = OverlandMapCopy.T("ctx.map.add"),
            click = function() OverlandMapCanvasTools.AddAt(ctx, u, v) end,
        }
    end
    if OverlandMapLabels.CanAdd(map.id) then
        entries[#entries + 1] = { text = OverlandMapCopy.T("label.addHere"), click = function() ctx.CreateLabel(u, v) end }
    end
    if Model.IsDirector() and Model.CanMovePartyOn(map.id) then
        -- On a point crawl map a placement next to a pin is "at" it, so it can travel on from there (Q16).
        local atId = Model.IsPointCrawl(map) and snapId or nil
        entries[#entries + 1] = {
            text = OverlandMapCopy.T("ctx.map.party"),
            click = function()
                local result = OverlandMapCommands.PlaceParty(map.id, u, v, atId)
                local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
                if ctx.Report(ok, reason) then
                    ctx.Push(entry, "toast.partyPlaced", { party = Model.PartyName(), map = Model.DisplayName(map) })
                end
            end,
        }
    end
    return entries
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function OverlandMapCanvasTools.Styles()
    return {
        {
            selectors = { "overlandMapOverlay" },
            width = "100%",
            height = "100%",
            flow = "none",
        },
        {
            selectors = { "overlandMapRouteDot" },
            width = C.routeDotSize,
            height = C.routeDotSize,
            bgimage = true,
            bgcolor = "@accent",
            -- A ring in the theme's background colour keeps the route readable where it runs
            -- along a path of the same colour (Default's accent is parchment, like Road).
            borderColor = "@bg",
            borderWidth = 1.5,
            cornerRadius = C.routeDotSize / 2,
            opacity = 0.85,
        },
        {
            selectors = { "overlandMapRulerLine" },
            height = C.rulerWidth,
            bgimage = true,
            bgcolor = "@accent",
        },
        {
            selectors = { "overlandMapRulerEnd" },
            width = C.rulerEndSize,
            height = C.rulerEndSize,
            bgimage = true,
            bgcolor = "@accent",
            borderColor = "@bg",
            borderWidth = 2,
            cornerRadius = C.rulerEndSize / 2,
        },
        OverlandMapStyles.Chrome("overlandMapRulerLabel", {
            width = "auto",
            height = "auto",
            hpad = 8,
            vpad = 3,
            borderBox = true,
            borderColor = "@accent",
            bold = true,
            color = "@fgStrong",
            textWrap = false,
        }),
    }
end
