local mod = dmhub.GetModLoading()

--- Data access and permission rules for Region Map. The UI never reads the
--- Region Map tables directly; it calls the functions on this namespace.
--- @class RegionMapModel: GameType
--- @field new fun(o?: table): RegionMapModel
RegionMapModel = RegisterGameType("RegionMapModel")
local C = RegionMapConstants
local R = RegionMapRecords
local Journal = RegionMapJournal

local Clamp = R.Clamp
local IsFinite = R.IsFinite
local Field = R.Field
local ValidText = R.ValidText
local NextRevision = R.NextRevision
local Audit = R.Audit
local UploadRecord = R.UploadRecord
local PendingWrite = R.PendingWrite
local LastWrite = R.LastWrite
local StateDocument = R.StateDocument
local StateData = R.StateData
local CurrentUserName = R.CurrentUserName
local NormalizeMultiline = R.NormalizeMultiline
local SidecarSpec = R.SidecarSpec
local ReadSidecar = R.ReadSidecar

-- Utilities the UI shares with the model.
RegionMapModel.Clamp = Clamp
RegionMapModel.IsFinite = IsFinite
RegionMapModel.IsPositiveInteger = R.IsPositiveInteger
RegionMapModel.Field = Field
RegionMapModel.TrimSingleLine = R.TrimSingleLine
RegionMapModel.TextLength = R.TextLength
RegionMapModel.ValidText = ValidText

--- Escape rich-text markup in user text before it reaches a label.
--- @param value any
--- @return string
function RegionMapModel.LiteralText(value)
    -- Escape each opening bracket separately, including literal closing noparse tags.
    return (tostring(value or ""):gsub("<", "<noparse><</noparse>"))
end

--- @return string
function RegionMapModel.StatePath()
    return StateDocument().path
end

local function CanCommit(guard)
    return not mod.unloaded and (guard == nil or guard())
end

-- The Location tree --------------------------------------------------------------------------

--- Every valid Location, validated once and grouped by parent. Not filtered
--- for the viewer.
--- @class RegionMapLocationIndex
--- @field byId table<string, RegionMapLocationRecord>
--- @field childrenOf table<string, RegionMapLocationRecord[]> sorted by name; "" holds the top level

--- One reversible part of a model write. Table steps restore a row; the Party
--- step restores the state document's party. Undo refuses a step whose row
--- changed since (another write), which revision and mutationId detect.
--- @class RegionMapUndoStep
--- @field tableName nil|string
--- @field id nil|string
--- @field before nil|table the row before the write; nil when the write created it
--- @field party nil|table|false the party before a Party write; false = not placed
--- @field afterRevision integer
--- @field afterMutationId string

--- What one user action changed, for RegionMapUndo.
--- @class RegionMapUndoEntry
--- @field description string
--- @field steps RegionMapUndoStep[]

--- The Party as the viewer may know it. At a Location, mapId/u/v follow that pin.
--- @class RegionMapPartyView
--- @field mapId string
--- @field u number
--- @field v number
--- @field locationId nil|string only when the viewer can see that pin
--- @field revision integer

--- @alias RegionMapWriteReason "permission"|"invalid"|"busy"|"limit"|"unavailable"

local Locations = R.LocationsTable
local ValidName = R.ValidName

-- View as player (V2-19): the Director's client answers every visibility
-- question as a player who owns nothing, and refuses writes while it is on.
local viewAsPlayer = false

--- @param on boolean
function RegionMapModel.SetViewAsPlayer(on)
    viewAsPlayer = on == true and dmhub.isDM
end

--- @return boolean
function RegionMapModel.ViewingAsPlayer()
    return viewAsPlayer
end

--- True when the viewer gets Director rights (a Director not viewing as player).
--- @return boolean
function RegionMapModel.IsDirector()
    return dmhub.isDM and not viewAsPlayer
end
local IsDirector = RegionMapModel.IsDirector

local function ViewerId()
    if viewAsPlayer then return "" end
    return dmhub.loginUserid
end

local function CanWrite()
    return not mod.unloaded and not viewAsPlayer
end

-- Index ------------------------------------------------------------------------------------

local cachedIndex = nil --- @type nil|RegionMapLocationIndex
local cachedKey = nil --- @type nil|string

-- Changes whenever cloud data arrives; this client's own writes call InvalidateIndex.
local function IndexKey()
    return tostring(dmhub.ngameupdate) .. ":" .. tostring(dmhub.tablesUpdateId)
end

--- Drop the cached index so the next question rebuilds it.
function RegionMapModel.InvalidateIndex()
    cachedIndex = nil
end
local InvalidateIndex = RegionMapModel.InvalidateIndex

local function NameKey(location)
    return R.MapNameKey(location.name)
end

