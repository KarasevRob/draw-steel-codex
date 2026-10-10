local mod = dmhub.GetModLoading()

--- Draws point crawl paths on the canvas (V21-09) and finds the path under the
--- pointer. Every line is a run of thin rotated panels (the ruler technique):
--- a casing in the opposite tone under each mark (Q1), the coloured mark on top,
--- with patterns sized in screen pixels so they read the same at every zoom (Q2).
--- Panels are pooled and only placed on screen plus half a view around it, so a
--- pan slides the layer and only a zoom, a resize or a long pan places them again.
---
--- The canvas adds `layer` to its children above the border and below the route,
--- calls Bind when the model changes, Layout whenever it lays out, SetFocus when
--- the hovered or selected path changes, and PathAt for clicks and hover.
--- @class RegionMapPathLayer: GameType
--- @field new fun(o?: table): RegionMapPathLayer
RegionMapPathLayer = RegisterGameType("RegionMapPathLayer")
local C = RegionMapConstants
local Model = RegionMapModel
local Paths = RegionMapPaths
local Tools = RegionMapCanvasTools

--- How a path draws: its type's look, or the plain "No type" line (N3).
--- @class RegionMapPathLook
--- @field pattern string
--- @field color string hex
--- @field casing string hex
--- @field width number px at Font Size 100

--- One drawn path: its id, look and points in image units, a to b.
--- @class RegionMapDrawnPath
--- @field id string
--- @field look RegionMapPathLook
--- @field hidden boolean drawn faded with eye-slash badges (Director only sees these)
--- @field points {u: number, v: number}[]
--- @field label string
--- @field aName string the end pins' names, kept clear of labels
--- @field bName string

--- A bend handle drag in progress (V21-14): bend `index` moved to (u, v), or with
--- insert, a new bend put in at `index` (on segment `index` of the line).
--- @class RegionMapBendPreview
--- @field index integer
--- @field insert boolean
--- @field u number
--- @field v number

--- What the canvas holds. `layer` slides with the map; `top` (the line being drawn
--- and the bend handles) goes right above it and is placed again on every Layout.
--- @class RegionMapPathLayerApi
--- @field layer Panel
--- @field top Panel
--- @field Bind fun(mapId: nil|string)
--- @field Layout fun(layout: nil|RegionMapLayout, scale: number, moving: nil|boolean) moving: a zoom is in motion (see Tools.Stretch)
--- @field SetFocus fun(hoverId: nil|string, selectedId: nil|string, showNames: boolean)
--- @field PathAt fun(layout: RegionMapLayout, x: number, y: number, scale: number): nil|string
--- @field SetDraft fun(points: nil|{u: number, v: number}[], cursor: nil|{u: number, v: number}, look: nil|RegionMapPathLook) the start pin and bends so far, and the pointer
--- @field SetHandles fun(pathId: nil|string, preview: nil|RegionMapBendPreview) show a path's bend handles, with a drag's preview
--- @field HandleAt fun(x: number, y: number, scale: number): nil|{kind: "bend"|"plus", index: integer}
--- @field HandlePoints fun(): nil|{u: number, v: number}[] the a end, bends and b end of the path whose handles show

-- Light lines get a dark casing and dark ones a light casing, by perceived brightness.
local function CasingFor(hex)
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)")
    if r == nil then return C.pathCasingDark end
    local brightness = (0.299 * tonumber(r, 16) + 0.587 * tonumber(g, 16) + 0.114 * tonumber(b, 16)) / 255
    return brightness < 0.4 and C.pathCasingLight or C.pathCasingDark
end

--- The look of a path from its type.
--- @param path RegionMapPathRecord
--- @return RegionMapPathLook
function RegionMapPathLayer.LookOf(path)
    return RegionMapPathLayer.LookOfType(Paths.TypeById(path.typeId))
end

--- The look of a type; nil gives the "No type" line (plain, thin, solid).
--- @param item nil|RegionMapPathType
--- @return RegionMapPathLook
function RegionMapPathLayer.LookOfType(item)
    local color = C.pathColors.parchment
    if item == nil then return { pattern = "solid", color = color, casing = CasingFor(color), width = C.pathWidths.thin } end
    color = C.pathColors[item.color] or color
    return { pattern = item.pattern, color = color, casing = CasingFor(color), width = C.pathWidths[item.width] or C.pathWidths.normal }
end

