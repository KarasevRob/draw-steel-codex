local mod = dmhub.GetModLoading()

--- The Location side panel at the right edge of the window (D6): read mode,
--- edit mode with autosave (D13b), the inline pickers (map image, target map,
--- journal entry) and the "..." menu shared with a pin's right-click (R12).
---
--- Events on the returned panel:
---   bind()    redraw for ctx.data.selectedId and ctx.data.panelMode
---   flush()   save pending typed text now (before any navigation)
--- @class OverlandMapSidePanel: GameType
--- @field new fun(o?: table): OverlandMapSidePanel
OverlandMapSidePanel = RegisterGameType("OverlandMapSidePanel")
local C = OverlandMapConstants
local Model = OverlandMapModel
local Session = OverlandMapControls
local Copy = OverlandMapCopy
local Journal = OverlandMapJournal

local SetText = Session.SetText
local T = Copy.T
local Label, Button, Segments = Session.Label, Session.Button, Session.Segments

local DisplayName = Model.DisplayName

-- "..." menu --------------------------------------------------------------------------------------

-- Runs a model write and hands its results to onResult. While it answers "busy"
-- (a save of the same rows is still in flight, such as a rename just typed) it is
-- tried again shortly; if it never clears, it reports as not saved.
local function WhenNotBusy(ctx, write, onResult, attempt, valid)
    valid = valid or OverlandMapSession.Guard(ctx)
    if not valid() then return end
    attempt = attempt or 1
    local result = write()
    local ok, reason, entry, count = result.outcome == "accepted" or result.outcome == "unchanged", result.reason, result.undo, result.count
    if reason == "busy" then
        if attempt < C.busyRetries then
            OverlandMapLifetime.Schedule(C.busyRetryDelay, function()
                if valid() then WhenNotBusy(ctx, write, onResult, attempt + 1, valid) end
            end)
            return
        end
        reason = "unavailable"
    end
    onResult(ok, reason, entry, count)
end

-- How many paths the viewer sees that a removal of these pins takes with it (B5).
local function PathCount(ids)
    return OverlandMapPaths.CountVisible(OverlandMapPaths.Touching(ids))
end

