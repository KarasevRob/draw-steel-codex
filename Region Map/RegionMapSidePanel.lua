local mod = dmhub.GetModLoading()

--- The Location side panel at the right edge of the window (D6): read mode,
--- edit mode with autosave (D13b), the inline pickers (map image, target map,
--- journal entry) and the "..." menu shared with a pin's right-click (R12).
---
--- Events on the returned panel:
---   bind()    redraw for ctx.data.selectedId and ctx.data.panelMode
---   flush()   save pending typed text now (before any navigation)
--- @class RegionMapSidePanel: GameType
--- @field new fun(o?: table): RegionMapSidePanel
RegionMapSidePanel = RegisterGameType("RegionMapSidePanel")
local C = RegionMapConstants
local Model = RegionMapModel
local Session = RegionMapSession
local Copy = RegionMapCopy
local Journal = RegionMapJournal

local SetText = Session.SetText
local T = Copy.T
local Label, Button, Segments = Session.Label, Session.Button, Session.Segments

local DisplayName = Model.DisplayName

-- Whether the Party is on a Location's own map or anywhere below it.
local function PartyInside(id)
    local party = Model.Party()
    if party == nil then return false end
    return Model.IsInSubtree(id, party.mapId) or (party.locationId ~= nil and Model.IsInSubtree(id, party.locationId))
end

-- "..." menu --------------------------------------------------------------------------------------

-- Runs a model write and hands its results to onResult. While it answers "busy"
-- (a save of the same rows is still in flight, such as a rename just typed) it is
-- tried again shortly; if it never clears, it reports as not saved.
local function WhenNotBusy(ctx, write, onResult, attempt)
    attempt = attempt or 1
    local ok, reason, entry, count = write()
    if reason == "busy" then
        if attempt < C.busyRetries then
            dmhub.Schedule(C.busyRetryDelay, function()
                if ctx.IsAlive() then WhenNotBusy(ctx, write, onResult, attempt + 1) end
            end)
            return
        end
        reason = "unavailable"
    end
    onResult(ok, reason, entry, count)
end