-- The repeating marks of a dashed pattern in screen px: { length, "dash"|"dot" } marks and { length } gaps.
-- Solid and Double are continuous and return nil. Dots are at least 4 px (Q2).
local function Rhythm(pattern, thickness, scale)
    local dot = math.max(4 * scale, thickness + scale)
    if pattern == "dashed" then return { { 10 * scale, "dash" }, { 6 * scale } } end
    if pattern == "longDash" then return { { 20 * scale, "dash" }, { 7 * scale } } end
    if pattern == "dotted" then return { { dot, "dot" }, { 5 * scale } } end
    if pattern == "dashDot" then return { { 10 * scale, "dash" }, { 4 * scale }, { dot, "dot" }, { 4 * scale } } end
    return nil
end

-- Double: two lines of at least 2 px with a 2 px gap, at least 6 px across (Q2).
local function DoubleLine(thickness, scale)
    local line = math.max(2 * scale, thickness * 2 / 3)
    local gap = 2 * scale
    return line, gap, line * 2 + gap
end

-- How wide a path's line is across, for casing, halo and hit band.
local function Across(look, scale)
    local thickness = look.width * scale
    if look.pattern == "double" then
        local _, _, across = DoubleLine(thickness, scale)
        return across
    end
    if look.pattern == "dotted" or look.pattern == "dashDot" then return math.max(4 * scale, thickness + scale) end
    return thickness
end

-- The part of segment a-b inside the rectangle, as 0..1 parameters (Liang-Barsky), or nil.
local function ClipSegment(ax, ay, bx, by, x0, y0, x1, y1)
    local t0, t1 = 0, 1
    local dx, dy = bx - ax, by - ay
    for _, check in ipairs({ { -dx, ax - x0 }, { dx, x1 - ax }, { -dy, ay - y0 }, { dy, y1 - ay } }) do
        local p, q = check[1], check[2]
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

-- Distance from point p to segment a-b, in px.
local function DistanceToSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local lengthSquared = dx * dx + dy * dy
    local t = 0
    if lengthSquared > 0 then t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared)) end
    local cx, cy = ax + dx * t, ay + dy * t
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

-- A group of pooled panels in one z-layer. Panels past the count in use are
-- collapsed, never destroyed, so a dense map reuses them on every zoom.
local function Pool(make)
    -- Sized inline: a layer whose classes never change gets no class styles (V2 lesson).
    local group = gui.Panel { floating = true, interactable = false, width = "100%", height = "100%", flow = "none" }
    local pool = { group = group, items = {}, used = 0, shown = 0, grown = false }
    function pool.Next()
        pool.used = pool.used + 1
        local item = pool.items[pool.used]
        if item == nil then
            item = make()
            pool.items[pool.used] = item
            pool.grown = true
        elseif item:HasClass("collapsed") then
            item:SetClass("collapsed", false)
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
            if item ~= nil and not item:HasClass("collapsed") then item:SetClass("collapsed", true) end
        end
        pool.shown = pool.used
    end
    return pool
end

