local mod = dmhub.GetModLoading()

--- The Region Map window content (V2 shell): the canvas fills the window and
--- everything else floats over it - breadcrumb, toolbar, banners, Party status,
--- toasts and the side panel (brief section 4). The shell owns navigation,
--- selection, the active tool, Esc order (R2) and refresh routing; components
--- get a RegionMapContext and are driven by events.
--- @class RegionMapPanel: GameType
--- @field new fun(o?: table): RegionMapPanel
RegionMapPanel = RegisterGameType("RegionMapPanel")
local C = RegionMapConstants
local Model = RegionMapModel
local Styles = RegionMapStyles
local Session = RegionMapSession
local Copy = RegionMapCopy
local Undo = RegionMapUndo

local T = Copy.T
local SetText = Session.SetText

local escapePriorities = rawget(_G, "EscapePriority") or {}
local ESCAPE_PRIORITY = (escapePriorities.EXIT_DIALOG or 0) + 0.5

-- monitorAssets accepts data table names too; the stub types it as the
-- built-in asset kinds only, so the list is returned untyped.
--- @return any
local function MonitoredTables(...)
    return { ... }
end

--- Build the Region Map content panel.
--- Host hooks from RegionMap.lua. Expand hooks are absent or answer false
--- where the host cannot resize the window (native popouts, pinned windows).
--- @class RegionMapHostOptions
--- @field fitHost nil|fun(root: Panel)
--- @field canExpand nil|fun(root: Panel): boolean
--- @field isExpanded nil|fun(root: Panel): boolean
--- @field toggleExpand nil|fun(root: Panel)

