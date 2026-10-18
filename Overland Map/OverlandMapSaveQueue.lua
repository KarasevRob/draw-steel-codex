local mod = dmhub.GetModLoading()

--- @class OverlandMapSaveQueue: GameType
--- @field new fun(o?: table): OverlandMapSaveQueue
OverlandMapSaveQueue = RegisterGameType("OverlandMapSaveQueue")
local C = OverlandMapConstants
local Lifetime = OverlandMapLifetime

-- Save queues ------------------------------------------------------------------------------------

--- One change set on its way to a row. Batches are immutable once queued; a failed batch
--- keeps its place, so Retry resends exactly what failed.
--- @class OverlandMapSaveBatch
--- @field changes table
--- @field kind string "edit" unless the owner sends something else ("delete", "reset", "moved"...)
--- @field entry nil|OverlandMapUndoEntry
--- @field retry nil|OverlandMapRetry
--- @field repaired nil|boolean the owner already repaired it once

--- How a save queue reaches its rows. The owner (labels, pin text, map aids, or an
--- OverlandMapEditors lane) supplies these.
--- @class OverlandMapSaveQueueSpec
--- @field canEdit fun(id: string): boolean checked before every send; false drops unsent work
--- @field busy fun(id: string): boolean the row has a write in flight
--- @field send fun(id: string, batch: OverlandMapSaveBatch, callbacks: OverlandMapWriteCallbacks): OverlandMapOperationResult
--- @field filter nil|fun(id: string, changes: table): table drop changes no longer permitted, keep the rest
--- @field hold nil|fun(id: string, changes: table): boolean true keeps typed changes unsent ("invalid") until more typing fixes them
--- @field coalesce nil|fun(first: OverlandMapSaveBatch, later: OverlandMapSaveBatch): nil|OverlandMapSaveBatch fold a later batch into the unsent first one (one write instead of two)
--- @field repair nil|fun(id: string, batch: OverlandMapSaveBatch): nil|table changes to try once more after "invalid"
--- @field copyId nil|fun(id: string, batch: OverlandMapSaveBatch): nil|string toast for a saved batch; nil keeps Undo silently
--- @field mergeKinds nil|table<string, boolean> kinds whose saves of one row merge their Undo entries
--- @field saved nil|fun(id: string, batch: OverlandMapSaveBatch)

--- Per row: typed changes wait (Stage) and go out as batches, one write at a time.
--- status: "saved" | "pending" (waiting to send) | "saving" | "failed" (Retry offered)
--- | "invalid" (a batch was refused and dropped, or hold keeps typed changes unsent)
--- | "denied" (permission lost; unsent work dropped).
--- @class OverlandMapSaveQueueState
--- @field pending table
--- @field items OverlandMapSaveBatch[]
--- @field running boolean
--- @field failed boolean
--- @field status string
--- @field timer integer bumps whenever a scheduled autosave must not fire
--- @field version integer bumps on every change, for UI signatures
--- @field observers table<function, boolean>
--- @field left nil|boolean the editor closed; the queue goes once it is idle

