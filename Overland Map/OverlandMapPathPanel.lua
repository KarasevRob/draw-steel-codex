local mod = dmhub.GetModLoading()

--- The path panel at the right edge of the window:
--- what a selected point crawl path is, between which Locations, how long it
--- takes each way and its description. The Director also gets the hide/reveal
--- eye, the danger or requirement note (H5: players never see it), the "..."
--- menu, the edit form with autosave and the Connect to... picker.
--- It uses the side panel's look and place; the shell shows one or the other.
---
--- Events on the returned panel:
---   bind()    redraw for ctx.data.panelMode "path", "pathEdit" or "pickPathEnd"
---   flush()   save pending typed text now (before any navigation)
--- @class OverlandMapPathPanel: GameType
--- @field new fun(o?: table): OverlandMapPathPanel
OverlandMapPathPanel = RegisterGameType("OverlandMapPathPanel")
local C = OverlandMapConstants
local Model = OverlandMapModel
local Paths = OverlandMapPaths
local Session = OverlandMapControls
local Copy = OverlandMapCopy

local SetText = Session.SetText
local T = Copy.T
local Label, Button, Segments = Session.Label, Session.Button, Session.Segments

local function SetVisibility(ctx, path, visibility)
    local result = OverlandMapCommands.SetPathVisibility(path.id, visibility)
    local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
    if ctx.Report(ok, reason) then
        ctx.Push(entry, visibility == "hidden" and "toast.hid" or "toast.revealed", { name = Paths.Title(path, true) })
        ctx.RefreshAll()
    end
end

local TimeInputText, ParseTime = Paths.TimeInputText, Paths.ParseTime

--- Whether a Location can be joined to another by Connect to... now: the
--- Director, a pin on the open point crawl map, with another pin beside it (E1).
--- @param ctx OverlandMapContext
--- @param location OverlandMapLocationRecord
--- @return boolean
function OverlandMapPathPanel.CanConnect(ctx, location)
    if not Model.IsDirector() or location.parentId == "" or location.parentId ~= ctx.data.mapId then return false end
    local map = Model.GetLocation(location.parentId)
    return map ~= nil and Model.IsPointCrawl(map) and #Model.Children(map.id) >= 2
end

