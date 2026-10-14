local mod = dmhub.GetModLoading()

--- The session log panel at the right edge of the window (V2-15), in the
--- side panel's place: entries grouped under date headings, newest first;
--- the Director can annotate and delete entries. Add note, Undo last change
--- and the Show route switch sit below the title, above the entries.
---
--- Events on the returned panel:
---   bind()   redraw when ctx.data.panelMode is "log"
--- @class RegionMapLogPanel: GameType
--- @field new fun(o?: table): RegionMapLogPanel
RegionMapLogPanel = RegisterGameType("RegionMapLogPanel")
local C = RegionMapConstants
local Model = RegionMapModel
local Session = RegionMapSession
local Copy = RegionMapCopy
local Log = RegionMapLog
local Undo = RegionMapUndo

local T = Copy.T
local Label, Button = Session.Label, Session.Button

-- The local calendar day of a server time, as a comparable key and a date table.
local function Day(ms)
    local date = os.date("*t", math.floor(ms / 1000)) --[[@as osdate]]
    return date.year * 10000 + date.month * 100 + date.day, date
end

-- "Today", "Yesterday" or "September 28" (manifest log.day.*).
local function DayHeading(ms)
    local key, date = Day(ms)
    local today = Day(dmhub.serverTimeMilliseconds)
    local yesterday = Day(dmhub.serverTimeMilliseconds - 24 * 3600 * 1000)
    if key == today then return T("log.day.today") end
    if key == yesterday then return T("log.day.yesterday") end
    return T("log.day.date", { month = Copy.months[date.month] or "", day = date.day })
end

-- The entry's main line (manifest log.arrived etc.).
local function EntryText(entry)
    local NameOf = Model.NameOf
    if entry.kind == "leg" or entry.kind == "stopped" then
        -- Players get no path name on a secret leg or a path hidden from them (W1).
        local pathName = Log.ShowsPath(entry) and entry.pathName or ""
        if entry.kind == "leg" then
            return T(Log.LegCopy(entry.rest, NameOf(entry.fromId), NameOf(entry.toId), pathName, entry.time, "log.leg"))
        end
        local args = { path = pathName, time = RegionMapPaths.FormatTime(entry.spent), name = NameOf(entry.fromId) }
        return T(pathName ~= "" and "log.stopped" or "log.stopped.noPath", args)
    end
    if entry.kind == "arrived" then return T("log.arrived", { name = NameOf(entry.locationId) }) end
    if entry.kind == "traveling" then return T("log.traveling", { name = NameOf(entry.locationId) }) end
    if entry.kind == "placed" then return T("log.placed", { map = NameOf(entry.mapId) }) end
    return T("log.travelingOn", { map = NameOf(entry.mapId) })
end

