local mod = dmhub.GetModLoading()

--- Point crawl paths (V2.1): which paths each viewer sees (H1), the Director's
--- path writes (H3), the cascades the model runs when pins go (B5), the
--- game-wide path types and travel time unit (C3, C9), and time wording.
--- The UI never reads the paths table directly; it calls these.
--- @class OverlandMapPaths: GameType
--- @field new fun(o?: table): OverlandMapPaths
OverlandMapPaths = RegisterGameType("OverlandMapPaths")
local C = OverlandMapConstants
local R = OverlandMapRecords
local Model = OverlandMapModel

local IsFinite = R.IsFinite

--- One path type (C3): its name and how its line draws.
--- @class OverlandMapPathType
--- @field id string
--- @field name string
--- @field pattern "solid"|"dashed"|"dotted"|"double"|"dashDot"|"longDash"
--- @field color string a key of C.pathColors
--- @field width "thin"|"normal"|"thick"

--- Every path whose ends are pins on its point crawl map. Not filtered for the viewer.
--- @class OverlandMapPathIndex
--- @field byId table<string, OverlandMapPathRecord>
--- @field onMap table<string, OverlandMapPathRecord[]>
--- @field ofLocation table<string, OverlandMapPathRecord[]>

local patterns, widths, colors = R.SetOf(C.pathPatterns), R.SetOf(C.pathWidthOrder), R.SetOf(C.pathColorOrder)
local units = R.SetOf(C.pathTimeUnits)

local function T(id, args) return OverlandMapCopy.T(id, args) end

local function Entry(description, steps)
    return { description = description, steps = steps } --[[@as OverlandMapUndoEntry]]
end

-- Index ------------------------------------------------------------------------------------------

local cached = nil --- @type nil|OverlandMapPathIndex
local cachedRevision = nil --- @type nil|integer
local cachedLocations = nil --- @type nil|OverlandMapLocationIndex

