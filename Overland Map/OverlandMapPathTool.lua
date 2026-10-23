local mod = dmhub.GetModLoading()

--- Making and reshaping point crawl paths: the Path
--- tool's steps, Connect to..., Redraw line and the bend handle edits. The
--- canvas reports clicks, right-clicks and Backspace here; the line being drawn
--- lives in ctx.data.pathDraft and the path layer draws it.
---
--- Path tool: click the start pin, click the map for bends, click the end pin.
--- The path is made with the last type and time (Q8) and opens in the edit
--- form, and the tool stays on for the next one.
--- @class OverlandMapPathTool: GameType
--- @field new fun(o?: table): OverlandMapPathTool
OverlandMapPathTool = RegisterGameType("OverlandMapPathTool")
local C = OverlandMapConstants
local Model = OverlandMapModel
local Paths = OverlandMapPaths
local Session = OverlandMapControls
local Undo = OverlandMapUndo

local function T(id, args) return OverlandMapCopy.T(id, args) end

--- The line being drawn on the open map, or nil.
--- @param ctx OverlandMapContext
--- @return nil|OverlandMapPathDraft
function OverlandMapPathTool.Draft(ctx)
    local data = ctx.data
    local draft = data.pathDraft
    if draft == nil or (data.tool ~= "path" and data.tool ~= "redraw") or draft.mapId ~= data.mapId then return nil end
    return draft
end
local Draft = OverlandMapPathTool.Draft

-- A new row can answer success a moment before this client's index has it,
-- so wait for it before opening it.
local function WhenReadable(ctx, id, valid, action, attempt)
    attempt = attempt or 1
    if not valid() or not Model.IsDirector() then return end
    if Paths.Get(id) ~= nil then
        action()
    elseif attempt < C.busyRetries then
        OverlandMapLifetime.Schedule(C.busyRetryDelay, function() WhenReadable(ctx, id, valid, action, attempt + 1) end)
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
--- @param ctx OverlandMapContext
--- @param aId string
--- @param bId string
--- @param bends nil|OverlandMapBend[]
--- @return boolean ok
function OverlandMapPathTool.Connect(ctx, aId, bId, bends)
    local map = ctx.CurrentMap()
    local a, b = Model.GetLocation(aId), Model.GetLocation(bId)
    if map == nil or a == nil or b == nil then return false end
    bends = bends or {}
    if #bends == 0 then
        local existing = Paths.CountJoining(aId, bId)
        local bend = existing > 0 and OffsetBend(a, b, existing) or nil
        if bend ~= nil then bends = { bend } end
    end
    local style = OverlandMapPreferences.LastPathStyle()
    local valid = OverlandMapSession.Guard(ctx, function()
        return Model.IsDirector() and Model.CanOpenMap(Model.GetLocation(map.id))
            and Model.GetLocation(aId) ~= nil and Model.GetLocation(bId) ~= nil
    end)
    local result = OverlandMapCommands.CreatePath(map.id, aId, bId, {
        typeId = style.typeId, time = style.time, backTime = style.time, bends = bends,
    }, {
        success = function(write)
            local created = write.record.id
            WhenReadable(ctx, created, valid, function() ctx.SelectPath(created, "pathEdit") end)
        end,
        failure = function() if valid() then ctx.Report(false, "unavailable") end end,
    })
    local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
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
    local result = OverlandMapCommands.UpdatePath(path.id, { bends = draft.bends }, "Redraw overland map path")
    local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
    if ctx.Report(ok, reason) then ctx.Push(entry, "toast.moved", { name = Paths.Title(path, true) }) end
    ctx.SelectPath(path.id)
end