--- Build the queues of one kind of row. Owners keep any extra state (such as an unsaved
--- draft) themselves and see it again in send.
--- @param spec OverlandMapSaveQueueSpec
--- @return table api
function OverlandMapSaveQueue.Create(spec)
    local queues = {} --- @type table<string, OverlandMapSaveQueueState>
    local api = {}
    local Drain

    Lifetime.Subscribe(function() queues = {} end)

    local function Notify(q)
        q.version = q.version + 1
        local observers = {}
        for callback in pairs(q.observers) do observers[#observers + 1] = callback end
        for _, callback in ipairs(observers) do
            if q.observers[callback] then callback() end
        end
    end

    local function Get(id)
        local q = queues[id]
        if q == nil then
            q = { pending = {}, items = {}, running = false, failed = false, status = "saved", timer = 0, version = 0, observers = {} }
            queues[id] = q
        end
        return q
    end

    local function Idle(q)
        return not q.running and not q.failed and #q.items == 0 and next(q.pending) == nil
    end

    local function Later(id, delay)
        local captured = Lifetime.Capture()
        OverlandMapLifetime.Schedule(delay, function() if Lifetime.Valid(captured) then Drain(id) end end)
    end

    --- @param id string
    --- @return nil|OverlandMapSaveQueueState
    function api.Find(id) return queues[id] end

    --- Drop unsent work: pending changes and queued batches (a batch already sending finishes).
    --- status is "denied" only when work was actually dropped; otherwise the row reads "saved".
    --- @param id string
    --- @param status nil|string the status when work was dropped (default "denied")
    --- @return boolean dropped
    function api.Cancel(id, status)
        local q = queues[id]
        if q == nil then return false end
        local dropped = next(q.pending) ~= nil or #q.items > (q.running and 1 or 0)
        q.timer, q.pending, q.failed = q.timer + 1, {}, false
        q.items = q.running and { q.items[1] } or {}
        if q.running then q.status = "saving"
        elseif dropped then q.status = status or "denied"
        else q.status = "saved" end
        Notify(q)
        return dropped
    end

    --- Queue a batch now, after any typed changes still waiting.
    --- @param id string
    --- @param changes table
    --- @param kind nil|string
    function api.Commit(id, changes, kind)
        api.Flush(id)
        local q = Get(id)
        q.items[#q.items + 1] = { changes = DeepCopy(changes), kind = kind or "edit" }
        if not q.running and not q.failed then q.status = "saving" end
        Notify(q)
        Drain(id)
    end

    --- Remember typed changes; they go out together after the autosave delay or Flush.
    --- @param id string
    --- @param changes table
    function api.Stage(id, changes)
        local q = Get(id)
        for key, value in pairs(DeepCopy(changes)) do q.pending[key] = value end
        q.timer = q.timer + 1
        if q.status ~= "failed" then q.status = "pending" end
        local timer = q.timer
        OverlandMapLifetime.Schedule(C.autosaveDelay, function()
            if not mod.unloaded and queues[id] == q and q.timer == timer then api.Flush(id) end
        end)
        Notify(q)
    end

    --- Invalid field input withdraws only its unsubmitted debounce value.
    function api.Withdraw(id, field)
        local q = queues[id]
        if q == nil or q.pending[field] == nil then return end
        q.pending[field] = nil
        if Idle(q) then q.status = "saved" end
        Notify(q)
    end

    --- Send typed changes now (field exit, editor close).
    --- @param id string
    function api.Flush(id)
        local q = queues[id]
        if q == nil or next(q.pending) == nil then return end
        q.timer = q.timer + 1
        if spec.hold and spec.hold(id, q.pending) then
            q.status = "invalid"
            Notify(q)
            return
        end
        local changes = q.pending
        q.pending = {}
        if spec.filter then changes = spec.filter(id, changes) end
        if next(changes) ~= nil then q.items[#q.items + 1] = { changes = changes, kind = "edit" } end
        if #q.items == 0 then q.status = "saved" end
        Notify(q)
        Drain(id)
    end

    Drain = function(id)
        local q = queues[id]
        if mod.unloaded or q == nil or q.running or q.failed or #q.items == 0 then return end
        local batch = q.items[1]
        if not spec.canEdit(id) then api.Cancel(id); return end
        if spec.busy(id) then Later(id, C.busyRetryDelay); return end
        while spec.coalesce and not batch.retry and q.items[2] ~= nil do
            local merged = spec.coalesce(batch, q.items[2])
            if merged == nil then break end
            table.remove(q.items, 2)
            q.items[1], batch = merged, merged
        end
        if spec.filter and not batch.retry then batch.changes = spec.filter(id, batch.changes) end
        q.running, q.status = true, "saving"
        local function Receipt(success, operation)
            -- Upload callbacks may run before send returns its Undo entry.
            OverlandMapLifetime.Schedule(0, function()
                if mod.unloaded or queues[id] ~= q or q.items[1] ~= batch or not q.running then return end
                q.running = false
                if success then
                    table.remove(q.items, 1)
                    q.status = next(q.pending) ~= nil and "pending" or "saved"
                    local copyId = spec.copyId and spec.copyId(id, batch) or nil
                    if spec.mergeKinds and spec.mergeKinds[batch.kind] then
                        OverlandMapUndo.PushMerged(batch.entry, copyId, id .. ":" .. batch.kind, C.undoMergeSeconds)
                    elseif copyId ~= nil then OverlandMapUndo.Push(batch.entry, copyId)
                    else OverlandMapUndo.Remember(batch.entry) end
                    if spec.saved then spec.saved(id, batch) end
                    Notify(q)
                    Drain(id)
                    if q.left and next(q.observers) == nil and Idle(q) and queues[id] == q then queues[id] = nil end
                elseif spec.canEdit(id) then
                    q.failed, q.status = true, "failed"
                    batch.retry = { operation = operation, before = batch.entry and batch.entry.steps[1].before }
                    OverlandMapUndo.Notify("toast.saveFailed", nil, function() api.Retry(id) end)
                    Notify(q)
                else
                    table.remove(q.items, 1)
                    api.Cancel(id)
                end
            end)
        end
        local result = spec.send(id, batch, {
            success = function(op) Receipt(true, op) end,
            failure = function(op) Receipt(false, op) end,
        })
        local ok = result.outcome == "accepted" or result.outcome == "unchanged"
        local reason, entry, operation = result.reason, result.undo, result.receipt
        batch.entry = entry
        if ok then
            -- A write that changed nothing never reports back.
            if operation == nil then Receipt(true, nil) end
        elseif reason == "busy" then
            q.running = false
            Later(id, C.busyRetryDelay)
        elseif reason == "permission" then
            q.running = false
            api.Cancel(id)
        elseif reason == "invalid" then
            q.running = false
            local repaired = not batch.repaired and spec.repair and spec.repair(id, batch) or nil
            if repaired ~= nil then
                batch.changes, batch.repaired = repaired, true
            else
                table.remove(q.items, 1)
                q.status = "invalid"
            end
            Notify(q)
            Drain(id)
            return
        else
            Receipt(false, operation)
        end
        Notify(q)
    end

    --- @param id string
    function api.Retry(id)
        local q = queues[id]
        if q == nil or not q.failed then return end
        q.failed = false
        Drain(id)
    end

    --- @param id string
    --- @return string
    function api.Status(id)
        local q = queues[id]
        return q and q.status or "saved"
    end

    --- The changes not yet confirmed, oldest first, for the owner's preview of the row.
    --- @param id string
    --- @return OverlandMapSaveBatch[] batches
    --- @return table pending
    function api.Unconfirmed(id)
        local q = queues[id]
        if q == nil then return {}, {} end
        return q.items, q.pending
    end

    --- @param id string
    --- @return integer
    function api.Version(id)
        local q = queues[id]
        return q and q.version or 0
    end

    --- Tell observers the owner's own state for id changed (an unsaved draft moved).
    --- @param id string
    function api.Touch(id)
        Notify(Get(id))
    end

    --- @param id string
    --- @param fn fun()
    --- @return fun() unsubscribe
    function api.Observe(id, fn)
        local q = Get(id)
        q.observers[fn], q.left = true, false
        local active = true
        return function()
            if not active then return end
            active = false
            q.observers[fn] = nil
            if next(q.observers) == nil and Idle(q) and queues[id] == q then queues[id] = nil end
        end
    end

    --- The editor closed: send typed changes and forget the queue once nothing is left in it
    --- (now, or when its last write is confirmed). The editor detaches its own subscription.
    --- @param id string
    function api.Leave(id)
        api.Flush(id)
        local q = queues[id]
        if q == nil then return end
        q.left = true
        if next(q.observers) == nil and Idle(q) then queues[id] = nil end
    end

    --- Forget idle queues nobody observes (the editor that opened them is gone).
    function api.Prune()
        for id, q in pairs(queues) do
            if next(q.observers) == nil and Idle(q) then queues[id] = nil end
        end
    end

    --- @return table<string, OverlandMapSaveQueueState>
    function api.All() return queues end

    return api
end
