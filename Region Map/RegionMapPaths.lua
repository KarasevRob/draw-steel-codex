local mod = dmhub.GetModLoading()

--- Point crawl paths (V2.1): which paths each viewer sees (H1), the Director's
--- path writes (H3), the cascades the model runs when pins go (B5), the
--- game-wide path types and travel time unit (C3, C9), and time wording.
--- The UI never reads the paths table directly; it calls these.
--- @class RegionMapPaths: GameType
--- @field new fun(o?: table): RegionMapPaths
RegionMapPaths = RegisterGameType("RegionMapPaths")
local C = RegionMapConstants
local R = RegionMapRecords
local Model = RegionMapModel

local IsFinite = R.IsFinite

--- One path type (C3): its name and how its line draws.
--- @class RegionMapPathType
--- @field id string
--- @field name string
--- @field pattern "solid"|"dashed"|"dotted"|"double"|"dashDot"|"longDash"
--- @field color string a key of C.pathColors
--- @field width "thin"|"normal"|"thick"

--- Every path whose ends are pins on its point crawl map. Not filtered for the viewer.
--- @class RegionMapPathIndex
--- @field byId table<string, RegionMapPathRecord>
--- @field onMap table<string, RegionMapPathRecord[]>
--- @field ofLocation table<string, RegionMapPathRecord[]>

local patterns, widths, colors = {}, {}, {}
for _, key in ipairs(C.pathPatterns) do patterns[key] = true end
for _, key in ipairs(C.pathWidthOrder) do widths[key] = true end
for _, key in ipairs(C.pathColorOrder) do colors[key] = true end
local units = { days = true, watches = true }

local function T(id, args) return RegionMapCopy.T(id, args) end

local function Entry(description, steps)
    return { description = description, steps = steps } --[[@as RegionMapUndoEntry]]
end

-- Index ------------------------------------------------------------------------------------------

local cached = nil --- @type nil|RegionMapPathIndex
local cachedKey = nil --- @type nil|string
local cachedLocations = nil --- @type nil|RegionMapLocationIndex

-- Rebuilt when cloud data arrives or the Location index was rebuilt; this client's
-- own path writes call Model.InvalidateIndex, which does the latter.
local function Key()
    return tostring(dmhub.ngameupdate) .. ":" .. tostring(dmhub.tablesUpdateId)
end

