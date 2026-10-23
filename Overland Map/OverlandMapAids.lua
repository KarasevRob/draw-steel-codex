local mod = dmhub.GetModLoading()

--- Map aids (compass, scale bar): permission, the save queue and the local preview of
--- unconfirmed edits. The settings editor is OverlandMapAidEditor.
--- @class OverlandMapAids: GameType
--- @field new fun(o?: table): OverlandMapAids
OverlandMapAids = RegisterGameType("OverlandMapAids")
local Aids = OverlandMapAids
local R, Model, Session = OverlandMapRecords, OverlandMapModel, OverlandMapControls
local A, Tools, C = OverlandMapTextAppearance, OverlandMapCanvasTools, OverlandMapConstants
local T = OverlandMapCopy.T
local kinds = { "compass", "scaleBar" }

function OverlandMapAids.CanEdit(id)
    local map = Model.GetLocation(id)
    return not mod.unloaded and Model.IsDirector() and map ~= nil and map.imageId ~= ""
end

local queue = OverlandMapSaveQueue.Create {
    canEdit = Aids.CanEdit,
    busy = function(id) return R.PendingWrite(C.locationTableName, id) ~= nil end,
    send = function(id, batch, callbacks)
        local change = batch.changes
        return OverlandMapCommands.SetMapAid(id, change.aid, change.patch, change.action, callbacks, batch.retry)
    end,
}

function OverlandMapAids.Snapshot(map, kind)
    if kind ~= "compass" and kind ~= "scaleBar" then return nil end
    local id = R.Field(map, "id", nil)
    local raw = R.Field(R.Field(map, "mapAids", nil), kind, nil)
    raw = type(raw) == "table" and DeepCopy(raw) or nil
    if id then
        local batches = queue.Unconfirmed(id)
        for _, batch in ipairs(batches) do
            local change = batch.changes
            if change.aid == kind then
                if change.action == "remove" then raw = nil
                else
                    raw = raw or R.MapAidDefaults(kind)
                    for key, value in pairs(change.patch) do raw[key] = value end
                end
            end
        end
    end
    return R.MapAid({ mapAids = { [kind] = raw } }, kind)
end

function OverlandMapAids.Commit(id, kind, patch, action)
    if kind ~= "compass" and kind ~= "scaleBar" then return false end
    if not Aids.CanEdit(id) then if id then queue.Cancel(id) end; return false end
    action = action or "edit"
    local current = Aids.Snapshot(Model.GetLocation(id), kind)
    if action ~= "remove" and R.ApplyMapAidPatch(current, kind, patch) == nil then return false end
    if action == "edit" and current == nil then return false end
    queue.Commit(id, { aid = kind, patch = patch, action = action }, action)
    return true
end

function OverlandMapAids.Status(id) return id and queue.Status(id) or "saved" end
function OverlandMapAids.Retry(id) if id then queue.Retry(id) end end
function OverlandMapAids.Observe(id, callback) if id then return queue.Observe(id, callback) end end
function OverlandMapAids.Leave(id) if id then queue.Leave(id) end end
function OverlandMapAids.Prune() queue.Prune() end

Model.RegisterCompanion {
    cancelMap = function(id)
        queue.Cancel(id)
    end,
    afterViewChange = function()
        for id in pairs(queue.All()) do if not Aids.CanEdit(id) then queue.Cancel(id) end end
    end,
}
