local mod = dmhub.GetModLoading()

--- Region Map undo and toasts, local to this session. Model writes return an
--- undo entry; Push keeps it and shows a toast with an Undo button. Region Map
--- table writes are not on the engine undo stack (Ctrl+Z), so this is the only
--- undo they have. The UI draws Current() and redraws when Version() changes.
--- @class RegionMapUndo: GameType
--- @field new fun(o?: table): RegionMapUndo
RegionMapUndo = RegisterGameType("RegionMapUndo")
local C = RegionMapConstants
local Model = RegionMapModel
local Copy = RegionMapCopy

--- The one toast on screen. Newer toasts replace it.
--- @class RegionMapToast
--- @field text string already filled in from the copy manifest
--- @field entry nil|RegionMapUndoEntry offers Undo while the entry can still be reverted
--- @field retry nil|fun() offers Retry (toast.saveFailed)
--- @field action nil|RegionMapToastAction one more button, e.g. "Replace image..." on a size warning
--- @field remaining number seconds left; counts down only while not paused
--- @field paused boolean true while the pointer is over the toast (R9)

--- A toast button that runs any action; the toast closes first.
--- @class RegionMapToastAction
--- @field text string the button label, already filled in from the copy manifest
--- @field click fun()

local stack = {} --- @type RegionMapUndoEntry[] newest last
local toast = nil --- @type nil|RegionMapToast
local version = 0
local timerGeneration = 0

-- Seconds between timer ticks and between checks while an undo waits for its writes.
local tick = C.undoTick
local settleTimeout = C.undoSettleSeconds

local function Changed()
    version = version + 1
end

local function RemoveFromStack(entry)
    for i = #stack, 1, -1 do
        if stack[i] == entry then table.remove(stack, i) end
    end
end

-- One timer chain per toast: a new toast bumps the generation and the old chain stops.
local function StartTimer()
    timerGeneration = timerGeneration + 1
    local generation = timerGeneration
    local function Tick()
        if mod.unloaded or generation ~= timerGeneration or toast == nil then return end
        if not toast.paused then toast.remaining = toast.remaining - tick end
        if toast.remaining <= 0 then
            toast = nil
            Changed()
            return
        end
        dmhub.Schedule(tick, Tick)
    end
    dmhub.Schedule(tick, Tick)
end

local function Show(text, entry, retry, action)
    toast = { text = text, entry = entry, retry = retry, action = action, remaining = C.toastSeconds, paused = false }
    Changed()
    StartTimer()
end

