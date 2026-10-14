local mod = dmhub.GetModLoading()

-- Region Map bootstrap: checks the host once, registers the panel and the
-- presentable dialog, and hosts the map fullscreen, in-app or in a native popout. Region Map
-- is an opt-in CodeMod; it depends only on public DMHub UI and game services.
local C = RegionMapConstants

-- The host APIs an older core may lack. Everything else Region Map uses has
-- been in the core for longer than the mod has existed.
local function MissingHostApis()
    local missing = {}
    local function Need(ok, name) if not ok then missing[#missing + 1] = name end end
    local dockable = rawget(_G, "DockablePanel")
    local panelDocument = rawget(_G, "PanelDocument")
    local gameHud = rawget(_G, "GameHud")
    Need(dockable ~= nil and type(dockable.Register) == "function"
        and type(dockable.LaunchPanelByName) == "function", "DockablePanel")
    Need(panelDocument ~= nil and type(panelDocument.OpenPopout) == "function"
        and type(panelDocument.PopoutHost) == "function" and type(panelDocument.PopoutForgetWindow) == "function"
        and type(panelDocument.WindowUIScale) == "function", "PanelDocument popouts")
    Need(gameHud ~= nil and type(gameHud.RegisterPresentableDialog) == "function"
        and type(gameHud.GetPresentDialogDocRaw) == "function", "GameHud presentation")
    Need(type(gui.IconEditor) == "function", "gui.IconEditor")
    Need(type(gui.SearchInput) == "function", "gui.SearchInput")
    Need(type(gui.ExpandoArrow) == "function", "gui.ExpandoArrow")
    Need(type(gui.WindowResizePanel) == "function", "gui.WindowResizePanel")
    return missing
end

local missing = MissingHostApis()
if #missing > 0 then
    -- raw: the message goes to chat and the log, which do not render markup.
    local message = RegionMapCopy.T("load.missing", { list = table.concat(missing, ", ") }, true)
    print("REGION_MAP: " .. message)
    dmhub.Schedule(1, function()
        local notify = rawget(_G, "SendTitledChatMessage")
        if mod.unloaded or notify == nil then return end
        pcall(notify, message, RegionMapCopy.T("window.title", nil, true), nil, { dmhub.loginUserid })
    end)
    return
end

-- In-app host -------------------------------------------------------------------------
-- One content tree changes size in place, so switching view keeps drafts and selection.
local Session = RegionMapSession
local T = RegionMapCopy.T
local POPOUT_KEY = string.lower(C.panelName)
local inAppHost = nil --- @type Panel|nil
local actionBarRestore = nil --- @type boolean|nil

local function HideActionBar()
    if actionBarRestore ~= nil then return end
    actionBarRestore = dmhub.GetSettingValue("hideactionbar") == true
    dmhub.SetSettingValue("hideactionbar", true)
end

local function RestoreActionBar()
    if actionBarRestore == nil then return end
    dmhub.SetSettingValue("hideactionbar", actionBarRestore)
    actionBarRestore = nil
end

local function RailMode()
    local active = rawget(_G, "RailModeActive")
    if type(active) ~= "function" then return false end
    local ok, value = pcall(active)
    return ok and value == true
end

local function IsOpen()
    return inAppHost ~= nil and inAppHost.valid
end

local function SavePlacement(host)
    if host.data.mode ~= "window" then return end
    local scale = host.data.scale
    local geometry = {
        x = host.x / scale, y = host.y / scale,
        width = host.selfStyle.width / scale, height = host.selfStyle.height / scale,
    }
    host.data.geometry = geometry
    Session.SaveWindowGeometry(geometry)
end

local function CloseInApp()
    local host = inAppHost
    inAppHost = nil
    if host == nil or not host.valid then return end
    SavePlacement(host)
    host:DestroySelf()
end

local function RequestClose()
    local host = inAppHost
    if host ~= nil and host.valid then host.data.content:FireEvent("requestClose", CloseInApp) end
end

local OpenInApp

local function PopOut()
    CloseInApp()
    PanelDocument.OpenPopout(C.panelName, { width = C.windowWidth, height = C.windowHeight, scale = 1 })
end

local function PopIn()
    PanelDocument.PopoutForgetWindow(POPOUT_KEY)
    local host = PanelDocument.PopoutHost(POPOUT_KEY)
    if host ~= nil then host:DestroySelf() end
    OpenInApp(true)
end

-- Host coordinates use the documents layer; its content and title share one UI scale.
local function WorkArea(host)
    local layer = host.parent
    if layer == nil then return nil end
    local width, height = layer.renderedWidth, layer.renderedHeight
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return nil end
    local scale = 1
    local ok, value = pcall(PanelDocument.WindowUIScale)
    if ok and type(value) == "number" and value > 0 then scale = value end
    local side, top, bottom = 0, 0, 0
    if RailMode() then
        side = C.railInset + C.railButton * scale + C.railGap
        top = math.max(C.railTopMin, (C.railButton + C.railStopGap) * scale + C.railStopGap)
        bottom = C.railGap
    end
    local barHeight = 0
    local hidden = dmhub.GetSettingValue("hideactionbar") == true
    if actionBarRestore ~= nil then hidden = actionBarRestore end
    if not hidden then
        pcall(function()
            local bar = GameHud.instance:try_get("actionBarPanel")
            if bar ~= nil and bar.valid then barHeight = bar.renderedHeight or 0 end
        end)
    end
    return {
        scale = scale, width = width, height = height, side = side, top = top, bottom = bottom,
        left = side + C.panelMargin, right = width - side - C.panelMargin,
        upper = top + C.panelMargin, lower = height - math.max(bottom, barHeight) - C.panelMargin,
    }
end

local function LayoutContent(host)
    local d = host.data
    if d.mode == nil or d.area == nil then return end
    local window = d.mode == "window"
    local width, height = host.selfStyle.width, host.selfStyle.height
    local left = window and 0 or d.area.side
    local top = window and C.panelTitleHeight * d.scale or d.area.top
    local bottom = window and 0 or d.area.bottom
    local w, h = math.max(1, width - left * 2), math.max(1, height - top - bottom)
    d.frame.selfStyle.lmargin, d.frame.selfStyle.tmargin = left, top
    d.frame.selfStyle.width, d.frame.selfStyle.height = w, h
    d.zoom.selfStyle.pivot = { x = 0, y = 1 }
    d.zoom.selfStyle.uiscale = d.scale
    d.zoom.selfStyle.width, d.zoom.selfStyle.height = w / d.scale, h / d.scale
    d.title.selfStyle.pivot = { x = 0, y = 1 }
    d.title.selfStyle.uiscale = d.scale
    d.title.selfStyle.width = width / d.scale
end

local function SetHostSize(host, width, height)
    local d = host.data
    host.selfStyle.width, host.selfStyle.height = width, height
    if d.mode == "window" then
        d.resizer:FireEventTree("resize", host, { deltax = width - d.resizeWidth, deltay = height - d.resizeHeight })
        d.resizeWidth, d.resizeHeight = width, height
    end
    LayoutContent(host)
end

local function PlaceWindow(host, geometry)
    local d, clamp = host.data, RegionMapModel.Clamp
    local a, scale = d.area, d.scale
    local width = clamp((geometry and geometry.width or C.panelWidth) * scale,
        C.windowMinWidth * scale, math.min(C.windowMaxWidth * scale, a.right - a.left))
    local height = clamp((geometry and geometry.height or C.panelHeight) * scale,
        C.windowMinHeight * scale, math.min(C.windowMaxHeight * scale, a.lower - a.upper))
    local x = geometry and geometry.x * scale or (a.left + a.right - width) / 2
    local y = geometry and geometry.y * scale or (a.upper + a.lower - height) / 2
    host.x, host.y = clamp(x, a.left, a.right - width), clamp(y, a.upper, a.lower - height)
    SetHostSize(host, width, height)
end

local function FitHost(host, force)
    local d, a = host.data, WorkArea(host)
    if a == nil or d.dragging then return end
    local key = table.concat({ d.requestedMode, a.scale, a.width, a.height, a.side, a.top, a.lower }, ":")
    if not force and d.fit == key then return end
    d.fit, d.area, d.scale = key, a, a.scale
    local mode = d.requestedMode
    if mode == "window" and (a.right - a.left < C.windowMinWidth * a.scale
        or a.lower - a.upper < C.windowMinHeight * a.scale) then mode = "fullscreen" end
    local changed = d.mode ~= mode
    d.mode = mode
    local window = mode == "window"
    host:SetClass("regionMapWindowHost", window)
    d.border:SetClass("collapsed", not window)
    d.title:SetClass("collapsed", not window)
    d.grip:SetClass("collapsed", not window)
    d.resizer:SetClass("collapsed", not window)
    d.resizeOptions.minWidth, d.resizeOptions.minHeight = C.windowMinWidth * a.scale, C.windowMinHeight * a.scale
    d.resizeOptions.maxWidth = math.min(C.windowMaxWidth * a.scale, a.right - a.left)
    d.resizeOptions.maxHeight = math.min(C.windowMaxHeight * a.scale, a.lower - a.upper)
    if window then
        RestoreActionBar()
        PlaceWindow(host, d.geometry)
    else
        HideActionBar()
        host.x, host.y = 0, 0
        SetHostSize(host, a.width, a.height)
    end
    if changed then
        d.content:FireEvent("regionMapHostMode", mode)
        if window then host:SetAsLastSibling() else host:SetAsFirstSibling() end
        host:ScheduleEvent("regionMapCheckFocus", 0.01)
    end
end

local function FinishPlacement(host)
    local d = host.data
    if d.mode ~= "window" then return end
    local geometry = {
        x = host.x / d.scale, y = host.y / d.scale,
        width = host.selfStyle.width / d.scale, height = host.selfStyle.height / d.scale,
    }
    PlaceWindow(host, geometry)
    SavePlacement(host)
end

local function PointerInLayer(host)
    local layer = host.parent
    local point = layer ~= nil and layer.mousePoint or nil
    if point == nil then return nil, nil end
    return point.x * layer.renderedWidth, (1 - point.y) * layer.renderedHeight
end

-- Native drag transfer changes the grab offset between title and host pivots.
-- Track the pointer in the stationary documents layer instead.
local function PollTitleDrag(host)
    local d, clamp = host.data, RegionMapModel.Clamp
    local drag = d.titleDrag
    if drag == nil then return end
    if not host:GetMouseButton(0) then
        d.titleDrag, d.dragging = nil, false
        FinishPlacement(host)
        if not d.hovered then host.thinkTime = 0.25 end
        return
    end
    local x, y = PointerInLayer(host)
    if x == nil or y == nil then return end
    host.x = clamp(drag.x + x - drag.pointerX, d.area.left, d.area.right - host.selfStyle.width)
    host.y = clamp(drag.y + y - drag.pointerY, d.area.upper, d.area.lower - host.selfStyle.height)
end

local function ToggleView()
    local host = inAppHost
    if host == nil or not host.valid then return end
    SavePlacement(host)
    host.data.requestedMode = host.data.mode == "window" and "fullscreen" or "window"
    Session.SetInAppView(host.data.requestedMode)
    FitHost(host, true)
end

OpenInApp = function(focus)
    if mod.unloaded or IsOpen() then return end
    local layer = nil
    pcall(function() layer = GameHud.instance.documentsPanel end)
    if layer == nil or not layer.valid then return end
    local host
    local content = RegionMapPanel.Create { close = CloseInApp, popOut = PopOut, toggleView = ToggleView, mode = "fullscreen" }
    local zoom = gui.Panel { width = "100%", height = "100%", halign = "left", valign = "top", content }
    local frame = gui.Panel { floating = true, width = "100%", height = "100%", halign = "left", valign = "top", zoom }
    local resizeOptions = {
        onResized = function(element)
            element.data.resizeWidth, element.data.resizeHeight = element.selfStyle.width, element.selfStyle.height
            FinishPlacement(element)
        end,
    }
    local placement = { try_get = function(self, key) return rawget(self, key) end }
    local resizer = gui.WindowResizePanel(placement, C.panelWidth, C.panelHeight, resizeOptions)
    local optionsButton = Session.IconButton("region-map-window-options", C.iconMore, T("window.options"), function(element)
        element.popupsInheritStyles = false
        element.popup = Session.ContextMenu(element, { entries = {
            { text = T("window.reset"), click = function()
                element.popup = nil
                if not IsOpen() or host.data.mode ~= "window" then return end
                host.data.geometry = nil
                FitHost(host, true)
                SavePlacement(host)
            end },
        } })
    end, { "regionMapHostControl" })
    local close = Session.IconButton("region-map-window-close", C.iconClose, T("tb.close"), RequestClose, { "regionMapHostControl" })
    local title = gui.Panel {
        id = "region-map-window-title", classes = { "regionMapWindowTitle" }, floating = true,
        swallowPress = true,
        press = function(element)
            if host.data.mode ~= "window" or not element:GetMouseButton(0) then return end
            Session.CloseContextMenu()
            local x, y = PointerInLayer(host)
            if x == nil or y == nil then return end
            host.data.titleDrag = { x = host.x, y = host.y, pointerX = x, pointerY = y }
            host.data.dragging = true
            host.thinkTime = C.canvasThinkActive
            host:SetAsLastSibling()
        end,
        wheel = function() return true end,
        gui.Label { classes = { "label", "sizeM" }, text = T("window.title"),
            width = "100% available", height = "auto", lmargin = 6, textAlignment = "left", valign = "center", interactable = false },
        optionsButton, close,
    }
    -- Draw above the map and title, which cover a border painted on their parent.
    local border = gui.Panel {
        id = "region-map-window-border", classes = { "regionMapWindowBorder", "collapsed" },
        floating = true, interactable = false,
    }
    local grip = gui.Label { classes = { "regionMapResizeGrip" }, text = "//", floating = true, interactable = false }
    host = gui.Panel {
        id = "region-map-fullscreen",
        classes = { "regionMapRoot" },
        styles = ThemeEngine.MergeStyles(RegionMapStyles.Build()),
        halign = "left", valign = "top", x = 0, y = 0, floating = true,
        swallowPress = true, thinkTime = 0.25,
        data = {
            fit = nil, frame = frame, zoom = zoom, content = content, title = title, border = border, grip = grip, resizer = resizer,
            resizeOptions = resizeOptions, resizeWidth = C.panelWidth, resizeHeight = C.panelHeight,
            requestedMode = Session.InAppView(), mode = nil, scale = 1,
            geometry = Session.ReadWindowGeometry(), hovered = false, pressed = false, dragging = false,
            openFocus = gui.GetFocus(),
        },
        multimonitor = { "fontsize", "iconrail", "hideactionbar" },
        monitor = function(element) FitHost(element) end,
        create = function(element)
            RegionMapStyles.Subscribe(element)
            FitHost(element)
        end,
        rendered = function(element) LayoutContent(element) end,
        hover = function(element) element.data.hovered = true; element.thinkTime = C.canvasThinkActive end,
        dehover = function(element)
            element.data.hovered = false
            element.thinkTime = element.data.dragging and C.canvasThinkActive or 0.25
        end,
        childfocus = function(element)
            if element.data.mode == "window" then element:SetAsLastSibling() end
        end,
        regionMapHostFocus = function(element, from, direction) Session.FocusHostControl(element, from, direction) end,
        regionMapInitialFocus = function(element)
            if gui.GetFocus() == element.data.openFocus then Session.FocusHostControl(element, nil, 1) end
            element.data.openFocus = nil
        end,
        regionMapCheckFocus = function(element)
            local focused = gui.GetFocus()
            if focused ~= nil and focused:IsDescendantOf(element) and not focused.enabled then
                Session.FocusHostControl(element, nil, 1)
            end
        end,
        wheel = function() return true end,
        think = function(element)
            if mod.unloaded then element:DestroySelf(); return end
            local d = element.data
            PollTitleDrag(element)
            if d.mode == "fullscreen" and element.siblingIndex ~= 1 then element:SetAsFirstSibling() end
            local pressed = element:GetMouseButton(0) or element:GetMouseButton(1) or element:GetMouseButton(2)
            if d.mode == "window" and d.hovered and pressed and not d.pressed then element:SetAsLastSibling() end
            d.pressed = pressed
            FitHost(element)
            local active = d.mode ~= "window" or (element.parent ~= nil and element.siblingIndex == #element.parent.children)
            if d.active ~= active then
                d.active = active
                d.content:FireEvent("regionMapHostActive", active)
            end
        end,
        destroy = function(element)
            if inAppHost == host then inAppHost = nil end
            RegionMapStyles.Unsubscribe(element)
            RestoreActionBar()
        end,
        frame, title, border, grip, resizer,
    }
    inAppHost = host
    layer:AddChild(host)
    FitHost(host, true)
    if focus then host:ScheduleEvent("regionMapInitialFocus", 0.01) end
end

local function ShowMapHost(focus)
    local popout = PanelDocument.PopoutHost(POPOUT_KEY)
    if popout ~= nil then
        pcall(function() popout:RaiseNativeWindow() end)
        return
    end
    OpenInApp(focus)
end

local function ToggleInApp()
    local host = inAppHost
    if host ~= nil and host.valid then
        if host.data.mode == "window" and host.parent ~= nil and host.siblingIndex ~= #host.parent.children then
            host:SetAsLastSibling()
        else
            RequestClose()
        end
    else
        ShowMapHost(true)
    end
end

-- Registration -------------------------------------------------------------------------

-- Close any legacy instance before replacing its registration (Lua reloads).
DockablePanel.LaunchPanelByName(C.panelName, "hide")
DockablePanel.Deregister(C.panelName)
-- An action registration: the rail button, the Game menu and ShowPanelByName run
-- launch instead of opening a window. content is still built for the native popout.
DockablePanel.Register {
    name = C.panelName,
    icon = C.panelIcon,
    dmonly = false,
    vscroll = false,
    minWidth = C.windowMinWidth,
    maxWidth = C.windowMaxWidth,
    minHeight = C.windowMinHeight,
    maxHeight = C.windowMaxHeight,
    popoutHeight = C.popoutHeight,
    resizableWidth = true,
    resizableHeight = true,
    menu = "game",
    launch = ToggleInApp,
    content = function()
        return RegionMapPanel.Create { popIn = PopIn, mode = "native" }
    end,
}

-- keeplocal = false: every client, the presenter included, opens its own
-- map; the panel then reads the presentation itself. Show, never toggle:
-- a map that is already open stays open.
GameHud.RegisterPresentableDialog {
    id = C.panelName,
    keeplocal = false,
    create = function()
        ShowMapHost()
        return nil
    end,
}

print("REGION_MAP: addon loaded")