--- The validated Location tree, rebuilt only when the data changed.
--- @return RegionMapLocationIndex
function RegionMapModel.Index()
    local key = IndexKey()
    if cachedIndex ~= nil and cachedKey == key then return cachedIndex end
    local candidates = {} --- @type table<string, RegionMapLocationRecord>
    for id, row in pairs(Locations()) do
        if R.IsValidLocationFields(row) then candidates[id] = row end
    end
    local byId, childrenOf, keys = {}, { [""] = {} }, {}
    for id, row in pairs(candidates) do
        if R.IsValidLocation(row, candidates) then
            byId[id] = row
            keys[id] = NameKey(row)
            local list = childrenOf[row.parentId]
            if list == nil then
                list = {}
                childrenOf[row.parentId] = list
            end
            list[#list + 1] = row
        end
    end
    local function Before(a, b)
        if keys[a.id] ~= keys[b.id] then return keys[a.id] < keys[b.id] end
        return a.id < b.id
    end
    for _, list in pairs(childrenOf) do table.sort(list, Before) end
    cachedIndex = { byId = byId, childrenOf = childrenOf }
    cachedKey = key
    return cachedIndex
end
local Index = RegionMapModel.Index

-- A valid Location with no viewer filter. Internal: public reads filter.
local function Raw(id)
    if type(id) ~= "string" then return nil end
    return Index().byId[id]
end

-- Visibility rules (D9, R4) ---------------------------------------------------------------

--- Whether the viewer may open a Location's map. Director: any map. Player: a
--- shared map whose own pin they can see (top-level maps have no pin).
--- @param location nil|RegionMapLocationRecord
--- @return boolean
function RegionMapModel.CanOpenMap(location)
    if location == nil or location.imageId == "" then return false end
    if IsDirector() then return true end
    if not location.mapShared then return false end
    return location.parentId == "" or RegionMapModel.CanSeePin(location)
end
local CanOpenMap = RegionMapModel.CanOpenMap

--- Whether the viewer sees a Location's pin on its parent's map.
--- @param location nil|RegionMapLocationRecord
--- @return boolean
function RegionMapModel.CanSeePin(location)
    if location == nil or location.parentId == "" then return false end
    if IsDirector() then return true end
    return location.visibility == "revealed" and CanOpenMap(Raw(location.parentId))
end
local CanSeePin = RegionMapModel.CanSeePin

-- A pin the viewer sees, or a top-level map they may open.
local function CanSee(location)
    if location == nil then return false end
    if location.parentId == "" then return CanOpenMap(location) end
    return CanSeePin(location)
end

--- @param location nil|RegionMapLocationRecord
--- @return boolean
function RegionMapModel.CanEdit(location)
    if not CanWrite() or not CanSee(location) then return false end
    return IsDirector() or (location ~= nil and location.ownerId == ViewerId())
end
local CanEdit = RegionMapModel.CanEdit

--- A Location the viewer may see, or nil. Never returns a Hidden pin or an
--- unshared map to a player.
--- @param id any
--- @return nil|RegionMapLocationRecord
function RegionMapModel.GetLocation(id)
    local location = Raw(id)
    if not CanSee(location) then return nil end
    return location
end

--- The pins on a map the viewer may see, sorted by name. Empty when the
--- viewer may not open the map.
--- @param mapId string
--- @return RegionMapLocationRecord[]
function RegionMapModel.Children(mapId)
    local result = {} --- @type RegionMapLocationRecord[]
    if not CanOpenMap(Raw(mapId)) then return result end
    for _, child in ipairs(Index().childrenOf[mapId] or {}) do
        if CanSeePin(child) then result[#result + 1] = child end
    end
    return result
end
local Children = RegionMapModel.Children

--- Top-level maps the viewer may open, sorted by name (the Atlas).
--- @return RegionMapLocationRecord[]
function RegionMapModel.TopLevel()
    local result = {} --- @type RegionMapLocationRecord[]
    for _, location in ipairs(Index().childrenOf[""]) do
        if CanOpenMap(location) then result[#result + 1] = location end
    end
    return result
end

--- Every map the viewer may open, at any depth, sorted by name ("Move to map...").
--- @return RegionMapLocationRecord[]
function RegionMapModel.OpenableMaps()
    local result, keys = {}, {} --- @type RegionMapLocationRecord[], table<string, string>
    for id, location in pairs(Index().byId) do
        if CanOpenMap(location) then
            result[#result + 1] = location
            keys[id] = NameKey(location)
        end
    end
    table.sort(result, function(a, b)
        if keys[a.id] ~= keys[b.id] then return keys[a.id] < keys[b.id] end
        return a.id < b.id
    end)
    return result
end

--- Locations the viewer can see on any map whose name contains the query
--- (case-folded like the sort key), best first: names that start with the
--- query, then the rest, each by name. Unnamed Locations never match.
--- @param query string
--- @param limit integer
--- @return RegionMapLocationRecord[]
function RegionMapModel.Search(query, limit)
    local needle = R.MapNameKey(R.TrimSingleLine(query))
    local result, rank, keys = {}, {}, {} --- @type RegionMapLocationRecord[], table<string, integer>, table<string, string>
    if needle == "" then return result end
    for id, location in pairs(Index().byId) do
        if location.name ~= "" and CanSee(location) then
            local key = NameKey(location)
            local at = string.find(key, needle, 1, true)
            if at ~= nil then
                result[#result + 1] = location
                rank[id] = at == 1 and 0 or 1
                keys[id] = key
            end
        end
    end
    table.sort(result, function(a, b)
        if rank[a.id] ~= rank[b.id] then return rank[a.id] < rank[b.id] end
        if keys[a.id] ~= keys[b.id] then return keys[a.id] < keys[b.id] end
        return a.id < b.id
    end)
    for i = #result, limit + 1, -1 do result[i] = nil end
    return result
end

--- The path to a Location, root first and the Location itself last, for the
--- breadcrumb. Empty when the viewer may not see it (so a player never gets a
--- level they cannot see).
--- @param id string
--- @return RegionMapLocationRecord[]
function RegionMapModel.Ancestors(id)
    local path = {} --- @type RegionMapLocationRecord[]
    local location = Raw(id)
    if not CanSee(location) then return path end
    for _ = 1, C.maxDepth do
        if location == nil then break end
        table.insert(path, 1, location)
        if location.parentId == "" then break end
        location = Raw(location.parentId)
    end
    return path
end

--- True when target is the Location or anywhere below it.
--- @param id string
--- @param targetId string
--- @return boolean
function RegionMapModel.IsInSubtree(id, targetId)
    local location = Raw(targetId)
    for _ = 1, C.maxDepth + 1 do
        if location == nil then return false end
        if location.id == id then return true end
        location = Raw(location.parentId)
    end
    return false
end
local IsInSubtree = RegionMapModel.IsInSubtree

-- Every valid Location below id, deepest last; viewer filter not applied.
local function Descendants(id)
    local result, queue = {}, { id }
    local childrenOf = Index().childrenOf
    while #queue > 0 do
        local parentId = table.remove(queue, 1)
        for _, child in ipairs(childrenOf[parentId] or {}) do
            result[#result + 1] = child
            queue[#queue + 1] = child.id
        end
    end
    return result
end

--- How many Locations below this one the viewer sees (dialog and Atlas counts).
--- @param id string
--- @return integer
function RegionMapModel.VisibleDescendantCount(id)
    local count = 0
    for _, location in ipairs(Descendants(id)) do
        if CanSeePin(location) then count = count + 1 end
    end
    return count
end

-- State document settings ------------------------------------------------------------------

-- Write state document fields. Party settings are not on the engine undo stack:
-- Region Map keeps its own undo, and Ctrl+Z must not desync it.
local function WriteState(description, apply)
    if not CanWrite() or StateData() == nil then return false end
    local doc = StateDocument()
    doc:BeginChange()
    doc.data.schemaVersion = C.schemaVersion
    apply(doc.data)
    doc:CompleteChange(description, { undoable = false })
    return true
end

--- The Party's custom name (D11b).
--- @return string
function RegionMapModel.PartyName()
    local data = StateData()
    local name = data and data.partyName
    if ValidText(name) then return name --[[@as string]] end
    return RegionMapCopy.T("party.defaultName", nil, true)
end

--- @param name string "" restores the default name
--- @return boolean written
function RegionMapModel.SetPartyName(name)
    name = R.TrimSingleLine(name)
    if not IsDirector() or not ValidName(name) then return false end
    return WriteState("Rename the Party", function(data) data.partyName = name end)
end

--- A library image id for the Party marker, or "" for the default banner.
--- @return string
function RegionMapModel.PartyImageId()
    local data = StateData()
    local imageId = data and data.partyImageId
    if type(imageId) == "string" and #imageId <= C.journalIdLimit then return imageId end
    return ""
end

--- @param imageId string
--- @return boolean written
function RegionMapModel.SetPartyImageId(imageId)
    if not IsDirector() or type(imageId) ~= "string" or #imageId > C.journalIdLimit then return false end
    return WriteState("Change the Party image", function(data) data.partyImageId = imageId end)
end

--- Game-wide: whether players may add Locations (D9d). On unless the Director turned it off.
--- @return boolean
function RegionMapModel.PlayersCanAddLocations()
    local data = StateData()
    return data == nil or data.playersCanAddLocations ~= false
end

--- @param value boolean
--- @return boolean written
function RegionMapModel.SetPlayersCanAddLocations(value)
    if not IsDirector() then return false end
    return WriteState("Change who can add Region Map locations", function(data)
        data.playersCanAddLocations = value == true
    end)
end

--- Whether the viewer may add a Location on this map now.
--- @param mapId string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
function RegionMapModel.CanAdd(mapId)
    if not CanWrite() or not CanOpenMap(Raw(mapId)) then return false, "permission" end
    if not IsDirector() and not RegionMapModel.PlayersCanAddLocations() then return false, "permission" end
    -- Counted per viewer, so hidden pins neither leak nor block a player (V1 RM-02).
    if #Children(mapId) >= C.labelLimit then return false, "limit" end
    return true, nil
end
local CanAdd = RegionMapModel.CanAdd

-- Location writes --------------------------------------------------------------------------

--- Upload one Location row built from current (nil to create) plus changes.
--- Returns the undo step, or nil when the upload could not start.
--- @param current nil|RegionMapLocationRecord
--- @param changes table
--- @param description string
--- @param callbacks nil|RegionMapWriteCallbacks told when the server confirms or refuses
--- @return nil|RegionMapUndoStep
local function WriteLocation(current, changes, description, callbacks)
    local record = current and DeepCopy(current) or RegionMapLocationRecord.new { revision = 0 }
    for key, value in pairs(changes) do
        -- false clears an optional field (scale, pace); nil cannot sit in a table.
        if value == false and (key == "scale" or key == "pace") then record[key] = nil else record[key] = value end
    end
    local revision = NextRevision(record)
    if revision == nil then return nil end
    record.revision = revision
    Audit(record, current == nil)
    local function Finish(callback)
        return function(write)
            InvalidateIndex()
            if callback ~= nil then callback(write) end
        end
    end
    local operation = UploadRecord(C.locationTableName, record, description, {
        success = Finish(callbacks and callbacks.success), failure = Finish(callbacks and callbacks.failure),
    }, current == nil)
    if operation == nil then return nil end
    InvalidateIndex()
    return {
        tableName = C.locationTableName, id = record.id,
        before = current and DeepCopy(current) or nil,
        afterRevision = revision, afterMutationId = record.mutationId,
    }
end

-- Validates and normalizes UpdateLocation changes; nil when any is invalid.
local function NormalizeChanges(current, changes)
    local result = {}
    for key, value in pairs(changes) do
        if key == "name" then
            value = R.TrimSingleLine(value)
            if not ValidName(value) then return nil end
        elseif key == "u" or key == "v" then
            if not IsFinite(value) or current.parentId == "" then return nil end
            value = Clamp(value, 0, 1)
        elseif key == "pinStyle" then
            if not R.pinStyles[value] then return nil end
        elseif key == "importance" then
            if not R.importances[value] then return nil end
        elseif key == "icon" then
            if type(value) ~= "string" or #value > C.journalIdLimit then return nil end
        elseif key == "visibility" then
            if not IsDirector() or not R.visibilities[value] or current.parentId == "" then return nil end
        elseif key == "mapShared" then
            if not IsDirector() or type(value) ~= "boolean" or current.imageId == "" then return nil end
        elseif key == "scale" then
            if not IsDirector() or not (value == false or R.ValidScale(value)) then return nil end
            if value then value = DeepCopy(value) end
        elseif key == "pace" then
            if not IsDirector() or not (value == false or (IsFinite(value) and value > 0)) then return nil end
        else
            -- parentId, imageId and hidden change only through their own functions.
            return nil
        end
        result[key] = value
    end
    return result
end

--- How the last write of a Location from this client ended, for the side
--- panel's Saving / Saved / Not saved line. nil when there was none.
--- @param id string
--- @return nil|"pending"|"confirmed"|"failed"
function RegionMapModel.WriteStatus(id)
    local operation = R.LastWrite(C.locationTableName, id)
    return operation and operation.status
end

--- @param description string
--- @param steps RegionMapUndoStep[]
--- @return RegionMapUndoEntry
local function Entry(description, steps)
    return { description = description, steps = steps }
end

--- Apply changed fields to the freshest row of a Location the viewer may edit.
--- Only the named fields change, so two people editing different fields of one
--- Location do not undo each other.
--- @param id string
--- @param changes {name: nil|string, u: nil|number, v: nil|number, pinStyle: nil|string, importance: nil|string, icon: nil|string, visibility: nil|string, mapShared: nil|boolean, scale: nil|false|RegionMapScale, pace: nil|false|number}
--- @param description nil|string
--- @param guard nil|RegionMapGuard
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapModel.UpdateLocation(id, changes, description, guard)
    local current = Raw(id)
    if not CanCommit(guard) or current == nil then return false, "invalid", nil end
    if not CanEdit(current) then return false, "permission", nil end
    if R.PendingWrite(C.locationTableName, id) then return false, "busy", nil end
    local normalized = NormalizeChanges(current, changes)
    if normalized == nil then return false, "invalid", nil end
    description = description or "Edit region map location"
    local step = WriteLocation(current, normalized, description)
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry(description, { step })
end
local UpdateLocation = RegionMapModel.UpdateLocation

--- The style a new pin starts with (R10: copied from the last one placed).
--- @class RegionMapPinStyle
--- @field icon nil|string
--- @field importance nil|"major"|"normal"|"minor"
--- @field pinStyle nil|"iconName"|"plate"|"iconOnly"
--- @field visibility nil|"hidden"|"revealed" Director only; players' Locations are always revealed

--- Create a Location at a point of a map. Director-made Locations start Hidden
--- unless style says otherwise; player-made ones are Revealed (R1). The name
--- starts empty and the UI shows edit.name.fallback until it is named.
--- @param mapId string
--- @param u number
--- @param v number
--- @param style nil|RegionMapPinStyle
--- @param callbacks nil|RegionMapWriteCallbacks the new row is readable only after success
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
--- @return nil|string id
function RegionMapModel.CreateLocation(mapId, u, v, style, callbacks)
    style = style or {}
    if not IsFinite(u) or not IsFinite(v) then return false, "invalid", nil, nil end
    local ok, reason = CanAdd(mapId)
    if not ok then return false, reason, nil, nil end
    local director = IsDirector()
    local visibility = "revealed"
    if director then visibility = R.visibilities[style.visibility] and style.visibility or "hidden" end
    local id = dmhub.GenerateGuid()
    local step = WriteLocation(nil, {
        id = id, schemaVersion = C.locationSchemaVersion, parentId = mapId, name = "",
        u = Clamp(u, 0, 1), v = Clamp(v, 0, 1),
        pinStyle = R.pinStyles[style.pinStyle] and style.pinStyle or "iconName",
        importance = R.importances[style.importance] and style.importance or "normal",
        icon = type(style.icon) == "string" and #style.icon <= C.journalIdLimit and style.icon or "",
        visibility = visibility, imageId = "", imageRevision = 0, mapShared = false,
        ownerId = dmhub.loginUserid, ownerName = CurrentUserName(), createdByDirector = director,
        hidden = false,
    }, "Add region map location", callbacks)
    if step == nil then return false, "unavailable", nil, nil end
    return true, nil, Entry("Add region map location", { step }), id
end

--- Create a top-level map (Atlas "New map"). Starts not shared (R1).
--- @param name string
--- @param imageId string
--- @param callbacks nil|RegionMapWriteCallbacks the new row is readable only after success
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
--- @return nil|string id
function RegionMapModel.CreateMap(name, imageId, callbacks)
    name = R.TrimSingleLine(name)
    if not CanWrite() or not IsDirector() then return false, "permission", nil, nil end
    if not ValidText(name) or type(imageId) ~= "string" or imageId == "" then return false, "invalid", nil, nil end
    local id = dmhub.GenerateGuid()
    local step = WriteLocation(nil, {
        id = id, schemaVersion = C.locationSchemaVersion, parentId = "", name = name, u = 0.5, v = 0.5,
        pinStyle = "iconName", importance = "normal", icon = "", visibility = "revealed",
        imageId = imageId, imageRevision = 1, mapShared = false,
        ownerId = dmhub.loginUserid, ownerName = CurrentUserName(), createdByDirector = true, hidden = false,
    }, "Create region map", callbacks)
    if step == nil then return false, "unavailable", nil, nil end
    return true, nil, Entry("Create region map", { step }), id
end

--- @param id string
--- @param u number
--- @param v number
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapModel.MoveLocation(id, u, v)
    return UpdateLocation(id, { u = u, v = v }, "Move region map location")
end

--- Move a Location (and everything under it) onto another map, at its middle.
--- @param id string
--- @param mapId string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapModel.MoveToMap(id, mapId)
    local current = Raw(id)
    if current == nil or current.parentId == "" or IsInSubtree(id, mapId) then return false, "invalid", nil end
    if not CanEdit(current) then return false, "permission", nil end
    if current.parentId == mapId then return true, nil, Entry("Move region map location", {}) end
    local ok, reason = CanAdd(mapId)
    if not ok then return false, reason, nil end
    if R.PendingWrite(C.locationTableName, id) then return false, "busy", nil end
    local step = WriteLocation(current, { parentId = mapId, u = 0.5, v = 0.5 }, "Move region map location to map")
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry("Move region map location to map", { step })
end

--- @param id string
--- @param visibility "hidden"|"revealed"
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapModel.SetVisibility(id, visibility)
    if not IsDirector() then return false, "permission", nil end
    return UpdateLocation(id, { visibility = visibility }, "Change location visibility")
end

--- @param id string
--- @param shared boolean
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapModel.SetMapShared(id, shared)
    if not IsDirector() then return false, "permission", nil end
    return UpdateLocation(id, { mapShared = shared }, "Change map sharing")
end

-- Sets a Location's image. Every new image bumps imageRevision, so cameras
-- saved for the old image are not reused.
local function SetImage(id, imageId, description)
    local current = Raw(id)
    if not IsDirector() or not CanWrite() then return false, "permission", nil end
    if current == nil or type(imageId) ~= "string" or imageId == "" then return false, "invalid", nil end
    if current.imageRevision >= C.maxRevision then return false, "unavailable", nil end
    if R.PendingWrite(C.locationTableName, id) then return false, "busy", nil end
    local changes = { imageId = imageId, imageRevision = current.imageRevision + 1 }
    -- New maps start not shared (R1); a replaced image keeps its sharing.
    if current.imageId == "" then changes.mapShared = false end
    local step = WriteLocation(current, changes, description)
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry(description, { step })
end

--- Give a Location without a map its own map image.
--- @param id string
--- @param imageId string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapModel.AddMap(id, imageId)
    local current = Raw(id)
    if current ~= nil and current.imageId ~= "" then return false, "invalid", nil end
    return SetImage(id, imageId, "Add map to location")
end

--- Replace a map's image. Pins keep their u/v (V1 behavior).
--- @param id string
--- @param imageId string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapModel.ReplaceImage(id, imageId)
    local current = Raw(id)
    if current ~= nil and current.imageId == "" then return false, "invalid", nil end
    return SetImage(id, imageId, "Replace map image")
end

-- Party -------------------------------------------------------------------------------------

-- The stored party, validated against the tree. At a valid Location it
-- follows that pin (D4d); otherwise it stays where it was dropped.
local function StoredParty()
    local data = StateData()
    local party = data and data.party
    if type(party) ~= "table" then return nil end
    local map = Raw(party.mapId)
    if map == nil or map.imageId == "" or not R.ValidUnit(party.u) or not R.ValidUnit(party.v) then return nil end
    --- @type RegionMapPartyView
    local result = { mapId = party.mapId, u = party.u, v = party.v, locationId = nil, revision = R.RecordRevision(party) }
    local location = Raw(party.locationId)
    if location ~= nil and location.parentId ~= "" and Raw(location.parentId) ~= nil then
        result.mapId, result.u, result.v, result.locationId = location.parentId, location.u, location.v, location.id
    end
    return result
end

--- Where the Party is, as the viewer may know it: nil when it is not placed or
--- on a map the viewer cannot open; locationId only when they see that pin (R3).
--- @return nil|RegionMapPartyView
function RegionMapModel.Party()
    local party = StoredParty()
    if party == nil or not CanOpenMap(Raw(party.mapId)) then return nil end
    if party.locationId ~= nil and not CanSeePin(Raw(party.locationId)) then party.locationId = nil end
    return party
end
local Party = RegionMapModel.Party

--- The Party status for the status chip, relative to the open map.
--- @param currentMapId nil|string
--- @return "at"|"traveling"|"elsewhere"|"none" kind
--- @return nil|RegionMapPartyView party
--- @return nil|RegionMapLocationRecord location set for "at"
function RegionMapModel.PartyStatus(currentMapId)
    local party = Party()
    if party == nil then return "none", nil, nil end
    if party.mapId ~= currentMapId then return "elsewhere", party, nil end
    if party.locationId ~= nil then return "at", party, Raw(party.locationId) end
    return "traveling", party, nil
end

--- Whether the viewer may move the Party on this map.
--- @param mapId string
--- @return boolean
function RegionMapModel.CanMovePartyOn(mapId)
    if not CanWrite() or StateData() == nil or not CanOpenMap(Raw(mapId)) then return false end
    return IsDirector() or RegionMapModel.PlayersCanMoveParty()
end
local CanMovePartyOn = RegionMapModel.CanMovePartyOn

-- Writes the party (or nil to unplace) and returns its undo step.
local function SetParty(party, description)
    local doc = StateDocument()
    local old = doc.data.party
    -- partyRevision survives an unplace, so revisions never go back and undo
    -- can tell any later Party write apart from its own.
    local oldRevision = math.max(R.RecordRevision(old), R.RecordRevision({ revision = doc.data.partyRevision }))
    if oldRevision >= C.maxRevision then return nil end
    local revision = oldRevision + 1
    local mutationId = dmhub.GenerateGuid()
    local before = type(old) == "table" and DeepCopy(old) or false
    doc:BeginChange()
    doc.data.schemaVersion = C.schemaVersion
    doc.data.partyRevision = revision
    doc.data.partyMutationId = mutationId
    if party == nil then
        doc.data.party = nil
    else
        party.revision, party.mutationId = revision, mutationId
        party.updatedBy, party.updatedByName, party.updatedAt = dmhub.loginUserid, CurrentUserName(), ServerTimestamp()
        doc.data.party = party
    end
    doc:CompleteChange(description, { undoable = false })
    return { party = before, afterRevision = revision, afterMutationId = mutationId }
end

--- Move the Party. With locationId it is "at" that Location (snapped to its
--- pin); without, it is traveling at u/v. A player can never snap it to a pin
--- they cannot see (R3).
--- @param args {mapId: string, u: nil|number, v: nil|number, locationId: nil|string, description: nil|string, placed: nil|boolean}
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapModel.WriteParty(args)
    if StateData() == nil then return false, "unavailable", nil end
    if not CanMovePartyOn(args.mapId) then return false, "permission", nil end
    local u, v, locationId = args.u, args.v, nil
    if args.locationId ~= nil then
        local location = Raw(args.locationId)
        if location == nil or location.parentId ~= args.mapId or not CanSeePin(location) then return false, "invalid", nil end
        u, v, locationId = location.u, location.v, location.id
    end
    if not IsFinite(u) or not IsFinite(v) then return false, "invalid", nil end
    local description = args.description or "Move Party on region map"
    local before = StoredParty()
    local after = { mapId = args.mapId, u = Clamp(u --[[@as number]], 0, 1), v = Clamp(v --[[@as number]], 0, 1), locationId = locationId }
    local step = SetParty(DeepCopy(after), description)
    if step == nil then return false, "unavailable", nil end
    -- The session log entry undoes with the move (R3); a failed log write leaves the move standing.
    local steps = { step }
    local logStep = RegionMapLog.Record(before, after, args.placed == true)
    if logStep ~= nil then steps[2] = logStep end
    return true, nil, Entry(description, steps)
end
local WriteParty = RegionMapModel.WriteParty

--- Director: put the Party anywhere on any map (R12 "Place Party here").
--- @param mapId string
--- @param u number
--- @param v number
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapModel.PlaceParty(mapId, u, v)
    if not IsDirector() then return false, "permission", nil end
    return WriteParty { mapId = mapId, u = u, v = v, description = "Place Party on region map", placed = true }
end

-- Deletion ------------------------------------------------------------------------------------

-- Hides each Location (deepest first, so no child outlives its parent on
-- another client mid-batch) and returns the steps that started.
local function HideAll(locations, description)
    local steps = {}
    for i = #locations, 1, -1 do
        local step = WriteLocation(locations[i], { hidden = true }, description)
        if step ~= nil then steps[#steps + 1] = step end
    end
    return steps
end

-- Where the Party goes when these maps are removed: the removed Location's
-- spot on its parent map, false to unplace it (a top-level map goes), or nil
-- when it is not on them. Read before the rows are hidden, since hiding drops
-- them from the tree StoredParty reads.
local function RescueTarget(location, removedMapIds)
    local party = StoredParty()
    if party == nil or StateData() == nil then return nil end
    local onRemoved = removedMapIds[party.mapId] or party.locationId ~= nil and removedMapIds[party.locationId]
    if not onRemoved then return nil end
    if location.parentId == "" then return false end
    return { mapId = location.parentId, u = location.u, v = location.v }
end

-- True when any of the rows still has a write in flight (a rename just typed):
-- writing it again now would fail, and a batch must not go through half done.
local function AnyPending(locations)
    for _, location in ipairs(locations) do
        if R.PendingWrite(C.locationTableName, location.id) then return true end
    end
    return false
end

--- Whether the viewer may delete a Location. Players delete only their own
--- Locations, and only while they have no map: only the Director adds maps, so
--- a map and everything pinned on it is Director content (decision 2026-10-07).
--- @param location nil|RegionMapLocationRecord
--- @return boolean
function RegionMapModel.CanDelete(location)
    if location == nil or not CanEdit(location) then return false end
    if IsDirector() then return true end
    return location.parentId ~= "" and location.imageId == ""
end

--- Delete a Location and its whole subtree in one batch. A Party inside moves
--- to the deleted Location's spot on its parent map (D7d). Details and notes
--- rows are left in place: nothing shows them, and undo needs them intact.
--- @param id string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
--- @return integer count Locations deleted besides this one
function RegionMapModel.DeleteLocation(id)
    local current = Raw(id)
    if current == nil then return false, "invalid", nil, 0 end
    if not RegionMapModel.CanDelete(current) then return false, "permission", nil, 0 end
    local descendants = Descendants(id)
    local all = { current }
    for _, location in ipairs(descendants) do all[#all + 1] = location end
    if AnyPending(all) then return false, "busy", nil, 0 end
    local removed = {}
    for _, location in ipairs(all) do removed[location.id] = true end
    local description = "Delete region map location"
    local target = RescueTarget(current, removed)
    local steps = HideAll(all, description)
    if #steps == 0 then return false, "unavailable", nil, 0 end
    -- The Party moves only once the rows are on their way, so a failed delete leaves it be.
    if target ~= nil then
        local partyStep = SetParty(target or nil, description)
        if partyStep ~= nil then steps[#steps + 1] = partyStep end
    end
    return true, nil, Entry(description, steps), #descendants
end

--- Remove a Location's map image; the Locations pinned on it (and below) are
--- deleted (copy 17.5). Top-level maps are deleted instead, never emptied.
--- @param id string
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
--- @return integer count Locations deleted
function RegionMapModel.RemoveMap(id)
    local current = Raw(id)
    if not IsDirector() or not CanWrite() then return false, "permission", nil, 0 end
    if current == nil or current.parentId == "" or current.imageId == "" then return false, "invalid", nil, 0 end
    local descendants = Descendants(id)
    if R.PendingWrite(C.locationTableName, id) or AnyPending(descendants) then return false, "busy", nil, 0 end
    local removed = {}
    for _, location in ipairs(descendants) do removed[location.id] = true end
    local description = "Remove map from location"
    -- A Party on the removed map (or below it) goes to this Location's own pin, which stays.
    -- Decided before the writes, since hiding the rows drops them from the tree.
    local partyTarget = nil
    local party = StoredParty()
    if party ~= nil and (party.mapId == id or removed[party.mapId] or (party.locationId and removed[party.locationId])) then
        partyTarget = { mapId = current.parentId, u = current.u, v = current.v, locationId = current.id }
    end
    -- Pins go before the map (deepest first, see HideAll), so check up front that the
    -- map's own row can still take a write; the busy check above covers the rest.
    if NextRevision(current) == nil then return false, "unavailable", nil, 0 end
    local steps = HideAll(descendants, description)
    local own = WriteLocation(current, { imageId = "", mapShared = false, scale = false, pace = false }, description)
    if own == nil then return false, "unavailable", nil, 0 end
    steps[#steps + 1] = own
    if partyTarget ~= nil then
        local partyStep = SetParty(partyTarget, description)
        if partyStep ~= nil then steps[#steps + 1] = partyStep end
    end
    return true, nil, Entry(description, steps), #descendants
end

-- Undo support ---------------------------------------------------------------------------------

-- The live value a step compares against: the row, or the party document.
local function StepCurrent(step)
    if step.tableName ~= nil then
        local row = (dmhub.GetTable(step.tableName) or {})[step.id]
        return R.RecordRevision(row), Field(row, "mutationId", nil)
    end
    local data = StateData()
    if data == nil then return -1, nil end
    if type(data.party) == "table" then return R.RecordRevision(data.party), Field(data.party, "mutationId", nil) end
    return R.RecordRevision({ revision = data.partyRevision }), data.partyMutationId
end

--- True when none of an entry's table writes is still waiting for the server.
--- Undo waits for this: a row with a write in flight cannot be written again.
--- @param entry RegionMapUndoEntry
--- @return boolean
function RegionMapModel.IsSettled(entry)
    for _, step in ipairs(entry.steps) do
        if step.tableName ~= nil and R.PendingWrite(step.tableName, step.id) then return false end
    end
    return true
end

--- Whether every step of an entry is still exactly as this client left it.
--- False after anyone else changed one of the rows (R14).
--- @param entry RegionMapUndoEntry
--- @return boolean
function RegionMapModel.CanRevert(entry)
    if not CanWrite() or #entry.steps == 0 then return false end
    for _, step in ipairs(entry.steps) do
        local revision, mutationId = StepCurrent(step)
        if revision ~= step.afterRevision or mutationId ~= step.afterMutationId then return false end
    end
    return true
end

--- A row (or the Party) that an undo rewrote: the state it restored, and the
--- revision that state now carries. Older undo entries that ended in the
--- restored state are moved onto the new revision, so they stay undoable.
--- @class RegionMapRebind
--- @field tableName nil|string nil for the Party
--- @field id nil|string
--- @field fromRevision integer
--- @field fromMutationId nil|string
--- @field toRevision integer
--- @field toMutationId string

--- Undo an entry: restore each step's earlier row (a created row is hidden)
--- with a new revision. All or nothing: refused when any step moved on.
--- Reverts are not themselves undoable.
--- @param entry RegionMapUndoEntry
--- @return boolean ok
--- @return RegionMapRebind[] rebinds
function RegionMapModel.Revert(entry)
    local rebinds = {} --- @type RegionMapRebind[]
    if not RegionMapModel.CanRevert(entry) then return false, rebinds end
    local ok = true
    for i = #entry.steps, 1, -1 do
        local step = entry.steps[i]
        if step.tableName ~= nil then
            local current = (dmhub.GetTable(step.tableName) or {})[step.id]
            local record
            if step.before ~= nil then record = DeepCopy(step.before) else record = DeepCopy(current); record.hidden = true end
            record.revision = NextRevision(current)
            if record.revision == nil then
                ok = false
            else
                Audit(record, false)
                local started = UploadRecord(step.tableName, record, "Undo: " .. entry.description,
                    { success = InvalidateIndex, failure = InvalidateIndex }, false) ~= nil
                ok = started and ok
                if started and step.before ~= nil then
                    rebinds[#rebinds + 1] = {
                        tableName = step.tableName, id = step.id,
                        fromRevision = R.RecordRevision(step.before), fromMutationId = Field(step.before, "mutationId", nil),
                        toRevision = record.revision, toMutationId = record.mutationId,
                    }
                end
            end
        else
            local before = step.party
            if before == false then before = nil else before = DeepCopy(before) end
            local written = SetParty(before, "Undo: " .. entry.description)
            ok = written ~= nil and ok
            if written ~= nil and type(step.party) == "table" then
                rebinds[#rebinds + 1] = {
                    fromRevision = R.RecordRevision(step.party), fromMutationId = Field(step.party, "mutationId", nil),
                    toRevision = written.afterRevision, toMutationId = written.afterMutationId,
                }
            end
        end
    end
    InvalidateIndex()
    return ok, rebinds
end

--- Game-wide: whether players may move the Party (D11c). Off unless the Director turned it on.
--- @return boolean
function RegionMapModel.PlayersCanMoveParty()
    local data = StateData()
    return data ~= nil and data.playerCanMoveParty == true
end

--- @param value boolean
--- @return boolean written
function RegionMapModel.SetPlayersCanMoveParty(value)
    if not IsDirector() then return false end
    return WriteState("Change who can move the Party", function(data)
        data.playerCanMoveParty = value == true
    end)
end

-- Location content: description, journal link, Director notes ----------------------------------

--- A Location's description and journal link as the viewer may see them.
--- @class RegionMapDetails
--- @field description string
--- @field journal RegionMapJournalView the link resolved for this viewer
--- @field journalDocId string the stored link; "" for players
--- @field state "empty"|"available"|"unavailable"

--- @param id string
--- @return nil|RegionMapDetails nil when the viewer may not see the Location
function RegionMapModel.Details(id)
    if RegionMapModel.GetLocation(id) == nil then return nil end
    local row, state = ReadSidecar(id, false)
    local docId = Field(row, "journalDocId", "")
    return {
        description = Field(row, "description", ""),
        journal = Journal.ResolveForViewer(docId),
        journalDocId = IsDirector() and docId or "",
        state = state,
    }
end

--- The Director notes of a Location; nil for anyone but the Director.
--- @param id string
--- @return nil|string note
--- @return nil|"empty"|"available"|"unavailable" state
function RegionMapModel.DirectorNote(id)
    if not IsDirector() or Raw(id) == nil then return nil, nil end
    local row, state = ReadSidecar(id, true)
    return Field(row, "note", ""), state
end

-- Writes one sidecar row with only the given fields changed. Rows keep the V1
-- format (labelId repeats the id), so ReadSidecar accepts both.
local function SaveSidecar(id, fields, private, callbacks)
    local tableName, schema, recordType = SidecarSpec(private)
    if PendingWrite(tableName, id) then return false, "busy" end
    local current, state = ReadSidecar(id, private)
    if state == "unavailable" then return false, "unavailable" end
    local changed = false
    for key, value in pairs(fields) do
        if value ~= Field(current, key, "") then changed = true end
    end
    if not changed then
        if callbacks ~= nil and callbacks.success ~= nil then callbacks.success(nil) end
        return true, nil
    end
    local record = current and DeepCopy(current) or recordType.new {
        id = id, labelId = id, schemaVersion = schema, hidden = false, revision = 0,
    }
    if current == nil then
        if private then record.note = "" else record.description, record.journalDocId = "", "" end
    end
    for key, value in pairs(fields) do record[key] = value end
    local revision = NextRevision(record)
    if revision == nil then return false, "unavailable" end
    record.revision = revision
    Audit(record, current == nil)
    local operation = UploadRecord(tableName, record, private and "Save Director note" or "Save location details",
        callbacks, current == nil)
    if operation == nil then return false, "unavailable" end
    return true, nil
end

--- Save a Location's description and/or journal link. Linking is Director only.
--- @param id string
--- @param patch {description: nil|string, journalDocId: nil|string}
--- @param callbacks nil|RegionMapWriteCallbacks
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
function RegionMapModel.SaveDetails(id, patch, callbacks)
    if not CanEdit(Raw(id)) then return false, "permission" end
    local fields = {}
    if patch.description ~= nil then
        fields.description = NormalizeMultiline(patch.description, C.descriptionLimit, C.descriptionByteLimit)
        if fields.description == nil then return false, "invalid" end
    end
    if patch.journalDocId ~= nil then
        local docId = patch.journalDocId
        if not IsDirector() then return false, "permission" end
        if type(docId) ~= "string" or #docId > C.journalIdLimit then return false, "invalid" end
        if docId ~= "" and Journal.ResolveForViewer(docId).status ~= "available" then return false, "invalid" end
        fields.journalDocId = docId
    end
    return SaveSidecar(id, fields, false, callbacks)
end

--- @param id string
--- @param note string
--- @param callbacks nil|RegionMapWriteCallbacks
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
function RegionMapModel.SaveDirectorNote(id, note, callbacks)
    if not IsDirector() or not CanWrite() or Raw(id) == nil then return false, "permission" end
    local normalized = NormalizeMultiline(note, C.noteLimit, C.noteByteLimit)
    if normalized == nil then return false, "invalid" end
    return SaveSidecar(id, { note = normalized }, true, callbacks)
end

--- How this client's latest writes of one Location (row, details, notes)
--- stand, for the side panel's Saving / Saved / Not saved line.
--- @param id string
--- @return nil|"pending"|"confirmed"|"failed" nil when nothing was written
function RegionMapModel.SaveStatus(id)
    local result = nil
    for _, tableName in ipairs({ C.locationTableName, C.detailsTableName, C.notesTableName }) do
        local operation = LastWrite(tableName, id)
        if operation ~= nil then
            if operation.status == "pending" then return "pending" end
            if operation.status == "failed" then result = "failed"
            elseif result == nil then result = "confirmed" end
        end
    end
    return result
end

--- A name to show for a Location: its own, or edit.name.fallback while unnamed.
--- @param location RegionMapLocationRecord
--- @return string plain text; escape it before it reaches a label
function RegionMapModel.DisplayName(location)
    if location.name ~= "" then return location.name end
    return RegionMapCopy.T("edit.name.fallback", nil, true)
end