local function ConfirmDelete(ctx, location)
    local plan = Model.PlanDeletion(location.id, false)
    if plan == nil then return end
    local count, paths, labels = plan.descendants, plan.paths, plan.labels
    local function Delete()
        WhenNotBusy(ctx, function() return OverlandMapCommands.DeleteLocation(location.id, plan) end, function(ok, reason, entry, deleted)
            if reason == "changed" then
                local current = Model.GetLocation(location.id)
                if current then ConfirmDelete(ctx, current) end
                return
            end
            if not ctx.Report(ok, reason) then return end
            if ctx.data.selectedId == location.id then ctx.Select(nil, nil) end
            if deleted > 0 then
                ctx.Push(entry, "toast.deletedTree", { name = DisplayName(location), count = count })
            else
                ctx.Push(entry, "toast.deleted", { name = DisplayName(location) })
            end
            ctx.RefreshAll()
        end)
    end
    -- Only a Location with a map, children or paths asks first (D7d, B5); undo covers the rest.
    if location.imageId == "" and count == 0 and paths == 0 then
        Delete()
        return
    end
    local lines = {}
    if count > 0 then lines[#lines + 1] = T("dlg.delete.body", { count = count }) end
    if paths > 0 then lines[#lines + 1] = T("dlg.delete.paths", { count = paths }) end
    if labels > 0 then lines[#lines + 1] = T("label.deleteCount", { count = labels }) end
    local parent = Model.GetLocation(location.parentId)
    if parent ~= nil and plan.partyTarget ~= nil then
        lines[#lines + 1] = T("dlg.delete.party", { map = DisplayName(parent) })
    end
    ctx.Confirm {
        title = T("dlg.delete.title", { name = DisplayName(location) }),
        message = table.concat(lines, "\n"),
        confirm = T("dlg.delete.ok"),
        onConfirm = Delete,
    }
end

--- Ask before deleting a Location or Atlas map, using its current permissions and contents.
--- @param ctx OverlandMapContext
--- @param id string
function OverlandMapSidePanel.RequestDelete(ctx, id)
    if not ctx.IsAlive() then return end
    local location = Model.GetLocation(id)
    if location ~= nil and Model.CanDelete(location) then ConfirmDelete(ctx, location) end
end

local function ConfirmRemoveMap(ctx, location)
    local plan = Model.PlanDeletion(location.id, true)
    if plan == nil then return end
    local count = plan.descendants
    local body
    if count > 0 then body = T("dlg.removeMap.body", { count = count }) else body = T("dlg.removeMap.body.empty") end
    local paths = plan.paths
    if paths > 0 then body = body .. "\n" .. T("dlg.delete.paths", { count = paths }) end
    local labels = plan.labels
    if labels > 0 then body = body .. "\n" .. T("label.deleteCount", { count = labels }) end
    ctx.Confirm {
        title = T("dlg.removeMap.title", { name = DisplayName(location) }),
        message = body,
        confirm = T("dlg.removeMap.ok"),
        onConfirm = function()
            WhenNotBusy(ctx, function() return OverlandMapCommands.RemoveMap(location.id, plan) end, function(ok, reason, entry)
                if reason == "changed" then
                    local current = Model.GetLocation(location.id)
                    if current then ConfirmRemoveMap(ctx, current) end
                    return
                end
                if ctx.Report(ok, reason) then
                    ctx.Push(entry, "toast.mapRemoved", { name = DisplayName(location) })
                    ctx.RefreshAll()
                end
            end)
        end,
    }
end

local function SetVisibility(ctx, location, visibility)
    local result = OverlandMapCommands.SetLocationVisibility(location.id, visibility)
    local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
    if ctx.Report(ok, reason) then
        ctx.Push(entry, visibility == "hidden" and "toast.hid" or "toast.revealed", { name = DisplayName(location) })
        ctx.RefreshAll()
    end
end

local function SetMapShared(ctx, location, shared)
    local result = OverlandMapCommands.SetMapShared(location.id, shared)
    local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
    if ctx.Report(ok, reason) then
        ctx.Push(entry, shared and "toast.mapShared" or "toast.mapUnshared", { map = DisplayName(location) })
        ctx.RefreshAll()
    end
end

--- The "..." menu of a Location, filtered by role and state (manifest section 8).
--- Top-level maps share the complete action list with their Atlas cards.
--- Players see Move, Move to map... and Delete on their own Locations only.
--- @param ctx OverlandMapContext
--- @param id string
--- @return table[] gui.ContextMenu entries
function OverlandMapSidePanel.MenuEntries(ctx, id)
    local location = Model.GetLocation(id)
    local entries = {}
    if location == nil then return entries end
    local director = Model.IsDirector()
    local canEdit = Model.CanEdit(location)
    local isPin = location.parentId ~= ""
    local mapActions = director and not isPin and Model.CanOpenMap(location)
    local function Add(copyId, action, group, disabled)
        entries[#entries + 1] = {
            id = "overland-map-menu-" .. copyId,
            text = T(copyId), group = mapActions and (group or "map") or nil, disabled = disabled,
            click = function()
                if not ctx.IsAlive() or disabled or (director and not Model.IsDirector()) then return end
                local current = Model.GetLocation(id)
                if current ~= nil then action(current) end
            end,
        }
    end
    -- Canvas actions must open the card's map before using current-map services.
    local function OnMap(action)
        return function(current)
            ctx.OpenMap(current.id, "restore")
            if ctx.data.mapId ~= current.id then return end
            ctx.SetPopover(nil)
            action(current)
        end
    end
    if mapActions then
        Add("panel.openMap", function(current) ctx.OpenMap(current.id, "restore") end, "open")
        if canEdit then
            Add("panel.edit", function(current) ctx.Select(current.id, "edit") end, "open")
        end
        local canAdd = Model.CanAdd(id)
        Add("tb.import", OnMap(function(current)
            if Model.CanAdd(current.id) then ctx.ImportLocations() end
        end), "contents", not canAdd)
    end
    if canEdit and isPin then
        -- Move places the pin on the open map, so it is offered only for that map's pins,
        -- not for a Location read from the breadcrumb.
        if location.parentId == ctx.data.mapId then
            Add("menu.move", function() ctx.SetTool("move", location.id) end)
        end
        Add("menu.moveToMap", function() ctx.Select(location.id, "pickMap") end)
    end
    if OverlandMapPathPanel.CanConnect(ctx, location) then
        Add("menu.connect", function() ctx.Select(location.id, "pickPathEnd") end)
    end
    if director and isPin then
        if location.visibility == "hidden" then
            Add("menu.reveal", function() SetVisibility(ctx, location, "revealed") end)
        else
            Add("menu.hide", function() SetVisibility(ctx, location, "hidden") end)
        end
    end
    if director then
        if location.imageId == "" then
            -- The map's kind comes first (A1); the image picker follows.
            Add("menu.addMap", function()
                ctx.data.pickKind, ctx.data.newMapMode = "add", nil
                ctx.Select(location.id, "pickMode")
            end)
        else
            Add("menu.replaceImage", function()
                ctx.data.pickKind = "replace"
                ctx.Select(location.id, "pickImage")
            end)
            if isPin then Add("menu.removeMap", function() ConfirmRemoveMap(ctx, location) end) end
        end
        if mapActions then
            Add("menu.mapSettings", OnMap(function() ctx.SetPopover("settings") end))
        end
        local details = Model.Details(location.id)
        if details ~= nil and Journal.Available() then
            if mapActions and details.journal.id ~= nil then
                Add("panel.journal", function(current)
                    local latest = Model.Details(current.id)
                    if latest ~= nil and latest.journal.id ~= nil then Journal.Open(latest.journal.id) end
                end, "journal")
            end
            if details.journalDocId == "" then
                Add("menu.linkJournal", function() ctx.Select(location.id, "pickJournal") end, "journal")
            else
                Add("menu.changeJournal", function() ctx.Select(location.id, "pickJournal") end, "journal")
                Add("menu.unlinkJournal", function()
                    local result = OverlandMapCommands.SaveDetails(location.id, { journalDocId = "" })
                    ctx.Report(OverlandMapCommands.Accepted(result), result.reason)
                end, "journal")
            end
        end
    end
    if mapActions then
        local shared = location.mapShared
        Add(shared and "menu.unshareMap" or "menu.shareMap", function(current)
            SetMapShared(ctx, current, not shared)
        end, "sharing")
        Add("tb.show", OnMap(function() ctx.ShowToPlayers() end), "sharing")
    end
    if Model.CanDelete(location) then
        Add("menu.delete", function() OverlandMapSidePanel.RequestDelete(ctx, id) end, "delete")
    end
    return entries
end

--- Build the side panel.
--- @param ctx OverlandMapContext
--- @return Panel
function OverlandMapSidePanel.Create(ctx)
    local data = ctx.data
    local panel
    local releaseSession
    local readView
    local editView
    local pickView

    local function Current()
        return Model.GetLocation(data.selectedId)
    end

    -- Autosave -----------------------------------------------------------------------------------

    local editor = OverlandMapEditors.Create("location", function()
        if panel ~= nil and panel.valid then panel:FireEvent("bind") end
    end)
    local Flush = editor.Flush
    local function Edited(field, value)
        editor.Stage(data.selectedId, field, value)
    end

    -- Read view ------------------------------------------------------------------------------------

    local readIcon = gui.Panel { classes = { "overlandMapSideIcon" }, interactable = false }
    local readTitle = gui.Label { classes = { "overlandMapSideTitle", "sizeL" }, text = "" }
    local closeButton = Session.IconButton("overland-map-panel-close", C.iconClose, T("panel.close"), function()
        ctx.Select(nil, nil)
    end)
    local metaLabel = Label({ "overlandMapMeta", "sizeXs" })
    local eyeButton = Session.IconButton("overland-map-panel-eye", C.iconEye, "", function()
        local location = Current()
        if location ~= nil then
            SetVisibility(ctx, location, location.visibility == "hidden" and "revealed" or "hidden")
        end
    end)
    local mapButton = Session.IconButton("overland-map-panel-share", C.iconMap, "", function()
        local location = Current()
        if location ~= nil then SetMapShared(ctx, location, not location.mapShared) end
    end)
    local metaRow = gui.Panel { classes = { "overlandMapSideRow" }, metaLabel, eyeButton, mapButton }
    -- Every viewer sees a map's kind (A2).
    local modeChip = gui.Label { classes = { "overlandMapChip", "overlandMapSideChip", "sizeXs" }, text = T("chip.pointcrawl"), interactable = false }
    local readArtwork = OverlandMapArtwork.Create(ctx, "location", false,
        function(id) return data.selectedId == id and data.panelMode == "read" end)
    local description = Label({ "overlandMapBody", "sizeS" })
    local journalLink = gui.Label {
        classes = { "overlandMapLink", "sizeS" }, text = T("panel.journal"),
        click = function()
            local details = Model.Details(data.selectedId or "")
            if details ~= nil and details.journal.id ~= nil then Journal.Open(details.journal.id) end
        end,
    }
    local author = Label({ "overlandMapMeta", "sizeXs" })
    local partyHere = Label({ "overlandMapBody", "sizeS" })
    local movePartyButton = Button(T("panel.moveParty"), function()
        local location = Current()
        if location == nil then return end
        -- On a point crawl map this is the Director's jump, logged as placed, not travel (Q16).
        local placed = Model.IsPointCrawl(Model.GetLocation(location.parentId))
        local result = OverlandMapCommands.WriteParty{ mapId = location.parentId, locationId = location.id, placed = placed }
        local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
        if ctx.Report(ok, reason) then
            ctx.Push(entry, "toast.partyAt", { party = Model.PartyName(), name = DisplayName(location) })
            ctx.RefreshAll()
        end
    end)
    local openMapButton = Button(T("panel.openMap"), function()
        local location = Current()
        if location == nil then return end
        -- A Location read from the breadcrumb is above the open map, so its map opens going up.
        local above = data.mapId ~= nil and Model.IsInSubtree(location.id, data.mapId)
        ctx.OpenMap(location.id, above and "up" or "down")
    end)
    local editButton = Button(T("panel.edit"), function()
        if data.selectedId ~= nil then ctx.Select(data.selectedId, "edit") end
    end)
    local moreButton = Session.IconButton("overland-map-panel-more", C.iconMore, T("panel.more"), function(element)
        if data.selectedId ~= nil then ctx.ShowMenu(element, data.selectedId) end
    end)
    local notesBody = Label({ "overlandMapBody", "collapsed", "sizeS" })
    local notesSub = Label({ "overlandMapHint", "collapsed", "sizeXs" }, T("panel.notes.sub"))
    local notesExpanded = false
    local notesArrow
    notesArrow = gui.ExpandoArrow {
        bgimage = C.iconCaret,
        click = function(element)
            notesExpanded = not notesExpanded
            element:SetClass("expanded", notesExpanded)
            notesBody:SetClass("collapsed", not notesExpanded)
            notesSub:SetClass("collapsed", not notesExpanded)
        end,
    }
    local notesSection = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        gui.Panel { classes = { "overlandMapRule" }, interactable = false },
        gui.Panel {
            classes = { "overlandMapSectionHeader" },
            notesArrow,
            Label({ "overlandMapSectionLabel", "sizeS" }, T("panel.notes")),
        },
        notesSub,
        notesBody,
    }

    local pathsSection = OverlandMapPathPanel.PathsSection(ctx)

    readView = gui.Panel {
        classes = { "overlandMapSideBody" },
        gui.Panel { classes = { "overlandMapSideHeader" }, readIcon, readTitle, closeButton },
        modeChip,
        metaRow,
        readArtwork,
        description,
        journalLink,
        author,
        partyHere,
        gui.Panel { classes = { "overlandMapRule" }, interactable = false },
        gui.Panel { classes = { "overlandMapButtonRow" }, movePartyButton, openMapButton },
        gui.Panel { classes = { "overlandMapButtonRow" }, editButton, moreButton },
        pathsSection,
        notesSection,
    }

    local function BindRead(location)
        local view = OverlandMapReaders.Location(location.id)
        if view == nil then return end
        local director = Model.IsDirector()
        local isPin = location.parentId ~= ""
        SetText(readTitle, Copy.Literal(DisplayName(location)))
        -- Same fallback as the pin on the canvas, so the header matches what the map shows.
        local icon = C.pinIcons[location.icon] or (location.icon ~= "" and location.icon) or C.pinIcons[C.defaultPinIcon]
        if not isPin then icon = C.iconMap end
        if readIcon.bgimage ~= icon then readIcon.bgimage = icon end
        readIcon:SetClass("image", isPin and location.icon ~= "" and C.pinIcons[location.icon] == nil)
        modeChip:SetClass("collapsed", location.imageId == "" or not Model.IsPointCrawl(location))

        -- Director meta: importance and visibility, the eye, and the map-shared toggle (R4).
        metaRow:SetClass("collapsed", not director)
        if director then
            local meta = ""
            if isPin then
                meta = T("panel.meta", {
                    importance = T("edit.importance." .. location.importance),
                    visibility = T("edit.visibility." .. location.visibility),
                })
            end
            SetText(metaLabel, meta)
            eyeButton:SetClass("collapsed", not isPin)
            Session.SetIconButton(eyeButton,
                T(location.visibility == "hidden" and "panel.eye.hidden" or "panel.eye.revealed"),
                location.visibility == "hidden" and C.iconEyeSlash or C.iconEye)
            mapButton:SetClass("collapsed", location.imageId == "")
            mapButton:SetClass("on", location.mapShared)
            Session.SetIconButton(mapButton, T(location.mapShared and "panel.map.on" or "panel.map.off"))
        end

        local details = view.details
        local text = details ~= nil and details.description or ""
        if text == "" and director then
            SetText(description, T("panel.desc.empty"))
        else
            SetText(description, Copy.Literal(text))
        end
        description:SetClass("collapsed", text == "" and not director)
        journalLink:SetClass("collapsed", details == nil or details.journal.status ~= "available")

        author:SetClass("collapsed", location.createdByDirector)
        SetText(author, T("panel.author", { player = location.ownerName }))

        local party = Model.Party()
        local here = party ~= nil and party.locationId == location.id
        partyHere:SetClass("collapsed", not here)
        SetText(partyHere, T("panel.partyHere", { party = Model.PartyName() }))

        -- Players on a point crawl map move the Party only by Travel to (G5, Q16).
        local crawl = isPin and Model.IsPointCrawl(Model.GetLocation(location.parentId))
        movePartyButton:SetClass("collapsed", not isPin or here or not Model.CanMovePartyOn(location.parentId)
            or (crawl and not director))
        -- Players see Open map only once the map is shared (R4); CanOpenMap says so.
        openMapButton:SetClass("collapsed", location.imageId == "" or not Model.CanOpenMap(location)
            or data.mapId == location.id)
        editButton:SetClass("collapsed", not Model.CanEdit(location))
        moreButton:SetClass("collapsed", #OverlandMapSidePanel.MenuEntries(ctx, location.id) == 0)

        pathsSection.data.bind(location)

        notesSection:SetClass("collapsed", not director)
        if director then
            local note = view.note or ""
            SetText(notesBody, Copy.Literal(note))
        end
    end

    -- Edit view ------------------------------------------------------------------------------------

    local function UpdateField(changes, undoText)
        local location = Current()
        if location == nil then return end
        local result = OverlandMapCommands.UpdateLocation(location.id, changes, undoText)
        local ok, reason = OverlandMapCommands.Accepted(result), result.reason
        if ctx.Report(ok, reason) then
            local updated = Model.GetLocation(location.id)
            if updated ~= nil then OverlandMapPreferences.RememberPinStyle(updated) end
            ctx.RefreshAll()
        end
    end

    local visibilityLabel = Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.visibility"))
    local visibilitySegments = Segments(C.visibilities, "edit.visibility.", function(value)
        local location = Current()
        if location ~= nil and location.visibility ~= value then SetVisibility(ctx, location, value) end
    end)
    local nameInput = gui.Input {
        classes = { "input", "bordered", "overlandMapInput" },
        placeholderText = T("edit.name.placeholder"), characterLimit = C.textLimit,
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

    local pinFields = gui.Panel { width = "100%", height = "auto", flow = "vertical" }
    local iconButton = Button(T("edit.icon.choose"), function()
        panel.data.iconPicker = not panel.data.iconPicker
        panel:FireEvent("bind")
    end)
    local iconChoices = {} --- @type Panel[]
    for _, key in ipairs(C.pinIconOrder) do
        iconChoices[#iconChoices + 1] = gui.Panel {
            classes = { "overlandMapIconChoice" }, data = { key = key },
            click = function(element) UpdateField({ icon = element.data.key }, "Change location icon") end,
            gui.Panel { classes = { "overlandMapPinGlyph" }, bgimage = C.pinIcons[key], interactable = false },
        }
    end
    local iconLibrary = gui.IconEditor {
        classes = { "collapsed" }, width = "100%", height = 150, tmargin = 6, library = "journal", categoriesHidden = true,
        allowPaste = true, allowNone = false, hideIcon = true,
        change = function(element)
            if not panel.data.binding and type(element.value) == "string" and element.value ~= "" then
                UpdateField({ icon = element.value }, "Change location icon")
            end
        end,
    }
    local iconTabs = Segments({ "map", "library" }, "edit.icon.tab.", function(value)
        panel.data.iconTab = value
        panel:FireEvent("bind")
    end)
    local iconGrid = gui.Panel { classes = { "overlandMapIconGrid" }, children = iconChoices }
    local iconPicker = gui.Panel {
        width = "100%", height = "auto", flow = "vertical", classes = { "collapsed" },
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.icon.picker")),
        iconTabs,
        iconGrid,
        iconLibrary,
        gui.Panel {
            classes = { "overlandMapButtonRow" },
            Button(T("edit.icon.clear"), function() UpdateField({ icon = "" }, "Change location icon") end),
        },
    }
    local styleSegments = Segments(C.pinStyles, "edit.style.", function(value)
        UpdateField({ pinStyle = value }, "Change pin style")
    end)
    local importanceSegments = Segments(C.importances, "edit.importance.", function(value)
        UpdateField({ importance = value }, "Change location importance")
    end)
    pinFields.children = {
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.icon")),
        gui.Panel { classes = { "overlandMapButtonRow" }, iconButton },
        iconPicker,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.style")),
        styleSegments,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.importance")),
        importanceSegments,
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
    local journalLabel = Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.journal"))
    local journalTitle = Label({ "overlandMapBody", "sizeS" })
    local journalButton = Button(T("menu.linkJournal"), function()
        if data.selectedId ~= nil then ctx.Select(data.selectedId, "pickJournal") end
    end)
    local journalRow = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        journalLabel, journalTitle, gui.Panel { classes = { "overlandMapButtonRow" }, journalButton },
    }
    local notesLabel = Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.notes"))
    local notesInput = TextArea("note", C.noteLimit, T("edit.notes.placeholder"))
    local stateLine = Label({ "overlandMapStateLine", "sizeXs" })
    local retryButton = Button(T("edit.retry"), function()
        if data.selectedId ~= nil then editor.Retry(data.selectedId) end
    end)
    local doneButton = Button(T("edit.done"), function()
        Flush()
        if data.selectedId ~= nil then ctx.Select(data.selectedId, "read") end
    end)

    local editArtwork = OverlandMapArtwork.Create(ctx, "location", true,
        function(id) return data.selectedId == id and data.panelMode == "edit" end)
    editView = gui.Panel {
        classes = { "overlandMapSideBody", "collapsed" },
        visibilityLabel,
        visibilitySegments,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.name")),
        nameInput,
        pinFields,
        editArtwork,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.desc")),
        descriptionInput,
        journalRow,
        notesLabel,
        notesInput,
        gui.Panel { classes = { "overlandMapSideRow" }, stateLine, retryButton },
        gui.Panel { classes = { "overlandMapButtonRow" }, doneButton },
    }

    -- Typed fields follow the live record unless the viewer has unsaved text
    -- in them or is typing there now.
    local inputBindings = setmetatable({}, { __mode = "k" })
    local function SetInput(input, field, value)
        local id = data.selectedId or ""
        local signature = id .. ":" .. editor.Discards(id)
        local replaced = inputBindings[input] ~= signature
        inputBindings[input] = signature
        local fields = editor.Pending(id)
        if not replaced and ((fields ~= nil and fields[field] ~= nil) or input.hasFocus) then return end
        if input.text ~= value then input.text = value end
    end

    local function BindEdit(location)
        local director = Model.IsDirector()
        local isPin = location.parentId ~= ""
        visibilityLabel:SetClass("collapsed", not director or not isPin)
        visibilitySegments:SetClass("collapsed", not director or not isPin)
        visibilitySegments.data.select(location.visibility)
        SetInput(nameInput, "name", location.name)
        pinFields:SetClass("collapsed", not isPin)
        iconPicker:SetClass("collapsed", not panel.data.iconPicker)
        local tab = panel.data.iconTab or "map"
        iconTabs.data.select(tab)
        iconGrid:SetClass("collapsed", tab ~= "map")
        iconLibrary:SetClass("collapsed", tab ~= "library")
        for _, choice in ipairs(iconChoices) do choice:SetClass("selected", choice.data.key == location.icon) end
        styleSegments.data.select(location.pinStyle)
        importanceSegments.data.select(location.importance)

        local details = Model.Details(location.id)
        SetInput(descriptionInput, "description", details ~= nil and details.description or "")
        journalRow:SetClass("collapsed", not director or not Journal.Available())
        if director and details ~= nil then
            local linked = details.journal.status == "available"
            SetText(journalTitle, linked and Copy.Literal(details.journal.title or "") or "")
            journalTitle:SetClass("collapsed", not linked)
            SetText(journalButton, T(linked and "menu.changeJournal" or "menu.linkJournal"))
        end
        notesLabel:SetClass("collapsed", not director)
        notesInput:SetClass("collapsed", not director)
        if director then SetInput(notesInput, "note", Model.DirectorNote(location.id) or "") end

        editor.Bind(location.id)
        local status = editor.Status(location.id)
        local text, danger = "", false
        if status == "pending" or status == "saving" then text = T("edit.saving")
        elseif status == "failed" or status == "invalid" or status == "denied" then text, danger = T("edit.notSaved"), true
        elseif status == "saved" then text = T("edit.saved") end
        SetText(stateLine, text)
        stateLine:SetClass("danger", danger)
        retryButton:SetClass("collapsed", not danger)


        if data.focusName then
            data.focusName = false
            Session.FocusSoon(nameInput)
        end
    end

    -- Pickers (map image, target map, journal entry) ----------------------------------------------

    local pickTitle = gui.Label { classes = { "overlandMapSideTitle", "sizeL" }, text = "" }
    local pickHint = Label({ "overlandMapHint", "sizeXs" })
    local pickHiddenNotice = gui.Label {
        id = "overland-map-add-map-hidden-notice",
        classes = { "overlandMapModeDesc", "bold", "collapsed", "sizeXs" }, tmargin = 4, bmargin = 6,
        text = T("map.new.hidden"), interactable = false,
    }
    local pickImage = gui.IconEditor {
        width = "100%", height = 150, library = "journal", categoriesHidden = true,
        -- A "none image" hides the editor's "(none)" label; it still reads back as "".
        noneImage = "panels/square.png",
        allowPaste = true, allowNone = true, hideIcon = true,
        -- The IconEditor reads stretch as a flag; the shared stub types it as a border.
        ---@diagnostic disable-next-line: assign-type-mismatch
        stretch = true,
        aspect = 9 / 16,
        change = function(element)
            if panel.data.binding then return end
            local location = Current()
            local imageId = element.value
            if location == nil or type(imageId) ~= "string" or imageId == "" then return end
            local result
            if data.pickKind == "add" then result = OverlandMapCommands.AddMap(location.id, imageId, data.newMapMode)
            else result = OverlandMapCommands.ReplaceImage(location.id, imageId) end
            if ctx.Report(OverlandMapCommands.Accepted(result), result.reason) then
                ctx.Select(location.id, "read")
                ctx.CheckImageSize(location.id, imageId)
                if data.pickKind ~= "add" then OverlandMapUndo.Notify("aids.replaced") end
            end
        end,
    }
    -- Same drop slot as the Atlas New map card: the editor's own white box loses to a
    -- selfStyle tint, and a plus floats over it without taking the pointer.
    pickImage.selfStyle.bgcolor = "#ffffff14"
    local pickImageSlot = gui.Panel {
        width = "100%", height = 150, tmargin = 6,
        pickImage,
        gui.Panel {
            floating = true, interactable = false, width = 32, height = 32,
            halign = "center", valign = "center", bgimage = C.iconAdd, bgcolor = "#ffffff99",
        },
    }
    -- Always visible while choosing an image, so the guidance is read before the pick (J2).
    local pickSizeHint = Label({ "overlandMapHint", "sizeXs" })
    local pickList = gui.Panel { width = "100%", height = "auto", flow = "vertical", tmargin = 6 }
    -- Add map: the kind first (A1), then the image; Back returns to the kind.
    local pickModeLabel = Label({ "overlandMapFormLabel", "sizeXs" }, T("mode.title"))
    local pickModeChoice = Session.ModeChoice(function(mode)
        if data.selectedId == nil then return end
        data.newMapMode = mode
        ctx.Select(data.selectedId, "pickImage")
    end)
    local pickModeName = Label({ "overlandMapFormLabel", "sizeXs" })
    local pickBack = Button(T("mode.back"), function()
        if data.selectedId ~= nil then ctx.Select(data.selectedId, "pickMode") end
    end)
    pickView = gui.Panel {
        classes = { "overlandMapSideBody", "collapsed" },
        gui.Panel {
            classes = { "overlandMapSideHeader" }, pickTitle,
            Session.IconButton("overland-map-pick-close", C.iconClose, T("dlg.cancel"), function()
                if data.selectedId ~= nil then ctx.Select(data.selectedId, "read") end
            end),
        },
        pickHint,
        pickHiddenNotice,
        pickModeLabel,
        pickModeChoice,
        pickModeName,
        pickImageSlot,
        pickSizeHint,
        pickList,
        gui.Panel {
            classes = { "overlandMapButtonRow" },
            pickBack,
            Button(T("dlg.cancel"), function()
                if data.selectedId ~= nil then ctx.Select(data.selectedId, "read") end
            end),
        },
    }

    --- @param icon nil|string a leading glyph, such as the journal entry's kind
    local function Row(text, action, icon)
        local children = {} --- @type Panel[]
        if icon ~= nil then
            children[1] = gui.Panel { classes = { "overlandMapRowIcon" }, bgimage = icon, interactable = false }
        end
        children[#children + 1] = gui.Label { classes = { "overlandMapRowName", "sizeS" }, text = text, interactable = false }
        return gui.Panel { classes = { "overlandMapRow" }, click = function() action() end, children = children }
    end

    local function BindPick(location)
        local mode = data.panelMode
        local adding = data.pickKind == "add" and (mode == "pickMode" or mode == "pickImage")
        pickHiddenNotice:SetClass("collapsed", not adding)
        pickImageSlot:SetClass("collapsed", mode ~= "pickImage")
        pickSizeHint:SetClass("collapsed", mode ~= "pickImage")
        pickList:SetClass("collapsed", mode == "pickImage" or mode == "pickMode")
        pickHint:SetClass("collapsed", mode ~= "pickMap")
        pickModeLabel:SetClass("collapsed", mode ~= "pickMode")
        pickModeChoice:SetClass("collapsed", mode ~= "pickMode")
        pickModeName:SetClass("collapsed", not adding or mode ~= "pickImage" or data.newMapMode == nil)
        pickBack:SetClass("collapsed", not adding or mode ~= "pickImage")
        local rows = {} --- @type Panel[]
        if mode == "pickMode" then
            SetText(pickTitle, T("side.addMap.title", { name = DisplayName(location) }))
        elseif mode == "pickImage" then
            SetText(pickTitle, adding and T("side.addMap.title", { name = DisplayName(location) }) or T("atlas.new.picker"))
            if data.newMapMode ~= nil then SetText(pickModeName, T("mode." .. data.newMapMode)) end
            SetText(pickSizeHint, ctx.ImageHint())
            if pickImage.value ~= "" then pickImage.value = "" end
        elseif mode == "pickMap" then
            SetText(pickTitle, T("picker.moveToMap.title", { name = DisplayName(location) }))
            SetText(pickHint, T("picker.moveToMap.hint"))
            for _, map in ipairs(Model.OpenableMaps()) do
                if map.id ~= location.parentId and not Model.IsInSubtree(location.id, map.id) then
                    local function Move()
                        WhenNotBusy(ctx, function() return OverlandMapCommands.MoveToMap(location.id, map.id) end, function(ok, reason, entry)
                            if ctx.Report(ok, reason) then
                                ctx.Push(entry, "toast.movedToMap", { name = DisplayName(location), map = DisplayName(map) })
                                ctx.Select(nil, nil)
                                ctx.RefreshAll()
                            end
                        end)
                    end
                    rows[#rows + 1] = Row(Copy.Literal(DisplayName(map)), function()
                        -- Its paths join pins on the map it leaves, so they go; ask first (B5).
                        local paths = PathCount({ [location.id] = true })
                        if paths == 0 then
                            Move()
                            return
                        end
                        ctx.Confirm {
                            title = T("dlg.moveToMap.title", { name = DisplayName(location), map = DisplayName(map) }),
                            message = T("dlg.moveToMap.body", { count = paths }),
                            confirm = T("dlg.moveToMap.ok"),
                            onConfirm = Move,
                        }
                    end)
                end
            end
        elseif mode == "pickJournal" then
            SetText(pickTitle, T("edit.journal"))
            for _, entry in ipairs(Journal.ListLinkTargets("")) do
                rows[#rows + 1] = Row(Copy.Literal(entry.title), function()
                    local result = OverlandMapCommands.SaveDetails(location.id, { journalDocId = entry.id })
                    if ctx.Report(OverlandMapCommands.Accepted(result), result.reason) then
                        ctx.Select(location.id, "read")
                    end
                end, entry.icon)
            end
        end
        pickList.children = rows
    end

    -- Binding ----------------------------------------------------------------------------------------

    local function Bind()
        local location = Current()
        local mode = data.panelMode
        editor.Bind(mode == "edit" and location and Model.CanEdit(location) and location.id or nil)
        -- Connect to... picks in the path panel, which takes this panel's place meanwhile.
        local open = location ~= nil and mode ~= "none" and mode ~= "pickPathEnd"
        panel:SetClass("collapsed", not open)
        readArtwork:FireEvent("bind", location ~= nil and open and mode == "read" and location.id or nil)
        editArtwork:FireEvent("bind", location ~= nil and open and mode == "edit" and location.id or nil)
        if not open or location == nil then return end
        local rootWidth = ctx.root.renderedWidth or 0
        local width = C.sidePanelWidth * Session.UIScale()
        if rootWidth > 0 and rootWidth < C.narrowWidth then width = rootWidth end
        if panel.data.width ~= width then
            panel.data.width = width
            panel.selfStyle.width = width
        end
        if panel.data.boundId ~= location.id then
            panel.data.boundId = location.id
            panel.data.iconPicker = false
            notesExpanded = false
            notesArrow:SetClass("expanded", false)
            notesBody:SetClass("collapsed", true)
            notesSub:SetClass("collapsed", true)
        end
        panel.data.binding = true
        readView:SetClass("collapsed", mode ~= "read")
        editView:SetClass("collapsed", mode ~= "edit")
        pickView:SetClass("collapsed", mode ~= "pickMode" and mode ~= "pickImage" and mode ~= "pickMap" and mode ~= "pickJournal")
        if mode == "read" then BindRead(location)
        elseif mode == "edit" then BindEdit(location)
        else BindPick(location) end
        panel.data.binding = false
    end

    panel = gui.Panel {
        id = "overland-map-side-panel",
        classes = { "overlandMapSide", "collapsed" },
        floating = true,
        width = C.sidePanelWidth,
        popupsInheritStyles = true,
        data = { binding = false, boundId = nil, iconPicker = false, iconTab = "map", recheckScheduled = false },
        bind = function() Bind() end,
        flush = function() Flush() end,
        destroy = function() editor.Destroy(); if releaseSession then releaseSession() end end,
        gui.Panel {
            classes = { "overlandMapSideScroll" }, vscroll = true,
            readView, editView, pickView,
        },
    }
    releaseSession = OverlandMapSession.Register {
        scope = ctx, valid = function() return panel.valid end, flush = Flush,
        cancel = function(reason, id) editor.Cancel(id, reason == "permission") end,
    }
    return panel
end
