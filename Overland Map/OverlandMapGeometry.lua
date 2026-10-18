local mod = dmhub.GetModLoading()

--- @class OverlandMapGeometry: GameType
--- @field new fun(o?: table): OverlandMapGeometry
OverlandMapGeometry = RegisterGameType("OverlandMapGeometry")
local C = OverlandMapConstants
local R = OverlandMapRecords
local Clamp, IsFinite = R.Clamp, R.IsFinite

--- Where the image sits inside the canvas, in canvas pixels.
--- @class OverlandMapLayout
--- @field x number
--- @field y number
--- @field width number
--- @field height number
--- @field viewWidth number
--- @field viewHeight number

--- The fade depth for an image drawn width x height on screen: a share of its
--- shorter side, capped so a zoomed-in map keeps a narrow edge.
--- @param width number
--- @param height number
--- @return number
function OverlandMapGeometry.FadeBand(width, height)
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
--- @param camera OverlandMapCamera
--- @param rightInset nil|number
--- @return nil|OverlandMapLayout
function OverlandMapGeometry.CalculateImageLayout(viewWidth, viewHeight, imageWidth, imageHeight, camera, rightInset)
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
    if camera.allowEdgeFocus then
        centerX, centerY = Clamp(centerX, 0, 1), Clamp(centerY, 0, 1)
    else
        centerX = Clamp(centerX, (viewWidth / 2 - maxX) / width, (viewWidth / 2 - minX) / width)
        if height <= viewHeight then
            centerY = 0.5
        else
            local halfVisible = viewHeight / (2 * height)
            centerY = Clamp(centerY, halfVisible, 1 - halfVisible)
        end
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

--- @param layout OverlandMapLayout
--- @param u number
--- @param v number
--- @return number x, number y
function OverlandMapGeometry.ImageToPanel(layout, u, v)
    return layout.x + u * layout.width, layout.y + v * layout.height
end

--- @param layout OverlandMapLayout
--- @param x number
--- @param y number
--- @return nil|number u, nil|number v nil when the point is off the image (letterbox)
function OverlandMapGeometry.PanelToImage(layout, x, y)
    local u = (x - layout.x) / layout.width
    local v = (y - layout.y) / layout.height
    if u < 0 or u > 1 or v < 0 or v > 1 then
        return nil, nil
    end
    return u, v
end

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
function OverlandMapGeometry.ClipSegment(ax, ay, bx, by, x0, y0, x1, y1)
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
local ClipSegment = OverlandMapGeometry.ClipSegment

--- Distance per image width; using height/width makes diagonal calibration true on rectangular maps.
function OverlandMapGeometry.Calibration(map, width, height)
    local scale = R.Field(map, "scale", nil)
    if scale == nil or not R.ValidScale(scale) or not R.IsFinite(width) or not R.IsFinite(height)
        or width <= 0 or height <= 0 then return nil end
    local dx, dy = scale.u2 - scale.u1, (scale.v2 - scale.v1) * height / width
    local fraction = math.sqrt(dx * dx + dy * dy)
    local units = scale.distance / fraction
    if not R.IsFinite(units) or units <= 0 or fraction <= 0 then return nil end
    return units, scale.unit
end

function OverlandMapGeometry.InitialDistance(map, width, height)
    local units = OverlandMapGeometry.Calibration(map, width, height)
    if units == nil then return nil end
    local maximum = units * 0.2
    if not R.IsFinite(maximum) or maximum <= 0 then return nil end
    local power = 10 ^ math.floor(math.log(maximum, 10))
    for _, factor in ipairs({ 5, 2, 1 }) do
        local value = factor * power
        if value <= maximum and value > 0 then return value end
    end
    return nil
end

function OverlandMapGeometry.ScaleWidth(map, aid, width, height)
    local units, unit = OverlandMapGeometry.Calibration(map, width, height)
    if units == nil then return nil, "aids.calibrate" end
    if not R.IsFinite(aid.distance) or aid.distance <= 0 then return nil, "aids.invalidDistance" end
    local fraction = aid.distance / units
    if not R.IsFinite(fraction) or fraction <= 0 or fraction > 1 then return nil, "aids.tooLong" end
    return fraction, nil, unit
end

--- The label is separated from the rotated original top edge by its measured, upright bounds.
function OverlandMapGeometry.NorthAnchor(height, angle, textWidth, textHeight, gap)
    local a = math.rad(angle)
    local nx, ny = math.sin(a), -math.cos(a)
    local clearance = math.abs(nx) * textWidth / 2 + math.abs(ny) * textHeight / 2 + gap
    return nx * (height / 2 + clearance), ny * (height / 2 + clearance)
end

--- Only label rows move. Every tick stays at its measured endpoint or midpoint.
function OverlandMapGeometry.ScaleLabels(length, sizes, gap)
    local rows, result, heights = {}, {}, {}
    for i, size in ipairs(sizes) do
        local x, row = (i - 2) * length / 2, 1
        while true do
            local clear = true
            for _, other in ipairs(rows[row] or {}) do
                if x - size.width / 2 < other.right + gap and x + size.width / 2 > other.left - gap then clear = false; break end
            end
            if clear then break end
            row = row + 1
        end
        rows[row] = rows[row] or {}
        rows[row][#rows[row] + 1] = { left = x - size.width / 2, right = x + size.width / 2 }
        heights[row] = math.max(heights[row] or 0, size.height)
        result[i] = { x = x, row = row, width = size.width, height = size.height }
    end
    for _, label in ipairs(result) do
        local y = gap
        for row = 1, label.row - 1 do y = y + heights[row] + gap end
        label.y, label.top = y + label.height / 2, y
    end
    return result
end

--- Break a long tick where it would cross an earlier label's measured bounds.
function OverlandMapGeometry.TickSegments(label, labels, gap)
    local spans = { { first = 0, last = label.top } }
    for _, other in ipairs(labels) do
        if other.row < label.row and math.abs(label.x - other.x) <= other.width / 2 + gap then
            local first, last = other.top - gap / 2, other.top + other.height + gap / 2
            local nextSpans = {}
            for _, span in ipairs(spans) do
                if last <= span.first or first >= span.last then nextSpans[#nextSpans + 1] = span
                else
                    if first > span.first then nextSpans[#nextSpans + 1] = { first = span.first, last = first } end
                    if last < span.last then nextSpans[#nextSpans + 1] = { first = last, last = span.last } end
                end
            end
            spans = nextSpans
        end
    end
    return spans
end

--- Move the camera just enough to expose editing controls, without changing the aid's anchor.
function OverlandMapGeometry.RevealOffset(bounds, area)
    local function Offset(first, last, low, high)
        if last - first > high - low then return (low + high - first - last) / 2 end
        if first < low then return low - first end
        if last > high then return high - last end
        return 0
    end
    return Offset(bounds.x1, bounds.x2, area.x1, area.x2), Offset(bounds.y1, bounds.y2, area.y1, area.y2)
end
