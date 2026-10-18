local mod = dmhub.GetModLoading()

--- @class OverlandMapDrawing: GameType
--- @field new fun(o?: table): OverlandMapDrawing
OverlandMapDrawing = RegisterGameType("OverlandMapDrawing")
local C = OverlandMapConstants
local R = OverlandMapRecords
local Clamp, IsFinite = R.Clamp, R.IsFinite

local Session = OverlandMapControls

-- Overlay: the drawn route and the ruler --------------------------------------------------------

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
function OverlandMapDrawing.PositionPanel(panel, x, y)
    panel.x, panel.y = x, y
    placedX[panel], placedY[panel] = x, y
end
local PositionPanel = OverlandMapDrawing.PositionPanel

--- Puts a center-aligned panel's middle at canvas point (x, y). The engine's
--- pivot does not move a panel, so offsets are measured from the canvas center.
--- @param panel Panel
--- @param layout OverlandMapLayout
--- @param x number
--- @param y number
function OverlandMapDrawing.PlaceCentered(panel, layout, x, y)
    PositionPanel(panel, x - layout.viewWidth * 0.5, y - layout.viewHeight * 0.5)
end
local PlaceCentered = OverlandMapDrawing.PlaceCentered

--- While a zoom is in motion (a camera ease or a burst of wheel notches), the
--- pieces of a layer placed against `ref` are moved to where `layout` shows those
--- points, keeping their size, instead of being placed again each frame; the
--- caller places them for real once the zoom settles. Pieces move through
--- panel.x/y: scaling the layer is a style write, ~100 ms a frame on the map.
--- Returns false, changing nothing, when the view has left the area placed
--- around ref (on screen and half a view around it), so the caller places again.
--- @param panel Panel a floating layer the size of the canvas, holding the pools
--- @param pools {items: Panel[], used: integer}[] the pools whose pieces were placed against ref
--- @param ref OverlandMapLayout the layout its pieces were placed against
--- @param layout OverlandMapLayout the current layout
--- @return boolean
function OverlandMapDrawing.Stretch(panel, pools, ref, layout)
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
local Stretch = OverlandMapDrawing.Stretch

--- A pool of panels in one z-layer, reused by index. Each pass calls Begin,
--- then Next once for every panel it needs, then Finish. Panels past the count
--- in use are collapsed, never destroyed, so a dense map reuses them on every
--- zoom, and the layer's children are set once per pass, only after it grew.
--- @param make fun(): Panel builds one new panel
--- @param group nil|Panel the layer to fill; nil makes a full-size one (pool.group)
function OverlandMapDrawing.Pool(make, group)
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

--- @class OverlandMapRunPool
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
--- @return OverlandMapRunPool
function OverlandMapDrawing.RunPool(make)
    local group = gui.Panel { floating = true, interactable = false, width = "100%", height = "100%", flow = "none" }
    ---@diagnostic disable-next-line: missing-fields
    local pool = { group = group, items = {}, used = 0 } --- @type OverlandMapRunPool
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