--- Keep an undo entry and show its toast. Entries with no steps are ignored.
--- @param entry nil|RegionMapUndoEntry
--- @param copyId string a toast.* manifest ID
--- @param args nil|table<string, any>
function RegionMapUndo.Push(entry, copyId, args)
    if entry == nil or #entry.steps == 0 then return end
    stack[#stack + 1] = entry
    while #stack > C.undoDepth do table.remove(stack, 1) end
    Show(Copy.T(copyId, args), entry, nil)
end

--- Keep an undo entry without a toast, for changes that have no toast copy
--- (session log notes and deletions); "Undo last change" reaches them.
--- @param entry nil|RegionMapUndoEntry
function RegionMapUndo.Remember(entry)
    if entry == nil or #entry.steps == 0 then return end
    stack[#stack + 1] = entry
    while #stack > C.undoDepth do table.remove(stack, 1) end
    Changed()
end

--- Show a toast with no Undo (toast.showing, toast.shown, toast.saveFailed).
--- @param copyId string
--- @param args nil|table<string, any>
--- @param retry nil|fun() adds a Retry button
--- @param action nil|{copyId: string, click: fun()} adds a button labeled from copyId
function RegionMapUndo.Notify(copyId, args, retry, action)
    local button = nil
    if action ~= nil then button = { text = Copy.T(action.copyId), click = action.click } end
    Show(Copy.T(copyId, args), nil, retry, button)
end

--- The toast to draw, or nil.
--- @return nil|RegionMapToast
function RegionMapUndo.Current()
    return toast
end

--- Increases whenever the toast or the undo stack changes; the UI compares it to redraw.
--- @return integer
function RegionMapUndo.Version()
    return version
end

--- Whether the toast should show its Undo button. Turns false for good once
--- someone else changed one of the rows (R14).
--- @return boolean
function RegionMapUndo.ToastCanUndo()
    return toast ~= nil and toast.entry ~= nil and Model.CanRevert(toast.entry)
end

--- Pause the toast timer (hover) and resume it (dehover).
--- @param paused boolean
function RegionMapUndo.SetPaused(paused)
    if toast == nil or toast.paused == paused then return end
    toast.paused = paused
    Changed()
end

--- Close the toast now.
function RegionMapUndo.Dismiss()
    if toast == nil then return end
    toast = nil
    Changed()
end

-- Runs fn once every step of entry has been confirmed by the server, or gives
-- up after settleTimeout (the write is still in flight; undoing it now could
-- not be written).
local function WhenSettled(entry, fn)
    local waited = 0
    local function Check()
        if mod.unloaded then return end
        if Model.IsSettled(entry) then fn(true) return end
        waited = waited + tick
        if waited >= settleTimeout then fn(false) return end
        dmhub.Schedule(tick, Check)
    end
    Check()
end

-- An undo restores rows to an older entry's end state under a new revision;
-- move the older entries onto it, or they would read as changed by someone else.
local function ApplyRebinds(rebinds)
    for _, rebind in ipairs(rebinds) do
        for _, older in ipairs(stack) do
            for _, step in ipairs(older.steps) do
                if step.tableName == rebind.tableName and step.id == rebind.id and step.state == rebind.state
                    and step.afterRevision == rebind.fromRevision and step.afterMutationId == rebind.fromMutationId then
                    step.afterRevision, step.afterMutationId = rebind.toRevision, rebind.toMutationId
                end
            end
        end
    end
end

--- Undo one entry. Its toast closes with no second toast. When someone else
--- changed one of its rows since, nothing is written, the entry is dropped and
--- its toast loses the Undo button.
--- @param entry RegionMapUndoEntry
--- @param done nil|fun(ok: boolean)
function RegionMapUndo.Undo(entry, done)
    WhenSettled(entry, function(settled)
        local allowed = settled and Model.CanRevert(entry)
        local ok = false
        if allowed then
            local rebinds
            ok, rebinds = Model.Revert(entry)
            ApplyRebinds(rebinds)
        end
        RemoveFromStack(entry)
        if toast ~= nil and toast.entry == entry then
            if ok then toast = nil else toast.entry = nil end
        end
        -- A refused undo is silent (the button just goes); a failed upload says so.
        if allowed and not ok then RegionMapUndo.Notify("toast.saveFailed") end
        Changed()
        if done ~= nil then done(ok) end
    end)
end

--- Undo the newest entry of this session that can still be reverted ("Undo
--- last change" in the session log). Entries that can no longer be reverted
--- are dropped on the way, since that never becomes possible again.
--- @param done nil|fun(ok: boolean)
--- @return boolean started false when there is nothing to undo
function RegionMapUndo.UndoLast(done)
    while #stack > 0 do
        local entry = stack[#stack]
        if Model.IsSettled(entry) and not Model.CanRevert(entry) then
            table.remove(stack)
            Changed()
        else
            RegionMapUndo.Undo(entry, done)
            return true
        end
    end
    return false
end

--- Whether "Undo last change" has anything to do.
--- @return boolean
function RegionMapUndo.HasUndo()
    for i = #stack, 1, -1 do
        if Model.CanRevert(stack[i]) then return true end
    end
    return false
end

--- Keep an undo entry like Push, but fold it into the newest entry when both rewrote the
--- same single row, this one starting exactly where that one ended, within seconds and under
--- the same key. A slider drag or a burst of typing then takes one Undo, not twenty.
--- @param entry nil|RegionMapUndoEntry
--- @param copyId nil|string toast copy; nil keeps it without a toast (like Remember)
--- @param key string what may merge: the same row and kind of change
--- @param seconds number
function RegionMapUndo.PushMerged(entry, copyId, key, seconds)
    if entry == nil or #entry.steps == 0 then return end
    local top, now = stack[#stack], dmhub.Time()
    local step = entry.steps[1]
    local last = top and top.steps[1]
    if top ~= nil and top.mergeKey == key and now - (top.mergedAt or -math.huge) <= seconds
        and #top.steps == 1 and #entry.steps == 1 and last.tableName ~= nil
        and last.tableName == step.tableName and last.id == step.id and step.before ~= nil
        and RegionMapRecords.RecordRevision(step.before) == last.afterRevision
        and RegionMapRecords.Field(step.before, "mutationId", nil) == last.afterMutationId then
        last.afterRevision, last.afterMutationId = step.afterRevision, step.afterMutationId
        top.mergedAt = now
        if copyId ~= nil then Show(Copy.T(copyId), top, nil) else Changed() end
        return
    end
    entry.mergeKey, entry.mergedAt = key, now
    if copyId ~= nil then RegionMapUndo.Push(entry, copyId) else RegionMapUndo.Remember(entry) end
end

-- Save queues ------------------------------------------------------------------------------------

--- One change set on its way to a row. Batches are immutable once queued; a failed batch
--- keeps its place, so Retry resends exactly what failed.
--- @class RegionMapSaveBatch
--- @field changes table
--- @field kind string "edit" unless the owner sends something else ("delete", "reset", "moved"...)
--- @field entry nil|RegionMapUndoEntry
--- @field retry nil|RegionMapRetry
--- @field repaired nil|boolean the owner already repaired it once

--- How a save queue reaches its rows. The owner (labels, map pin text) supplies these.
--- @class RegionMapSaveQueueSpec
--- @field canEdit fun(id: string): boolean checked before every send; false drops unsent work
--- @field busy fun(id: string): boolean the row has a write in flight
--- @field send fun(id: string, batch: RegionMapSaveBatch, callbacks: RegionMapWriteCallbacks): boolean, nil|string, nil|RegionMapUndoEntry, nil|RegionMapWrite
--- @field filter nil|fun(id: string, changes: table): table drop changes no longer permitted, keep the rest
--- @field hold nil|fun(id: string, changes: table): boolean true keeps typed changes unsent ("invalid") until more typing fixes them
--- @field coalesce nil|fun(first: RegionMapSaveBatch, later: RegionMapSaveBatch): nil|RegionMapSaveBatch fold a later batch into the unsent first one (one write instead of two)
--- @field repair nil|fun(id: string, batch: RegionMapSaveBatch): nil|table changes to try once more after "invalid"
--- @field copyId nil|fun(id: string, batch: RegionMapSaveBatch): nil|string toast for a saved batch; nil keeps Undo silently
--- @field mergeKinds nil|table<string, boolean> kinds whose saves of one row merge their Undo entries
--- @field saved nil|fun(id: string, batch: RegionMapSaveBatch)

--- Per row: typed changes wait (Stage) and go out as batches, one write at a time.
--- status: "saved" | "pending" (waiting to send) | "saving" | "failed" (Retry offered)
--- | "invalid" (a batch was refused as invalid and dropped) | "denied" (permission lost; unsent work dropped).
--- @class RegionMapSaveQueueState
--- @field pending table
--- @field items RegionMapSaveBatch[]
--- @field running boolean
--- @field failed boolean
--- @field status string
--- @field timer integer bumps whenever a scheduled autosave must not fire
--- @field version integer bumps on every change, for UI signatures
--- @field notify nil|fun()
--- @field left nil|boolean the editor closed; the queue goes once it is idle

--- Build the queues of one kind of row. Owners keep any extra state (such as an unsaved
--- draft) themselves and see it again in send.
--- @param spec RegionMapSaveQueueSpec
--- @return table api
function RegionMapUndo.SaveQueue(spec)
    local queues = {} --- @type table<string, RegionMapSaveQueueState>
    local api = {}
    local Drain

    local function Notify(q)
        q.version = q.version + 1
        if q.notify ~= nil then q.notify() end
    end

    local function Get(id)
        local q = queues[id]
        if q == nil then
            q = { pending = {}, items = {}, running = false, failed = false, status = "saved", timer = 0, version = 0 }
            queues[id] = q
        end
        return q
    end

    local function Idle(q)
        return not q.running and not q.failed and #q.items == 0 and next(q.pending) == nil
    end

    local function Later(id, delay)
        dmhub.Schedule(delay, function() if not mod.unloaded then Drain(id) end end)
    end

    --- @param id string
    --- @return nil|RegionMapSaveQueueState
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
        for key, value in pairs(changes) do q.pending[key] = value end
        q.timer = q.timer + 1
        if q.status ~= "failed" then q.status = "pending" end
        local timer = q.timer
        dmhub.Schedule(C.autosaveDelay, function()
            if not mod.unloaded and queues[id] == q and q.timer == timer then api.Flush(id) end
        end)
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
        while spec.coalesce and q.items[2] ~= nil do
            local merged = spec.coalesce(batch, q.items[2])
            if merged == nil then break end
            table.remove(q.items, 2)
            q.items[1], batch = merged, merged
        end
        if spec.filter and not batch.retry then batch.changes = spec.filter(id, batch.changes) end
        q.running, q.status = true, "saving"
        local function Receipt(success, operation)
            -- Upload callbacks may run before send returns its Undo entry.
            dmhub.Schedule(0, function()
                if mod.unloaded or queues[id] ~= q or q.items[1] ~= batch or not q.running then return end
                q.running = false
                if success then
                    table.remove(q.items, 1)
                    q.status = next(q.pending) ~= nil and "pending" or "saved"
                    local copyId = spec.copyId and spec.copyId(id, batch) or nil
                    if spec.mergeKinds and spec.mergeKinds[batch.kind] then
                        RegionMapUndo.PushMerged(batch.entry, copyId, id .. ":" .. batch.kind, C.undoMergeSeconds)
                    elseif copyId ~= nil then RegionMapUndo.Push(batch.entry, copyId)
                    else RegionMapUndo.Remember(batch.entry) end
                    if spec.saved then spec.saved(id, batch) end
                    Notify(q)
                    Drain(id)
                    if q.left and Idle(q) and queues[id] == q then queues[id] = nil end
                elseif spec.canEdit(id) then
                    q.failed, q.status = true, "failed"
                    batch.retry = { operation = operation, before = batch.entry and batch.entry.steps[1].before }
                    RegionMapUndo.Notify("toast.saveFailed", nil, function() api.Retry(id) end)
                    Notify(q)
                else
                    table.remove(q.items, 1)
                    api.Cancel(id)
                end
            end)
        end
        local ok, reason, entry, operation = spec.send(id, batch, {
            success = function(op) Receipt(true, op) end,
            failure = function(op) Receipt(false, op) end,
        })
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
    --- @return RegionMapSaveBatch[] batches
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
    --- @param fn nil|fun()
    function api.Observe(id, fn)
        local q = Get(id)
        q.notify, q.left = fn, false
    end

    --- The editor closed: send typed changes and forget the queue once nothing is left in it
    --- (now, or when its last write is confirmed). Until then its observer still hears receipts.
    --- @param id string
    function api.Leave(id)
        api.Flush(id)
        local q = queues[id]
        if q == nil then return end
        q.left = true
        if Idle(q) then queues[id] = nil end
    end

    --- Forget idle queues nobody observes (the editor that opened them is gone).
    function api.Prune()
        for id, q in pairs(queues) do
            if q.notify == nil and Idle(q) then queues[id] = nil end
        end
    end

    --- @return table<string, RegionMapSaveQueueState>
    function api.All() return queues end

    return api
end
