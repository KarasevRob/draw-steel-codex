local mod = dmhub.GetModLoading()

--- Region Map storage: record types, safe reads of untrusted rows, validation
--- and table uploads. Only the model and undo call this; the UI goes through
--- the model. V1 map, label and tombstone rows are no longer read (decision 8.3).
--- @class RegionMapRecords: GameType
--- @field new fun(o?: table): RegionMapRecords
RegionMapRecords = RegisterGameType("RegionMapRecords")
local C = RegionMapConstants

--- Who changed a record and when. Every Region Map record carries these.
--- @class RegionMapAudit
--- @field mutationId string unique per write; lets a retry recognize its own failed upload
--- @field createdBy string
--- @field createdByName string
--- @field createdAt any
--- @field updatedBy string
--- @field updatedByName string
--- @field updatedAt any

--- Shared description and journal link of one Location (keyed by its id;
--- labelId repeats the id, as V1 rows did).
--- @class RegionMapLocationDetailRecord: GameType, RegionMapAudit
--- @field new fun(o?: table): RegionMapLocationDetailRecord
--- @field id string
--- @field labelId string
--- @field schemaVersion integer
--- @field hidden boolean
--- @field revision integer
--- @field description string
--- @field journalDocId string
RegionMapLocationDetailRecord = RegisterGameType("RegionMapLocationDetailRecord")
RegionMapLocationDetailRecord.tableName = C.detailsTableName

--- Director note of one Location (keyed by its id). Synced to every client
--- like any game table; the UI only shows it to Directors.
--- @class RegionMapLocationDirectorNoteRecord: GameType, RegionMapAudit
--- @field new fun(o?: table): RegionMapLocationDirectorNoteRecord
--- @field id string
--- @field labelId string
--- @field schemaVersion integer
--- @field hidden boolean
--- @field revision integer
--- @field note string
RegionMapLocationDirectorNoteRecord = RegisterGameType("RegionMapLocationDirectorNoteRecord")
RegionMapLocationDirectorNoteRecord.tableName = C.notesTableName

--- Distance calibration of a Location's map: two points and the distance between them.
--- @class RegionMapScale
--- @field u1 number
--- @field v1 number
--- @field u2 number
--- @field v2 number
--- @field distance number
--- @field unit "mi"|"km"

--- One place in the Region Map tree (V2). A Location may have a pin on its
--- parent's map and/or its own map image. Top-level Locations (parentId == "")
--- are the Atlas and always have an image. Description and journal link live in
--- the V1 details table and Director notes in the V1 notes table, keyed by this id.
--- @class RegionMapLocationRecord: GameType, RegionMapAudit
--- @field new fun(o?: table): RegionMapLocationRecord
--- @field id string V1 map or label id when migrated, else a new GUID
--- @field schemaVersion integer
--- @field parentId string "" for top-level
--- @field name string up to textLimit characters, one line; "" until named
--- @field u number 0..1 on the parent's map; ignored for top-level
--- @field v number
--- @field pinStyle "iconName"|"plate"|"iconOnly"
--- @field importance "major"|"normal"|"minor"
--- @field icon string curated icon key, library image id, or ""
--- @field visibility "hidden"|"revealed" pin visibility to players
--- @field imageId string "" when the Location has no map
--- @field imageRevision integer bumps on every new image; camera keys include it
--- @field mapShared boolean players may open this Location's map
--- @field scale nil|RegionMapScale
--- @field pace nil|number travel distance per day in the scale's unit
--- @field border nil|"none"|"fade"|"torn"|"frame" how the map image's edge draws; nil (older maps) is none
--- @field mode nil|"free"|"pointcrawl" set when the map is made, never changed (A4); nil (older maps) is free
--- @field ownerId string
--- @field ownerName string
--- @field createdByDirector boolean
--- @field revision integer
--- @field hidden boolean soft delete
RegionMapLocationRecord = RegisterGameType("RegionMapLocationRecord")
RegionMapLocationRecord.tableName = C.locationTableName

--- A point of the Party's route on one map.
--- @class RegionMapRoutePoint
--- @field u number
--- @field v number

