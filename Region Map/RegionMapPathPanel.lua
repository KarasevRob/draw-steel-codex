local mod = dmhub.GetModLoading()

--- The path panel at the right edge of the window (V21-10, V21-12, V21-13):
--- what a selected point crawl path is, between which Locations, how long it
--- takes each way and its description. The Director also gets the hide/reveal
--- eye, the danger or requirement note (H5: players never see it), the "..."
--- menu, the edit form with autosave and the Connect to... picker.
--- It uses the side panel's look and place; the shell shows one or the other.
---
--- Events on the returned panel:
---   bind()    redraw for ctx.data.panelMode "path", "pathEdit" or "pickPathEnd"
---   flush()   save pending typed text now (before any navigation)
--- @class RegionMapPathPanel: GameType
--- @field new fun(o?: table): RegionMapPathPanel
RegionMapPathPanel = RegisterGameType("RegionMapPathPanel")
local C = RegionMapConstants
local Model = RegionMapModel
local Paths = RegionMapPaths
local Session = RegionMapSession
local Copy = RegionMapCopy

local SetText = Session.SetText
local T = Copy.T
local Label, Button, Segments = Session.Label, Session.Button, Session.Segments

local function SetVisibility(ctx, path, visibility)
    local ok, reason, entry = Paths.SetVisibility(path.id, visibility)
    if ctx.Report(ok, reason) then
        ctx.Push(entry, visibility == "hidden" and "toast.hid" or "toast.revealed", { name = Paths.Title(path, true) })
        ctx.RefreshAll()
    end
end

local TimeInputText, ParseTime = Paths.TimeInputText, Paths.ParseTime

--- Whether a Location can be joined to another by Connect to... now: the
--- Director, a pin on the open point crawl map, with another pin beside it (E1).
--- @param ctx RegionMapContext
--- @param location RegionMapLocationRecord
--- @return boolean
function RegionMapPathPanel.CanConnect(ctx, location)
    if not Model.IsDirector() or location.parentId == "" or location.parentId ~= ctx.data.mapId then return false end
    local map = Model.GetLocation(location.parentId)
    return map ~= nil and Model.IsPointCrawl(map) and #Model.Children(map.id) >= 2
end

