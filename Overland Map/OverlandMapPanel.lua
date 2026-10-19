local mod = dmhub.GetModLoading()

--- The Overland Map window content (V2 shell): the canvas fills the window and
--- everything else floats over it - breadcrumb, toolbar, banners, Party status,
--- toasts and the side panel (brief section 4). The shell owns navigation,
--- selection, the active tool, Esc order (R2) and refresh routing; components
--- get a OverlandMapContext and are driven by events.
--- @class OverlandMapPanel: GameType
--- @field new fun(o?: table): OverlandMapPanel
OverlandMapPanel = RegisterGameType("OverlandMapPanel")
local C = OverlandMapConstants
local Model = OverlandMapModel
local Styles = OverlandMapStyles
local Session = OverlandMapControls
local Copy = OverlandMapCopy
local Undo = OverlandMapUndo

local T = Copy.T
local SetText = Session.SetText

-- The engine stores escapePriority as a whole number, and on a tie a hidden
-- panel can take Esc and drop it (the inventory dialogs at 13 do), so use
-- whole numbers that no always-present panel holds.
local escapePriorities = EscapePriority
-- In the popout the map is a window like any other.
local WINDOW_PRIORITY = escapePriorities.EXIT_DIALOG
-- Fullscreen, every window is drawn over the map, the character sheet (10)
-- included, so all of the map's Esc handling yields to them.
local FULLSCREEN_PRIORITY = escapePriorities.EXIT_CHARACTER_SHEET - 1

-- monitorAssets accepts data table names too; the stub types it as the
-- built-in asset kinds only, so the list is returned untyped.
--- @return any
local function MonitoredTables(...)
    return { ... }
end

--- Build the Overland Map content panel.
--- Host hooks from OverlandMap.lua; each adds its toolbar button when present.
--- The host-to-content contract. The host passes these callbacks once and never reads
--- the table again; the content never writes to it.
--- Content -> host: the callbacks below.
--- Host -> content: events on the content root:
---   overlandMapHostMode(mode)        the view changed ("fullscreen" or "window"); the content restyles
---   overlandMapHostActive(engaged)   whether this window takes Esc and shortcuts now
---   requestClose(continue)         finish edits and imports, then call continue()
--- The in-app host can change view without replacing this content.
--- @class OverlandMapHostOptions
--- @field close nil|fun() close the in-app map (also Esc at the Atlas)
--- @field popOut nil|fun() move the map into its own OS window
--- @field popIn nil|fun() bring a popped-out map back into the app
--- @field toggleView nil|fun() switch the existing in-app host's size
--- @field mode nil|"fullscreen"|"window"|"native" the view it starts in