--- Build the path layer for a canvas.
--- @return RegionMapPathLayerApi
function RegionMapPathLayer.Create()
    local function Piece(classes)
        return gui.Panel { classes = classes, floating = true, halign = "center", valign = "center", interactable = false }
    end
    local halos = Pool(function() return Piece({ "regionMapPathHalo" }) end)
    local casings = Pool(function() return Piece({ "regionMapPathPiece" }) end)
    local marks = Pool(function() return Piece({ "regionMapPathPiece" }) end)
    local badges = Pool(function()
        return gui.Panel {
            classes = { "regionMapPathBadge" }, floating = true, halign = "center", valign = "center", interactable = false,
            gui.Panel { classes = { "regionMapPinBadgeGlyph" }, bgimage = C.iconEyeSlash, interactable = false },
        }
    end)
    local labels = Pool(function()
        return gui.Label { classes = { "regionMapPathLabel" }, floating = true, halign = "center", valign = "center", interactable = false, text = "" }
    end)

    local layer = gui.Panel {
        floating = true, interactable = false, width = "100%", height = "100%", flow = "none",
        halos.group, casings.group, marks.group, badges.group, labels.group,
    }

    -- The line being drawn and the bend handles follow the pointer, so they sit in a
    -- layer that does not slide and are placed against the current layout every time.
    local draftCasings = Pool(function() return Piece({ "regionMapPathPiece" }) end)
    local draftMarks = Pool(function() return Piece({ "regionMapPathPiece" }) end)
    local handles = Pool(function() return Piece({ "regionMapPathHandle" }) end)
    local pluses = Pool(function()
        return gui.Panel {
            classes = { "regionMapPathPlus" }, floating = true, halign = "center", valign = "center", interactable = false,
            gui.Panel { classes = { "regionMapPathPlusGlyph" }, bgimage = C.iconAdd, interactable = false },
        }
    end)
    local top = gui.Panel {
        floating = true, interactable = false, width = "100%", height = "100%", flow = "none",
        draftCasings.group, draftMarks.group, handles.group, pluses.group,
    }

    local drawn = {} --- @type RegionMapDrawnPath[]
    local signature = ""
    local ref = nil --- @type nil|RegionMapLayout the layout pieces were last placed against
    local refScale = 1
    local layerX, layerY = 0, 0
    local hoverId, selectedId, showNames = nil, nil, false
    local dirty = true
    local stretched = false -- scaled mid-zoom (Tools.Stretch) rather than placed
    -- The top layer: the draft line, whose handles show, and a handle drag in progress.
    local draft = nil --- @type nil|{points: {u: number, v: number}[], cursor: nil|{u: number, v: number}, look: RegionMapPathLook}
    local handlesId = nil --- @type nil|string
    local preview = nil --- @type nil|RegionMapBendPreview
    local handleSpots = {} --- @type {x: number, y: number, kind: "bend"|"plus", index: integer}[]
    local topLayout = nil --- @type nil|RegionMapLayout

    -- Pieces -----------------------------------------------------------------------------------------

    -- An engine style write costs far more than a Lua compare, and placing the pieces
    -- again after a zoom keeps most of their sizes, corners, colours and angles, so a
    -- piece's style is written only where it changed. Pieces are styled only through Set.
    local written = setmetatable({}, { __mode = "k" }) --- @type table<Panel, table<string, any>>
    local function Set(panel, key, value)
        local last = written[panel]
        if last == nil then
            last = {}
            written[panel] = last
        end
        if last[key] ~= value then
            last[key] = value
            panel.selfStyle[key] = value
        end
    end

    -- A rotated bar from (x1,y1) to (x2,y2), `thickness` across, with round ends.
    -- Placed against `at`, or the layout the sliding layer was last placed against.
    local function Bar(panel, x1, y1, x2, y2, thickness, at)
        local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local layout = (at or ref) --[[@as RegionMapLayout]]
        Set(panel, "width", math.max(thickness, length))
        Set(panel, "height", thickness)
        Set(panel, "cornerRadius", thickness / 2)
        -- As Tools.PlaceCentered: offsets from the canvas center.
        Set(panel, "x", (x1 + x2) / 2 - layout.viewWidth * 0.5)
        Set(panel, "y", (y1 + y2) / 2 - layout.viewHeight * 0.5)
        Set(panel, "rotate", length > 0 and -math.deg(math.atan(y2 - y1, x2 - x1)) or 0)
    end

    -- One mark with its casing under it; the casing reaches casingWidth past every edge.
    local function Mark(entry, x1, y1, x2, y2, thickness, casingAcross, offsetX, offsetY)
        local casing = C.pathCasing * refScale
        local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local ux, uy = 0, 0
        if length > 0 then ux, uy = (x2 - x1) / length * casing, (y2 - y1) / length * casing end
        if casingAcross ~= nil then
            local under = casings.Next()
            Bar(under, x1 - ux, y1 - uy, x2 + ux, y2 + uy, casingAcross + casing * 2)
            Set(under, "bgcolor", entry.look.casing)
        end
        local mark = marks.Next()
        Bar(mark, x1 + (offsetX or 0), y1 + (offsetY or 0), x2 + (offsetX or 0), y2 + (offsetY or 0), thickness)
        Set(mark, "bgcolor", entry.look.color)
        -- A hidden path fades its colour but keeps its casing at full strength (Q12).
        Set(mark, "opacity", entry.hidden and C.pathHiddenOpacity or 1)
    end

    -- Draws the visible part [t0, t1] of one segment in the path's pattern.
    local function DrawSegment(entry, ax, ay, bx, by, t0, t1)
        local scale = refScale
        local look = entry.look
        local thickness = look.width * scale
        local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        if length <= 0 then return end
        local function At(s) return ax + (bx - ax) * s / length, ay + (by - ay) * s / length end
        local from, to = t0 * length, t1 * length
        if look.pattern == "double" then
            local line, gap, across = DoubleLine(thickness, scale)
            local nx, ny = -(by - ay) / length, (bx - ax) / length
            local offset = (gap + line) / 2
            local x1, y1 = At(from)
            local x2, y2 = At(to)
            Mark(entry, x1, y1, x2, y2, line, across, nx * offset, ny * offset)
            Mark(entry, x1, y1, x2, y2, line, nil, -nx * offset, -ny * offset)
            return
        end
        local rhythm = Rhythm(look.pattern, thickness, scale)
        -- Solid, and any pattern once the piece budget runs out (F4), is one bar.
        local period = 0
        for _, item in ipairs(rhythm or {}) do period = period + item[1] end
        local estimate = period > 0 and (to - from) / period * 2 * #(rhythm or {}) or 2
        if rhythm == nil or period <= 0 or marks.used + casings.used + estimate > C.pathPieceLimit then
            local x1, y1 = At(from)
            local x2, y2 = At(to)
            Mark(entry, x1, y1, x2, y2, thickness, thickness)
            return
        end
        -- Marks sit at whole periods from the segment's start, so they stay put while the view pans.
        local start = math.floor(from / period) * period
        while start < to do
            local s = start
            for _, item in ipairs(rhythm) do
                local size, kind = item[1], item[2]
                if kind == "dot" then
                    local center = s + size / 2
                    if center >= from and center <= to then
                        local x, y = At(center)
                        Mark(entry, x, y, x, y, size, size)
                    end
                elseif kind == "dash" then
                    local a, b = math.max(s, from), math.min(s + size, to)
                    if b > a then
                        local x1, y1 = At(a)
                        local x2, y2 = At(b)
                        Mark(entry, x1, y1, x2, y2, thickness, thickness)
                    end
                end
                s = s + size
            end
            start = start + period
        end
    end

    -- Labels show for the hovered and selected path, or for all with Show names (F3, Q11).
    -- Not for the path whose bend handles show: a "+" sits where its label would.
    -- Show names declutters (Q11): longest lines first, a label shows only if its line is
    -- long enough on screen and it clears the pins, their names and the labels already
    -- placed, so zooming in brings more of them back. Hover and selection always show.
    local function PlaceLabels()
        labels.Begin()
        local layout = ref
        if layout ~= nil then
            local scale = refScale
            local fontSize = C.pathLabelSize * scale
            local gap = C.pathLabelGap * scale
            local taken = {} --- @type {x0: number, y0: number, x1: number, y1: number}[]
            local function Clear(box)
                for _, other in ipairs(taken) do
                    if box.x0 < other.x1 and other.x0 < box.x1 and box.y0 < other.y1 and other.y0 < box.y1 then return false end
                end
                return true
            end
            local function Box(x, y, width, height)
                return { x0 = x - width / 2 - gap, y0 = y - height / 2 - gap, x1 = x + width / 2 + gap, y1 = y + height / 2 + gap }
            end
            local function TextWidth(text, size, pad)
                return #text * size * C.pathLabelCharWidth + pad * 2
            end

            local candidates = {} --- @type {entry: RegionMapDrawnPath, x: number, y: number, length: number, forced: boolean}[]
            local pins = {} --- @type table<string, boolean>
            for _, entry in ipairs(drawn) do
                -- Each end is a pin: keep its disc and the name under it clear.
                for _, at in ipairs({ { entry.points[1], entry.aName }, { entry.points[#entry.points], entry.bName } }) do
                    local key = at[1].u .. "," .. at[1].v
                    if not pins[key] then
                        pins[key] = true
                        local px, py = Tools.ImageToPanel(layout, at[1].u, at[1].v)
                        local disc = C.pinDisc.normal * scale
                        local nameSize = C.pinNameSize.normal * scale
                        taken[#taken + 1] = Box(px, py, disc, disc)
                        taken[#taken + 1] = Box(px, py + disc / 2 + nameSize * 0.75, TextWidth(at[2], nameSize, 0), nameSize * 1.5)
                    end
                end
                local forced = entry.id == hoverId or entry.id == selectedId
                if (showNames or forced) and entry.id ~= handlesId then
                    -- At the middle of the longest segment on screen.
                    local best, bestLength, bx, by = -1, -1, 0, 0
                    for i = 1, #entry.points - 1 do
                        local x1, y1 = Tools.ImageToPanel(layout, entry.points[i].u, entry.points[i].v)
                        local x2, y2 = Tools.ImageToPanel(layout, entry.points[i + 1].u, entry.points[i + 1].v)
                        local length = (x2 - x1) ^ 2 + (y2 - y1) ^ 2
                        if length > bestLength then best, bestLength, bx, by = i, length, (x1 + x2) / 2, (y1 + y2) / 2 end
                    end
                    if best > 0 then
                        candidates[#candidates + 1] = { entry = entry, x = bx, y = by, length = math.sqrt(bestLength), forced = forced }
                    end
                end
            end
            table.sort(candidates, function(a, b)
                if a.forced ~= b.forced then return a.forced end
                return a.length > b.length
            end)

            for _, item in ipairs(candidates) do
                local width = TextWidth(item.entry.label, fontSize, C.pathLabelPad * scale)
                local box = Box(item.x, item.y, width, fontSize * 1.5)
                if item.forced or (item.length >= width * C.pathLabelFit and Clear(box)) then
                    taken[#taken + 1] = box
                    local label = labels.Next()
                    if label.text ~= item.entry.label then label.text = item.entry.label end
                    label.selfStyle.fontSize = fontSize
                    Tools.PlaceCentered(label, layout, item.x, item.y)
                end
            end
        end
        labels.Finish()
    end

    -- The area pieces are placed in: on screen and half a view around it.
    local function PlaceBounds(layout)
        local marginX, marginY = layout.viewWidth / 2 + 40, layout.viewHeight / 2 + 40
        return -marginX, -marginY, layout.viewWidth + marginX, layout.viewHeight + marginY
    end

    -- The selected path's halo has its own pool, so selecting a path redraws only the halo.
    local function PlaceHalos()
        halos.Begin()
        local layout = ref
        if layout ~= nil and selectedId ~= nil then
            local scale = refScale
            local x0, y0, x1, y1 = PlaceBounds(layout)
            for _, entry in ipairs(drawn) do
                if entry.id == selectedId then
                    local across = Across(entry.look, scale)
                    for i = 1, #entry.points - 1 do
                        local ax, ay = Tools.ImageToPanel(layout, entry.points[i].u, entry.points[i].v)
                        local bx, by = Tools.ImageToPanel(layout, entry.points[i + 1].u, entry.points[i + 1].v)
                        local t0, t1 = ClipSegment(ax, ay, bx, by, x0, y0, x1, y1)
                        if t0 ~= nil and t1 ~= nil then
                            Bar(halos.Next(), ax + (bx - ax) * t0, ay + (by - ay) * t0, ax + (bx - ax) * t1,
                                ay + (by - ay) * t1, across + (C.pathCasing + C.pathHalo) * scale * 2)
                        end
                    end
                end
            end
        end
        halos.Finish()
    end

    -- Places every piece against layout; pieces lie on screen and half a view around it.
    local function Place(layout)
        ref = layout
        casings.Begin()
        marks.Begin()
        badges.Begin()
        local scale = refScale
        local x0, y0, x1, y1 = PlaceBounds(layout)
        for _, entry in ipairs(drawn) do
            for i = 1, #entry.points - 1 do
                local ax, ay = Tools.ImageToPanel(layout, entry.points[i].u, entry.points[i].v)
                local bx, by = Tools.ImageToPanel(layout, entry.points[i + 1].u, entry.points[i + 1].v)
                local t0, t1 = ClipSegment(ax, ay, bx, by, x0, y0, x1, y1)
                if t0 ~= nil and t1 ~= nil then
                    DrawSegment(entry, ax, ay, bx, by, t0, t1)
                    -- The eye-slash repeats on every segment of a hidden path (Q12).
                    if entry.hidden and t0 <= 0.5 and t1 >= 0.5 then
                        local badge = badges.Next()
                        local size = C.pathBadgeSize * scale
                        badge.selfStyle.width, badge.selfStyle.height = size, size
                        badge.selfStyle.cornerRadius = size / 2
                        Tools.PlaceCentered(badge, layout, (ax + bx) / 2, (ay + by) / 2)
                    end
                end
            end
        end
        casings.Finish()
        marks.Finish()
        badges.Finish()
        PlaceHalos()
        PlaceLabels()
        layerX, layerY = 0, 0
        layer.selfStyle.x, layer.selfStyle.y = 0, 0
        dirty = false
    end

    -- API ----------------------------------------------------------------------------------------------

    local inputs = "" -- what the last Bind was built from
    local function Bind(mapId)
        local parts = { tostring(Model.IsDirector()), Paths.TimeUnit() }
        for _, item in ipairs(Paths.Types()) do
            parts[#parts + 1] = table.concat({ item.id, item.name, item.pattern, item.color, item.width }, "|")
        end
        -- Every refresh binds, and building the lines costs several ms on a full map;
        -- the paths and the pins they join only change with the data revision.
        local now = table.concat(parts, ",") .. "#" .. tostring(mapId) .. "#" .. tostring(Model.Revision())
        if now == inputs then return end
        inputs = now
        local list = {} --- @type RegionMapDrawnPath[]
        if mapId ~= nil then
            for _, path in ipairs(Paths.Paths(mapId)) do
                local a, b = Paths.Ends(path)
                if a ~= nil and b ~= nil then
                    local points = { { u = a.u, v = a.v } }
                    for _, bend in ipairs(path.bends) do points[#points + 1] = { u = bend.u, v = bend.v } end
                    points[#points + 1] = { u = b.u, v = b.v }
                    local hidden = path.visibility == "hidden"
                    list[#list + 1] = {
                        id = path.id, look = RegionMapPathLayer.LookOf(path), hidden = hidden,
                        points = points, label = Paths.Label(path),
                        aName = Model.DisplayName(a), bName = Model.DisplayName(b),
                    }
                    parts[#parts + 1] = table.concat({
                        path.id, tostring(path.revision), a.u, a.v, b.u, b.v, a.name, b.name,
                    }, "|")
                end
            end
        end
        drawn = list
        local key = table.concat(parts, ",")
        if key ~= signature then
            signature = key
            dirty = true
        end
    end

    local function Layout(layout, scale, moving)
        if layout == nil then
            ref = nil
            for _, pool in ipairs({ halos, casings, marks, badges, labels }) do
                pool.Begin()
                pool.Finish()
            end
            return
        end
        local last = ref
        -- Mid-zoom the pieces placed last stretch with the map; placing them all again
        -- costs tens of ms on a full map, every frame of the zoom.
        if moving and not dirty and last ~= nil and scale == refScale and last.viewWidth == layout.viewWidth
            and last.viewHeight == layout.viewHeight and (last.width ~= layout.width or stretched)
            and Tools.Stretch(layer, last, layout) then
            stretched = true
            layerX, layerY = -math.huge, -math.huge
            return
        end
        if stretched then
            stretched = false
            layer.selfStyle.scale = 1
        end
        if dirty or last == nil or scale ~= refScale or last.width ~= layout.width or last.height ~= layout.height
            or last.viewWidth ~= layout.viewWidth or last.viewHeight ~= layout.viewHeight
            or math.abs(layout.x - last.x) > layout.viewWidth / 2 or math.abs(layout.y - last.y) > layout.viewHeight / 2 then
            refScale = scale
            Place(layout)
            return
        end
        local x, y = layout.x - last.x, layout.y - last.y
        if x ~= layerX or y ~= layerY then
            layerX, layerY = x, y
            layer.selfStyle.x, layer.selfStyle.y = x, y
        end
    end

    local function SetFocus(hover, selected, names)
        if selected ~= selectedId then
            hoverId, selectedId, showNames = hover, selected, names
            if ref ~= nil and not dirty then
                PlaceHalos()
                PlaceLabels()
            end
            return
        end
        if hover ~= hoverId or names ~= showNames then
            hoverId, showNames = hover, names
            if ref ~= nil and not dirty then PlaceLabels() end
        end
    end

    -- The nearest drawn path within its hit band of (x, y): at least 24 px wide (Q4).
    local function PathAt(layout, x, y, scale)
        local bestId, bestDistance = nil, math.huge
        for _, entry in ipairs(drawn) do
            local band = math.max(C.pinHitMin * scale / 2, Across(entry.look, scale) / 2 + 4)
            for i = 1, #entry.points - 1 do
                local ax, ay = Tools.ImageToPanel(layout, entry.points[i].u, entry.points[i].v)
                local bx, by = Tools.ImageToPanel(layout, entry.points[i + 1].u, entry.points[i + 1].v)
                local distance = DistanceToSegment(x, y, ax, ay, bx, by)
                if distance <= band and distance < bestDistance then bestId, bestDistance = entry.id, distance end
            end
        end
        return bestId
    end

    -- Draft line and bend handles ------------------------------------------------------------------------

    -- A solid line through points (canvas px) in a look, with its casing; patterns are
    -- left out because the line moves with the pointer every frame.
    local function DraftLine(points, look, scale, layout)
        local thickness = look.width * scale
        local casing = C.pathCasing * scale
        for i = 1, #points - 1 do
            local a, b = points[i], points[i + 1]
            local under = draftCasings.Next()
            Bar(under, a.x, a.y, b.x, b.y, thickness + casing * 2, layout)
            Set(under, "bgcolor", look.casing)
            local mark = draftMarks.Next()
            Bar(mark, a.x, a.y, b.x, b.y, thickness, layout)
            Set(mark, "bgcolor", look.color)
            -- The last stretch follows the pointer and is not placed yet, so it reads lighter.
            Set(mark, "opacity", b.loose and 0.6 or 1)
        end
    end

    local function Spot(panel, layout, x, y, size)
        panel.selfStyle.width, panel.selfStyle.height = size, size
        panel.selfStyle.cornerRadius = size / 2
        Tools.PlaceCentered(panel, layout, x, y)
    end

    -- Places the draft and the handles of the selected path against the current layout.
    local function PlaceTop(layout)
        topLayout = layout
        draftCasings.Begin()
        draftMarks.Begin()
        handles.Begin()
        pluses.Begin()
        handleSpots = {}
        if layout ~= nil then
            local scale = refScale
            local function At(point) return Tools.ImageToPanel(layout, point.u, point.v) end
            if draft ~= nil then
                local points = {}
                for _, point in ipairs(draft.points) do
                    local x, y = At(point)
                    points[#points + 1] = { x = x, y = y }
                end
                if draft.cursor ~= nil then
                    local x, y = At(draft.cursor)
                    points[#points + 1] = { x = x, y = y, loose = true }
                end
                DraftLine(points, draft.look, scale, layout)
                for i = 2, #draft.points do
                    local x, y = At(draft.points[i])
                    Spot(handles.Next(), layout, x, y, C.pathHandleSize * scale)
                end
            end
            local entry = nil
            for _, item in ipairs(drawn) do
                if item.id == handlesId then entry = item end
            end
            if entry ~= nil then
                -- A handle drag shows the line it will make; the stored line stays under it.
                local points = {}
                for _, point in ipairs(entry.points) do points[#points + 1] = { u = point.u, v = point.v } end
                if preview ~= nil then
                    if preview.insert then
                        table.insert(points, preview.index + 1, { u = preview.u, v = preview.v })
                    else
                        points[preview.index + 1] = { u = preview.u, v = preview.v }
                    end
                    local line = {}
                    for _, point in ipairs(points) do
                        local x, y = At(point)
                        line[#line + 1] = { x = x, y = y }
                    end
                    DraftLine(line, entry.look, scale, layout)
                end
                for i = 2, #points - 1 do
                    local x, y = At(points[i])
                    Spot(handles.Next(), layout, x, y, C.pathHandleSize * scale)
                    handleSpots[#handleSpots + 1] = { x = x, y = y, kind = "bend", index = i - 1 }
                end
                -- No "+" while dragging, or once the path holds all the bends it can.
                if preview == nil and #points - 2 < C.pathBendLimit then
                    for i = 1, #points - 1 do
                        local ax, ay = At(points[i])
                        local bx, by = At(points[i + 1])
                        local x, y = (ax + bx) / 2, (ay + by) / 2
                        local plus = pluses.Next()
                        Spot(plus, layout, x, y, C.pathPlusSize * scale)
                        handleSpots[#handleSpots + 1] = { x = x, y = y, kind = "plus", index = i }
                    end
                end
            end
        end
        draftCasings.Finish()
        draftMarks.Finish()
        handles.Finish()
        pluses.Finish()
    end

    local function SetDraft(points, cursor, look)
        if points == nil or #points == 0 or look == nil then
            if draft == nil then return end
            draft = nil
        else
            draft = { points = points, cursor = cursor, look = look }
        end
        PlaceTop(topLayout)
    end

    local function SetHandles(pathId, bendPreview)
        if pathId == handlesId and bendPreview == nil and preview == nil then return end
        local changed = pathId ~= handlesId
        handlesId, preview = pathId, bendPreview
        PlaceTop(topLayout)
        if changed then PlaceLabels() end
    end

    -- The handle under (x, y) within its hit area, nearest first: a bend or a "+".
    local function HandleAt(x, y, scale)
        local best, bestDistance = nil, C.pathHandleHit * scale / 2
        for _, spot in ipairs(handleSpots) do
            local distance = math.sqrt((spot.x - x) ^ 2 + (spot.y - y) ^ 2)
            if distance <= bestDistance then best, bestDistance = spot, distance end
        end
        if best == nil then return nil end
        return { kind = best.kind, index = best.index }
    end

    -- The stored points of the path whose handles show: a, its bends, b.
    local function HandlePoints()
        for _, item in ipairs(drawn) do
            if item.id == handlesId then return item.points end
        end
        return nil
    end

    return {
        layer = layer,
        top = top,
        Bind = function(mapId) if not mod.unloaded then Bind(mapId) end end,
        Layout = function(layout, scale, moving)
            Layout(layout, scale, moving == true)
            PlaceTop(layout)
        end,
        SetFocus = SetFocus,
        PathAt = PathAt,
        SetDraft = SetDraft,
        SetHandles = SetHandles,
        HandleAt = HandleAt,
        HandlePoints = HandlePoints,
    }
end

--- A short sample of a type's line for lists and chips (Settings, the path
--- panel): casing and marks in a panel `width` x 12 px.
--- @param width number
--- @return Panel sample with data.set(look) to redraw it
function RegionMapPathLayer.Sample(width)
    local height = 12
    local pieces = {} --- @type Panel[]
    local panel = gui.Panel {
        classes = { "regionMapPathSample" }, width = width, height = height, flow = "none", interactable = false,
        data = {},
    }
    local function Piece(index)
        local piece = pieces[index]
        if piece == nil then
            piece = gui.Panel { classes = { "regionMapPathPiece" }, floating = true, halign = "left", valign = "top", interactable = false }
            pieces[index] = piece
            panel.children = pieces
        end
        piece:SetClass("collapsed", false)
        return piece
    end
    -- Horizontal pieces only, so plain x/y place them.
    local function Bar(index, x1, x2, y, thickness, color, opacity)
        local piece = Piece(index)
        piece.selfStyle.x, piece.selfStyle.y = x1, y - thickness / 2
        piece.selfStyle.width, piece.selfStyle.height = math.max(thickness, x2 - x1), thickness
        piece.selfStyle.cornerRadius = thickness / 2
        piece.selfStyle.bgcolor = color
        piece.selfStyle.opacity = opacity or 1
    end
    local shown = nil --- @type nil|string the look last drawn
    panel.data.set = function(look)
        -- Every bind of the lists that show samples calls this; redraw only a new look.
        local key = table.concat({ look.pattern, look.color, look.casing, tostring(look.width) }, "|")
        if key == shown then return end
        shown = key
        local count = 0
        local function Add(x1, x2, y, thickness, color)
            count = count + 1
            Bar(count, x1, x2, y, thickness, color)
        end
        local mid = height / 2
        local thickness = look.width
        local casing = C.pathCasing
        local left, right = 2, width - 2
        if look.pattern == "double" then
            local line, gap, across = DoubleLine(thickness, 1)
            Add(left - casing, right + casing, mid, across + casing * 2, look.casing)
            Add(left, right, mid - (gap + line) / 2, line, look.color)
            Add(left, right, mid + (gap + line) / 2, line, look.color)
        else
            local rhythm = Rhythm(look.pattern, thickness, 1)
            if rhythm == nil then
                Add(left - casing, right + casing, mid, thickness + casing * 2, look.casing)
                Add(left, right, mid, thickness, look.color)
            else
                local s = left
                local index = 1
                while s < right do
                    local item = rhythm[index]
                    local size, kind = item[1], item[2]
                    if kind ~= nil then
                        local across = kind == "dot" and size or thickness
                        local e = math.min(s + size, right)
                        Add(s - casing, e + casing, mid, across + casing * 2, look.casing)
                        Add(s, e, mid, across, look.color)
                    end
                    s = s + size
                    index = index % #rhythm + 1
                end
            end
        end
        for i = count + 1, #pieces do pieces[i]:SetClass("collapsed", true) end
    end
    return panel
end
