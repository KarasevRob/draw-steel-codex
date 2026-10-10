local mod = dmhub.GetModLoading()

--- Making and reshaping point crawl paths (V21-11, V21-12, V21-14): the Path
--- tool's steps, Connect to..., Redraw line and the bend handle edits. The
--- canvas reports clicks, right-clicks and Backspace here; the line being drawn
--- lives in ctx.data.pathDraft and the path layer draws it.
---
--- Path tool: click the start pin, click the map for bends, click the end pin.
--- The path is made with the last type and time (Q8) and opens in the edit
--- form, and the tool stays on for the next one.
--- @class RegionMapPathTool: GameType
--- @field new fun(o?: table): RegionMapPathTool
RegionMapPathTool = RegisterGameType("RegionMapPathTool")
local C = RegionMapConstants
local Model = RegionMapModel
local Paths = RegionMapPaths
local Session = RegionMapSession
local Undo = RegionMapUndo

local function T(id, args) return RegionMapCopy.T(id, args) end

--- The line being drawn on the open map, or nil.
--- @param ctx RegionMapContext
--- @return nil|RegionMapPathDraft
function RegionMapPathTool.Draft(ctx)
    local data = ctx.data
    local draft = data.pathDraft
    if draft == nil or (data.tool ~= "path" and data.tool ~= "redraw") or draft.mapId ~= data.mapId then return nil end
    return draft
end
local Draft = RegionMapPathTool.Draft

-- A new row can answer success a moment before this client's index has it
-- (see the P3 build notes), so wait for it before opening it.
local function WhenReadable(ctx, id, action, attempt)
    attempt = attempt or 1
    if not ctx.IsAlive() then return end
    if Paths.Get(id) ~= nil then
        action()
    elseif attempt < C.busyRetries then
        dmhub.Schedule(C.busyRetryDelay, function() WhenReadable(ctx, id, action, attempt + 1) end)
    end
end

-- Q9: a second path between the same two pins gets one bend bowed to the side,
-- alternating sides and further out for each path already there.
local function OffsetBend(a, b, existing)
    local du, dv = b.u - a.u, b.v - a.v
    local length = math.sqrt(du * du + dv * dv)
    if length <= 0 then return nil end
    local side = existing % 2 == 1 and 1 or -1
    local offset = C.pathParallelOffset * length * math.ceil(existing / 2) * side
    return {
        u = Model.Clamp((a.u + b.u) / 2 - dv / length * offset, 0, 1),
        v = Model.Clamp((a.v + b.v) / 2 + du / length * offset, 0, 1),
    }
end

--- Make a path from a to b on the open map with the last type and time (Q8),
--- then open it in the edit form. The Path tool and Connect to... both end here.
--- @param ctx RegionMapContext
--- @param aId string
--- @param bId string
--- @param bends nil|RegionMapBend[]
--- @return boolean ok
function RegionMapPathTool.Connect(ctx, aId, bId, bends)
    local map = ctx.CurrentMap()
    local a, b = Model.GetLocation(aId), Model.GetLocation(bId)
    if map == nil or a == nil or b == nil then return false end
    bends = bends or {}
    if #bends == 0 then
        local existing = Paths.CountJoining(aId, bId)
        local bend = existing > 0 and OffsetBend(a, b, existing) or nil
        if bend ~= nil then bends = { bend } end
    end
    local style = Session.LastPathStyle()
    local newId = nil
    local ok, reason, entry, id = Paths.CreatePath(map.id, aId, bId, {
        typeId = style.typeId, time = style.time, backTime = style.time, bends = bends,
    }, {
        success = function()
            if newId == nil then return end
            local created = newId
            WhenReadable(ctx, created, function() ctx.SelectPath(created, "pathEdit") end)
        end,
        failure = function() ctx.Report(false, "unavailable") end,
    })
    newId = id
    -- The edit form opening is the sign it worked; "Undo last change" can still take it back.
    if ctx.Report(ok, reason) then Undo.Remember(entry) end
    return ok
end

-- Redraw line ends at the path's b end: its bends are replaced, every other field kept (Q6).
local function FinishRedraw(ctx, draft)
    local path = Paths.Get(draft.pathId)
    ctx.data.pathDraft = nil
    ctx.SetTool("none")
    if path == nil then return end
    local ok, reason, entry = Paths.UpdatePath(path.id, { bends = draft.bends }, "Redraw region map path")
    if ctx.Report(ok, reason) then ctx.Push(entry, "toast.moved", { name = Paths.Title(path, true) }) end
    ctx.SelectPath(path.id)
end

