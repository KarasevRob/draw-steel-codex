--- Canvas geometry and placement tools: image/screen coordinate math, the Add
--- and Move tools (a click on the map places), and the map's right-click menu.
--- The canvas calls these; they report through the context.
--- @class RegionMapCanvasTools: GameType
--- @field new fun(o?: table): RegionMapCanvasTools
RegionMapCanvasTools = RegisterGameType("RegionMapCanvasTools")
local C = RegionMapConstants
local Model = RegionMapModel
local Session = RegionMapSession

local Clamp = Model.Clamp
local IsFinite = Model.IsFinite

--- Where the image sits inside the canvas, in canvas pixels.
--- @class RegionMapLayout
--- @field x number
--- @field y number
--- @field width number
--- @field height number
--- @field viewWidth number
--- @field viewHeight number

--- Calls onSize(width, height) once with an image's size in pixels, as soon as the
--- engine knows it. Cores without the size API never call back, so nothing warns.
--- @param imageId string
--- @param onSize fun(width: integer, height: integer)
function RegionMapCanvasTools.ImageSize(imageId, onSize)
    local reported = false
    local function Report(dims)
        if reported or type(dims) ~= "table" then return end
        local width, height = tonumber(dims.width), tonumber(dims.height)
        if width == nil or height == nil or width <= 0 or height <= 0 then return end
        reported = true
        onSize(math.floor(width + 0.5), math.floor(height + 0.5))
    end
    local ok, dims = pcall(function() return gui.TryGetImageDimensions(imageId) end)
    if ok and dims ~= nil then
        Report(dims)
        return
    end
    -- Not known yet (the image is still arriving): ask to be told once it is.
    pcall(function() gui.GetImageDimensionsCallback(imageId, Report) end)
end

--- The Soft fade border (K1): four strips over a map image's edges that shade from
--- the canvas color to clear, so the art melts into the background. Size the panel
--- like the image, then call SetFadeBand. It never takes the pointer, and the
--- canvas draws pins, paths and the Party above it (Q23).
--- @return Panel
function RegionMapCanvasTools.CreateFade()
    local edges = {} --- @type Panel[]
    for _, side in ipairs({ "Left", "Right", "Top", "Bottom" }) do
        edges[#edges + 1] = gui.Panel {
            classes = { "regionMapFadeEdge", "regionMapFade" .. side }, floating = true, interactable = false,
            data = { side = side },
        }
    end
    return gui.Panel {
        classes = { "regionMapFade" }, floating = true, interactable = false, halign = "left", valign = "top",
        data = { band = nil }, children = edges,
    }
end

--- Set how deep the fade reaches into the image, in pixels.
--- @param fade Panel from CreateFade
--- @param band number
function RegionMapCanvasTools.SetFadeBand(fade, band)
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

--- The fade depth for an image drawn width x height on screen: a share of its
--- shorter side, capped so a zoomed-in map keeps a narrow edge.
--- @param width number
--- @param height number
--- @return number
function RegionMapCanvasTools.FadeBand(width, height)
    return math.min(math.min(width, height) * C.fadeShare, C.fadeMaxWidth)
end

--- Fit the image into the view, apply zoom and clamp the camera so the image
--- never leaves a gap it could fill. Writes the clamped values back to camera.
--- rightInset is the width an open panel covers at the right: the image may then
--- slide that much further left, so a pin under the panel can be brought out.
--- @param viewWidth number
--- @param viewHeight number
--- @param imageWidth number
--- @param imageHeight number
--- @param camera RegionMapCamera
--- @param rightInset nil|number
--- @return nil|RegionMapLayout
function RegionMapCanvasTools.CalculateImageLayout(viewWidth, viewHeight, imageWidth, imageHeight, camera, rightInset)
    if not IsFinite(viewWidth) or not IsFinite(viewHeight) or not IsFinite(imageWidth) or not IsFinite(imageHeight)
        or viewWidth <= 0 or viewHeight <= 0 or imageWidth <= 0 or imageHeight <= 0 then
        return nil
    end
    local fitScale = math.min(viewWidth / imageWidth, viewHeight / imageHeight)
    local zoom = Clamp(camera.zoom or C.minZoom, C.minZoom, C.maxZoom)
    local width = imageWidth * fitScale * zoom
    local height = imageHeight * fitScale * zoom
    local centerX = camera.centerX or 0.5
    local centerY = camera.centerY or 0.5
    -- The image's left edge (x) may go from maxX down to minX: centred or flush with the
    -- view, and with a panel open, until its right edge meets the panel.
    local inset = IsFinite(rightInset) and Clamp(rightInset --[[@as number]], 0, viewWidth) or 0
    local maxX = width <= viewWidth and (viewWidth - width) / 2 or 0
    local minX = math.min(maxX, viewWidth - inset - width)
    centerX = Clamp(centerX, (viewWidth / 2 - maxX) / width, (viewWidth / 2 - minX) / width)
    if height <= viewHeight then
        centerY = 0.5
    else
        local halfVisible = viewHeight / (2 * height)
        centerY = Clamp(centerY, halfVisible, 1 - halfVisible)
    end
    camera.zoom = zoom
    camera.centerX = centerX
    camera.centerY = centerY
    return {
        x = viewWidth * 0.5 - centerX * width,
        y = viewHeight * 0.5 - centerY * height,
        width = width,
        height = height,
        viewWidth = viewWidth,
        viewHeight = viewHeight,
    }