--- One automatic Party entry in the session log (D14d, R8). Point crawl
--- entries (V2.1) add the path fields; older rows read their defaults.
--- @class RegionMapLogEntryRecord: GameType, RegionMapAudit
--- @field new fun(o?: table): RegionMapLogEntryRecord
--- @field id string
--- @field schemaVersion integer
--- @field kind "arrived"|"traveling"|"travelingOn"|"placed"|"leg"|"stopped"
--- @field mapId string the map the Party is on
--- @field locationId string arrived and leg: the Location reached; traveling: the one it left; else ""
--- @field pathId string leg and stopped: the path travelled; else ""
--- @field pathName string the path's display name when logged, so a later rename or delete keeps the history
--- @field fromId string leg: the end the leg set out from; stopped: the end the time counts from
--- @field toId string leg: the end reached; stopped: the other end
--- @field time number leg: watches it took (I1)
--- @field spent number stopped: watches already spent from fromId (Q15)
--- @field rest ""|"on"|"back" leg: left from partway, going on or turning back
--- @field secret boolean players get no path name and no line (W1)
--- @field route RegionMapRoutePoint[] Party positions on mapId, oldest first
--- @field mergedCount integer traveling drops merged into this entry
--- @field at any ServerTimestamp of the last change
--- @field byId string
--- @field byName string
--- @field byDirector boolean the log shows "the Director" instead of byName
--- @field note string Director annotation, may be ""
--- @field revision integer
--- @field hidden boolean
RegionMapLogEntryRecord = RegisterGameType("RegionMapLogEntryRecord")
RegionMapLogEntryRecord.tableName = C.logTableName
RegionMapLogEntryRecord.byDirector = false
-- Reading a field a row never had raises on a game type, so the V2.1 fields have defaults.
RegionMapLogEntryRecord.pathId = ""
RegionMapLogEntryRecord.pathName = ""
RegionMapLogEntryRecord.fromId = ""
RegionMapLogEntryRecord.toId = ""
RegionMapLogEntryRecord.time = 0
RegionMapLogEntryRecord.spent = 0
RegionMapLogEntryRecord.rest = ""
RegionMapLogEntryRecord.secret = false

--- A bend of a path line, in the map's 0..1 image units.
--- @class RegionMapBend
--- @field u number
--- @field v number

--- One point crawl path between two pins on the same map. Paths are two-way;
--- `back` makes the other direction slower or impossible (W2). The note is the
--- Director's: it syncs like any row and only the UI keeps it from players (C5).
--- @class RegionMapPathRecord: GameType, RegionMapAudit
--- @field new fun(o?: table): RegionMapPathRecord
--- @field id string
--- @field schemaVersion integer
--- @field mapId string the point crawl map both ends are pinned on
--- @field aId string one end (a Location id); times are "from a" unless stated
--- @field bId string the other end; never equal to aId
--- @field bends RegionMapBend[] at most pathBendLimit, in order from a to b
--- @field name string "" shows the type's name
--- @field typeId string a path type id; an unknown id draws as "No type" (N3)
--- @field time number watches from a to b, 0 or more
--- @field back "same"|"different"|"none" the b-to-a direction
--- @field backTime number watches from b to a when back is "different"
--- @field description string players read it once the path is visible (H5)
--- @field note string Director-only danger or requirement
--- @field visibility "hidden"|"revealed" new paths start revealed (W3)
--- @field revision integer
--- @field hidden boolean soft delete
RegionMapPathRecord = RegisterGameType("RegionMapPathRecord")
RegionMapPathRecord.tableName = C.pathTableName

--- A pending table write and how it ended.
--- @class RegionMapWrite
--- @field status "pending"|"confirmed"|"failed"
--- @field record table
--- @field description string
--- @field tableName string
--- @field mutationId nil|string
--- @field creating boolean
--- @field error nil|string
--- @field unchanged nil|boolean

--- @alias RegionMapWriteCallbacks {success: nil|fun(operation?: RegionMapWrite), failure: nil|fun(operation?: RegionMapWrite)}

setting {
    id = C.preferencesSettingId,
    description = "Region Map local view state.",
    storage = "pergamepreference",
    default = {},
}

mod:RegisterDocumentForCheckpointBackups(C.stateDocumentId)

--- @param value number
--- @param low number
--- @param high number
--- @return number
function RegionMapRecords.Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

--- @param value any
--- @return boolean
function RegionMapRecords.IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local IsFinite = RegionMapRecords.IsFinite

