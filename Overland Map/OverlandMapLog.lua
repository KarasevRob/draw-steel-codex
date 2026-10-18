local mod = dmhub.GetModLoading()

--- The session log (D14d, R8): one automatic entry per Party move, written by
--- whoever moved it. Consecutive traveling drops on one map merge into one
--- entry whose route grows. The Director may annotate or delete entries; the
--- Director's client trims the table to the newest C.logCap entries on open.
--- Model.WriteParty calls Record, so a Party move and its entry undo together.
--- @class OverlandMapLog: GameType
--- @field new fun(o?: table): OverlandMapLog
OverlandMapLog = RegisterGameType("OverlandMapLog")
local C = OverlandMapConstants
local R = OverlandMapRecords
local Model = OverlandMapModel

local Field = R.Field

--- A Party position as Record compares it.
--- @class OverlandMapPartyPoint
--- @field mapId string
--- @field u number
--- @field v number
--- @field locationId nil|string

-- A row's time in server milliseconds. A row this client just wrote still
-- holds the ServerTimestamp placeholder, which means "now".
local function TimeOf(entry)
    local at = Field(entry, "at", nil)
    if type(at) == "number" then return at end
    return dmhub.serverTimeMilliseconds
end

--- @param entry OverlandMapLogEntryRecord
--- @return number milliseconds of server time
function OverlandMapLog.Time(entry)
    return TimeOf(entry)
end

-- Newest first; equal times fall back to the id so the order is stable.
local function Newer(a, b)
    local ta, tb = TimeOf(a), TimeOf(b)
    if ta ~= tb then return ta > tb end
    return a.id > b.id
end

local cached = nil --- @type nil|OverlandMapLogEntryRecord[]
local cachedRevision = nil --- @type nil|integer

local function Invalidate()
    cached = nil
end

