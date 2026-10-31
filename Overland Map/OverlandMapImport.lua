local mod = dmhub.GetModLoading()

--- JSON import of Locations into the open map (V2.1 idea 9, brief IM1-IM7).
--- Director only. Paste JSON or choose a file, preview, then create Locations
--- in batches as one undo entry. The format is in docs/IMPORT_FORMAT.md.
---
--- Create(ctx) returns the card layer for the shell. Its data holds:
---   start()                 open the editor (does nothing while an import is running)
---   openFile(path, mapId)   check a file and show its preview card (what the dialog calls)
---   close()                 ask before discarding a draft and closing the card
---   requestClose(continue)  the same discard guard for mod-owned host actions
--- @class OverlandMapImport: GameType
--- @field new fun(o?: table): OverlandMapImport
OverlandMapImport = RegisterGameType("OverlandMapImport")
local C = OverlandMapConstants
local Model = OverlandMapModel
local R = OverlandMapRecords
local Session = OverlandMapControls
local Copy = OverlandMapCopy
local Undo = OverlandMapUndo

local T = Copy.T
local SetText = Session.SetText
local running = false

--- One file entry that passed the checks, ready to create.
--- @class OverlandMapImportEntry
--- @field index integer position in the file, from 1
--- @field name string
--- @field u nil|number nil until placed on the grid
--- @field v nil|number
--- @field style OverlandMapPinStyle
--- @field description nil|string
--- @field note nil|string

--- A checked file: what will be created and what was left out.
--- @class OverlandMapImportPlan
--- @field entries OverlandMapImportEntry[]
--- @field skipped string[] first importPreviewLimit reasons, in file order
--- @field skippedCount integer total skipped entries
--- @field duplicates string[] first importPreviewLimit names already on the map, each once
--- @field duplicateCount integer total distinct duplicate names
--- @field error nil|"json"|"empty"|"allSkipped"

-- Enum fields of an entry and the values each accepts.
local enums = { pinStyle = R.pinStyles, importance = R.importances, visibility = R.visibilities }

-- A multi-line field ("description", "note"): the text, or nil plus a reason line.
local function CheckText(raw, field, index, limit, byteLimit)
    local value = raw[field]
    if value == nil then return nil, nil end
    if type(value) ~= "string" then return nil, T("import.skip.field", { n = index, field = field }) end
    local normalized = R.NormalizeMultiline(value, limit, byteLimit)
    if normalized ~= nil then return normalized, nil end
    -- Too long is the common case; control characters read as "not a valid value".
    if #value > byteLimit or R.TextLength(value) > limit then
        return nil, T("import.skip.tooLong", { n = index, field = field })
    end
    return nil, T("import.skip.field", { n = index, field = field })
end

--- Check one file entry. The same rules as a typed edit apply (the file is
--- untrusted input), so a row that gets in is an ordinary Location.
--- @param raw any
--- @param index integer
--- @return nil|OverlandMapImportEntry entry
--- @return nil|string reason when skipped
function OverlandMapImport.CheckEntry(raw, index)
    if type(raw) ~= "table" then return nil, T("import.skip.noName", { n = index }) end
    local name = raw.name
    if name == nil or (type(name) == "string" and name:match("^%s*$")) then
        return nil, T("import.skip.noName", { n = index })
    end
    if type(name) ~= "string" then return nil, T("import.skip.field", { n = index, field = "name" }) end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if not R.ValidText(name) then return nil, T("import.skip.name", { n = index, limit = C.textLimit }) end

    local u, v = raw.u, raw.v
    if (u ~= nil or v ~= nil) and not (R.ValidUnit(u) and R.ValidUnit(v)) then
        return nil, T("import.skip.position", { n = index })
    end
    for field, allowed in pairs(enums) do
        local value = raw[field]
        if value ~= nil and not allowed[value] then return nil, T("import.skip.field", { n = index, field = field }) end
    end
    -- Only the curated icon keys: a library id cannot be checked from a file.
    local icon = raw.icon
    if icon ~= nil and (type(icon) ~= "string" or C.pinIcons[icon] == nil) then
        return nil, T("import.skip.field", { n = index, field = "icon" })
    end
    local description, descriptionReason = CheckText(raw, "description", index, C.descriptionLimit, C.descriptionByteLimit)
    if descriptionReason ~= nil then return nil, descriptionReason end
    local note, noteReason = CheckText(raw, "note", index, C.noteLimit, C.noteByteLimit)
    if noteReason ~= nil then return nil, noteReason end

    return {
        index = index, name = name, u = u, v = v,
        style = { icon = icon, pinStyle = raw.pinStyle, importance = raw.importance, visibility = raw.visibility or "hidden" },
        description = description ~= "" and description or nil,
        note = note ~= "" and note or nil,
    }, nil
end

-- The entry list of a parsed file: a top-level array, or {"locations": [...]}.
-- Anything else holds no entries. JSON nulls arrive as gaps, kept as nil entries.
local function EntriesOf(data)
    if type(data) == "table" and data.locations ~= nil then data = data.locations end
    if type(data) ~= "table" then return {}, 0 end
    local count = 0
    for key in pairs(data) do
        if math.type(key) == "integer" and key > count then count = key end
    end
    return data, count