--- The "..." and right-click menu of a path: Director only (H3). Redraw line
--- joins it with the Path tool.
--- @param ctx OverlandMapContext
--- @param id string
--- @return table[] gui.ContextMenu entries
function OverlandMapPathPanel.MenuEntries(ctx, id)
    local path = Paths.Get(id)
    local entries = {}
    if path == nil or not Model.IsDirector() then return entries end
    local function Add(copyId, action) entries[#entries + 1] = { text = T(copyId), click = action } end
    -- Stopping the Party partway goes first: it is the in-play action (G3, Q4).
    if path.mapId == ctx.data.mapId and OverlandMapTravel.CanStopOn(path) then
        entries[#entries + 1] = {
            text = T("ctx.path.place", { path = Paths.ShownName(path) }), click = function() ctx.StopOnPath(path.id) end,
        }
    end
    if path.mapId == ctx.data.mapId then
        Add("menu.redraw", function() OverlandMapPathTool.StartRedraw(ctx, path.id) end)
    end
    if path.visibility == "hidden" then
        Add("menu.reveal", function() SetVisibility(ctx, path, "revealed") end)
    else
        Add("menu.hide", function() SetVisibility(ctx, path, "hidden") end)
    end
    -- Deleting removes nothing else, so it needs no confirm; the toast has Undo (E3).
    Add("menu.delete", function()
        local title = Paths.Title(path, true)
        local result = OverlandMapCommands.DeletePath(path.id)
        if ctx.Report(result.outcome == "accepted" or result.outcome == "unchanged", result.reason) then
            if ctx.data.selectedPathId == path.id then ctx.SelectPath(nil) end
            ctx.Push(result.undo, "toast.pathDeleted", { path = title })
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
--- @param ctx OverlandMapContext
--- @return Panel section; section.data.bind(location) redraws it
function OverlandMapPathPanel.PathsSection(ctx)
    local rows = gui.Panel { width = "100%", height = "auto", flow = "vertical", tmargin = 4 }
    local none = Label({ "overlandMapHint", "sizeXs" }, T("panel.paths.none"))
    local connect = Button(T("menu.connect"), function()
        if ctx.data.selectedId ~= nil then ctx.Select(ctx.data.selectedId, "pickPathEnd") end
    end)
    local connectRow = gui.Panel { classes = { "overlandMapButtonRow" }, connect }
    local section = gui.Panel {
        width = "100%", height = "auto", flow = "vertical", data = { signature = nil },
        gui.Panel { classes = { "overlandMapRule" }, interactable = false },
        Label({ "overlandMapSectionLabel", "sizeS" }, T("panel.paths")),
        none,
        rows,
        connectRow,
    }

    local function Row(id, text, hidden)
        local children = { Label({ "overlandMapRowName", "overlandMapPathRowName", "sizeS" }, text) } --- @type Panel[]
        if hidden then
            children[#children + 1] = gui.Panel { classes = { "overlandMapPathRowEye" }, bgimage = C.iconEyeSlash, interactable = false }
        end
        return gui.Panel {
            classes = { "overlandMapRow", "overlandMapPathRow" },
            click = function() if not mod.unloaded then ctx.SelectPath(id) end end,
            children = children,
        }
    end

    section.data.bind = function(location)
        local map = location.parentId ~= "" and Model.GetLocation(location.parentId) or nil
        local shown = map ~= nil and Model.IsPointCrawl(map)
        section:SetClass("collapsed", not shown)
        if not shown then return end
        connectRow:SetClass("collapsed", not OverlandMapPathPanel.CanConnect(ctx, location))
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
--- @param ctx OverlandMapContext
--- @return Panel
function OverlandMapPathPanel.Create(ctx)
    local data = ctx.data
    local panel
    local releaseSession
    local readView
    local editView
    local pickView

    local function Current()
        return Paths.Get(data.selectedPathId)
    end

    -- Autosave (the side panel's pattern) ---------------------------------------------------------

    local editor = OverlandMapEditors.Create("path", function()
        if panel ~= nil and panel.valid then panel:FireEvent("bind") end
    end)
    local Flush = editor.Flush
    local function Edited(field, value)
        editor.Stage(data.selectedPathId, field, value)
    end

    local badTime = {} --- @type table<string, boolean>

    -- A typed time: a valid one waits to be saved, any other shows the range line.
    local function EditedTime(field, text)
        local watches = ParseTime(text)
        badTime[field] = watches == nil
        if watches ~= nil then
            Edited(field, watches)
        else
            editor.Withdraw(data.selectedPathId, field)
        end
        if panel ~= nil and panel.valid then panel:FireEvent("bind") end
    end

    -- A click on a choice (type, the other way): saved at once, after any write in flight.
    local function Write(changes, _)
        local id = data.selectedPathId
        if id == nil then return end
        editor.Commit(id, changes)
        local path = Paths.Get(id)
        if path ~= nil and changes.typeId ~= nil then OverlandMapPreferences.RememberPathStyle(path) end
        ctx.RefreshAll()
    end

    -- Header (read and edit) -----------------------------------------------------------------------

    local icon = gui.Panel { classes = { "overlandMapSideIcon" }, bgimage = C.iconPath, interactable = false }
    local title = gui.Label { classes = { "overlandMapSideTitle", "sizeL" }, text = "" }
    local closeButton = Session.IconButton("overland-map-path-close", C.iconClose, T("panel.close"), function()
        ctx.SelectPath(nil)
    end)
    local header = gui.Panel { classes = { "overlandMapSideHeader" }, icon, title, closeButton }

    -- Read view ------------------------------------------------------------------------------------

    -- The type, drawn the way the map draws it, so the chip is the legend (N1).
    local sample = OverlandMapPathLayer.Sample(40)
    local typeName = Label({ "overlandMapChipText", "sizeS" })
    local typeChip = gui.Panel { classes = { "overlandMapPathChip" }, interactable = false, sample, typeName }

    local visibility = Label({ "overlandMapMeta", "sizeXs" })
    local eyeButton = Session.IconButton("overland-map-path-eye", C.iconEye, "", function()
        local path = Current()
        if path ~= nil then SetVisibility(ctx, path, path.visibility == "hidden" and "revealed" or "hidden") end
    end)
    local visibilityWaits = false
    local metaRow = gui.Panel { classes = { "overlandMapSideRow" }, visibility, eyeButton }

    local ends = Label({ "overlandMapBody", "sizeS" })
    local time = Label({ "overlandMapBody", "overlandMapPathTime", "sizeS" })
    local readArtwork = OverlandMapArtwork.Create(ctx, "path", false,
        function(id) return data.selectedPathId == id and data.panelMode == "path" end)
    local description = Label({ "overlandMapBody", "sizeS" })

    local editButton = Button(T("panel.edit"), function()
        if data.selectedPathId ~= nil then ctx.SelectPath(data.selectedPathId, "pathEdit") end
    end)
    local moreButton = Session.IconButton("overland-map-path-more", C.iconMore, T("panel.more"), function(element)
        if data.selectedPathId == nil then return end
        local entries = OverlandMapPathPanel.MenuEntries(ctx, data.selectedPathId)
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
    local buttons = gui.Panel { classes = { "overlandMapButtonRow" }, editButton, moreButton }

    local noteBody = Label({ "overlandMapBody", "sizeS" })
    local noteSection = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        gui.Panel { classes = { "overlandMapRule" }, interactable = false },
        Label({ "overlandMapSectionLabel", "sizeS" }, T("path.note")),
        Label({ "overlandMapHint", "sizeXs" }, T("path.note.sub")),
        noteBody,
    }

    readView = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        typeChip, metaRow, ends, time, readArtwork, description, buttons, noteSection,
    }

    local function BindRead(path)
        local view = OverlandMapReaders.Path(path.id)
        if view == nil then return end
        path = view.row
        local director = Model.IsDirector()
        local a, b = Paths.Ends(path)
        local aName = Model.DisplayName(a)
        local bName = Model.DisplayName(b)

        local item = Paths.TypeById(path.typeId)
        sample.data.set(OverlandMapPathLayer.LookOfType(item))
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

    -- Edit view ---------------------------------------------------------------------------

    local visibilitySegments = Segments(C.visibilities, "edit.visibility.", function(value)
        local path = Current()
        if path ~= nil and path.visibility ~= value then SetVisibility(ctx, path, value) end
    end)
    local nameInput = gui.Input {
        classes = { "input", "bordered", "overlandMapInput" },
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
        local rowSample = OverlandMapPathLayer.Sample(40)
        rowSample.data.set(OverlandMapPathLayer.LookOfType(item))
        return gui.Panel {
            classes = { "overlandMapRow", "overlandMapTypeRow" },
            data = { id = item.id },
            click = function(element)
                local path = Current()
                if path ~= nil and path.typeId ~= element.data.id then
                    Write({ typeId = element.data.id }, "Change path type")
                end
            end,
            rowSample,
            Label({ "overlandMapRowName", "overlandMapTypeName", "sizeS" }, Copy.Literal(item.name)),
        }
    end

    local function TimeInput(field)
        return gui.Input {
            classes = { "input", "bordered", "overlandMapInput", "overlandMapTimeInput" },
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
    local timeUnit = Label({ "overlandMapBody", "overlandMapTimeUnit", "sizeS" })
    local timeError = Label({ "overlandMapHint", "danger", "sizeXs" }, T("edit.path.timeRange"))
    local backSegments = Segments(C.pathBacks, "edit.path.back.", function(value)
        local path = Current()
        if path ~= nil and path.back ~= value then Write({ back = value }, "Change path direction") end
    end)
    local backTimeLabel = Label({ "overlandMapFormLabel", "sizeXs" })
    local backTimeInput = TimeInput("backTime")
    local backTimeUnit = Label({ "overlandMapBody", "overlandMapTimeUnit", "sizeS" })
    local backTimeError = Label({ "overlandMapHint", "danger", "sizeXs" }, T("edit.path.timeRange"))
    local backTimeFields = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        backTimeLabel,
        gui.Panel { classes = { "overlandMapTimeRow" }, backTimeInput, backTimeUnit },
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

    local stateLine = Label({ "overlandMapStateLine", "sizeXs" })
    local retryButton = Button(T("edit.retry"), function()
        if data.selectedPathId ~= nil then editor.Retry(data.selectedPathId) end
    end)
    local doneButton = Button(T("edit.done"), function()
        Flush()
        if data.selectedPathId ~= nil then ctx.SelectPath(data.selectedPathId, "path") end
    end)

    local editArtwork = OverlandMapArtwork.Create(ctx, "path", true,
        function(id) return data.selectedPathId == id and data.panelMode == "pathEdit" end)
    editView = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.visibility")),
        visibilitySegments,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.name")),
        nameInput,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.path.type")),
        typesList,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.path.time")),
        gui.Panel { classes = { "overlandMapTimeRow" }, timeInput, timeUnit },
        timeError,
        Label({ "overlandMapHint", "sizeXs" }, T("edit.path.unit.hint")),
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.path.back")),
        backSegments,
        backTimeFields,
        editArtwork,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.desc")),
        descriptionInput,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("path.note")),
        Label({ "overlandMapHint", "sizeXs" }, T("path.note.sub")),
        noteInput,
        Label({ "overlandMapHint", "sizeXs" }, T("edit.path.bends")),
        gui.Panel { classes = { "overlandMapSideRow" }, stateLine, retryButton },
        gui.Panel { classes = { "overlandMapButtonRow" }, doneButton },
    }

    -- Typed fields follow the live record unless the viewer has unsaved text
    -- in them or is typing there now.
    local inputBindings = setmetatable({}, { __mode = "k" })
    local function SetInput(input, field, value)
        local id = data.selectedPathId or ""
        local signature = id .. ":" .. editor.Discards(id)
        local replaced = inputBindings[input] ~= signature
        inputBindings[input] = signature
        local fields = editor.Pending(id)
        if not replaced and ((fields ~= nil and fields[field] ~= nil) or input.hasFocus or badTime[field]) then return end
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

        editor.Bind(path.id)
        local status = editor.Status(path.id)
        local text, danger = "", false
        if status == "pending" or status == "saving" then text = T("edit.saving")
        elseif status == "failed" or status == "invalid" or status == "denied" then text, danger = T("edit.notSaved"), true
        elseif status == "saved" then text = T("edit.saved") end
        SetText(stateLine, text)
        stateLine:SetClass("danger", danger)
        retryButton:SetClass("collapsed", not danger)

    end

    -- Connect to... picker (Q10) -----------------------------------------------------------

    local pickTitle = gui.Label { classes = { "overlandMapSideTitle", "noIcon", "sizeL" }, text = "" }
    local pickNone = Label({ "overlandMapHint", "sizeXs" })
    local pickList = gui.Panel { width = "100%", height = "auto", flow = "vertical", tmargin = 6 }
    local pickTop = nil --- @type nil|OverlandMapLocationRecord the pin Enter picks
    local pickInput

    local function PickBack()
        if data.selectedId ~= nil then ctx.Select(data.selectedId, "read") end
    end

    local function Pick(target)
        local from = Model.GetLocation(data.selectedId)
        if from == nil then return end
        -- The new path opens in the edit form once it is readable.
        if OverlandMapPathTool.Connect(ctx, from.id, target.id) then ctx.Select(nil, nil) end
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
        local candidates = {} --- @type {location: OverlandMapLocationRecord, distance: number}[]
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
                classes = { "overlandMapRow" },
                click = function() if not mod.unloaded then Pick(target) end end,
                gui.Label { classes = { "overlandMapRowName", "sizeS" }, text = Copy.Literal(Model.DisplayName(target)), interactable = false },
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
        classes = { "overlandMapPopoverInput" }, tmargin = 6,
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
            classes = { "overlandMapSideHeader" }, pickTitle,
            Session.IconButton("overland-map-connect-close", C.iconClose, T("dlg.cancel"), PickBack),
        },
        pickInput,
        pickNone,
        pickList,
        gui.Panel { classes = { "overlandMapButtonRow" }, Button(T("dlg.cancel"), PickBack) },
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
        editor.Bind(mode == "pathEdit" and Model.IsDirector() and path and path.id or nil)
        local picking = nil --- @type nil|OverlandMapLocationRecord
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
        id = "overland-map-path-panel",
        classes = { "overlandMapSide", "collapsed" },
        floating = true,
        width = C.sidePanelWidth,
        popupsInheritStyles = true,
        data = { width = nil, binding = false, recheckScheduled = false, pickFor = nil },
        bind = function() if not mod.unloaded then Bind() end end,
        flush = function() Flush() end,
        destroy = function() editor.Destroy(); if releaseSession then releaseSession() end end,
        gui.Panel {
            classes = { "overlandMapSideScroll" }, vscroll = true,
            gui.Panel {
                classes = { "overlandMapSideBody" },
                header,
                readView,
                editView,
                pickView,
            },
        },
    }
    releaseSession = OverlandMapSession.Register {
        scope = ctx, valid = function() return panel.valid end, flush = Flush,
        cancel = function(reason, id) editor.Cancel(id, reason == "permission") end,
    }
    return panel
end

--- @return table[]
function OverlandMapPathPanel.Styles()
    return {
        {
            selectors = { "overlandMapPathRow" },
            height = "auto",
            vpad = 6,
        },
        {
            selectors = { "overlandMapPathRowName" },
            width = "100%-22",
            halign = "left",
            textWrap = true,
        },
        {
            selectors = { "overlandMapPathRowEye" },
            width = 16,
            height = 16,
            halign = "right",
            valign = "center",
            bgcolor = "@fgMuted",
        },
    }
end
