local mod = dmhub.GetModLoading()

--- The session log (D14d, R8): one automatic entry per Party move, written by
--- whoever moved it. Consecutive traveling drops on one map merge into one
--- entry whose route grows. The Director may annotate or delete entries; the
--- Director's client trims the table to the newest C.logCap entries on open.
--- Model.WriteParty calls Record, so a Party move and its entry undo together.
--- @class RegionMapLog: GameType
--- @field new fun(o?: table): RegionMapLog
RegionMapLog = RegisterGameType("RegionMapLog")
local C = RegionMapConstants
local R = RegionMapRecords
local Model = RegionMapModel

local Field = R.Field

--- A Party position as Record compares it.
--- @class RegionMapPartyPoint
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

--- @param entry RegionMapLogEntryRecord
--- @return number milliseconds of server time
function RegionMapLog.Time(entry)
    return TimeOf(entry)
end

-- Newest first; equal times fall back to the id so the order is stable.
local function Newer(a, b)
    local ta, tb = TimeOf(a), TimeOf(b)
    if ta ~= tb then return ta > tb end
    return a.id > b.id
end

local cached = nil --- @type nil|RegionMapLogEntryRecord[]
local cachedKey = nil --- @type nil|string

local function CacheKey()
    return tostring(dmhub.ngameupdate) .. ":" .. tostring(dmhub.tablesUpdateId)
end

local function Invalidate()
    cached = nil
end

