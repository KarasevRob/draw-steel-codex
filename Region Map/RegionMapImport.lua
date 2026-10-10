local mod = dmhub.GetModLoading()

--- JSON import of Locations into the open map (V2.1 idea 9, brief IM1-IM7).
--- Director only. ctx.ImportLocations asks for a file, checks every entry and
--- shows a preview card; Import then creates the Locations in batches as one
--- undo entry. The file format is in docs/IMPORT_FORMAT.md.
---
--- Create(ctx) returns the card layer for the shell. Its data holds:
---   start()                 open the file dialog (does nothing while an import is running)
---   openFile(path, mapId)   check a file and show its preview card (what the dialog calls)
---   close()                 close the card
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
    if not R.ValidText(name) then return nil, T("import.skip.name", { n = index }) end

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
            ctx.Push(entry, "toast.saveFailed")
        else
            ctx.Push(entry, "toast.imported", { count = #confirmed, map = Model.DisplayName(map) })
        end
        onDone()
    end)
end

-- Card -------------------------------------------------------------------------------------------

--- Build the import card layer.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapImport.Create(ctx)
    local layer
    local title
    local scroll
    local lines
    local okButton
    local cancelButton
    -- The file being previewed; a Location count change while the card is open is checked again on Import.
    local pending = nil --- @type nil|{mapId: string, plan: RegionMapImportPlan, aspect: number}
    local running = false

    local function Close()
        pending = nil
        layer:SetClass("collapsed", true)
        ctx.RefreshAll()
    end

    local function Line(text, classes)
        return gui.Label { classes = classes or { "regionMapImportLine" }, text = text, interactable = false }
    end

    -- Show the card. okText nil means a card with only Close.
    local function Show(rows, okText)
        SetText(title, T("import.title"))
        lines.children = rows
        okButton:SetClass("collapsed", okText == nil)
        if okText ~= nil then SetText(okButton, okText) end
        SetText(cancelButton, okText == nil and T("dlg.close") or T("dlg.cancel"))
        -- The list scrolls inside the card, which never grows past the window.
        local height = ctx.root.renderedHeight or 0
        if height > 0 then scroll.selfStyle.maxHeight = math.max(120, height - 220) end
        layer:SetClass("collapsed", false)
        -- Start at the top (1 = top); again once the new lines have laid out.
        scroll.vscrollPosition = 1
        dmhub.Schedule(C.afterLayoutDelay, function()
            if not mod.unloaded and scroll.valid then scroll.vscrollPosition = 1 end
        end)
        ctx.RefreshAll()
    end

    local function Reasons(rows, reasons)
        for _, reason in ipairs(reasons) do rows[#rows + 1] = Line(reason, { "regionMapImportLine", "item" }) end
    end

    local function Preview(mapId, data, readError)
        local map = Model.GetLocation(mapId)
        if map == nil or not ctx.IsAlive() then return end
        if readError == "json" then
            Show({ Line(T("import.error.json")) }, nil)
            return
        end
        local plan = RegionMapImport.Check(data, mapId)
        if readError == "empty" or plan.error == "empty" then
            Show({ Line(T("import.error.empty")) }, nil)
            return
        end
        if plan.error == "allSkipped" then
            local rows = { Line(T("import.error.allSkipped")) }
            Reasons(rows, plan.skipped)
            Show(rows, nil)
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
        -- The grid needs the image's shape; until the engine reports it, assume 3:2.
        pending = { mapId = mapId, plan = plan, aspect = 1.5 }
        RegionMapCanvasTools.ImageSize(map.imageId, function(width, height)
            if pending ~= nil and pending.mapId == mapId then pending.aspect = width / height end
        end)
        Show(rows, T("import.ok", { count = count }))
    end

    local function Import()
        local job = pending
        if job == nil or running then return end
        if Model.GetLocation(job.mapId) == nil then
            Close()
            return
        end
        Close()
        running = true
        Commit(ctx, job.mapId, job.plan, job.aspect, function() running = false end)
    end

    title = gui.Label { classes = { "regionMapConfirmTitle" }, text = "", interactable = false }
    lines = gui.Panel { classes = { "regionMapImportLines" } }
    scroll = gui.Panel { classes = { "regionMapImportScroll" }, vscroll = true, lines }
    okButton = gui.Button {
        id = "region-map-import-ok", classes = { "regionMapButton", "sizeS" }, text = "",
        click = function() if not mod.unloaded then Import() end end,
    }
    cancelButton = gui.Button {
        id = "region-map-import-cancel", classes = { "regionMapButton", "sizeS" }, text = "",
        click = function() if not mod.unloaded then Close() end end,
    }
    layer = gui.Panel {
        id = "region-map-import", classes = { "regionMapConfirmLayer", "collapsed" }, floating = true,
        swallowPress = true, data = {},
        gui.Panel {
            classes = { "regionMapConfirm", "regionMapImportCard" },
            title,
            scroll,
            gui.Panel { classes = { "regionMapConfirmButtons" }, okButton, cancelButton },
        },
    }

    -- Check a chosen file against the map that was open when the import began.
    -- The file dialog calls this; tests call it with a path directly.
    layer.data.openFile = function(path, mapId)
        if mod.unloaded or not ctx.IsAlive() or running or not Model.IsDirector() then return end
        local data, readError = RegionMapImport.ReadFile(path)
        Preview(mapId, data, readError)
    end

    layer.data.start = function()
        local map = ctx.CurrentMap()
        if running or map == nil or not Model.IsDirector() then return end
        local mapId = map.id
        dmhub.OpenFileDialog {
            id = "RegionMapImport",
            extensions = { "json" },
            multiFiles = false,
            prompt = T("import.picker"),
            open = function(path) layer.data.openFile(path, mapId) end,
        }
    end
    layer.data.close = Close
    return layer
end
