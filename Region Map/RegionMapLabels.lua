local mod = dmhub.GetModLoading()

--- Independent map lettering; visibility never participates in structural validation.
--- @class RegionMapMapLabelRecord: GameType, RegionMapAudit, RegionMapTextAppearanceFormat
--- @field new fun(o?: table): RegionMapMapLabelRecord
--- @field id string
--- @field mapId string
--- @field schemaVersion integer
--- @field text string
--- @field u number
--- @field v number
--- @field size number font size divided by map width
--- @field angle number clockwise degrees
--- @field font string
--- @field bold boolean
--- @field italics boolean
--- @field alignment string
--- @field spacing number extra character spacing in em
--- @field color string
--- @field background string
--- @field backgroundColor string
--- @field visibility string
--- @field ownerId string
--- @field ownerName string
--- @field revision integer
--- @field hidden boolean
RegionMapMapLabelRecord = RegisterGameType("RegionMapMapLabelRecord")
RegionMapMapLabelRecord.tableName = RegionMapConstants.labelTableName

--- @class RegionMapLabels: GameType
--- @field new fun(o?: table): RegionMapLabels
RegionMapLabels = RegisterGameType("RegionMapLabels")
local Labels = RegionMapLabels
local C, R, Model = RegionMapConstants, RegionMapRecords, RegionMapModel
local defaults = { font = "berling", bold = false, italics = false, alignment = "center",
    size = C.labelDefaultSize, spacing = 0, color = "#ffffffff", background = "auto", backgroundColor = "#000000bf" }
local formats = { font = true, bold = true, italics = true, alignment = true, size = true,
    spacing = true, color = true, background = true, backgroundColor = true }
for key, value in pairs(RegionMapTextAppearance.defaults) do defaults[key], formats[key] = value, true end

--- @return table<string, RegionMapMapLabelRecord>
function RegionMapLabels.Table()
    return (dmhub.GetTable(C.labelTableName) or {}) --[[@as table<string, RegionMapMapLabelRecord>]]
end

local function ValidFormat(key, value)
    if RegionMapTextAppearance.defaults[key] ~= nil then return RegionMapTextAppearance.Valid(key, value, false) end
    local typography = RegionMapTextAppearance.ValidTypography(key, value)
    if typography ~= nil then return typography end
    if key == "alignment" then return value == "left" or value == "center" or value == "right" end
    if key == "size" then return R.IsFinite(value) and value >= C.labelMinSize and value <= C.labelMaxSize end
    return false
end

--- Tolerate unavailable fonts and malformed optional formatting in stored rows/preferences.
--- @param row any
--- @return table<string, any>
function RegionMapLabels.Format(row)
    local result = {}
    for key, default in pairs(defaults) do
        local value = R.Field(row, key, nil)
        if ValidFormat(key, value) then result[key] = value else result[key] = default end
    end
    return result
end

RegionMapLabels.DisplayFont = RegionMapTextAppearance.DisplayFont

--- @param value any
--- @return nil|string
function RegionMapLabels.NormalizeText(value)
    return R.NormalizeMultiline(value, C.labelTextLimit, C.labelByteLimit)
end

--- @param row any
--- @param deleted nil|boolean
--- @return boolean
function RegionMapLabels.Valid(row, deleted)
    local text = R.Field(row, "text", nil)
    local id, mapId = R.Field(row, "id", nil), R.Field(row, "mapId", nil)
    local u, v = R.Field(row, "u", nil), R.Field(row, "v", nil)
    return type(id) == "string" and id ~= "" and type(mapId) == "string" and mapId ~= ""
        and R.Field(row, "schemaVersion", nil) == 1 and (deleted or R.Field(row, "hidden", true) == false)
        and Labels.NormalizeText(text) == text and text ~= "" and text ~= nil
        and R.IsFinite(u) and u >= 0 and u <= 1 and R.IsFinite(v) and v >= 0 and v <= 1
        and R.IsFinite(R.Field(row, "angle", nil)) and R.RecordRevision(row) >= 1
        and type(R.Field(row, "ownerId", nil)) == "string"
        and (R.Field(row, "visibility", nil) == "hidden" or R.Field(row, "visibility", nil) == "revealed")