--- @param options nil|RegionMapHostOptions
--- @return Panel
function RegionMapPanel.Create(options)
    options = options or {}
    --- @type RegionMapShellData
    local data = {
        mapId = nil, selectedId = nil, panelMode = "none", pickKind = nil,
        locked = true, tool = "none", toolTargetId = nil,
        camera = { zoom = C.minZoom, centerX = 0.5, centerY = 0.5 },
        focusName = false, popover = nil, ruler = nil, scaleDraft = nil, expanded = false,
    }
    -- The service functions are attached below, before any component is built.
    ---@diagnostic disable-next-line: missing-fields
    local ctx = { data = data } --[[@as RegionMapContext]]

    local root
    local canvas
    local atlas
    local sidePanel
    local logPanel
    local popovers
    local present
    local breadcrumb
    local searchButton
    local addButton
    local lockButton
    local rulerButton
    local showButton
    local viewAsButton
    local logButton
    local expandButton
    local settingsButton
    local statusChip
    local banners
    local toast
    local toastText
    local toastUndo
    local toastRetry
    local confirmLayer
    local confirmTitle
    local confirmBody
    local confirmOk
    local shell = {
        refreshScheduled = false, refreshing = false, refreshPending = false,
        toastVersion = -1, toastCanUndo = nil, director = dmhub.isDM,
        transition = nil, -- set while Open map zooms into a pin; other map changes wait for it
    }

    local RefreshAll

    function ctx.IsAlive()
        return not mod.unloaded and root ~= nil and root.valid
    end

    function ctx.CurrentMap()
        local map = Model.GetLocation(data.mapId)
        if map == nil or not Model.CanOpenMap(map) then return nil end
        return map
    end

    function ctx.FlushEdits()
        if sidePanel ~= nil and sidePanel.valid then sidePanel:FireEvent("flush") end
    end

    -- A failed write says so in a toast; refusals the UI already prevents stay silent.
    function ctx.Report(ok, reason)
        if ok then return true end
        if reason == "limit" then Undo.Notify("limit.locations")
        elseif reason == "invalid" or reason == "unavailable" then Undo.Notify("toast.saveFailed") end
        return false
    end

    function ctx.Push(entry, copyId, args)
        Undo.Push(entry, copyId, args)
    end

    -- Navigation ---------------------------------------------------------------------------------

    local function ApplyOpen(map, how)
        data.mapId = map.id
        data.locked = true
        data.tool, data.toolTargetId = "none", nil
        data.ruler, data.scaleDraft = nil, nil
        -- The log panel stays open: its entries open their maps.
        if data.panelMode ~= "log" then data.selectedId, data.panelMode = nil, "none" end
        Session.SaveLastMap(map.id)
        canvas:FireEvent("showMap", how)
        RefreshAll()
        gui.SetFocus(canvas)
    end

    --- Open a map. "down" (Open map) first zooms into the pin (D8c).
    function ctx.OpenMap(id, how)
        local map = Model.GetLocation(id)
        if map == nil or not Model.CanOpenMap(map) or shell.transition ~= nil then return end
        ctx.FlushEdits()
        if how == "down" and data.mapId ~= nil and map.parentId == data.mapId and not Session.ReduceMotion() then
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
        ctx.FlushEdits()
        shell.transition = nil
        data.mapId = nil
        data.tool, data.toolTargetId = "none", nil
        data.ruler, data.scaleDraft = nil, nil
        -- The log panel stays open on the Atlas; a Location panel has nothing to show there.
        if data.panelMode ~= "log" then data.selectedId, data.panelMode = nil, "none" end
        canvas:FireEvent("showMap", "restore")
        RefreshAll()
    end

    -- Up one level; a player skips levels they cannot open (R4).
    function ctx.GoUp()
        local map = ctx.CurrentMap()
        if map == nil then return end
        local path = Model.Ancestors(map.id)
        for i = #path - 1, 1, -1 do
            if Model.CanOpenMap(path[i]) then
                ctx.OpenMap(path[i].id, "up")
                return
            end
        end
        ctx.GoAtlas()
    end

    function ctx.Select(id, mode)
        local leaving = data.selectedId ~= id or (data.panelMode == "edit" and mode ~= "edit")
        if leaving then ctx.FlushEdits() end
        if id == nil or Model.GetLocation(id) == nil then
            data.selectedId, data.panelMode = nil, "none"
        else
            data.selectedId, data.panelMode = id, mode or "read"
        end
        RefreshAll()
        if data.selectedId ~= nil then
            -- The panel has not laid out yet on its first open, so use its intended width.
            canvas:FireEvent("keepVisible", data.selectedId, C.sidePanelWidth * Session.UIScale())
        end
    end

    local tools = { add = true, move = true, ruler = true, scale = true }

    function ctx.SetTool(tool, targetId)
        if not tools[tool] then tool = "none" end
        -- Pressing the active tool's button again turns it off.
        if tool == data.tool and targetId == data.toolTargetId then tool = "none" end
        -- Measurements are local and go when the ruler does; a scale draft with
        -- both points waits for its distance in Settings.
        if tool ~= "ruler" then data.ruler = nil end
        local draft = data.scaleDraft
        if tool ~= "scale" and draft ~= nil and draft.u2 == nil then data.scaleDraft = nil end
        data.tool = tool
        data.toolTargetId = tool == "move" and targetId or nil
        RefreshAll()
        gui.SetFocus(canvas)
    end

    function ctx.SetPopover(popover)
        if popover == data.popover then popover = nil end
        -- A scale draft lives only while Settings can take its distance.
        if popover ~= "settings" and data.tool ~= "scale" then data.scaleDraft = nil end
        data.popover = popover
        RefreshAll()
    end

    function ctx.ToggleLog()
        if data.panelMode == "log" then
            data.panelMode = "none"
        else
            ctx.FlushEdits()
            data.selectedId, data.panelMode = nil, "log"
        end
        RefreshAll()
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

    function ctx.CanExpand()
        return options.canExpand ~= nil and ctx.IsAlive() and options.canExpand(root)
    end

    function ctx.ToggleExpand()
        if not ctx.CanExpand() or options.toggleExpand == nil then return end
        options.toggleExpand(root)
        RefreshAll()
    end

    function ctx.ShowMenu(element, id)
        local entries = RegionMapSidePanel.MenuEntries(ctx, id)
        if #entries == 0 then return end
        for _, entry in ipairs(entries) do
            local action = entry.click
            entry.click = function()
                element.popup = nil
                action()
            end
        end
        -- Inheriting the Region Map rules left the menu without its theme background.
        element.popupsInheritStyles = false
        -- The opener's hover tooltip would otherwise stay drawn under the menu.
        element.tooltip = nil
        element.popup = gui.ContextMenu { entries = entries }
    end

    local function CloseConfirm()
        confirmLayer.data.onConfirm = nil
        confirmLayer:SetClass("collapsed", true)
    end

    --- Ask before a destructive or outward-facing act. A compact dialog inside
    --- this window (the engine's ModalMessage fills most of the screen);
    --- Cancel, Esc or a second Confirm call closes it without running onConfirm.
    function ctx.Confirm(args)
        confirmLayer.data.onConfirm = args.onConfirm
        SetText(confirmTitle, args.title)
        SetText(confirmBody, args.message or "")
        confirmBody:SetClass("collapsed", args.message == nil or args.message == "")
        SetText(confirmOk, args.confirm)
        confirmLayer:SetClass("collapsed", false)
        root.captureEscape = true
    end

    function ctx.ShowToPlayers()
        present.ShowToPlayers()
    end

    -- Chrome ------------------------------------------------------------------------------------

    -- The start of a description for a tooltip: blank lines folded, cut at a word near limit.
    local function Preview(text, limit)
        text = text:gsub("\r", ""):gsub("\n%s*\n", "\n"):match("^%s*(.-)%s*$")
        if #text <= limit then return text end
        local cut = text:sub(1, limit)
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
            classes = { "regionMapCrumb", current and "current" or nil },
            text = text,
            hover = function(element)
                -- No tooltip once the side panel shows this Location: it would repeat it.
                if levelId == nil or (data.panelMode == "read" and data.selectedId == levelId) then return end
                local tooltip = CrumbTooltip(levelId, current)
                if tooltip ~= nil then gui.Tooltip(tooltip)(element) end
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
        return gui.Panel { classes = { "regionMapCrumbSep" }, bgimage = C.iconCrumb, interactable = false }
    end

    local function RefreshBreadcrumb(map)
        local children = {} --- @type Panel[]
        children[1] = Crumb(T("crumb.root"), map == nil, function() ctx.GoAtlas() end)
        if map ~= nil then
            for _, level in ipairs(Model.Ancestors(map.id)) do
                -- A player's path lists only the levels they can see (R4).
                if Model.CanOpenMap(level) then
                    children[#children + 1] = CrumbSeparator()
                    local isCurrent = level.id == map.id
                    children[#children + 1] = Crumb(Copy.Literal(Model.DisplayName(level)), isCurrent, function()
                        if isCurrent then ctx.Select(level.id, "read") else ctx.OpenMap(level.id, "up") end
                    end, level.id)
                end
            end
        end
        breadcrumb.children = children
    end

    local function RefreshToolbar(map)
        local director = Model.IsDirector()
        local hasMap = map ~= nil
        local canAdd, reason = false, nil
        if hasMap then canAdd, reason = Model.CanAdd(map.id) end
        -- Players lose the button when the Director turns adding off (D9d).
        addButton:SetClass("collapsed", not hasMap or (not canAdd and reason == "permission"))
        addButton:SetClass("disabled", not canAdd)
        addButton:SetClass("on", data.tool == "add")
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
        data.expanded = options.isExpanded ~= nil and options.isExpanded(root)
        expandButton:SetClass("collapsed", not ctx.CanExpand())
        expandButton:SetClass("on", data.expanded)
        Session.SetIconButton(expandButton, T(data.expanded and "tb.expand.on" or "tb.expand.off"),
            data.expanded and C.iconRestore or C.iconExpand)
        settingsButton:SetClass("collapsed", not director)
        settingsButton:SetClass("on", data.popover == "settings")
    end

    local function RefreshStatus(map)
        local kind, party, location = Model.PartyStatus(map and map.id or nil)
        local args = { party = Model.PartyName() }
        local text
        if kind == "at" and location ~= nil then
            args.name = Model.DisplayName(location)
            text = T("status.at", args)
        elseif kind == "traveling" then
            text = T("status.traveling", args)
        elseif kind == "elsewhere" and party ~= nil then
            local partyMap = Model.GetLocation(party.mapId)
            args.map = partyMap ~= nil and Model.DisplayName(partyMap) or ""
            text = T("status.elsewhere", args)
        else
            text = T("status.none", args)
        end
        SetText(statusChip, text)
        statusChip.data.kind = kind
        statusChip.data.mapId = party ~= nil and party.mapId or nil
        statusChip:SetClass("link", kind == "elsewhere")
        -- The chip moves left of the side panel while the panel is open.
        local inset = 8
        local rightPanel = data.panelMode == "log" and logPanel or sidePanel
        if data.panelMode ~= "none" and rightPanel.renderedWidth ~= nil then inset = inset + rightPanel.renderedWidth end
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
        if data.tool == "move" then
            local target = Model.GetLocation(data.toolTargetId)
            if target ~= nil then lines[#lines + 1] = T("hint.move", { name = Model.DisplayName(target) }) end
        end
        if data.tool == "ruler" then lines[#lines + 1] = T("hint.ruler") end
        if data.tool == "scale" then lines[#lines + 1] = T("set.map.scale.hint") end
        local children = {} --- @type Panel[]
        for _, line in ipairs(lines) do
            children[#children + 1] = gui.Label { classes = { "regionMapBanner" }, text = line, interactable = false }
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
    end

    local function EscapeLayer()
        if confirmLayer ~= nil and not confirmLayer:HasClass("collapsed") then return "confirm" end
        if data.popover ~= nil then return "popover" end
        if data.tool ~= "none" then return "tool" end
        if data.panelMode == "log" and logPanel ~= nil and logPanel.data.editing then return "edit" end
        if data.panelMode == "read" or data.panelMode == "log" then return "panel" end
        if data.panelMode ~= "none" then return "edit" end
        if data.mapId ~= nil then return "map" end
        return nil
    end

    -- Refresh ------------------------------------------------------------------------------------

    local function QueueRefresh(delay)
        if shell.refreshScheduled or not ctx.IsAlive() then return end
        shell.refreshScheduled = true
        root:ScheduleEvent("regionMapRefresh", delay or C.refreshDelay)
    end

    RefreshAll = function()
        if not ctx.IsAlive() then return end
        if shell.refreshing then
            shell.refreshPending = true
            return
        end
        shell.refreshing = true
        shell.refreshPending = false
        local ok, message = pcall(function()
            -- Drop what the viewer can no longer see: a deleted or unshared map, a
            -- hidden selection, a Move tool whose Location is gone.
            local map = ctx.CurrentMap()
            if data.mapId ~= nil and map == nil then
                data.mapId = nil
                canvas:FireEvent("showMap", "restore")
            end
            if data.selectedId ~= nil and Model.GetLocation(data.selectedId) == nil then
                data.selectedId, data.panelMode = nil, "none"
            end
            if data.tool == "move" and Model.GetLocation(data.toolTargetId) == nil then data.tool = "none" end
            if data.tool == "add" and (map == nil or not Model.CanAdd(map.id)) then data.tool = "none" end
            if (data.tool == "ruler" or data.tool == "scale") and map == nil then data.tool = "none" end
            if data.tool == "scale" and not Model.IsDirector() then data.tool = "none" end
            if data.popover == "settings" and not Model.IsDirector() then data.popover = nil end

            canvas:SetClass("collapsed", map == nil)
            atlas:SetClass("collapsed", map ~= nil)
            if map == nil then atlas:FireEvent("bind") else canvas:FireEvent("bind") end
            sidePanel:FireEvent("bind")
            logPanel:FireEvent("bind")
            popovers:FireEvent("bind")
            RefreshBreadcrumb(map)
            RefreshToolbar(map)
            RefreshStatus(map)
            RefreshBanners(map)
            RefreshToast()
            root.captureEscape = EscapeLayer() ~= nil
        end)
        local pending = shell.refreshPending
        shell.refreshing = false
        shell.refreshPending = false
        if ok and pending then QueueRefresh(0.01) end
        if not ok then error(message) end
    end
    ctx.RefreshAll = RefreshAll

    -- Components ---------------------------------------------------------------------------------

    present = RegionMapPresent.Create(ctx)
    canvas = RegionMapCanvas.Create(ctx)
    atlas = RegionMapAtlas.Create(ctx)
    sidePanel = RegionMapSidePanel.Create(ctx)
    logPanel = RegionMapLogPanel.Create(ctx)
    popovers = RegionMapPopovers.Create(ctx)

    breadcrumb = gui.Panel { id = "region-map-breadcrumb", classes = { "regionMapBreadcrumb" }, floating = true }

    searchButton = Session.IconButton("region-map-search", C.iconSearch, T("tb.search"), function()
        ctx.SetPopover("search")
    end)
    addButton = Session.IconButton("region-map-add", C.iconAdd, T("tb.add"), function()
        ctx.SetTool("add")
    end)
    rulerButton = Session.IconButton("region-map-ruler", C.iconRuler, T("tb.ruler"), function()
        ctx.SetTool("ruler")
    end)
    logButton = Session.IconButton("region-map-log", C.iconLog, T("tb.log"), function()
        ctx.ToggleLog()
    end)
    expandButton = Session.IconButton("region-map-expand", C.iconExpand, T("tb.expand.off"), function()
        ctx.ToggleExpand()
    end)
    settingsButton = Session.IconButton("region-map-settings", C.iconSettings, T("tb.settings"), function()
        ctx.SetPopover("settings")
    end)
    lockButton = Session.IconButton("region-map-lock", C.iconLocked, T("tb.lock.on"), function()
        data.locked = not data.locked
        RefreshAll()
    end)
    showButton = Session.IconButton("region-map-show", C.iconShow, T("tb.show"), function()
        ctx.ShowToPlayers()
    end)
    viewAsButton = Session.IconButton("region-map-view-as", C.iconViewAs, T("tb.viewAs.off"), function()
        Model.SetViewAsPlayer(not Model.ViewingAsPlayer())
        data.tool, data.toolTargetId = "none", nil
        RefreshAll()
    end)
    local toolbar = gui.Panel {
        id = "region-map-toolbar", classes = { "regionMapToolbar" }, floating = true,
        -- Brief order (D12a): Search, Add, Lock, Ruler, Show, View as player, Log, Expand, Settings.
        searchButton, addButton, lockButton, rulerButton, showButton, viewAsButton, logButton, expandButton,
        settingsButton,
    }

    statusChip = gui.Label {
        id = "region-map-status", classes = { "regionMapStatus" }, floating = true, text = "",
        data = { kind = "none", mapId = nil },
        hover = function(element)
            if element.data.kind == "elsewhere" then gui.Tooltip(T("status.elsewhere.tooltip"))(element)
            elseif element.data.kind == "none" and Model.IsDirector() then gui.Tooltip(T("status.none.hint"))(element) end
        end,
        click = function(element)
            if element.data.kind == "elsewhere" and element.data.mapId ~= nil then
                ctx.OpenMap(element.data.mapId, "restore")
            end
        end,
    }
    banners = gui.Panel { classes = { "regionMapBanners" }, floating = true, interactable = false }

    toastText = gui.Label { classes = { "regionMapToastText" }, text = "", interactable = false }
    toastUndo = gui.Label {
        classes = { "regionMapToastButton" }, text = T("toast.undo"),
        click = function()
            local current = Undo.Current()
            if current ~= nil and current.entry ~= nil then
                Undo.Undo(current.entry, function() if ctx.IsAlive() then RefreshAll() end end)
            end
        end,
    }
    toastRetry = gui.Label {
        classes = { "regionMapToastButton", "collapsed" }, text = T("toast.retry"),
        click = function()
            local current = Undo.Current()
            if current ~= nil and current.retry ~= nil then
                Undo.Dismiss()
                current.retry()
            end
        end,
    }
    toast = gui.Panel {
        id = "region-map-toast", classes = { "regionMapToast", "collapsed" }, floating = true,
        hover = function() Undo.SetPaused(true) end,
        dehover = function() Undo.SetPaused(false) end,
        toastText, toastUndo, toastRetry,
    }

    -- Built once and reused (see ctx.Confirm); the dim layer swallows clicks to the map below.
    confirmTitle = gui.Label { classes = { "regionMapConfirmTitle" }, text = "", interactable = false }
    confirmBody = gui.Label { classes = { "regionMapConfirmBody" }, text = "", interactable = false }
    confirmOk = gui.Button {
        id = "region-map-confirm-ok", classes = { "regionMapButton", "sizeS" }, text = "",
        click = function()
            local action = confirmLayer.data.onConfirm
            CloseConfirm()
            if action ~= nil and not mod.unloaded then action() end
        end,
    }
    confirmLayer = gui.Panel {
        id = "region-map-confirm", classes = { "regionMapConfirmLayer", "collapsed" }, floating = true,
        swallowPress = true, data = { onConfirm = nil },
        gui.Panel {
            classes = { "regionMapConfirm" },
            confirmTitle,
            confirmBody,
            gui.Panel {
                classes = { "regionMapConfirmButtons" },
                confirmOk,
                gui.Button {
                    id = "region-map-confirm-cancel", classes = { "regionMapButton", "sizeS" }, text = T("dlg.cancel"),
                    click = function() CloseConfirm() end,
                },
            },
        },
    }

    root = gui.Panel {
        id = "region-map-panel",
        classes = { "regionMapRoot" },
        styles = ThemeEngine.MergeStyles(Styles.Build()),
        popupsInheritStyles = true,
        thinkTime = C.rootThink,
        escapePriority = ESCAPE_PRIORITY,
        monitorAssets = MonitoredTables(C.locationTableName, C.detailsTableName, C.notesTableName, C.logTableName),
        monitorGame = { Model.StatePath(), GameHud.PresentDialogPath() },
        data = {},
        create = function(element)
            Styles.Subscribe(element)
            -- Players open on their last map (D13c); otherwise the first map, else the Atlas.
            local last = Model.GetLocation(Session.LastMapId())
            if last == nil or not Model.CanOpenMap(last) then last = Model.TopLevel()[1] end
            if last ~= nil then
                data.mapId = last.id
                canvas:FireEvent("showMap", "restore")
            end
            RefreshAll()
            present.Receive()
            RegionMapLog.EnforceCap()
            if options.fitHost ~= nil then element:ScheduleEvent("regionMapFitHost", 0.01) end
        end,
        destroy = function(element)
            ctx.FlushEdits()
            Model.SetViewAsPlayer(false)
            Styles.Unsubscribe(element)
        end,
        refreshAssets = function() QueueRefresh() end,
        refreshGame = function()
            present.Receive()
            QueueRefresh()
        end,
        regionMapRefresh = function()
            shell.refreshScheduled = false
            RefreshAll()
        end,
        regionMapFitHost = function(element)
            if options.fitHost ~= nil then options.fitHost(element) end
        end,
        think = function()
            if not ctx.IsAlive() then return end
            if shell.director ~= dmhub.isDM then
                shell.director = dmhub.isDM
                Model.SetViewAsPlayer(false)
                RefreshAll()
            end
            present.Receive()
            RefreshToast()
            -- A resize by hand ends Expand; the toggle then offers Expand again.
            if data.expanded and options.isExpanded ~= nil and not options.isExpanded(root) then RefreshAll() end
            root.captureEscape = EscapeLayer() ~= nil
        end,
        -- Esc order (R2): stop the tool -> leave edit mode -> close the panel -> go up a level.
        escape = function()
            local layer = EscapeLayer()
            if layer == "confirm" then
                CloseConfirm()
            elseif layer == "popover" then
                ctx.SetPopover(nil)
            elseif layer == "tool" then
                canvas:FireEvent("cancelGesture")
                ctx.SetTool("none")
            elseif layer == "edit" and data.panelMode == "log" then
                logPanel:FireEvent("closeEditor")
            elseif layer == "edit" then
                ctx.Select(data.selectedId, "read")
            elseif layer == "panel" and data.panelMode == "log" then
                ctx.ToggleLog()
            elseif layer == "panel" then
                ctx.Select(nil, nil)
            elseif layer == "map" then
                ctx.GoUp()
            end
        end,

        canvas, atlas, breadcrumb, toolbar, banners, statusChip, sidePanel, logPanel, popovers, toast, confirmLayer,
    }
    ctx.root = root
    return root
end