--- The "..." and right-click menu of a path: Director only (H3). Redraw line
--- joins it with the Path tool (V21-14).
--- @param ctx RegionMapContext
--- @param id string
--- @return table[] gui.ContextMenu entries
function RegionMapPathPanel.MenuEntries(ctx, id)
    local path = Paths.Get(id)
    local entries = {}
    if path == nil or not Model.IsDirector() then return entries end
    local function Add(copyId, action) entries[#entries + 1] = { text = T(copyId), click = action } end
    -- Stopping the Party partway goes first: it is the in-play action (G3, Q4).
    if path.mapId == ctx.data.mapId and RegionMapTravel.CanStopOn(path) then
        entries[#entries + 1] = {
            text = T("ctx.path.place", { path = Paths.ShownName(path) }), click = function() ctx.StopOnPath(path.id) end,
        }
    end
    if path.mapId == ctx.data.mapId then
        Add("menu.redraw", function() RegionMapPathTool.StartRedraw(ctx, path.id) end)
    end
    if path.visibility == "hidden" then
        Add("menu.reveal", function() SetVisibility(ctx, path, "revealed") end)
    else
        Add("menu.hide", function() SetVisibility(ctx, path, "hidden") end)
    end
    -- Deleting removes nothing else, so it needs no confirm; the toast has Undo (E3).
    Add("menu.delete", function()
        local title = Paths.Title(path, true)
        local ok, reason, entry = Paths.DeletePath(path.id)
        if ctx.Report(ok, reason) then
            if ctx.data.selectedPathId == path.id then ctx.SelectPath(nil) end
            ctx.Push(entry, "toast.pathDeleted", { path = title })
            ctx.RefreshAll()
        end
    end)
    return entries
end

-- Paths section of a Location (Q10) -------------------------------------------------------------------

-- The time a path takes leaving from one of its ends (W2).
local function TimeFrom(path, locationId)
    if path.aId == locationId or path.back == "same" then return Paths.FormatTime(path.time) end
    if path.back == "different" then return Paths.FormatTime(path.backTime) end
    -- Raw: the row's own copy escapes it once as an argument.
    local a, b = Paths.Ends(path)
    return T("path.time.oneWay", {
        time = Paths.FormatTime(path.time),
        a = Model.DisplayName(a), b = Model.DisplayName(b),
    }, true)
end

--- The Paths section in a pin's read view on a point crawl map: one row per
--- path the viewer sees, and Connect to... for the Director. Clicking a row
--- opens that path.
--- @param ctx RegionMapContext
--- @return Panel section; section.data.bind(location) redraws it
function RegionMapPathPanel.PathsSection(ctx)
    local rows = gui.Panel { width = "100%", height = "auto", flow = "vertical", tmargin = 4 }
    local none = Label({ "regionMapHint" }, T("panel.paths.none"))
    local connect = Button(T("menu.connect"), function()
        if ctx.data.selectedId ~= nil then ctx.Select(ctx.data.selectedId, "pickPathEnd") end
    end)
    local connectRow = gui.Panel { classes = { "regionMapButtonRow" }, connect }
    local section = gui.Panel {
        width = "100%", height = "auto", flow = "vertical", data = { signature = nil },
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
        Label({ "regionMapSectionLabel" }, T("panel.paths")),
        none,
        rows,
        connectRow,
    }

    local function Row(id, text, hidden)
        local children = { Label({ "regionMapRowName", "regionMapPathRowName" }, text) } --- @type Panel[]
        if hidden then
            children[#children + 1] = gui.Panel { classes = { "regionMapPathRowEye" }, bgimage = C.iconEyeSlash, interactable = false }
        end
        return gui.Panel {
            classes = { "regionMapRow", "regionMapPathRow" },
            click = function() if not mod.unloaded then ctx.SelectPath(id) end end,
            children = children,
        }
    end

    section.data.bind = function(location)
        local map = location.parentId ~= "" and Model.GetLocation(location.parentId) or nil
        local shown = map ~= nil and Model.IsPointCrawl(map)
        section:SetClass("collapsed", not shown)
        if not shown then return end
        connectRow:SetClass("collapsed", not RegionMapPathPanel.CanConnect(ctx, location))
        local items = {} --- @type {id: string, dest: string, text: string, hidden: boolean}[]
        for _, path in ipairs(Paths.PathsOf(location.id)) do
            local other = Model.GetLocation(Paths.OtherEnd(path, location.id))
            if other ~= nil then
                local name = Paths.ShownName(path)
                local dest = Model.DisplayName(other)
                items[#items + 1] = {
                    id = path.id, dest = dest, hidden = path.visibility == "hidden",
                    text = T("panel.paths.row", { dest = dest, path = name, time = TimeFrom(path, location.id) }),
                }
            end
        end
        table.sort(items, function(x, y)
            if x.dest ~= y.dest then return x.dest < y.dest end
            return x.id < y.id
        end)
        none:SetClass("collapsed", #items > 0)
        -- Rebuilt only when a row changed, so a refresh does not relayout the list.
        local parts = {}
        for _, item in ipairs(items) do parts[#parts + 1] = item.id .. "|" .. item.text .. "|" .. tostring(item.hidden) end
        local signature = table.concat(parts, "\n")
        if section.data.signature == signature then return end
        section.data.signature = signature
        local children = {} --- @type Panel[]
        for _, item in ipairs(items) do children[#children + 1] = Row(item.id, item.text, item.hidden) end
        rows.children = children
    end
    return section
end

-- The panel ------------------------------------------------------------------------------------------

--- Build the path panel.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapPathPanel.Create(ctx)
    local data = ctx.data
    local panel
    local readView
    local editView
    local pickView

    local function Current()
        return Paths.Get(data.selectedPathId)
    end

    -- Autosave (the side panel's pattern) ---------------------------------------------------------

    -- Typed values waiting to be saved, per path id: { name?, description?, note?, time?, backTime? }.
    local pending = {} --- @type table<string, table<string, string|number>>
    local failed = {} --- @type table<string, boolean>
    -- Time fields holding a number that is no valid time; shown, never sent.
    local badTime = {} --- @type table<string, boolean>
    local saveToken = 0

    local Flush

    local function ScheduleSave(delay)
        saveToken = saveToken + 1
        local token = saveToken
        dmhub.Schedule(delay, function()
            if mod.unloaded or token ~= saveToken then return end
            Flush()
        end)
    end

    -- Sends each path's pending fields as one write. A path with a write in flight
    -- waits ("busy") and is tried again shortly; any other refusal is Not saved.
    Flush = function()
        local retry = false
        for id, fields in pairs(pending) do
            local changes = {}
            for field, value in pairs(fields) do changes[field] = value end
            local ok, reason = Paths.UpdatePath(id, changes, "Edit region map path")
            if ok then
                pending[id] = nil
                local path = Paths.Get(id)
                if path ~= nil and changes.time ~= nil then Session.RememberPathStyle(path) end
            elseif reason == "busy" then
                retry = true
            else
                pending[id] = nil
                failed[id] = true
            end
        end
        if retry then ScheduleSave(0.5) end
        if panel ~= nil and panel.valid then panel:FireEvent("bind") end
    end

    local function Edited(field, value)
        local id = data.selectedPathId
        if id == nil then return end
        pending[id] = pending[id] or {}
        pending[id][field] = value
        failed[id] = nil
        ScheduleSave(C.autosaveDelay)
    end

    -- A typed time: a valid one waits to be saved, any other shows the range line.
    local function EditedTime(field, text)
        local watches = ParseTime(text)
        badTime[field] = watches == nil
        local fields = pending[data.selectedPathId or ""]
        if watches ~= nil then
            Edited(field, watches)
        elseif fields ~= nil then
            fields[field] = nil
        end
        if panel ~= nil and panel.valid then panel:FireEvent("bind") end
    end

    -- A click on a choice (type, the other way): saved at once, after any write in flight.
    local function Write(changes, description, attempt)
        attempt = attempt or 1
        local id = data.selectedPathId
        if id == nil then return end
        local ok, reason = Paths.UpdatePath(id, changes, description)
        if reason == "busy" and attempt < C.busyRetries then
            dmhub.Schedule(C.busyRetryDelay, function()
                if ctx.IsAlive() and data.selectedPathId == id then Write(changes, description, attempt + 1) end
            end)
            return
        end
        if ctx.Report(ok, reason == "busy" and "unavailable" or reason) then
            local path = Paths.Get(id)
            if path ~= nil and changes.typeId ~= nil then Session.RememberPathStyle(path) end
            ctx.RefreshAll()
        end
    end

    -- Header (read and edit) -----------------------------------------------------------------------

    local icon = gui.Panel { classes = { "regionMapSideIcon" }, bgimage = C.iconPath, interactable = false }
    local title = gui.Label { classes = { "regionMapSideTitle" }, text = "" }
    local closeButton = Session.IconButton("region-map-path-close", C.iconClose, T("panel.close"), function()
        ctx.SelectPath(nil)
    end)
    local header = gui.Panel { classes = { "regionMapSideHeader" }, icon, title, closeButton }

    -- Read view ------------------------------------------------------------------------------------

    -- The type, drawn the way the map draws it, so the chip is the legend (N1).
    local sample = RegionMapPathLayer.Sample(40)
    local typeName = Label({ "regionMapChipText" })
    local typeChip = gui.Panel { classes = { "regionMapPathChip" }, interactable = false, sample, typeName }

    local visibility = Label({ "regionMapMeta" })
    local eyeButton = Session.IconButton("region-map-path-eye", C.iconEye, "", function()
        local path = Current()
        if path ~= nil then SetVisibility(ctx, path, path.visibility == "hidden" and "revealed" or "hidden") end
    end)
    local visibilityWaits = false
    local metaRow = gui.Panel { classes = { "regionMapSideRow" }, visibility, eyeButton }

    local ends = Label({ "regionMapBody" })
    local time = Label({ "regionMapBody", "regionMapPathTime" })
    local readArtwork = RegionMapArtwork.Create(ctx, "path", false)
    local description = Label({ "regionMapBody" })

    local editButton = Button(T("panel.edit"), function()
        if data.selectedPathId ~= nil then ctx.SelectPath(data.selectedPathId, "pathEdit") end
    end)
    local moreButton = Session.IconButton("region-map-path-more", C.iconMore, T("panel.more"), function(element)
        if data.selectedPathId == nil then return end
        local entries = RegionMapPathPanel.MenuEntries(ctx, data.selectedPathId)
        if #entries == 0 then return end
        for _, entry in ipairs(entries) do
            local action = entry.click
            entry.click = function()
                element.popup = nil
                action()
            end
        end
        -- Same as the Location "..." menu: the theme background needs the menu's own styles.
        element.popupsInheritStyles = false
        element.tooltip = nil
        element.popup = Session.ContextMenu(element, { entries = entries })
    end)
    local buttons = gui.Panel { classes = { "regionMapButtonRow" }, editButton, moreButton }

    local noteBody = Label({ "regionMapBody" })
    local noteSection = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
        Label({ "regionMapSectionLabel" }, T("path.note")),
        Label({ "regionMapHint" }, T("path.note.sub")),
        noteBody,
    }

    readView = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        typeChip, metaRow, ends, time, readArtwork, description, buttons, noteSection,
    }

    local function BindRead(path)
        local director = Model.IsDirector()
        local a, b = Paths.Ends(path)
        local aName = Model.DisplayName(a)
        local bName = Model.DisplayName(b)

        local item = Paths.TypeById(path.typeId)
        sample.data.set(RegionMapPathLayer.LookOfType(item))
        SetText(typeName, item ~= nil and Copy.Literal(item.name) or T("path.type.none"))

        metaRow:SetClass("collapsed", not director)
        if director then
            -- A revealed path waits for its hidden end before players see it (H1); that
            -- line replaces the plain "Revealed", wrapping beside the eye button.
            local hiddenEnd = nil
            if a ~= nil and a.visibility == "hidden" then hiddenEnd = a elseif b ~= nil and b.visibility == "hidden" then hiddenEnd = b end
            local waits = path.visibility == "revealed" and hiddenEnd ~= nil
            if waits and hiddenEnd ~= nil then
                SetText(visibility, T("path.waits", { name = Model.DisplayName(hiddenEnd) }))
            else
                SetText(visibility, T("edit.visibility." .. path.visibility))
            end
            if visibilityWaits ~= waits then
                visibilityWaits = waits
                visibility.selfStyle.width = waits and "100%-40" or "auto"
            end
            Session.SetIconButton(eyeButton,
                T(path.visibility == "hidden" and "panel.eye.hidden" or "panel.eye.revealed"),
                path.visibility == "hidden" and C.iconEyeSlash or C.iconEye)
        end

        SetText(ends, T("path.ends", { a = aName, b = bName }))
        SetText(time, Paths.TimeText(path))
        if path.description == "" and director then
            SetText(description, T("panel.desc.empty"))
        else
            SetText(description, Copy.Literal(path.description))
        end
        description:SetClass("collapsed", path.description == "" and not director)

        buttons:SetClass("collapsed", not director)
        noteSection:SetClass("collapsed", not director)
        if director then SetText(noteBody, path.note ~= "" and Copy.Literal(path.note) or T("path.note.placeholder")) end
    end

    -- Edit view (V21-13) ---------------------------------------------------------------------------

    local visibilitySegments = Segments(C.visibilities, "edit.visibility.", function(value)
        local path = Current()
        if path ~= nil and path.visibility ~= value then SetVisibility(ctx, path, value) end
    end)
    local nameInput = gui.Input {
        classes = { "input", "bordered", "regionMapInput" },
        placeholderText = T("edit.path.name.placeholder"), characterLimit = C.textLimit,
        edit = function(element)
            if not panel.data.binding then Edited("name", element.text) end
        end,
        change = function(element)
            if not panel.data.binding then
                Edited("name", element.text)
                Flush()
            end
        end,
    }

    -- Types: one row per type with its line sample; the path's own is marked.
    local typesList = gui.Panel { width = "100%", height = "auto", flow = "vertical" }
    local typesSignature = nil
    local function TypeRow(item)
        local rowSample = RegionMapPathLayer.Sample(40)
        rowSample.data.set(RegionMapPathLayer.LookOfType(item))
        return gui.Panel {
            classes = { "regionMapRow", "regionMapTypeRow" },
            data = { id = item.id },
            click = function(element)
                local path = Current()
                if path ~= nil and path.typeId ~= element.data.id then
                    Write({ typeId = element.data.id }, "Change path type")
                end
            end,
            rowSample,
            Label({ "regionMapRowName", "regionMapTypeName" }, Copy.Literal(item.name)),
        }
    end

    local function TimeInput(field)
        return gui.Input {
            classes = { "input", "bordered", "regionMapInput", "regionMapTimeInput" },
            characterLimit = 8,
            edit = function(element)
                if not panel.data.binding then EditedTime(field, element.text) end
            end,
            change = function(element)
                if not panel.data.binding then
                    EditedTime(field, element.text)
                    Flush()
                end
            end,
        }
    end
    local timeInput = TimeInput("time")
    local timeUnit = Label({ "regionMapBody", "regionMapTimeUnit" })
    local timeError = Label({ "regionMapHint", "danger" }, T("edit.path.timeRange"))
    local backSegments = Segments(C.pathBacks, "edit.path.back.", function(value)
        local path = Current()
        if path ~= nil and path.back ~= value then Write({ back = value }, "Change path direction") end
    end)
    local backTimeLabel = Label({ "regionMapFormLabel" })
    local backTimeInput = TimeInput("backTime")
    local backTimeUnit = Label({ "regionMapBody", "regionMapTimeUnit" })
    local backTimeError = Label({ "regionMapHint", "danger" }, T("edit.path.timeRange"))
    local backTimeFields = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        backTimeLabel,
        gui.Panel { classes = { "regionMapTimeRow" }, backTimeInput, backTimeUnit },
        backTimeError,
    }

    local function TextArea(field, limit, placeholder)
        return Session.TextArea(limit, {
            placeholderText = placeholder,
            edit = function(element)
                if not panel.data.binding then Edited(field, element.text) end
            end,
            change = function(element)
                if not panel.data.binding then
                    Edited(field, element.text)
                    Flush()
                end
            end,
        })
    end
    local descriptionInput = TextArea("description", C.descriptionLimit, T("edit.desc.placeholder"))
    local noteInput = TextArea("note", C.noteLimit, T("path.note.placeholder"))

    local stateLine = Label({ "regionMapStateLine" })
    local retryButton = Button(T("edit.retry"), function()
        local id = data.selectedPathId
        if id == nil then return end
        failed[id] = nil
        pending[id] = pending[id] or {}
        pending[id].name = nameInput.text
        pending[id].description = descriptionInput.text
        pending[id].note = noteInput.text
        local watches = ParseTime(timeInput.text)
        if watches ~= nil then pending[id].time = watches end
        local backWatches = ParseTime(backTimeInput.text)
        if backWatches ~= nil then pending[id].backTime = backWatches end
        Flush()
    end)
    local doneButton = Button(T("edit.done"), function()
        Flush()
        if data.selectedPathId ~= nil then ctx.SelectPath(data.selectedPathId, "path") end
    end)

    local editArtwork = RegionMapArtwork.Create(ctx, "path", true)
    editView = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        Label({ "regionMapFormLabel" }, T("edit.visibility")),
        visibilitySegments,
        Label({ "regionMapFormLabel" }, T("edit.name")),
        nameInput,
        Label({ "regionMapFormLabel" }, T("edit.path.type")),
        typesList,
        Label({ "regionMapFormLabel" }, T("edit.path.time")),
        gui.Panel { classes = { "regionMapTimeRow" }, timeInput, timeUnit },
        timeError,
        Label({ "regionMapHint" }, T("edit.path.unit.hint")),
        Label({ "regionMapFormLabel" }, T("edit.path.back")),
        backSegments,
        backTimeFields,
        editArtwork,
        Label({ "regionMapFormLabel" }, T("edit.desc")),
        descriptionInput,
        Label({ "regionMapFormLabel" }, T("path.note")),
        Label({ "regionMapHint" }, T("path.note.sub")),
        noteInput,
        Label({ "regionMapHint" }, T("edit.path.bends")),
        gui.Panel { classes = { "regionMapSideRow" }, stateLine, retryButton },
        gui.Panel { classes = { "regionMapButtonRow" }, doneButton },
    }

    -- Typed fields follow the live record unless the viewer has unsaved text
    -- in them or is typing there now.
    local function SetInput(input, field, value)
        local fields = pending[data.selectedPathId or ""]
        if (fields ~= nil and fields[field] ~= nil) or input.hasFocus or badTime[field] then return end
        if input.text ~= value then input.text = value end
    end

    local function BindEdit(path)
        visibilitySegments.data.select(path.visibility)
        SetInput(nameInput, "name", path.name)

        local types = Paths.Types()
        local parts = {}
        for _, item in ipairs(types) do
            parts[#parts + 1] = item.id .. "|" .. item.name .. "|" .. item.pattern .. "|" .. item.color .. "|" .. item.width
        end
        local signature = table.concat(parts, "\n")
        if signature ~= typesSignature then
            typesSignature = signature
            local rows = {} --- @type Panel[]
            for _, item in ipairs(types) do rows[#rows + 1] = TypeRow(item) end
            typesList.children = rows
        end
        for _, row in ipairs(typesList.children) do row:SetClass("selected", row.data.id == path.typeId) end

        local unit = T("set.timeUnit." .. Paths.TimeUnit())
        SetInput(timeInput, "time", TimeInputText(path.time))
        SetText(timeUnit, unit)
        timeError:SetClass("collapsed", not badTime.time)
        backSegments.data.select(path.back)
        backTimeFields:SetClass("collapsed", path.back ~= "different")
        local _, b = Paths.Ends(path)
        SetText(backTimeLabel, T("edit.path.backTime", { b = Model.DisplayName(b) }))
        SetInput(backTimeInput, "backTime", TimeInputText(path.backTime))
        SetText(backTimeUnit, unit)
        backTimeError:SetClass("collapsed", not badTime.backTime)
        SetInput(descriptionInput, "description", path.description)
        SetInput(noteInput, "note", path.note)

        local status = Paths.SaveStatus(path.id)
        local text, danger = "", false
        if pending[path.id] ~= nil or status == "pending" then text = T("edit.saving")
        elseif failed[path.id] or status == "failed" then text, danger = T("edit.notSaved"), true
        elseif status == "confirmed" then text = T("edit.saved") end
        SetText(stateLine, text)
        stateLine:SetClass("danger", danger)
        retryButton:SetClass("collapsed", not danger)
        -- A confirmed write does not always trigger a refresh, so check again shortly.
        -- Only this panel shows the save state, so only it is bound again.
        if text == T("edit.saving") and not panel.data.recheckScheduled then
            panel.data.recheckScheduled = true
            dmhub.Schedule(C.saveRecheckDelay, function()
                if mod.unloaded or not panel.valid then return end
                panel.data.recheckScheduled = false
                panel:FireEvent("bind")
            end)
        end
    end

    -- Connect to... picker (V21-12, Q10) -----------------------------------------------------------

    local pickTitle = gui.Label { classes = { "regionMapSideTitle", "noIcon" }, text = "" }
    local pickNone = Label({ "regionMapHint" })
    local pickList = gui.Panel { width = "100%", height = "auto", flow = "vertical", tmargin = 6 }
    local pickTop = nil --- @type nil|RegionMapLocationRecord the pin Enter picks
    local pickInput

    local function PickBack()
        if data.selectedId ~= nil then ctx.Select(data.selectedId, "read") end
    end

    local function Pick(target)
        local from = Model.GetLocation(data.selectedId)
        if from == nil then return end
        -- The new path opens in the edit form once it is readable.
        if RegionMapPathTool.Connect(ctx, from.id, target.id) then ctx.Select(nil, nil) end
    end

    -- The other pins of the map, nearest first, narrowed by the typed text.
    local function RunPick(query)
        local from = Model.GetLocation(data.selectedId)
        local rows = {} --- @type Panel[]
        pickTop = nil
        if from == nil then
            pickList.children = rows
            return
        end
        local needle = string.lower(Model.TrimSingleLine(query))
        local candidates = {} --- @type {location: RegionMapLocationRecord, distance: number}[]
        local others = 0
        for _, other in ipairs(Model.Children(from.parentId)) do
            if other.id ~= from.id then
                others = others + 1
                local name = Model.DisplayName(other)
                if needle == "" or string.find(string.lower(name), needle, 1, true) ~= nil then
                    local du, dv = other.u - from.u, other.v - from.v
                    candidates[#candidates + 1] = { location = other, distance = du * du + dv * dv }
                end
            end
        end
        table.sort(candidates, function(x, y)
            if x.distance ~= y.distance then return x.distance < y.distance end
            return x.location.id < y.location.id
        end)
        pickTop = candidates[1] ~= nil and candidates[1].location or nil
        for _, candidate in ipairs(candidates) do
            local target = candidate.location
            rows[#rows + 1] = gui.Panel {
                classes = { "regionMapRow" },
                click = function() if not mod.unloaded then Pick(target) end end,
                gui.Label { classes = { "regionMapRowName" }, text = Copy.Literal(Model.DisplayName(target)), interactable = false },
            }
        end
        pickList.children = rows
        if others == 0 then
            SetText(pickNone, T("picker.connect.none"))
        else
            SetText(pickNone, T("search.none", { query = Model.TrimSingleLine(query) }))
        end
        pickNone:SetClass("collapsed", #candidates > 0)
        pickInput:SetClass("collapsed", others == 0)
    end

    pickInput = gui.SearchInput {
        classes = { "regionMapPopoverInput" }, tmargin = 6,
        placeholderText = T("search.placeholder"), editlag = 0.15,
        edit = function(element) RunPick(element.text) end,
        change = function(element) RunPick(element.text) end,
        -- Enter connects to the top result, so the picker works from the keyboard alone.
        submit = function(element)
            RunPick(element.text)
            if pickTop ~= nil then Pick(pickTop) end
        end,
    }

    pickView = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        gui.Panel {
            classes = { "regionMapSideHeader" }, pickTitle,
            Session.IconButton("region-map-connect-close", C.iconClose, T("dlg.cancel"), PickBack),
        },
        pickInput,
        pickNone,
        pickList,
        gui.Panel { classes = { "regionMapButtonRow" }, Button(T("dlg.cancel"), PickBack) },
    }

    local function BindPick(location)
        SetText(pickTitle, T("picker.connect.title", { name = Model.DisplayName(location) }))
        -- A fresh picker for each opening: empty search, focus in it.
        if panel.data.pickFor == location.id then return end
        panel.data.pickFor = location.id
        if pickInput.text ~= "" then pickInput.text = "" end
        RunPick("")
        Session.FocusSoon(pickInput, function() return data.panelMode == "pickPathEnd" end)
    end

    -- Binding --------------------------------------------------------------------------------------

    local function Bind()
        local mode = data.panelMode
        local path = (mode == "path" or mode == "pathEdit") and Current() or nil
        local picking = nil --- @type nil|RegionMapLocationRecord
        if mode == "pickPathEnd" and Model.IsDirector() then picking = Model.GetLocation(data.selectedId) end
        panel:SetClass("collapsed", path == nil and picking == nil)
        if mode ~= "pickPathEnd" then panel.data.pickFor = nil end
        if mode ~= "pathEdit" then
            badTime.time, badTime.backTime = nil, nil
        end
        readArtwork:FireEvent("bind", path ~= nil and mode == "path" and path.id or nil)
        editArtwork:FireEvent("bind", path ~= nil and mode == "pathEdit" and path.id or nil)
        if path == nil and picking == nil then return end
        local rootWidth = ctx.root.renderedWidth or 0
        local width = C.sidePanelWidth * Session.UIScale()
        if rootWidth > 0 and rootWidth < C.narrowWidth then width = rootWidth end
        if panel.data.width ~= width then
            panel.data.width = width
            panel.selfStyle.width = width
        end
        local editing = mode == "pathEdit" and Model.IsDirector()
        header:SetClass("collapsed", path == nil)
        readView:SetClass("collapsed", path == nil or editing)
        editView:SetClass("collapsed", path == nil or not editing)
        pickView:SetClass("collapsed", picking == nil)
        panel.data.binding = true
        if path ~= nil then
            SetText(title, Paths.Title(path))
            if editing then BindEdit(path) else BindRead(path) end
        elseif picking ~= nil then
            BindPick(picking)
        end
        panel.data.binding = false
    end

    panel = gui.Panel {
        id = "region-map-path-panel",
        classes = { "regionMapSide", "collapsed" },
        floating = true,
        width = C.sidePanelWidth,
        popupsInheritStyles = true,
        data = { width = nil, binding = false, recheckScheduled = false, pickFor = nil },
        bind = function() if not mod.unloaded then Bind() end end,
        flush = function() Flush() end,
        destroy = function() Flush() end,
        gui.Panel {
            classes = { "regionMapSideScroll" }, vscroll = true,
            gui.Panel {
                classes = { "regionMapSideBody" },
                header,
                readView,
                editView,
                pickView,
            },
        },
    }
    return panel
end