end

local cached, cachedRevision, cachedMaps = nil, nil, nil
function RegionMapLabels.Index()
    local maps, revision = Model.Index(), Model.Revision()
    if cached ~= nil and revision == cachedRevision and maps == cachedMaps then return cached end
    local byId, onMap = {}, {}
    for id, row in pairs(Labels.Table()) do
        local write = R.LastWrite(C.labelTableName, id)
        if Labels.Valid(row) and row.id == id and not (write and write.creating and write.status ~= "confirmed") then
            local map = maps.byId[row.mapId]
            if map ~= nil and map.imageId ~= "" then
                byId[id] = row
                onMap[row.mapId] = onMap[row.mapId] or {}
                table.insert(onMap[row.mapId], row)
            end
        end
    end
    for _, list in pairs(onMap) do table.sort(list, function(a, b) return a.id < b.id end) end
    cached, cachedRevision, cachedMaps = { byId = byId, onMap = onMap }, revision, maps
    return cached
end

function RegionMapLabels.PlayersCanManage()
    local state = R.StateData()
    return state ~= nil and state.playersCanManageLabels == true
end

function RegionMapLabels.SetPlayersCanManage(value)
    if mod.unloaded or not Model.IsDirector() then return false end
    return Model.WriteStateKey("playersCanManageLabels", value == true, "Change who can manage map labels") ~= nil
end

function RegionMapLabels.CanSee(row)
    if row == nil or not Model.CanOpenMap(Model.GetLocation(row.mapId)) then return false end
    return Model.IsDirector() or row.visibility == "revealed"
end

function RegionMapLabels.CanAdd(mapId)
    return not mod.unloaded and not Model.ViewingAsPlayer()
        and Model.CanOpenMap(Model.GetLocation(mapId)) and (Model.IsDirector() or Labels.PlayersCanManage())
end

function RegionMapLabels.CanEdit(row)
    return row ~= nil and Labels.CanAdd(row.mapId) and Labels.CanSee(row)
        and (Model.IsDirector() or row.ownerId == dmhub.loginUserid)
end

function RegionMapLabels.Get(id)
    local row = type(id) == "string" and Labels.Index().byId[id] or nil
    if Labels.CanSee(row) then return row end
    return nil
end