--- @param options nil|OverlandMapHostOptions
--- @return Panel
function OverlandMapPanel.Create(options)
    options = options or {}
    -- What the host last told this content; kept here, not in the host's options table.
    local hostMode = options.mode or (options.close ~= nil and "fullscreen" or "native")
    local hostEngaged = true
    local data = OverlandMapSession.ViewState()
    -- The service functions are attached below, before any component is built.
    ---@diagnostic disable-next-line: missing-fields
    local ctx = { data = data } --[[@as OverlandMapContext]]
    local owner = OverlandMapLifetime.Owner("view")
    local ownerValid = owner:Guard()

    local root
    local canvas
    local atlas
    local stopCard
    local popovers
    local present
    local breadcrumb
    local searchButton
    local addButton
    local importButton
    local pathButton
    local lockButton
    local rulerButton
    local showButton
    local viewAsButton
    local logButton
    local settingsButton
    local aidsButton
    local popOutButton
    local popInButton
    local viewButton
    local closeButton
    local statusChip
    local banners
    local toast
    local toastText
    local toastUndo
    local toastRetry
    local toastAction
    local confirmLayer
    local confirmTitle
    local confirmBody
    local confirmOk
    local confirmAlternate
    local shell = {
        refreshScheduled = false, refreshing = false, refreshPending = false,
        toastVersion = -1, toastCanUndo = nil, director = dmhub.isDM,
        transition = nil, -- set while Open map zooms into a pin; other map changes wait for it
        -- What the breadcrumb and banners were last built for; never a real key at first, so the first refresh builds.
        crumbKey = "\0", bannerKey = "\0",
    }

    local RefreshAll
    local changes = OverlandMapSession.Changes()

    function ctx.IsAlive()
        return ownerValid() and not shell.destroying and root ~= nil and root.valid
    end

    local components = {} --- @type table<string, {slot: Panel, panel: Panel?, attempted: boolean?, factory: fun(): Panel}>
    local function Existing(key)
        local entry = key and components[key]
        return entry and entry.panel or nil
    end

    local function Ensure(key)
        local entry = key and components[key]
        if entry == nil or not ctx.IsAlive() then return nil end
        if entry.panel ~= nil then return entry.panel end
        -- A failed or re-entrant constructor must not start another subtree on refresh.
        if entry.attempted then return nil end
        entry.attempted = true
        local panel = entry.factory()
        if not ctx.IsAlive() then panel:DestroySelf(); return nil end
        entry.slot:AddChild(panel)
        entry.panel = panel
        return panel, true
    end

    local function ActiveSideKey(mode)
        if mode == "log" then return "log" end
        if mode == "party" then return "party" end
        if mode == "labelEdit" then return "label" end
        if mode == "path" or mode == "pathEdit" or mode == "pickPathEnd" then return "path" end
        if mode == "read" or mode == "edit" or mode == "pickMode" or mode == "pickImage"
            or mode == "pickMap" or mode == "pickJournal" then return "location" end
        return nil
    end

    local function BindExisting(key)
        local panel = Existing(key)
        if panel ~= nil then panel:FireEvent("bind") end
    end

    function ctx.CurrentMap()
        local map = Model.GetLocation(data.mapId)
        if map == nil or not Model.CanOpenMap(map) then return nil end
        return map
    end

    function ctx.FlushEdits()
        OverlandMapSession.Transition("flush", ctx)
    end

    function ctx.Transition(reason)
        OverlandMapSession.Transition(reason, ctx)
    end

    function ctx.ClearAid()
        if data.selectedAid == nil and data.tool ~= "aidPlace" then return end
        data.selectedAid, data.aidMapId = nil, nil
        if data.tool == "aidPlace" then data.tool = "none" end
        if canvas and canvas.valid then canvas:FireEvent("cancelGesture") end
    end

    -- A failed write says so in a toast; refusals the UI already prevents stay silent.
    function ctx.Report(ok, reason)
        if ok then return true end
        if reason == "invalid" or reason == "unavailable" then Undo.Notify("toast.saveFailed") end
        return false
    end

    function ctx.Push(entry, copyId, args)
        Undo.Push(entry, copyId, args)
    end

    function ctx.ImageHint()
        return T("image.hint", { min = C.imageMinWidth, recommended = C.imageRecommendedWidth, max = C.imageMaxWidth })
    end

    -- Size guidance warns and never blocks (J3); only new picks call this (J4).
    function ctx.CheckImageSize(mapId, imageId)
        OverlandMapImages.Size(imageId, function(width, height)
            if not ctx.IsAlive() then return end
            local copyId = nil
            if width < C.imageMinWidth then copyId = "toast.image.small"
            elseif width > C.imageMaxWidth then copyId = "toast.image.large" end
            if copyId == nil then return end
            Undo.Notify(copyId, { width = width, height = height, recommended = C.imageRecommendedWidth }, nil, {
                copyId = "toast.replaceImage",
                click = function()
                    local map = Model.GetLocation(mapId)
                    if not ctx.IsAlive() or map == nil or map.imageId ~= imageId then return end
                    data.pickKind = "replace"
                    ctx.Select(mapId, "pickImage")
                end,
            })
        end, function()
            local map = Model.GetLocation(mapId)
            return ctx.IsAlive() and data.mapId == mapId and map ~= nil and map.imageId == imageId
        end)
    end

    -- Navigation ---------------------------------------------------------------------------------

    local function LeaveLabel()
        ctx.ClearAid()
        if data.selectedLabelId ~= nil then OverlandMapLabels.Leave(data.selectedLabelId) end
        data.selectedLabelId = nil
        if data.panelMode == "labelEdit" then data.panelMode = "none" end
    end

    local function ApplyOpen(map, how)
        LeaveLabel()
        data.mapId = map.id
        data.locked = true
        data.tool, data.toolTargetId, data.pathDraft = "none", nil, nil
        data.ruler, data.scaleDraft = nil, nil
        -- The log panel stays open: its entries open their maps.
        if data.panelMode ~= "log" then data.selectedId, data.panelMode = nil, "none" end
        data.selectedPathId = nil
        OverlandMapPreferences.SaveLastMap(map.id)
        canvas:FireEvent("showMap", how)
        RefreshAll()
        gui.SetFocus(canvas)
    end

    --- Open a map. "down" (Open map) first zooms into the pin (D8c).
    function ctx.OpenMap(id, how)
        local map = Model.GetLocation(id)
        if map == nil or not Model.CanOpenMap(map) or shell.transition ~= nil then return end
        ctx.Transition("navigation")
        if how == "down" and data.mapId ~= nil and map.parentId == data.mapId and not OverlandMapPreferences.ReduceMotion() then
            -- The canvas always calls back, even when the zoom is cut short; going to
            -- the Atlas meanwhile drops this transition, so the callback then does nothing.
            local transition = {}
            shell.transition = transition
            canvas:FireEvent("animateInto", map.id, function()
                if shell.transition ~= transition then return end
                shell.transition = nil
                local current = Model.GetLocation(map.id)
                if ctx.IsAlive() and current ~= nil and Model.CanOpenMap(current) then ApplyOpen(current, "down") end
            end)
            return
        end
        ApplyOpen(map, how or "restore")
    end

    function ctx.GoAtlas()
        ctx.Transition("navigation")
        LeaveLabel()
        shell.transition = nil
        data.mapId = nil
        data.tool, data.toolTargetId, data.pathDraft = "none", nil, nil
        data.ruler, data.scaleDraft = nil, nil
        -- The log panel stays open on the Atlas; a Location panel has nothing to show there.
        if data.panelMode ~= "log" then data.selectedId, data.panelMode = nil, "none" end
        data.selectedPathId = nil
        canvas:FireEvent("showMap", "restore")
        RefreshAll()
    end

    -- Up one level; a player skips levels they cannot open (R4).
    function ctx.GoUp()
        local map = ctx.CurrentMap()
        if map == nil then return end
        local path = OverlandMapReaders.Breadcrumbs(map.id)
        for i = #path - 1, 1, -1 do
            if Model.CanOpenMap(path[i]) then
                ctx.OpenMap(path[i].id, "up")
                return
            end
        end
        ctx.GoAtlas()
    end

    function ctx.Select(id, mode)
        LeaveLabel()
        local leaving = data.selectedId ~= id or (data.panelMode == "edit" and mode ~= "edit")
        if leaving then ctx.Transition("selection") end
        data.selectedPathId = nil
        if id == nil or Model.GetLocation(id) == nil then
            data.selectedId, data.panelMode = nil, "none"
        else
            data.selectedId, data.panelMode = id, mode or "read"
        end
        RefreshAll("selection")
        if data.selectedId ~= nil then
            -- The panel has not laid out yet on its first open, so use its intended width.
            canvas:FireEvent("keepVisible", data.selectedId, C.sidePanelWidth * Session.UIScale())
        end
    end

    -- A path shows in its own panel, in the side panel's place, read or edit.
    function ctx.SelectPath(id, mode)
        ctx.Transition("selection")
        LeaveLabel()
        if id == nil or OverlandMapPaths.Get(id) == nil then
            data.selectedPathId = nil
            if data.panelMode == "path" or data.panelMode == "pathEdit" then data.panelMode = "none" end
        else
            data.selectedId, data.selectedPathId = nil, id
            data.panelMode = (mode == "pathEdit" and Model.IsDirector()) and "pathEdit" or "path"
        end
        RefreshAll("selection")
    end

    function ctx.SelectLabel(id, edit)
        ctx.Transition("selection")
        ctx.ClearAid()
        if id == nil then
            LeaveLabel()
        else
            local row = OverlandMapLabels.Snapshot(id)
            if row == nil or row.mapId ~= data.mapId then return end
            if data.selectedLabelId ~= id then LeaveLabel() end
            data.selectedId, data.selectedPathId, data.selectedLabelId = nil, nil, id
            data.panelMode = edit and OverlandMapLabels.CanEdit(row) and "labelEdit" or "none"
        end
        RefreshAll("selection")
    end

    function ctx.CreateLabel(u, v)
        local map = ctx.CurrentMap()
        if map == nil then return end
        ctx.FlushEdits()
        local id = OverlandMapLabels.NewDraft(map.id, u, v, OverlandMapPreferences.LastLabelFormat())
        if id == nil then return end
        ctx.SetTool("none")
        ctx.SelectLabel(id, true)
    end

    function ctx.FocusLabel(id, edit)
        local row = OverlandMapLabels.Get(id)
        if row == nil then return end
        if data.mapId ~= row.mapId then ctx.OpenMap(row.mapId, "restore") end
        if data.mapId ~= row.mapId then return end
        ctx.SelectLabel(id, edit)
        canvas:FireEvent("centerOnLabel", id)
    end

    function ctx.SelectAid(kind, edit, reveal)
        ctx.Transition("selection")
        LeaveLabel()
        data.tool, data.toolTargetId, data.pathDraft = "none", nil, nil
        data.selectedId, data.selectedPathId, data.panelMode = nil, nil, "none"
        if kind and OverlandMapAids.CanEdit(data.mapId) then
            data.selectedAid, data.aidMapId = kind, data.mapId
            data.popover = edit ~= false and "aids" or nil
        end
        RefreshAll("selection")
        if kind and reveal ~= false then ctx.KeepAidVisible(kind) end
    end

    function ctx.KeepAidVisible(kind)
        local gap = C.chromeInset * Session.UIScale()
        local inset = data.popover == "aids" and C.popoverWidth * Session.UIScale() + gap or 0
        canvas:FireEvent("keepAidVisible", kind, {
            x1 = gap, x2 = root.renderedWidth - inset - gap,
            y1 = C.belowChromeBar * Session.UIScale() + (banners.renderedHeight or 0) + gap,
            y2 = root.renderedHeight - (C.chromeBarHeight + C.chromeInset * 2) * Session.UIScale(),
        })
    end

    function ctx.FindAid(kind)
        canvas:FireEvent("centerOnAid", kind)
    end

    local tools = { add = true, move = true, ruler = true, scale = true, path = true, redraw = true, labelAdd = true, aidPlace = true }

    function ctx.SetTool(tool, targetId)
        if not tools[tool] then tool = "none" end
        -- Pressing the active tool's button again turns it off.
        if tool == data.tool and targetId == data.toolTargetId then tool = "none" end
        ctx.Transition("tool")
        if tool ~= "aidPlace" then ctx.ClearAid() end
        canvas:FireEvent("cancelGesture")
        -- Measurements are local and go when the ruler does; a scale draft with
        -- both points waits for its distance in Settings.
        if tool ~= "ruler" then data.ruler = nil end
        local draft = data.scaleDraft
        if tool ~= "scale" and draft ~= nil and draft.u2 == nil then data.scaleDraft = nil end
        -- A line being drawn belongs to the tool that drew it.
        if tool ~= data.tool or targetId ~= data.toolTargetId then data.pathDraft = nil end
        data.tool = tool
        data.toolTargetId = (tool == "move" or tool == "redraw") and targetId or nil
        RefreshAll("selection")
        gui.SetFocus(canvas)
    end

    function ctx.SetPopover(popover)
        if popover == "aids" and not OverlandMapAids.CanEdit(data.mapId) then return end
        if popover == data.popover then popover = nil end
        ctx.Transition("editor")
        if popover ~= "aids" and not (popover == nil and data.tool == "aidPlace") then ctx.ClearAid() end
        -- A scale draft lives only while Settings can take its distance.
        if popover ~= "settings" and data.tool ~= "scale" then data.scaleDraft = nil end
        data.popover = popover
        RefreshAll("selection")
    end

    -- The Party section takes the side panel's place, like the log (G1).
    function ctx.ShowParty()
        if not OverlandMapPartyPanel.Available(ctx) then return end
        ctx.Transition("selection")
        LeaveLabel()
        data.selectedId, data.selectedPathId, data.panelMode = nil, nil, "party"
        RefreshAll("selection")
    end

    function ctx.StopOnPath(pathId)
        stopCard.data.open(pathId)
    end

    function ctx.ToggleLog()
        LeaveLabel()
        if data.panelMode == "log" then
            data.panelMode = "none"
        else
            ctx.FlushEdits()
            data.selectedId, data.panelMode = nil, "log"
        end
        RefreshAll("selection")
    end

    -- Search: open the result's map (or the map itself, for a top-level result),
    -- center its pin and select it (D12b).
    function ctx.FocusLocation(id)
        local location = Model.GetLocation(id)
        if location == nil then return end
        if location.parentId == "" then
            ctx.OpenMap(location.id, "restore")
            return
        end
        if data.mapId ~= location.parentId then ctx.OpenMap(location.parentId, "restore") end
        if data.mapId ~= location.parentId then return end
        canvas:FireEvent("centerOn", location.id)
        ctx.Select(location.id, "read")
    end

    -- Leaving the map runs a host hook that destroys this panel; edits are saved first.
    local function RunHostHook(hook)
        if hook == nil or not ctx.IsAlive() then return end
        local function Continue()
            if not ctx.IsAlive() then return end
            ctx.FlushEdits()
            hook()
        end
        local importLayer = Existing("import")
        if importLayer ~= nil then importLayer.data.requestClose(Continue) else Continue() end
    end

    function ctx.ShowMenu(element, id)
        local entries = OverlandMapSidePanel.MenuEntries(ctx, id)
        if #entries == 0 then return end
        for _, entry in ipairs(entries) do
            local action = entry.click
            entry.click = function()
                element.popup = nil
                action()
            end
        end
        -- Inheriting the Overland Map rules left the menu without its theme background.
        element.popupsInheritStyles = false
        -- The opener's hover tooltip would otherwise stay drawn under the menu.
        element.tooltip = nil
        local menu = Session.ContextMenu(element, { entries = entries })
        if menu == nil then return end
        menu.vscroll = true
        menu.selfStyle.maxHeight = math.max(120, root.renderedHeight - 32)
        element.popup = menu
    end

    local function CloseConfirm()
        confirmLayer.data.onConfirm = nil
        confirmLayer.data.onAlternate = nil
        confirmLayer:SetClass("collapsed", true)
    end

    --- Ask before a destructive or outward-facing act. A compact dialog inside
    --- this window (the engine's ModalMessage fills most of the screen);
    --- Cancel or Esc closes it without running onConfirm; a second Confirm call
    --- replaces the open question, whose onConfirm then never runs.
    --- Opening it flushes valid editor fields and cancels the pointer preview.
    function ctx.Confirm(args)
        ctx.Transition("dialog")
        confirmLayer.data.onConfirm = args.onConfirm
        confirmLayer.data.onAlternate = args.onAlternate
        SetText(confirmTitle, args.title)
        SetText(confirmBody, args.message or "")
        confirmBody:SetClass("collapsed", args.message == nil or args.message == "")
        SetText(confirmOk, args.confirm)
        confirmAlternate:SetClass("collapsed", args.alternate == nil)
        SetText(confirmAlternate, args.alternate or "")
        confirmLayer:SetClass("collapsed", false)
        root.captureEscape = true
    end

    function ctx.ImportLocations()
        if not ctx.IsAlive() or OverlandMapImport.IsRunning() or not Model.IsDirector() then return end
        local map = ctx.CurrentMap()
        if map == nil or not Model.CanAdd(map.id) then return end
        local importLayer = Ensure("import")
        if importLayer ~= nil then importLayer.data.start() end
    end

    function ctx.ShowToPlayers()
        present.ShowToPlayers()
    end

    -- Chrome ------------------------------------------------------------------------------------

    -- The start of a description for a tooltip: blank lines folded, cut at a word near limit
    -- characters (never inside a multi-byte character).
    local function Preview(text, limit)
        text = text:gsub("\r", ""):gsub("\n%s*\n", "\n"):match("^%s*(.-)%s*$")
        local length = Model.TextLength(text)
        if length <= limit then return text end
        -- Malformed UTF-8 (length is huge) can only be cut by bytes.
        local finish = length < math.huge and utf8.offset(text, limit + 1) or nil
        local cut = text:sub(1, finish and finish - 1 or limit)
        return (cut:match("^(.*)%s") or cut) .. "..."
    end

    -- A Location crumb's tooltip (idea 8): its name, the start of its description, and
    -- what a click does, so the Director or a player can read a parent without leaving.
    local function CrumbTooltip(id, current)
        local location = Model.GetLocation(id)
        if location == nil then return nil end
        local details = Model.Details(id)
        local args = {
            name = Model.DisplayName(location),
            description = Preview(details ~= nil and details.description or "", C.crumbPreviewLimit),
            hint = T(current and "crumb.hint.current" or "crumb.hint.up"),
        }
        return T(args.description == "" and "crumb.hover.nameOnly" or "crumb.hover", args)
    end

    -- levelId is nil for the Atlas crumb, which has no tooltip and no right-click.
    local function Crumb(text, current, action, levelId)
        return gui.Label {
            classes = { "overlandMapCrumb", current and "current" or nil },
            text = text,
            hover = function(element)
                -- No tooltip once the side panel shows this Location: it would repeat it.
                if levelId == nil or (data.panelMode == "read" and data.selectedId == levelId) then return end
                local tooltip = CrumbTooltip(levelId, current)
                if tooltip ~= nil then Session.HoverText(element, tooltip) end
            end,
            click = function() if not mod.unloaded then action() end end,
            -- Reads the Location in the side panel; the open map stays as it is.
            rightClick = function(element)
                if levelId == nil or mod.unloaded then return end
                element.tooltip = nil
                ctx.Select(levelId, "read")
            end,
        }
    end

    local function CrumbSeparator()
        return gui.Panel { classes = { "overlandMapCrumbSep" }, bgimage = C.iconCrumb, interactable = false }
    end

    local function RefreshBreadcrumb(map)
        -- A player's path lists only the levels they can see (R4).
        local levels = {} --- @type OverlandMapLocationRecord[]
        local parts = { map ~= nil and "map" or "atlas" }
        if map ~= nil then
            for _, level in ipairs(OverlandMapReaders.Breadcrumbs(map.id)) do
                if Model.CanOpenMap(level) then
                    levels[#levels + 1] = level
                    parts[#parts + 1] = level.id .. "|" .. Model.DisplayName(level)
                end
            end
        end
        -- The crumbs are new panels, so they are built again only when the path changed.
        local key = table.concat(parts, ",")
        if key == shell.crumbKey then return end
        shell.crumbKey = key
        local children = {} --- @type Panel[]
        children[1] = Crumb(T("crumb.root"), map == nil, function() ctx.GoAtlas() end)
        for _, level in ipairs(levels) do
            children[#children + 1] = CrumbSeparator()
            local isCurrent = map ~= nil and level.id == map.id
            children[#children + 1] = Crumb(Copy.Literal(Model.DisplayName(level)), isCurrent, function()
                if isCurrent then ctx.Select(level.id, "read") else ctx.OpenMap(level.id, "up") end
            end, level.id)
        end
        breadcrumb.children = children
    end

    local function RefreshToolbar(map)
        local director = Model.IsDirector()
        local hasMap = map ~= nil
        local canAdd = false
        if hasMap then canAdd = Model.CanAdd(map.id) end
        local canLabel = hasMap and OverlandMapLabels.CanAdd(map.id)
        -- Players lose the button when the Director turns adding off (D9d).
        addButton:SetClass("collapsed", not hasMap or (not canAdd and not canLabel))
        addButton:SetClass("disabled", not canAdd and not canLabel)
        addButton:SetClass("on", data.tool == "add" or data.tool == "labelAdd")
        Session.SetIconButton(addButton, T(canLabel and (canAdd and "label.addMenu" or "label.add") or "tb.add"))
        importButton:SetClass("collapsed", not hasMap or not director)
        importButton:SetClass("disabled", not canAdd or OverlandMapImport.IsRunning())
        local importLayer = Existing("import")
        importButton:SetClass("on", importLayer ~= nil and not importLayer:HasClass("collapsed"))
        -- The Path tool: Director, point crawl maps only; it needs two pins to join (Q7).
        local crawl = hasMap and director and Model.IsPointCrawl(map)
        local enoughPins = crawl and #Model.Children(map.id) >= 2
        pathButton:SetClass("collapsed", not crawl)
        pathButton:SetClass("disabled", not enoughPins)
        pathButton:SetClass("on", data.tool == "path" or data.tool == "redraw")
        Session.SetIconButton(pathButton, T(enoughPins and "tb.path" or "tb.path.disabled"))
        lockButton:SetClass("collapsed", not hasMap)
        lockButton:SetClass("on", not data.locked)
        Session.SetIconButton(lockButton, T(data.locked and "tb.lock.on" or "tb.lock.off"),
            data.locked and C.iconLocked or C.iconUnlocked)
        searchButton:SetClass("on", data.popover == "search")
        rulerButton:SetClass("collapsed", not hasMap)
        rulerButton:SetClass("on", data.tool == "ruler")
        showButton:SetClass("collapsed", not hasMap or not director)
        viewAsButton:SetClass("collapsed", not dmhub.isDM)
        viewAsButton:SetClass("on", Model.ViewingAsPlayer())
        Session.SetIconButton(viewAsButton, T(Model.ViewingAsPlayer() and "tb.viewAs.on" or "tb.viewAs.off"))
        logButton:SetClass("on", data.panelMode == "log")
        settingsButton:SetClass("collapsed", false)
        settingsButton:SetClass("on", data.popover == "settings")
        aidsButton:SetClass("collapsed", not hasMap or not director)
        aidsButton:SetClass("on", data.popover == "aids")
    end

    local function RefreshStatus(map)
        local kind, party, location = Model.PartyStatus(map and map.id or nil)
        local args = { party = Model.PartyName() }
        local text
        if kind == "at" and location ~= nil then
            args.name = Model.DisplayName(location)
            text = T("status.at", args)
        elseif kind == "onPath" and party ~= nil then
            local path = OverlandMapPaths.Get(party.pathId)
            args.path = path ~= nil and OverlandMapPaths.ShownName(path) or T("path.type.none", nil, true)
            text = T("status.onPath", args)
        elseif kind == "traveling" then
            text = T("status.traveling", args)
        elseif kind == "elsewhere" and party ~= nil then
            local partyMap = Model.GetLocation(party.mapId)
            args.map = Model.DisplayName(partyMap)
            text = T("status.elsewhere", args)
        else
            text = T("status.none", args)
        end
        SetText(statusChip, text)
        statusChip.data.kind = kind
        statusChip.data.mapId = party ~= nil and party.mapId or nil
        -- On a point crawl map a click opens the Party section (G1).
        statusChip.data.travel = kind ~= "elsewhere" and kind ~= "none" and OverlandMapPartyPanel.Available(ctx)
        -- Wherever the Party is, a click takes the camera there.
        statusChip:SetClass("link", kind ~= "none")
        -- The chip moves left of the side panel while the panel is open.
        local inset = 8
        local key = ActiveSideKey(data.panelMode)
        local rightPanel = Existing(key)
        if key ~= nil then
            -- Bind sets the intended width before the engine's first layout (initially 100).
            local width = rightPanel and rightPanel.data.width or C.sidePanelWidth * Session.UIScale()
            local rootWidth = root.renderedWidth or 0
            if rootWidth > 0 and rootWidth < C.narrowWidth then width = rootWidth end
            inset = inset + width
        end
        -- Reading an unset selfStyle field raises, so the last value is kept in data.
        if statusChip.data.inset ~= inset then
            statusChip.data.inset = inset
            statusChip.selfStyle.rmargin = inset
        end
    end

    local function RefreshBanners(map)
        local lines = {}
        if Model.ViewingAsPlayer() then lines[#lines + 1] = T("banner.viewAs") end
        if map ~= nil and not data.locked then lines[#lines + 1] = T("chip.unlocked") end
        if data.tool == "add" then lines[#lines + 1] = T("hint.add") end
        if data.tool == "labelAdd" then lines[#lines + 1] = T("label.placeHint") end
        if map ~= nil and not OverlandMapPreferences.ShowLabels() then
            lines[#lines + 1] = T("label.hiddenLocal")
            if data.selectedLabelId ~= nil then lines[#lines + 1] = T("label.forced") end
        end
        if data.tool == "move" then
            local target = Model.GetLocation(data.toolTargetId)
            if target ~= nil then lines[#lines + 1] = T("hint.move", { name = Model.DisplayName(target) }) end
        end
        if data.tool == "ruler" then lines[#lines + 1] = T("hint.ruler") end
        if data.tool == "scale" then lines[#lines + 1] = T("set.map.scale.hint") end
        if data.tool == "aidPlace" then lines[#lines + 1] = T("aids.placeHint") end
        local pathHint = OverlandMapPathTool.Hint(ctx)
        if pathHint ~= nil then lines[#lines + 1] = pathHint end
        -- An empty point crawl map says how to start (Q21).
        if map ~= nil and Model.IsDirector() and Model.IsPointCrawl(map) and data.tool == "none"
            and #Model.Children(map.id) < 2 then
            lines[#lines + 1] = T("hint.pointcrawl.empty")
        end
        local key = table.concat(lines, "\n")
        if key == shell.bannerKey then return end
        shell.bannerKey = key
        local children = {} --- @type Panel[]
        for _, line in ipairs(lines) do
            children[#children + 1] = gui.Label { classes = { "overlandMapBanner", "sizeS" }, text = line, interactable = false }
        end
        banners.children = children
        if atlas ~= nil then atlas:FireEvent("bannerRows", #children) end
    end

    local function RefreshToast()
        local current = Undo.Current()
        local canUndo = Undo.ToastCanUndo()
        if Undo.Version() == shell.toastVersion and canUndo == shell.toastCanUndo then return end
        shell.toastVersion, shell.toastCanUndo = Undo.Version(), canUndo
        toast:SetClass("collapsed", current == nil)
        if current == nil then return end
        SetText(toastText, current.text)
        toastUndo:SetClass("collapsed", not canUndo)
        toastRetry:SetClass("collapsed", current.retry == nil)
        toastAction:SetClass("collapsed", current.action == nil)
        if current.action ~= nil then SetText(toastAction, current.action.text) end
    end

    local function EscapeLayer()
        local importLayer, logPanel = Existing("import"), Existing("log")
        if confirmLayer ~= nil and not confirmLayer:HasClass("collapsed") then return "confirm" end
        if stopCard ~= nil and not stopCard:HasClass("collapsed") then return "stop" end
        if importLayer ~= nil and not importLayer:HasClass("collapsed") then return "import" end
        if canvas ~= nil and canvas.data.hasGesture() then return "gesture" end
        if data.popover ~= nil then return "popover" end
        if data.selectedAid ~= nil then return "aid" end
        if data.tool ~= "none" then return "tool" end
        if data.panelMode == "log" and logPanel ~= nil and logPanel.data.editing then return "edit" end
        if data.panelMode == "read" or data.panelMode == "log" or data.panelMode == "path" or data.panelMode == "party" then
            return "panel"
        end
        if data.panelMode ~= "none" then return "edit" end
        if data.mapId ~= nil then return "map" end
        return nil
    end

    -- Esc goes to the map's own layers first; with none open, only the host can take it (close).
    -- A window that is not engaged (focus and pointer elsewhere) leaves Esc to the rest of Codex.
    local function SyncEscape()
        root.captureEscape = (hostMode ~= "window" or hostEngaged)
            and (EscapeLayer() ~= nil or options.close ~= nil)
    end

    -- Refresh ------------------------------------------------------------------------------------

    local function QueueRefresh(delay, domain)
        changes.Mark(domain)
        if shell.refreshScheduled or not ctx.IsAlive() then return end
        shell.refreshScheduled = true
        root:ScheduleEvent("overlandMapRefresh", delay or C.refreshDelay)
    end

    RefreshAll = function(domain)
        if domain ~= false then changes.Mark(domain) end
        if not ctx.IsAlive() then return end
        if shell.refreshing then
            shell.refreshPending = true
            return
        end
        local dirty = changes.Take()
        local function Needs(...)
            if dirty.all or dirty.permissions then return true end
            for _, name in ipairs({ ... }) do if dirty[name] then return true end end
            return false
        end
        shell.refreshing = true
        shell.refreshPending = false
        local ok, message = pcall(function()
            -- Drop what the viewer can no longer see: a deleted or unshared map, a
            -- hidden selection, a Move tool whose Location is gone.
            local map = ctx.CurrentMap()
            if data.mapId ~= nil and map == nil then
                dirty.permissions = true
                data.mapId = nil
                canvas:FireEvent("showMap", "restore")
            end
            if data.selectedId ~= nil and Model.GetLocation(data.selectedId) == nil then
                dirty.permissions = true
                data.selectedId, data.panelMode = nil, "none"
            end
            if ActiveSideKey(data.panelMode) == "location" and data.selectedId == nil then data.panelMode = "none" end
            if data.selectedLabelId ~= nil then
                local row = OverlandMapLabels.Snapshot(data.selectedLabelId)
                if row == nil or map == nil or row.mapId ~= map.id then
                    OverlandMapLabels.CancelPending(data.selectedLabelId)
                    data.selectedLabelId = nil
                    if data.panelMode == "labelEdit" then data.panelMode = "none" end
                    canvas:FireEvent("cancelGesture")
                elseif data.panelMode == "labelEdit" and not OverlandMapLabels.CanEdit(row) then
                    OverlandMapLabels.CancelPending(row.id)
                    data.panelMode = "none"
                    canvas:FireEvent("cancelGesture")
                end
            end
            if data.panelMode == "labelEdit" and data.selectedLabelId == nil then data.panelMode = "none" end
            -- A path that was deleted, hidden from this viewer, or left behind on another map.
            if data.panelMode == "path" or data.panelMode == "pathEdit" then
                local path = OverlandMapPaths.Get(data.selectedPathId)
                if path == nil or map == nil or path.mapId ~= map.id then
                    data.selectedPathId, data.panelMode = nil, "none"
                elseif data.panelMode == "pathEdit" and not Model.IsDirector() then
                    data.panelMode = "path"
                end
            end
            -- Connect to... joins pins of the open map only, and only the Director's.
            if data.panelMode == "pickPathEnd" then
                local from = Model.GetLocation(data.selectedId)
                if from == nil or not OverlandMapPathPanel.CanConnect(ctx, from) then
                    data.panelMode = from ~= nil and "read" or "none"
                end
            end
            -- The Party section follows the Party: it closes when the Party leaves the open point crawl map.
            if data.panelMode == "party" and not OverlandMapPartyPanel.Available(ctx) then data.panelMode = "none" end
            if data.tool == "move" and Model.GetLocation(data.toolTargetId) == nil then data.tool = "none" end
            if data.tool == "add" and (map == nil or not Model.CanAdd(map.id)) then data.tool = "none" end
            if data.tool == "labelAdd" and (map == nil or not OverlandMapLabels.CanAdd(map.id)) then data.tool = "none" end
            if (data.tool == "ruler" or data.tool == "scale") and map == nil then data.tool = "none" end
            if data.tool == "scale" and not Model.IsDirector() then data.tool = "none" end
            -- Path tools need the Director on a point crawl map; Redraw line also its path.
            if (data.tool == "path" or data.tool == "redraw")
                and (map == nil or not Model.IsDirector() or not Model.IsPointCrawl(map)) then
                data.tool = "none"
            end
            if data.tool == "redraw" and OverlandMapPaths.Get(data.toolTargetId) == nil then data.tool = "none" end
            if data.tool ~= "path" and data.tool ~= "redraw" then data.pathDraft = nil end
            if data.selectedAid and (map == nil or data.aidMapId ~= map.id or not Model.IsDirector()
                or OverlandMapAids.Snapshot(map, data.selectedAid) == nil) then ctx.ClearAid() end

            local _, created = Ensure(ActiveSideKey(data.panelMode))
            if created then dirty.selection = true end

            -- An open panel covers the map's right edge; the camera may pan that far further,
            -- so a pin under it can be reached even at fit. A narrow window's panel covers all.
            local inset = 0
            local rootWidth = root.renderedWidth or 0
            if data.panelMode ~= "none" and not (rootWidth > 0 and rootWidth < C.narrowWidth) then
                inset = C.sidePanelWidth * Session.UIScale()
            end
            if data.panelInset ~= inset then
                data.panelInset = inset
                canvas:FireEvent("relayout")
            end

            canvas:SetClass("collapsed", map == nil)
            atlas:SetClass("collapsed", map ~= nil)
            if map == nil then
                if Needs("records", "party", "assets", "layout", "preferences") then atlas:FireEvent("bind") end
            elseif Needs("records", "party", "assets", "selection", "preferences", "layout") then canvas:FireEvent("bind") end
            if Needs("records", "selection", "assets", "layout", "party") then
                BindExisting("location")
                BindExisting("path")
                BindExisting("label")
            end
            local artworkReader = OverlandMapArtwork.ActiveReader(ctx)
            local labelTool = data.tool == "labelAdd" or data.tool == "aidPlace"
            if canvas.data.artworkReader ~= artworkReader or canvas.data.labelTool ~= labelTool then
                canvas.data.artworkReader = artworkReader
                canvas.data.labelTool = labelTool
                canvas.inputEvents = (artworkReader ~= nil or labelTool) and { "enter" } or {}
            end
            if Needs("records", "selection", "party", "layout") then BindExisting("party") end
            if Needs("records", "selection", "party", "layout", "preferences") then BindExisting("log") end
            if Needs("records", "selection", "preferences", "assets", "layout") then popovers:FireEvent("bind") end
            if Needs("records", "selection", "layout") then BindExisting("import") end
            if Needs("records", "selection", "layout") then RefreshBreadcrumb(map) end
            RefreshToolbar(map)
            RefreshStatus(map)
            RefreshBanners(map)
            RefreshToast()
            SyncEscape()
        end)
        local pending = shell.refreshPending
        shell.refreshing = false
        shell.refreshPending = false
        if ok and pending then QueueRefresh(0.01, "selection") end
        if not ok then error(message) end
    end
    ctx.RefreshAll = RefreshAll
    function ctx.Refresh(domain) RefreshAll(domain) end

    -- Components ---------------------------------------------------------------------------------

    present = OverlandMapPresent.Create(ctx)
    -- Enter on the focused canvas: Add label places at the view's center, else the open image reader opens.
    -- Input events follow focus; selecting a pin or path leaves focus on the canvas.
    function ctx.HandleEnter(element)
        if element.hasFocus and (data.tool == "labelAdd" or data.tool == "aidPlace") then
            OverlandMapCanvasTools.PlaceAt(ctx, Model.Clamp(data.camera.centerX, 0, 1), Model.Clamp(data.camera.centerY, 0, 1))
            return
        end
        local reader = element.data.artworkReader
        if ctx.IsAlive() and reader ~= nil and reader.valid then reader:FireEvent("enter") end
    end
    canvas = OverlandMapCanvas.Create(ctx)
    atlas = OverlandMapAtlas.Create(ctx)
    OverlandMapLabels.SetSavedListener(OverlandMapPreferences.RememberLabelFormat)
    local function Slot(key, factory)
        local slot = gui.Panel { width = "100%", height = "100%", flow = "none", floating = true, interactable = false }
        components[key] = { factory = function() return factory(ctx) end, slot = slot }
        return slot
    end
    local locationSlot = Slot("location", OverlandMapSidePanel.Create)
    local pathSlot = Slot("path", OverlandMapPathPanel.Create)
    local labelSlot = Slot("label", OverlandMapLabelPanel.Create)
    local partySlot = Slot("party", OverlandMapPartyPanel.Create)
    local logSlot = Slot("log", OverlandMapLogPanel.Create)
    popovers = OverlandMapPopovers.Create(ctx)
    local importSlot = Slot("import", OverlandMapImport.Create)
    stopCard = OverlandMapPartyPanel.CreateStopCard(ctx)

    breadcrumb = gui.Panel { id = "overland-map-breadcrumb", classes = { "overlandMapBreadcrumb" }, floating = true }

    searchButton = Session.IconButton("overland-map-search", C.iconSearch, T("label.search"), function()
        ctx.SetPopover("search")
    end)
    addButton = Session.IconButton("overland-map-add", C.iconAdd, T("tb.add"), function(element)
        local map = ctx.CurrentMap()
        if map == nil then return end
        local location, label = Model.CanAdd(map.id), OverlandMapLabels.CanAdd(map.id)
        if location and label then
            element.popup = Session.ContextMenu(element, { entries = {
                { text = T("tb.add"), click = function() element.popup = nil; ctx.SetTool("add") end },
                { text = T("label.add"), click = function() element.popup = nil; ctx.SetTool("labelAdd") end },
            } })
        elseif label then ctx.SetTool("labelAdd") elseif location then ctx.SetTool("add") end
    end)
    importButton = Session.IconButton("overland-map-import-button", C.iconImport, T("tb.import"), function()
        ctx.ImportLocations()
    end)
    pathButton = Session.IconButton("overland-map-path", C.iconPath, T("tb.path"), function()
        -- From Redraw line this switches to the Path tool; pressed again, it turns the tool off.
        ctx.SetTool("path")
    end)
    rulerButton = Session.IconButton("overland-map-ruler", C.iconRuler, T("tb.ruler"), function()
        ctx.SetTool("ruler")
    end)
    logButton = Session.IconButton("overland-map-log", C.iconLog, T("tb.log"), function()
        ctx.ToggleLog()
    end)
    popOutButton = Session.IconButton("overland-map-pop-out", C.iconPopOut, T("tb.popOut"), function()
        RunHostHook(options.popOut)
    end, { "overlandMapHostControl" })
    popOutButton:SetClass("collapsed", options.popOut == nil)
    popInButton = Session.IconButton("overland-map-pop-in", C.iconPopIn, T("tb.popIn"), function()
        RunHostHook(options.popIn)
    end, { "overlandMapHostControl" })
    popInButton:SetClass("collapsed", options.popIn == nil)
    closeButton = Session.IconButton("overland-map-close", C.iconClose, T("tb.close"), function()
        RunHostHook(options.close)
    end, { "overlandMapHostControl" })
    closeButton:SetClass("collapsed", options.close == nil or hostMode == "window")
    viewButton = Session.IconButton("overland-map-view", C.iconWindow, T("tb.window"), function()
        if ctx.IsAlive() and options.toggleView ~= nil then options.toggleView() end
    end, { "overlandMapHostControl" })
    viewButton:SetClass("collapsed", options.toggleView == nil)
    settingsButton = Session.IconButton("overland-map-settings", C.iconSettings, T("tb.settings"), function()
        ctx.SetPopover("settings")
    end)
    aidsButton = Session.IconButton("overland-map-aids", "phosphor/compass.png", T("aids.title"), function()
        ctx.SetPopover("aids")
    end)
    lockButton = Session.IconButton("overland-map-lock", C.iconLocked, T("tb.lock.on"), function()
        canvas:FireEvent("cancelGesture")
        data.locked = not data.locked
        RefreshAll()
    end)
    showButton = Session.IconButton("overland-map-show", C.iconShow, T("tb.show"), function()
        ctx.ShowToPlayers()
    end)
    viewAsButton = Session.IconButton("overland-map-view-as", C.iconViewAs, T("tb.viewAs.off"), function()
        Model.SetViewAsPlayer(not Model.ViewingAsPlayer())
        data.tool, data.toolTargetId = "none", nil
        RefreshAll()
    end)
    local toolbar = gui.Panel {
        id = "overland-map-toolbar", classes = { "overlandMapToolbar" }, floating = true,
        -- Creation actions stay together; host controls end the row.
        searchButton, addButton, importButton, pathButton, lockButton, rulerButton, showButton, viewAsButton, logButton,
        rendered = function(_, width)
            if type(width) == "number" and width > 0 then
                breadcrumb.selfStyle.maxWidth = string.format("100%%-%d", math.ceil(width + C.chromeInset * 3))
            end
        end,
        aidsButton, settingsButton, viewButton, popOutButton, popInButton, closeButton,
    }

    statusChip = gui.Label {
        id = "overland-map-status", classes = { "overlandMapStatus", "sizeS" }, floating = true, text = "",
        data = { kind = "none", mapId = nil, travel = false },
        hover = function(element)
            if element.data.kind == "none" then
                if Model.IsDirector() then gui.Tooltip(T("status.none.hint"))(element) end
            else
                gui.Tooltip(T("status.elsewhere.tooltip"))(element)
            end
        end,
        -- Goes to the Party: opens its map when it is elsewhere, then eases the camera onto
        -- it. On a point crawl map it also opens the Party section with Travel to (G1),
        -- first, so the camera centers in the part of the map the section leaves visible.
        click = function(element)
            local kind = element.data.kind
            if kind == "none" then return end
            if kind == "elsewhere" then
                if element.data.mapId == nil then return end
                ctx.OpenMap(element.data.mapId, "restore")
            elseif element.data.travel then
                ctx.ShowParty()
            end
            canvas:FireEvent("centerOnParty")
        end,
    }
    banners = gui.Panel { classes = { "overlandMapBanners" }, floating = true, interactable = false }

    toastText = gui.Label { classes = { "overlandMapToastText", "sizeS" }, text = "", interactable = false }
    toastUndo = gui.Label {
        classes = { "overlandMapToastButton", "sizeS" }, text = T("toast.undo"),
        click = function()
            local current = Undo.Current()
            if current ~= nil and current.entry ~= nil then
                Undo.Undo(current.entry, function() if ctx.IsAlive() then RefreshAll() end end)
            end
        end,
    }
    toastRetry = gui.Label {
        classes = { "overlandMapToastButton", "collapsed", "sizeS" }, text = T("toast.retry"),
        click = function()
            local current = Undo.Current()
            if current ~= nil and current.retry ~= nil then
                Undo.Dismiss()
                current.retry()
            end
        end,
    }
    toastAction = gui.Label {
        classes = { "overlandMapToastButton", "collapsed", "sizeS" }, text = "",
        click = function()
            local current = Undo.Current()
            if current ~= nil and current.action ~= nil then
                Undo.Dismiss()
                current.action.click()
            end
        end,
    }
    toast = gui.Panel {
        id = "overland-map-toast", classes = { "overlandMapToast", "collapsed" }, floating = true,
        hover = function() Undo.SetPaused(true) end,
        dehover = function() Undo.SetPaused(false) end,
        toastText, toastUndo, toastRetry, toastAction,
    }

    -- Built once and reused (see ctx.Confirm); the dim layer swallows clicks to the map below.
    confirmTitle = gui.Label { classes = { "overlandMapConfirmTitle", "sizeL" }, text = "", interactable = false }
    confirmBody = gui.Label { classes = { "overlandMapConfirmBody", "sizeS" }, text = "", interactable = false }
    confirmOk = gui.Button {
        id = "overland-map-confirm-ok", classes = { "overlandMapButton", "sizeS" }, text = "",
        click = function()
            local action = confirmLayer.data.onConfirm
            CloseConfirm()
            if action ~= nil and not mod.unloaded then action() end
        end,
    }
    -- Only some questions have a second way to go on (W1); it hides otherwise.
    confirmAlternate = gui.Button {
        id = "overland-map-confirm-alternate", classes = { "overlandMapButton", "sizeS", "collapsed" }, text = "",
        click = function()
            local action = confirmLayer.data.onAlternate
            CloseConfirm()
            if action ~= nil and not mod.unloaded then action() end
        end,
    }
    confirmLayer = gui.Panel {
        id = "overland-map-confirm", classes = { "overlandMapConfirmLayer", "collapsed" }, floating = true,
        swallowPress = true, data = { onConfirm = nil, onAlternate = nil },
        gui.Panel {
            classes = { "overlandMapConfirm" },
            confirmTitle,
            confirmBody,
            gui.Panel {
                classes = { "overlandMapConfirmButtons" },
                confirmOk,
                confirmAlternate,
                gui.Button {
                    id = "overland-map-confirm-cancel", classes = { "overlandMapButton", "sizeS" }, text = T("dlg.cancel"),
                    click = function() CloseConfirm() end,
                },
            },
        },
    }

    root = gui.Panel {
        id = "overland-map-panel",
        classes = { "overlandMapRoot" },
        styles = ThemeEngine.MergeStyles(Styles.Build()),
        popupsInheritStyles = true,
        thinkTime = C.rootThink,
        escapePriority = hostMode == "fullscreen" and FULLSCREEN_PRIORITY or WINDOW_PRIORITY,
        monitorAssets = MonitoredTables(C.locationTableName, C.labelTableName, C.detailsTableName, C.notesTableName, C.logTableName,
            C.pathTableName),
        monitorGame = { Model.StatePath(), GameHud.PresentDialogPath() },
        data = {},
        press = function(element)
            if element:GetMouseButton(0) then Session.CloseContextMenu() end
        end,
        create = function(element)
            Styles.Subscribe(element)
            element.data.recordsSubscription = OverlandMapRecords.Observe(function()
                if ctx.IsAlive() then ctx.Transition("reconcile"); QueueRefresh(nil, "records") end
            end)
            -- Every viewer opens on their last map (D13c); otherwise the first map, else the Atlas.
            local last = Model.GetLocation(OverlandMapPreferences.LastMapId())
            if last == nil or not Model.CanOpenMap(last) then last = Model.TopLevel()[1] end
            if last ~= nil then
                data.mapId = last.id
                canvas:FireEvent("showMap", "restore")
            end
            RefreshAll()
            present.Receive()
            OverlandMapLog.EnforceCap()
        end,
        requestClose = function(_, continue) RunHostHook(continue) end,
        overlandMapHostMode = function(element, mode)
            ctx.Transition("resize")
            hostMode = mode
            element.escapePriority = mode == "fullscreen" and FULLSCREEN_PRIORITY or WINDOW_PRIORITY
            closeButton:SetClass("collapsed", options.close == nil or mode == "window")
            Session.SetIconButton(viewButton, T(mode == "window" and "tb.fullscreen" or "tb.window"),
                mode == "window" and C.iconFullscreen or C.iconWindow)
            QueueRefresh(0.01, "layout")
            SyncEscape()
        end,
        overlandMapHostActive = function(_, engaged)
            hostEngaged = engaged
            if not engaged then ctx.Transition("resize") end
            SyncEscape()
        end,
        rendered = function() ctx.Transition("resize"); QueueRefresh(0.01, "layout") end,
        destroy = function(element)
            shell.destroying = true
            ctx.FlushEdits()
            if element.data.recordsSubscription then element.data.recordsSubscription() end
            owner:Destroy()
            ctx.ClearAid()
            Model.SetViewAsPlayer(false)
            Styles.Unsubscribe(element)
        end,
        -- Another client changed one of our tables: mark the data changed, whatever
        -- the engine's table counter did, so no cache serves the old rows.
        refreshAssets = function()
            Model.InvalidateIndex()
            ctx.Transition("reconcile")
            QueueRefresh(nil, "records")
        end,
        refreshGame = function()
            ctx.Transition("reconcile")
            present.Receive()
            QueueRefresh(nil, "party")
        end,
        overlandMapRefresh = function()
            shell.refreshScheduled = false
            RefreshAll(false)
        end,
        think = function()
            if not ctx.IsAlive() then return end
            if shell.director ~= dmhub.isDM then
                ctx.Transition("permission")
                shell.director = dmhub.isDM
                Model.SetViewAsPlayer(false)
                RefreshAll()
            end
            present.Receive()
            RefreshToast()
            SyncEscape()
        end,
        -- Esc order (R2): stop the tool -> leave edit mode -> close the panel -> go up a level,
        -- and at the Atlas close the fullscreen map (a window closes itself there instead).
        escape = function()
            local layer = EscapeLayer()
            if layer == "gesture" then
                canvas:FireEvent("cancelGesture")
            elseif layer == "confirm" then
                CloseConfirm()
            elseif layer == "stop" then
                stopCard.data.close()
            elseif layer == "import" then
                local importLayer = Existing("import")
                if importLayer ~= nil then importLayer.data.close() end
            elseif layer == "popover" then
                ctx.SetPopover(nil)
            elseif layer == "aid" then
                ctx.ClearAid()
                RefreshAll()
            elseif layer == "tool" then
                canvas:FireEvent("cancelGesture")
                -- The Path tool's first Esc drops the line being drawn and keeps the tool (Q7).
                if not OverlandMapPathTool.Escape(ctx) then ctx.SetTool("none") end
            elseif layer == "edit" and data.panelMode == "log" then
                local logPanel = Existing("log")
                if logPanel ~= nil then logPanel:FireEvent("closeEditor") end
            elseif layer == "edit" and data.panelMode == "pathEdit" then
                ctx.SelectPath(data.selectedPathId, "path")
            elseif layer == "edit" and data.panelMode == "labelEdit" then
                ctx.SelectLabel(nil)
            elseif layer == "edit" then
                ctx.Select(data.selectedId, "read")
            elseif layer == "panel" and data.panelMode == "log" then
                ctx.ToggleLog()
            elseif layer == "panel" and data.panelMode == "path" then
                ctx.SelectPath(nil)
            elseif layer == "panel" and data.panelMode == "party" then
                data.panelMode = "none"
                RefreshAll()
            elseif layer == "panel" then
                ctx.Select(nil, nil)
            elseif layer == "map" then
                ctx.GoUp()
            else
                RunHostHook(options.close)
            end
        end,

        canvas, atlas, breadcrumb, toolbar, banners, statusChip, locationSlot, pathSlot, labelSlot, partySlot, logSlot, popovers,
        toast, importSlot, stopCard, confirmLayer,
    }
    ctx.root = root
    return root
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function OverlandMapPanel.Styles()
    return {
        {
            selectors = { "overlandMapRoot" },
            width = "100%",
            height = "100%",
            minWidth = 0,
            minHeight = 0,
            flow = "none",
            bgimage = true,
            bgcolor = "@bgAlt",
        },
        OverlandMapStyles.Chrome("overlandMapBreadcrumb", {
            width = "auto",
            height = C.breadcrumbHeight,
            -- The toolbar's rendered width supplies the final clearance.
            maxWidth = "35%",
            flow = "horizontal",
            halign = "left",
            valign = "top",
            lmargin = C.chromeInset,
            tmargin = C.chromeInset,
            hpad = 10,
            borderBox = true,
        }),
        {
            selectors = { "overlandMapCrumb" },
            width = "auto",
            height = "auto",
            maxWidth = 220,
            valign = "center",
            color = "@fg",
            textWrap = false,
            textOverflow = "ellipsis",
        },
        {
            selectors = { "overlandMapCrumb", "hover" },
            color = "@fgStrong",
            transitionTime = 0.1,
        },
        {
            selectors = { "overlandMapCrumb", "current" },
            color = "@fgStrong",
            bold = true,
        },
        {
            selectors = { "overlandMapCrumbSep" },
            width = 10,
            height = 10,
            valign = "center",
            hmargin = 6,
            bgcolor = "@fgMuted",
        },
        OverlandMapStyles.Chrome("overlandMapToolbar", {
            width = "auto",
            height = C.chromeBarHeight,
            flow = "horizontal",
            halign = "right",
            valign = "top",
            rmargin = C.chromeInset,
            tmargin = C.chromeInset,
            hpad = 3,
            borderBox = true,
        }),
        OverlandMapStyles.Chrome("overlandMapCameraControls", {
            width = "auto",
            height = C.chromeBarHeight,
            flow = "horizontal",
            halign = "left",
            valign = "bottom",
            lmargin = C.chromeInset,
            bmargin = C.chromeInset,
            hpad = 3,
            borderBox = true,
            opacity = 1,
            transitionTime = 0.3,
        }),
        {
            selectors = { "overlandMapCameraControls", "faded" },
            opacity = 0.55,
            transitionTime = 0.6,
        },
        OverlandMapStyles.Chrome("overlandMapStatus", {
            width = "auto",
            height = "auto",
            maxWidth = 360,
            halign = "right",
            valign = "bottom",
            rmargin = 8,
            bmargin = 8,
            hpad = 10,
            vpad = 6,
            borderBox = true,
            color = "@fgStrong",
            textWrap = false,
        }),
        {
            selectors = { "overlandMapStatus", "link" },
            color = "@accent",
        },
        {
            selectors = { "overlandMapStatus", "link", "hover" },
            color = "@accentHover",
        },
        {
            selectors = { "overlandMapBanners" },
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            lmargin = 8,
            tmargin = 48,
        },
        OverlandMapStyles.Chrome("overlandMapBanner", {
            width = "auto",
            height = "auto",
            maxWidth = 460,
            halign = "left",
            bmargin = 4,
            hpad = 10,
            vpad = 5,
            borderBox = true,
            borderColor = "@accent",
            color = "@fgStrong",
            textWrap = true,
        }),
        OverlandMapStyles.Chrome("overlandMapToast", {
            width = "auto",
            height = "auto",
            minHeight = 38,
            maxWidth = "80%",
            flow = "horizontal",
            halign = "center",
            valign = "bottom",
            bmargin = C.belowChromeBar,
            hpad = 12,
            vpad = 4,
            borderBox = true,
            borderColor = "@fgMuted",
        }),
        {
            selectors = { "overlandMapToastText" },
            width = "auto",
            height = "auto",
            maxWidth = 420,
            valign = "center",
            color = "@fgStrong",
            textWrap = true,
        },
        {
            selectors = { "overlandMapToastButton" },
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 14,
            bold = true,
            color = "@accent",
        },
        {
            selectors = { "overlandMapToastButton", "hover" },
            color = "@accentHover",
        },
    }
end
