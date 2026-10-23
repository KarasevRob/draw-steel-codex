local mod = dmhub.GetModLoading()

--- @class OverlandMapEditors: GameType
--- @field new fun(o?: table): OverlandMapEditors
OverlandMapEditors = RegisterGameType("OverlandMapEditors")
local C, R, Model = OverlandMapConstants, OverlandMapRecords, OverlandMapModel
local Paths = OverlandMapPaths

local lanes = {
    log = {
        tableName = C.logTableName,
        canEdit = function(id) return Model.IsDirector() and OverlandMapLog.Get(id) ~= nil end,
        send = function(id, batch, callbacks)
            return OverlandMapCommands.SetLogNote(id, batch.changes.note, callbacks, batch.retry)
        end,
    },
    location = {
        tableName = C.locationTableName,
        canEdit = function(id) return Model.CanEdit(Model.GetLocation(id)) end,
        send = function(id, batch, callbacks)
            return OverlandMapCommands.UpdateLocation(id, batch.changes, "Edit location", batch.retry, callbacks)
        end,
    },
    details = {
        tableName = C.detailsTableName,
        canEdit = function(id) return Model.CanEdit(Model.GetLocation(id)) end,
        send = function(id, batch, callbacks) return OverlandMapCommands.SaveDetails(id, batch.changes, callbacks, batch.retry) end,
    },
    notes = {
        tableName = C.notesTableName,
        canEdit = function(id) return Model.IsDirector() and Model.GetLocation(id) ~= nil end,
        send = function(id, batch, callbacks) return OverlandMapCommands.SaveDirectorNote(id, batch.changes.note, callbacks, batch.retry) end,
    },
    path = {
        tableName = C.pathTableName,
        canEdit = function(id) return Model.IsDirector() and Paths.Get(id) ~= nil end,
        send = function(id, batch, callbacks)
            return OverlandMapCommands.UpdatePath(id, batch.changes, "Edit path", batch.retry, callbacks)
        end,
    },
}

local queues, discarded = {}, {}
for name, lane in pairs(lanes) do
    local queue = OverlandMapSaveQueue.Create {
        canEdit = lane.canEdit,
        busy = function(id) return R.PendingWrite(lane.tableName, id) ~= nil end,
        send = lane.send,
        mergeKinds = { edit = true },
    }
    queues[name], discarded[name] = queue, {}
    Model.RegisterCompanion {
        tableName = lane.tableName,
        cancelRow = function(id)
            if queue.Cancel(id, "saved") then discarded[name][id] = (discarded[name][id] or 0) + 1 end
        end,
        beforeViewChange = function() for id in pairs(queue.All()) do queue.Flush(id) end end,
        afterViewChange = function()
            for id in pairs(queue.All()) do
                if not lane.canEdit(id) then queue.Cancel(id) end
            end
        end,
    }
end

local locationFields = { name = "location", description = "details", note = "notes" }
local priority = { saved = 0, pending = 1, saving = 2, invalid = 3, denied = 4, failed = 5 }

--- A panel owns drafts and subscriptions; the queues continue after it closes.
--- @param kind "location"|"path"|"log"
--- @param changed fun()
--- @return table
function OverlandMapEditors.Create(kind, changed)
    local names = kind ~= "location" and { kind } or { "location", "details", "notes" }
    local subscriptions, identities = {}, {}
    local alive, boundId = true, nil
    local api = {}

    function api.Flush()
        for id in pairs(identities) do
            for _, name in ipairs(names) do queues[name].Flush(id) end
        end
    end

    function api.Bind(id)
        if id == boundId then return end
        for _, release in ipairs(subscriptions) do release() end
        subscriptions, boundId = {}, id
        api.Flush()
        if id == nil then return end
        identities[id] = true
        for _, name in ipairs(names) do
            subscriptions[#subscriptions + 1] = queues[name].Observe(id, function()
                if alive and boundId == id then changed() end
            end)
        end
    end

    function api.Stage(id, field, value)
        if not alive or id == nil then return end
        local name = kind ~= "location" and kind or locationFields[field]
        if name == nil or not lanes[name].canEdit(id) then return end
        identities[id] = true
        queues[name].Stage(id, { [field] = value })
    end

    function api.Withdraw(id, field)
        local name = kind ~= "location" and kind or locationFields[field]
        if name and id then queues[name].Withdraw(id, field) end
    end

    function api.Commit(id, changes)
        if not alive or not id then return end
        identities[id] = true
        if kind ~= "location" then queues[kind].Commit(id, changes); return end
        for field, value in pairs(changes) do api.Stage(id, field, value) end
        api.Flush()
    end

    function api.Pending(id)
        local result = {}
        for _, name in ipairs(names) do
            local batches, pending = queues[name].Unconfirmed(id)
            for _, batch in ipairs(batches) do
                for key, value in pairs(batch.changes) do result[key] = value end
            end
            for key, value in pairs(pending) do result[key] = value end
        end
        return next(result) ~= nil and result or nil
    end

    function api.Status(id)
        local status = "saved"
        for _, name in ipairs(names) do
            local value = queues[name].Status(id)
            if (priority[value] or 0) > priority[status] then status = value end
        end
        return status
    end

    function api.Discards(id)
        local version = 0
        for _, name in ipairs(names) do version = version + (discarded[name][id] or 0) end
        return version
    end

    function api.Retry(id)
        for _, name in ipairs(names) do queues[name].Retry(id) end
    end

    function api.Cancel(id, unauthorizedOnly)
        for identity in pairs(identities) do
            if id == nil or identity == id then
                for _, name in ipairs(names) do
                    if not unauthorizedOnly or not lanes[name].canEdit(identity) then
                        discarded[name][identity] = (discarded[name][identity] or 0) + 1
                        queues[name].Cancel(identity, "saved")
                    end
                end
            end
        end
    end

    function api.Destroy()
        api.Flush()
        alive = false
        for _, release in ipairs(subscriptions) do release() end
        subscriptions = {}
        for id in pairs(identities) do
            for _, name in ipairs(names) do queues[name].Leave(id) end
        end
    end

    return api
end