function RegionMapLabels.ForMap(mapId)
    local result = {}
    for _, row in ipairs(Labels.Index().onMap[mapId] or {}) do
        if Labels.CanSee(row) then result[#result + 1] = row end
    end
    return result
end

function RegionMapLabels.Name(row)
    return R.TrimSingleLine(row.text:gsub("\n", " "))
end

--- The mixed wrapper leaves Location-only callers unchanged.
function RegionMapLabels.Search(query, limit)
    local needle = R.MapNameKey(R.TrimSingleLine(query))
    if needle == "" then return {} end
    local results = {}
    for _, row in ipairs(Model.Search(query, limit)) do
        results[#results + 1] = { kind = "location", id = row.id, row = row, name = row.name }
    end
    for _, row in pairs(Labels.Index().byId) do
        if Labels.CanSee(row) then
            local name = Labels.Name(row)
            if R.MapNameKey(name):find(needle, 1, true) then
                results[#results + 1] = { kind = "label", id = row.id, row = row, name = name }
            end
        end
    end
    for _, result in ipairs(results) do
        result.key = R.MapNameKey(result.name)
        result.rank = result.key:sub(1, #needle) == needle and 0 or 1
    end
    table.sort(results, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.key ~= b.key then return a.key < b.key end
        if a.kind ~= b.kind then return a.kind == "location" end
        return a.id < b.id
    end)
    for i = #results, limit + 1, -1 do results[i] = nil end
    return results
end

local function Changes(fields, director, allowBlank, current)
    if type(fields) ~= "table" then return nil end
    if not RegionMapTextAppearance.CanChange(current, fields, director) then return nil end
    local result = {}
    for key, value in pairs(fields) do
        if formats[key] then
            if not ValidFormat(key, value) then return nil end
            if key == "font" and Labels.DisplayFont(value) ~= value then return nil end
        elseif key == "text" then
            value = Labels.NormalizeText(value)
            if value == nil or (value == "" and not allowBlank) then return nil end
        elseif key == "u" or key == "v" then
            if not R.IsFinite(value) or value < 0 or value > 1 then return nil end
        elseif key == "angle" then
            if not R.IsFinite(value) then return nil end
            value = (value + 180) % 360 - 180
        elseif key == "visibility" then
            if not director or (value ~= "hidden" and value ~= "revealed") then return nil end
        else return nil end
        result[key] = value
    end
    return result
end

local function Write(current, record, description, callbacks, creating, retry)
    if R.PendingWrite(C.labelTableName, record.id) then return false, "busy" end
    local step, operation = R.WriteRow(C.labelTableName, current, record, description, callbacks,
        { creating = creating, retry = retry })
    if step == nil then return false, "unavailable", nil, operation end
    return true, nil, { description = description, steps = { step } }, operation
end

function RegionMapLabels.Create(mapId, u, v, fields, callbacks, reservedId, retry)
    if not Labels.CanAdd(mapId) then return false, "permission" end
    local director = Model.IsDirector()
    local changes = Changes(fields, director)
    if changes == nil or changes.text == nil or not R.IsFinite(u) or not R.IsFinite(v)
        or u < 0 or u > 1 or v < 0 or v > 1 then return false, "invalid" end
    local id = reservedId or dmhub.GenerateGuid()
    local current = Labels.Table()[id]
    if current ~= nil and not (retry and retry.operation == R.LastWrite(C.labelTableName, id)
        and retry.operation.creating and retry.operation.status == "failed"
        and R.Field(current, "mutationId", nil) == retry.operation.mutationId) then return false, "busy" end
    local record = RegionMapMapLabelRecord.new(Labels.Format(changes))
    record.id, record.mapId, record.schemaVersion = id, mapId, 1
    record.u, record.v, record.text, record.angle = u, v, changes.text, changes.angle or 0
    record.visibility = director and (changes.visibility or "hidden") or "revealed"
    record.ownerId, record.ownerName, record.hidden = dmhub.loginUserid, R.CurrentUserName(), false
    local ok, reason, entry, operation = Write(current, record, "Add map label", callbacks, true, retry)
    return ok, reason, entry, id, operation
end

function RegionMapLabels.Update(id, fields, callbacks, retry)
    local current = Labels.Get(id)
    if not Labels.CanEdit(current) then return false, "permission" end
    local changes = Changes(fields, Model.IsDirector(), false, current)
    if changes == nil then return false, "invalid" end
    local record, changed = DeepCopy(current), false
    for key, value in pairs(changes) do
        if R.Field(current, key, nil) ~= value then changed = true end
        record[key] = value
    end
    if not changed and retry == nil then return true, nil end
    return Write(current, record, "Edit map label", callbacks, false, retry)
end

function RegionMapLabels.Delete(id, callbacks, retry)
    local current = Labels.Get(id)
    -- A failed optimistic delete is hidden, but its original owner may retry that exact write.
    if current == nil and retry ~= nil then
        local raw = Labels.Table()[id]
        if raw and retry.operation == R.LastWrite(C.labelTableName, id)
            and retry.operation.status == "failed" and R.Field(raw, "mutationId", nil) == retry.operation.mutationId then current = raw end
    end
    if not Labels.CanEdit(current) then return false, "permission" end
    local record = DeepCopy(current)
    record.hidden = true
    return Write(current, record, "Delete map label", callbacks, false, retry)
end

function RegionMapLabels.OnMaps(mapIds)
    local rows = {}
    for _, row in pairs(Labels.Table()) do
        if Labels.Valid(row) and mapIds[row.mapId] then rows[#rows + 1] = row end
    end
    return rows
end

function RegionMapLabels.AnyPending(rows)
    for _, row in ipairs(rows) do if R.PendingWrite(C.labelTableName, row.id) then return true end end
    return false
end

function RegionMapLabels.HideSteps(rows, description)
    if mod.unloaded or not Model.IsDirector() then return {} end
    local steps = {}
    for _, row in ipairs(rows) do
        local record = DeepCopy(row)
        record.hidden = true
        local _, _, entry = Write(row, record, description, nil, false)
        if entry then steps[#steps + 1] = entry.steps[1] end
    end
    return steps
end

--- Deleted maps may be restored by this same Undo entry; evaluate that projected state first.
function RegionMapLabels.CanRevertStep(step, entry)
    if mod.unloaded or Model.ViewingAsPlayer() then return false end
    local current = Labels.Table()[step.id]
    if not Labels.Valid(current, true) then return false end
    local map = Model.Index().byId[current.mapId]
    if Model.IsDirector() then
        for _, other in ipairs(entry.steps) do
            if other.tableName == C.locationTableName and other.id == current.mapId and other.before ~= nil then
                map = other.before
            end
        end
        return map ~= nil and not map.hidden and map.imageId ~= ""
    end
    if not Labels.CanEdit(current) then return false end
    local before = step.before
    return before == nil or (Labels.Valid(before, true) and before.ownerId == current.ownerId
        and before.mapId == current.mapId and before.visibility == current.visibility
        and RegionMapTextAppearance.SameImages(before, current))
end

-- Save queue ----------------------------------------------------------------------------------
-- Save batches outlive the editor: closing it flushes, and losing permission drops only unsent work.

local drafts = {} --- @type table<string, RegionMapMapLabelRecord> labels being added, not created yet
local discards = {} --- @type table<string, integer> bumps when unsent edits are dropped, so editors rebind
local savedListener = nil --- @type nil|fun(row: RegionMapMapLabelRecord)

local function DraftOrRow(id)
    return drafts[id] or Labels.Get(id)
end

-- A delete whose optimistic write failed hides the row; its author may still retry that exact write.
local function FailedDeleteRow(id)
    local raw = Labels.Table()[id]
    local write = R.LastWrite(C.labelTableName, id)
    if raw == nil or write == nil or write.status ~= "failed" or R.Field(raw, "mutationId", nil) ~= write.mutationId then return nil end
    return raw
end

local function WithoutImageChanges(changes)
    local result = {}
    for key, value in pairs(changes) do
        if key ~= "background" and not RegionMapTextAppearance.IsImageField(key) then result[key] = value end
    end
    return result
end

local queue
queue = RegionMapUndo.SaveQueue {
    canEdit = function(id)
        return Labels.CanEdit(DraftOrRow(id) or FailedDeleteRow(id))
    end,
    busy = function(id) return R.PendingWrite(C.labelTableName, id) ~= nil end,
    -- A player's queued background change the Director has since overruled is dropped; their text still saves.
    filter = function(id, changes)
        if Model.IsDirector() then return changes end
        local refused = RegionMapTextAppearance.PlayerRefused(DraftOrRow(id), changes)
        local result = {}
        for key, value in pairs(changes) do if not refused[key] then result[key] = value end end
        return result
    end,
    -- Blank text never saves; it waits until the label has text again.
    hold = function(id, changes)
        local text = changes.text
        if text == nil then
            local row = DraftOrRow(id)
            text = row and row.text or ""
        end
        return Labels.NormalizeText(text) == ""
    end,
    send = function(id, batch, callbacks)
        local draft = drafts[id]
        if draft ~= nil then
            local director = Model.IsDirector()
            local fields = Labels.Format(draft)
            if not director then fields = RegionMapTextAppearance.PlayerFormat(fields) end
            fields.text, fields.angle = draft.text, draft.angle
            if director then fields.visibility = draft.visibility end
            for key, value in pairs(batch.changes) do fields[key] = value end
            local u, v = fields.u or draft.u, fields.v or draft.v
            fields.u, fields.v = nil, nil
            batch.kind = "create"
            local ok, reason, entry, _, operation = Labels.Create(draft.mapId, u, v, fields, callbacks, id, batch.retry)
            return ok, reason, entry, operation
        elseif batch.kind == "delete" then
            return Labels.Delete(id, callbacks, batch.retry)
        end
        return Labels.Update(id, batch.changes, callbacks, batch.retry)
    end,
    -- An image deleted, or a font missing here, since the change was queued: keep the rest.
    repair = function(id, batch)
        local draft = drafts[id]
        if draft ~= nil then
            for key, value in pairs(WithoutImageChanges(batch.changes)) do draft[key] = value end
            for key, value in pairs(RegionMapTextAppearance.UsableFormat(Labels.Format(draft))) do draft[key] = value end
            return {}
        end
        local stripped = WithoutImageChanges(batch.changes)
        if next(stripped) == nil or dmhub.DeepEqual(stripped, batch.changes) then return nil end
        return stripped
    end,
    copyId = function(_, batch)
        if batch.kind == "create" then return "label.added" end
        if batch.kind == "delete" then return "label.deleted" end
        if batch.kind == "moved" or batch.kind == "resized" or batch.kind == "rotated" then return "label." .. batch.kind end
        return "label.updated"
    end,
    mergeKinds = { edit = true },
    saved = function(id, batch)
        if batch.kind == "create" then drafts[id] = nil end
        local row = Labels.Get(id)
        if row ~= nil and savedListener ~= nil then savedListener(row) end
    end,
}

--- The editor remembers the last saved format for the next new label.
--- @param fn nil|fun(row: RegionMapMapLabelRecord)
function RegionMapLabels.SetSavedListener(fn)
    savedListener = fn
end

--- Start a new label that is created on its first save. Its remembered format is made
--- usable first, so an image deleted or a font missing since cannot make the create fail.
--- @param mapId string
--- @param u number
--- @param v number
--- @param format nil|table
--- @return nil|string id
function RegionMapLabels.NewDraft(mapId, u, v, format)
    if not Labels.CanAdd(mapId) then return nil end
    format = RegionMapTextAppearance.UsableFormat(Labels.Format(format))
    if not Model.IsDirector() then format = RegionMapTextAppearance.PlayerFormat(format) end
    local record = RegionMapMapLabelRecord.new(Labels.Format(format))
    record.id, record.mapId, record.schemaVersion, record.revision = dmhub.GenerateGuid(), mapId, 1, 0
    record.u, record.v, record.text, record.angle = R.Clamp(u, 0, 1), R.Clamp(v, 0, 1), "", 0
    record.visibility = Model.IsDirector() and "hidden" or "revealed"
    record.ownerId, record.ownerName, record.hidden = dmhub.loginUserid, R.CurrentUserName(), false
    drafts[record.id] = record
    queue.Touch(record.id)
    return record.id
end

--- The label as this editor sees it: the saved row (or the unsaved draft) with every
--- queued and typed change on top. Reading never cancels anything.
--- @param id nil|string
--- @return nil|table
function RegionMapLabels.Snapshot(id)
    if id == nil then return nil end
    local row = DraftOrRow(id)
    if row == nil or (drafts[id] and not Labels.CanEdit(row)) then return nil end
    local result = DeepCopy(row)
    for key, value in pairs(Labels.Format(row)) do result[key] = value end
    local batches, pending = queue.Unconfirmed(id)
    local director = Model.IsDirector()
    local function Apply(changes)
        local refused = director and {} or RegionMapTextAppearance.PlayerRefused(row, changes)
        for key, value in pairs(changes) do if not refused[key] then result[key] = value end end
    end
    for _, batch in ipairs(batches) do if batch.kind ~= "delete" then Apply(batch.changes) end end
    Apply(pending)
    result._tmp_labelVersion = queue.Version(id) * 1000 + (discards[id] or 0)
    return result
end

--- "draft" (new, never saved), or the queue's status.
--- @param id string
--- @return string
function RegionMapLabels.Status(id)
    local status = queue.Status(id)
    if drafts[id] ~= nil and status == "saved" then return "draft" end
    return status
end

--- How many times unsent edits of this label were dropped; editors rebind focused fields when it moves.
--- @param id string
--- @return integer
function RegionMapLabels.Discards(id)
    return discards[id] or 0
end

--- @param id string
--- @param callback nil|fun()
function RegionMapLabels.Observe(id, callback)
    queue.Observe(id, callback)
end

--- Drop unsent edits (and an unsent new label). status is what the editor shows when
--- something was dropped: "denied" after a permission change, "saved" when Undo replaced it.
--- @param id string
--- @param status nil|string
function RegionMapLabels.CancelPending(id, status)
    local state = queue.Find(id)
    local running = state ~= nil and state.running
    if queue.Cancel(id, status) then discards[id] = (discards[id] or 0) + 1 end
    if drafts[id] ~= nil and not running then drafts[id] = nil; queue.Touch(id) end
end

--- @param id nil|string
function RegionMapLabels.Flush(id)
    if id ~= nil then queue.Flush(id) end
end

--- Typed changes wait for the autosave delay (or Flush). Blank text is allowed while typing.
--- @param id nil|string
--- @param changes table
--- @return boolean accepted
function RegionMapLabels.Stage(id, changes)
    local row = Labels.Snapshot(id)
    if id == nil or not Labels.CanEdit(row) then return false end
    local valid = Changes(changes, Model.IsDirector(), true, row)
    if valid == nil then return false end
    queue.Stage(id, valid)
    return true
end

--- A finished gesture (move, resize, rotate) or a delete, saved now after any typing.
--- @param id nil|string
--- @param changes table
--- @param kind nil|string
--- @return boolean accepted
function RegionMapLabels.Commit(id, changes, kind)
    local row = Labels.Snapshot(id)
    if id == nil or not Labels.CanEdit(row) then return false end
    local valid = Changes(changes, Model.IsDirector(), false, row)
    if valid == nil then return false end
    changes = valid
    queue.Flush(id)
    local batches = queue.Unconfirmed(id)
    local draft = drafts[id]
    if draft ~= nil and #batches == 0 then
        -- Not created yet: the gesture just changes the draft the create will use.
        for key, value in pairs(changes) do draft[key] = value end
        queue.Touch(id)
        return true
    end
    queue.Commit(id, changes, kind)
    return true
end

--- @param id string
--- @return boolean
function RegionMapLabels.RequestDelete(id)
    local state = queue.Find(id)
    if drafts[id] ~= nil and (state == nil or (not state.running and #state.items == 0)) then
        Labels.CancelPending(id); return true
    end
    return Labels.Commit(id, {}, "delete")
end

--- @param id nil|string
function RegionMapLabels.Retry(id)
    if id ~= nil then queue.Retry(id) end
end

--- The editor closed: send typed changes; a draft with nothing to create is discarded.
--- @param id string
function RegionMapLabels.Leave(id)
    queue.Flush(id)
    local state = queue.Find(id)
    if drafts[id] ~= nil and (state == nil or (not state.running and #state.items == 0)) then Labels.CancelPending(id) end
    queue.Leave(id)
    if drafts[id] == nil then discards[id] = nil end
end

Model.RegisterCompanion {
    tableName = C.labelTableName,
    rowsOnMaps = Labels.OnMaps,
    anyPending = Labels.AnyPending,
    hideSteps = Labels.HideSteps,
    cancelRow = function(id) Labels.CancelPending(id, "saved") end,
    canRevertStep = Labels.CanRevertStep,
    beforeViewChange = function()
        for id in pairs(queue.All()) do queue.Flush(id) end
    end,
    afterViewChange = function()
        for id in pairs(queue.All()) do
            if not Labels.CanEdit(DraftOrRow(id)) then Labels.CancelPending(id) end
        end
    end,
}