--- @param value any
--- @return boolean
function RegionMapRecords.IsPositiveInteger(value)
    return IsFinite(value) and value >= 1 and value <= C.maxRevision and value % 1 == 0
end
local IsPositiveInteger = RegionMapRecords.IsPositiveInteger

-- A plain function, not a closure per call: index rebuilds read thousands of fields.
local function TryGet(object, key, default)
    if type(object.try_get) == "function" then return object:try_get(key, default) end
    return object[key]
end

--- Read a field of an untrusted row. Rows may come from older or foreign
--- clients, and game types raise on reads of fields they do not declare.
--- @param object any
--- @param key string
--- @param default any
--- @return any
function RegionMapRecords.Field(object, key, default)
    if type(object) ~= "table" and type(object) ~= "userdata" then return default end
    local ok, value = pcall(TryGet, object, key, default)
    if not ok or value == nil then return default end
    return value
end
local Field = RegionMapRecords.Field

--- A record's revision, or 0 when it is missing or out of range.
--- @param record any
--- @return integer
function RegionMapRecords.RecordRevision(record)
    local value = Field(record, "revision", 0)
    if value == 0 or IsPositiveInteger(value) then return value end
    return 0
end

--- The revision the next write of a record carries, or nil when it cannot advance.
--- @param record any
--- @return nil|integer
function RegionMapRecords.NextRevision(record)
    local revision = Field(record, "revision", 0)
    if revision ~= 0 and not IsPositiveInteger(revision) then return nil end
    if revision >= C.maxRevision then return nil end
    return revision + 1
end

--- @param value any
--- @return string
function RegionMapRecords.TrimSingleLine(value)
    value = tostring(value or "")
    value = value:gsub("[\r\n]+", " ")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end
local TrimSingleLine = RegionMapRecords.TrimSingleLine

--- Length in UTF-8 characters; huge for malformed text so limits reject it.
--- @param value any
--- @return number
function RegionMapRecords.TextLength(value)
    local ok, length = pcall(utf8.len, value)
    if ok and length ~= nil then
        return length
    end
    return math.huge
end
local TextLength = RegionMapRecords.TextLength

--- Map names and label text: one trimmed line of 1..textLimit characters.
--- @param value any
--- @return boolean
function RegionMapRecords.ValidText(value)
    return type(value) == "string" and value ~= "" and TrimSingleLine(value) == value
        and TextLength(value) <= C.textLimit
end
local ValidText = RegionMapRecords.ValidText

--- Normalize multi-line text; nil when it holds control characters or is too long.
--- @param value any
--- @param limit integer characters
--- @param byteLimit integer
--- @return nil|string
function RegionMapRecords.NormalizeMultiline(value, limit, byteLimit)
    if type(value) ~= "string" then return nil end
    if value:find("[%z\1-\8\11\12\14-\31\127]") then return nil end
    value = value:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if #value > byteLimit or TextLength(value) > limit or value:find("[%z\1-\8\11\12\14-\31\127]") then return nil end
    return value
end

