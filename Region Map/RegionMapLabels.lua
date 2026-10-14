local mod = dmhub.GetModLoading()

--- Independent map lettering; visibility never participates in structural validation.
--- @class RegionMapMapLabelRecord: GameType, RegionMapAudit
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

--- @return table<string, RegionMapMapLabelRecord>
function RegionMapLabels.Table()
    return (dmhub.GetTable(C.labelTableName) or {}) --[[@as table<string, RegionMapMapLabelRecord>]]
end

local function ColorValue(value)
    return type(value) == "string" and (value:match("^#%x%x%x%x%x%x$") ~= nil
        or value:match("^#%x%x%x%x%x%x%x%x$") ~= nil)
end

local function ValidFormat(key, value)
    if key == "font" then return type(value) == "string" and #value > 0 and #value <= 128 end
    if key == "bold" or key == "italics" then return type(value) == "boolean" end
    if key == "alignment" then return value == "left" or value == "center" or value == "right" end
    if key == "size" then return R.IsFinite(value) and value >= C.labelMinSize and value <= C.labelMaxSize end
    if key == "spacing" then return R.IsFinite(value) and value >= 0 and value <= 1 end
    if key == "color" or key == "backgroundColor" then return ColorValue(value) end
    if key == "background" then return value == "auto" or value == "plate" or value == "none" end
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

--- @param font string
--- @return string
function RegionMapLabels.DisplayFont(font)
    local fallback = nil
    for _, available in ipairs(gui.availableFonts or {}) do
        if available == font then return font end
        if available == "berling" then fallback = available end
    end
    return fallback or (gui.availableFonts or {})[1] or "book"
end

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

local function Changes(fields, director, allowBlank)
    if type(fields) ~= "table" then return nil end
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
    local before = current and DeepCopy(current) or nil
    if retry ~= nil and retry.operation == R.LastWrite(C.labelTableName, record.id)
        and retry.operation.status == "failed" and current ~= nil
        and R.Field(current, "mutationId", nil) == retry.operation.mutationId then before = retry.before end
    record.revision = R.NextRevision(current or { revision = 0 })
    if record.revision == nil then return false, "unavailable" end
    R.Audit(record, creating)
    local step = { tableName = C.labelTableName, id = record.id, before = before,
        afterRevision = record.revision, afterMutationId = record.mutationId }
    local operation = R.UploadRecord(C.labelTableName, record, description, {
        success = function(op)
            Model.InvalidateIndex()
            if callbacks and callbacks.success then callbacks.success(op) end
        end,
        failure = function(op)
            Model.InvalidateIndex()
            if callbacks and callbacks.failure then callbacks.failure(op) end
        end,
    }, creating)
    Model.InvalidateIndex()
    local entry = { description = description, steps = { step } }
    if operation == nil then return false, "unavailable", entry, R.LastWrite(C.labelTableName, record.id) end
    return true, nil, entry, operation
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
    local changes = Changes(fields, Model.IsDirector())
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
        and before.mapId == current.mapId and before.visibility == current.visibility)
end

-- Immutable save batches outlive the editor. Closing flushes, while losing permission cancels unsent work.
local queues = {}
local Drain

local function Notify(q)
    q.version = (q.version or 0) + 1
    if q.notify ~= nil then q.notify() end
end

function RegionMapLabels.NewDraft(mapId, u, v, format, notify)
    if not Labels.CanAdd(mapId) then return nil end
    local record = RegionMapMapLabelRecord.new(Labels.Format(format))
    record.id, record.mapId, record.schemaVersion, record.revision = dmhub.GenerateGuid(), mapId, 1, 0
    record.u, record.v, record.text, record.angle = R.Clamp(u, 0, 1), R.Clamp(v, 0, 1), "", 0
    record.visibility = Model.IsDirector() and "hidden" or "revealed"
    record.ownerId, record.ownerName, record.hidden = dmhub.loginUserid, R.CurrentUserName(), false
    queues[record.id] = { draft = record, pending = {}, items = {}, timer = 0, status = "draft", notify = notify }
    return record.id
end

local function Queue(id)
    queues[id] = queues[id] or { pending = {}, items = {}, timer = 0, status = "saved" }
    return queues[id]
end

function RegionMapLabels.Snapshot(id)
    local q = queues[id]
    local row = (q and q.draft) or Labels.Get(id)
    if row == nil or (q and q.draft and not Labels.CanEdit(row)) then return nil end
    local result = DeepCopy(row)
    for key, value in pairs(Labels.Format(row)) do result[key] = value end
    if q == nil then return result end
    for _, batch in ipairs(q.items) do for key, value in pairs(batch.changes) do result[key] = value end end
    for key, value in pairs(q.pending) do result[key] = value end
    result._tmp_labelVersion = q.version or 0
    return result
end

function RegionMapLabels.Status(id)
    local q = queues[id]
    return q and q.status or "saved"
end

function RegionMapLabels.Observe(id, callback)
    Queue(id).notify = callback
end

function RegionMapLabels.CancelPending(id)
    local q = queues[id]
    if q == nil then return end
    q.timer, q.pending = q.timer + 1, {}
    q.failed = false
    if q.running then q.items = { q.items[1] } else q.items = {}; q.draft = nil end
    q.status = "denied"
    Notify(q)
end

