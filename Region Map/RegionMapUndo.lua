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
local tick = 0.25
local settleTimeout = 5

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
