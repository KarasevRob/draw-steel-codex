local mod = dmhub.GetModLoading()

--- Data access and permission rules for Overland Map. The UI never reads the
--- Overland Map tables directly; it calls the functions on this namespace.
--- @class OverlandMapModel: GameType
--- @field new fun(o?: table): OverlandMapModel
OverlandMapModel = RegisterGameType("OverlandMapModel")
local C = OverlandMapConstants
local R = OverlandMapRecords
local Journal = OverlandMapJournal

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
OverlandMapModel.Clamp = Clamp
OverlandMapModel.IsFinite = IsFinite
OverlandMapModel.Field = Field
OverlandMapModel.TrimSingleLine = R.TrimSingleLine
OverlandMapModel.TextLength = R.TextLength

--- @return string
function OverlandMapModel.StatePath()
    return StateDocument().path
end

-- The Location tree --------------------------------------------------------------------------

--- Every valid Location, validated once and grouped by parent. Not filtered
--- for the viewer.
--- @class OverlandMapLocationIndex
--- @field byId table<string, OverlandMapLocationRecord>
--- @field childrenOf table<string, OverlandMapLocationRecord[]> sorted by name; "" holds the top level

--- One reversible part of a model write. Table steps restore a row; the Party
--- step restores the state document's party; a state step restores one game-wide
--- setting (path types, time unit). Undo refuses a step whose row changed since
--- (another write), which revision and mutationId detect.
--- @class OverlandMapUndoStep
--- @field tableName nil|string
--- @field id nil|string
--- @field before nil|table the row before the write; nil when the write created it
--- @field party nil|table|false the party before a Party write; false = not placed
--- @field state nil|string the state document key a state step restores
--- @field stateBefore any the key's value before the write; false = not set
--- @field stateBeforeRevision nil|integer the key's revision before the write
--- @field stateBeforeMutationId nil|string
--- @field afterRevision integer
--- @field afterMutationId string
--- @field receipt nil|OverlandMapWrite table steps require a successful upload before Undo
--- @field guards nil|{tableName: string, id: string, revision: integer, mutationId: nil|string}[] related rows that must remain unchanged

--- What one user action changed, for OverlandMapUndo.
--- @class OverlandMapUndoEntry
--- @field description string
--- @field operations nil|table[] individual submissions, including rows that could not start
--- @field steps OverlandMapUndoStep[]
--- @field partial nil|boolean the steps are independent rows (an import); Undo restores those still untouched
--- @field mergeKey nil|string set by OverlandMapUndo.PushMerged
--- @field mergedAt nil|number

--- The Party as the viewer may know it. At a Location, mapId/u/v follow that pin.
--- @class OverlandMapPartyView
--- @field mapId string
--- @field u number
--- @field v number
--- @field locationId nil|string only when the viewer can see that pin
--- @field pathId nil|string stopped partway on this path (Q13); only when the viewer sees the path
--- @field pathFrom nil|string the path end the time spent counts from
--- @field spent nil|number watches spent from pathFrom; u/v are worked out from it
--- @field revision integer

--- @alias OverlandMapWriteReason "permission"|"invalid"|"busy"|"unavailable"|"changed"

local Locations = R.LocationsTable
local ValidName = R.ValidName

-- Companions ---------------------------------------------------------------------------------

--- A data module that keeps its own rows on a map (labels) or its own queue of map
--- settings (pin text). It registers here so map deletion, Undo and View as player
--- include it; the model never names it, and it may load after the model.
--- @class OverlandMapCompanion
--- @field tableName nil|string Undo steps on this table are this companion's rows
--- @field rowsOnMaps nil|fun(mapIds: table<string, boolean>): table[] its live rows on these maps
--- @field anyPending nil|fun(rows: table[]): boolean whether one of the rows has a write in flight
--- @field hideSteps nil|fun(rows: table[], description: string): OverlandMapUndoStep[] soft-delete the rows
--- @field cancelRow nil|fun(id: string) drop unsent edits of one of its rows
--- @field cancelMap nil|fun(id: string) drop unsent edits that belong to this map
--- @field canRevertStep nil|fun(step: OverlandMapUndoStep, entry: OverlandMapUndoEntry): boolean
--- @field beforeViewChange nil|fun() send unsent edits while the viewer still has the rights
--- @field afterViewChange nil|fun() drop unsent edits the viewer can no longer make

local companions = {} --- @type OverlandMapCompanion[]

