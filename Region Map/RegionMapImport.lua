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
--- @class RegionMapImport: GameType
--- @field new fun(o?: table): RegionMapImport
RegionMapImport = RegisterGameType("RegionMapImport")
local C = RegionMapConstants
local Model = RegionMapModel
local R = RegionMapRecords
local Session = RegionMapSession
local Copy = RegionMapCopy

local T = Copy.T
local SetText = Session.SetText
local running = false

--- One file entry that passed the checks, ready to create.
--- @class RegionMapImportEntry
--- @field index integer position in the file, from 1
--- @field name string
--- @field u nil|number nil until placed on the grid
--- @field v nil|number
--- @field style RegionMapPinStyle
--- @field description nil|string
--- @field note nil|string

--- A checked file: what will be created and what was left out.
--- @class RegionMapImportPlan
--- @field entries RegionMapImportEntry[]
--- @field skipped string[] one reason line per skipped entry, in file order
--- @field duplicates string[] names already on the map, each once
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
--- @return nil|RegionMapImportEntry entry
--- @return nil|string reason when skipped
function RegionMapImport.CheckEntry(raw, index)
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
    local list = {}
    if type(data) ~= "table" then return list, 0 end
    local count = 0
    for key in pairs(data) do
        if math.type(key) == "integer" and key > count then count = key end
    end
    for i = 1, count do list[i] = data[i] end
    return list, count
end

