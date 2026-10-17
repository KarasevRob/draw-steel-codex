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
local inAppHost = nil --- @type RegionMapWindowHost|nil
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

--- The in-app map window. It is also its panel's data, so the content and the checks
--- read the same fields. The host talks to the content only through events (see
--- RegionMapHostOptions in RegionMapPanel.lua): regionMapHostMode, regionMapHostActive and requestClose.
--- @class RegionMapWindowHost
--- @field panel Panel
--- @field frame Panel
--- @field zoom Panel
--- @field content Panel
--- @field title Panel
--- @field border Panel
--- @field grip Panel
--- @field resizer Panel
--- @field resizeOptions table
--- @field resizeWidth number
--- @field resizeHeight number
--- @field requestedMode "fullscreen"|"window" the viewer's choice
--- @field mode nil|"fullscreen"|"window" what shows: window falls back to fullscreen when there is no room
--- @field scale number
--- @field area nil|table the documents layer's usable rectangle (WorkArea)
--- @field geometry nil|RegionMapWindowGeometry
--- @field hovered boolean
--- @field pressed boolean
--- @field dragging boolean
--- @field titleDrag nil|{x: number, y: number, pointerX: number, pointerY: number}
--- @field pointer nil|{x: number, y: number} the last pointer position read inside the layer
--- @field openFocus nil|Panel
--- @field active nil|boolean last value sent with regionMapHostActive
--- @field nextFit number time of the next idle refit check
local Host = {}
Host.__index = Host

--- @return boolean
function Host:Valid()
    return self.panel ~= nil and self.panel.valid
end