--- The validated paths, rebuilt only when the data changed (Model.Revision; this
--- client's own path writes call Model.InvalidateIndex). Deleting or moving a pin
--- hides its paths too (B5); a path whose end is gone anyway is skipped here.
--- @return OverlandMapPathIndex
function OverlandMapPaths.Index()
    local locations = Model.Index()
    local key = Model.Revision()
    if cached ~= nil and cachedRevision == key and cachedLocations == locations then return cached end
    local byId, onMap, ofLocation = {}, {}, {} --- @type table<string, OverlandMapPathRecord>, table<string, OverlandMapPathRecord[]>, table<string, OverlandMapPathRecord[]>
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
    cachedRevision, cachedLocations = key, locations
    return cached
end
local Index = OverlandMapPaths.Index

-- Visibility (H1, Q28) ------------------------------------------------------------------------------

--- Whether the viewer sees a path. The Director sees every path on a map they
--- can open; a player (or View as player) only a revealed path whose two ends
--- they can both see, so a path never gives away a hidden place.
--- @param path nil|OverlandMapPathRecord
--- @return boolean
function OverlandMapPaths.CanSee(path)
    if path == nil then return false end
    local map = Model.GetLocation(path.mapId)
    if map == nil or not Model.CanOpenMap(map) then return false end
    if Model.IsDirector() then return true end
    if path.visibility ~= "revealed" then return false end
    return Model.CanSeePin(Model.GetLocation(path.aId)) and Model.CanSeePin(Model.GetLocation(path.bId))
end
local CanSee = OverlandMapPaths.CanSee

--- A path the viewer may see, or nil.
--- @param id any
--- @return nil|OverlandMapPathRecord
function OverlandMapPaths.Get(id)
    if type(id) ~= "string" then return nil end
    local path = Index().byId[id]
    if not CanSee(path) then return nil end
    return path
end

local function Visible(list)
    local result = {} --- @type OverlandMapPathRecord[]
    for _, path in ipairs(list or {}) do
        if CanSee(path) then result[#result + 1] = path end
    end
    return result
end

--- The paths on a map the viewer sees.
--- @param mapId string
--- @return OverlandMapPathRecord[]
function OverlandMapPaths.Paths(mapId)
    return Visible(Index().onMap[mapId])
end

--- The paths with an end at a Location that the viewer sees.
--- @param locationId string
--- @return OverlandMapPathRecord[]
function OverlandMapPaths.PathsOf(locationId)
    return Visible(Index().ofLocation[locationId])
end

--- How many paths already join two pins, either way round (Q9 bows a new one out).
--- @param aId string
--- @param bId string
--- @return integer
function OverlandMapPaths.CountJoining(aId, bId)
    local count = 0
    for _, path in ipairs(Index().ofLocation[aId] or {}) do
        if (path.aId == aId and path.bId == bId) or (path.aId == bId and path.bId == aId) then count = count + 1 end
    end
    return count
end

--- The path's line from a through its bends to b, in image units. Not filtered:
--- callers pass a path the viewer may use.
--- @param path OverlandMapPathRecord
--- @return OverlandMapRoutePoint[] empty when an end is missing
function OverlandMapPaths.Points(path)
    local locations = Model.Index().byId
    local a, b = locations[path.aId], locations[path.bId]
    if a == nil or b == nil then return {} end
    local points = { { u = a.u, v = a.v } } --- @type OverlandMapRoutePoint[]
    for _, bend in ipairs(path.bends) do points[#points + 1] = { u = bend.u, v = bend.v } end
    points[#points + 1] = { u = b.u, v = b.v }
    return points
end

--- The two ends of a path as the viewer may see them.
--- @param path OverlandMapPathRecord
--- @return nil|OverlandMapLocationRecord a, nil|OverlandMapLocationRecord b
function OverlandMapPaths.Ends(path)
    return Model.GetLocation(path.aId), Model.GetLocation(path.bId)
end

-- Path types and the time unit (C3, C4, C9) ----------------------------------------------------------

local function ValidType(item)
    return type(item) == "table" and type(item.id) == "string" and item.id ~= "" and #item.id <= C.pathTypeIdLimit
        and R.ValidStoredText(item.name) and patterns[item.pattern] == true and colors[item.color] == true
        and widths[item.width] == true
end

-- The starter set (C4), named from the copy so a game that never edits types reads in its language.
local function StarterTypes()
    local result = {} --- @type OverlandMapPathType[]
    for _, starter in ipairs(C.starterPathTypes) do
        result[#result + 1] = {
            id = starter.id, name = OverlandMapCopy.T("type." .. starter.id, nil, true),
            pattern = starter.pattern, color = starter.color, width = starter.width,
        }
    end
    return result
end

--- The game's path types in their list order. The starter set until the
--- Director first edits one; nothing is written before that.
--- @return OverlandMapPathType[]
function OverlandMapPaths.Types()
    local data = R.StateData()
    local stored = data and data.pathTypes
    if type(stored) ~= "table" then return StarterTypes() end
    local result, seen = {}, {} --- @type OverlandMapPathType[], table<string, boolean>
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
local Types = OverlandMapPaths.Types

--- @param id any
--- @return nil|OverlandMapPathType
function OverlandMapPaths.TypeById(id)
    local data = R.StateData()
    local stored = data and data.pathTypes
    if type(stored) ~= "table" then
        for _, item in ipairs(StarterTypes()) do
            if item.id == id then return item end
        end
        return nil
    end
    -- Same answer as searching Types() (the first valid entry with this id), but only the
    -- matching entry is checked and copied: every drawn path looks its type up.
    for _, item in ipairs(stored) do
        if type(item) == "table" and item.id == id and ValidType(item) then
            return { id = item.id, name = item.name, pattern = item.pattern, color = item.color, width = item.width }
        end
    end
    return nil
end
local TypeById = OverlandMapPaths.TypeById

-- Write the whole type list as one undoable change.
local function WriteTypes(list, description)
    for _, item in ipairs(list) do
        if not ValidType(item) then return false, "invalid", nil end
    end
    local step = Model.WriteStateKey("pathTypes", list, description)
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry(description, { step })
end

--- Change one type's name or look.
--- @param id string
--- @param changes {name: nil|string, pattern: nil|string, color: nil|string, width: nil|string}
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapPaths.UpdateType(id, changes)
    if not Model.IsDirector() then return false, "permission", nil end
    local list = Types()
    local changed = false
    for _, item in ipairs(list) do
        if item.id == id then
            for key, value in pairs(changes) do
                if key == "name" then
                    value = R.TrimSingleLine(value)
                    if not R.ValidText(value) then return false, "invalid", nil end
                end
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
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
--- @return nil|string id
function OverlandMapPaths.AddType()
    if not Model.IsDirector() then return false, "permission", nil, nil end
    local list = Types()
    local id = dmhub.GenerateGuid()
    list[#list + 1] = {
        id = id, name = OverlandMapCopy.T("set.pathType.newName", nil, true),
        pattern = "solid", color = "parchment", width = "normal",
    }
    local ok, reason, entry = WriteTypes(list, "Add path type")
    return ok, reason, entry, ok and id or nil
end

--- Delete a type. Paths that use it keep its id and draw as "No type" (N3), so
--- undoing the delete gives them their look back.
--- @param id string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapPaths.DeleteType(id)
    if not Model.IsDirector() then return false, "permission", nil end
    local list = {} --- @type OverlandMapPathType[]
    for _, item in ipairs(Types()) do
        if item.id ~= id then list[#list + 1] = item end
    end
    return WriteTypes(list, "Delete path type")
end

--- How many paths in the game use a type (any map, hidden ones too).
--- @param typeId string
--- @return integer
function OverlandMapPaths.CountUsing(typeId)
    local count = 0
    for _, path in pairs(Index().byId) do
        if path.typeId == typeId then count = count + 1 end
    end
    return count
end

--- Another type that draws exactly like this one (pattern and width), for the
--- Q3 warning; colour alone does not tell lines apart.
--- @param item OverlandMapPathType
--- @return nil|OverlandMapPathType
function OverlandMapPaths.SameLook(item)
    for _, other in ipairs(Types()) do
        if other.id ~= item.id and other.pattern == item.pattern and other.width == item.width then return other end
    end
    return nil
end

--- Game-wide: the unit travel times show in (C9).
--- @return "days"|"watches"|"custom"
function OverlandMapPaths.TimeUnit()
    local data = R.StateData()
    local unit = data and data.timeUnit
    if units[unit] then return unit --[[@as "days"|"watches"|"custom"]] end
    return C.defaultTimeUnit --[[@as "days"|"watches"|"custom"]]
end
local TimeUnit = OverlandMapPaths.TimeUnit

--- @param unit "days"|"watches"|"custom"
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapPaths.SetTimeUnit(unit)
    if not Model.IsDirector() then return false, "permission", nil end
    if not units[unit] then return false, "invalid", nil end
    if TimeUnit() == unit then return true, nil, nil end
    local description = "Change travel time unit"
    local step = Model.WriteStateKey("timeUnit", unit, description)
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry(description, { step })
end

--- @return table<string, string> forms plain text, with defaults for missing or invalid names
function OverlandMapPaths.CustomTimeUnit()
    local data = R.StateData()
    local stored = data and data.customTimeUnit
    local forms = {}
    for _, key in ipairs({ "singular", "plural" }) do
        local value = type(stored) == "table" and stored[key] or nil
        forms[key] = R.ValidText(value) and value or T("time.custom." .. key)
    end
    return forms
end

--- @param changes table<string, string>
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapPaths.SetCustomTimeUnit(changes)
    if not Model.IsDirector() then return false, "permission", nil end
    if type(changes) ~= "table" then return false, "invalid", nil end
    local forms, changed = OverlandMapPaths.CustomTimeUnit(), false
    for key, value in pairs(changes) do
        if (key ~= "singular" and key ~= "plural") or type(value) ~= "string" then return false, "invalid", nil end
        value = R.TrimSingleLine(value)
        if not R.ValidText(value) then return false, "invalid", nil end
        changed = changed or forms[key] ~= value
        forms[key] = value
    end
    if not changed then return true, nil, nil end
    local description = "Change custom travel time unit"
    local step = Model.WriteStateKey("customTimeUnit", forms, description)
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry(description, { step })
end

--- The plain unit name beside a numeric input; nil uses the plural.
--- @param count nil|number
--- @return string
function OverlandMapPaths.TimeUnitName(count)
    if TimeUnit() ~= "custom" then return T("set.timeUnit." .. TimeUnit()) end
    local forms = OverlandMapPaths.CustomTimeUnit()
    return count == 1 and forms.singular or forms.plural
end

--- Include editable names when a view caches travel-time wording.
--- @return string
function OverlandMapPaths.TimeFormatKey()
    local unit = TimeUnit()
    if unit ~= "custom" then return unit end
    local forms = OverlandMapPaths.CustomTimeUnit()
    return table.concat({ unit, forms.singular, forms.plural }, "\n")
end

-- Time wording (manifest section 22) ----------------------------------------------------------------

-- A count for the copy: one decimal at most, and a whole number as an integer so it
-- prints "2", not "2.0", and 1 picks the singular.
local function Count(value)
    local rounded = math.floor(value * 10 + 0.5) / 10
    if rounded % 1 == 0 then return math.tointeger(rounded) or rounded end
    return rounded
end

--- A stored time in the game's unit, as plain text for copy arguments.
--- @param watches number
--- @return string
function OverlandMapPaths.FormatTime(watches)
    if not IsFinite(watches) or watches <= 0 then return T("time.none") end
    if TimeUnit() == "custom" then
        local count = Count(watches)
        return tostring(count) .. " " .. OverlandMapPaths.TimeUnitName(count)
    end
    if TimeUnit() == "watches" then return T("time.watches", { count = Count(watches) }) end
    local days = math.floor(watches / C.watchesPerDay + 1e-9)
    local rest = watches - days * C.watchesPerDay
    if rest < 0.05 then return T("time.days", { count = days }) end
    if days == 0 then return T("time.watches", { count = Count(rest) }) end
    return T("time.daysWatches", {
        days = T("time.days", { count = days }), watches = T("time.watches", { count = Count(rest) }),
    })
end
local FormatTime = OverlandMapPaths.FormatTime

-- Travel times are stored in watches and typed in the game's unit (C9).
local function UnitFactor()
    return TimeUnit() == "days" and C.watchesPerDay or 1
end

--- A stored time as the number a time field shows: at most two decimals, no
--- trailing zeros (the path form and the stop card).
--- @param watches number
--- @return string
function OverlandMapPaths.TimeInputText(watches)
    local text = string.format("%.2f", watches / UnitFactor())
    text = text:gsub("0+$", ""):gsub("%.$", "")
    return text
end

--- A typed time in watches, or nil when it is no valid time. Accepts a decimal
--- comma; kept to a tenth of a watch, the finest the time wording shows.
--- @param text any
--- @return nil|number watches
function OverlandMapPaths.ParseTime(text)
    local value = tonumber((tostring(text or ""):gsub(",", ".")))
    if not IsFinite(value) or value < 0 then return nil end
    local watches = math.floor(value * UnitFactor() * 10 + 0.5) / 10
    if not R.ValidTime(watches) then return nil end
    return watches
end

--- The end of a path that is not this one.
--- @param path OverlandMapPathRecord
--- @param id string one of its ends
--- @return string
function OverlandMapPaths.OtherEnd(path, id)
    return path.aId == id and path.bId or path.aId
end

local EndName = Model.DisplayName

--- The name a path shows: its own, else its type's, else "".
--- @param path OverlandMapPathRecord
--- @return string plain text
function OverlandMapPaths.DisplayName(path)
    if path.name ~= "" then return path.name end
    local item = TypeById(path.typeId)
    return item ~= nil and item.name or ""
end

--- The side panel title (manifest section 21).
--- @param path OverlandMapPathRecord
--- @param raw nil|boolean plain text for toast arguments, which escape it themselves
--- @return string
function OverlandMapPaths.Title(path, raw)
    if path.name ~= "" then return raw and path.name or OverlandMapCopy.Literal(path.name) end
    local a, b = OverlandMapPaths.Ends(path)
    local item = TypeById(path.typeId)
    if item ~= nil then
        return OverlandMapCopy.T("path.title.unnamed", { type = item.name, a = EndName(a), b = EndName(b) }, raw)
    end
    return OverlandMapCopy.T("path.title.noType", { a = EndName(a), b = EndName(b) }, raw)
end

--- The name a path goes by in rows, menus, toasts and its map label: its own,
--- its type's, else "No type".
--- @param path OverlandMapPathRecord
--- @return string plain text
function OverlandMapPaths.ShownName(path)
    local name = OverlandMapPaths.DisplayName(path)
    if name == "" then name = OverlandMapCopy.T("path.type.none", nil, true) end
    return name
end

--- The label on the map: name and time (F3, Q11).
--- @param path OverlandMapPathRecord
--- @return string
function OverlandMapPaths.Label(path)
    return T("path.label", { path = OverlandMapPaths.ShownName(path), time = FormatTime(path.time) })
end

--- The travel time each way, for the read panel (W2).
--- @param path OverlandMapPathRecord
--- @return string
function OverlandMapPaths.TimeText(path)
    local a, b = OverlandMapPaths.Ends(path)
    local args = { time = FormatTime(path.time), a = EndName(a), b = EndName(b), backTime = FormatTime(path.backTime) }
    if path.back == "none" then return T("path.time.oneWay", args) end
    if path.back == "different" and path.backTime ~= path.time then return T("path.time.both", args) end
    return T("path.time", args)
end

-- Writes (H3: Director only) -------------------------------------------------------------------------

-- Upload one path row built from current (nil to create) plus changes; the undo step or nil.
local function WritePath(current, changes, description, callbacks, retry)
    local record = current and DeepCopy(current) or OverlandMapPathRecord.new { revision = 0, artworkImageId = "" }
    for key, value in pairs(changes) do record[key] = value end
    return R.WriteRow(C.pathTableName, current, record, description, callbacks, { retry = retry })
end

local function CopyBends(bends)
    if type(bends) ~= "table" or #bends > C.pathBendLimit then return nil end
    local result = {} --- @type OverlandMapBend[]
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
        elseif key == "artworkImageId" then
            if not R.ValidArtwork(value) then return nil end
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
--- @class OverlandMapPathFields
--- @field name nil|string
--- @field typeId nil|string
--- @field time nil|number watches
--- @field back nil|"same"|"different"|"none"
--- @field backTime nil|number
--- @field description nil|string
--- @field artworkImageId nil|string
--- @field note nil|string
--- @field visibility nil|"hidden"|"revealed"
--- @field bends nil|OverlandMapBend[]

--- Create a path between two pins of a point crawl map. New paths start
--- revealed (W3); players still see one only once both ends are revealed.
--- @param mapId string
--- @param aId string
--- @param bId string
--- @param fields nil|OverlandMapPathFields
--- @param callbacks nil|OverlandMapWriteCallbacks the new row is readable only after success
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
--- @return nil|string id
function OverlandMapPaths.CreatePath(mapId, aId, bId, fields, callbacks)
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
    local description = "Add overland map path"
    local step = WritePath(nil, record, description, callbacks)
    if step == nil then return false, "unavailable", nil, nil end
    return true, nil, Entry(description, { step }), record.id
end

--- Change fields of a path.
--- @param id string
--- @param changes OverlandMapPathFields
--- @param description nil|string
--- @param retry nil|OverlandMapRetry an explicit retry of this client's failed write
--- @param callbacks nil|OverlandMapWriteCallbacks
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
--- @return nil|OverlandMapWrite receipt
function OverlandMapPaths.UpdatePath(id, changes, description, retry, callbacks)
    local current = OverlandMapPaths.Get(id)
    if current == nil then return false, "invalid", nil end
    if mod.unloaded or not Model.IsDirector() then return false, "permission", nil end
    if R.PendingWrite(C.pathTableName, id) then return false, "busy", nil end
    local normalized = NormalizeFields(changes)
    if normalized == nil then return false, "invalid", nil end
    if not R.CanRetryWrite(C.pathTableName, current, retry) then
        for key, value in pairs(normalized) do
            local previous = key == "artworkImageId" and R.ArtworkValue(current) or R.Field(current, key, nil)
            if dmhub.DeepEqual(previous, value) then normalized[key] = nil end
        end
    end
    if next(normalized) == nil then return true, nil, nil end
    description = description or "Edit overland map path"
    local step, operation = WritePath(current, normalized, description, callbacks, retry)
    if step == nil then return false, "unavailable", nil, operation end
    return true, nil, Entry(description, { step }), operation
end

--- @param id string
--- @param visibility "hidden"|"revealed"
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapPaths.SetVisibility(id, visibility)
    return OverlandMapPaths.UpdatePath(id, { visibility = visibility }, "Change path visibility")
end

--- @param id string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapPaths.DeletePath(id)
    local current = OverlandMapPaths.Get(id)
    if current == nil then return false, "invalid", nil end
    if mod.unloaded or not Model.IsDirector() then return false, "permission", nil end
    if R.PendingWrite(C.pathTableName, id) then return false, "busy", nil end
    local description = "Delete overland map path"
    -- A Party stopped on the path goes to its nearer end in the same undo entry (Q13).
    local partyTarget = Model.PartyOffPaths({ current }, {})
    local step = WritePath(current, { hidden = true }, description)
    if step == nil then return false, "unavailable", nil end
    local entry = Entry(description, { step })
    if partyTarget ~= nil then
        OverlandMapCommands.Append(entry, Model.MovePartyOff(partyTarget, description), nil, C.stateDocumentId)
    end
    return true, nil, entry
end

-- Cascades (B5): the model removes these with the pins they join ------------------------------------

--- Every path (not filtered for the viewer) with an end among the given Location ids.
--- @param removed table<string, boolean>
--- @return OverlandMapPathRecord[]
function OverlandMapPaths.Touching(removed)
    local result = {} --- @type OverlandMapPathRecord[]
    for _, path in pairs(Index().byId) do
        if removed[path.aId] or removed[path.bId] then result[#result + 1] = path end
    end
    table.sort(result, function(x, y) return x.id < y.id end)
    return result
end

--- How many of these paths the viewer sees, for a confirm's count.
--- @param paths OverlandMapPathRecord[]
--- @return integer
function OverlandMapPaths.CountVisible(paths)
    local count = 0
    for _, path in ipairs(paths) do
        if CanSee(path) then count = count + 1 end
    end
    return count
end

--- True when any of these paths still has a write in flight; a batch must not go half done.
--- @param paths OverlandMapPathRecord[]
--- @return boolean
function OverlandMapPaths.AnyPending(paths)
    for _, path in ipairs(paths) do
        if R.PendingWrite(C.pathTableName, path.id) then return true end
    end
    return false
end

--- Hide these paths in the caller's batch; retain refused uploads separately from Undo steps.
--- @param paths OverlandMapPathRecord[]
--- @param description string
--- @return OverlandMapUndoStep[]
--- @return table[] operations
function OverlandMapPaths.HideSteps(paths, description)
    local entry = Entry(description, {})
    for _, path in ipairs(paths) do
        local step = WritePath(path, { hidden = true }, description)
        OverlandMapCommands.Append(entry, step, C.pathTableName, path.id)
    end
    return entry.steps, entry.operations or {}
end