--- Check a parsed file against a map.
--- @param data any what dmhub.ParseJsonFile returned
--- @param mapId string
--- @return RegionMapImportPlan
function RegionMapImport.Check(data, mapId)
    --- @type RegionMapImportPlan
    local plan = { entries = {}, skipped = {}, duplicates = {}, error = nil }
    local list, count = EntriesOf(data)
    if count == 0 then
        plan.error = "empty"
        return plan
    end
    local existing = {} --- @type table<string, boolean>
    for _, child in ipairs(Model.Children(mapId)) do existing[R.MapNameKey(child.name)] = true end
    local listed = {} --- @type table<string, boolean>
    for index = 1, count do
        local entry, reason = RegionMapImport.CheckEntry(list[index], index)
        if entry == nil then
            plan.skipped[#plan.skipped + 1] = reason or ""
        else
            plan.entries[#plan.entries + 1] = entry
            local key = R.MapNameKey(entry.name)
            if existing[key] and not listed[key] then
                listed[key] = true
                plan.duplicates[#plan.duplicates + 1] = entry.name
            end
        end
    end
    if #plan.entries == 0 then plan.error = "allSkipped" end
    return plan
end

--- Read and parse a file. The engine returns nil for both an empty file and
--- invalid JSON, so the raw text tells them apart.
--- @param path string
--- @return any data
--- @return nil|"json"|"empty" error
function RegionMapImport.ReadFile(path)
    local text = dmhub.ReadTextFile(path)
    if text == nil then return nil, "json" end
    if text:gsub("^\239\187\191", ""):match("^%s*$") then return nil, "empty" end
    local data = dmhub.ParseJsonFile(path)
    if data == nil then return nil, "json" end
    return data, nil
end

--- Parse pasted JSON without letting the editor's native cap silently shorten an import.
--- @param text string
--- @return any data
--- @return nil|"json"|"empty"|"tooLong" error
function RegionMapImport.ReadText(text)
    local length = R.TextLength(text)
    if length == math.huge then return nil, "json" end
    if length > C.importTextLimit then return nil, "tooLong" end
    text = text:gsub("^\239\187\191", "")
    if text:match("^%s*$") then return nil, "empty" end
    local ok, parsed = pcall(dmhub.FromJson, text)
    -- FromJson can report success for malformed JSON but return no result.
    if not ok or type(parsed) ~= "table" or parsed.success ~= true or parsed.result == nil then
        return nil, "json"
    end
    return parsed.result, nil
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
function RegionMapImport.GridPositions(count, aspect)
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

-- Create the plan's Locations on a map, a batch at a time: each batch waits
-- for the server, so the undo entry holds only rows that exist. A failed write
-- stops the import; its toast then carries the Undo for what was written.
--
-- With several creates in flight, the engine can confirm a row before it reaches
-- the local table, so a row is only written to again (its description and note)
-- from this loop once Model.GetLocation can read it, never from a callback.
local function Commit(ctx, mapId, plan, aspect, onDone)
    local loose = {} --- @type RegionMapImportEntry[]
    for _, entry in ipairs(plan.entries) do
        if entry.u == nil then loose[#loose + 1] = entry end
    end
    local grid = RegionMapImport.GridPositions(#loose, aspect)
    for i, entry in ipairs(loose) do entry.u, entry.v = grid[i].u, grid[i].v end

    local confirmed = {} --- @type RegionMapUndoStep[]
    local failed = false
    local pending = 0

    local function Done(ok)
        pending = pending - 1
        if not ok then failed = true end
    end
    local callbacks = { success = function() Done(true) end, failure = function() Done(false) end }

    -- Yield until ready() is true; false when the wait ran out or the mod reloaded.
    local function WaitFor(ready)
        local started = dmhub.Time()
        while not ready() do
            if mod.unloaded or dmhub.Time() - started >= C.importWait then return false end
            coroutine.yield(0.05)
        end
        return true
    end

    dmhub.Coroutine(function()
        local first = 1
        while first <= #plan.entries and not failed and not mod.unloaded do
            if Unavailable(mapId) ~= nil then failed = true; break end
            local last = math.min(first + C.importBatch - 1, #plan.entries)
            local created = {} --- @type {id: string, entry: RegionMapImportEntry}[]

            -- 1. Create the batch's Locations and wait for the server's answers.
            pending = 0
            for i = first, last do
                local entry = plan.entries[i]
                local step = nil --- @type nil|RegionMapUndoStep
                local id = nil --- @type nil|string
                pending = pending + 1
                local ok, _, undo, newId = Model.CreateLocation(mapId, entry.u --[[@as number]], entry.v --[[@as number]],
                    entry.style, {
                        success = function()
                            if step ~= nil and id ~= nil then
                                confirmed[#confirmed + 1] = step
                                created[#created + 1] = { id = id, entry = entry }
                            end
                            Done(true)
                        end,
                        failure = function() Done(false) end,
                    }, entry.name)
                id, step = newId, undo and undo.steps[1] or nil
                if not ok then
                    Done(false)
                    break
                end
            end
            if not WaitFor(function() return pending <= 0 end) then failed = true end

            -- 2. Once the rows can be read, save their descriptions and notes.
            if not failed and not WaitFor(function()
                for _, row in ipairs(created) do
                    if Model.GetLocation(row.id) == nil then return false end
                end
                return true
            end) then failed = true end
            if Unavailable(mapId) ~= nil then failed = true end
            if not failed then
                pending = 0
                for _, row in ipairs(created) do
                    if row.entry.description ~= nil then
                        pending = pending + 1
                        if not Model.SaveDetails(row.id, { description = row.entry.description }, callbacks) then Done(false) end
                    end
                    if row.entry.note ~= nil then
                        pending = pending + 1
                        if not Model.SaveDirectorNote(row.id, row.entry.note, callbacks) then Done(false) end
                    end
                end
                if not WaitFor(function() return pending <= 0 end) then failed = true end
            end

            if not mod.unloaded and ctx.IsAlive() then ctx.RefreshAll() end
            first = last + 1
        end
        if mod.unloaded then return end
        local map = Model.GetLocation(mapId)
        local entry = { description = "Import region map locations", steps = confirmed }
        if failed then
            if #confirmed > 0 then ctx.Push(entry, "toast.saveFailed")
            else ctx.Report(false, "unavailable") end
        else
            ctx.Push(entry, "toast.imported", { count = #confirmed, map = Model.DisplayName(map) })
        end
        onDone()
    end)
end

-- Card -------------------------------------------------------------------------------------------

--- @class RegionMapImportPending
--- @field data any parsed source, retained so the preview can be checked again
--- @field plan RegionMapImportPlan
--- @field source "file"|"text"
--- @field aspect number
--- @field imageId string
--- @field imageRevision number
--- @field mapName string

--- @class RegionMapImportState
--- @field mode "closed"|"edit"|"preview"
--- @field generation integer
--- @field mapId nil|string
--- @field mapName string
--- @field text string
--- @field error nil|string copy id
--- @field pending nil|RegionMapImportPending

local function SameLines(a, b)
    if #a ~= #b then return false end
    for i, value in ipairs(a) do if value ~= b[i] then return false end end
    return true
end

--- Build the import card layer.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapImport.Create(ctx)
    local layer
    --- @type TextEditor
    local editor
    local editBody
    local editScroll
    local previewScroll
    local lines
    local target
    local counter
    local errorLabel
    local sourceButtons
    local previewButton
    local okButton
    local backButton

    --- @return RegionMapImportState
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
        SetText(counter, T("import.count", { count = length == math.huge and "?" or length }))
        SetText(errorLabel, errorId ~= nil and T(errorId) or "")
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
        return gui.Label { classes = classes or { "regionMapImportLine" }, text = text, interactable = false }
    end

    local function ShowRows(rows)
        lines.children = rows
        local generation = State().generation
        previewScroll.vscrollPosition = 1
        dmhub.Schedule(C.afterLayoutDelay, function()
            if Alive() and State().generation == generation then previewScroll.vscrollPosition = 1 end
        end)
        RefreshControls()
        Session.FocusSoon(State().pending ~= nil and okButton or backButton,
            function() return Alive() and State().generation == generation end)
        ctx.RefreshAll()
    end

    local function Reasons(rows, reasons)
        for _, reason in ipairs(reasons) do rows[#rows + 1] = Line(reason, { "regionMapImportLine", "item" }) end
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
        local plan = RegionMapImport.Check(data, map.id)
        if readError == "empty" or plan.error == "empty" then
            ShowRows({ Line(T(errorPrefix .. "empty")) })
            return
        end
        if plan.error == "allSkipped" then
            local rows = { Line(T(errorPrefix .. "allSkipped")) }
            Reasons(rows, plan.skipped)
            ShowRows(rows)
            return
        end
        local count = #plan.entries
        local rows = { Line(T("import.summary", { count = count, map = Model.DisplayName(map) }), { "regionMapImportLine", "lead" }) }
        if #plan.skipped > 0 then
            rows[#rows + 1] = Line(T("import.skipped", { count = #plan.skipped }), { "regionMapImportLine", "heading" })
            Reasons(rows, plan.skipped)
        end
        if #plan.duplicates > 0 then
            rows[#rows + 1] = Line(T("import.duplicates", { count = #plan.duplicates }), { "regionMapImportLine", "heading" })
            local names = {} --- @type string[]
            for _, name in ipairs(plan.duplicates) do names[#names + 1] = Copy.Literal(name) end
            Reasons(rows, names)
        end
        rows[#rows + 1] = Line(T("import.placement"), { "regionMapImportLine", "note" })
        local job = {
            data = data, plan = plan, source = source, aspect = 1.5,
            imageId = map.imageId, imageRevision = map.imageRevision, mapName = Model.DisplayName(map),
        }
        state.pending = job
        local generation = state.generation
        RegionMapCanvasTools.ImageSize(map.imageId, function(width, height)
            if Alive() and State().generation == generation and State().pending == job and height > 0 then
                job.aspect = width / height
            end
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
        local fresh = RegionMapImport.Check(job.data, map.id)
        if job.mapName ~= Model.DisplayName(map) or job.imageId ~= map.imageId or job.imageRevision ~= map.imageRevision
            or fresh.error ~= job.plan.error or #fresh.entries ~= #job.plan.entries
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
        local data, readError = RegionMapImport.ReadFile(path)
        if readError ~= nil or RegionMapImport.Check(data, mapId).error ~= nil then
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
            id = "RegionMapImport", extensions = { "json" }, multiFiles = false, prompt = T("import.picker"),
            open = function(path)
                if Alive() and State().generation == generation and State().mode == "edit" then OpenFile(path, mapId) end
            end,
        }
    end

    editor = Session.TextArea(C.importEditorLimit, {
        id = "region-map-import-text",
        classes = { "input", "bordered", "sizeS", "monospace", "regionMapTextArea", "regionMapImportEditor" },
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
    target = Line("", { "regionMapImportLine", "regionMapImportTarget" })
    counter = Line("", { "regionMapImportLine", "regionMapImportCounter" })
    errorLabel = Line("", { "regionMapImportLine", "regionMapImportError", "collapsed" })
    errorLabel.id = "region-map-import-error"
    local contract = T("import.contract", nil, true)
    local help = {
        gui.Panel {
            classes = { "regionMapImportActions" },
            gui.Label {
                classes = { "regionMapImportLine", "heading" }, text = T("import.help"),
                width = "auto", tmargin = 0, rmargin = 8, valign = "center", interactable = false,
            },
            gui.Button {
                id = "region-map-import-copy-contract", classes = { "regionMapButton", "sizeS" },
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
        gui.Panel {
            id = "region-map-import-contract-scroll", classes = { "bordered", "bg", "regionMapImportContract" },
            bgimage = true, borderBox = true, vscroll = true, hscroll = true,
            gui.Label {
                id = "region-map-import-contract", classes = { "monospace", "regionMapImportContractText" },
                text = contract, interactable = false,
            },
        },
    }
    editBody = gui.Panel {
        classes = { "regionMapImportEditBody" },
        gui.Panel {
            classes = { "regionMapImportColumns" },
            gui.Panel {
                classes = { "regionMapImportEditColumn" },
                Line(T("import.paste"), { "regionMapImportLine", "heading" }), editor, counter,
                Line(T("import.draftHint"), { "regionMapImportLine", "note" }),
            },
            gui.Panel { classes = { "regionMapImportHelpColumn" }, children = help },
        },
    }
    editScroll = gui.Panel {
        id = "region-map-import-edit-scroll", classes = { "regionMapImportScroll" }, vscroll = true, editBody,
    }
    lines = gui.Panel { classes = { "regionMapImportLines" } }
    previewScroll = gui.Panel { classes = { "regionMapImportScroll", "collapsed" }, vscroll = true, lines }
    sourceButtons = gui.Panel {
        classes = { "regionMapImportActions" },
        gui.Button {
            id = "region-map-import-file", classes = { "regionMapButton", "sizeS" }, text = T("import.file"),
            click = ChooseFile,
        },
        gui.Button {
            id = "region-map-import-example", classes = { "regionMapButton", "sizeS" }, text = T("import.fill"),
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
        id = "region-map-import-preview", classes = { "regionMapButton", "sizeS" }, text = T("import.preview"),
        click = function()
            if not Alive() then return end
            SyncInput()
            local data, readError = RegionMapImport.ReadText(editor.text)
            Preview(data, "text", readError)
        end,
    }
    okButton = gui.Button {
        id = "region-map-import-ok", classes = { "regionMapButton", "sizeS" }, text = "",
        click = Import,
    }
    backButton = gui.Button {
        id = "region-map-import-back", classes = { "regionMapButton", "sizeS" }, text = T("import.back"),
        click = function() if Alive() then ShowEditor(nil) end end,
    }
    layer = gui.Panel {
        id = "region-map-import", classes = { "regionMapConfirmLayer", "collapsed" }, floating = true,
        swallowPress = true,
        data = { mode = "closed", generation = 0, text = "", mapName = "" },
        bind = function()
            if not Alive() or State().mode == "closed" then return end
            local reason = Unavailable(State().mapId)
            if reason ~= nil and State().mode == "preview" then ShowEditor("import." .. reason)
            else RefreshControls() end
        end,
        gui.Panel {
            id = "region-map-import-card",
            classes = { "regionMapConfirm", "regionMapImportCard" },
            rendered = function(element, width)
                local narrow = width < C.importNarrowWidth
                if element.data.narrow ~= narrow then
                    element.data.narrow = narrow
                    element:SetClassTree("importNarrow", narrow)
                end
            end,
            gui.Label { classes = { "regionMapConfirmTitle" }, text = T("import.title"), interactable = false },
            target, editScroll, previewScroll, errorLabel,
            gui.Panel {
                classes = { "regionMapImportActions", "footer" }, previewButton, backButton, okButton,
                gui.Button {
                    id = "region-map-import-cancel", classes = { "regionMapButton", "sizeS" }, text = T("dlg.cancel"),
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