--- Current placement in unscaled UI units (what the viewer's preferences store).
--- @return RegionMapWindowGeometry
function Host:CurrentGeometry()
    local scale, panel = self.scale, self.panel
    return { x = panel.x / scale, y = panel.y / scale,
        width = panel.selfStyle.width / scale, height = panel.selfStyle.height / scale }
end

function Host:SavePlacement()
    if self.mode ~= "window" then return end
    self.geometry = self:CurrentGeometry()
    Session.SaveWindowGeometry(self.geometry)
end

-- Host coordinates use the documents layer; its content and title share one UI scale.
--- @return nil|table
function Host:WorkArea()
    local layer = self.panel.parent
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

function Host:LayoutContent()
    if self.mode == nil or self.area == nil then return end
    local window = self.mode == "window"
    local width, height = self.panel.selfStyle.width, self.panel.selfStyle.height
    local left = window and 0 or self.area.side
    local top = window and C.panelTitleHeight * self.scale or self.area.top
    local bottom = window and 0 or self.area.bottom
    local w, h = math.max(1, width - left * 2), math.max(1, height - top - bottom)
    self.frame.selfStyle.lmargin, self.frame.selfStyle.tmargin = left, top
    self.frame.selfStyle.width, self.frame.selfStyle.height = w, h
    self.zoom.selfStyle.pivot = { x = 0, y = 1 }
    self.zoom.selfStyle.uiscale = self.scale
    self.zoom.selfStyle.width, self.zoom.selfStyle.height = w / self.scale, h / self.scale
    self.title.selfStyle.pivot = { x = 0, y = 1 }
    self.title.selfStyle.uiscale = self.scale
    self.title.selfStyle.width = width / self.scale
end

function Host:SetSize(width, height)
    self.panel.selfStyle.width, self.panel.selfStyle.height = width, height
    if self.mode == "window" then
        self.resizer:FireEventTree("resize", self.panel, { deltax = width - self.resizeWidth, deltay = height - self.resizeHeight })
        self.resizeWidth, self.resizeHeight = width, height
    end
    self:LayoutContent()
end

--- Clamp a placement into the work area; nil geometry centers the default size.
--- @param geometry nil|RegionMapWindowGeometry
function Host:Place(geometry)
    local clamp = RegionMapModel.Clamp
    local a, scale = self.area, self.scale
    if a == nil then return end
    local width = clamp((geometry and geometry.width or C.panelWidth) * scale,
        C.windowMinWidth * scale, math.min(C.windowMaxWidth * scale, a.right - a.left))
    local height = clamp((geometry and geometry.height or C.panelHeight) * scale,
        C.windowMinHeight * scale, math.min(C.windowMaxHeight * scale, a.lower - a.upper))
    local x = geometry and geometry.x * scale or (a.left + a.right - width) / 2
    local y = geometry and geometry.y * scale or (a.upper + a.lower - height) / 2
    self.panel.x, self.panel.y = clamp(x, a.left, a.right - width), clamp(y, a.upper, a.lower - height)
    self:SetSize(width, height)
end

--- Whether a window fits in the work area at all.
--- @param a table
--- @return boolean
local function WindowFits(a)
    return a.right - a.left >= C.windowMinWidth * a.scale and a.lower - a.upper >= C.windowMinHeight * a.scale
end

--- Recompute the view for the layer's size, scale, rails and action bar; cheap when nothing moved.
--- @param force nil|boolean
function Host:Fit(force)
    local a = self:WorkArea()
    if a == nil or self.dragging then return end
    local old = self.area
    if not force and old ~= nil and self.fitMode == self.requestedMode and old.scale == a.scale and old.width == a.width
        and old.height == a.height and old.side == a.side and old.top == a.top and old.lower == a.lower then return end
    self.fitMode, self.area, self.scale = self.requestedMode, a, a.scale
    local mode = self.requestedMode
    if mode == "window" and not WindowFits(a) then mode = "fullscreen" end
    local changed = self.mode ~= mode
    self.mode = mode
    local window = mode == "window"
    local panel = self.panel
    panel:SetClass("regionMapWindowHost", window)
    self.border:SetClass("collapsed", not window)
    self.title:SetClass("collapsed", not window)
    self.grip:SetClass("collapsed", not window)
    self.resizer:SetClass("collapsed", not window)
    self.resizeOptions.minWidth, self.resizeOptions.minHeight = C.windowMinWidth * a.scale, C.windowMinHeight * a.scale
    self.resizeOptions.maxWidth = math.min(C.windowMaxWidth * a.scale, a.right - a.left)
    self.resizeOptions.maxHeight = math.min(C.windowMaxHeight * a.scale, a.lower - a.upper)
    if window then
        RestoreActionBar()
        self:Place(self.geometry)
    else
        HideActionBar()
        panel.x, panel.y = 0, 0
        self:SetSize(a.width, a.height)
    end
    if changed then
        self.content:FireEvent("regionMapHostMode", mode)
        if window then panel:SetAsLastSibling() else panel:SetAsFirstSibling() end
        panel:ScheduleEvent("regionMapCheckFocus", 0.01)
    end
end

function Host:FinishPlacement()
    if self.mode ~= "window" then return end
    self:Place(self:CurrentGeometry())
    self:SavePlacement()
end

--- The pointer in documents-layer pixels. The engine reports (0,0) while the pointer is
--- outside the layer, so that reading keeps the last real position instead.
--- @return nil|number x
--- @return nil|number y
function Host:PointerInLayer()
    local layer = self.panel.parent
    local point = layer ~= nil and layer.mousePoint or nil
    if point ~= nil and not (point.x == 0 and point.y == 0) then
        self.pointer = { x = point.x * layer.renderedWidth, y = (1 - point.y) * layer.renderedHeight }
    end
    if self.pointer == nil then return nil, nil end
    return self.pointer.x, self.pointer.y
end

--- Native drag transfer changes the grab offset between title and host pivots, so a title
--- drag tracks the pointer in the stationary documents layer instead.
function Host:BeginTitleDrag()
    if self.mode ~= "window" or not self.title:GetMouseButton(0) then return end
    Session.CloseContextMenu()
    self.pointer = nil
    local x, y = self:PointerInLayer()
    if x == nil or y == nil then return end
    self.titleDrag = { x = self.panel.x, y = self.panel.y, pointerX = x, pointerY = y }
    self.dragging = true
    self:Raise()
    self:UpdateThink()
end

function Host:PollTitleDrag()
    local drag, clamp, panel = self.titleDrag, RegionMapModel.Clamp, self.panel
    if drag == nil then return end
    if not panel:GetMouseButton(0) then
        self.titleDrag, self.dragging = nil, false
        self:FinishPlacement()
        self:UpdateThink()
        return
    end
    local x, y = self:PointerInLayer()
    if x == nil or y == nil then return end
    panel.x = clamp(drag.x + x - drag.pointerX, self.area.left, self.area.right - panel.selfStyle.width)
    panel.y = clamp(drag.y + y - drag.pointerY, self.area.upper, self.area.lower - panel.selfStyle.height)
end

--- Fast polling only while it matters: dragging, or a hovered window that a click should raise.
function Host:UpdateThink()
    local fast = self.dragging or (self.mode == "window" and self.hovered)
    self.panel.thinkTime = self.dragging and C.canvasThinkActive or fast and C.hostThinkHover or C.canvasThinkIdle
end

--- The window is the top one in its layer (fullscreen always counts as foremost).
--- @return boolean
function Host:Foremost()
    local panel = self.panel
    return self.mode ~= "window" or (panel.parent ~= nil and panel.siblingIndex == #panel.parent.children)
end

--- Whether this map takes Esc: fullscreen always; a window only while it is foremost and
--- the viewer is working in it (focus inside or the pointer over it), so Esc for the
--- action bar, character sheet or a menu elsewhere still reaches them.
--- @return boolean
function Host:Engaged()
    if self.mode ~= "window" then return true end
    if not self:Foremost() then return false end
    if self.hovered then return true end
    local focus = gui.GetFocus()
    return focus ~= nil and focus:IsDescendantOf(self.panel)
end

function Host:SyncEngaged()
    local engaged = self:Engaged()
    if self.active ~= engaged then
        self.active = engaged
        self.content:FireEvent("regionMapHostActive", engaged)
    end
end

function Host:Raise()
    if self.mode == "window" then self.panel:SetAsLastSibling() end
    self:SyncEngaged()
end

--- The viewer chose the map (rail button, menu): bring it forward and give it focus,
--- so Esc and Tab go to it next.
function Host:Activate()
    if self.mode == "window" then self.panel:SetAsLastSibling() end
    local focus = gui.GetFocus()
    if focus == nil or not focus:IsDescendantOf(self.panel) then Session.FocusHostControl(self.panel, nil, 1) end
    self:SyncEngaged()
end

function Host:Think()
    local panel = self.panel
    self:PollTitleDrag()
    if self.mode == "fullscreen" and panel.siblingIndex ~= 1 then panel:SetAsFirstSibling() end
    if self.mode == "window" and self.hovered then
        local pressed = panel:GetMouseButton(0) or panel:GetMouseButton(1) or panel:GetMouseButton(2)
        if pressed and not self.pressed then self:Raise() end
        self.pressed = pressed
    else
        self.pressed = false
    end
    -- Layout inputs (scale, rails, action bar) change rarely; check them at the idle rate.
    local now = dmhub.Time()
    if now >= self.nextFit then
        self.nextFit = now + C.canvasThinkIdle
        self:Fit()
    end
    self:SyncEngaged()
end

function Host:Close()
    if inAppHost == self then inAppHost = nil end
    if not self:Valid() then return end
    self:SavePlacement()
    self.panel:DestroySelf()
end

--- Ask the content to finish edits and imports first; it calls Close when that is done.
function Host:RequestClose()
    if self:Valid() then
        self.content:FireEvent("requestClose", function() self:Close() end)
    end
end

function Host:ToggleView()
    if not self:Valid() then return end
    self:SavePlacement()
    -- A window that cannot fit stays fullscreen; say so instead of silently remembering the choice.
    if self.mode == "fullscreen" and self.requestedMode == "window" then
        RegionMapUndo.Notify("window.tooSmall", { width = C.windowMinWidth, height = C.windowMinHeight })
        return
    end
    self.requestedMode = self.mode == "window" and "fullscreen" or "window"
    Session.SetInAppView(self.requestedMode)
    self:Fit(true)
end

function Host:ResetPlacement()
    if not self:Valid() or self.mode ~= "window" then return end
    self.geometry = nil
    self:Fit(true)
    self:SavePlacement()
end

local function IsOpen()
    return inAppHost ~= nil and inAppHost:Valid()
end

local function CloseInApp()
    if inAppHost ~= nil then inAppHost:Close() end
end

local function RequestClose()
    if inAppHost ~= nil then inAppHost:RequestClose() end
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

OpenInApp = function(focus)
    if mod.unloaded or IsOpen() then return end
    local layer = nil
    pcall(function() layer = GameHud.instance.documentsPanel end)
    if layer == nil or not layer.valid then return end
    local host = setmetatable({}, Host) --[[@as RegionMapWindowHost]]
    local content = RegionMapPanel.Create {
        close = CloseInApp, popOut = PopOut, mode = "fullscreen",
        toggleView = function() host:ToggleView() end,
    }
    local zoom = gui.Panel { width = "100%", height = "100%", halign = "left", valign = "top", content }
    local frame = gui.Panel { floating = true, width = "100%", height = "100%", halign = "left", valign = "top", zoom }
    local resizeOptions = {
        onResized = function(element)
            host.resizeWidth, host.resizeHeight = element.selfStyle.width, element.selfStyle.height
            host:FinishPlacement()
        end,
    }
    local placement = { try_get = function(self, key) return rawget(self, key) end }
    local resizer = gui.WindowResizePanel(placement, C.panelWidth, C.panelHeight, resizeOptions)
    local optionsButton = Session.IconButton("region-map-window-options", C.iconMore, T("window.options"), function(element)
        element.popupsInheritStyles = false
        element.popup = Session.ContextMenu(element, { entries = {
            { text = T("window.reset"), click = function()
                element.popup = nil
                host:ResetPlacement()
            end },
        } })
    end, { "regionMapHostControl" })
    local close = Session.IconButton("region-map-window-close", C.iconClose, T("tb.close"), RequestClose, { "regionMapHostControl" })
    local title = gui.Panel {
        id = "region-map-window-title", classes = { "regionMapWindowTitle" }, floating = true,
        swallowPress = true,
        press = function() host:BeginTitleDrag() end,
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
    local grip = gui.Label { classes = { "regionMapResizeGrip", "sizeS" }, text = "//", floating = true, interactable = false }
    host.frame, host.zoom, host.content, host.title, host.border, host.grip = frame, zoom, content, title, border, grip
    host.resizer, host.resizeOptions = resizer, resizeOptions
    host.resizeWidth, host.resizeHeight = C.panelWidth, C.panelHeight
    host.requestedMode, host.mode, host.scale = Session.InAppView(), nil, 1
    host.geometry = Session.ReadWindowGeometry()
    host.hovered, host.pressed, host.dragging = false, false, false
    host.openFocus, host.nextFit = gui.GetFocus(), 0
    host.panel = gui.Panel {
        id = "region-map-fullscreen",
        classes = { "regionMapRoot" },
        styles = ThemeEngine.MergeStyles(RegionMapStyles.Build()),
        halign = "left", valign = "top", x = 0, y = 0, floating = true,
        swallowPress = true, thinkTime = C.canvasThinkIdle,
        data = host,
        multimonitor = { "fontsize", "iconrail", "hideactionbar" },
        monitor = function() host:Fit() end,
        create = function(element)
            RegionMapStyles.Subscribe(element)
            host:Fit()
        end,
        rendered = function() host:LayoutContent() end,
        hover = function() host.hovered = true; host:UpdateThink(); host:SyncEngaged() end,
        dehover = function() host.hovered = false; host:UpdateThink(); host:SyncEngaged() end,
        childfocus = function() host:Raise() end,
        regionMapInitialFocus = function(element)
            if gui.GetFocus() == host.openFocus then Session.FocusHostControl(element, nil, 1) end
            host.openFocus = nil
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
            host:Think()
        end,
        destroy = function()
            if inAppHost == host then inAppHost = nil end
            RegionMapStyles.Unsubscribe(host.panel)
            RestoreActionBar()
        end,
        frame, title, border, grip, resizer,
    }
    inAppHost = host
    layer:AddChild(host.panel)
    host:Fit(true)
    host:SyncEngaged()
    if focus then host.panel:ScheduleEvent("regionMapInitialFocus", 0.01) end
end

-- A presented or rail-opened map comes to the front wherever it is.
local function ShowMapHost(focus)
    local popout = PanelDocument.PopoutHost(POPOUT_KEY)
    if popout ~= nil then
        pcall(function() popout:RaiseNativeWindow() end)
        return
    end
    local host = inAppHost
    if host ~= nil and host:Valid() then
        host:Raise()
        return
    end
    OpenInApp(focus)
end

local function ToggleInApp()
    local host = inAppHost
    if host ~= nil and host:Valid() then
        if host.mode == "window" and not host:Foremost() then host:Activate() else RequestClose() end
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