--- @param companion OverlandMapCompanion
function OverlandMapModel.RegisterCompanion(companion)
    companions[#companions + 1] = companion
end

--- Recheck every game-scoped queue when records or permissions change, even with its editor closed.
function OverlandMapModel.ReconcilePermissions()
    for _, companion in ipairs(companions) do
        if companion.afterViewChange then companion.afterViewChange() end
    end
end

-- View as player: the Director's client answers every visibility
-- question as a player who owns nothing, and refuses writes while it is on.
local viewAsPlayer = false

--- Unsent edits go out before the switch, so turning it on never loses typing.
--- @param on boolean
function OverlandMapModel.SetViewAsPlayer(on)
    for _, companion in ipairs(companions) do
        if companion.beforeViewChange then companion.beforeViewChange() end
    end
    viewAsPlayer = on == true and dmhub.isDM
    OverlandMapModel.ReconcilePermissions()
end

--- @return boolean
function OverlandMapModel.ViewingAsPlayer()
    return viewAsPlayer
end

--- True when the viewer gets Director rights (a Director not viewing as player).
--- @return boolean
function OverlandMapModel.IsDirector()
    return dmhub.isDM and not viewAsPlayer
end
local IsDirector = OverlandMapModel.IsDirector

local function ViewerId()
    if viewAsPlayer then return "" end
    return dmhub.loginUserid
end

local function CanWrite()
    return not mod.unloaded and not viewAsPlayer
end

-- Index ------------------------------------------------------------------------------------

local cachedIndex = nil --- @type nil|OverlandMapLocationIndex
local cachedRevision = nil --- @type nil|integer

-- The engine's tablesUpdateId moves on every data table change, this client's
-- writes and cloud updates alike, but not on token moves, chat or document
-- writes, which happen all the time in play and leave our data alone.
local dataRevision, seenTablesUpdate = 0, nil

--- A number that changes whenever Overland Map data may have changed. The
--- Location, path and log caches, and any UI signature built from that data,
--- key on it.
--- @return integer
function OverlandMapModel.Revision()
    local tablesUpdate = dmhub.tablesUpdateId
    if tablesUpdate ~= seenTablesUpdate then
        seenTablesUpdate = tablesUpdate
        dataRevision = dataRevision + 1
    end
    return dataRevision
end
local Revision = OverlandMapModel.Revision

--- Mark the data changed, so every cache keyed on Revision rebuilds on its next question.
function OverlandMapModel.InvalidateIndex()
    dataRevision = dataRevision + 1
end
local InvalidateIndex = OverlandMapModel.InvalidateIndex
R.SetChangeListener(InvalidateIndex)
OverlandMapLifetime.Subscribe(function()
    cachedIndex, cachedRevision, seenTablesUpdate = nil, nil, nil
    viewAsPlayer = false
    InvalidateIndex()
end)

local function NameKey(location)
    return R.MapNameKey(location.name)
end

--- The validated Location tree, rebuilt only when the data changed.
--- @return OverlandMapLocationIndex
function OverlandMapModel.Index()
    local key = Revision()
    if cachedIndex ~= nil and cachedRevision == key then return cachedIndex end
    local candidates = {} --- @type table<string, OverlandMapLocationRecord>
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
    cachedRevision = key
    return cachedIndex
end
local Index = OverlandMapModel.Index

-- A valid Location with no viewer filter. Internal: public reads filter.
local function Raw(id)
    if type(id) ~= "string" then return nil end
    return Index().byId[id]
end

-- Visibility rules (D9, R4) ---------------------------------------------------------------

--- Whether the viewer may open a Location's map. Director: any map. Player: a
--- shared map whose own pin they can see (top-level maps have no pin).
--- @param location nil|OverlandMapLocationRecord
--- @return boolean
function OverlandMapModel.CanOpenMap(location)
    if location == nil or location.imageId == "" then return false end
    if IsDirector() then return true end
    if not location.mapShared then return false end
    return location.parentId == "" or OverlandMapModel.CanSeePin(location)
end
local CanOpenMap = OverlandMapModel.CanOpenMap

--- Whether the viewer sees a Location's pin on its parent's map.
--- @param location nil|OverlandMapLocationRecord
--- @return boolean
function OverlandMapModel.CanSeePin(location)
    if location == nil or location.parentId == "" then return false end
    if IsDirector() then return true end
    return location.visibility == "revealed" and CanOpenMap(Raw(location.parentId))
end
local CanSeePin = OverlandMapModel.CanSeePin

-- A pin the viewer sees, or a top-level map they may open.
local function CanSee(location)
    if location == nil then return false end
    if location.parentId == "" then return CanOpenMap(location) end
    return CanSeePin(location)
end

--- @param location nil|OverlandMapLocationRecord
--- @return boolean
function OverlandMapModel.CanEdit(location)
    if not CanWrite() or not CanSee(location) then return false end
    return IsDirector() or (location ~= nil and location.ownerId == ViewerId())
end
local CanEdit = OverlandMapModel.CanEdit

--- A Location the viewer may see, or nil. Never returns a Hidden pin or an
--- unshared map to a player.
--- @param id any
--- @return nil|OverlandMapLocationRecord
function OverlandMapModel.GetLocation(id)
    local location = Raw(id)
    if not CanSee(location) then return nil end
    return location
end

--- The pins on a map the viewer may see, sorted by name. Empty when the
--- viewer may not open the map.
--- @param mapId string
--- @return OverlandMapLocationRecord[]
function OverlandMapModel.Children(mapId)
    local result = {} --- @type OverlandMapLocationRecord[]
    if not CanOpenMap(Raw(mapId)) then return result end
    for _, child in ipairs(Index().childrenOf[mapId] or {}) do
        if CanSeePin(child) then result[#result + 1] = child end
    end
    return result
end

--- Top-level maps the viewer may open, sorted by name (the Atlas).
--- @return OverlandMapLocationRecord[]
function OverlandMapModel.TopLevel()
    local result = {} --- @type OverlandMapLocationRecord[]
    for _, location in ipairs(Index().childrenOf[""]) do
        if CanOpenMap(location) then result[#result + 1] = location end
    end
    return result
end

--- Every map the viewer may open, at any depth, sorted by name ("Move to map...").
--- @return OverlandMapLocationRecord[]
function OverlandMapModel.OpenableMaps()
    local result, keys = {}, {} --- @type OverlandMapLocationRecord[], table<string, string>
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
--- @return OverlandMapLocationRecord[]
function OverlandMapModel.Search(query, limit)
    local needle = R.MapNameKey(R.TrimSingleLine(query))
    local result, rank, keys = {}, {}, {} --- @type OverlandMapLocationRecord[], table<string, integer>, table<string, string>
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
--- @return OverlandMapLocationRecord[]
function OverlandMapModel.Ancestors(id)
    local path = {} --- @type OverlandMapLocationRecord[]
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
function OverlandMapModel.IsInSubtree(id, targetId)
    local location = Raw(targetId)
    for _ = 1, C.maxDepth + 1 do
        if location == nil then return false end
        if location.id == id then return true end
        location = Raw(location.parentId)
    end
    return false
end
local IsInSubtree = OverlandMapModel.IsInSubtree

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
function OverlandMapModel.VisibleDescendantCount(id)
    local count = 0
    for _, location in ipairs(Descendants(id)) do
        if CanSeePin(location) then count = count + 1 end
    end
    return count
end

-- State document settings ------------------------------------------------------------------

-- Write state document fields. Party settings are not on the engine undo stack:
-- Overland Map keeps its own undo, and Ctrl+Z must not desync it.
local function WriteState(description, apply)
    if not CanWrite() then return false, "permission" end
    if StateData() == nil then return false, "unavailable" end
    local doc = StateDocument()
    doc:BeginChange()
    doc.data.schemaVersion = C.schemaVersion
    apply(doc.data)
    doc:CompleteChange(description, { undoable = false })
    return true, nil
end

--- Write one game-wide setting the Director can undo (path types, time unit).
--- Each key keeps its own revision in stateMeta, so undo can tell whether the
--- setting changed again since. Returns the undo step, or nil when not written.
--- @param key string
--- @param value any nil removes the key
--- @param description string
--- @return nil|OverlandMapUndoStep
function OverlandMapModel.WriteStateKey(key, value, description)
    if not CanWrite() or not IsDirector() or StateData() == nil then return nil end
    local doc = StateDocument()
    local metaAll = type(doc.data.stateMeta) == "table" and DeepCopy(doc.data.stateMeta) or {}
    local meta = metaAll[key]
    local oldRevision = R.RecordRevision(meta)
    if oldRevision >= C.maxRevision then return nil end
    local before = doc.data[key]
    if before == nil then before = false else before = DeepCopy(before) end
    local revision, mutationId = oldRevision + 1, dmhub.GenerateGuid()
    metaAll[key] = { revision = revision, mutationId = mutationId }
    doc:BeginChange()
    doc.data.schemaVersion = C.schemaVersion
    doc.data.stateMeta = metaAll
    if value == nil then doc.data[key] = nil else doc.data[key] = DeepCopy(value) end
    doc:CompleteChange(description, { undoable = false })
    return {
        state = key, stateBefore = before,
        stateBeforeRevision = oldRevision, stateBeforeMutationId = Field(meta, "mutationId", nil),
        afterRevision = revision, afterMutationId = mutationId,
    }
end

--- The Party's custom name (D11b).
--- @return string
function OverlandMapModel.PartyName()
    local data = StateData()
    local name = data and data.partyName
    if R.ValidStoredText(name) then return name --[[@as string]] end
    return OverlandMapCopy.T("party.defaultName", nil, true)
end

--- @param name string "" restores the default name
--- @return boolean written
--- @return nil|OverlandMapWriteReason reason
function OverlandMapModel.SetPartyName(name)
    name = R.TrimSingleLine(name)
    if not IsDirector() then return false, "permission" end
    if not ValidName(name) then return false, "invalid" end
    return WriteState("Rename the Party", function(data) data.partyName = name end)
end

--- A library image id for the Party marker, or "" for the default banner.
--- @return string
function OverlandMapModel.PartyImageId()
    local data = StateData()
    local imageId = data and data.partyImageId
    if type(imageId) == "string" and #imageId <= C.journalIdLimit then return imageId end
    return ""
end

--- @param imageId string
--- @return boolean written
--- @return nil|OverlandMapWriteReason reason
function OverlandMapModel.SetPartyImageId(imageId)
    if not IsDirector() then return false, "permission" end
    if type(imageId) ~= "string" or #imageId > C.journalIdLimit then return false, "invalid" end
    return WriteState("Change the Party image", function(data) data.partyImageId = imageId end)
end

--- Game-wide: whether players may add Locations (D9d). On unless the Director turned it off.
--- @return boolean
function OverlandMapModel.PlayersCanAddLocations()
    local data = StateData()
    return data == nil or data.playersCanAddLocations ~= false
end

--- @param value boolean
--- @return boolean written
--- @return nil|OverlandMapWriteReason reason
function OverlandMapModel.SetPlayersCanAddLocations(value)
    if not IsDirector() then return false, "permission" end
    return WriteState("Change who can add Overland Map locations", function(data)
        data.playersCanAddLocations = value == true
    end)
end

-- How many Locations deep a map is: 1 for a top-level map.
local function Depth(id)
    local location, depth = Raw(id), 0
    while location ~= nil and depth <= C.maxDepth do
        depth = depth + 1
        if location.parentId == "" then break end
        location = Raw(location.parentId)
    end
    return depth
end

--- Whether the viewer may add a Location on this map now. A map already maxDepth deep
--- takes no more: every reader would reject the new row as nested too deep.
--- @param mapId string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
function OverlandMapModel.CanAdd(mapId)
    if not CanWrite() or not CanOpenMap(Raw(mapId)) then return false, "permission" end
    if not IsDirector() and not OverlandMapModel.PlayersCanAddLocations() then return false, "permission" end
    if Depth(mapId) >= C.maxDepth then return false, "invalid" end
    return true, nil
end
local CanAdd = OverlandMapModel.CanAdd

-- Location writes --------------------------------------------------------------------------

--- Upload one Location row built from current (nil to create) plus changes.
--- Returns the undo step, or nil when the upload could not start.
--- @param current nil|OverlandMapLocationRecord
--- @param changes table
--- @param description string
--- @param callbacks nil|OverlandMapWriteCallbacks told when the server confirms or refuses
--- @param retry nil|OverlandMapRetry an explicit retry of this client's failed write
--- @return nil|OverlandMapUndoStep step
--- @return nil|OverlandMapWrite operation
local function WriteLocation(current, changes, description, callbacks, retry)
    local record = current and DeepCopy(current) or OverlandMapLocationRecord.new { revision = 0, artworkImageId = "" }
    for key, value in pairs(changes) do
        -- false clears optional fields; nil cannot sit in a change table.
        if value == false and (key == "scale" or key == "pace" or key == "mode" or key == "pinNameFormat" or key == "mapAids") then
            record[key] = nil
        else record[key] = value end
    end
    return R.WriteRow(C.locationTableName, current, record, description, callbacks, { retry = retry })
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
        elseif key == "artworkImageId" then
            if not IsDirector() or not R.ValidArtwork(value) then return nil end
        elseif key == "visibility" then
            if not IsDirector() or not R.visibilities[value] or current.parentId == "" then return nil end
        elseif key == "mapShared" then
            if not IsDirector() or type(value) ~= "boolean" or current.imageId == "" then return nil end
        elseif key == "scale" then
            if not IsDirector() or not (value == false or R.ValidScale(value)) then return nil end
            if value then value = DeepCopy(value) end
        elseif key == "pace" then
            if not IsDirector() or not (value == false or (IsFinite(value) and value > 0)) then return nil end
        elseif key == "border" then
            if not IsDirector() or not R.borders[value] or current.imageId == "" then return nil end
        else
            -- parentId, imageId and hidden change only through their own functions.
            return nil
        end
        result[key] = value
    end
    return result
end

--- @param description string
--- @param steps OverlandMapUndoStep[]
--- @return OverlandMapUndoEntry
local function Entry(description, steps)
    return { description = description, steps = steps }
end

--- Apply changed fields to the freshest row of a Location the viewer may edit.
--- Only the named fields change, so two people editing different fields of one
--- Location do not undo each other.
--- @param id string
--- @param changes {name: nil|string, u: nil|number, v: nil|number, pinStyle: nil|string, importance: nil|string, icon: nil|string, artworkImageId: nil|string, visibility: nil|string, mapShared: nil|boolean, scale: nil|false|OverlandMapScale, pace: nil|false|number, border: nil|string}
--- @param description nil|string
--- @param retry nil|OverlandMapRetry an explicit retry of this client's failed write
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
--- @param callbacks nil|OverlandMapWriteCallbacks
--- @return nil|OverlandMapWrite receipt
function OverlandMapModel.UpdateLocation(id, changes, description, retry, callbacks)
    local current = Raw(id)
    if mod.unloaded or current == nil then return false, "invalid", nil end
    if not CanEdit(current) then return false, "permission", nil end
    if changes.artworkImageId ~= nil and not IsDirector() then return false, "permission", nil end
    if R.PendingWrite(C.locationTableName, id) then return false, "busy", nil end
    local normalized = NormalizeChanges(current, changes)
    if normalized == nil then return false, "invalid", nil end
    if not R.CanRetryWrite(C.locationTableName, current, retry) then
        for key, value in pairs(normalized) do
            local previous = key == "artworkImageId" and R.ArtworkValue(current) or Field(current, key, nil)
            if value == false and (key == "scale" or key == "pace") then value = nil end
            if dmhub.DeepEqual(previous, value) then normalized[key] = nil end
        end
    end
    if next(normalized) == nil then return true, nil, nil end
    description = description or "Edit overland map location"
    local step, operation = WriteLocation(current, normalized, description, callbacks, retry)
    if step == nil then return false, "unavailable", nil, operation end
    return true, nil, Entry(description, { step }), operation
end
local UpdateLocation = OverlandMapModel.UpdateLocation

--- Apply a pin-text leaf patch to the latest map row, independently of player-owned pin editing.
--- @param id string
--- @param patch table
--- @param reset boolean
--- @param callbacks nil|OverlandMapWriteCallbacks
--- @param retry nil|OverlandMapRetry
--- @return boolean, nil|OverlandMapWriteReason, nil|OverlandMapUndoEntry, nil|OverlandMapWrite
function OverlandMapModel.SetPinNameFormat(id, patch, reset, callbacks, retry)
    if not IsDirector() or not CanWrite() then return false, "permission" end
    local current = Raw(id)
    if current == nil or current.imageId == "" then return false, "invalid" end
    if R.PendingWrite(C.locationTableName, id) then return false, "busy" end
    local format = OverlandMapTextAppearance.ApplyPinPatch(Field(current, "pinNameFormat", nil), patch, reset, true)
    if format == nil then return false, "invalid" end
    local value = next(format) ~= nil and format or false
    if not R.CanRetryWrite(C.locationTableName, current, retry)
        and dmhub.DeepEqual(Field(current, "pinNameFormat", false), value) then
        if callbacks and callbacks.success then callbacks.success(nil) end
        return true
    end
    local description = reset and "Reset map pin text" or "Format map pin text"
    local step, operation = WriteLocation(current, { pinNameFormat = value }, description, callbacks, retry)
    if step == nil then return false, "unavailable", nil, operation end
    return true, nil, Entry(description, { step }), operation
end

--- Director-only map-aid writes share the row lock, receipt and guarded Undo machinery.
--- @param id string
--- @param kind string
--- @param patch table
--- @param action string
--- @param callbacks nil|OverlandMapWriteCallbacks
--- @param retry nil|OverlandMapRetry
--- @return boolean, nil|OverlandMapWriteReason, nil|OverlandMapUndoEntry, nil|OverlandMapWrite
function OverlandMapModel.SetMapAid(id, kind, patch, action, callbacks, retry)
    if not IsDirector() or not CanWrite() then return false, "permission" end
    local current = Raw(id)
    if current == nil or current.imageId == "" or (kind ~= "compass" and kind ~= "scaleBar") then return false, "invalid" end
    if R.PendingWrite(C.locationTableName, id) then return false, "busy" end
    local stored = Field(current, "mapAids", nil)
    local aids = type(stored) == "table" and DeepCopy(stored) or {}
    if action == "remove" then
        aids[kind] = nil
    elseif action == "add" or action == "edit" then
        if action == "edit" and type(aids[kind]) ~= "table" then return false, "invalid" end
        if action == "add" and type(aids[kind]) == "table" and not R.CanRetryWrite(C.locationTableName, current, retry) then return false, "invalid" end
        if action == "add" and kind == "scaleBar" then
            local scale = Field(current, "scale", nil)
            if scale == nil or not R.ValidScale(scale) or (scale.u1 == scale.u2 and scale.v1 == scale.v2) then return false, "invalid" end
        end
        aids[kind] = R.ApplyMapAidPatch(aids[kind], kind, patch)
        if aids[kind] == nil or (action == "add" and kind == "scaleBar" and not IsFinite(aids[kind].distance)) then return false, "invalid" end
    else return false, "invalid" end
    local value = next(aids) ~= nil and aids or false
    if not R.CanRetryWrite(C.locationTableName, current, retry) and dmhub.DeepEqual(stored or false, value) then return true end
    local description = (action == "remove" and "Remove " or action == "add" and "Add " or "Edit ") .. (kind == "compass" and "map compass" or "map scale bar")
    local step, operation = WriteLocation(current, { mapAids = value }, description, callbacks, retry)
    if step == nil then return false, "unavailable", nil, operation end
    return true, nil, Entry(description, { step }), operation
end

local NewLocationRow

--- The style a new pin starts with (R10: copied from the last one placed).
--- @class OverlandMapPinStyle
--- @field icon nil|string
--- @field importance nil|"major"|"normal"|"minor"
--- @field pinStyle nil|"iconName"|"plate"|"iconOnly"
--- @field visibility nil|"hidden"|"revealed" Director only; players' Locations are always revealed

--- Create a Location at a point of a map. Director-made Locations start Hidden
--- unless style says otherwise; player-made ones are Revealed (R1). Without a
--- name it starts empty and the UI shows edit.name.fallback until it is named.
--- @param mapId string
--- @param u number
--- @param v number
--- @param style nil|OverlandMapPinStyle
--- @param callbacks nil|OverlandMapWriteCallbacks the new row is readable only after success
--- @param name nil|string set at creation (JSON import), so the row needs no second write
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
--- @return nil|string id
function OverlandMapModel.CreateLocation(mapId, u, v, style, callbacks, name)
    name = R.TrimSingleLine(name)
    if not IsFinite(u) or not IsFinite(v) or not ValidName(name) then return false, "invalid", nil, nil end
    local ok, reason = CanAdd(mapId)
    if not ok then return false, reason, nil, nil end
    local step, id = NewLocationRow(mapId, u, v, style, callbacks, name)
    if step == nil then return false, "unavailable", nil, nil end
    return true, nil, Entry("Add overland map location", { step }), id
end

--- One import item for CreateLocations.
--- @class OverlandMapNewLocation
--- @field u number
--- @field v number
--- @field style nil|OverlandMapPinStyle
--- @field name string
--- @field callbacks nil|OverlandMapWriteCallbacks

--- Create several Locations on one map after one permission check (JSON import), so a
--- long import does not rebuild the whole Location index once per row.
--- @param mapId string
--- @param items OverlandMapNewLocation[]
--- @return boolean ok false when the viewer may not add here; nothing was written
--- @return nil|OverlandMapWriteReason reason
--- @return {id: nil|string, step: nil|OverlandMapUndoStep}[] results one per item; step nil when that row was invalid or its upload did not start
function OverlandMapModel.CreateLocations(mapId, items)
    local ok, reason = CanAdd(mapId)
    if not ok then return false, reason, {} end
    local results = {}
    for i, item in ipairs(items) do
        local name = R.TrimSingleLine(item.name)
        if IsFinite(item.u) and IsFinite(item.v) and ValidName(name) then
            local step, id = NewLocationRow(mapId, item.u, item.v, item.style, item.callbacks, name)
            results[i] = { id = id, step = step }
        else
            results[i] = {}
        end
    end
    return true, nil, results
end

-- Writes a new Location row; the caller already checked the name, position and CanAdd.
NewLocationRow = function(mapId, u, v, style, callbacks, name)
    style = style or {}
    local director = IsDirector()
    local visibility = "revealed"
    if director then visibility = R.visibilities[style.visibility] and style.visibility or "hidden" end
    local id = dmhub.GenerateGuid()
    local step = WriteLocation(nil, {
        id = id, schemaVersion = C.locationSchemaVersion, parentId = mapId, name = name,
        u = Clamp(u, 0, 1), v = Clamp(v, 0, 1),
        pinStyle = R.pinStyles[style.pinStyle] and style.pinStyle or "iconName",
        importance = R.importances[style.importance] and style.importance or "normal",
        icon = type(style.icon) == "string" and #style.icon <= C.journalIdLimit and style.icon or "",
        visibility = visibility, imageId = "", imageRevision = 0, mapShared = false,
        ownerId = dmhub.loginUserid, ownerName = CurrentUserName(), createdByDirector = director,
        hidden = false,
    }, "Add overland map location", callbacks)
    return step, id
end

--- Whether a map is a point crawl map; an omitted mode means free.
--- @param location nil|OverlandMapLocationRecord
--- @return boolean
function OverlandMapModel.IsPointCrawl(location)
    return location ~= nil and Field(location, "mode", nil) == "pointcrawl"
end

-- Free maps omit the optional mode field.
local function StoredMode(mode)
    if mode == "pointcrawl" then return "pointcrawl" end
    return nil
end

--- Create a top-level map (Atlas "New map"). Starts not shared (R1).
--- @param name string
--- @param imageId string
--- @param callbacks nil|OverlandMapWriteCallbacks the new row is readable only after success
--- @param mode nil|"free"|"pointcrawl" fixed for the map's life (A4)
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
--- @return nil|string id
function OverlandMapModel.CreateMap(name, imageId, callbacks, mode)
    name = R.TrimSingleLine(name)
    if not CanWrite() or not IsDirector() then return false, "permission", nil, nil end
    if not ValidText(name) or type(imageId) ~= "string" or imageId == "" then return false, "invalid", nil, nil end
    local id = dmhub.GenerateGuid()
    local step = WriteLocation(nil, {
        id = id, schemaVersion = C.locationSchemaVersion, parentId = "", name = name, u = 0.5, v = 0.5,
        pinStyle = "iconName", importance = "normal", icon = "", visibility = "revealed",
        imageId = imageId, imageRevision = 1, mapShared = false, border = OverlandMapModel.LastBorder(),
        mode = StoredMode(mode),
        ownerId = dmhub.loginUserid, ownerName = CurrentUserName(), createdByDirector = true, hidden = false,
    }, "Create overland map", callbacks)
    if step == nil then return false, "unavailable", nil, nil end
    return true, nil, Entry("Create overland map", { step }), id
end

--- @param id string
--- @param u number
--- @param v number
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapModel.MoveLocation(id, u, v)
    return UpdateLocation(id, { u = u, v = v }, "Move overland map location")
end

--- Move a Location (and everything under it) onto another map, at its middle.
--- @param id string
--- @param mapId string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapModel.MoveToMap(id, mapId)
    local current = Raw(id)
    if current == nil or current.parentId == "" or IsInSubtree(id, mapId) then return false, "invalid", nil end
    if not CanEdit(current) then return false, "permission", nil end
    if current.parentId == mapId then return true, nil, Entry("Move overland map location", {}) end
    local ok, reason = CanAdd(mapId)
    if not ok then return false, reason, nil end
    -- Its paths join pins on the map it leaves, so they go with the move (B5).
    local paths = OverlandMapPaths.Touching({ [id] = true })
    if R.PendingWrite(C.locationTableName, id) or OverlandMapPaths.AnyPending(paths) then return false, "busy", nil end
    local description = "Move overland map location to map"
    local partyTarget = OverlandMapModel.PartyOffPaths(paths, { [id] = true })
    local steps, operations = OverlandMapPaths.HideSteps(paths, description)
    local entry = Entry(description, steps)
    entry.operations = operations
    local step = WriteLocation(current, { parentId = mapId, u = 0.5, v = 0.5 }, description)
    OverlandMapCommands.Append(entry, step, C.locationTableName, id)
    if partyTarget ~= nil then
        local partyStep = step ~= nil and OverlandMapModel.MovePartyOff(partyTarget, description) or nil
        OverlandMapCommands.Append(entry, partyStep, nil, C.stateDocumentId)
    end
    if #entry.steps == 0 then return false, "unavailable", entry end
    return true, nil, entry
end

--- @param id string
--- @param visibility "hidden"|"revealed"
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapModel.SetVisibility(id, visibility)
    if not IsDirector() then return false, "permission", nil end
    return UpdateLocation(id, { visibility = visibility }, "Change location visibility")
end

--- @param id string
--- @param shared boolean
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapModel.SetMapShared(id, shared)
    if not IsDirector() then return false, "permission", nil end
    return UpdateLocation(id, { mapShared = shared }, "Change map sharing")
end

-- Sets a Location's image. Every new image bumps imageRevision, so cameras
-- saved for the old image are not reused.
local function SetImage(id, imageId, description, mode)
    local current = Raw(id)
    if not IsDirector() or not CanWrite() then return false, "permission", nil end
    if current == nil or type(imageId) ~= "string" or imageId == "" then return false, "invalid", nil end
    if current.imageRevision >= C.maxRevision then return false, "unavailable", nil end
    if R.PendingWrite(C.locationTableName, id) then return false, "busy", nil end
    local changes = { imageId = imageId, imageRevision = current.imageRevision + 1 }
    -- New maps start not shared (R1) with the last border picked (K5) and their
    -- chosen mode (A1); a replaced image keeps its sharing, border and mode.
    if current.imageId == "" then
        changes.mapShared = false
        changes.border = OverlandMapModel.LastBorder()
        changes.mode = StoredMode(mode) or false
    end
    local step = WriteLocation(current, changes, description)
    if step == nil then return false, "unavailable", nil end
    return true, nil, Entry(description, { step })
end

--- How a map's image edge draws (K1). Maps from before borders have none.
--- @param location OverlandMapLocationRecord
--- @return "none"|"fade"|"torn"|"frame"
function OverlandMapModel.Border(location)
    local border = Field(location, "border", nil)
    if R.borders[border] then return border --[[@as "none"|"fade"|"torn"|"frame"]] end
    return "none"
end

--- Game-wide: the border the Director picked last, which new maps start with (K5, K8).
--- @return "none"|"fade"|"torn"|"frame"
function OverlandMapModel.LastBorder()
    local data = StateData()
    local border = data and data.lastBorder
    if R.borders[border] then return border --[[@as "none"|"fade"|"torn"|"frame"]] end
    return C.defaultBorder --[[@as "none"|"fade"|"torn"|"frame"]]
end

--- Set a map's border and remember it for the next new map. The returned undo
--- entry covers the border only; the remembered pick just seeds new maps.
--- @param id string
--- @param border "none"|"fade"|"torn"|"frame"
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapModel.SetBorder(id, border)
    if not IsDirector() then return false, "permission", nil end
    local ok, reason, undo = UpdateLocation(id, { border = border }, "Change map border")
    if ok and OverlandMapModel.LastBorder() ~= border then
        WriteState("Remember the map border", function(data) data.lastBorder = border end)
    end
    return ok, reason, undo
end

--- Give a Location without a map its own map image.
--- @param id string
--- @param imageId string
--- @param mode nil|"free"|"pointcrawl" fixed for the map's life (A4)
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapModel.AddMap(id, imageId, mode)
    local current = Raw(id)
    if current ~= nil and current.imageId ~= "" then return false, "invalid", nil end
    return SetImage(id, imageId, "Add map to location", mode)
end

--- Replace a map's image while preserving normalized pin positions.
--- @param id string
--- @param imageId string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapModel.ReplaceImage(id, imageId)
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
    --- @type OverlandMapPartyView
    local result = { mapId = party.mapId, u = party.u, v = party.v, locationId = nil, revision = R.RecordRevision(party) }
    local location = Raw(party.locationId)
    if location ~= nil and location.parentId ~= "" and Raw(location.parentId) ~= nil then
        result.mapId, result.u, result.v, result.locationId = location.parentId, location.u, location.v, location.id
    elseif type(party.pathId) == "string" then
        -- Partway along a path the banner follows the path's line, so editing its bends or
        -- time never strands it (Q13). A path that is gone leaves it where it was drawn.
        local path = OverlandMapPaths.Index().byId[party.pathId]
        local from, spent = party.pathFrom, party.spent
        if path ~= nil and path.mapId == party.mapId and (from == path.aId or from == path.bId) and IsFinite(spent) and spent > 0 then
            result.u, result.v = OverlandMapTravel.PositionOn(path, from, spent)
            result.pathId, result.pathFrom, result.spent = path.id, from, spent
        end
    end
    return result
end

--- Where the Party is, as the viewer may know it: nil when it is not placed or
--- on a map the viewer cannot open; locationId only when they see that pin (R3).
--- @return nil|OverlandMapPartyView
function OverlandMapModel.Party()
    local party = StoredParty()
    if party == nil or not CanOpenMap(Raw(party.mapId)) then return nil end
    if party.locationId ~= nil and not CanSeePin(Raw(party.locationId)) then party.locationId = nil end
    -- A player who does not see the path sees the Party on the map, not on a path.
    if party.pathId ~= nil and not OverlandMapPaths.CanSee(OverlandMapPaths.Index().byId[party.pathId]) then
        party.pathId, party.pathFrom, party.spent = nil, nil, nil
    end
    return party
end
local Party = OverlandMapModel.Party

--- The Party status for the status chip, relative to the open map.
--- @param currentMapId nil|string
--- @return "at"|"onPath"|"traveling"|"elsewhere"|"none" kind
--- @return nil|OverlandMapPartyView party
--- @return nil|OverlandMapLocationRecord location set for "at"
function OverlandMapModel.PartyStatus(currentMapId)
    local party = Party()
    if party == nil then return "none", nil, nil end
    if party.mapId ~= currentMapId then return "elsewhere", party, nil end
    if party.locationId ~= nil then return "at", party, Raw(party.locationId) end
    if party.pathId ~= nil then return "onPath", party, nil end
    return "traveling", party, nil
end

--- Whether the viewer may move the Party on this map.
--- @param mapId string
--- @return boolean
function OverlandMapModel.CanMovePartyOn(mapId)
    if not CanWrite() or StateData() == nil or not CanOpenMap(Raw(mapId)) then return false end
    return IsDirector() or OverlandMapModel.PlayersCanMoveParty()
end
local CanMovePartyOn = OverlandMapModel.CanMovePartyOn

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

--- What WriteParty is asked to do.
--- @class OverlandMapPartyWrite
--- @field mapId string
--- @field u nil|number
--- @field v nil|number
--- @field locationId nil|string "at" this Location, snapped to its pin
--- @field pathId nil|string partway along this path (Director stop, Q13); u/v follow from spent
--- @field pathFrom nil|string
--- @field spent nil|number
--- @field description nil|string
--- @field placed nil|boolean a jump, logged as placed rather than as travel
--- @field travel nil|boolean a move along a path (OverlandMapTravel), the only player move on point crawl maps (G5)
--- @field noLog nil|boolean the caller writes its own log entry (legs and stops)

--- Move the Party. With locationId it is "at" that Location (snapped to its
--- pin); with pathId it is partway along that path; else it is traveling at
--- u/v. A player can never snap it to a pin they cannot see (R3).
--- @param args OverlandMapPartyWrite
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapModel.WriteParty(args)
    if StateData() == nil then return false, "unavailable", nil end
    if not CanMovePartyOn(args.mapId) then return false, "permission", nil end
    -- On a point crawl map players move only by travelling along paths (Q16).
    if not IsDirector() and args.travel ~= true and OverlandMapModel.IsPointCrawl(Raw(args.mapId)) then
        return false, "permission", nil
    end
    local u, v, locationId = args.u, args.v, nil
    local pathId, pathFrom, spent = nil, nil, nil
    if args.locationId ~= nil then
        local location = Raw(args.locationId)
        if location == nil or location.parentId ~= args.mapId or not CanSeePin(location) then return false, "invalid", nil end
        u, v, locationId = location.u, location.v, location.id
    elseif args.pathId ~= nil then
        local path = OverlandMapPaths.Get(args.pathId)
        if not IsDirector() or path == nil or path.mapId ~= args.mapId or (args.pathFrom ~= path.aId and args.pathFrom ~= path.bId)
            or not IsFinite(args.spent) or args.spent <= 0 then
            return false, "invalid", nil
        end
        u, v = OverlandMapTravel.PositionOn(path, args.pathFrom --[[@as string]], args.spent --[[@as number]])
        pathId, pathFrom, spent = path.id, args.pathFrom, args.spent
    end
    if not IsFinite(u) or not IsFinite(v) then return false, "invalid", nil end
    local description = args.description or "Move Party on overland map"
    local before = StoredParty()
    local after = {
        mapId = args.mapId, u = Clamp(u --[[@as number]], 0, 1), v = Clamp(v --[[@as number]], 0, 1), locationId = locationId,
        pathId = pathId, pathFrom = pathFrom, spent = spent,
    }
    local step = SetParty(DeepCopy(after), description)
    if step == nil then return false, "unavailable", nil end
    -- The session log entry undoes with the move (R3); a failed log write leaves the move standing.
    local entry = Entry(description, { step })
    if args.noLog ~= true then
        local logStep = OverlandMapLog.Record(before, after, args.placed == true)
        OverlandMapCommands.Append(entry, logStep, C.logTableName)
    end
    return true, nil, entry
end
local WriteParty = OverlandMapModel.WriteParty

--- Where the Party is, unfiltered: what travel and the log compare against.
--- @return nil|OverlandMapPartyView
function OverlandMapModel.StoredParty()
    return StoredParty()
end

--- Director: put the Party anywhere on any map (R12 "Place Party here").
--- With locationId (a point crawl pin near the click, Q16) it is "at" that pin.
--- @param mapId string
--- @param u number
--- @param v number
--- @param locationId nil|string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
function OverlandMapModel.PlaceParty(mapId, u, v, locationId)
    if not IsDirector() then return false, "permission", nil end
    return WriteParty {
        mapId = mapId, u = u, v = v, locationId = locationId, description = "Place Party on overland map", placed = true,
    }
end

--- Cascades (B5, Q13): when these paths go, a Party stopped on one of them
--- moves to its nearer end, or the other end when the nearer one goes too.
--- Read this before the batch hides anything (hidden rows leave the index);
--- nil when the Party is not on them or has nowhere to go.
--- @param paths OverlandMapPathRecord[]
--- @param removed table<string, boolean> Location ids going in the same batch
--- @return nil|table the party to write with MovePartyOff
function OverlandMapModel.PartyOffPaths(paths, removed)
    local party = StoredParty()
    if party == nil or party.pathId == nil or party.pathFrom == nil or StateData() == nil then return nil end
    local from = party.pathFrom --[[@as string]]
    for _, path in ipairs(paths) do
        if path.id == party.pathId then
            local far = OverlandMapPaths.OtherEnd(path, from)
            local nearer, other = far, from
            if OverlandMapTravel.Fraction(path, from, party.spent or 0) <= 0.5 then
                nearer, other = from, far
            end
            if removed[nearer] then nearer = other end
            local location = Raw(nearer)
            if location == nil or removed[nearer] then return nil end
            return { mapId = location.parentId, u = location.u, v = location.v, locationId = location.id }
        end
    end
    return nil
end
local PartyOffPaths = OverlandMapModel.PartyOffPaths

--- Write the target PartyOffPaths chose, in the caller's batch; its undo step.
--- @param target table
--- @param description string
--- @return nil|OverlandMapUndoStep
function OverlandMapModel.MovePartyOff(target, description)
    if not CanWrite() or StateData() == nil then return nil end
    return SetParty(DeepCopy(target), description)
end

-- Deletion ------------------------------------------------------------------------------------

-- Hides each Location (deepest first, so no child outlives its parent on
-- another client mid-batch) and returns the steps that started.
local function HideAll(locations, description)
    local steps = {}
    for i = #locations, 1, -1 do
        local step = WriteLocation(locations[i], { hidden = true }, description)
        if step ~= nil then
            steps[#steps + 1] = step
            for _, companion in ipairs(companions) do
                if companion.cancelMap then companion.cancelMap(locations[i].id) end
            end
        end
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

-- Each companion's rows on the maps going away, read before anything is hidden.
local function CompanionRows(mapIds)
    local result = {}
    for _, companion in ipairs(companions) do
        if companion.rowsOnMaps then result[#result + 1] = { companion = companion, rows = companion.rowsOnMaps(mapIds) } end
    end
    return result
end

local function CompanionsPending(groups)
    for _, group in ipairs(groups) do
        if group.companion.anyPending and group.companion.anyPending(group.rows) then return true end
    end
    return false
end

-- Hide the companions' rows in the caller's batch; their unsent edits are dropped first.
local function HideCompanionRows(groups, description, steps)
    for _, group in ipairs(groups) do
        local companion = group.companion
        for _, row in ipairs(group.rows) do
            if companion.cancelRow then companion.cancelRow(row.id) end
        end
        if companion.hideSteps then
            for _, step in ipairs(companion.hideSteps(group.rows, description)) do steps[#steps + 1] = step end
        end
    end
end

--- Whether the viewer may delete a Location. Players delete only their own
--- Locations, and only while they have no map: only the Director adds maps, so
--- a map and everything pinned on it is Director content (decision 2026-10-07).
--- @param location nil|OverlandMapLocationRecord
--- @return boolean
function OverlandMapModel.CanDelete(location)
    if location == nil or not CanEdit(location) then return false end
    if IsDirector() then return true end
    return location.parentId ~= "" and location.imageId == ""
end

--- @class OverlandMapDeletionPlan
--- @field id string
--- @field removeMap boolean
--- @field locations table<string, boolean>
--- @field maps table<string, boolean>
--- @field descendants integer
--- @field paths integer
--- @field labels integer
--- @field partyTarget any
--- @field consequences table

--- The dialog and execution compare consequences, then execution rechecks permissions.
--- @param id string
--- @param removeMap boolean
--- @return nil|OverlandMapDeletionPlan
function OverlandMapModel.PlanDeletion(id, removeMap)
    local current = Raw(id)
    if current == nil or not OverlandMapModel.CanDelete(current) then return nil end
    if removeMap and (not IsDirector() or current.parentId == "" or current.imageId == "") then return nil end
    local locations, maps, ids = {}, { [id] = true }, {}
    for _, row in ipairs(Descendants(id)) do locations[row.id], maps[row.id] = true, true end
    if not removeMap then locations[id] = true end
    for key in pairs(locations) do ids[#ids + 1] = key end
    table.sort(ids)
    local paths, pathIds = OverlandMapPaths.Touching(locations), {}
    for _, row in ipairs(paths) do pathIds[#pathIds + 1] = row.id end
    table.sort(pathIds)
    local labelIds = {}
    for _, group in ipairs(CompanionRows(maps)) do
        if group.companion.tableName == C.labelTableName then
            for _, row in ipairs(group.rows) do labelIds[#labelIds + 1] = row.id end
        end
    end
    table.sort(labelIds)
    local target = RescueTarget(current, maps)
    if removeMap and target ~= nil then
        target = { mapId = current.parentId, locationId = id, u = current.u, v = current.v }
    elseif target == nil then target = PartyOffPaths(paths, locations) end
    local count = OverlandMapModel.VisibleDescendantCount(id)
    local consequences = { ids = ids, pathIds = pathIds, labelIds = labelIds, party = target,
        name = current.name, image = current.imageId, parent = current.parentId, count = count }
    return { id = id, removeMap = removeMap, locations = locations, maps = maps, descendants = count,
        paths = OverlandMapPaths.CountVisible(paths), labels = #labelIds, partyTarget = target,
        consequences = consequences }
end

local function DeletionEntry(description, steps, plan)
    local byRow, operations, partySubmitted = {}, {}, false
    for _, step in ipairs(steps) do
        if step.tableName then byRow[step.tableName .. ":" .. step.id] = step
        else
            partySubmitted = true
            operations[#operations + 1] = { outcome = "submitted", step = step }
        end
    end
    local function Row(tableName, id)
        local step = byRow[tableName .. ":" .. id]
        operations[#operations + 1] = { tableName = tableName, id = id, step = step,
            receipt = step and step.receipt, outcome = step and "accepted" or "failed" }
    end
    for id in pairs(plan.locations) do Row(C.locationTableName, id) end
    if plan.removeMap then Row(C.locationTableName, plan.id) end
    for _, id in ipairs(plan.consequences.pathIds) do Row(C.pathTableName, id) end
    for _, id in ipairs(plan.consequences.labelIds) do Row(C.labelTableName, id) end
    if plan.partyTarget ~= nil and not partySubmitted then
        operations[#operations + 1] = { outcome = "failed" }
    end
    return { description = description, steps = steps, operations = operations }
end

--- Delete a Location and its whole subtree in one batch. A Party inside moves
--- to the deleted Location's spot on its parent map (D7d). Details and notes
--- rows are left in place: nothing shows them, and undo needs them intact.
--- @param id string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
--- @return integer count Locations deleted besides this one
function OverlandMapModel.DeleteLocation(id, approved)
    local current = Raw(id)
    if current == nil then return false, "invalid", nil, 0 end
    if not OverlandMapModel.CanDelete(current) then return false, "permission", nil, 0 end
    local plan = OverlandMapModel.PlanDeletion(id, false)
    if approved and (plan == nil or not dmhub.DeepEqual(approved.consequences, plan.consequences)) then
        return false, "changed", nil, 0
    end
    local descendants = Descendants(id)
    local all = { current }
    for _, location in ipairs(descendants) do all[#all + 1] = location end
    local removed = {}
    for _, location in ipairs(all) do removed[location.id] = true end
    -- A path always joins two pins, so every path touching a deleted pin goes too (B5).
    local paths = OverlandMapPaths.Touching(removed)
    local groups = CompanionRows(removed)
    if AnyPending(all) or OverlandMapPaths.AnyPending(paths) or CompanionsPending(groups) then
        return false, "busy", nil, 0
    end
    local description = "Delete overland map location"
    local target = RescueTarget(current, removed)
    local pathTarget = target == nil and PartyOffPaths(paths, removed) or nil
    local steps = HideAll(all, description)
    if #steps == 0 then return false, "unavailable", DeletionEntry(description, steps, plan), 0 end
    for _, step in ipairs(OverlandMapPaths.HideSteps(paths, description)) do steps[#steps + 1] = step end
    HideCompanionRows(groups, description, steps)
    -- The Party moves only once the rows are on their way, so a failed delete leaves it be.
    if target ~= nil then
        local partyStep = SetParty(target or nil, description)
        if partyStep ~= nil then steps[#steps + 1] = partyStep end
    elseif pathTarget ~= nil then
        local partyStep = SetParty(pathTarget, description)
        if partyStep ~= nil then steps[#steps + 1] = partyStep end
    end
    return true, nil, DeletionEntry(description, steps, plan), #descendants
end

--- Remove a Location's map image; the Locations pinned on it (and below) are
--- deleted (copy 17.5). Top-level maps are deleted instead, never emptied.
--- @param id string
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
--- @return nil|OverlandMapUndoEntry undo
--- @return integer count Locations deleted
function OverlandMapModel.RemoveMap(id, approved)
    local current = Raw(id)
    if not IsDirector() or not CanWrite() then return false, "permission", nil, 0 end
    if current == nil or current.parentId == "" or current.imageId == "" then return false, "invalid", nil, 0 end
    local plan = OverlandMapModel.PlanDeletion(id, true)
    if approved and (plan == nil or not dmhub.DeepEqual(approved.consequences, plan.consequences)) then
        return false, "changed", nil, 0
    end
    local descendants = Descendants(id)
    local removed = {}
    for _, location in ipairs(descendants) do removed[location.id] = true end
    local paths = OverlandMapPaths.Touching(removed)
    -- Rows drawn on the removed map itself go too, not only those on the maps below it.
    local mapIds = DeepCopy(removed)
    mapIds[id] = true
    local groups = CompanionRows(mapIds)
    if R.PendingWrite(C.locationTableName, id) or AnyPending(descendants) or OverlandMapPaths.AnyPending(paths)
        or CompanionsPending(groups) then
        return false, "busy", nil, 0
    end
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
    for _, step in ipairs(OverlandMapPaths.HideSteps(paths, description)) do steps[#steps + 1] = step end
    HideCompanionRows(groups, description, steps)
    -- The mode goes with the image, so Add map can pick it again (A4).
    local own = WriteLocation(current, { imageId = "", mapShared = false, scale = false, pace = false, mode = false, mapAids = false,
        pinNameFormat = false }, description)
    if own == nil then return #steps > 0, #steps == 0 and "unavailable" or nil, DeletionEntry(description, steps, plan), #descendants end
    for _, companion in ipairs(companions) do
        if companion.cancelMap then companion.cancelMap(id) end
    end
    steps[#steps + 1] = own
    if partyTarget ~= nil then
        local partyStep = SetParty(partyTarget, description)
        if partyStep ~= nil then steps[#steps + 1] = partyStep end
    end
    return true, nil, DeletionEntry(description, steps, plan), #descendants
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
    if step.state ~= nil then
        local meta = type(data.stateMeta) == "table" and data.stateMeta[step.state] or nil
        return R.RecordRevision(meta), Field(meta, "mutationId", nil)
    end
    if type(data.party) == "table" then return R.RecordRevision(data.party), Field(data.party, "mutationId", nil) end
    return R.RecordRevision({ revision = data.partyRevision }), data.partyMutationId
end

--- True when none of an entry's table writes is still waiting for the server.
--- Undo waits for this: a row with a write in flight cannot be written again.
--- @param entry OverlandMapUndoEntry
--- @return boolean
function OverlandMapModel.IsSettled(entry)
    for _, step in ipairs(entry.steps) do
        if step.tableName ~= nil and R.PendingWrite(step.tableName, step.id) then return false end
    end
    return true
end

-- Whether one step is still exactly as this client left it and the viewer may restore it.
local function StepMatches(step, entry)
    if step.receipt ~= nil and step.receipt.status ~= "confirmed" then return false end
    local revision, mutationId = StepCurrent(step)
    if revision ~= step.afterRevision or mutationId ~= step.afterMutationId then return false end
    for _, guard in ipairs(step.guards or {}) do
        if PendingWrite(guard.tableName, guard.id) then return false end
        local row = (dmhub.GetTable(guard.tableName) or {})[guard.id]
        if R.RecordRevision(row) ~= guard.revision or Field(row, "mutationId", nil) ~= guard.mutationId then return false end
    end
    for _, companion in ipairs(companions) do
        if companion.tableName == step.tableName and companion.canRevertStep
            and not companion.canRevertStep(step, entry) then return false end
    end
    if not IsDirector() then
        if step.tableName == C.notesTableName then return false end
        if step.tableName == C.pathTableName then
            local current = (dmhub.GetTable(C.pathTableName) or {})[step.id]
            local restoringDeletedPin = false
            if current and current.hidden and step.before then
                for _, other in ipairs(entry.steps) do
                    if other.tableName == C.locationTableName and other.before
                        and (step.before.aId == other.id or step.before.bId == other.id)
                        and OverlandMapModel.CanDelete(other.before) then restoringDeletedPin = true end
                end
            end
            if not restoringDeletedPin then return false end
        end
        if step.tableName == C.detailsTableName and not CanEdit(Raw(step.id)) then return false end
        if step.tableName == C.locationTableName and not CanEdit(Raw(step.id) or step.before) then return false end
    end
    if not IsDirector() and step.before ~= nil
        and (step.tableName == C.locationTableName or step.tableName == C.pathTableName) then
        local current = (dmhub.GetTable(step.tableName) or {})[step.id]
        if not dmhub.DeepEqual(R.ArtworkValue(current), R.ArtworkValue(step.before)) then return false end
        if step.tableName == C.locationTableName
            and not dmhub.DeepEqual(Field(current, "pinNameFormat", false), Field(step.before, "pinNameFormat", false)) then return false end
        if step.tableName == C.locationTableName
            and not dmhub.DeepEqual(Field(current, "mapAids", false), Field(step.before, "mapAids", false)) then return false end
    end
    return true
end

--- Protect descriptions and notes edited after import, even though Undo only hides the pin.
--- @param step OverlandMapUndoStep
function OverlandMapModel.GuardLocationUndo(step)
    if step.id == nil then return end
    step.guards = {}
    for _, tableName in ipairs({ C.detailsTableName, C.notesTableName }) do
        local operation = LastWrite(tableName, step.id)
        local row = operation and operation.record or nil
        step.guards[#step.guards + 1] = {
            tableName = tableName, id = step.id,
            revision = R.RecordRevision(row), mutationId = Field(row, "mutationId", nil),
        }
    end
end

--- Whether every step of an entry is still exactly as this client left it.
--- False after anyone else changed one of the rows (R14). A partial entry (an import:
--- independent new rows) stays undoable while any of its rows is untouched.
--- @param entry OverlandMapUndoEntry
--- @return boolean
function OverlandMapModel.CanRevert(entry)
    if not CanWrite() or #entry.steps == 0 then return false end
    for _, operation in ipairs(entry.operations or {}) do
        if operation.outcome == "failed" and not entry.partial then return false end
    end
    local any = false
    for _, step in ipairs(entry.steps) do
        if StepMatches(step, entry) then any = true
        elseif not entry.partial then return false end
    end
    return any
end

--- A row (or the Party) that an undo rewrote: the state it restored, and the
--- revision that state now carries. Older undo entries that ended in the
--- restored state are moved onto the new revision, so they stay undoable.
--- @class OverlandMapRebind
--- @field tableName nil|string nil for the Party and state steps
--- @field state nil|string set for a state step
--- @field id nil|string
--- @field fromRevision integer
--- @field fromMutationId nil|string
--- @field toRevision integer
--- @field toMutationId string

--- Undo an entry: restore each step's earlier row (a created row is hidden)
--- with a new revision. Partial imports skip changed pins; other entries require every step.
--- Reverts are not themselves undoable.
--- @param entry OverlandMapUndoEntry
--- @return boolean ok
--- @return OverlandMapRebind[] rebinds
function OverlandMapModel.Revert(entry)
    local rebinds = {} --- @type OverlandMapRebind[]
    if not OverlandMapModel.CanRevert(entry) then return false, rebinds end
    local ok = true
    for i = #entry.steps, 1, -1 do
        local step = entry.steps[i]
        if entry.partial and not StepMatches(step, entry) then
            -- Someone changed this row since; a partial entry leaves it and undoes the rest.
        elseif step.tableName ~= nil then
            -- Unsent autosave edits of this row would write the undone values back.
            for _, companion in ipairs(companions) do
                if companion.tableName == step.tableName and companion.cancelRow then companion.cancelRow(step.id) end
            end
            if step.tableName == C.locationTableName then
                for _, owner in ipairs(companions) do if owner.cancelMap then owner.cancelMap(step.id) end end
            end
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
        elseif step.state ~= nil then
            local before = step.stateBefore
            if before == false then before = nil end
            local written = OverlandMapModel.WriteStateKey(step.state, before, "Undo: " .. entry.description)
            ok = written ~= nil and ok
            if written ~= nil then
                rebinds[#rebinds + 1] = {
                    state = step.state,
                    fromRevision = step.stateBeforeRevision or 0, fromMutationId = step.stateBeforeMutationId,
                    toRevision = written.afterRevision, toMutationId = written.afterMutationId,
                }
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
function OverlandMapModel.PlayersCanMoveParty()
    local data = StateData()
    return data ~= nil and data.playerCanMoveParty == true
end

--- @param value boolean
--- @return boolean written
--- @return nil|OverlandMapWriteReason reason
function OverlandMapModel.SetPlayersCanMoveParty(value)
    if not IsDirector() then return false, "permission" end
    return WriteState("Change who can move the Party", function(data)
        data.playerCanMoveParty = value == true
    end)
end

-- Location content: description, journal link, Director notes ----------------------------------

--- A Location's description and journal link as the viewer may see them.
--- @class OverlandMapDetails
--- @field description string
--- @field journal OverlandMapJournalView the link resolved for this viewer
--- @field journalDocId string the stored link; "" for players
--- @field state "empty"|"available"|"unavailable"

--- @param id string
--- @return nil|OverlandMapDetails nil when the viewer may not see the Location
function OverlandMapModel.Details(id)
    if OverlandMapModel.GetLocation(id) == nil then return nil end
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
function OverlandMapModel.DirectorNote(id)
    if not IsDirector() or Raw(id) == nil then return nil, nil end
    local row, state = ReadSidecar(id, true)
    return Field(row, "note", ""), state
end

-- Separate rows give descriptions and private notes independent revision guards.
local function SaveSidecar(id, fields, private, callbacks, retry)
    local tableName, schema, recordType = SidecarSpec(private)
    if PendingWrite(tableName, id) then return false, "busy" end
    local current, state = ReadSidecar(id, private)
    if state == "unavailable" then return false, "unavailable" end
    local changed = false
    for key, value in pairs(fields) do
        if value ~= Field(current, key, "") then changed = true end
    end
    if not changed and not R.CanRetryWrite(tableName, current, retry) then
        if callbacks ~= nil and callbacks.success ~= nil then callbacks.success(nil) end
        return true, nil
    end
    local record = current and DeepCopy(current) or recordType.new {
        id = id, locationId = id, schemaVersion = schema, hidden = false, revision = 0,
    }
    if current == nil then
        if private then record.note = "" else record.description, record.journalDocId = "", "" end
    end
    for key, value in pairs(fields) do record[key] = value end
    local description = private and "Save Director note" or "Save location details"
    local step, operation = R.WriteRow(tableName, current, record, description, callbacks, { retry = retry })
    if step == nil then return false, "unavailable", nil, operation end
    return true, nil, Entry(description, { step }), operation
end

--- Save a Location's description and/or journal link. Linking is Director only.
--- @param id string
--- @param patch {description: nil|string, journalDocId: nil|string}
--- @param callbacks nil|OverlandMapWriteCallbacks
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
function OverlandMapModel.SaveDetails(id, patch, callbacks, retry)
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
    return SaveSidecar(id, fields, false, callbacks, retry)
end

--- @param id string
--- @param note string
--- @param callbacks nil|OverlandMapWriteCallbacks
--- @return boolean ok
--- @return nil|OverlandMapWriteReason reason
function OverlandMapModel.SaveDirectorNote(id, note, callbacks, retry)
    if not IsDirector() or not CanWrite() or Raw(id) == nil then return false, "permission" end
    local normalized = NormalizeMultiline(note, C.noteLimit, C.noteByteLimit)
    if normalized == nil then return false, "invalid" end
    return SaveSidecar(id, { note = normalized }, true, callbacks, retry)
end

--- How this client's latest writes of one Location (row, details, notes)
--- stand, for the side panel's Saving / Saved / Not saved line.
--- @param id string
--- @return nil|"pending"|"confirmed"|"failed" nil when nothing was written
function OverlandMapModel.SaveStatus(id)
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

--- A name to show for a Location: its own, edit.name.fallback while unnamed,
--- or "" for no Location (a missing end, a deleted map).
--- @param location nil|OverlandMapLocationRecord
--- @return string plain text; escape it before it reaches a label
function OverlandMapModel.DisplayName(location)
    if location == nil then return "" end
    if location.name ~= "" then return location.name end
    return OverlandMapCopy.T("edit.name.fallback", nil, true)
end

--- The name of the Location with this id as the viewer may see it; "" when it
--- is gone or hidden from them.
--- @param id nil|string
--- @return string plain text
function OverlandMapModel.NameOf(id)
    return OverlandMapModel.DisplayName(OverlandMapModel.GetLocation(id))
end