--- Every valid entry, newest first, not filtered for the viewer. Rebuilt when
--- the data changed (Model.Revision) or this client wrote an entry.
--- @return OverlandMapLogEntryRecord[]
local function AllEntries()
    local key = Model.Revision()
    if cached ~= nil and cachedRevision == key then return cached end
    local list = {} --- @type OverlandMapLogEntryRecord[]
    local times = {} --- @type table<OverlandMapLogEntryRecord, number>
    for _, row in pairs(R.LogTable()) do
        if R.IsValidLogEntry(row) then
            list[#list + 1] = row
            times[row] = TimeOf(row)
        end
    end
    -- Times are read once up front: the sort compares each entry many times.
    table.sort(list, function(a, b)
        local ta, tb = times[a], times[b]
        if ta ~= tb then return ta > tb end
        return a.id > b.id
    end)
    cached, cachedRevision = list, key
    return list
end

local function IsPathEntry(entry)
    return entry.kind == "leg" or entry.kind == "stopped"
end

-- Players see an entry only when they may open its map and see the Location
-- it names (a Hidden Location never shows up in their log or route). A leg or
-- stop needs both ends of its path visible.
local function CanSeeEntry(entry)
    if not Model.CanOpenMap(Model.GetLocation(entry.mapId)) then return false end
    if IsPathEntry(entry) then
        return Model.CanSeePin(Model.GetLocation(entry.fromId)) and Model.CanSeePin(Model.GetLocation(entry.toId))
    end
    if entry.locationId == "" then return true end
    return Model.CanSeePin(Model.GetLocation(entry.locationId))
end

--- Whether the viewer may read a leg's or stop's path name and see its line
--- (W1): never for players on a secret entry or a path hidden from them now.
--- A path deleted since keeps the name it had.
--- @param entry OverlandMapLogEntryRecord
--- @return boolean
function OverlandMapLog.ShowsPath(entry)
    if not IsPathEntry(entry) then return true end
    if Model.IsDirector() then return true end
    if entry.secret then return false end
    local path = OverlandMapPaths.Index().byId[entry.pathId]
    return path == nil or OverlandMapPaths.CanSee(path)
end
local ShowsPath = OverlandMapLog.ShowsPath

-- The filtered list and routes are kept until the entries are rebuilt (a new
-- AllEntries list) or the viewer changes; every refresh asks for them.
local visible = nil --- @type nil|OverlandMapLogEntryRecord[]
local visibleFrom, visibleDirector = nil, nil --- @type nil|OverlandMapLogEntryRecord[], nil|boolean
local routes = {} --- @type table<string, OverlandMapRoutePoint[][]>

--- The entries the viewer may see, newest first. Shared: callers must not change it.
--- @return OverlandMapLogEntryRecord[]
function OverlandMapLog.Entries()
    local all = AllEntries()
    local director = Model.IsDirector()
    if visible ~= nil and visibleFrom == all and visibleDirector == director then return visible end
    local result = {} --- @type OverlandMapLogEntryRecord[]
    for _, entry in ipairs(all) do
        if CanSeeEntry(entry) then result[#result + 1] = entry end
    end
    visible, visibleFrom, visibleDirector, routes = result, all, director, {}
    return result
end

--- One visible entry by id, or nil.
--- @param id string
--- @return nil|OverlandMapLogEntryRecord
function OverlandMapLog.Get(id)
    for _, entry in ipairs(AllEntries()) do
        if entry.id == id then return CanSeeEntry(entry) and entry or nil end
    end
    return nil
end

--- The route the viewer may see on one map: one point list per entry, oldest
--- entry first. Consecutive entries share their joining point, so the lists
--- read as one path.
--- Shared like Entries: callers must not change it.
--- @param mapId string
--- @return OverlandMapRoutePoint[][]
function OverlandMapLog.Route(mapId)
    local entries = OverlandMapLog.Entries()
    local legs = routes[mapId]
    if legs ~= nil then return legs end
    legs = {} --- @type OverlandMapRoutePoint[][]
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry.mapId == mapId and #entry.route > 0 and ShowsPath(entry) then legs[#legs + 1] = entry.route end
    end
    routes[mapId] = legs
    return legs
end

--- The copy id and arguments of a leg's line, in the one wording the log and
--- the travel toast share (Q19). The rest of a path ("on") and turning back
--- ("back") name only where the Party went; a whole leg uses plainId.
--- @param rest nil|""|"on"|"back"
--- @param from string plain name
--- @param to string plain name
--- @param pathName string plain name; "" drops "by ..." (manifest 25.2)
--- @param watches number
--- @param plainId string a whole leg's copy id: "log.leg" or "toast.traveled"
--- @return string copyId
--- @return table args
function OverlandMapLog.LegCopy(rest, from, to, pathName, watches, plainId)
    local by = pathName ~= "" and OverlandMapCopy.T("leg.by", { path = pathName }, true) or ""
    -- Paths loads after this file, so it is read at call time.
    local args = { from = from, to = to, by = by, time = OverlandMapPaths.FormatTime(watches) }
    if rest == "on" then return "log.leg.on", args end
    if rest == "back" then return "log.leg.back", args end
    return plainId, args
end

-- Writes -------------------------------------------------------------------------------------

-- Upload one entry and return its undo step (nil when it could not start).
local function WriteEntry(current, changes, description, callbacks, retry)
    local record = current and DeepCopy(current) or OverlandMapLogEntryRecord.new { revision = 0 }
    for key, value in pairs(changes) do record[key] = value end
    local step, receipt = R.WriteRow(C.logTableName, current, record, description, {
        success = function(write) Invalidate(); if callbacks and callbacks.success then callbacks.success(write) end end,
        failure = function(write) Invalidate(); if callbacks and callbacks.failure then callbacks.failure(write) end end,
    }, { retry = retry })
    Invalidate()
    return step, receipt
end

local function Point(party)
    return { u = party.u, v = party.v }
end

--- Log a Party move and return its undo step. Called by Model.WriteParty
--- after the Party write; nil when nothing could be written (the move itself
--- still stands).
--- @param before nil|OverlandMapPartyView where the Party was (unfiltered); nil when not placed
--- @param after OverlandMapPartyPoint where it is now
--- @param placed boolean "Place Party here" (a jump, not a leg of travel)
--- @return nil|OverlandMapUndoStep
--- @return nil|OverlandMapWrite receipt
function OverlandMapLog.Record(before, after, placed)
    if mod.unloaded then return nil end
    -- Where the Party was, when that was on the same map: the start of this leg.
    local from = nil --- @type nil|OverlandMapPartyView
    if before ~= nil and before.mapId == after.mapId then from = before end
    local by = {
        byId = dmhub.loginUserid, byName = R.CurrentUserName(), byDirector = dmhub.isDM == true,
        at = ServerTimestamp(),
    }
    -- R8: a free drop right after another traveling entry on the same map extends it.
    local newest = AllEntries()[1]
    if not placed and after.locationId == nil and from ~= nil and from.locationId == nil and newest ~= nil
        and newest.mapId == after.mapId and (newest.kind == "traveling" or newest.kind == "travelingOn")
        and R.PendingWrite(C.logTableName, newest.id) == nil and #newest.route < C.routeDotLimit then
        local route = DeepCopy(newest.route)
        route[#route + 1] = Point(after)
        return WriteEntry(newest, {
            route = route, mergedCount = newest.mergedCount + 1,
            at = by.at, byId = by.byId, byName = by.byName, byDirector = by.byDirector,
        }, "Log Party travel")
    end
    local kind, locationId
    if placed then
        kind, locationId = "placed", ""
    elseif after.locationId ~= nil then
        kind, locationId = "arrived", after.locationId
    elseif from ~= nil and from.locationId ~= nil then
        kind, locationId = "traveling", from.locationId
    else
        kind, locationId = "travelingOn", ""
    end
    local route = {}
    if from ~= nil and not placed then route[1] = Point(from) end
    route[#route + 1] = Point(after)
    return WriteEntry(nil, {
        id = dmhub.GenerateGuid(), schemaVersion = C.logSchemaVersion, kind = kind,
        mapId = after.mapId, locationId = locationId, route = route, mergedCount = 0,
        note = "", hidden = false,
        at = by.at, byId = by.byId, byName = by.byName, byDirector = by.byDirector,
    }, "Log Party move")
end

--- The newest entry, unfiltered; nil when its write is still in flight, since
--- a row being written cannot be written again (a stop replacing it, Q14).
--- @return nil|OverlandMapLogEntryRecord
function OverlandMapLog.Newest()
    local newest = AllEntries()[1]
    if newest == nil or R.PendingWrite(C.logTableName, newest.id) then return nil end
    return newest
end

--- What a leg or stop entry records (OverlandMapTravel fills it in).
--- @class OverlandMapPathEntryArgs
--- @field mapId string
--- @field pathId string
--- @field pathName string
--- @field fromId string
--- @field toId string
--- @field time nil|number leg
--- @field spent nil|number stop
--- @field rest nil|""|"on"|"back"
--- @field secret boolean
--- @field route OverlandMapRoutePoint[]

local function WritePathEntry(kind, args)
    local by = {
        byId = dmhub.loginUserid, byName = R.CurrentUserName(), byDirector = dmhub.isDM == true, at = ServerTimestamp(),
    }
    local route = {} --- @type OverlandMapRoutePoint[]
    for _, point in ipairs(args.route) do route[#route + 1] = { u = point.u, v = point.v } end
    return WriteEntry(nil, {
        id = dmhub.GenerateGuid(), schemaVersion = C.logSchemaVersion, kind = kind, mapId = args.mapId,
        locationId = kind == "leg" and args.toId or "", route = route, mergedCount = 0, note = "", hidden = false,
        pathId = args.pathId, pathName = args.pathName, fromId = args.fromId, toId = args.toId,
        time = args.time or 0, spent = args.spent or 0, rest = args.rest or "", secret = args.secret == true,
        at = by.at, byId = by.byId, byName = by.byName, byDirector = by.byDirector,
    }, kind == "leg" and "Log Party travel" or "Log Party stop")
end

--- Log one leg of travel along a path (I1); its undo step, or nil.
--- @param args OverlandMapPathEntryArgs
--- @return nil|OverlandMapUndoStep
--- @return nil|OverlandMapWrite receipt
function OverlandMapLog.RecordLeg(args)
    if mod.unloaded then return nil end
    return WritePathEntry("leg", args)
end

--- Log a stop partway along a path (N2, Q15); its undo step, or nil.
--- @param args OverlandMapPathEntryArgs
--- @return nil|OverlandMapUndoStep
--- @return nil|OverlandMapWrite receipt
function OverlandMapLog.RecordStop(args)
    if mod.unloaded then return nil end
    return WritePathEntry("stopped", args)
end

--- Hide an entry inside another write's undo entry (a stop replacing the
--- arrival it interrupts, Q14); its undo step, or nil.
--- @param entry OverlandMapLogEntryRecord
--- @param description string
--- @return nil|OverlandMapUndoStep
--- @return nil|OverlandMapWrite receipt
function OverlandMapLog.HideStep(entry, description)
    if R.PendingWrite(C.logTableName, entry.id) then return nil end
    return WriteEntry(entry, { hidden = true }, description)
end

--- Director: set or clear an entry's note.
--- @param id string
--- @param note string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
--- @return nil|OverlandMapWrite receipt
function OverlandMapLog.SetNote(id, note, callbacks, retry)
    if not Model.IsDirector() then return false, "permission", nil end
    local entry = OverlandMapLog.Get(id)
    if entry == nil then return false, "invalid", nil end
    local normalized = R.NormalizeMultiline(note, C.noteLimit, C.noteByteLimit)
    if normalized == nil then return false, "invalid", nil end
    if normalized == entry.note and not R.CanRetryWrite(C.logTableName, entry, retry) then return true, nil, nil end
    if R.PendingWrite(C.logTableName, id) then return false, "busy", nil end
    local step, receipt = WriteEntry(entry, { note = normalized }, "Edit session log note", callbacks, retry)
    if step == nil then return false, "unavailable", nil, receipt end
    return true, nil, { description = "Edit session log note", steps = { step } }, receipt
end

--- Director: delete an entry (soft, so undo can restore it).
--- @param id string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapLog.DeleteEntry(id)
    if not Model.IsDirector() then return false, "permission", nil end
    local entry = OverlandMapLog.Get(id)
    if entry == nil then return false, "invalid", nil end
    if R.PendingWrite(C.logTableName, id) then return false, "busy", nil end
    local step = WriteEntry(entry, { hidden = true }, "Delete session log entry")
    if step == nil then return false, "unavailable", nil end
    return true, nil, { description = "Delete session log entry", steps = { step } }
end

local capChecked = false

--- Director, once per session: keep the newest C.logCap rows (decision 8.1).
--- Deleted rows go first, then the oldest entries.
function OverlandMapLog.EnforceCap()
    if capChecked or not dmhub.isDM or mod.unloaded then return end
    capChecked = true
    local rows = {} --- @type OverlandMapLogEntryRecord[]
    for _, row in pairs(R.LogTable()) do rows[#rows + 1] = row end
    local excess = #rows - C.logCap
    if excess <= 0 then return end
    table.sort(rows, function(a, b)
        local ha, hb = Field(a, "hidden", false) == true, Field(b, "hidden", false) == true
        if ha ~= hb then return ha end
        return Newer(b, a)
    end)
    for i = 1, excess do
        local id = Field(rows[i], "id", nil)
        if type(id) == "string" then pcall(dmhub.ObliterateTableItem, C.logTableName, id) end
    end
    Invalidate()
end