end

--- @param layout RegionMapLayout
--- @param u number
--- @param v number
--- @return number x, number y
function RegionMapCanvasTools.ImageToPanel(layout, u, v)
    return layout.x + u * layout.width, layout.y + v * layout.height
end

--- @param layout RegionMapLayout
--- @param x number
--- @param y number
--- @return nil|number u, nil|number v nil when the point is off the image (letterbox)
function RegionMapCanvasTools.PanelToImage(layout, x, y)
    local u = (x - layout.x) / layout.width
    local v = (y - layout.y) / layout.height
    if u < 0 or u > 1 or v < 0 or v > 1 then
        return nil, nil
    end
    return u, v
end

--- Create a Location at a point of the open map, copying the last pin style
--- (R10), and open it in the side panel in edit mode once the server has it.
--- @param ctx RegionMapContext
--- @param u number
--- @param v number
function RegionMapCanvasTools.AddAt(ctx, u, v)
    local map = ctx.CurrentMap()
    if map == nil then return end
    ctx.FlushEdits()
    -- The server confirms after this returns, so the callback reads newId set below.
    local newId = nil
    local ok, reason, _, id = Model.CreateLocation(map.id, u, v, Session.LastPinStyle(), {
        success = function()
            if not ctx.IsAlive() or ctx.data.mapId ~= map.id or newId == nil then return end
            ctx.data.focusName = true
            ctx.Select(newId, "edit")
        end,
        failure = function() ctx.Report(false, "unavailable") end,
    })
    newId = id
    if not ctx.Report(ok, reason) then ctx.SetTool("none") end
end

--- Put the Location the Move tool carries at a point of the open map.
--- @param ctx RegionMapContext
--- @param u number
--- @param v number
function RegionMapCanvasTools.MoveTo(ctx, u, v)
    local location = Model.GetLocation(ctx.data.toolTargetId)
    if location == nil then
        ctx.SetTool("none")
        return
    end
    local ok, reason, entry = Model.MoveLocation(location.id, u, v)
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

-- Set scale (V2-14): two clicks pick the points, then Settings asks for the distance.
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
--- @param ctx RegionMapContext
--- @param u nil|number
--- @param v nil|number
function RegionMapCanvasTools.PlaceAt(ctx, u, v)
    if u == nil or v == nil then return end
    local map = ctx.CurrentMap()
    if map == nil then return end
    if ctx.data.tool == "add" then
        RegionMapCanvasTools.AddAt(ctx, u, v)
    elseif ctx.data.tool == "move" then
        RegionMapCanvasTools.MoveTo(ctx, u, v)
    elseif ctx.data.tool == "ruler" then
        RulerClick(ctx, map, u, v)
    elseif ctx.data.tool == "scale" then
        ScaleClick(ctx, map, u, v)
    end
end

-- Measuring ---------------------------------------------------------------------------------

-- "9", "2.5", "14": one decimal below 10, whole numbers above.
local function FormatNumber(value)
    if value >= 10 then return string.format("%d", math.floor(value + 0.5)) end
    local text = string.format("%.1f", value)
    return (text:gsub("%.0$", ""))
end
RegionMapCanvasTools.FormatNumber = FormatNumber

