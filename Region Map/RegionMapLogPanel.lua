local mod = dmhub.GetModLoading()

--- The session log panel at the right edge of the window (V2-15), in the
--- side panel's place: entries grouped under date headings, newest first;
--- the Director can annotate and delete entries. The footer has Add note,
--- Undo last change and the Show route switch.
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

local function Label(classes, text)
    return gui.Label { classes = classes, text = text or "", interactable = false }
end

local function Button(text, action)
    return gui.Button {
        classes = { "regionMapButton", "sizeS" }, text = text,
        click = function(element)
            if not mod.unloaded and not element:HasClass("disabled") then action() end
        end,
    }
end

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

--- One leg's line, in the one wording every place uses (Q19). The rest of a
--- path ("on") and turning back ("back") name only where the Party went.
--- @param rest ""|"on"|"back"
--- @param from string plain name
--- @param to string plain name
--- @param pathName string plain name; "" drops "by ..." (manifest 25.2)
--- @param watches number
--- @return string
function RegionMapLogPanel.LegText(rest, from, to, pathName, watches)
    local by = pathName ~= "" and T("leg.by", { path = pathName }, true) or ""
    local args = { from = from, to = to, by = by, time = RegionMapPaths.FormatTime(watches) }
    if rest == "on" then return T("log.leg.on", args) end
    if rest == "back" then return T("log.leg.back", args) end
    return T("log.leg", args)
end

-- The entry's main line (manifest log.arrived etc.).
local function EntryText(entry)
    local function NameOf(id)
        local location = Model.GetLocation(id)
        return location ~= nil and Model.DisplayName(location) or ""
    end
    if entry.kind == "leg" or entry.kind == "stopped" then
        -- Players get no path name on a secret leg or a path hidden from them (W1).
        local pathName = Log.ShowsPath(entry) and entry.pathName or ""
        if entry.kind == "leg" then
            return RegionMapLogPanel.LegText(entry.rest, NameOf(entry.fromId), NameOf(entry.toId), pathName, entry.time)
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
    local routeCheck
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
        element.popup = gui.ContextMenu { entries = entries }
    end

    local function NoteEditor(entry)
        local editor
        editor = gui.TextEditor {
            classes = { "input", "bordered", "sizeS", "regionMapTextArea" }, borderBox = true,
            characterLimit = C.noteLimit, multiline = true, verticalScrollbar = true, editlag = 0,
            selectAllOnFocus = false, resetOnDeActivation = false, textAlignment = "topleft",
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
                dmhub.Schedule(0.05, function()
                    if mod.unloaded or not element.valid then return end
                    gui.SetFocus(element)
                    -- The caret goes after the existing note, so typing adds to it.
                    local text = element.text or ""
                    element:SetTextAndCaret(#text, text)
                end)
            end,
        }
        return editor
    end

    local function EntryRow(entry)
        local director = Model.IsDirector()
        local who = entry.byDirector and T("log.by.director") or entry.byName
        local time = os.date("%H:%M", math.floor(Log.Time(entry) / 1000)) --[[@as string]]
        local meta = T("log.by", { who = who }) .. " - " .. time
        if entry.mergedCount > 0 then meta = meta .. " - " .. T("log.merged", { count = entry.mergedCount }) end
        local children = {
            gui.Panel {
                classes = { "regionMapSideRow" },
                gui.Label {
                    classes = { "regionMapLogText" }, text = EntryText(entry),
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

    local function BuildList(entries)
        local rows = {} --- @type Panel[]
        local lastDay = nil
        for _, entry in ipairs(entries) do
            local ms = Log.Time(entry)
            local day = Day(ms)
            if day ~= lastDay then
                lastDay = day
                rows[#rows + 1] = Label({ "regionMapLogDay" }, DayHeading(ms))
            end
            rows[#rows + 1] = EntryRow(entry)
        end
        list.children = rows
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
    routeCheck = gui.Check {
        classes = { "regionMapCheck" }, text = T("log.showRoute"), value = Session.ShowRoute(), fontSize = 14,
        change = function(element)
            Session.SetShowRoute(element.value == true)
            ctx.RefreshAll()
        end,
    }

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
            tostring(dmhub.ngameupdate), tostring(dmhub.tablesUpdateId), tostring(#entries),
            tostring(editingId), tostring(Model.IsDirector()), tostring(DayHeading(dmhub.serverTimeMilliseconds)),
        }, ":")
        if key ~= signature then
            signature = key
            BuildList(entries)
        end
        empty:SetClass("collapsed", #entries > 0)
        addNoteButton:SetClass("collapsed", not Model.IsDirector() or #entries == 0)
        undoButton:SetClass("disabled", not Undo.HasUndo())
        routeCheck.value = Session.ShowRoute()
    end

    panel = gui.Panel {
        id = "region-map-log-panel",
        classes = { "regionMapSide", "collapsed" },
        floating = true,
        width = C.sidePanelWidth,
        popupsInheritStyles = true,
        data = { width = nil, editing = false },
        bind = function() Bind() end,
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
                empty,
                list,
                gui.Panel { classes = { "regionMapRule" }, interactable = false },
                gui.Panel { classes = { "regionMapButtonRow" }, addNoteButton, undoButton },
                routeCheck,
            },
        },
    }
    return panel
end