-- This is an intentionally limited, locale-independent case fold for map
-- names. It covers ASCII, Latin-1, Latin Extended-A, and Cyrillic. Unsupported
-- code points are preserved exactly. Canonically equivalent UTF-8 sequences
-- remain distinct because the addon has no public Unicode normalization API.
local function FoldMapNameCodepoint(codepoint)
    if codepoint >= 0x0041 and codepoint <= 0x005A then
        return utf8.char(codepoint + 0x20)
    end

    if (codepoint >= 0x00C0 and codepoint <= 0x00D6)
        or (codepoint >= 0x00D8 and codepoint <= 0x00DE) then
        return utf8.char(codepoint + 0x20)
    end
    if codepoint == 0x00DF or codepoint == 0x1E9E then
        return "ss"
    end

    if codepoint >= 0x0100 and codepoint <= 0x012E and codepoint % 2 == 0 then
        return utf8.char(codepoint + 1)
    end
    if codepoint == 0x0130 then
        return "i" .. utf8.char(0x0307)
    end
    if codepoint >= 0x0132 and codepoint <= 0x0136 and codepoint % 2 == 0 then
        return utf8.char(codepoint + 1)
    end
    if codepoint >= 0x0139 and codepoint <= 0x0147 and codepoint % 2 == 1 then
        return utf8.char(codepoint + 1)
    end
    if codepoint == 0x0149 then
        return utf8.char(0x02BC) .. "n"
    end
    if codepoint >= 0x014A and codepoint <= 0x0176 and codepoint % 2 == 0 then
        return utf8.char(codepoint + 1)
    end
    if codepoint == 0x0178 then
        return utf8.char(0x00FF)
    end
    if codepoint >= 0x0179 and codepoint <= 0x017D and codepoint % 2 == 1 then
        return utf8.char(codepoint + 1)
    end
    if codepoint == 0x017F then
        return "s"
    end

    if codepoint >= 0x0400 and codepoint <= 0x040F then
        return utf8.char(codepoint + 0x50)
    end
    if codepoint >= 0x0410 and codepoint <= 0x042F then
        return utf8.char(codepoint + 0x20)
    end
    if codepoint >= 0x0460 and codepoint <= 0x0480 and codepoint % 2 == 0 then
        return utf8.char(codepoint + 1)
    end
    if codepoint >= 0x048A and codepoint <= 0x04BE and codepoint % 2 == 0 then
        return utf8.char(codepoint + 1)
    end
    if codepoint == 0x04C0 then
        return utf8.char(0x04CF)
    end
    if codepoint >= 0x04C1 and codepoint <= 0x04CD and codepoint % 2 == 1 then
        return utf8.char(codepoint + 1)
    end
    if codepoint >= 0x04D0 and codepoint <= 0x052E and codepoint % 2 == 0 then
        return utf8.char(codepoint + 1)
    end

    return utf8.char(codepoint)
end