-- Length between two map points in image pixels, so a non-square map measures true.
local function ImageDistance(width, height, u1, v1, u2, v2)
    return math.sqrt(((u2 - u1) * width) ^ 2 + ((v2 - v1) * height) ^ 2)
end

--- The ruler label for two points on a map (manifest section 14): distance
--- and travel time from the map's scale and pace, or a percent of the map's
--- width when no scale is set.
--- @param map RegionMapLocationRecord
--- @param imageWidth number
--- @param imageHeight number
--- @param m RegionMapMeasure a complete measure (u2/v2 set)
--- @return string text
--- @return boolean calibrated
function RegionMapCanvasTools.MeasureText(map, imageWidth, imageHeight, m)
    local T = RegionMapCopy.T
    local pixels = ImageDistance(imageWidth, imageHeight, m.u1, m.v1, m.u2 or m.u1, m.v2 or m.v1)
    local scale = Model.Field(map, "scale", nil) --[[@as nil|RegionMapScale]]
    local reference = scale and ImageDistance(imageWidth, imageHeight, scale.u1, scale.v1, scale.u2, scale.v2) or 0
    if scale == nil or reference <= 0 then
        return T("ruler.uncalibrated", { percent = math.floor(pixels / imageWidth * 100 + 0.5) }), false
    end
    local distance = pixels / reference * scale.distance
    local args = { distance = FormatNumber(distance), unitShort = T("ruler.unitShort." .. scale.unit) }
    local pace = Model.Field(map, "pace", nil)
    if not IsFinite(pace) or pace <= 0 then return T("ruler.distance", args), true end
    local days = distance / pace
    if days < 0.5 then
        args.time = T("ruler.time.under")
    else
        local rounded = math.floor(days * 2 + 0.5) / 2
        args.time = T("ruler.time.days", { days = FormatNumber(rounded), count = rounded == 1 and 1 or 2 })
    end
    return T("ruler.withTime", args), true
end

-- Overlay: the drawn route and the ruler --------------------------------------------------------

--- Puts a center-aligned panel's middle at canvas point (x, y). The engine's
--- pivot does not move a panel, so offsets are measured from the canvas center.
--- Positions on the map go through panel.x/y, never selfStyle: a selfStyle write
--- re-matches the panel, and a layer's whole subtree, against every style rule
--- (544 on the map), which made a pan at close zoom run near 10 fps.
-- Where each piece was last placed (its offset from the canvas center), so a zoom
-- in motion can move it from there; weak keys let destroyed panels go.
local placedX = setmetatable({}, { __mode = "k" }) --- @type table<Panel, number>
local placedY = setmetatable({}, { __mode = "k" }) --- @type table<Panel, number>

--- Puts a panel at offset (x, y) from the canvas center and remembers it (see Stretch).
--- Positions on the map go through panel.x/y, never selfStyle: a selfStyle write
--- re-matches the panel, and a layer's whole subtree, against every style rule
--- (544 on the map), which made a pan at close zoom run near 10 fps.
--- @param panel Panel
--- @param x number
--- @param y number
function RegionMapCanvasTools.PlaceAt(panel, x, y)
    panel.x, panel.y = x, y
    placedX[panel], placedY[panel] = x, y
end
local PlaceAt = RegionMapCanvasTools.PlaceAt

--- Puts a center-aligned panel's middle at canvas point (x, y). The engine's
--- pivot does not move a panel, so offsets are measured from the canvas center.
--- @param panel Panel
--- @param layout RegionMapLayout
--- @param x number
--- @param y number
function RegionMapCanvasTools.PlaceCentered(panel, layout, x, y)
    PlaceAt(panel, x - layout.viewWidth * 0.5, y - layout.viewHeight * 0.5)
end
local PlaceCentered = RegionMapCanvasTools.PlaceCentered