end

--- Check a parsed file against a map.
--- @param data any what ReadFile or ReadText returned
--- @param mapId string
--- @return OverlandMapImportPlan
function OverlandMapImport.Check(data, mapId)
    --- @type OverlandMapImportPlan
    local plan = { entries = {}, skipped = {}, skippedCount = 0, duplicates = {}, duplicateCount = 0, error = nil }
    local list, count = EntriesOf(data)
    if count == 0 then
        plan.error = "empty"
        return plan
    end
    local existing = {} --- @type table<string, boolean>
    for _, child in ipairs(Model.Children(mapId)) do existing[R.MapNameKey(child.name)] = true end
    local listed = {} --- @type table<string, boolean>
    for index = 1, count do
        local entry, reason = OverlandMapImport.CheckEntry(list[index], index)
        if entry == nil then
            plan.skippedCount = plan.skippedCount + 1
            if #plan.skipped < C.importPreviewLimit then plan.skipped[#plan.skipped + 1] = reason or "" end
        else
            plan.entries[#plan.entries + 1] = entry
            local key = R.MapNameKey(entry.name)
            if existing[key] and not listed[key] then
                listed[key] = true
                plan.duplicateCount = plan.duplicateCount + 1
                if #plan.duplicates < C.importPreviewLimit then plan.duplicates[#plan.duplicates + 1] = entry.name end
            end
        end
    end
    if #plan.entries == 0 then plan.error = "allSkipped" end
    return plan
end

--- Parse the same text that was checked; file imports have no editor length cap.
--- @param text nil|string
--- @return any data
--- @return nil|"json"|"empty" error
local function ParseText(text)
    if text == nil then return nil, "json" end
    if R.TextLength(text) == math.huge then return nil, "json" end
    text = text:gsub("^\239\187\191", "")
    if text:match("^%s*$") then return nil, "empty" end
    local ok, parsed = pcall(dmhub.FromJson, text)
    if not ok or type(parsed) ~= "table" or parsed.success ~= true or parsed.result == nil then return nil, "json" end
    return parsed.result, nil
end

--- @param path string
--- @return any data
--- @return nil|"json"|"empty" error
function OverlandMapImport.ReadFile(path)
    return ParseText(dmhub.ReadTextFile(path))
end

--- Parse pasted JSON without letting the editor's native cap silently shorten an import.
--- @param text string
--- @return any data
--- @return nil|"json"|"empty"|"tooLong" error
function OverlandMapImport.ReadText(text)
    local length = R.TextLength(text)
    if length == math.huge then return nil, "json" end
    if length > C.importTextLimit then return nil, "tooLong" end
    return ParseText(text)
end

--- @param mapId nil|string
--- @return nil|"permission"|"unavailable" reason
local function Unavailable(mapId)
    if not Model.IsDirector() then return "permission" end
    if mapId == nil or Model.GetLocation(mapId) == nil or not Model.CanAdd(mapId) then return "unavailable" end
    return nil
end

--- Grid places for count Locations without a position: rows around the map's
--- center in file order (Q24), spaced so pins and names do not overlap at Fit.
--- aspect is the image's width / height.
--- @param count integer
--- @param aspect number
--- @return {u: number, v: number}[]
function OverlandMapImport.GridPositions(count, aspect)
    local positions = {} --- @type {u: number, v: number}[]
    if count <= 0 then return positions end
    local du = C.importSpacing
    -- v is a share of the height, so the aspect turns the screen gap into v units.
    local dv = du * aspect * C.importRowShare
    local columns = math.min(math.ceil(math.sqrt(count)), math.floor(0.9 / du) + 1)
    local rows = math.ceil(count / columns)
    -- A tall stack would leave the map; squeeze the rows to fit instead.
    if rows > 1 and (rows - 1) * dv > 0.9 then dv = 0.9 / (rows - 1) end
    for i = 0, count - 1 do
        local row, column = i // columns, i % columns
        -- A short last row is centered too.
        local inRow = math.min(columns, count - row * columns)
        positions[#positions + 1] = {
            u = Model.Clamp(0.5 + (column - (inRow - 1) / 2) * du, 0, 1),
            v = Model.Clamp(0.5 + (row - (rows - 1) / 2) * dv, 0, 1),
        }
    end
    return positions
end

-- Commit -----------------------------------------------------------------------------------------

--- Whether an import is still writing; the toolbar's Import button is disabled meanwhile.
--- @return boolean
function OverlandMapImport.IsRunning()
    return running
end

-- Create the plan's Locations on a map, a batch at a time: each batch waits for the
-- server, so the Undo entry holds only rows that exist. A failed write stops the import
-- after the current batch; its toast then carries the Undo for what was written.
--
-- Undo is partial: it removes every imported Location nobody has changed since, so
-- touching one pin during a long import does not lose Undo for the rest. Description and
-- note rows stay stored after Undo but nothing shows them, as with any deleted Location.
--
-- With several creates in flight, the engine can confirm a row before it reaches the
-- local table, so a row is only written to again (its description and note) from this
-- loop once Model.GetLocation can read it, never from a callback.
local function Commit(ctx, mapId, plan, aspect, onDone)
    local loose = {} --- @type OverlandMapImportEntry[]
    for _, entry in ipairs(plan.entries) do
        if entry.u == nil then loose[#loose + 1] = entry end
    end
    local grid = OverlandMapImport.GridPositions(#loose, aspect)
    for i, entry in ipairs(loose) do entry.u, entry.v = grid[i].u, grid[i].v end

    local confirmed = {} --- @type OverlandMapUndoStep[]
    local failed, reason = false, "unavailable"
    local pending = 0

    -- Each write settles once, whether its upload failed at once or the server answered.
    local function Tracker()
        local item = { settled = false, ok = false }
        pending = pending + 1
        function item.Settle(ok)
            if item.settled then return end
            item.settled, item.ok = true, ok
            pending = pending - 1
            if not ok then failed = true end
        end
        item.callbacks = { success = function() item.Settle(true) end, failure = function() item.Settle(false) end }
        return item
    end

    -- Yield until ready() is true; false when the wait ran out or the mod reloaded.
    local function WaitFor(ready)
        local started = dmhub.Time()
        while not ready() do
            if mod.unloaded or dmhub.Time() - started >= C.importWait then return false end
            coroutine.yield(0.05)
        end
        return true
    end

    local function Stop()
        local why = Unavailable(mapId)
        if why ~= nil then failed, reason = true, why end
        return failed or mod.unloaded
    end

    local function Run()
        local first = 1
        while first <= #plan.entries and not Stop() do
            local last = math.min(first + C.importBatch - 1, #plan.entries)

            -- 1. Create the batch's Locations (one permission check) and wait for the server.
            pending = 0
            local items, trackers = {}, {}
            for i = first, last do
                local entry = plan.entries[i]
                local tracker = Tracker()
                trackers[#trackers + 1] = tracker
                items[#items + 1] = { u = entry.u, v = entry.v, style = entry.style, name = entry.name, callbacks = tracker.callbacks }
            end
            local batch = OverlandMapCommands.CreateLocations(mapId, items)
            if batch.reason ~= nil then
                failed, reason = true, batch.reason
                break
            end
            local results = batch.rows or {}
            for i, result in ipairs(results) do
                if result.step == nil then trackers[i].Settle(false) end
            end
            if not WaitFor(function() return pending <= 0 end) then failed = true end
            local created = {} --- @type {id: string, entry: OverlandMapImportEntry, step: OverlandMapUndoStep}[]
            for i, result in ipairs(results) do
                if trackers[i].ok and result.step ~= nil and result.id ~= nil then
                    Model.GuardLocationUndo(result.step)
                    confirmed[#confirmed + 1] = result.step
                    created[#created + 1] = { id = result.id, entry = plan.entries[first + i - 1], step = result.step }
                end
            end

            -- 2. Once the rows can be read, save their descriptions and notes; rows a
            -- failed batch did create still get theirs, so no imported pin is left half-made.
            local readable = WaitFor(function()
                for _, row in ipairs(created) do
                    if Model.GetLocation(row.id) == nil then return false end
                end
                return true
            end)
            if not readable then failed = true end
            if readable and Unavailable(mapId) == nil then
                pending = 0
                for _, row in ipairs(created) do
                    if row.entry.description ~= nil then
                        local tracker = Tracker()
                        local result = OverlandMapCommands.SaveDetails(row.id, { description = row.entry.description }, tracker.callbacks)
                        if not OverlandMapCommands.Accepted(result) then tracker.Settle(false) end
                    end
                    if row.entry.note ~= nil then
                        local tracker = Tracker()
                        local result = OverlandMapCommands.SaveDirectorNote(row.id, row.entry.note, tracker.callbacks)
                        if not OverlandMapCommands.Accepted(result) then tracker.Settle(false) end
                    end
                    -- Capture our text writes before yielding to edits in this or another window.
                    Model.GuardLocationUndo(row.step)
                end
                if not WaitFor(function() return pending <= 0 end) then failed = true end
            end

            if not mod.unloaded and ctx.IsAlive() then ctx.RefreshAll() end
            first = last + 1
        end
    end

    dmhub.Coroutine(function()
        -- Whatever happens inside, the import ends: Import works again and what was written keeps its Undo.
        local ok, message = pcall(Run)
        if not ok then
            failed = true
            print("OVERLAND_MAP: import stopped: " .. tostring(message))
        end
        -- Release the lock before touching UI callbacks, which may themselves fail.
        onDone()
        if not mod.unloaded then
            local map = Model.GetLocation(mapId)
            local entry = { description = "Import overland map locations", steps = confirmed, partial = true }
            if failed then
                if #confirmed > 0 then ctx.Push(entry, "toast.importStopped", { count = #confirmed })
                elseif reason == "permission" then Undo.Notify("import.permission")
                else ctx.Report(false, "unavailable") end
            else
                ctx.Push(entry, "toast.imported", { count = #confirmed, map = Model.DisplayName(map) })
            end
        end
        if not mod.unloaded and ctx.IsAlive() then ctx.RefreshAll() end
    end)
end

-- Card -------------------------------------------------------------------------------------------

--- @class OverlandMapImportPending
--- @field data any parsed source, retained so the preview can be checked again
--- @field plan OverlandMapImportPlan
--- @field source "file"|"text"
--- @field aspect number
--- @field imageId string
--- @field imageRevision number
--- @field mapName string

--- @class OverlandMapImportState
--- @field mode "closed"|"edit"|"preview"
--- @field generation integer
--- @field mapId nil|string
--- @field mapName string
--- @field text string
--- @field error nil|string copy id
--- @field pending nil|OverlandMapImportPending

local function SameLines(a, b)
    if #a ~= #b then return false end
    for i, value in ipairs(a) do if value ~= b[i] then return false end end
    return true
end

--- Build the import card layer.
--- @param ctx OverlandMapContext
--- @return Panel
function OverlandMapImport.Create(ctx)
    local layer
    --- @type TextEditor
    local editor
    local editBody
    local editScroll
    local contractScroll
    local previewScroll
    local lines
    local target
    local counter
    local errorLabel
    local sourceButtons
    local previewButton
    local okButton
    local backButton

    --- @return OverlandMapImportState
    local function State() return layer.data end

    local function Alive()
        return not mod.unloaded and ctx.IsAlive() and layer ~= nil and layer.valid
    end

    local function HasDraft()
        return editor.text:gsub("^\239\187\191", ""):match("^%s*$") == nil
    end

    local function RefreshControls()
        local state = State()
        if state.mode == "closed" then return end
        local reason = Unavailable(state.mapId)
        local length = R.TextLength(editor.text)
        local errorId = state.error
        if state.mode == "edit" then
            if length == math.huge then errorId = "import.text.json"
            elseif length > C.importTextLimit then errorId = "import.text.tooLong" end
        end
        if reason ~= nil then errorId = "import." .. reason end
        local map = Model.GetLocation(state.mapId)
        if map ~= nil then state.mapName = Model.DisplayName(map) end
        SetText(target, T("import.into", { map = state.mapName }))
        SetText(counter, T("import.count", { count = length == math.huge and "?" or length, limit = C.importTextLimit }))
        SetText(errorLabel, errorId ~= nil and T(errorId, { limit = C.importTextLimit }) or "")
        errorLabel:SetClass("collapsed", errorId == nil)
        previewButton:SetClass("disabled", reason ~= nil or length > C.importTextLimit or not HasDraft())
        okButton:SetClass("disabled", reason ~= nil or running)
        okButton:SetClass("collapsed", state.mode ~= "preview" or state.pending == nil)
    end

    --- @param mode "closed"|"edit"|"preview"
    local function SetMode(mode)
        local state = State()
        state.generation = state.generation + 1
        state.mode, state.pending, state.error = mode, nil, nil
        layer:SetClass("collapsed", mode == "closed")
        editScroll:SetClass("collapsed", mode ~= "edit")
        previewScroll:SetClass("collapsed", mode ~= "preview")
        sourceButtons:SetClass("collapsed", mode ~= "edit")
        previewButton:SetClass("collapsed", mode ~= "edit")
        backButton:SetClass("collapsed", mode ~= "preview")
        okButton:SetClass("collapsed", true)
    end

    local function Close()
        SetMode("closed")
        State().mapId, State().text, State().mapName = nil, "", ""
        editor.textNoNotify = ""
        ctx.RefreshAll()
    end

    local function ShowEditor(errorId)
        SetMode("edit")
        State().error = errorId
        contractScroll.vscrollPosition = 1
        contractScroll:ScheduleEvent("contractTop", C.afterLayoutDelay)
        RefreshControls()
        Session.FocusSoon(editor, function() return Alive() and State().mode == "edit" end)
        ctx.RefreshAll()
    end

    local function ConfirmDraft(titleId, okId, action)
        if not Alive() then return end
        if not HasDraft() then action(); return end
        local generation = State().generation
        ctx.Confirm {
            title = T(titleId), confirm = T(okId),
            onConfirm = function()
                if Alive() and State().generation == generation then action() end
            end,
        }
    end

    local function RequestClose(continue)
        ConfirmDraft("import.discard", "import.discard.ok", function()
            Close()
            if continue ~= nil then continue() end
        end)
    end

    local function SyncInput()
        local state = State()
        if state.text ~= editor.text then
            state.text = editor.text
            state.generation = state.generation + 1
            state.pending, state.error = nil, nil
            if state.mode == "preview" then ShowEditor(nil) end
        end
        RefreshControls()
    end

    local function Line(text, classes)
        return gui.Label { classes = classes or { "overlandMapImportLine", "sizeS" }, text = text, interactable = false }
    end

    local function ShowRows(rows)
        lines.children = rows
        local generation = State().generation
        previewScroll.vscrollPosition = 1
        OverlandMapLifetime.Schedule(C.afterLayoutDelay, function()
            if Alive() and State().generation == generation then previewScroll.vscrollPosition = 1 end
        end)
        RefreshControls()
        Session.FocusSoon(State().pending ~= nil and okButton or backButton,
            function() return Alive() and State().generation == generation end)
        ctx.RefreshAll()
    end

    local function Reasons(rows, reasons, total)
        for _, reason in ipairs(reasons) do rows[#rows + 1] = Line(reason, { "overlandMapImportLine", "item", "sizeS" }) end
        if total > #reasons then rows[#rows + 1] = Line(T("import.more", { count = total - #reasons })) end
    end

    local function Preview(data, source, readError)
        if not Alive() or running then return end
        local state = State()
        local reason = Unavailable(state.mapId)
        if reason ~= nil then ShowEditor("import." .. reason); return end
        if source == "text" and readError ~= nil then
            ShowEditor("import.text." .. readError)
            return
        end
        local map = Model.GetLocation(state.mapId)
        if map == nil then return end
        SetMode("preview")
        local errorPrefix = source == "file" and "import.error." or "import.text."
        if readError == "json" then ShowRows({ Line(T(errorPrefix .. "json")) }); return end
        local plan = OverlandMapImport.Check(data, map.id)
        if readError == "empty" or plan.error == "empty" then
            ShowRows({ Line(T(errorPrefix .. "empty")) })
            return
        end
        if plan.error == "allSkipped" then
            local rows = { Line(T(errorPrefix .. "allSkipped")) }
            Reasons(rows, plan.skipped, plan.skippedCount)
            ShowRows(rows)
            return
        end
        local count = #plan.entries
        local rows = { Line(T("import.summary", { count = count, map = Model.DisplayName(map) }), { "overlandMapImportLine", "lead", "sizeM" }) }
        if plan.skippedCount > 0 then
            rows[#rows + 1] = Line(T("import.skipped", { count = plan.skippedCount }), { "overlandMapImportLine", "heading", "sizeS" })
            Reasons(rows, plan.skipped, plan.skippedCount)
        end
        if plan.duplicateCount > 0 then
            rows[#rows + 1] = Line(T("import.duplicates", { count = plan.duplicateCount }), { "overlandMapImportLine", "heading", "sizeS" })
            local names = {} --- @type string[]
            for _, name in ipairs(plan.duplicates) do names[#names + 1] = Copy.Literal(name) end
            Reasons(rows, names, plan.duplicateCount)
        end
        rows[#rows + 1] = Line(T("import.placement"), { "overlandMapImportLine", "note", "sizeS" })
        local job = {
            data = data, plan = plan, source = source, aspect = 1.5,
            imageId = map.imageId, imageRevision = map.imageRevision, mapName = Model.DisplayName(map),
        }
        state.pending = job
        local generation = state.generation
        OverlandMapImages.Size(map.imageId, function(width, height)
            if Alive() and State().generation == generation and State().pending == job and height > 0 then
                job.aspect = width / height
            end
        end, function()
            local current = ctx.CurrentMap()
            return ctx.IsAlive() and current ~= nil and current.id == map.id and current.imageId == map.imageId
        end)
        SetText(okButton, T("import.ok", { count = count }))
        ShowRows(rows)
    end

    local function Import()
        if not Alive() or running then return end
        local state = State()
        local job = state.pending
        if job == nil then return end
        local reason = Unavailable(state.mapId)
        if reason ~= nil then ShowEditor("import." .. reason); return end
        local map = Model.GetLocation(state.mapId)
        if map == nil then return end
        local fresh = OverlandMapImport.Check(job.data, map.id)
        if job.mapName ~= Model.DisplayName(map) or job.imageId ~= map.imageId or job.imageRevision ~= map.imageRevision
            or fresh.error ~= job.plan.error or #fresh.entries ~= #job.plan.entries
            or fresh.skippedCount ~= job.plan.skippedCount or fresh.duplicateCount ~= job.plan.duplicateCount
            or not SameLines(fresh.skipped, job.plan.skipped) or not SameLines(fresh.duplicates, job.plan.duplicates) then
            Preview(job.data, job.source, nil)
            return
        end
        local mapId = map.id
        running = true
        Close()
        Commit(ctx, mapId, fresh, job.aspect, function() running = false end)
    end

    local function Begin(mapId)
        if not Alive() or running or Unavailable(mapId) ~= nil then return false end
        State().mapId = mapId
        ShowEditor(nil)
        return true
    end

    local function OpenFile(path, mapId)
        if not Alive() or running or Unavailable(mapId) ~= nil then return end
        if State().mode == "closed" and not Begin(mapId) then return end
        if State().mapId ~= mapId then return end
        local data, readError = OverlandMapImport.ReadFile(path)
        if readError ~= nil or OverlandMapImport.Check(data, mapId).error ~= nil then
            Preview(data, "file", readError)
            return
        end
        ConfirmDraft("import.useFile", "import.useFile.ok", function()
            editor.textNoNotify = ""
            SyncInput()
            Preview(data, "file", nil)
        end)
    end

    local function ChooseFile()
        if not Alive() or running then return end
        local state = State()
        if Unavailable(state.mapId) ~= nil then RefreshControls(); return end
        state.generation = state.generation + 1
        local generation, mapId = state.generation, state.mapId
        dmhub.OpenFileDialog {
            id = "OverlandMapImport", extensions = { "json" }, multiFiles = false, prompt = T("import.picker"),
            open = function(path)
                if Alive() and State().generation == generation and State().mode == "edit" then OpenFile(path, mapId) end
            end,
        }
    end

    editor = Session.TextArea(C.importEditorLimit, {
        id = "overland-map-import-text",
        classes = { "input", "bordered", "sizeS", "monospace", "overlandMapTextArea", "overlandMapImportEditor" },
        richDisplay = false, text = "",
        create = function(element)
            element.data.fontThemeSubscription = ThemeEngine.OnThemeChanged(mod, function()
                if mod.unloaded or not element.valid then return end
                -- Rebinding after a layout keeps monospace glyphs readable across theme switches.
                element:SetClass("monospace", false)
                element:ScheduleEvent("restoreImportFont", C.afterLayoutDelay)
            end)
        end,
        restoreImportFont = function(element)
            if not mod.unloaded and element.valid then element:SetClass("monospace", true) end
        end,
        destroy = function(element)
            local subscription = element.data.fontThemeSubscription
            if subscription ~= nil then subscription:Deregister() end
        end,
        edit = function() if Alive() then SyncInput() end end,
        change = function() if Alive() then SyncInput() end end,
    })
    target = Line("", { "overlandMapImportLine", "overlandMapImportTarget", "sizeS" })
    counter = Line("", { "overlandMapImportLine", "overlandMapImportCounter", "sizeS" })
    errorLabel = Line("", { "overlandMapImportLine", "overlandMapImportError", "collapsed", "sizeS" })
    errorLabel.id = "overland-map-import-error"
    local fields = {
        { name = "name", kind = "string", limit = C.textLimit, required = true },
        { name = "description", kind = "string", limit = C.descriptionLimit },
        { name = "note", kind = "string", limit = C.noteLimit },
        { name = "icon", kind = "string" },
        { name = "pinStyle", kind = "string" },
        { name = "importance", kind = "string" },
        { name = "visibility", kind = "string" },
        { name = "u", kind = "number" },
        { name = "v", kind = "number" },
    }
    local contractLines = { T("import.help.shape"), T("import.help.required"), "" }
    --- @type Panel[]
    local fieldRows = {
        Line(T("import.help.shape"), { "monospace", "overlandMapImportDetail", "sizeXs" }),
        Line(T("import.help.required"), { "overlandMapImportDetail", "sizeXs" }),
    }
    for _, field in ipairs(fields) do
        local name = field.name .. (field.required and " *" or "")
        local detail = T("import.help." .. field.name, {
            limit = field.limit, icons = table.concat(C.pinIconOrder, ", "),
        }, true)
        contractLines[#contractLines + 1] = name .. " (" .. field.kind .. ")\n  " .. detail:gsub("\n", "\n  ")
        fieldRows[#fieldRows + 1] = gui.Panel {
            classes = { "overlandMapImportField" },
            gui.Panel {
                width = "100%", height = "auto", flow = "horizontal", wrap = true,
                gui.Label {
                    classes = { "monospace", "noBold", "overlandMapImportFieldName", "sizeS" }, text = name, interactable = false,
                },
                gui.Label {
                    classes = { "monospace", "overlandMapImportType", "sizeXs" }, text = field.kind, interactable = false,
                },
            },
            Line(detail, { "overlandMapImportDetail", "sizeXs" }),
            gui.Panel { classes = { "overlandMapRule" }, interactable = false },
        }
    end
    local behavior = T("import.help.behavior", { limit = C.importTextLimit }, true)
    contractLines[#contractLines + 1] = "\n" .. behavior
    fieldRows[#fieldRows + 1] = Line(behavior, { "overlandMapImportDetail", "sizeXs" })
    local contract = table.concat(contractLines, "\n")
    contractScroll = gui.Panel {
        id = "overland-map-import-contract-scroll", classes = { "bordered", "bg", "overlandMapImportContract" },
        bgimage = true, vscroll = true,
        contractTop = function(element)
            if Alive() and State().mode == "edit" then element.vscrollPosition = 1 end
        end,
        gui.Panel {
            id = "overland-map-import-contract", classes = { "overlandMapImportFields" },
            data = { text = contract }, children = fieldRows,
        },
    }
    local help = {
        gui.Panel {
            classes = { "overlandMapImportHeader" },
            gui.Label {
                classes = { "overlandMapImportHeading", "sizeS" }, text = T("import.help"), interactable = false,
            },
            gui.Button {
                id = "overland-map-import-copy-contract", classes = { "overlandMapButton", "sizeS", "overlandMapImportCopy" },
                text = T("import.copyContract"), data = { version = 0 },
                click = function(element)
                    if not Alive() then return end
                    dmhub.CopyToClipboard(contract)
                    SetText(element, T("import.copied"))
                    element.data.version = element.data.version + 1
                    element:ScheduleEvent("resetCopy", 2, element.data.version)
                end,
                resetCopy = function(element, version)
                    if Alive() and element.data.version == version then SetText(element, T("import.copyContract")) end
                end,
            },
        },
        contractScroll,
    }
    editBody = gui.Panel {
        classes = { "overlandMapImportEditBody" },
        gui.Panel {
            classes = { "overlandMapImportColumns" },
            gui.Panel {
                classes = { "overlandMapImportEditColumn" },
                gui.Panel {
                    classes = { "overlandMapImportHeader" },
                    Line(T("import.paste"), { "overlandMapImportHeading", "sizeS" }),
                },
                editor, counter,
                Line(T("import.draftHint"), { "overlandMapImportLine", "note", "sizeS" }),
            },
            gui.Panel { classes = { "overlandMapImportHelpColumn" }, children = help },
        },
    }
    editScroll = gui.Panel {
        id = "overland-map-import-edit-scroll", classes = { "overlandMapImportScroll" }, vscroll = true, editBody,
    }
    lines = gui.Panel { classes = { "overlandMapImportLines" } }
    previewScroll = gui.Panel { classes = { "overlandMapImportScroll", "collapsed" }, vscroll = true, lines }
    sourceButtons = gui.Panel {
        classes = { "overlandMapImportActions" },
        gui.Button {
            id = "overland-map-import-file", classes = { "overlandMapButton", "sizeS" }, text = T("import.file"),
            click = ChooseFile,
        },
        gui.Button {
            id = "overland-map-import-example", classes = { "overlandMapButton", "sizeS" }, text = T("import.fill"),
            click = function()
                ConfirmDraft("import.replace", "import.replace.ok", function()
                    -- A confirmed replacement starts a new draft without diffing large unrelated documents.
                    editor.textNoNotify = T("import.example", nil, true)
                    SyncInput()
                    ShowEditor(nil)
                end)
            end,
        },
    }
    editBody:AddChild(sourceButtons)
    sourceButtons:SetAsFirstSibling()
    previewButton = gui.Button {
        id = "overland-map-import-preview", classes = { "overlandMapButton", "sizeS" }, text = T("import.preview"),
        click = function()
            if not Alive() then return end
            SyncInput()
            local data, readError = OverlandMapImport.ReadText(editor.text)
            Preview(data, "text", readError)
        end,
    }
    okButton = gui.Button {
        id = "overland-map-import-ok", classes = { "overlandMapButton", "sizeS" }, text = "",
        click = Import,
    }
    backButton = gui.Button {
        id = "overland-map-import-back", classes = { "overlandMapButton", "sizeS" }, text = T("import.back"),
        click = function() if Alive() then ShowEditor(nil) end end,
    }
    layer = gui.Panel {
        id = "overland-map-import", classes = { "overlandMapConfirmLayer", "collapsed" }, floating = true,
        swallowPress = true,
        data = { mode = "closed", generation = 0, text = "", mapName = "" },
        bind = function()
            if not Alive() or State().mode == "closed" then return end
            local reason = Unavailable(State().mapId)
            if reason ~= nil and State().mode == "preview" then ShowEditor("import." .. reason)
            else RefreshControls() end
        end,
        gui.Panel {
            id = "overland-map-import-card",
            classes = { "overlandMapConfirm", "overlandMapImportCard" },
            rendered = function(element, width)
                local narrow = width < C.importNarrowWidth
                if element.data.narrow ~= narrow then
                    element.data.narrow = narrow
                    element:SetClassTree("importNarrow", narrow)
                end
            end,
            gui.Label { classes = { "overlandMapConfirmTitle", "sizeL" }, text = T("import.title"), interactable = false },
            target, editScroll, previewScroll, errorLabel,
            gui.Panel {
                classes = { "overlandMapImportActions", "footer" }, previewButton, backButton, okButton,
                gui.Button {
                    id = "overland-map-import-cancel", classes = { "overlandMapButton", "sizeS" }, text = T("dlg.cancel"),
                    click = function() RequestClose(nil) end,
                },
            },
        },
    }

    layer.data.openFile = OpenFile
    layer.data.start = function()
        local map = ctx.CurrentMap()
        if map ~= nil and State().mode == "closed" then Begin(map.id) end
    end
    layer.data.close = function() RequestClose(nil) end
    layer.data.requestClose = RequestClose
    return layer
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function OverlandMapImport.Styles()
    return {
        {
            selectors = { "overlandMapConfirm", "overlandMapImportCard" },
            width = C.importCardWidth,
            height = C.importCardHeight,
            -- Percentage caps apply to content bounds, so reserve the card's padding.
            maxWidth = "90%-40",
            maxHeight = "90%-40",
        },
        {
            selectors = { "overlandMapConfirm", "overlandMapImportCard", "importNarrow" },
            pad = 8,
            borderBox = true,
            maxWidth = "90%-16",
            maxHeight = "90%-16",
        },
        {
            selectors = { "overlandMapImportEditBody" },
            width = "100%-16",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
        },
        {
            selectors = { "overlandMapImportScroll" },
            width = "100%",
            height = "100% available",
            minHeight = 0,
            tmargin = 10,
        },
        {
            selectors = { "overlandMapImportColumns" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",
        },
        {
            selectors = { "overlandMapImportColumns", "importNarrow" },
            flow = "vertical",
        },
        {
            selectors = { "overlandMapImportEditColumn" },
            width = "60%-16",
            height = "auto",
            flow = "vertical",
            valign = "top",
            rmargin = 16,
        },
        {
            selectors = { "overlandMapImportHelpColumn" },
            width = "40%",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
        },
        {
            selectors = { "overlandMapImportEditColumn", "importNarrow" },
            width = "100%",
            rmargin = 0,
        },
        {
            selectors = { "overlandMapImportHelpColumn", "importNarrow" },
            width = "100%",
            tmargin = 12,
        },
        {
            selectors = { "overlandMapImportHeader" },
            width = "100%",
            height = "auto",
            minHeight = "36sp",
            flow = "horizontal",
            halign = "left",
            valign = "top",
        },
        {
            selectors = { "overlandMapImportHeading" },
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            rmargin = 8,
            bold = true,
            color = "@fg",
            textAlignment = "left",
            textWrap = true,
        },
        {
            selectors = { "overlandMapImportCopy" },
            height = "28sp",
            halign = "right",
            valign = "center",
            rmargin = 0,
            bmargin = 0,
            priority = 7,
        },
        {
            selectors = { "overlandMapTextArea", "overlandMapImportEditor" },
            -- The native editor adds 8 px of input padding outside its declared height.
            height = 312,
            tmargin = 6,
        },
        {
            selectors = { "overlandMapTextArea", "overlandMapImportEditor", "importNarrow" },
            height = 232,
        },
        {
            selectors = { "overlandMapImportTarget" },
            textAlignment = "center",
            tmargin = 4,
            color = "@fgMuted",
        },
        {
            selectors = { "overlandMapImportCounter" },
            tmargin = 6,
            color = "@fgMuted",
        },
        {
            selectors = { "overlandMapImportContract" },
            width = "100%",
            height = 320,
            tmargin = 6,
            pad = 10,
            borderBox = true,
            halign = "left",
            borderColor = "@borderSolid",
            cornerRadius = 5,
        },
        {
            selectors = { "overlandMapImportContract", "importNarrow" },
            height = 240,
            pad = 10,
            borderBox = true,
        },
        {
            selectors = { "overlandMapImportFields" },
            width = "100%-8",
            height = "auto",
            halign = "left",
            valign = "top",
            flow = "vertical",
        },
        {
            selectors = { "overlandMapImportField" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 6,
        },
        {
            selectors = { "overlandMapRule", "parent:overlandMapImportField" },
            vmargin = 6,
            bgcolor = "@borderSolid",
        },
        {
            selectors = { "overlandMapImportFieldName" },
            width = "auto",
            height = "auto",
            halign = "left",
            textAlignment = "left",
            color = "@fg",
            rmargin = 10,
        },
        {
            selectors = { "overlandMapImportType" },
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            color = "@fgMuted",
        },
        {
            selectors = { "overlandMapImportDetail" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            textWrap = true,
            tmargin = 4,
            color = "@fgMuted",
        },
        OverlandMapStyles.Danger({ "overlandMapImportError" }),
        {
            selectors = { "overlandMapImportError" },
            tmargin = 8,
        },
        {
            selectors = { "overlandMapImportActions" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 10,
        },
        {
            selectors = { "overlandMapImportActions", "importNarrow" },
            tmargin = 4,
        },
        {
            selectors = { "overlandMapButton", "parent:overlandMapImportActions" },
            width = "auto",
            minWidth = 80,
            maxWidth = "100%",
            height = "auto",
            minHeight = 30,
            hpad = 12,
            vpad = 6,
            borderBox = true,
            rmargin = 8,
            bmargin = 4,
            textWrap = true,
        },
        {
            selectors = { "overlandMapImportLines" },
            width = "100%-16",               -- clears the scrollbar when the list scrolls
            halign = "left",
            height = "auto",
            flow = "vertical",
            valign = "top",                  -- a list taller than the scroll box would otherwise center in it
        },
        {
            selectors = { "overlandMapImportLine" },
            width = "100%",
            height = "auto",
            color = "@fg",
            textWrap = true,
        },
        {
            selectors = { "overlandMapImportLine", "lead" },
            color = "@fgStrong",
        },
        {
            selectors = { "overlandMapImportLine", "heading" },
            tmargin = 10,
            bold = true,
        },
        {
            selectors = { "overlandMapImportLine", "item" },
            lmargin = 12,
            width = "100%-12",
            tmargin = 2,
        },
        {
            selectors = { "overlandMapImportLine", "note" },
            tmargin = 12,
            color = "@fgMuted",
        },
    }
end