--- A click while the Path tool or Redraw line is on: a pin (pinId, from a pin's
--- own click or within the snap radius of one) or a point of the map (u, v).
--- @param ctx OverlandMapContext
--- @param u nil|number
--- @param v nil|number
--- @param pinId nil|string
function OverlandMapPathTool.Click(ctx, u, v, pinId)
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
        if startId ~= nil then OverlandMapPathTool.Connect(ctx, startId, pinId, bends) end
        ctx.RefreshAll()
        return
    end
    if u == nil or v == nil or #draft.bends >= C.pathBendLimit then return end
    draft.bends[#draft.bends + 1] = { u = u, v = v }
end

--- Right-click or Backspace: drop the last bend. True when one was dropped.
--- @param ctx OverlandMapContext
--- @return boolean
function OverlandMapPathTool.Back(ctx)
    local draft = Draft(ctx)
    if draft == nil or #draft.bends == 0 then return false end
    table.remove(draft.bends)
    return true
end

--- Esc with the Path tool on: the first cancels the line being drawn and keeps
--- the tool; the shell turns the tool off on the next (Q7). True when handled.
--- @param ctx OverlandMapContext
--- @return boolean
function OverlandMapPathTool.Escape(ctx)
    if ctx.data.tool ~= "path" or Draft(ctx) == nil then return false end
    ctx.data.pathDraft = nil
    ctx.RefreshAll()
    return true
end

--- The banner line for the Path tool or Redraw line, or nil.
--- @param ctx OverlandMapContext
--- @return nil|string
function OverlandMapPathTool.Hint(ctx)
    local data = ctx.data
    if data.tool == "path" then return T(Draft(ctx) ~= nil and "hint.path.next" or "hint.path.start") end
    if data.tool ~= "redraw" then return nil end
    local draft = Draft(ctx)
    local path = Paths.Get(data.toolTargetId)
    if draft == nil or path == nil then return nil end
    local b = Model.GetLocation(draft.endId)
    return T("hint.redraw", { path = Paths.Title(path, true), name = Model.DisplayName(b) })
end

--- The points to draw for the line being drawn: the start pin and its bends.
--- @param ctx OverlandMapContext
--- @return nil|{u: number, v: number}[]
--- @return nil|OverlandMapPathLook look the line will have
function OverlandMapPathTool.DraftPoints(ctx)
    local draft = Draft(ctx)
    local start = draft ~= nil and Model.GetLocation(draft.startId) or nil
    if draft == nil or start == nil then return nil, nil end
    local points = { { u = start.u, v = start.v } }
    for _, bend in ipairs(draft.bends) do points[#points + 1] = { u = bend.u, v = bend.v } end
    local look
    local path = draft.pathId ~= nil and Paths.Get(draft.pathId) or nil
    if path ~= nil then
        look = OverlandMapPathLayer.LookOf(path)
    else
        look = OverlandMapPathLayer.LookOfType(Paths.TypeById(OverlandMapPreferences.LastPathStyle().typeId))
    end
    return points, look
end

--- Redraw line (Q6): the Path tool's second step for one path, from its a end.
--- @param ctx OverlandMapContext
--- @param pathId string
function OverlandMapPathTool.StartRedraw(ctx, pathId)
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
    local result = OverlandMapCommands.UpdatePath(path.id, { bends = bends }, "Edit overland map path bends")
    local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
    if ctx.Report(ok, reason) then ctx.Push(entry, "toast.moved", { name = Paths.Title(path, true) }) end
    ctx.RefreshAll()
end

local function CopyBends(path)
    local bends = {} --- @type OverlandMapBend[]
    for _, bend in ipairs(path.bends) do bends[#bends + 1] = { u = bend.u, v = bend.v } end
    return bends
end

--- Drop a bend handle: bend `index` moves to (u, v), or with insert a new bend
--- goes in at `index` (dragged from the "+" of segment `index`).
--- @param ctx OverlandMapContext
--- @param pathId string
--- @param index integer
--- @param insert boolean
--- @param u number
--- @param v number
function OverlandMapPathTool.DropBend(ctx, pathId, index, insert, u, v)
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
--- @param ctx OverlandMapContext
--- @param pathId string
--- @param index integer
function OverlandMapPathTool.RemoveBend(ctx, pathId, index)
    local path = Paths.Get(pathId)
    if path == nil or path.bends[index] == nil then return end
    local bends = CopyBends(path)
    table.remove(bends, index)
    WriteBends(ctx, path, bends)
end

--- Whether bend handles show for the selected path: the Director, pins
--- unlocked, no tool on, and the path's panel open (Q5).
--- @param ctx OverlandMapContext
--- @return nil|string pathId
function OverlandMapPathTool.HandlesFor(ctx)
    local data = ctx.data
    if data.locked or data.tool ~= "none" or not Model.IsDirector() then return nil end
    if data.panelMode ~= "path" and data.panelMode ~= "pathEdit" then return nil end
    return data.selectedPathId
end
