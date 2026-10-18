local mod = dmhub.GetModLoading()

--- @class OverlandMapCommands: GameType
--- @field new fun(o?: table): OverlandMapCommands
OverlandMapCommands = RegisterGameType("OverlandMapCommands")

--- @class OverlandMapOperationResult
--- @field outcome "accepted"|"unchanged"|"busy"|"denied"|"invalid"|"failed"
--- @field reason nil|OverlandMapWriteReason
--- @field receipt nil|OverlandMapWrite
--- @field undo nil|OverlandMapUndoEntry
--- @field undoSteps OverlandMapUndoStep[]
--- @field id nil|string
--- @field count nil|integer
--- @field operations table[]
--- @field rows nil|table[] import row results retain input order

--- Acceptance is submission, not server acknowledgement. Only table callbacks confirm rows.
--- @param ok boolean
--- @param reason nil|OverlandMapWriteReason
--- @param entry nil|OverlandMapUndoEntry
--- @param receipt nil|OverlandMapWrite
--- @return OverlandMapOperationResult
function OverlandMapCommands.Result(ok, reason, entry, receipt)
    if receipt == nil and entry ~= nil and #entry.steps == 1 then receipt = entry.steps[1].receipt end
    local outcome = "failed"
    if ok then outcome = ((entry ~= nil and #entry.steps > 0) or receipt ~= nil) and "accepted" or "unchanged"
    elseif reason == "busy" then outcome = "busy"
    elseif reason == "permission" then outcome = "denied"
    elseif reason == "invalid" or reason == "changed" then outcome = "invalid" end
    return { outcome = outcome, reason = reason, receipt = receipt, undo = entry,
        undoSteps = entry and entry.steps or {}, operations = entry and (entry.operations or entry.steps) or {} }
end

--- @param result OverlandMapOperationResult
--- @return boolean
function OverlandMapCommands.Accepted(result)
    return result.outcome == "accepted" or result.outcome == "unchanged"
end

local function Created(ok, reason, entry, id)
    local result = OverlandMapCommands.Result(ok, reason, entry)
    result.id = id
    return result
end

--- These settings have never offered Overland Undo; the document API only reports submission.
local function Setting(key, ok, reason)
    local result = OverlandMapCommands.Result(ok, reason)
    if ok then
        result.outcome = "accepted"
        result.operations = { { state = key, outcome = "submitted" } }
    end
    return result
end

--- Record a required operation even when its upload could not start.
--- @param entry OverlandMapUndoEntry
--- @param step nil|OverlandMapUndoStep
--- @param tableName nil|string nil for a document submission
--- @param id nil|string
function OverlandMapCommands.Append(entry, step, tableName, id)
    if entry.operations == nil then
        entry.operations = {}
        for _, existing in ipairs(entry.steps) do entry.operations[#entry.operations + 1] = existing end
    end
    if step then entry.steps[#entry.steps + 1] = step end
    entry.operations[#entry.operations + 1] = step or { outcome = "failed", tableName = tableName, id = id }
end

--- Mixed operations retain individual results. Document steps are submitted, never server-confirmed.
--- @param result OverlandMapOperationResult
--- @return table
function OverlandMapCommands.Settlement(result)
    local counts = { pending = 0, confirmed = 0, failed = 0, submitted = 0 }
    for _, step in ipairs(result.operations) do
        if step.outcome == "failed" then counts.failed = counts.failed + 1
        elseif step.tableName ~= nil then
            local receipt = step.receipt
            local status = receipt and receipt.status or "pending"
            counts[status] = counts[status] + 1
        else counts.submitted = counts.submitted + 1 end
    end
    return counts
end

function OverlandMapCommands.UpdateLocation(id, changes, description, retry, callbacks)
    return OverlandMapCommands.Result(OverlandMapModel.UpdateLocation(id, changes, description, retry, callbacks))
end
function OverlandMapCommands.CreateLocation(mapId, u, v, style, callbacks, name)
    return Created(OverlandMapModel.CreateLocation(mapId, u, v, style, callbacks, name))
end
function OverlandMapCommands.CreateLocations(mapId, items)
    local ok, reason, rows = OverlandMapModel.CreateLocations(mapId, items)
    local entry = { description = "Import overland map locations", steps = {}, partial = true }
    local results = {}
    for _, row in ipairs(rows) do
        OverlandMapCommands.Append(entry, row.step, OverlandMapConstants.locationTableName, row.id)
        results[#results + 1] = { id = row.id, step = row.step, outcome = row.step and "accepted" or "failed",
            receipt = row.step and row.step.receipt }
    end
    local result = OverlandMapCommands.Result(ok, reason, entry)
    if ok and #rows > 0 and #entry.steps == 0 then result.outcome = "failed" end
    result.rows = results
    return result
end
function OverlandMapCommands.CreateMap(name, imageId, callbacks, mode)
    return Created(OverlandMapModel.CreateMap(name, imageId, callbacks, mode))
end
function OverlandMapCommands.MoveLocation(id, u, v)
    return OverlandMapCommands.Result(OverlandMapModel.MoveLocation(id, u, v))
end
function OverlandMapCommands.SetLocationVisibility(id, visibility)
    return OverlandMapCommands.Result(OverlandMapModel.SetVisibility(id, visibility))
end
function OverlandMapCommands.SetMapShared(id, shared)
    return OverlandMapCommands.Result(OverlandMapModel.SetMapShared(id, shared))
end
function OverlandMapCommands.SetBorder(id, border)
    return OverlandMapCommands.Result(OverlandMapModel.SetBorder(id, border))
end
function OverlandMapCommands.AddMap(id, imageId, mode)
    return OverlandMapCommands.Result(OverlandMapModel.AddMap(id, imageId, mode))
end
function OverlandMapCommands.ReplaceImage(id, imageId)
    return OverlandMapCommands.Result(OverlandMapModel.ReplaceImage(id, imageId))
end
function OverlandMapCommands.SaveDetails(id, changes, callbacks, retry)
    return OverlandMapCommands.Result(OverlandMapModel.SaveDetails(id, changes, callbacks, retry))
end
function OverlandMapCommands.SaveDirectorNote(id, note, callbacks, retry)
    return OverlandMapCommands.Result(OverlandMapModel.SaveDirectorNote(id, note, callbacks, retry))
end
function OverlandMapCommands.UpdatePath(id, changes, description, retry, callbacks)
    return OverlandMapCommands.Result(OverlandMapPaths.UpdatePath(id, changes, description, retry, callbacks))
end
function OverlandMapCommands.CreatePath(mapId, aId, bId, fields, callbacks)
    return Created(OverlandMapPaths.CreatePath(mapId, aId, bId, fields, callbacks))
end
function OverlandMapCommands.SetPathVisibility(id, visibility)
    return OverlandMapCommands.Result(OverlandMapPaths.SetVisibility(id, visibility))
end
function OverlandMapCommands.UpdatePathType(id, changes)
    return OverlandMapCommands.Result(OverlandMapPaths.UpdateType(id, changes))
end
function OverlandMapCommands.AddPathType()
    return Created(OverlandMapPaths.AddType())
end
function OverlandMapCommands.DeletePathType(id)
    return OverlandMapCommands.Result(OverlandMapPaths.DeleteType(id))
end
function OverlandMapCommands.SetTimeUnit(unit)
    return OverlandMapCommands.Result(OverlandMapPaths.SetTimeUnit(unit))
end
function OverlandMapCommands.UpdateLabel(id, changes, callbacks, retry)
    return OverlandMapCommands.Result(OverlandMapLabels.Update(id, changes, callbacks, retry))
end
function OverlandMapCommands.DeleteLabel(id, callbacks, retry)
    return OverlandMapCommands.Result(OverlandMapLabels.Delete(id, callbacks, retry))
end
function OverlandMapCommands.CreateLabel(mapId, u, v, fields, callbacks, id, retry)
    local ok, reason, entry, createdId, receipt = OverlandMapLabels.Create(mapId, u, v, fields, callbacks, id, retry)
    local result = OverlandMapCommands.Result(ok, reason, entry, receipt)
    result.id = createdId
    return result
end
function OverlandMapCommands.SetPinNameFormat(id, changes, reset, callbacks, retry)
    return OverlandMapCommands.Result(OverlandMapModel.SetPinNameFormat(id, changes, reset, callbacks, retry))
end
function OverlandMapCommands.SetMapAid(id, kind, patch, action, callbacks, retry)
    return OverlandMapCommands.Result(OverlandMapModel.SetMapAid(id, kind, patch, action, callbacks, retry))
end
function OverlandMapCommands.DeleteLocation(id, approved)
    local ok, reason, entry, count = OverlandMapModel.DeleteLocation(id, approved)
    local result = OverlandMapCommands.Result(ok, reason, entry)
    result.count = count
    return result
end
function OverlandMapCommands.RemoveMap(id, approved)
    local ok, reason, entry, count = OverlandMapModel.RemoveMap(id, approved)
    local result = OverlandMapCommands.Result(ok, reason, entry)
    result.count = count
    return result
end

function OverlandMapCommands.MoveToMap(id, mapId)
    return OverlandMapCommands.Result(OverlandMapModel.MoveToMap(id, mapId))
end

function OverlandMapCommands.DeletePath(id)
    return OverlandMapCommands.Result(OverlandMapPaths.DeletePath(id))
end

function OverlandMapCommands.WriteParty(args)
    return OverlandMapCommands.Result(OverlandMapModel.WriteParty(args))
end
function OverlandMapCommands.PlaceParty(mapId, u, v, locationId)
    return OverlandMapCommands.Result(OverlandMapModel.PlaceParty(mapId, u, v, locationId))
end
function OverlandMapCommands.SetPartyName(name)
    return Setting("partyName", OverlandMapModel.SetPartyName(name))
end
function OverlandMapCommands.SetPartyImageId(imageId)
    return Setting("partyImageId", OverlandMapModel.SetPartyImageId(imageId))
end
function OverlandMapCommands.SetPlayersCanMoveParty(value)
    return Setting("playerCanMoveParty", OverlandMapModel.SetPlayersCanMoveParty(value))
end
function OverlandMapCommands.SetPlayersCanAddLocations(value)
    return Setting("playersCanAddLocations", OverlandMapModel.SetPlayersCanAddLocations(value))
end
function OverlandMapCommands.SetPlayersCanManageLabels(value)
    return Setting("playersCanManageLabels", OverlandMapLabels.SetPlayersCanManage(value))
end

function OverlandMapCommands.Travel(option, reveal)
    return OverlandMapCommands.Result(OverlandMapTravel.Travel(option, reveal))
end

function OverlandMapCommands.StopPartway(pathId, fromId, spent)
    return OverlandMapCommands.Result(OverlandMapTravel.StopPartway(pathId, fromId, spent))
end

function OverlandMapCommands.SetLogNote(id, note, callbacks, retry)
    return OverlandMapCommands.Result(OverlandMapLog.SetNote(id, note, callbacks, retry))
end
function OverlandMapCommands.DeleteLogEntry(id)
    return OverlandMapCommands.Result(OverlandMapLog.DeleteEntry(id))
end
