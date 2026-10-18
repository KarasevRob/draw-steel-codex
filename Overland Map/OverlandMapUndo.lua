local mod = dmhub.GetModLoading()

--- Overland Map undo and toasts, local to this session. Model writes return an
--- undo entry; Push keeps it and shows a toast with an Undo button. Overland Map
--- table writes are not on the engine undo stack (Ctrl+Z), so this is the only
--- undo they have. The UI draws Current() and redraws when Version() changes.
--- @class OverlandMapUndo: GameType
--- @field new fun(o?: table): OverlandMapUndo
OverlandMapUndo = RegisterGameType("OverlandMapUndo")
local C = OverlandMapConstants
local Model = OverlandMapModel
local Copy = OverlandMapCopy

--- The one toast on screen. Newer toasts replace it.
--- @class OverlandMapToast
--- @field text string already filled in from the copy manifest
--- @field entry nil|OverlandMapUndoEntry offers Undo while the entry can still be reverted
--- @field retry nil|fun() offers Retry (toast.saveFailed)
--- @field action nil|OverlandMapToastAction one more button, e.g. "Replace image..." on a size warning
--- @field remaining number seconds left; counts down only while not paused
--- @field paused boolean true while the pointer is over the toast (R9)

--- A toast button that runs any action; the toast closes first.
--- @class OverlandMapToastAction
--- @field text string the button label, already filled in from the copy manifest
--- @field click fun()

local stack = {} --- @type OverlandMapUndoEntry[] newest last
local toast = nil --- @type nil|OverlandMapToast
local version = 0
local timerGeneration = 0
OverlandMapLifetime.Subscribe(function()
    stack, toast = {}, nil
    timerGeneration, version = timerGeneration + 1, version + 1
end)

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
        OverlandMapLifetime.Schedule(tick, Tick)
    end
    OverlandMapLifetime.Schedule(tick, Tick)
end

local function Show(text, entry, retry, action)
    toast = { text = text, entry = entry, retry = retry, action = action, remaining = C.toastSeconds, paused = false }
    Changed()
    StartTimer()
end

local function ShowOperation(entry, text)
    local function Status()
        return OverlandMapCommands.Settlement(OverlandMapCommands.Result(true, nil, entry))
    end
    local counts = Status()
    local function Text()
        if counts.pending > 0 then return Copy.T("toast.saving") end
        if counts.failed > 0 then
            return Copy.T((counts.confirmed + counts.submitted > 0) and "toast.partiallySaved" or "toast.saveFailed")
        end
        return text
    end
    Show(Text(), entry, nil)
    local shown = toast
    local function Check()
        if toast ~= shown then return end
        counts = Status()
        shown.text = Text()
        shown.remaining = C.toastSeconds
        Changed()
        if counts.pending > 0 then OverlandMapLifetime.Schedule(tick, Check) end
    end
    if counts.pending > 0 then OverlandMapLifetime.Schedule(tick, Check) end
end

--- Keep an undo entry and show its toast. Entries with no steps are ignored.
--- @param entry nil|OverlandMapUndoEntry
--- @param copyId string a toast.* manifest ID
--- @param args nil|table<string, any>
function OverlandMapUndo.Push(entry, copyId, args)
    if entry == nil or #entry.steps == 0 then return end
    stack[#stack + 1] = entry
    while #stack > C.undoDepth do table.remove(stack, 1) end
    ShowOperation(entry, Copy.T(copyId, args))
end

--- Keep an undo entry without a toast, for changes that have no toast copy
--- (session log notes and deletions); "Undo last change" reaches them.
--- @param entry nil|OverlandMapUndoEntry
function OverlandMapUndo.Remember(entry)
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
function OverlandMapUndo.Notify(copyId, args, retry, action)
    local button = nil
    if action ~= nil then button = { text = Copy.T(action.copyId), click = action.click } end
    Show(Copy.T(copyId, args), nil, retry, button)
end

--- The toast to draw, or nil.
--- @return nil|OverlandMapToast
function OverlandMapUndo.Current()
    return toast
end

--- Increases whenever the toast or the undo stack changes; the UI compares it to redraw.
--- @return integer
function OverlandMapUndo.Version()
    return version
end

--- Whether the toast should show its Undo button. Turns false for good once
--- someone else changed one of the rows (R14).
--- @return boolean
function OverlandMapUndo.ToastCanUndo()
    return toast ~= nil and toast.entry ~= nil and Model.CanRevert(toast.entry)
end

--- Pause the toast timer (hover) and resume it (dehover).
--- @param paused boolean
function OverlandMapUndo.SetPaused(paused)
    if toast == nil or toast.paused == paused then return end
    toast.paused = paused
    Changed()
end

--- Close the toast now.
function OverlandMapUndo.Dismiss()
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
        OverlandMapLifetime.Schedule(tick, Check)
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
--- @param entry OverlandMapUndoEntry
--- @param done nil|fun(ok: boolean)
function OverlandMapUndo.Undo(entry, done)
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
        if allowed and not ok then OverlandMapUndo.Notify("toast.saveFailed") end
        Changed()
        if done ~= nil then done(ok) end
    end)
end

--- Undo the newest entry of this session that can still be reverted ("Undo
--- last change" in the session log). Entries that can no longer be reverted
--- are dropped on the way, since that never becomes possible again.
--- @param done nil|fun(ok: boolean)
--- @return boolean started false when there is nothing to undo
function OverlandMapUndo.UndoLast(done)
    while #stack > 0 do
        local entry = stack[#stack]
        if Model.IsSettled(entry) and not Model.CanRevert(entry) then
            table.remove(stack)
            Changed()
        else
            OverlandMapUndo.Undo(entry, done)
            return true
        end
    end
    return false
end

--- Whether "Undo last change" has anything to do.
--- @return boolean
function OverlandMapUndo.HasUndo()
    for i = #stack, 1, -1 do
        if Model.CanRevert(stack[i]) then return true end
    end
    return false
end

--- Keep an undo entry like Push, but fold it into the newest entry when both rewrote the
--- same single row, this one starting exactly where that one ended, within seconds and under
--- the same key. A slider drag or a burst of typing then takes one Undo, not twenty.
--- @param entry nil|OverlandMapUndoEntry
--- @param copyId nil|string toast copy; nil keeps it without a toast (like Remember)
--- @param key string what may merge: the same row and kind of change
--- @param seconds number
function OverlandMapUndo.PushMerged(entry, copyId, key, seconds)
    if entry == nil or #entry.steps == 0 then return end
    local top, now = stack[#stack], dmhub.Time()
    local step = entry.steps[1]
    local last = top and top.steps[1]
    if top ~= nil and top.mergeKey == key and now - (top.mergedAt or -math.huge) <= seconds
        and #top.steps == 1 and #entry.steps == 1 and last.tableName ~= nil
        and last.tableName == step.tableName and last.id == step.id and step.before ~= nil
        and OverlandMapRecords.RecordRevision(step.before) == last.afterRevision
        and OverlandMapRecords.Field(step.before, "mutationId", nil) == last.afterMutationId then
        last.afterRevision, last.afterMutationId = step.afterRevision, step.afterMutationId
        last.receipt = step.receipt
        top.mergedAt = now
        if copyId ~= nil then ShowOperation(top, Copy.T(copyId)) else Changed() end
        return
    end
    entry.mergeKey, entry.mergedAt = key, now
    if copyId ~= nil then OverlandMapUndo.Push(entry, copyId) else OverlandMapUndo.Remember(entry) end
end