--- Sort and disambiguation key for map names (not a uniqueness key).
--- @param value any
--- @return string
function RegionMapRecords.MapNameKey(value)
    value = tostring(value or "")
    local folded = {}
    local ok = pcall(function()
        for _, codepoint in utf8.codes(value) do
            folded[#folded + 1] = FoldMapNameCodepoint(codepoint)
        end
    end)
    if not ok then
        -- Preserve the old safe behavior for malformed byte strings.
        return string.lower(value)
    end
    return table.concat(folded)
end

--- @return string
function RegionMapRecords.CurrentUserName()
    local name = TrimSingleLine(dmhub.userDisplayName)
    return name ~= "" and name or "Unknown user"
end
local CurrentUserName = RegionMapRecords.CurrentUserName

--- Stamp who changed a record. A fresh mutationId marks every write.
--- @param record table
--- @param creating boolean
function RegionMapRecords.Audit(record, creating)
    local now = ServerTimestamp()
    if creating then
        record.createdBy = dmhub.loginUserid
        record.createdByName = CurrentUserName()
        record.createdAt = now
    end
    record.updatedBy = dmhub.loginUserid
    record.updatedByName = CurrentUserName()
    record.updatedAt = now
    record.mutationId = dmhub.GenerateGuid()
end

-- One write per record at a time. A record whose create is still pending is
-- treated as absent, so a failed create never leaves a half-visible row.
local pendingWrites = {} --- @type table<string, RegionMapWrite>

--- Upload one row. Nil when a write of the same row is still pending or the
--- upload could not start; otherwise the operation, whose status the
--- callbacks report.
--- @param tableName string
--- @param record table
--- @param description string
--- @param callbacks nil|RegionMapWriteCallbacks
--- @param creating nil|boolean
--- @return nil|RegionMapWrite
function RegionMapRecords.UploadRecord(tableName, record, description, callbacks, creating)
    if mod.unloaded then return nil end
    local key = tableName .. ":" .. record.id
    local previous = pendingWrites[key]
    if previous ~= nil and previous.status == "pending" then return nil end
    --- @type RegionMapWrite
    local operation = {
        status = "pending", record = DeepCopy(record), description = description,
        tableName = tableName, mutationId = Field(record, "mutationId", nil), creating = creating == true,
    }
    pendingWrites[key] = operation
    local function Finish(status, message)
        if operation.status ~= "pending" then return end
        operation.status, operation.error = status, message
        if mod.unloaded then return end
        if callbacks ~= nil then
            local callback
            if status == "confirmed" then callback = callbacks.success else callback = callbacks.failure end
            if callback ~= nil then callback(operation) end
        end
    end
    local ok, result = pcall(dmhub.SetAndUploadTableItem, tableName, DeepCopy(record), {
        success = function() Finish("confirmed") end,
        failure = function(message) Finish("failed", tostring(message)) end,
    })
    if not ok or result == nil then
        Finish("failed", not ok and tostring(result) or nil)
        return nil
    end
    return operation
end

--- The last write of a row this session, in any state.
--- @param tableName string
--- @param id any
--- @return nil|RegionMapWrite
function RegionMapRecords.LastWrite(tableName, id)
    return pendingWrites[tableName .. ":" .. tostring(id)]
end

--- The write of a row that is still in flight.
--- @param tableName string
--- @param id any
--- @return nil|RegionMapWrite
function RegionMapRecords.PendingWrite(tableName, id)
    local operation = pendingWrites[tableName .. ":" .. tostring(id)]
    return operation ~= nil and operation.status == "pending" and operation or nil
end
local LastWrite = RegionMapRecords.LastWrite

--- @return table<string, RegionMapLocationDetailRecord>
function RegionMapRecords.DetailsTable()
    return (dmhub.GetTable(C.detailsTableName) or {}) --[[@as table<string, RegionMapLocationDetailRecord>]]
end

--- @return table<string, RegionMapLocationDirectorNoteRecord>
function RegionMapRecords.NotesTable()
    return (dmhub.GetTable(C.notesTableName) or {}) --[[@as table<string, RegionMapLocationDirectorNoteRecord>]]
end

local invalidDataReports = {}

--- Log a malformed row once and report it invalid.
--- @param kind string
--- @param id any
--- @param reason string
--- @return false
function RegionMapRecords.RejectMalformed(kind, id, reason)
    local key = string.format("%s:%s:%s", kind, tostring(id or "<unknown>"), reason)
    if not invalidDataReports[key] then
        invalidDataReports[key] = true
        print(string.format("REGION_MAP: ignoring malformed %s %s (%s)",
            kind, tostring(id or "<unknown>"), reason))
    end
    return false
end
local RejectMalformed = RegionMapRecords.RejectMalformed

-- V2 Locations and session log ------------------------------------------------------------

--- @return table<string, RegionMapLocationRecord>
function RegionMapRecords.LocationsTable()
    return (dmhub.GetTable(C.locationTableName) or {}) --[[@as table<string, RegionMapLocationRecord>]]
end

--- @return table<string, RegionMapLogEntryRecord>
function RegionMapRecords.LogTable()
    return (dmhub.GetTable(C.logTableName) or {}) --[[@as table<string, RegionMapLogEntryRecord>]]
end

-- Allowed values of the Location and log entry enums.
RegionMapRecords.pinStyles = { iconName = true, plate = true, iconOnly = true }
RegionMapRecords.importances = { major = true, normal = true, minor = true }
RegionMapRecords.visibilities = { hidden = true, revealed = true }
RegionMapRecords.scaleUnits = { mi = true, km = true }
RegionMapRecords.borders = { none = true, fade = true, torn = true, frame = true }
RegionMapRecords.modes = { free = true, pointcrawl = true }
RegionMapRecords.pathBacks = { same = true, different = true, none = true }
RegionMapRecords.logKinds = { arrived = true, traveling = true, travelingOn = true, placed = true, leg = true, stopped = true }
RegionMapRecords.legRests = { [""] = true, on = true, back = true }

--- A Location name: "" (not named yet) or one trimmed line of 1..textLimit characters.
--- @param value any
--- @return boolean
function RegionMapRecords.ValidName(value)
    return value == "" or ValidText(value)
end

--- @param value any
--- @return boolean
function RegionMapRecords.ValidUnit(value)
    return IsFinite(value) and value >= 0 and value <= 1
end
local ValidUnit = RegionMapRecords.ValidUnit

--- A map scale table, or nil for "not set". Anything else is invalid.
--- @param scale any
--- @return boolean
function RegionMapRecords.ValidScale(scale)
    if scale == nil then return true end
    if type(scale) ~= "table" then return false end
    return ValidUnit(scale.u1) and ValidUnit(scale.v1) and ValidUnit(scale.u2) and ValidUnit(scale.v2)
        and IsFinite(scale.distance) and scale.distance > 0 and RegionMapRecords.scaleUnits[scale.unit] == true
end

--- Field checks of one Location row, without looking at other rows. The tree
--- checks (parent exists, no cycles) are in IsValidLocation.
--- @param location any
--- @return boolean
function RegionMapRecords.IsValidLocationFields(location)
    if location == nil or Field(location, "hidden", false) then return false end
    local id = Field(location, "id", nil)
    local operation = id and LastWrite(C.locationTableName, id)
    if operation and operation.creating and operation.status ~= "confirmed" then return false end
    if Field(location, "schemaVersion", 0) ~= C.locationSchemaVersion then
        return RejectMalformed("location", id, "unsupported schema")
    end
    if type(id) ~= "string" or id == "" then return RejectMalformed("location", id, "missing id") end
    local parentId = Field(location, "parentId", nil)
    if type(parentId) ~= "string" or parentId == id then return RejectMalformed("location", id, "invalid parent") end
    if not RegionMapRecords.ValidName(Field(location, "name", nil)) then return RejectMalformed("location", id, "invalid name") end
    if not RegionMapRecords.pinStyles[Field(location, "pinStyle", "")]
        or not RegionMapRecords.importances[Field(location, "importance", "")]
        or not RegionMapRecords.visibilities[Field(location, "visibility", "")] then
        return RejectMalformed("location", id, "invalid style")
    end
    local icon = Field(location, "icon", nil)
    if type(icon) ~= "string" or #icon > C.journalIdLimit then return RejectMalformed("location", id, "invalid icon") end
    local imageId, imageRevision = Field(location, "imageId", nil), Field(location, "imageRevision", nil)
    if type(imageId) ~= "string" or (parentId == "" and imageId == "") then
        return RejectMalformed("location", id, "missing image")
    end
    if not (imageRevision == 0 and imageId == "") and not IsPositiveInteger(imageRevision) then
        return RejectMalformed("location", id, "invalid image revision")
    end
    if type(Field(location, "mapShared", nil)) ~= "boolean" then
        return RejectMalformed("location", id, "invalid sharing")
    end
    if parentId ~= "" and (not ValidUnit(Field(location, "u", nil)) or not ValidUnit(Field(location, "v", nil))) then
        return RejectMalformed("location", id, "invalid coordinates")
    end
    local pace = Field(location, "pace", nil)
    if not RegionMapRecords.ValidScale(Field(location, "scale", nil))
        or (pace ~= nil and not (IsFinite(pace) and pace > 0)) then
        return RejectMalformed("location", id, "invalid scale")
    end
    local border = Field(location, "border", nil)
    if border ~= nil and not RegionMapRecords.borders[border] then return RejectMalformed("location", id, "invalid border") end
    local mode = Field(location, "mode", nil)
    if mode ~= nil and not RegionMapRecords.modes[mode] then return RejectMalformed("location", id, "invalid mode") end
    if type(Field(location, "ownerId", nil)) ~= "string" or type(Field(location, "ownerName", nil)) ~= "string"
        or type(Field(location, "createdByDirector", nil)) ~= "boolean" then
        return RejectMalformed("location", id, "missing owner")
    end
    if RegionMapRecords.NextRevision(location) == nil then return RejectMalformed("location", id, "invalid revision") end
    return true
end

--- A Location whose fields are valid and whose parent chain reaches a
--- top-level Location through parents that have a map, with no cycle.
--- candidates holds the rows that passed IsValidLocationFields, by id.
--- @param location any
--- @param candidates table<string, RegionMapLocationRecord>
--- @return boolean
function RegionMapRecords.IsValidLocation(location, candidates)
    -- A row taken from candidates already passed the field checks; the index rebuild relies on this.
    local id = Field(location, "id", nil)
    if (type(id) ~= "string" or candidates[id] ~= location) and not RegionMapRecords.IsValidLocationFields(location) then
        return false
    end
    local current = location
    for _ = 1, C.maxDepth do
        local parentId = current.parentId
        if parentId == "" then return true end
        local parent = candidates[parentId]
        if parent == nil then return false end
        if parent.imageId == "" then return RejectMalformed("location", location.id, "parent has no map") end
        if parent.id == location.id then return RejectMalformed("location", location.id, "cycle") end
        current = parent
    end
    return RejectMalformed("location", location.id, "nested too deep")
end

--- @param entry any
--- @return boolean
function RegionMapRecords.IsValidLogEntry(entry)
    if entry == nil or Field(entry, "hidden", false) then return false end
    local id = Field(entry, "id", nil)
    local operation = id and LastWrite(C.logTableName, id)
    if operation and operation.creating and operation.status ~= "confirmed" then return false end
    if Field(entry, "schemaVersion", 0) ~= C.logSchemaVersion then
        return RejectMalformed("log entry", id, "unsupported schema")
    end
    if type(id) ~= "string" or id == "" then return RejectMalformed("log entry", id, "missing id") end
    if not RegionMapRecords.logKinds[Field(entry, "kind", "")] then return RejectMalformed("log entry", id, "invalid kind") end
    local mapId, locationId = Field(entry, "mapId", nil), Field(entry, "locationId", nil)
    if type(mapId) ~= "string" or mapId == "" or type(locationId) ~= "string" then
        return RejectMalformed("log entry", id, "invalid place")
    end
    local route = Field(entry, "route", nil)
    if type(route) ~= "table" then return RejectMalformed("log entry", id, "invalid route") end
    for _, point in ipairs(route) do
        if type(point) ~= "table" or not ValidUnit(point.u) or not ValidUnit(point.v) then
            return RejectMalformed("log entry", id, "invalid route")
        end
    end
    local merged = Field(entry, "mergedCount", nil)
    if not (merged == 0 or IsPositiveInteger(merged)) then return RejectMalformed("log entry", id, "invalid count") end
    local note = Field(entry, "note", nil)
    if type(Field(entry, "byId", nil)) ~= "string" or type(Field(entry, "byName", nil)) ~= "string"
        or type(note) ~= "string" or RegionMapRecords.NormalizeMultiline(note, C.noteLimit, C.noteByteLimit) ~= note then
        return RejectMalformed("log entry", id, "invalid author or note")
    end
    local kind = Field(entry, "kind", "")
    if kind == "leg" or kind == "stopped" then
        local pathId, fromId, toId = Field(entry, "pathId", ""), Field(entry, "fromId", ""), Field(entry, "toId", "")
        if type(pathId) ~= "string" or pathId == "" or type(fromId) ~= "string" or fromId == ""
            or type(toId) ~= "string" or toId == "" or fromId == toId
            or not RegionMapRecords.ValidName(Field(entry, "pathName", "")) then
            return RejectMalformed("log entry", id, "invalid path")
        end
        if not RegionMapRecords.ValidTime(Field(entry, "time", 0)) or not RegionMapRecords.ValidTime(Field(entry, "spent", 0))
            or not RegionMapRecords.legRests[Field(entry, "rest", "")] or type(Field(entry, "secret", false)) ~= "boolean" then
            return RejectMalformed("log entry", id, "invalid leg")
        end
    end
    if RegionMapRecords.NextRevision(entry) == nil then return RejectMalformed("log entry", id, "invalid revision") end
    return true
end

--- @return table<string, RegionMapPathRecord>
function RegionMapRecords.PathsTable()
    return (dmhub.GetTable(C.pathTableName) or {}) --[[@as table<string, RegionMapPathRecord>]]
end

--- @param value any
--- @return boolean
function RegionMapRecords.ValidTime(value)
    return IsFinite(value) and value >= 0 and value <= C.pathTimeMax
end

--- Field checks of one path row, without looking at other rows. Whether its
--- ends are pins on a point crawl map is checked by RegionMapPaths.
--- @param path any
--- @return boolean
function RegionMapRecords.IsValidPathFields(path)
    if path == nil or Field(path, "hidden", false) then return false end
    local id = Field(path, "id", nil)
    local operation = id and LastWrite(C.pathTableName, id)
    if operation and operation.creating and operation.status ~= "confirmed" then return false end
    if Field(path, "schemaVersion", 0) ~= C.pathSchemaVersion then return RejectMalformed("path", id, "unsupported schema") end
    if type(id) ~= "string" or id == "" then return RejectMalformed("path", id, "missing id") end
    local mapId, aId, bId = Field(path, "mapId", nil), Field(path, "aId", nil), Field(path, "bId", nil)
    if type(mapId) ~= "string" or mapId == "" or type(aId) ~= "string" or aId == ""
        or type(bId) ~= "string" or bId == "" or aId == bId then
        return RejectMalformed("path", id, "invalid ends")
    end
    local bends = Field(path, "bends", nil)
    if type(bends) ~= "table" or #bends > C.pathBendLimit then return RejectMalformed("path", id, "invalid bends") end
    for _, bend in ipairs(bends) do
        if type(bend) ~= "table" or not ValidUnit(bend.u) or not ValidUnit(bend.v) then
            return RejectMalformed("path", id, "invalid bends")
        end
    end
    local name, typeId = Field(path, "name", nil), Field(path, "typeId", nil)
    if not RegionMapRecords.ValidName(name) or type(typeId) ~= "string" or #typeId > C.pathTypeIdLimit then
        return RejectMalformed("path", id, "invalid name or type")
    end
    if not RegionMapRecords.ValidTime(Field(path, "time", nil)) or not RegionMapRecords.pathBacks[Field(path, "back", "")]
        or not RegionMapRecords.ValidTime(Field(path, "backTime", nil)) then
        return RejectMalformed("path", id, "invalid time")
    end
    local description, note = Field(path, "description", nil), Field(path, "note", nil)
    if type(description) ~= "string"
        or RegionMapRecords.NormalizeMultiline(description, C.descriptionLimit, C.descriptionByteLimit) ~= description
        or type(note) ~= "string" or RegionMapRecords.NormalizeMultiline(note, C.noteLimit, C.noteByteLimit) ~= note then
        return RejectMalformed("path", id, "invalid text")
    end
    if not RegionMapRecords.visibilities[Field(path, "visibility", "")] then return RejectMalformed("path", id, "invalid visibility") end
    if RegionMapRecords.NextRevision(path) == nil then return RejectMalformed("path", id, "invalid revision") end
    return true
end

--- The shared Region Map document (Party and its permission).
--- @return LuaCodeModDocumentSnapshot
function RegionMapRecords.StateDocument()
    return mod:GetDocumentSnapshot(C.stateDocumentId)
end

--- The state document's data, or nil when its schema is unsupported.
--- @return nil|table
function RegionMapRecords.StateData()
    local data = RegionMapRecords.StateDocument().data
    if type(data) ~= "table" then return nil end
    if data.schemaVersion == nil and next(data) == nil then return data end
    if data.schemaVersion ~= C.schemaVersion then
        RejectMalformed("state", C.stateDocumentId, "unsupported schema")
        return nil
    end
    return data
end

-- Location content (details and Director note sidecars) ----------------------------------

local NextRevision = RegionMapRecords.NextRevision

--- Table name, schema and record type of a location sidecar.
--- @param private boolean true for the Director note, false for shared details
--- @return string tableName, integer schema, table recordType
function RegionMapRecords.SidecarSpec(private)
    if private then return C.notesTableName, C.notesSchemaVersion, RegionMapLocationDirectorNoteRecord end
    return C.detailsTableName, C.detailsSchemaVersion, RegionMapLocationDetailRecord
end

local function SidecarTable(private)
    if private then return RegionMapRecords.NotesTable() end
    return RegionMapRecords.DetailsTable()
end

--- Read and validate a location sidecar row.
--- @param id string Location id
--- @param private boolean
--- @return nil|table row
--- @return "empty"|"available"|"unavailable" state
function RegionMapRecords.ReadSidecar(id, private)
    local _, schema = RegionMapRecords.SidecarSpec(private)
    local row = SidecarTable(private)[id]
    if row == nil then return nil, "empty" end
    local valid = Field(row, "id") == id and Field(row, "labelId") == id
        and Field(row, "schemaVersion") == schema and Field(row, "hidden") == false
        and NextRevision(row) ~= nil
    if private then
        local note = Field(row, "note")
        valid = valid and type(note) == "string" and RegionMapRecords.NormalizeMultiline(note, C.noteLimit, C.noteByteLimit) == note
    else
        local description, link = Field(row, "description"), Field(row, "journalDocId")
        valid = valid and type(description) == "string"
            and RegionMapRecords.NormalizeMultiline(description, C.descriptionLimit, C.descriptionByteLimit) == description
            and type(link) == "string" and #link <= C.journalIdLimit
    end
    if not valid then
        if dmhub.isDM then RejectMalformed(private and "Director note" or "location details", id, "unavailable content") end
        return nil, "unavailable"
    end
    return row, "available"
end