--- A click while the Path tool or Redraw line is on: a pin (pinId, from a pin's
--- own click or within the snap radius of one) or a point of the map (u, v).
--- @param ctx RegionMapContext
--- @param u nil|number
--- @param v nil|number
--- @param pinId nil|string
function RegionMapPathTool.Click(ctx, u, v, pinId)
    local data = ctx.data
    local map = ctx.CurrentMap()
    if map == nil then return end
    local draft = Draft(ctx)
    if draft == nil then
        -- Only the Path tool starts a line; it starts at a pin.
        if data.tool == "path" and pinId ~= nil then
            data.pathDraft = { mapId = map.id, startId = pinId, bends = {} }
            ctx.RefreshAll()
        end
        return
    end
    if pinId ~= nil then
        -- The start pin is no end; Redraw line ends only at the path's own b end.
        if pinId == draft.startId then return end
        if draft.pathId ~= nil then
            if pinId == draft.endId then FinishRedraw(ctx, draft) end
            return
        end
        local startId, bends = draft.startId, draft.bends
        data.pathDraft = nil
        if startId ~= nil then RegionMapPathTool.Connect(ctx, startId, pinId, bends) end
        ctx.RefreshAll()
        return
    end
    if u == nil or v == nil or #draft.bends >= C.pathBendLimit then return end
    draft.bends[#draft.bends + 1] = { u = u, v = v }
end

--- Right-click or Backspace: drop the last bend. True when one was dropped.
--- @param ctx RegionMapContext
--- @return boolean
function RegionMapPathTool.Back(ctx)
    local draft = Draft(ctx)
    if draft == nil or #draft.bends == 0 then return false end
    table.remove(draft.bends)
    return true
end

--- Esc with the Path tool on: the first cancels the line being drawn and keeps
--- the tool; the shell turns the tool off on the next (Q7). True when handled.
--- @param ctx RegionMapContext
--- @return boolean
function RegionMapPathTool.Escape(ctx)
    if ctx.data.tool ~= "path" or Draft(ctx) == nil then return false end
    ctx.data.pathDraft = nil
    ctx.RefreshAll()
    return true
end

--- The banner line for the Path tool or Redraw line, or nil.
--- @param ctx RegionMapContext
--- @return nil|string
function RegionMapPathTool.Hint(ctx)
    local data = ctx.data
    if data.tool == "path" then return T(Draft(ctx) ~= nil and "hint.path.next" or "hint.path.start") end
    if data.tool ~= "redraw" then return nil end
    local draft = Draft(ctx)
    local path = Paths.Get(data.toolTargetId)
    if draft == nil or path == nil then return nil end
    local b = Model.GetLocation(draft.endId)
    return T("hint.redraw", { path = Paths.Title(path, true), name = b ~= nil and Model.DisplayName(b) or "" })
end

--- The points to draw for the line being drawn: the start pin and its bends.
--- @param ctx RegionMapContext
--- @return nil|{u: number, v: number}[]
--- @return nil|RegionMapPathLook look the line will have
function RegionMapPathTool.DraftPoints(ctx)
    local draft = Draft(ctx)
    local start = draft ~= nil and Model.GetLocation(draft.startId) or nil
    if draft == nil or start == nil then return nil, nil end
    local points = { { u = start.u, v = start.v } }
    for _, bend in ipairs(draft.bends) do points[#points + 1] = { u = bend.u, v = bend.v } end
    local look
    local path = draft.pathId ~= nil and Paths.Get(draft.pathId) or nil
    if path ~= nil then
        look = RegionMapPathLayer.LookOf(path)
    else
        look = RegionMapPathLayer.LookOfType(Paths.TypeById(Session.LastPathStyle().typeId))
    end
    return points, look
end

--- Redraw line (Q6): the Path tool's second step for one path, from its a end.
--- @param ctx RegionMapContext
--- @param pathId string
function RegionMapPathTool.StartRedraw(ctx, pathId)
    local path = Paths.Get(pathId)
    local map = ctx.CurrentMap()
    if path == nil or map == nil or path.mapId ~= map.id or mod.unloaded then return end
    ctx.SetTool("redraw", path.id)
    if ctx.data.tool ~= "redraw" then return end
    ctx.data.pathDraft = { mapId = map.id, startId = path.aId, endId = path.bId, pathId = path.id, bends = {} }
    ctx.RefreshAll()
end

-- Bend handles (Q5) ---------------------------------------------------------------------------------

local function WriteBends(ctx, path, bends)
    local ok, reason, entry = Paths.UpdatePath(path.id, { bends = bends }, "Edit region map path bends")
    if ctx.Report(ok, reason) then ctx.Push(entry, "toast.moved", { name = Paths.Title(path, true) }) end
    ctx.RefreshAll()
end

local function CopyBends(path)
    local bends = {} --- @type RegionMapBend[]
    for _, bend in ipairs(path.bends) do bends[#bends + 1] = { u = bend.u, v = bend.v } end
    return bends
end

--- Drop a bend handle: bend `index` moves to (u, v), or with insert a new bend
--- goes in at `index` (dragged from the "+" of segment `index`).
--- @param ctx RegionMapContext
--- @param pathId string
--- @param index integer
--- @param insert boolean
--- @param u number
--- @param v number
function RegionMapPathTool.DropBend(ctx, pathId, index, insert, u, v)
    local path = Paths.Get(pathId)
    if path == nil then return end
    local bends = CopyBends(path)
    local point = { u = Model.Clamp(u, 0, 1), v = Model.Clamp(v, 0, 1) }
    if insert then
        if #bends >= C.pathBendLimit or index < 1 or index > #bends + 1 then return end
        table.insert(bends, index, point)
    else
        if bends[index] == nil then return end
        bends[index] = point
    end
    WriteBends(ctx, path, bends)
end

--- Right-click on a bend handle removes that bend.
--- @param ctx RegionMapContext
--- @param pathId string
--- @param index integer
function RegionMapPathTool.RemoveBend(ctx, pathId, index)
    local path = Paths.Get(pathId)
    if path == nil or path.bends[index] == nil then return end
    local bends = CopyBends(path)
    table.remove(bends, index)
    WriteBends(ctx, path, bends)
end

--- Whether bend handles show for the selected path: the Director, pins
--- unlocked, no tool on, and the path's panel open (Q5).
--- @param ctx RegionMapContext
--- @return nil|string pathId
function RegionMapPathTool.HandlesFor(ctx)
    local data = ctx.data
    if data.locked or data.tool ~= "none" or not Model.IsDirector() then return nil end
    if data.panelMode ~= "path" and data.panelMode ~= "pathEdit" then return nil end
    return data.selectedPathId
end