--- Build the session log panel.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapLogPanel.Create(ctx)
    local data = ctx.data
    local panel
    local list
    local empty
    local addNoteButton
    local undoButton
    local routeCheck = nil --- @type nil|Panel built on first open (EnsureRouteCheck)
    local editingId = nil --- @type nil|string the entry whose note editor is open
    local draft = nil --- @type nil|string the editor's text, saved when the editor closes
    local signature = nil --- @type nil|string what the list was last built from

    local function Refresh()
        signature = nil
        ctx.RefreshAll()
    end

    -- Saves the open note (if any) and closes its editor. Runs when the editor
    -- loses focus, on Esc, when another note opens and when the panel closes,
    -- so typed text is never dropped.
    local function CloseEditor()
        local id, text = editingId, draft
        editingId, draft = nil, nil
        panel.data.editing = false
        if id ~= nil and text ~= nil then
            local ok, reason, entry = Log.SetNote(id, text)
            if ctx.Report(ok, reason) then Undo.Remember(entry) end
        end
        Refresh()
    end

    local function OpenEditor(id)
        if editingId ~= nil then CloseEditor() end
        local entry = Log.Get(id)
        if entry == nil then return end
        editingId, draft = id, entry.note
        panel.data.editing = true
        Refresh()
    end

    local function EntryMenu(element, entry)
        local entries = {
            { text = T(entry.note == "" and "log.addNote" or "log.editNote"), click = function() OpenEditor(entry.id) end },
            {
                text = T("log.deleteEntry"),
                click = function()
                    local ok, reason, undo = Log.DeleteEntry(entry.id)
                    if ctx.Report(ok, reason) then Undo.Remember(undo) end
                    Refresh()
                end,
            },
        }
        for _, item in ipairs(entries) do
            local action = item.click
            item.click = function()
                element.popup = nil
                action()
            end
        end
        element.popupsInheritStyles = false
        element.tooltip = nil
        element.popup = Session.ContextMenu(element, { entries = entries })
    end

    local function NoteEditor(entry)
        local editor
        editor = Session.TextArea(C.noteLimit, {
            -- The list is rebuilt when any Region Map row changes (another client moving the
            -- Party), so a rebuilt editor starts from the typed text, not the saved note.
            text = (editingId == entry.id and draft) or entry.note,
            edit = function(element)
                if editingId == entry.id then draft = element.text end
            end,
            change = function(element)
                if editingId ~= entry.id then return end
                draft = element.text
                CloseEditor()
            end,
            create = function(element)
                dmhub.Schedule(C.afterLayoutDelay, function()
                    if mod.unloaded or not element.valid then return end
                    gui.SetFocus(element)
                    -- The caret goes after the existing note, so typing adds to it.
                    local text = element.text or ""
                    element:SetTextAndCaret(#text, text)
                end)
            end,
        })
        return editor
    end

    -- Who logged the entry and when, under its main line.
    local function MetaText(entry)
        local who = entry.byDirector and T("log.by.director") or entry.byName
        local time = os.date("%H:%M", math.floor(Log.Time(entry) / 1000)) --[[@as string]]
        local meta = T("log.by", { who = who }) .. " - " .. time
        if entry.mergedCount > 0 then meta = meta .. " - " .. T("log.merged", { count = entry.mergedCount }) end
        return meta
    end

    local function EntryRow(entry, text, meta, director)
        local children = {
            gui.Panel {
                classes = { "regionMapSideRow" },
                gui.Label {
                    classes = { "regionMapLogText" }, text = text,
                    -- Clicking an entry opens the map it happened on.
                    click = function()
                        if data.mapId ~= entry.mapId then ctx.OpenMap(entry.mapId, "restore") end
                    end,
                },
                director and Session.IconButton("region-map-log-more", C.iconMore, T("panel.more"), function(element)
                    EntryMenu(element, entry)
                end) or nil,
            },
            Label({ "regionMapMeta" }, meta),
        }
        if editingId == entry.id then
            children[#children + 1] = NoteEditor(entry)
        elseif entry.note ~= "" then
            children[#children + 1] = Label({ "regionMapLogNote" }, Copy.Literal(entry.note))
        end
        return gui.Panel { classes = { "regionMapLogEntry" }, children = children }
    end

    -- Rows are kept by entry id and built again only when what they show changed,
    -- so a new entry or an edited note costs one row, not the whole list (up to logCap).
    local rows = {} --- @type table<string, {panel: Panel, key: string}>
    local dayRows = {} --- @type table<integer, Panel>

    -- Builds at most logRowsPerFrame new rows, so opening a long log never freezes
    -- one frame; the list stops at the first row not built yet and the rest follow
    -- on the next frames, newest first.
    local function BuildList(entries)
        local director = Model.IsDirector()
        local children = {} --- @type Panel[]
        local keptRows, keptDays = {}, {} --- @type table<string, {panel: Panel, key: string}>, table<integer, Panel>
        local budget = C.logRowsPerFrame
        local lastDay = nil
        local complete = true
        for _, entry in ipairs(entries) do
            local text, meta = EntryText(entry), MetaText(entry)
            local key = table.concat({ text, meta, entry.note, tostring(editingId == entry.id), tostring(director) }, "\n")
            local row = rows[entry.id]
            if row == nil or row.key ~= key or not row.panel.valid then
                if budget <= 0 then
                    complete = false
                    break
                end
                budget = budget - 1
                row = { panel = EntryRow(entry, text, meta, director), key = key }
            end
            local ms = Log.Time(entry)
            local day = Day(ms)
            if day ~= lastDay then
                lastDay = day
                local heading = DayHeading(ms)
                local dayRow = dayRows[day]
                if dayRow == nil or not dayRow.valid then
                    dayRow = Label({ "regionMapLogDay" }, heading)
                elseif dayRow.text ~= heading then
                    dayRow.text = heading
                end
                keptDays[day] = dayRow
                children[#children + 1] = dayRow
            end
            keptRows[entry.id] = row
            children[#children + 1] = row.panel
        end
        -- Panels left out of the list are destroyed by the engine; only the kept ones stay.
        rows, dayRows = keptRows, keptDays
        list.children = children
        if not complete then panel:ScheduleEvent("buildMore", 0.01) end
        return complete
    end

    list = gui.Panel { width = "100%", height = "auto", flow = "vertical" }
    empty = Label({ "regionMapHint", "collapsed" }, T("log.empty"))
    addNoteButton = Button(T("log.addNote"), function()
        local newest = Log.Entries()[1]
        if newest ~= nil then OpenEditor(newest.id) end
    end)
    undoButton = Button(T("log.undoLast"), function()
        Undo.UndoLast(function() if ctx.IsAlive() then Refresh() end end)
    end)
    -- A checkbox costs ~9 ms to build, so Show route is built the first time the log opens.
    local routeSlot = gui.Panel { width = "100%", height = "auto", flow = "vertical" }
    local function EnsureRouteCheck()
        if routeCheck ~= nil then return end
        routeCheck = gui.Check {
            classes = { "regionMapCheck" }, text = T("log.showRoute"), value = Session.ShowRoute(), fontSize = 14,
            change = function(element)
                Session.SetShowRoute(element.value == true)
                ctx.RefreshAll()
            end,
        }
        routeSlot.children = { routeCheck }
    end

    local function Bind()
        local open = data.panelMode == "log"
        panel:SetClass("collapsed", not open)
        if not open then
            if editingId ~= nil then
                -- Closing the panel saves a note being typed (CloseEditor refreshes again, now with no editor).
                CloseEditor()
            end
            signature = nil
            return
        end
        local rootWidth = ctx.root.renderedWidth or 0
        local width = C.sidePanelWidth * Session.UIScale()
        if rootWidth > 0 and rootWidth < C.narrowWidth then width = rootWidth end
        if panel.data.width ~= width then
            panel.data.width = width
            panel.selfStyle.width = width
        end
        local entries = Log.Entries()
        -- Rebuilding hundreds of rows on every refresh is wasteful; rebuild only when something shown changed.
        local key = table.concat({
            tostring(Model.Revision()), tostring(#entries),
            tostring(editingId), tostring(Model.IsDirector()), tostring(DayHeading(dmhub.serverTimeMilliseconds)),
        }, ":")
        if key ~= signature then
            signature = key
            BuildList(entries)
        end
        empty:SetClass("collapsed", #entries > 0)
        addNoteButton:SetClass("collapsed", not Model.IsDirector() or #entries == 0)
        undoButton:SetClass("disabled", not Undo.HasUndo())
        EnsureRouteCheck()
        local check = routeCheck --[[@as Panel]]
        local showRoute = Session.ShowRoute()
        if check.value ~= showRoute then check.value = showRoute end
    end

    panel = gui.Panel {
        id = "region-map-log-panel",
        classes = { "regionMapSide", "collapsed" },
        floating = true,
        width = C.sidePanelWidth,
        popupsInheritStyles = true,
        data = { width = nil, editing = false },
        bind = function() Bind() end,
        -- The next rows of a long list (see BuildList).
        buildMore = function()
            if mod.unloaded or data.panelMode ~= "log" then return end
            BuildList(Log.Entries())
        end,
        -- Esc while a note is open saves it and closes only the editor (R2).
        closeEditor = function() if editingId ~= nil then CloseEditor() end end,
        gui.Panel {
            classes = { "regionMapSideScroll" }, vscroll = true,
            gui.Panel {
                classes = { "regionMapSideBody" },
                gui.Panel {
                    classes = { "regionMapSideHeader" },
                    gui.Label { classes = { "regionMapSideTitle", "noIcon" }, text = T("log.title") },
                    Session.IconButton("region-map-log-close", C.iconClose, T("panel.close"), function()
                        ctx.ToggleLog()
                    end),
                },
                gui.Panel { classes = { "regionMapButtonRow" }, addNoteButton, undoButton },
                routeSlot,
                gui.Panel { classes = { "regionMapRule" }, interactable = false },
                empty,
                list,
            },
        },
    }
    return panel
end