--- While a zoom is in motion (a camera ease or a burst of wheel notches), the
--- pieces of a layer placed against `ref` are moved to where `layout` shows those
--- points, keeping their size, instead of being placed again each frame; the
--- caller places them for real once the zoom settles. Pieces move through
--- panel.x/y: scaling the layer is a style write, ~100 ms a frame on the map.
--- Returns false, changing nothing, when the view has left the area placed
--- around ref (on screen and half a view around it), so the caller places again.
--- @param panel Panel a floating layer the size of the canvas, holding the pools
--- @param pools {items: Panel[], used: integer}[] the pools whose pieces were placed against ref
--- @param ref RegionMapLayout the layout its pieces were placed against
--- @param layout RegionMapLayout the current layout
--- @return boolean
function RegionMapCanvasTools.Stretch(panel, pools, ref, layout)
    local k = layout.width / ref.width
    if not IsFinite(k) or k <= 0 then return false end
    local viewWidth, viewHeight = layout.viewWidth, layout.viewHeight
    -- The screen edges in ref's frame: a screen point s shows ref point ref.x + (s - layout.x) / k.
    local left, right = ref.x - layout.x / k, ref.x + (viewWidth - layout.x) / k
    local top, bottom = ref.y - layout.y / k, ref.y + (viewHeight - layout.y) / k
    if left < -viewWidth / 2 or right > viewWidth * 1.5 or top < -viewHeight / 2 or bottom > viewHeight * 1.5 then
        return false
    end
    panel.x, panel.y = 0, 0
    -- A piece at offset p (from the center, in ref) shows at layout.x + (p + view/2 - ref.x) * k.
    local offsetX = layout.x + (viewWidth / 2 - ref.x) * k - viewWidth / 2
    local offsetY = layout.y + (viewHeight / 2 - ref.y) * k - viewHeight / 2
    for _, pool in ipairs(pools) do
        local items = pool.items
        for i = 1, pool.used do
            local item = items[i]
            local x, y = placedX[item], placedY[item]
            if x ~= nil and y ~= nil then
                item.x, item.y = offsetX + x * k, offsetY + y * k
            end
        end
    end
    return true
end
local Stretch = RegionMapCanvasTools.Stretch

--- The part of segment a-b inside the rectangle [x0,x1]x[y0,y1], as 0..1
--- parameters along it (Liang-Barsky), or nil when it misses the rectangle.
--- Shared by the route dots and the path layer, which cull to the view with it.
--- @param ax number
--- @param ay number
--- @param bx number
--- @param by number
--- @param x0 number
--- @param y0 number
--- @param x1 number
--- @param y1 number
function RegionMapCanvasTools.ClipSegment(ax, ay, bx, by, x0, y0, x1, y1)
    local t0, t1 = 0, 1
    local dx, dy = bx - ax, by - ay
    -- The four edges as (p, q) pairs, unrolled: this runs for every segment on every
    -- re-place, and a table per edge was garbage each time.
    local p, q
    for edge = 1, 4 do
        if edge == 1 then p, q = -dx, ax - x0
        elseif edge == 2 then p, q = dx, x1 - ax
        elseif edge == 3 then p, q = -dy, ay - y0
        else p, q = dy, y1 - ay end
        if p == 0 then
            if q < 0 then return nil end
        else
            local t = q / p
            if p < 0 then
                if t > t1 then return nil end
                if t > t0 then t0 = t end
            else
                if t < t0 then return nil end
                if t < t1 then t1 = t end
            end
        end
    end
    return t0, t1
end
local ClipSegment = RegionMapCanvasTools.ClipSegment

--- A pool of panels in one z-layer, reused by index. Each pass calls Begin,
--- then Next once for every panel it needs, then Finish. Panels past the count
--- in use are collapsed, never destroyed, so a dense map reuses them on every
--- zoom, and the layer's children are set once per pass, only after it grew.
--- @param make fun(): Panel builds one new panel
--- @param group nil|Panel the layer to fill; nil makes a full-size one (pool.group)
function RegionMapCanvasTools.Pool(make, group)
    -- Sized inline: a layer whose classes never change gets no class styles (V2 lesson).
    group = group or gui.Panel { floating = true, interactable = false, width = "100%", height = "100%", flow = "none" }
    local pool = { group = group, items = {}, used = 0, shown = 0, grown = false }
    function pool.Next()
        pool.used = pool.used + 1
        local item = pool.items[pool.used]
        if item == nil then
            item = make()
            pool.items[pool.used] = item
            pool.grown = true
        else
            Session.SetClassIf(item, "collapsed", false)
        end
        return item
    end
    function pool.Begin() pool.used = 0 end
    function pool.Finish()
        if pool.grown then
            pool.grown = false
            group.children = pool.items
        end
        for i = pool.used + 1, pool.shown do
            local item = pool.items[i]
            if item ~= nil then Session.SetClassIf(item, "collapsed", true) end
        end
        pool.shown = pool.used
    end
    return pool