--- The validated paths, rebuilt only when the data changed. A path whose end was
--- deleted or moved away is skipped, not removed: undoing the delete brings it back.
--- @return RegionMapPathIndex
function RegionMapPaths.Index()
    local locations = Model.Index()
    local key = Key()
    if cached ~= nil and cachedKey == key and cachedLocations == locations then return cached end
    local byId, onMap, ofLocation = {}, {}, {} --- @type table<string, RegionMapPathRecord>, table<string, RegionMapPathRecord[]>, table<string, RegionMapPathRecord[]>
    local function Add(list, id, row)
        list[id] = list[id] or {}
        list[id][#list[id] + 1] = row
    end
    for id, row in pairs(R.PathsTable()) do
        if R.IsValidPathFields(row) then
            local map, a, b = locations.byId[row.mapId], locations.byId[row.aId], locations.byId[row.bId]
            if map ~= nil and a ~= nil and b ~= nil and a.parentId == row.mapId and b.parentId == row.mapId
                and Model.IsPointCrawl(map) then
                byId[id] = row
                Add(onMap, row.mapId, row)
                Add(ofLocation, row.aId, row)
                Add(ofLocation, row.bId, row)
            end
        end
    end
    -- A stable order, so lines draw the same way on every client.
    local function Before(x, y) return x.id < y.id end
    for _, list in pairs(onMap) do table.sort(list, Before) end
    for _, list in pairs(ofLocation) do table.sort(list, Before) end
    cached = { byId = byId, onMap = onMap, ofLocation = ofLocation }
    cachedKey, cachedLocations = key, locations
    return cached
end
local Index = RegionMapPaths.Index

-- Visibility (H1, Q28) ------------------------------------------------------------------------------

--- Whether the viewer sees a path. The Director sees every path on a map they
--- can open; a player (or View as player) only a revealed path whose two ends
--- they can both see, so a path never gives away a hidden place.
--- @param path nil|RegionMapPathRecord
--- @return boolean
function RegionMapPaths.CanSee(path)
    if path == nil then return false end
    local map = Model.GetLocation(path.mapId)
    if map == nil or not Model.CanOpenMap(map) then return false end
    if Model.IsDirector() then return true end
    if path.visibility ~= "revealed" then return false end
    return Model.CanSeePin(Model.GetLocation(path.aId)) and Model.CanSeePin(Model.GetLocation(path.bId))
end
local CanSee = RegionMapPaths.CanSee

--- A path the viewer may see, or nil.
--- @param id any
--- @return nil|RegionMapPathRecord
function RegionMapPaths.Get(id)
    if type(id) ~= "string" then return nil end
    local path = Index().byId[id]
    if not CanSee(path) then return nil end
    return path
end

local function Visible(list)
    local result = {} --- @type RegionMapPathRecord[]
    for _, path in ipairs(list or {}) do
        if CanSee(path) then result[#result + 1] = path end
    end
    return result
end

--- The paths on a map the viewer sees.
--- @param mapId string
--- @return RegionMapPathRecord[]
function RegionMapPaths.Paths(mapId)
    return Visible(Index().onMap[mapId])
end

--- The paths with an end at a Location that the viewer sees.
--- @param locationId string
--- @return RegionMapPathRecord[]
function RegionMapPaths.PathsOf(locationId)
    return Visible(Index().ofLocation[locationId])
end

--- How many paths already join two pins, either way round (Q9 bows a new one out).
--- @param aId string
--- @param bId string
--- @return integer
function RegionMapPaths.CountJoining(aId, bId)
    local count = 0
    for _, path in ipairs(Index().ofLocation[aId] or {}) do
        if (path.aId == aId and path.bId == bId) or (path.aId == bId and path.bId == aId) then count = count + 1 end
    end
    return count
end

--- The state of this client's last write of a path, for the edit form's
--- Saving / Saved / Not saved line.
--- @param id string
--- @return nil|"pending"|"confirmed"|"failed"
function RegionMapPaths.SaveStatus(id)
    local operation = R.LastWrite(C.pathTableName, id)
    return operation ~= nil and operation.status or nil
end

--- The path's line from a through its bends to b, in image units. Not filtered:
--- callers pass a path the viewer may use.
--- @param path RegionMapPathRecord
--- @return RegionMapRoutePoint[] empty when an end is missing
function RegionMapPaths.Points(path)
    local locations = Model.Index().byId
    local a, b = locations[path.aId], locations[path.bId]
    if a == nil or b == nil then return {} end
    local points = { { u = a.u, v = a.v } } --- @type RegionMapRoutePoint[]
    for _, bend in ipairs(path.bends) do points[#points + 1] = { u = bend.u, v = bend.v } end
    points[#points + 1] = { u = b.u, v = b.v }
    return points
end

--- The two ends of a path as the viewer may see them.
--- @param path RegionMapPathRecord
--- @return nil|RegionMapLocationRecord a, nil|RegionMapLocationRecord b
function RegionMapPaths.Ends(path)
    return Model.GetLocation(path.aId), Model.GetLocation(path.bId)
end

-- Path types and the time unit (C3, C4, C9) ----------------------------------------------------------

local function ValidType(item)
    return type(item) == "table" and type(item.id) == "string" and item.id ~= "" and #item.id <= C.pathTypeIdLimit
        and R.ValidText(item.name) and patterns[item.pattern] == true and colors[item.color] == true
        and widths[item.width] == true
end

-- The starter set (C4), named from the copy so a game that never edits types reads in its language.
local function StarterTypes()
    local result = {} --- @type RegionMapPathType[]
    for _, starter in ipairs(C.starterPathTypes) do
        result[#result + 1] = {
            id = starter.id, name = RegionMapCopy.T("type." .. starter.id, nil, true),
            pattern = starter.pattern, color = starter.color, width = starter.width,
        }
    end
    return result
end

--- The game's path types in their list order. The starter set until the
--- Director first edits one; nothing is written before that.
--- @return RegionMapPathType[]
function RegionMapPaths.Types()
    local data = R.StateData()
    local stored = data and data.pathTypes
    if type(stored) ~= "table" then return StarterTypes() end
    local result, seen = {}, {} --- @type RegionMapPathType[], table<string, boolean>
    for _, item in ipairs(stored) do
        if ValidType(item) and not seen[item.id] then
            seen[item.id] = true
            result[#result + 1] = {
                id = item.id, name = item.name, pattern = item.pattern, color = item.color, width = item.width,
            }
        end
    end
    return result
end
local Types = RegionMapPaths.Types

--- @param id any
--- @return nil|RegionMapPathType
function RegionMapPaths.TypeById(id)
    for _, item in ipairs(Types()) do
        if item.id == id then return item end
    end
    return nil
end
local TypeById = RegionMapPaths.TypeById

-- Write the whole type list as one undoable change.
local function WriteTypes(list, description)
    for _, item in ipairs(list) do
        if not ValidType(item) then return false, "invalid", nil end
    end
    if #list > C.pathTypeLimit then return false, "limit", nil end
    local step = Model.WriteStateKey("pathTypes", list, description)
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry(description, { step })
end

--- Change one type's name or look.
--- @param id string
--- @param changes {name: nil|string, pattern: nil|string, color: nil|string, width: nil|string}
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapPaths.UpdateType(id, changes)
    if not Model.IsDirector() then return false, "permission", nil end
    local list = Types()
    local changed = false
    for _, item in ipairs(list) do
        if item.id == id then
            for key, value in pairs(changes) do
                if key == "name" then value = R.TrimSingleLine(value) end
                if item[key] ~= value then
                    item[key] = value
                    changed = true
                end
            end
        end
    end
    if not changed then return true, nil, nil end
    return WriteTypes(list, "Change path type")
end

--- Add a type at the end of the list, Solid and Parchment until edited.
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
--- @return nil|string id
function RegionMapPaths.AddType()
    if not Model.IsDirector() then return false, "permission", nil, nil end
    local list = Types()
    local id = dmhub.GenerateGuid()
    list[#list + 1] = {
        id = id, name = RegionMapCopy.T("set.pathType.newName", nil, true),
        pattern = "solid", color = "parchment", width = "normal",
    }
    local ok, reason, entry = WriteTypes(list, "Add path type")
    return ok, reason, entry, ok and id or nil
end

--- Delete a type. Paths that use it keep its id and draw as "No type" (N3), so
--- undoing the delete gives them their look back.
--- @param id string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapPaths.DeleteType(id)
    if not Model.IsDirector() then return false, "permission", nil end
    local list = {} --- @type RegionMapPathType[]
    for _, item in ipairs(Types()) do
        if item.id ~= id then list[#list + 1] = item end
    end
    return WriteTypes(list, "Delete path type")
end

--- How many paths in the game use a type (any map, hidden ones too).
--- @param typeId string
--- @return integer
function RegionMapPaths.CountUsing(typeId)
    local count = 0
    for _, path in pairs(Index().byId) do
        if path.typeId == typeId then count = count + 1 end
    end
    return count
end

--- Another type that draws exactly like this one (pattern and width), for the
--- Q3 warning; colour alone does not tell lines apart.
--- @param item RegionMapPathType
--- @return nil|RegionMapPathType
function RegionMapPaths.SameLook(item)
    for _, other in ipairs(Types()) do
        if other.id ~= item.id and other.pattern == item.pattern and other.width == item.width then return other end
    end
    return nil
end

--- Game-wide: the unit travel times show in (C9).
--- @return "days"|"watches"
function RegionMapPaths.TimeUnit()
    local data = R.StateData()
    local unit = data and data.timeUnit
    if units[unit] then return unit --[[@as "days"|"watches"]] end
    return C.defaultTimeUnit --[[@as "days"|"watches"]]
end
local TimeUnit = RegionMapPaths.TimeUnit

--- @param unit "days"|"watches"
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapPaths.SetTimeUnit(unit)
    if not Model.IsDirector() then return false, "permission", nil end
    if not units[unit] then return false, "invalid", nil end
    if TimeUnit() == unit then return true, nil, nil end
    local description = "Change travel time unit"
    local step = Model.WriteStateKey("timeUnit", unit, description)
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry(description, { step })
end

-- Time wording (manifest section 22) ----------------------------------------------------------------

-- A count for the copy: one decimal at most, and a whole number as an integer so it
-- prints "2", not "2.0", and 1 picks the singular.
local function Count(value)
    local rounded = math.floor(value * 10 + 0.5) / 10
    if rounded % 1 == 0 then return math.tointeger(rounded) or rounded end
    return rounded
end

--- A stored time in the game's unit: "2 days", "1 day and 2 watches", "3 watches".
--- @param watches number
--- @return string
function RegionMapPaths.FormatTime(watches)
    if not IsFinite(watches) or watches <= 0 then return T("time.none") end
    if TimeUnit() == "watches" then return T("time.watches", { count = Count(watches) }) end
    local days = math.floor(watches / C.watchesPerDay + 1e-9)
    local rest = watches - days * C.watchesPerDay
    if rest < 0.05 then return T("time.days", { count = days }) end
    if days == 0 then return T("time.watches", { count = Count(rest) }) end
    return T("time.daysWatches", {
        days = T("time.days", { count = days }), watches = T("time.watches", { count = Count(rest) }),
    })
end
local FormatTime = RegionMapPaths.FormatTime

local function EndName(location)
    if location == nil then return "" end
    return Model.DisplayName(location)
end

--- The name a path shows: its own, else its type's, else "".
--- @param path RegionMapPathRecord
--- @return string plain text
function RegionMapPaths.DisplayName(path)
    if path.name ~= "" then return path.name end
    local item = TypeById(path.typeId)
    return item ~= nil and item.name or ""
end

--- The side panel title (manifest section 21).
--- @param path RegionMapPathRecord
--- @param raw nil|boolean plain text for toast arguments, which escape it themselves
--- @return string
function RegionMapPaths.Title(path, raw)
    if path.name ~= "" then return raw and path.name or RegionMapCopy.Literal(path.name) end
    local a, b = RegionMapPaths.Ends(path)
    local item = TypeById(path.typeId)
    if item ~= nil then
        return RegionMapCopy.T("path.title.unnamed", { type = item.name, a = EndName(a), b = EndName(b) }, raw)
    end
    return RegionMapCopy.T("path.title.noType", { a = EndName(a), b = EndName(b) }, raw)
end

--- The label on the map: name and time (F3, Q11).
--- @param path RegionMapPathRecord
--- @return string
function RegionMapPaths.Label(path)
    local name = RegionMapPaths.DisplayName(path)
    if name == "" then name = RegionMapCopy.T("path.type.none", nil, true) end
    return T("path.label", { path = name, time = FormatTime(path.time) })
end

--- The travel time each way, for the read panel (W2).
--- @param path RegionMapPathRecord
--- @return string
function RegionMapPaths.TimeText(path)
    local a, b = RegionMapPaths.Ends(path)
    local args = { time = FormatTime(path.time), a = EndName(a), b = EndName(b), backTime = FormatTime(path.backTime) }
    if path.back == "none" then return T("path.time.oneWay", args) end
    if path.back == "different" and path.backTime ~= path.time then return T("path.time.both", args) end
    return T("path.time", args)
end

-- Writes (H3: Director only) -------------------------------------------------------------------------

-- Upload one path row built from current (nil to create) plus changes; the undo step or nil.
local function WritePath(current, changes, description, callbacks)
    local record = current and DeepCopy(current) or RegionMapPathRecord.new { revision = 0 }
    for key, value in pairs(changes) do record[key] = value end
    local revision = R.NextRevision(record)
    if revision == nil then return nil end
    record.revision = revision
    R.Audit(record, current == nil)
    local function Finish(callback)
        return function(write)
            Model.InvalidateIndex()
            if callback ~= nil then callback(write) end
        end
    end
    local operation = R.UploadRecord(C.pathTableName, record, description, {
        success = Finish(callbacks and callbacks.success), failure = Finish(callbacks and callbacks.failure),
    }, current == nil)
    if operation == nil then return nil end
    Model.InvalidateIndex()
    return {
        tableName = C.pathTableName, id = record.id,
        before = current and DeepCopy(current) or nil,
        afterRevision = revision, afterMutationId = record.mutationId,
    } --[[@as RegionMapUndoStep]]
end

local function CopyBends(bends)
    if type(bends) ~= "table" or #bends > C.pathBendLimit then return nil end
    local result = {} --- @type RegionMapBend[]
    for _, bend in ipairs(bends) do
        if type(bend) ~= "table" or not IsFinite(bend.u) or not IsFinite(bend.v) then return nil end
        result[#result + 1] = { u = R.Clamp(bend.u, 0, 1), v = R.Clamp(bend.v, 0, 1) }
    end
    return result
end

-- Validates and normalizes path fields; nil when any is invalid.
local function NormalizeFields(fields)
    local result = {}
    for key, value in pairs(fields) do
        if key == "name" then
            value = R.TrimSingleLine(value)
            if not R.ValidName(value) then return nil end
        elseif key == "typeId" then
            if type(value) ~= "string" or #value > C.pathTypeIdLimit then return nil end
        elseif key == "time" or key == "backTime" then
            if not R.ValidTime(value) then return nil end
        elseif key == "back" then
            if not R.pathBacks[value] then return nil end
        elseif key == "description" then
            value = R.NormalizeMultiline(value, C.descriptionLimit, C.descriptionByteLimit)
            if value == nil then return nil end
        elseif key == "note" then
            value = R.NormalizeMultiline(value, C.noteLimit, C.noteByteLimit)
            if value == nil then return nil end
        elseif key == "visibility" then
            if not R.visibilities[value] then return nil end
        elseif key == "bends" then
            value = CopyBends(value)
            if value == nil then return nil end
        else
            -- mapId and the ends change only by making a new path.
            return nil
        end
        result[key] = value
    end
    return result
end

--- Fields a new path may start with; the rest take their defaults.
--- @class RegionMapPathFields
--- @field name nil|string
--- @field typeId nil|string
--- @field time nil|number watches
--- @field back nil|"same"|"different"|"none"
--- @field backTime nil|number
--- @field description nil|string
--- @field note nil|string
--- @field visibility nil|"hidden"|"revealed"
--- @field bends nil|RegionMapBend[]

--- Create a path between two pins of a point crawl map. New paths start
--- revealed (W3); players still see one only once both ends are revealed.
--- @param mapId string
--- @param aId string
--- @param bId string
--- @param fields nil|RegionMapPathFields
--- @param callbacks nil|RegionMapWriteCallbacks the new row is readable only after success
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
--- @return nil|string id
function RegionMapPaths.CreatePath(mapId, aId, bId, fields, callbacks)
    if mod.unloaded or not Model.IsDirector() then return false, "permission", nil, nil end
    local map, a, b = Model.GetLocation(mapId), Model.GetLocation(aId), Model.GetLocation(bId)
    if map == nil or not Model.IsPointCrawl(map) or a == nil or b == nil or aId == bId
        or a.parentId ~= mapId or b.parentId ~= mapId then
        return false, "invalid", nil, nil
    end
    local normalized = NormalizeFields(fields or {})
    if normalized == nil then return false, "invalid", nil, nil end
    local record = {
        id = dmhub.GenerateGuid(), schemaVersion = C.pathSchemaVersion, mapId = mapId, aId = aId, bId = bId,
        bends = {}, name = "", typeId = "", time = C.watchesPerDay, back = "same", backTime = C.watchesPerDay,
        description = "", note = "", visibility = "revealed", hidden = false,
    }
    for key, value in pairs(normalized) do record[key] = value end
    local description = "Add region map path"
    local step = WritePath(nil, record, description, callbacks)
    if step == nil then return false, "unavailable", nil, nil end
    return true, nil, Entry(description, { step }), record.id
end

--- Change fields of a path.
--- @param id string
--- @param changes RegionMapPathFields
--- @param description nil|string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapPaths.UpdatePath(id, changes, description)
    local current = RegionMapPaths.Get(id)
    if current == nil then return false, "invalid", nil end
    if mod.unloaded or not Model.IsDirector() then return false, "permission", nil end
    if R.PendingWrite(C.pathTableName, id) then return false, "busy", nil end
    local normalized = NormalizeFields(changes)
    if normalized == nil then return false, "invalid", nil end
    description = description or "Edit region map path"
    local step = WritePath(current, normalized, description)
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry(description, { step })
end

--- @param id string
--- @param visibility "hidden"|"revealed"
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapPaths.SetVisibility(id, visibility)
    return RegionMapPaths.UpdatePath(id, { visibility = visibility }, "Change path visibility")
end

--- @param id string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapPaths.DeletePath(id)
    local current = RegionMapPaths.Get(id)
    if current == nil then return false, "invalid", nil end
    if mod.unloaded or not Model.IsDirector() then return false, "permission", nil end
    if R.PendingWrite(C.pathTableName, id) then return false, "busy", nil end
    local description = "Delete region map path"
    -- A Party stopped on the path goes to its nearer end in the same undo entry (Q13).
    local partyTarget = Model.PartyOffPaths({ current }, {})
    local step = WritePath(current, { hidden = true }, description)
    if step == nil then return false, "unavailable", nil end
    local steps = { step }
    local partyStep = partyTarget ~= nil and Model.MovePartyOff(partyTarget, description) or nil
    if partyStep ~= nil then steps[2] = partyStep end
    return true, nil, Entry(description, steps)
end

-- Cascades (B5): the model removes these with the pins they join ------------------------------------

--- Every path (not filtered for the viewer) with an end among the given Location ids.
--- @param removed table<string, boolean>
--- @return RegionMapPathRecord[]
function RegionMapPaths.Touching(removed)
    local result = {} --- @type RegionMapPathRecord[]
    for _, path in pairs(Index().byId) do
        if removed[path.aId] or removed[path.bId] then result[#result + 1] = path end
    end
    table.sort(result, function(x, y) return x.id < y.id end)
    return result
end

--- How many of these paths the viewer sees, for a confirm's count.
--- @param paths RegionMapPathRecord[]
--- @return integer
function RegionMapPaths.CountVisible(paths)
    local count = 0
    for _, path in ipairs(paths) do
        if CanSee(path) then count = count + 1 end
    end
    return count
end

--- True when any of these paths still has a write in flight; a batch must not go half done.
--- @param paths RegionMapPathRecord[]
--- @return boolean
function RegionMapPaths.AnyPending(paths)
    for _, path in ipairs(paths) do
        if R.PendingWrite(C.pathTableName, path.id) then return true end
    end
    return false
end

--- Hide these paths in the caller's batch; the undo steps that started.
--- @param paths RegionMapPathRecord[]
--- @param description string
--- @return RegionMapUndoStep[]
function RegionMapPaths.HideSteps(paths, description)
    local steps = {} --- @type RegionMapUndoStep[]
    for _, path in ipairs(paths) do
        local step = WritePath(path, { hidden = true }, description)
        if step ~= nil then steps[#steps + 1] = step end
    end
    return steps
end
