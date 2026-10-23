local mod = dmhub.GetModLoading()

--- @class OverlandMapGuideLayer: GameType
--- @field new fun(o?: table): OverlandMapGuideLayer
OverlandMapGuideLayer = RegisterGameType("OverlandMapGuideLayer")
local C, Model = OverlandMapConstants, OverlandMapModel
local Session, Copy = OverlandMapControls, OverlandMapCopy
local Clamp, IsFinite = Model.Clamp, Model.IsFinite
local ImageToPanel = OverlandMapGeometry.ImageToPanel

local ClipSegment = OverlandMapGeometry.ClipSegment
local PlaceCentered, Stretch = OverlandMapDrawing.PlaceCentered, OverlandMapDrawing.Stretch

--- The canvas layers that draw the Party's past route (below pins) and the
--- ruler (above them). The canvas adds route and ruler to its children,
--- calls Bind when the model changes and Layout whenever it lays out.
--- @class OverlandMapOverlay
--- @field route Panel non-interactable layer of route dots
--- @field ruler Panel non-interactable layer with the ruler line and end dots
--- @field label Panel the ruler's label; a direct canvas child so it can show a tooltip
--- @field Bind fun()
--- @field Layout fun(layout: nil|OverlandMapLayout, imageWidth: nil|number, imageHeight: nil|number, moving: nil|boolean) moving: a zoom is in motion (see Stretch)

--- @param ctx OverlandMapContext
--- @return OverlandMapOverlay
function OverlandMapGuideLayer.Create(ctx)
    local data = ctx.data
    local noLegs = {} --- @type OverlandMapRoutePoint[][] one shared empty route, so "no route" compares equal
    local legs = noLegs --- @type OverlandMapRoutePoint[][]
    local legsKey = "" -- which route the dots were built from
    local labelTooltip = nil --- @type nil|string
    -- Like the pin layer, the route layer slides while the map pans; dots are
    -- placed again only on zoom, after a long pan or when the route changes.
    local routeRef = nil --- @type nil|OverlandMapLayout
    local routeX, routeY = 0, 0
    local routeStretched = false -- moved mid-zoom (Stretch) rather than placed

    -- Sized inline: this layer never changes class, so the engine never re-resolves
    -- its styles after it is attached and the class size alone left it at 100x100.
    local route = gui.Panel {
        classes = { "overlandMapOverlay" }, floating = true, interactable = false,
        width = "100%", height = "100%",
    }
    local function Dot(classes)
        return gui.Panel { classes = classes, floating = true, halign = "center", valign = "center", interactable = false }
    end
    local line = Dot({ "overlandMapRulerLine" })
    local startDot = Dot({ "overlandMapRulerEnd" })
    local endDot = Dot({ "overlandMapRulerEnd" })
    local ruler = gui.Panel {
        classes = { "overlandMapOverlay" }, floating = true, interactable = false,
        line, startDot, endDot,
    }
    local label = gui.Label {
        classes = { "overlandMapRulerLabel", "collapsed", "sizeS" }, floating = true, halign = "center", valign = "center",
        text = "",
        hover = function(element)
            if labelTooltip ~= nil then gui.Tooltip(labelTooltip)(element) end
        end,
    }

    local dots = OverlandMapDrawing.Pool(function() return Dot({ "overlandMapRouteDot" }) end, route)

    -- Dots every routeDotSpacing screen px along the legs, only on screen and
    -- half a view around it, so a pan of up to half a view needs no new dots.
    local function PlaceDots(layout)
        dots.Begin()
        local spacing = C.routeDotSpacing
        local marginX, marginY = layout.viewWidth / 2 + spacing, layout.viewHeight / 2 + spacing
        local x0, y0, x1, y1 = -marginX, -marginY, layout.viewWidth + marginX, layout.viewHeight + marginY
        for _, points in ipairs(legs) do
            for i = 1, #points - 1 do
                local ax, ay = OverlandMapGeometry.ImageToPanel(layout, points[i].u, points[i].v)
                local bx, by = OverlandMapGeometry.ImageToPanel(layout, points[i + 1].u, points[i + 1].v)
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
        local measure = nil --- @type nil|OverlandMapMeasure
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
        local ax, ay = OverlandMapGeometry.ImageToPanel(layout, measure.u1, measure.v1)
        PlaceCentered(startDot, layout, ax, ay)
        local complete = measure.u2 ~= nil and measure.v2 ~= nil
        ShowPart(line, complete)
        ShowPart(endDot, complete)
        if not complete then
            ShowPart(label, false)
            return
        end
        local bx, by = OverlandMapGeometry.ImageToPanel(layout, measure.u2 --[[@as number]], measure.v2 --[[@as number]])
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
        local text, calibrated = OverlandMapCanvasTools.MeasureText(map, imageWidth --[[@as number]],
            imageHeight --[[@as number]], measure)
        if label.text ~= text then label.text = text end
        labelTooltip = (not calibrated and Model.IsDirector()) and OverlandMapCopy.T("ruler.uncalibrated.hint") or nil
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
            if map ~= nil and OverlandMapPreferences.ShowRoute() then newLegs = OverlandMapLog.Route(map.id) end
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