end

--- @class RegionMapRunPool
--- @field group Panel the layer holding every piece
--- @field items Panel[] the pieces in use after the last Finish
--- @field used integer during a pass, pieces handed out so far; after Finish, #items
--- @field Begin fun()
--- @field Next fun(key: string): Panel
--- @field Finish fun()

--- Like Pool, but pieces are handed out in runs: Next(key) gives the next piece of
--- that key's run, and a run keeps its pieces from pass to pass. Key a run by what
--- its pieces share (one segment of one path), and a re-place after a zoom or pan
--- gets back the pieces that already have its angle, colour and size, so only
--- their positions change; a style write per piece is what made the re-place stall.
--- After Finish, items and used list the pieces in use (for Stretch).
--- @param make fun(): Panel builds one new panel
--- @return RegionMapRunPool
function RegionMapCanvasTools.RunPool(make)
    local group = gui.Panel { floating = true, interactable = false, width = "100%", height = "100%", flow = "none" }
    ---@diagnostic disable-next-line: missing-fields
    local pool = { group = group, items = {}, used = 0 } --- @type RegionMapRunPool
    local all = {} --- @type Panel[] every piece made: the group's children
    local free = {} --- @type Panel[] pieces in no run, collapsed
    local runs = {} --- @type table<string, {items: Panel[], used: integer}>
    local grown = false
    function pool.Begin()
        pool.used = 0
        for _, run in pairs(runs) do run.used = 0 end
    end
    function pool.Next(key)
        local run = runs[key]
        if run == nil then
            run = { items = {}, used = 0 }
            runs[key] = run
        end
        run.used = run.used + 1
        pool.used = pool.used + 1
        local item = run.items[run.used]
        if item == nil then
            item = table.remove(free)
            if item == nil then
                item = make()
                all[#all + 1] = item
                grown = true
            else
                Session.SetClassIf(item, "collapsed", false)
            end
            run.items[run.used] = item
        end
        return item
    end
    function pool.Finish()
        if grown then
            grown = false
            group.children = all
        end
        local items = {}
        for key, run in pairs(runs) do
            -- A run that shrank gives its spare pieces to the free list for any run to take.
            for i = #run.items, run.used + 1, -1 do
                local item = run.items[i]
                run.items[i] = nil
                Session.SetClassIf(item, "collapsed", true)
                free[#free + 1] = item
            end
            if run.used == 0 then runs[key] = nil end
            for i = 1, run.used do items[#items + 1] = run.items[i] end
        end
        pool.items, pool.used = items, #items
    end
    return pool
end

--- The canvas layers that draw the Party's past route (below pins) and the
--- ruler (above them). The canvas adds route and ruler to its children,
--- calls Bind when the model changes and Layout whenever it lays out.
--- @class RegionMapOverlay
--- @field route Panel non-interactable layer of route dots
--- @field ruler Panel non-interactable layer with the ruler line and end dots
--- @field label Panel the ruler's label; a direct canvas child so it can show a tooltip
--- @field Bind fun()
--- @field Layout fun(layout: nil|RegionMapLayout, imageWidth: nil|number, imageHeight: nil|number, moving: nil|boolean) moving: a zoom is in motion (see Stretch)

--- @param ctx RegionMapContext
--- @return RegionMapOverlay
function RegionMapCanvasTools.CreateOverlay(ctx)
    local data = ctx.data
    local noLegs = {} --- @type RegionMapRoutePoint[][] one shared empty route, so "no route" compares equal
    local legs = noLegs --- @type RegionMapRoutePoint[][]
    local legsKey = "" -- which route the dots were built from
    local labelTooltip = nil --- @type nil|string
    -- Like the pin layer, the route layer slides while the map pans; dots are
    -- placed again only on zoom, after a long pan or when the route changes.
    local routeRef = nil --- @type nil|RegionMapLayout
    local routeX, routeY = 0, 0
    local routeStretched = false -- moved mid-zoom (Stretch) rather than placed

    -- Sized inline: this layer never changes class, so the engine never re-resolves
    -- its styles after it is attached and the class size alone left it at 100x100.
    local route = gui.Panel {
        classes = { "regionMapOverlay" }, floating = true, interactable = false,
        width = "100%", height = "100%",
    }
    local function Dot(classes)
        return gui.Panel { classes = classes, floating = true, halign = "center", valign = "center", interactable = false }
    end
    local line = Dot({ "regionMapRulerLine" })
    local startDot = Dot({ "regionMapRulerEnd" })
    local endDot = Dot({ "regionMapRulerEnd" })
    local ruler = gui.Panel {
        classes = { "regionMapOverlay" }, floating = true, interactable = false,
        line, startDot, endDot,
    }
    local label = gui.Label {
        classes = { "regionMapRulerLabel", "collapsed" }, floating = true, halign = "center", valign = "center",
        text = "",
        hover = function(element)
            if labelTooltip ~= nil then gui.Tooltip(labelTooltip)(element) end
        end,
    }

    local dots = RegionMapCanvasTools.Pool(function() return Dot({ "regionMapRouteDot" }) end, route)

    -- Dots every routeDotSpacing screen px along the legs, only on screen and
    -- half a view around it, so a pan of up to half a view needs no new dots.
    local function PlaceDots(layout)
        dots.Begin()
        local spacing = C.routeDotSpacing
        local marginX, marginY = layout.viewWidth / 2 + spacing, layout.viewHeight / 2 + spacing
        local x0, y0, x1, y1 = -marginX, -marginY, layout.viewWidth + marginX, layout.viewHeight + marginY
        for _, points in ipairs(legs) do
            for i = 1, #points - 1 do
                local ax, ay = RegionMapCanvasTools.ImageToPanel(layout, points[i].u, points[i].v)
                local bx, by = RegionMapCanvasTools.ImageToPanel(layout, points[i + 1].u, points[i + 1].v)
                local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
                local t0, t1 = ClipSegment(ax, ay, bx, by, x0, y0, x1, y1)
                if t0 ~= nil and length > 0 then
                    -- Dots sit at whole multiples of the spacing from the leg's start,
                    -- so they stay put while the view pans.
                    local first = math.ceil(t0 * length / spacing)
                    local last = math.floor(t1 * length / spacing)
                    for step = first, last do
                        if dots.used >= C.routeDotLimit then break end
                        local t = step * spacing / length
                        PlaceCentered(dots.Next(), layout, ax + (bx - ax) * t, ay + (by - ay) * t)
                    end
                end
            end
        end
        dots.Finish()
    end

    local function LayoutRoute(layout, moving)
        local ref = routeRef
        -- Mid-zoom, the dots placed last stretch with the map (see Stretch).
        if moving and ref ~= nil and ref.viewWidth == layout.viewWidth and ref.viewHeight == layout.viewHeight
            and (ref.width ~= layout.width or routeStretched) and Stretch(route, { dots }, ref, layout) then
            routeStretched = true
            -- The stretch moved the layer; the next slide must write its place again.
            routeX, routeY = -math.huge, -math.huge
            return
        end
        if routeStretched then
            -- The dots sit where the stretch left them, so place them again even if the zoom came back.
            routeStretched = false
            ref = nil
        end
        if ref == nil or ref.width ~= layout.width or ref.height ~= layout.height
            or ref.viewWidth ~= layout.viewWidth or ref.viewHeight ~= layout.viewHeight
            or math.abs(layout.x - ref.x) > layout.viewWidth / 2 or math.abs(layout.y - ref.y) > layout.viewHeight / 2 then
            ref = layout
            routeRef = layout
            PlaceDots(layout)
        end
        local x, y = layout.x - ref.x, layout.y - ref.y
        if x ~= routeX or y ~= routeY then
            routeX, routeY = x, y
            route.x, route.y = x, y
        end
    end

    -- Layout runs every frame of a pan or zoom, so classes are touched only when they flip.
    local function ShowPart(panel, show)
        Session.SetClassIf(panel, "collapsed", not show)
    end

    local function HideRuler()
        ShowPart(ruler, false)
        ShowPart(label, false)
    end

    local function LayoutRuler(layout, imageWidth, imageHeight)
        local measure = nil --- @type nil|RegionMapMeasure
        local isScale = false
        if data.tool == "scale" or (data.scaleDraft ~= nil and data.popover == "settings") then
            measure, isScale = data.scaleDraft, true
        elseif data.tool == "ruler" then
            measure = data.ruler
        end
        -- No measure (the usual case) needs no model question at all.
        if measure == nil then
            HideRuler()
            return
        end
        local map = ctx.CurrentMap()
        if map == nil or measure.mapId ~= map.id then
            HideRuler()
            return
        end
        ShowPart(ruler, true)
        local ax, ay = RegionMapCanvasTools.ImageToPanel(layout, measure.u1, measure.v1)
        PlaceCentered(startDot, layout, ax, ay)
        local complete = measure.u2 ~= nil and measure.v2 ~= nil
        ShowPart(line, complete)
        ShowPart(endDot, complete)
        if not complete then
            ShowPart(label, false)
            return
        end
        local bx, by = RegionMapCanvasTools.ImageToPanel(layout, measure.u2 --[[@as number]], measure.v2 --[[@as number]])
        PlaceCentered(endDot, layout, bx, by)
        -- A thin panel as long as the measure, centered on its middle and turned to its angle.
        local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        line.selfStyle.width = math.max(1, length)
        PlaceCentered(line, layout, (ax + bx) / 2, (ay + by) / 2)
        line.selfStyle.rotate = -math.deg(math.atan(by - ay, bx - ax))
        if isScale or not IsFinite(imageWidth) or not IsFinite(imageHeight) then
            ShowPart(label, false)
            return
        end
        local text, calibrated = RegionMapCanvasTools.MeasureText(map, imageWidth --[[@as number]],
            imageHeight --[[@as number]], measure)
        if label.text ~= text then label.text = text end
        labelTooltip = (not calibrated and Model.IsDirector()) and RegionMapCopy.T("ruler.uncalibrated.hint") or nil
        ShowPart(label, true)
        -- The label sits just above the end point, clear of the end dot.
        PlaceCentered(label, layout, bx, by - C.rulerEndSize - 12)
    end

    return {
        route = route,
        ruler = ruler,
        label = label,
        Bind = function()
            local map = ctx.CurrentMap()
            local newLegs = noLegs
            if map ~= nil and Session.ShowRoute() then newLegs = RegionMapLog.Route(map.id) end
            -- The log keeps one route list per map until its entries change, so the same list means no change.
            if newLegs == legs then return end
            -- Rows are replaced, not edited, when an entry changes, so table identity and size tell a change.
            local parts = { map and map.id or "" }
            for _, points in ipairs(newLegs) do parts[#parts + 1] = tostring(points) .. "#" .. #points end
            local key = table.concat(parts, ",")
            legs = newLegs
            if key ~= legsKey then
                legsKey = key
                routeRef = nil
            end
        end,
        Layout = function(layout, imageWidth, imageHeight, moving)
            if layout == nil then
                routeRef = nil
                dots.Begin()
                dots.Finish()
                HideRuler()
                return
            end
            LayoutRoute(layout, moving == true)
            LayoutRuler(layout, imageWidth, imageHeight)
        end,
    }
end

--- The map's right-click menu entries at a point (manifest section 6).
--- @param ctx RegionMapContext
--- @param u number
--- @param v number
--- @param snapId nil|string a pin within the Party snap radius of the click
--- @return table[] gui.ContextMenu entries
function RegionMapCanvasTools.MapMenu(ctx, u, v, snapId)
    local map = ctx.CurrentMap()
    local entries = {}
    if map == nil then return entries end
    if Model.CanAdd(map.id) then
        entries[#entries + 1] = {
            text = RegionMapCopy.T("ctx.map.add"),
            click = function() RegionMapCanvasTools.AddAt(ctx, u, v) end,
        }
    end
    if Model.IsDirector() and Model.CanMovePartyOn(map.id) then
        -- On a point crawl map a placement next to a pin is "at" it, so it can travel on from there (Q16).
        local atId = Model.IsPointCrawl(map) and snapId or nil
        entries[#entries + 1] = {
            text = RegionMapCopy.T("ctx.map.party"),
            click = function()
                local ok, reason, entry = Model.PlaceParty(map.id, u, v, atId)
                if ctx.Report(ok, reason) then
                    ctx.Push(entry, "toast.partyPlaced", { party = Model.PartyName(), map = Model.DisplayName(map) })
                end
            end,
        }
    end
    return entries
end