--- Every valid entry, newest first, not filtered for the viewer.
--- @return RegionMapLogEntryRecord[]
local function AllEntries()
    local key = CacheKey()
    if cached ~= nil and cachedKey == key then return cached end
    local list = {} --- @type RegionMapLogEntryRecord[]
    for _, row in pairs(R.LogTable()) do
        if R.IsValidLogEntry(row) then list[#list + 1] = row end
    end
    table.sort(list, Newer)
    cached, cachedKey = list, key
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
--- @param entry RegionMapLogEntryRecord
--- @return boolean
function RegionMapLog.ShowsPath(entry)
    if not IsPathEntry(entry) then return true end
    if Model.IsDirector() then return true end
    if entry.secret then return false end
    local path = RegionMapPaths.Index().byId[entry.pathId]
    return path == nil or RegionMapPaths.CanSee(path)
end
local ShowsPath = RegionMapLog.ShowsPath

--- The entries the viewer may see, newest first.
--- @return RegionMapLogEntryRecord[]
function RegionMapLog.Entries()
    local result = {} --- @type RegionMapLogEntryRecord[]
    for _, entry in ipairs(AllEntries()) do
        if CanSeeEntry(entry) then result[#result + 1] = entry end
    end
    return result
end

--- One visible entry by id, or nil.
--- @param id string
--- @return nil|RegionMapLogEntryRecord
function RegionMapLog.Get(id)
    for _, entry in ipairs(AllEntries()) do
        if entry.id == id then return CanSeeEntry(entry) and entry or nil end
    end
    return nil
end

--- The route the viewer may see on one map: one point list per entry, oldest
--- entry first. Consecutive entries share their joining point, so the lists
--- read as one path.
--- @param mapId string
--- @return RegionMapRoutePoint[][]
function RegionMapLog.Route(mapId)
    local legs = {} --- @type RegionMapRoutePoint[][]
    local entries = RegionMapLog.Entries()
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry.mapId == mapId and #entry.route > 0 and ShowsPath(entry) then legs[#legs + 1] = entry.route end
    end
    return legs
end

-- Writes -------------------------------------------------------------------------------------

-- Upload one entry and return its undo step (nil when it could not start).
local function WriteEntry(current, changes, description)
    local record = current and DeepCopy(current) or RegionMapLogEntryRecord.new { revision = 0 }
    for key, value in pairs(changes) do record[key] = value end
    local revision = R.NextRevision(record)
    if revision == nil then return nil end
    record.revision = revision
    R.Audit(record, current == nil)
    local operation = R.UploadRecord(C.logTableName, record, description,
        { success = Invalidate, failure = Invalidate }, current == nil)
    if operation == nil then return nil end
    Invalidate()
    --- @type RegionMapUndoStep
    return {
        tableName = C.logTableName, id = record.id,
        before = current and DeepCopy(current) or nil,
        afterRevision = revision, afterMutationId = record.mutationId,
    }
end

local function Point(party)
    return { u = party.u, v = party.v }
end

--- Log a Party move and return its undo step. Called by Model.WriteParty
--- after the Party write; nil when nothing could be written (the move itself
--- still stands).
--- @param before nil|RegionMapPartyView where the Party was (unfiltered); nil when not placed
--- @param after RegionMapPartyPoint where it is now
--- @param placed boolean "Place Party here" (a jump, not a leg of travel)
--- @return nil|RegionMapUndoStep
function RegionMapLog.Record(before, after, placed)
    if mod.unloaded then return nil end
    -- Where the Party was, when that was on the same map: the start of this leg.
    local from = nil --- @type nil|RegionMapPartyView
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
--- @return nil|RegionMapLogEntryRecord
function RegionMapLog.Newest()
    local newest = AllEntries()[1]
    if newest == nil or R.PendingWrite(C.logTableName, newest.id) then return nil end
    return newest
end

--- What a leg or stop entry records (RegionMapTravel fills it in).
--- @class RegionMapPathEntryArgs
--- @field mapId string
--- @field pathId string
--- @field pathName string
--- @field fromId string
--- @field toId string
--- @field time nil|number leg
--- @field spent nil|number stop
--- @field rest nil|""|"on"|"back"
--- @field secret boolean
--- @field route RegionMapRoutePoint[]

local function WritePathEntry(kind, args)
    local by = {
        byId = dmhub.loginUserid, byName = R.CurrentUserName(), byDirector = dmhub.isDM == true, at = ServerTimestamp(),
    }
    local route = {} --- @type RegionMapRoutePoint[]
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
--- @param args RegionMapPathEntryArgs
--- @return nil|RegionMapUndoStep
function RegionMapLog.RecordLeg(args)
    if mod.unloaded then return nil end
    return WritePathEntry("leg", args)
end

--- Log a stop partway along a path (N2, Q15); its undo step, or nil.
--- @param args RegionMapPathEntryArgs
--- @return nil|RegionMapUndoStep
function RegionMapLog.RecordStop(args)
    if mod.unloaded then return nil end
    return WritePathEntry("stopped", args)
end

--- Hide an entry inside another write's undo entry (a stop replacing the
--- arrival it interrupts, Q14); its undo step, or nil.
--- @param entry RegionMapLogEntryRecord
--- @param description string
--- @return nil|RegionMapUndoStep
function RegionMapLog.HideStep(entry, description)
    if R.PendingWrite(C.logTableName, entry.id) then return nil end
    return WriteEntry(entry, { hidden = true }, description)
end

--- Director: set or clear an entry's note.
--- @param id string
--- @param note string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapLog.SetNote(id, note)
    if not Model.IsDirector() then return false, "permission", nil end
    local entry = RegionMapLog.Get(id)
    if entry == nil then return false, "invalid", nil end
    local normalized = R.NormalizeMultiline(note, C.noteLimit, C.noteByteLimit)
    if normalized == nil then return false, "invalid", nil end
    if normalized == entry.note then return true, nil, nil end
    if R.PendingWrite(C.logTableName, id) then return false, "busy", nil end
    local step = WriteEntry(entry, { note = normalized }, "Edit session log note")
    if step == nil then return false, "unavailable", nil end
    return true, nil, { description = "Edit session log note", steps = { step } }
end

--- Director: delete an entry (soft, so undo can restore it).
--- @param id string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapLog.DeleteEntry(id)
    if not Model.IsDirector() then return false, "permission", nil end
    local entry = RegionMapLog.Get(id)
    if entry == nil then return false, "invalid", nil end
    if R.PendingWrite(C.logTableName, id) then return false, "busy", nil end
    local step = WriteEntry(entry, { hidden = true }, "Delete session log entry")
    if step == nil then return false, "unavailable", nil end
    return true, nil, { description = "Delete session log entry", steps = { step } }
end

local capChecked = false

--- Director, once per session: keep the newest C.logCap rows (decision 8.1).
--- Deleted rows go first, then the oldest entries.
function RegionMapLog.EnforceCap()
    if capChecked or not dmhub.isDM or mod.unloaded then return end
    capChecked = true
    local rows = {} --- @type RegionMapLogEntryRecord[]
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