local function RememberFormat(row)
    local session = rawget(_G, "RegionMapSession")
    if row ~= nil and session and session.RememberLabelFormat then session.RememberLabelFormat(row) end
end

Drain = function(id)
    local q = queues[id]
    if mod.unloaded or q == nil or q.running or q.failed or #q.items == 0 then return end
    local batch = q.items[1]
    local base = q.draft or Labels.Get(id)
    if not Labels.CanEdit(base) and not (batch.kind == "delete" and batch.retry ~= nil) then
        Labels.CancelPending(id); return
    end
    if R.PendingWrite(C.labelTableName, id) then
        dmhub.Schedule(C.busyRetryDelay, function() if not mod.unloaded then Drain(id) end end)
        return
    end
    q.running, q.status = true, "saving"
    local function Receipt(success, operation)
        dmhub.Schedule(0, function()
            if mod.unloaded or queues[id] ~= q or q.items[1] ~= batch or not q.running then return end
            q.running = false
            if success then
                if q.draft ~= nil then q.draft = nil end
                table.remove(q.items, 1)
                q.status = next(q.pending) ~= nil and "pending" or "saved"
                if batch.entry ~= nil then RegionMapUndo.Push(batch.entry, batch.copyId) end
                RememberFormat(Labels.Get(id))
                Notify(q)
                Drain(id)
            else
                q.failed, q.status = true, "failed"
                batch.retry = { operation = operation, before = batch.entry and batch.entry.steps[1].before }
                RegionMapUndo.Notify("toast.saveFailed", nil, function() Labels.Retry(id) end)
                Notify(q)
            end
        end)
    end
    local callbacks = { success = function(op) Receipt(true, op) end, failure = function(op) Receipt(false, op) end }
    local ok, reason, operation
    if q.draft ~= nil then
        local fields = Labels.Format(q.draft)
        fields.text, fields.angle = q.draft.text, q.draft.angle
        if Model.IsDirector() then fields.visibility = q.draft.visibility end
        for key, value in pairs(batch.changes) do fields[key] = value end
        local _
        ok, reason, batch.entry, _, operation = Labels.Create(q.draft.mapId, q.draft.u, q.draft.v, fields, callbacks, id, batch.retry)
        batch.copyId = "label.added"
    elseif batch.kind == "delete" then
        ok, reason, batch.entry, operation = Labels.Delete(id, callbacks, batch.retry)
    else
        ok, reason, batch.entry, operation = Labels.Update(id, batch.changes, callbacks, batch.retry)
    end
    if not ok and reason == "busy" then
        q.running = false
        dmhub.Schedule(C.busyRetryDelay, function() if not mod.unloaded then Drain(id) end end)
    elseif not ok and (reason == "permission" or reason == "invalid") then
        q.running = false
        Labels.CancelPending(id)
    elseif operation == nil then
        Receipt(ok, R.LastWrite(C.labelTableName, id))
    end
    Notify(q)
end

function RegionMapLabels.Flush(id)
    local q = queues[id]
    if q == nil or next(q.pending) == nil then return end
    q.timer = q.timer + 1
    local snapshot = Labels.Snapshot(id)
    if snapshot == nil or not Labels.CanEdit(snapshot) then Labels.CancelPending(id); return end
    if Changes(q.pending, Model.IsDirector()) == nil or Labels.NormalizeText(snapshot.text) == "" then
        q.status = "invalid"; Notify(q); return
    end
    q.items[#q.items + 1] = { changes = DeepCopy(q.pending), kind = "edit", copyId = "label.updated" }
    q.pending = {}
    Drain(id)
end

function RegionMapLabels.Stage(id, changes)
    local row = Labels.Snapshot(id)
    if not Labels.CanEdit(row) then return false end
    changes = Changes(changes, Model.IsDirector(), true)
    if changes == nil then return false end
    local q = Queue(id)
    for key, value in pairs(changes) do q.pending[key] = value end
    q.timer, q.status = q.timer + 1, "pending"
    local timer = q.timer
    dmhub.Schedule(C.autosaveDelay, function()
        if not mod.unloaded and queues[id] == q and q.timer == timer then Labels.Flush(id) end
    end)
    Notify(q)
    return true
end

function RegionMapLabels.Commit(id, changes, kind)
    if not Labels.CanEdit(Labels.Snapshot(id)) then return false end
    changes = Changes(changes, Model.IsDirector())
    if changes == nil then return false end
    Labels.Flush(id)
    local q = Queue(id)
    if q.draft and #q.items == 0 then
        for key, value in pairs(changes) do q.draft[key] = value end
        Notify(q); return true
    end
    q.items[#q.items + 1] = { changes = DeepCopy(changes), kind = kind or "edit",
        copyId = "label." .. (kind == "delete" and "deleted" or kind or "updated") }
    Drain(id)
    return true
end

function RegionMapLabels.RequestDelete(id)
    local q = queues[id]
    if q and q.draft and not q.running and #q.items == 0 then Labels.CancelPending(id); return true end
    return Labels.Commit(id, {}, "delete")
end

function RegionMapLabels.Retry(id)
    local q = queues[id]
    if q == nil or not q.failed then return end
    q.failed = false
    Drain(id)
end

function RegionMapLabels.Leave(id)
    Labels.Flush(id)
    local q = queues[id]
    if q and q.draft and not q.running and #q.items == 0 then Labels.CancelPending(id) end
end