-- Ids of a Location and every Location below it: the pins a delete removes.
local function SubtreeIds(location, includeSelf)
    local ids, queue = {}, { location.id }
    if includeSelf then ids[location.id] = true end
    while #queue > 0 do
        local parentId = table.remove(queue, 1)
        for _, child in ipairs(Model.Index().childrenOf[parentId] or {}) do
            ids[child.id] = true
            queue[#queue + 1] = child.id
        end
    end
    return ids
end

-- How many paths the viewer sees that a removal of these pins takes with it (B5).
local function PathCount(ids)
    return RegionMapPaths.CountVisible(RegionMapPaths.Touching(ids))
end

local function ConfirmDelete(ctx, location)
    local count = Model.VisibleDescendantCount(location.id)
    local paths = PathCount(SubtreeIds(location, true))
    local labels = #RegionMapLabels.OnMaps(SubtreeIds(location, true))
    local function Delete()
        WhenNotBusy(ctx, function() return Model.DeleteLocation(location.id) end, function(ok, reason, entry, deleted)
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
    if parent ~= nil and PartyInside(location.id) then
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
--- @param ctx RegionMapContext
--- @param id string
function RegionMapSidePanel.RequestDelete(ctx, id)
    if not ctx.IsAlive() then return end
    local location = Model.GetLocation(id)
    if location ~= nil and Model.CanDelete(location) then ConfirmDelete(ctx, location) end
end

local function ConfirmRemoveMap(ctx, location)
    local count = Model.VisibleDescendantCount(location.id)
    local body
    if count > 0 then body = T("dlg.removeMap.body", { count = count }) else body = T("dlg.removeMap.body.empty") end
    local paths = PathCount(SubtreeIds(location, false))
    if paths > 0 then body = body .. "\n" .. T("dlg.delete.paths", { count = paths }) end
    local labels = #RegionMapLabels.OnMaps(SubtreeIds(location, true))
    if labels > 0 then body = body .. "\n" .. T("label.deleteCount", { count = labels }) end
    ctx.Confirm {
        title = T("dlg.removeMap.title", { name = DisplayName(location) }),
        message = body,
        confirm = T("dlg.removeMap.ok"),
        onConfirm = function()
            WhenNotBusy(ctx, function() return Model.RemoveMap(location.id) end, function(ok, reason, entry)
                if ctx.Report(ok, reason) then
                    ctx.Push(entry, "toast.mapRemoved", { name = DisplayName(location) })
                    ctx.RefreshAll()
                end
            end)
        end,
    }
end

local function SetVisibility(ctx, location, visibility)
    local ok, reason, entry = Model.SetVisibility(location.id, visibility)
    if ctx.Report(ok, reason) then
        ctx.Push(entry, visibility == "hidden" and "toast.hid" or "toast.revealed", { name = DisplayName(location) })
        ctx.RefreshAll()
    end
end

local function SetMapShared(ctx, location, shared)
    local ok, reason, entry = Model.SetMapShared(location.id, shared)
    if ctx.Report(ok, reason) then
        ctx.Push(entry, shared and "toast.mapShared" or "toast.mapUnshared", { map = DisplayName(location) })
        ctx.RefreshAll()
    end
end

--- The "..." menu of a Location, filtered by role and state (manifest section 8).
--- Top-level maps share the complete action list with their Atlas cards.
--- Players see Move, Move to map... and Delete on their own Locations only.
--- @param ctx RegionMapContext
--- @param id string
--- @return table[] gui.ContextMenu entries
function RegionMapSidePanel.MenuEntries(ctx, id)
    local location = Model.GetLocation(id)
    local entries = {}
    if location == nil then return entries end
    local director = Model.IsDirector()
    local canEdit = Model.CanEdit(location)
    local isPin = location.parentId ~= ""
    local mapActions = director and not isPin and Model.CanOpenMap(location)
    local function Add(copyId, action, group, disabled)
        entries[#entries + 1] = {
            id = "region-map-menu-" .. copyId,
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
    if RegionMapPathPanel.CanConnect(ctx, location) then
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
                    ctx.Report(Model.SaveDetails(location.id, { journalDocId = "" }))
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
        Add("menu.delete", function() RegionMapSidePanel.RequestDelete(ctx, id) end, "delete")
    end
    return entries
end

--- Build the side panel.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapSidePanel.Create(ctx)
    local data = ctx.data
    local panel
    local readView
    local editView
    local pickView

    local function Current()
        return Model.GetLocation(data.selectedId)
    end

    -- Autosave -----------------------------------------------------------------------------------

    -- Typed text waiting to be saved, per Location id: { name?, description?, note? }.
    local pending = {} --- @type table<string, table<string, string>>
    local failed = {} --- @type table<string, boolean>
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

    -- Sends every pending field. A field whose row has a write in flight waits
    -- ("busy") and is retried shortly; an invalid value is dropped as Not saved.
    Flush = function()
        local retry = false
        for id, fields in pairs(pending) do
            local function Done(field, ok, reason)
                if ok then
                    fields[field] = nil
                elseif reason == "busy" then
                    retry = true
                else
                    fields[field] = nil
                    failed[id] = true
                end
            end
            local callbacks = {
                success = function() failed[id] = nil; ctx.RefreshAll() end,
                failure = function() failed[id] = true; ctx.RefreshAll() end,
            }
            if fields.name ~= nil then
                local ok, reason = Model.UpdateLocation(id, { name = fields.name }, "Rename region map location")
                Done("name", ok, reason)
            end
            if fields.description ~= nil then
                local ok, reason = Model.SaveDetails(id, { description = fields.description }, callbacks)
                Done("description", ok, reason)
            end
            if fields.note ~= nil then
                local ok, reason = Model.SaveDirectorNote(id, fields.note, callbacks)
                Done("note", ok, reason)
            end
            if next(fields) == nil then pending[id] = nil end
        end
        if retry then ScheduleSave(0.5) end
        if panel ~= nil and panel.valid then panel:FireEvent("bind") end
    end

    local function Edited(field, value)
        local id = data.selectedId
        if id == nil then return end
        pending[id] = pending[id] or {}
        pending[id][field] = value
        failed[id] = nil
        ScheduleSave(C.autosaveDelay)
    end

    -- Read view ------------------------------------------------------------------------------------

    local readIcon = gui.Panel { classes = { "regionMapSideIcon" }, interactable = false }
    local readTitle = gui.Label { classes = { "regionMapSideTitle" }, text = "" }
    local closeButton = Session.IconButton("region-map-panel-close", C.iconClose, T("panel.close"), function()
        ctx.Select(nil, nil)
    end)
    local metaLabel = Label({ "regionMapMeta" })
    local eyeButton = Session.IconButton("region-map-panel-eye", C.iconEye, "", function()
        local location = Current()
        if location ~= nil then
            SetVisibility(ctx, location, location.visibility == "hidden" and "revealed" or "hidden")
        end
    end)
    local mapButton = Session.IconButton("region-map-panel-share", C.iconMap, "", function()
        local location = Current()
        if location ~= nil then SetMapShared(ctx, location, not location.mapShared) end
    end)
    local metaRow = gui.Panel { classes = { "regionMapSideRow" }, metaLabel, eyeButton, mapButton }
    -- Every viewer sees a map's kind (A2).
    local modeChip = gui.Label { classes = { "regionMapChip", "regionMapSideChip" }, text = T("chip.pointcrawl"), interactable = false }
    local readArtwork = RegionMapArtwork.Create(ctx, "location", false)
    local description = Label({ "regionMapBody" })
    local journalLink = gui.Label {
        classes = { "regionMapLink" }, text = T("panel.journal"),
        click = function()
            local details = Model.Details(data.selectedId or "")
            if details ~= nil and details.journal.id ~= nil then Journal.Open(details.journal.id) end
        end,
    }
    local author = Label({ "regionMapMeta" })
    local partyHere = Label({ "regionMapBody" })
    local movePartyButton = Button(T("panel.moveParty"), function()
        local location = Current()
        if location == nil then return end
        -- On a point crawl map this is the Director's jump, logged as placed, not travel (Q16).
        local placed = Model.IsPointCrawl(Model.GetLocation(location.parentId))
        local ok, reason, entry = Model.WriteParty { mapId = location.parentId, locationId = location.id, placed = placed }
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
    local moreButton = Session.IconButton("region-map-panel-more", C.iconMore, T("panel.more"), function(element)
        if data.selectedId ~= nil then ctx.ShowMenu(element, data.selectedId) end
    end)
    local notesBody = Label({ "regionMapBody", "collapsed" })
    local notesSub = Label({ "regionMapHint", "collapsed" }, T("panel.notes.sub"))
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
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
        gui.Panel {
            classes = { "regionMapSectionHeader" },
            notesArrow,
            Label({ "regionMapSectionLabel" }, T("panel.notes")),
        },
        notesSub,
        notesBody,
    }

    local pathsSection = RegionMapPathPanel.PathsSection(ctx)

    readView = gui.Panel {
        classes = { "regionMapSideBody" },
        gui.Panel { classes = { "regionMapSideHeader" }, readIcon, readTitle, closeButton },
        modeChip,
        metaRow,
        readArtwork,
        description,
        journalLink,
        author,
        partyHere,
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
        gui.Panel { classes = { "regionMapButtonRow" }, movePartyButton, openMapButton },
        gui.Panel { classes = { "regionMapButtonRow" }, editButton, moreButton },
        pathsSection,
        notesSection,
    }

    local function BindRead(location)
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

        local details = Model.Details(location.id)
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
        moreButton:SetClass("collapsed", #RegionMapSidePanel.MenuEntries(ctx, location.id) == 0)

        pathsSection.data.bind(location)

        notesSection:SetClass("collapsed", not director)
        if director then
            local note = Model.DirectorNote(location.id) or ""
            SetText(notesBody, Copy.Literal(note))
        end
    end

    -- Edit view ------------------------------------------------------------------------------------

    local function UpdateField(changes, undoText)
        local location = Current()
        if location == nil then return end
        local ok, reason = Model.UpdateLocation(location.id, changes, undoText)
        if ctx.Report(ok, reason) then
            local updated = Model.GetLocation(location.id)
            if updated ~= nil then Session.RememberPinStyle(updated) end
            ctx.RefreshAll()
        end
    end

    local visibilityLabel = Label({ "regionMapFormLabel" }, T("edit.visibility"))
    local visibilitySegments = Segments(C.visibilities, "edit.visibility.", function(value)
        local location = Current()
        if location ~= nil and location.visibility ~= value then SetVisibility(ctx, location, value) end
    end)
    local nameInput = gui.Input {
        classes = { "input", "bordered", "regionMapInput" },
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
            classes = { "regionMapIconChoice" }, data = { key = key },
            click = function(element) UpdateField({ icon = element.data.key }, "Change location icon") end,
            gui.Panel { classes = { "regionMapPinGlyph" }, bgimage = C.pinIcons[key], interactable = false },
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
    local iconGrid = gui.Panel { classes = { "regionMapIconGrid" }, children = iconChoices }
    local iconPicker = gui.Panel {
        width = "100%", height = "auto", flow = "vertical", classes = { "collapsed" },
        Label({ "regionMapFormLabel" }, T("edit.icon.picker")),
        iconTabs,
        iconGrid,
        iconLibrary,
        gui.Panel {
            classes = { "regionMapButtonRow" },
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
        Label({ "regionMapFormLabel" }, T("edit.icon")),
        gui.Panel { classes = { "regionMapButtonRow" }, iconButton },
        iconPicker,
        Label({ "regionMapFormLabel" }, T("edit.style")),
        styleSegments,
        Label({ "regionMapFormLabel" }, T("edit.importance")),
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
    local journalLabel = Label({ "regionMapFormLabel" }, T("edit.journal"))
    local journalTitle = Label({ "regionMapBody" })
    local journalButton = Button(T("menu.linkJournal"), function()
        if data.selectedId ~= nil then ctx.Select(data.selectedId, "pickJournal") end
    end)
    local journalRow = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        journalLabel, journalTitle, gui.Panel { classes = { "regionMapButtonRow" }, journalButton },
    }
    local notesLabel = Label({ "regionMapFormLabel" }, T("edit.notes"))
    local notesInput = TextArea("note", C.noteLimit, T("edit.notes.placeholder"))
    local stateLine = Label({ "regionMapStateLine" })
    local retryButton = Button(T("edit.retry"), function()
        local id = data.selectedId
        if id == nil then return end
        failed[id] = nil
        pending[id] = pending[id] or {}
        pending[id].name = nameInput.text
        pending[id].description = descriptionInput.text
        if Model.IsDirector() then pending[id].note = notesInput.text end
        Flush()
    end)
    local doneButton = Button(T("edit.done"), function()
        Flush()
        if data.selectedId ~= nil then ctx.Select(data.selectedId, "read") end
    end)

    local editArtwork = RegionMapArtwork.Create(ctx, "location", true)
    editView = gui.Panel {
        classes = { "regionMapSideBody", "collapsed" },
        visibilityLabel,
        visibilitySegments,
        Label({ "regionMapFormLabel" }, T("edit.name")),
        nameInput,
        pinFields,
        editArtwork,
        Label({ "regionMapFormLabel" }, T("edit.desc")),
        descriptionInput,
        journalRow,
        notesLabel,
        notesInput,
        gui.Panel { classes = { "regionMapSideRow" }, stateLine, retryButton },
        gui.Panel { classes = { "regionMapButtonRow" }, doneButton },
    }

    -- Typed fields follow the live record unless the viewer has unsaved text
    -- in them or is typing there now.
    local function SetInput(input, field, value)
        local fields = pending[data.selectedId or ""]
        if (fields ~= nil and fields[field] ~= nil) or input.hasFocus then return end
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

        local status = Model.SaveStatus(location.id)
        local text, danger = "", false
        if pending[location.id] ~= nil or status == "pending" then text = T("edit.saving")
        elseif failed[location.id] or status == "failed" then text, danger = T("edit.notSaved"), true
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

        if data.focusName then
            data.focusName = false
            Session.FocusSoon(nameInput)
        end
    end

    -- Pickers (map image, target map, journal entry) ----------------------------------------------

    local pickTitle = gui.Label { classes = { "regionMapSideTitle" }, text = "" }
    local pickHint = Label({ "regionMapHint" })
    local pickHiddenNotice = gui.Label {
        id = "region-map-add-map-hidden-notice",
        classes = { "regionMapModeDesc", "bold", "collapsed" }, tmargin = 4, bmargin = 6,
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
            local ok, reason
            if data.pickKind == "add" then ok, reason = Model.AddMap(location.id, imageId, data.newMapMode)
            else ok, reason = Model.ReplaceImage(location.id, imageId) end
            if ctx.Report(ok, reason) then
                ctx.Select(location.id, "read")
                ctx.CheckImageSize(location.id, imageId)
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
    local pickSizeHint = Label({ "regionMapHint" })
    local pickList = gui.Panel { width = "100%", height = "auto", flow = "vertical", tmargin = 6 }
    -- Add map: the kind first (A1), then the image; Back returns to the kind.
    local pickModeLabel = Label({ "regionMapFormLabel" }, T("mode.title"))
    local pickModeChoice = Session.ModeChoice(function(mode)
        if data.selectedId == nil then return end
        data.newMapMode = mode
        ctx.Select(data.selectedId, "pickImage")
    end)
    local pickModeName = Label({ "regionMapFormLabel" })
    local pickBack = Button(T("mode.back"), function()
        if data.selectedId ~= nil then ctx.Select(data.selectedId, "pickMode") end
    end)
    pickView = gui.Panel {
        classes = { "regionMapSideBody", "collapsed" },
        gui.Panel {
            classes = { "regionMapSideHeader" }, pickTitle,
            Session.IconButton("region-map-pick-close", C.iconClose, T("dlg.cancel"), function()
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
            classes = { "regionMapButtonRow" },
            pickBack,
            Button(T("dlg.cancel"), function()
                if data.selectedId ~= nil then ctx.Select(data.selectedId, "read") end
            end),
        },
    }

    local function Row(text, action)
        return gui.Panel {
            classes = { "regionMapRow" },
            click = function() action() end,
            gui.Label { classes = { "regionMapRowName" }, text = text, interactable = false },
        }
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
                        WhenNotBusy(ctx, function() return Model.MoveToMap(location.id, map.id) end, function(ok, reason, entry)
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
                    if ctx.Report(Model.SaveDetails(location.id, { journalDocId = entry.id })) then
                        ctx.Select(location.id, "read")
                    end
                end)
            end
        end
        pickList.children = rows
    end

    -- Binding ----------------------------------------------------------------------------------------

    local function Bind()
        local location = Current()
        local mode = data.panelMode
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
        id = "region-map-side-panel",
        classes = { "regionMapSide", "collapsed" },
        floating = true,
        width = C.sidePanelWidth,
        popupsInheritStyles = true,
        data = { binding = false, boundId = nil, iconPicker = false, iconTab = "map", recheckScheduled = false },
        bind = function() Bind() end,
        flush = function() Flush() end,
        destroy = function() Flush() end,
        gui.Panel {
            classes = { "regionMapSideScroll" }, vscroll = true,
            readView, editView, pickView,
        },
    }
    return panel
end
