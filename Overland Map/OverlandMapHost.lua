local mod = dmhub.GetModLoading()

-- The in-app Overland window: its chrome, geometry and visibility state. One content tree
-- changes size in place, so switching view keeps drafts and selection. Everything that
-- needs the shared Tabletop goes through OverlandMapTabletop; the bootstrap and lifecycle
-- reconciliation live in OverlandMap.lua.
OverlandMapHost = {}
local C = OverlandMapConstants
local Session = OverlandMapControls
local T = OverlandMapCopy.T
local Prefs = OverlandMapPreferences

-- Window state ----------------------------------------------------------------------------
-- One answer to "where is the map". The in-app host owns open, minimizing, minimized and
-- restoring; closed and native (a popped-out OS window) mean there is no in-app host.
-- minimizing lasts while Tabletop flies the window into its button; it behaves like minimized.

--- @alias OverlandMapWindowState "closed"|"native"|"open"|"minimizing"|"minimized"|"restoring"

--- @type table<OverlandMapWindowState, table<OverlandMapWindowState, boolean>>
local TRANSITIONS = {
    closed = { open = true, restoring = true, native = true },
    native = { closed = true, open = true, restoring = true },
    open = { minimizing = true, closed = true, native = true },
    minimizing = { minimized = true, restoring = true, closed = true, native = true },
    minimized = { restoring = true, closed = true, native = true },
    -- restoring -> restoring retries a restore whose animation could not finish.
    restoring = { open = true, restoring = true, minimizing = true, closed = true, native = true },
}

-- What a viewer's choice saves in their preferences, so the next session reopens the same way.
--- @type table<OverlandMapWindowState, "closed"|"open"|"minimized"|"native">
local SAVED = { closed = "closed", native = "native", open = "open", restoring = "open",
    minimizing = "minimized", minimized = "minimized" }

--- @type {state: OverlandMapWindowState, host: OverlandMapWindowHost|nil}
local presence = { state = "closed", host = nil }

-- Who decided the current state. Automatic restoration (from saved preferences, at game
-- entry or after a HUD rebuild) gives way permanently to any viewer action; generation
-- lets a restoration in progress notice that one happened meanwhile.
local intent = { generation = 0, automatic = true }

--- Move the window to a new state. persist saves it as the viewer's choice.
--- @param host OverlandMapWindowHost|nil the host entering an in-app state; nil for closed/native
--- @param to OverlandMapWindowState
--- @param persist nil|boolean
--- @return boolean entered
local function Enter(host, to, persist)
    local from = presence.state
    -- Only the current host (or a new one, from closed/native) may move the state.
    if host ~= nil and presence.host ~= nil and presence.host ~= host then return false end
    if from ~= to and not TRANSITIONS[from][to] or from == to and to ~= "restoring" then
        if from ~= to then print("OVERLAND_MAP: ignored window transition " .. from .. " -> " .. to) end
        return false
    end
    presence.state = to
    presence.host = (to ~= "closed" and to ~= "native") and host or nil
    if persist then Prefs.SaveHostState(SAVED[to]) end
    return true
end

--- @return OverlandMapWindowState
function OverlandMapHost.State()
    return presence.state
end

--- The in-app host, if there is one; it may have been invalidated since (check Valid).
--- @return OverlandMapWindowHost|nil
function OverlandMapHost.Current()
    return presence.host
end

--- The map moved to (or left) a native popout while no in-app host exists.
--- @param state "closed"|"native"
--- @param persist nil|boolean
function OverlandMapHost.SetOutside(state, persist)
    if presence.host ~= nil then presence.host:Release(state, persist) else Enter(nil, state, persist) end
end

--- Forget everything about the previous game's window without saving anything.
function OverlandMapHost.Reset()
    if presence.host ~= nil then presence.host:Release() end
    presence.state, presence.host = "closed", nil
    intent.generation, intent.automatic = intent.generation + 1, true
end

--- A viewer action: automatic restoration must not override it.
function OverlandMapHost.UserIntent()
    intent.generation = intent.generation + 1
    intent.automatic = false
end

--- Automatic restoration may run again (game entry, generic teardown).
function OverlandMapHost.AllowAutomatic()
    intent.automatic = true
end

--- @return {generation: integer, automatic: boolean}
function OverlandMapHost.Intent()
    return intent
end

-- Action bar ------------------------------------------------------------------------------
-- Fullscreen hides the action bar; remember the viewer's own setting to give it back.
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

--- The in-app map window. It is also its panel's data, so the content and the checks
--- read the same fields. The host talks to the content only through events (see
--- OverlandMapHostOptions in OverlandMapPanel.lua): overlandMapHostMode, overlandMapHostActive and requestClose.
--- @class OverlandMapWindowHost
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
--- @field fitMode nil|"fullscreen"|"window" the requested mode the last Fit used
--- @field scale number
--- @field area nil|table the documents layer's usable rectangle (WorkArea)
--- @field geometry nil|OverlandMapWindowGeometry
--- @field hovered boolean
--- @field pressed boolean
--- @field dragging boolean
--- @field titleDrag nil|{x: number, y: number, pointerX: number, pointerY: number}
--- @field pointer nil|{x: number, y: number} the last pointer position read inside the layer
--- @field openFocus nil|Panel
--- @field active nil|boolean last value sent with overlandMapHostActive
--- @field nextFit number time of the next idle refit check
--- @field allowFocus boolean
--- @field restoreFocus boolean whether the restore in progress should take focus
--- @field gameId string|nil
--- @field external table the Tabletop record for the minimized button (OverlandMapTabletop.NewRecord)
--- @field selectedMapId string|nil
--- @field minimizeButton Panel
local Host = {}
Host.__index = Host
OverlandMapHost.Host = Host

--- @return boolean
function Host:Valid()
    return not mod.unloaded and self.gameId == dmhub.gameid and self.panel ~= nil and self.panel.valid
end

--- This host's state; a host that was replaced or released is closed.
--- @return OverlandMapWindowState
function Host:State()
    return presence.host == self and presence.state or "closed"
end

--- @return boolean
function Host:Visible()
    return self:Valid() and self:State() == "open"
end

function Host:UserIntent()
    OverlandMapHost.UserIntent()
    self.allowFocus = self:State() == "open"
    -- A minimized preference shown as a fallback window becomes "open" once the viewer acts.
    if self:Visible() then Prefs.SaveHostState("open") end
end

--- Current placement in unscaled UI units (what the viewer's preferences store).
--- @return OverlandMapWindowGeometry
function Host:CurrentGeometry()
    local scale, panel = self.scale, self.panel
    return { x = panel.x / scale, y = panel.y / scale,
        width = panel.selfStyle.width / scale, height = panel.selfStyle.height / scale }
end

function Host:SavePlacement()
    if self.mode ~= "window" then return end
    self.geometry = self:CurrentGeometry()
    Prefs.SaveWindowGeometry(self.geometry)
end

-- Host coordinates use the documents layer; its content and title share one UI scale.
--- @return nil|table
function Host:WorkArea()
    local layer = self.panel.parent
    if layer == nil then return nil end
    local width, height = layer.renderedWidth, layer.renderedHeight
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return nil end
    local scale = PanelDocument.WindowUIScale()
    local side, top, bottom = 0, 0, 0
    if RailModeActive() then
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
--- @param geometry nil|OverlandMapWindowGeometry
function Host:Placement(geometry, centerX, centerY)
    local clamp = OverlandMapModel.Clamp
    local a = self:WorkArea()
    if a == nil then return end
    local scale = a.scale
    local width = clamp((geometry and geometry.width or C.panelWidth) * scale,
        C.windowMinWidth * scale, math.min(C.windowMaxWidth * scale, a.right - a.left))
    local height = clamp((geometry and geometry.height or C.panelHeight) * scale,
        C.windowMinHeight * scale, math.min(C.windowMaxHeight * scale, a.lower - a.upper))
    local x = geometry and geometry.x * scale or (a.left + a.right - width) / 2
    local y = geometry and geometry.y * scale or (a.upper + a.lower - height) / 2
    if centerX ~= nil and centerY ~= nil then x, y = centerX - width / 2, centerY - height / 2 end
    return { x = clamp(x, a.left, a.right - width) / scale, y = clamp(y, a.upper, a.lower - height) / scale,
        width = width / scale, height = height / scale }
end

function Host:Place(geometry)
    local placement = self:Placement(geometry)
    if placement == nil then return end
    self.panel.x, self.panel.y = placement.x * self.scale, placement.y * self.scale
    self:SetSize(placement.width * self.scale, placement.height * self.scale)
end

--- Whether a window fits in the work area at all.
--- @param a table
--- @return boolean
function OverlandMapHost.WindowFits(a)
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
    if mode == "window" and not OverlandMapHost.WindowFits(a) then mode = "fullscreen" end
    local changed = self.mode ~= mode
    self.mode = mode
    local window = mode == "window"
    local panel = self.panel
    OverlandMapTabletop.SetRaiseOnPress(panel, window and self:Visible())
    panel:SetClass("overlandMapWindowHost", window)
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
        if self:Visible() then HideActionBar() end
        panel.x, panel.y = 0, 0
        self:SetSize(a.width, a.height)
    end
    if changed then
        self.content:FireEvent("overlandMapHostMode", mode)
        if self:Visible() then
            if window and self.allowFocus then panel:SetAsLastSibling() elseif not window then panel:SetAsFirstSibling() end
            if self.allowFocus then panel:ScheduleEvent("overlandMapCheckFocus", 0.01) end
        end
    end
end

function Host:FinishPlacement()
    if self.mode ~= "window" then return end
    self:Place(self:CurrentGeometry())
    self:SavePlacement()
end

local function HasPointer(point)
    return point ~= nil and point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1
        and not (point.x == 0 and point.y == 0)
end

--- The pointer in documents-layer pixels. Outside readings can be zero or out of range;
--- keep the last valid drag position until the pointer returns.
--- @return nil|number x
--- @return nil|number y
function Host:PointerInLayer()
    local layer = self.panel.parent
    local point = layer ~= nil and layer.mousePoint or nil
    if layer ~= nil and point ~= nil and HasPointer(point) then
        self.pointer = { x = point.x * layer.renderedWidth, y = (1 - point.y) * layer.renderedHeight }
    end
    if self.pointer == nil then return nil, nil end
    return self.pointer.x, self.pointer.y
end

--- Native drag transfer changes the grab offset between title and host pivots, so a title
--- drag tracks the pointer in the stationary documents layer instead.
function Host:BeginTitleDrag()
    if self.mode ~= "window" or not self.title:GetMouseButton(0) then return end
    self:UserIntent()
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
    local drag, clamp, panel = self.titleDrag, OverlandMapModel.Clamp, self.panel
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

--- Poll quickly while dragging or while the foremost window contains the pointer.
function Host:UpdateThink()
    local fast = self.mode == "window" and self:Foremost() and self:PointerInside()
    local interval = self.dragging and C.canvasThinkActive or fast and C.hostThinkHover or C.canvasThinkIdle
    if self.panel.thinkTime ~= interval then self.panel.thinkTime = interval end
end

--- The window is the top one in its layer (fullscreen always counts as foremost).
--- @return boolean
function Host:Foremost()
    if not self:Visible() then return false end
    local panel = self.panel
    return self.mode ~= "window" or (panel.parent ~= nil and panel.siblingIndex == #panel.parent.children)
end

--- Whether this map takes Esc: fullscreen always; a window only while it is foremost and
--- the viewer is working in it (focus inside or the pointer over it), so Esc for the
--- action bar, character sheet or a menu elsewhere still reaches them.
--- @return boolean
function Host:Engaged()
    if not self:Visible() then return false end
    if self.atlasDrag ~= nil then return true end
    if self.mode ~= "window" then return true end
    if not self:Foremost() then return false end
    if self:PointerInside() then return true end
    local focus = gui.GetFocus()
    return focus ~= nil and focus:IsDescendantOf(self.panel)
end

--- Child controls receive hover events themselves; the host's coordinates cover the whole window.
--- @return boolean
function Host:PointerInside()
    return HasPointer(self.panel.mousePoint)
end

function Host:SyncEngaged()
    local engaged = self:Engaged()
    if self.active ~= engaged then
        self.active = engaged
        self.content:FireEvent("overlandMapHostActive", engaged)
    end
end

function Host:Raise()
    if not self:Visible() then return end
    self:UserIntent()
    if self.mode == "window" then self.panel:SetAsLastSibling()
    else OverlandMapTabletop.StampActivation(self.panel) end
    self:SyncEngaged()
end

--- The viewer chose the map (rail button, menu): bring it forward and give it focus,
--- so Esc and Tab go to it next.
function Host:Activate()
    if not self:Valid() then return end
    if self:State() ~= "open" then self:Restore(true); return end
    self:Raise()
    local focus = gui.GetFocus()
    if focus == nil or not focus:IsDescendantOf(self.panel) then Session.FocusHostControl(self.panel, nil, 1) end
    self:SyncEngaged()
end

function Host:Think()
    if not self:Visible() then return end
    local panel = self.panel
    self:PollTitleDrag()
    self:UpdateThink()
    if self.mode == "fullscreen" and panel.siblingIndex ~= 1 then panel:SetAsFirstSibling() end
    if self.mode == "window" and self.hovered and self:PointerInside() then
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

--- The viewer's accepted close: the only path that saves "closed" and gives up the rail slot.
function Host:Close()
    if not self:Valid() then return end
    self:UserIntent()
    self:SavePlacement()
    OverlandMapTabletop.Close(self.external)
    self:Release("closed", true)
end

--- Take the host down. Without arguments this is teardown (game change, reload, HUD
--- rebuild): nothing is saved and the rail slot stays, so the window can come back.
--- @param to nil|"closed"|"native"
--- @param persist nil|boolean
function Host:Release(to, persist)
    if presence.host == self then Enter(self, to or "closed", persist) end
    self.allowFocus = false
    self:CancelAtlasDrag()
    OverlandMapTabletop.Release(self.external)
    if self.panel ~= nil and self.panel.valid then self.panel:DestroySelf() end
    RestoreActionBar()
end

--- Ask the content to finish edits and imports first; it calls Close when that is done.
function Host:RequestClose()
    if self:Valid() then
        self:Restore(true, false)
        self.content:FireEvent("requestClose", function() self:Close() end)
    end
end

function Host:ToggleView()
    if not self:Valid() then return end
    self:UserIntent()
    self:SavePlacement()
    -- A window that cannot fit stays fullscreen; say so instead of silently remembering the choice.
    if self.mode == "fullscreen" and self.requestedMode == "window" then
        OverlandMapUndo.Notify("window.tooSmall", { width = C.windowMinWidth, height = C.windowMinHeight })
        return
    end
    self.requestedMode = self.mode == "window" and "fullscreen" or "window"
    Prefs.SetInAppView(self.requestedMode)
    self:Fit(true)
end

function Host:ResetPlacement()
    if not self:Valid() or self.mode ~= "window" then return end
    self:UserIntent()
    self.geometry = nil
    self:Fit(true)
    self:SavePlacement()
end

--- The picture that stands for the window: the current map, or the Overland icon.
--- @return string image
--- @return boolean placeholder
function Host:Image()
    local map = OverlandMapModel.GetLocation(self.selectedMapId)
    if map ~= nil and OverlandMapModel.CanOpenMap(map) then return map.imageId, false end
    return mod.images["compass-icon"] or C.panelIcon, true
end

--- The window's name as the viewer may see it: the current map's, else the panel title.
--- @return string
function Host:Name()
    local map = OverlandMapModel.GetLocation(self.selectedMapId)
    if map ~= nil and OverlandMapModel.CanOpenMap(map) then return OverlandMapModel.DisplayName(map) end
    return T("window.title")
end

function Host:HoverPreview(element)
    if not self:Valid() then return end
    local image, placeholder = self:Image()
    element.tooltip = gui.Panel {
        classes = { "bordered", "bgAlt" }, styles = ThemeEngine.GetStyles(),
        width = 240, height = "auto", flow = "vertical", interactable = false,
        gui.Panel { width = "100%", height = 135, interactable = false,
            gui.Panel { classes = { "panel", "image" }, bgimage = image, interactable = false,
                width = placeholder and 48 or "100%", height = placeholder and 48 or "100%", nostretch = not placeholder },
        },
        gui.Label { classes = { "label", "sizeS" }, text = OverlandMapCopy.Literal(self:Name()),
            width = "100%", height = "auto", textWrap = true, interactable = false },
    }
end

--- Collapse into the Tabletop button. automatic (restoring a saved layout) neither
--- animates nor saves the state, since the viewer did not ask for it.
--- @param automatic nil|boolean
function Host:Minimize(automatic)
    local state = self:State()
    if not self:Valid() or (state ~= "open" and state ~= "restoring") or not OverlandMapTabletop.CanMinimize() then return end
    if not automatic then self:UserIntent() end
    self:SavePlacement()
    local from = OverlandMapTabletop.PanelRect(self.panel)
    Enter(self, "minimizing", not automatic)
    self.allowFocus = false
    self:CancelAtlasDrag()
    self.titleDrag, self.dragging = nil, false
    Session.CloseContextMenu()
    self.content:FireEvent("overlandMapHostVisibility", false)
    self.content:FireEvent("overlandMapSuspend")
    local focus = gui.GetFocus()
    if focus ~= nil and (focus == self.panel or focus:IsDescendantOf(self.panel)) then gui.SetFocus(nil) end
    OverlandMapTabletop.SetRaiseOnPress(self.panel, false)
    self.panel:SetClass("collapsed", true)
    RestoreActionBar()
    self:SyncEngaged()
    OverlandMapTabletop.Minimize(self.external, from, not automatic and not Prefs.ReduceMotion(), function()
        self:FinishMinimize()
    end)
end

--- The button has landed. Reconciliation also calls this when Tabletop dropped the
--- flight's callback (its own reload or a game change mid-flight).
function Host:FinishMinimize()
    if self:Valid() and self:State() == "minimizing" then Enter(self, "minimized") end
end

--- Show the window again. focus marks a viewer's choice: it is saved, raised and focused.
--- Automatic restoration (focus false) never takes focus from what the viewer is doing.
--- @param focus nil|boolean
--- @param animate nil|boolean false skips the flight out of the button
function Host:Restore(focus, animate)
    if not self:Valid() then return end
    if focus then self:UserIntent() end
    if self:State() == "open" then
        if focus then
            Prefs.SaveHostState("open")
            self:Activate()
        end
        return
    end
    if not Enter(self, "restoring", focus) then return end
    self.restoreFocus = focus == true
    self.allowFocus = false
    self.content:FireEvent("overlandMapReconcile")
    self:Fit(true)
    -- The state is the guard: a newer minimize, close or teardown has moved it on.
    local function Shown()
        if not self:Valid() or self:State() ~= "restoring" then return end
        self.content:FireEvent("overlandMapReconcile")
        Enter(self, "open", focus)
        self.allowFocus = focus == true
        self.panel:SetClass("collapsed", false)
        self.content:FireEvent("overlandMapHostVisibility", true)
        self:Fit(true)
        self:SyncEngaged()
        if focus then self:Activate() end
    end
    -- SetSize always writes numbers, never "auto" or percentages.
    OverlandMapTabletop.Restore(self.external, { x = self.panel.x, y = self.panel.y,
        w = self.panel.selfStyle.width --[[@as number]], h = self.panel.selfStyle.height --[[@as number]] },
        animate ~= false and focus == true and not Prefs.ReduceMotion(), Shown)
end

-- Construction ------------------------------------------------------------------------------

--- @class OverlandMapHostCreateOptions
--- @field focus nil|boolean the viewer opened it: raise and focus it
--- @field savedState nil|"open"|"minimized" restoring a saved layout instead
--- @field popOut fun() move the map into a native popout

--- Build the in-app host on the documents layer; nil when there is no layer or one exists.
--- @param options OverlandMapHostCreateOptions
--- @return OverlandMapWindowHost|nil
function OverlandMapHost.Create(options)
    if mod.unloaded or (presence.host ~= nil and presence.host:Valid()) then return nil end
    local focus, savedState = options.focus, options.savedState
    local openingGeneration = intent.generation
    local layer = nil
    pcall(function() layer = GameHud.instance.documentsPanel end)
    if layer == nil or not layer.valid then return nil end
    if presence.host ~= nil then presence.host:Release() end
    local host = setmetatable({}, Host) --[[@as OverlandMapWindowHost]]
    local minimized = savedState == "minimized" and OverlandMapTabletop.CanMinimize()
    if not Enter(host, minimized and "restoring" or "open") then return nil end
    host.allowFocus, host.restoreFocus = focus == true, false
    host.gameId = dmhub.gameid
    host.external = OverlandMapTabletop.NewRecord(host)
    local content = OverlandMapPanel.Create {
        close = function() host:Close() end, popOut = options.popOut, mode = "fullscreen",
        visible = not minimized,
        toggleView = function() host:ToggleView() end,
        minimize = function() host:Minimize() end,
        canTabletop = function() return host:CanPlace() end,
        canFocus = function() return host:Visible() and host.allowFocus end,
        userAction = function() host:UserIntent() end,
        selectionChanged = function(id) host.selectedMapId = id end,
        openOnTabletop = function(id, atPointer) host:OpenOnTabletop(id, atPointer) end,
        atlasDragging = function(card, id) host:AtlasDragging(card, id) end,
        cancelAtlasDrag = function() return host:CancelAtlasDrag() end,
        preparePresentation = function() OverlandMapHost.UserIntent(); host:Restore(true, false) end,
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
    local optionsButton = Session.IconButton("overland-map-window-options", C.iconMore, T("window.options"), function(element)
        element.popupsInheritStyles = false
        element.popup = Session.ContextMenu(element, { entries = {
            { text = T("window.reset"), click = function()
                element.popup = nil
                host:ResetPlacement()
            end },
        } })
    end, { "overlandMapHostControl" })
    local close = Session.IconButton("overland-map-window-close", C.iconClose, T("tb.close"),
        function() host:RequestClose() end, { "overlandMapHostControl" })
    local minimize = Session.IconButton("overland-map-window-minimize", "phosphor/minus.png", T("window.minimize"),
        function() host:Minimize() end, { "overlandMapHostControl" })
    host.minimizeButton = minimize
    minimize:SetClass("collapsed", not OverlandMapTabletop.CanMinimize())
    local title = gui.Panel {
        id = "overland-map-window-title", classes = { "overlandMapWindowTitle" }, floating = true,
        swallowPress = true,
        press = function() host:BeginTitleDrag() end,
        wheel = function() return true end,
        gui.Label { classes = { "label", "sizeM" }, text = T("window.title"),
            width = "100% available", height = "auto", lmargin = 6, textAlignment = "left", valign = "center", interactable = false },
        optionsButton, minimize, close,
    }
    -- Draw above the map and title, which cover a border painted on their parent.
    local border = gui.Panel {
        id = "overland-map-window-border", classes = { "overlandMapWindowBorder", "collapsed" },
        floating = true, interactable = false,
    }
    local grip = gui.Label { classes = { "overlandMapResizeGrip", "sizeS" }, text = "//", floating = true, interactable = false }
    host.frame, host.zoom, host.content, host.title, host.border, host.grip = frame, zoom, content, title, border, grip
    host.resizer, host.resizeOptions = resizer, resizeOptions
    host.resizeWidth, host.resizeHeight = C.panelWidth, C.panelHeight
    host.requestedMode, host.mode, host.scale = Prefs.InAppView(), nil, 1
    host.geometry = Prefs.ReadWindowGeometry()
    host.hovered, host.pressed, host.dragging = false, false, false
    host.openFocus, host.nextFit = gui.GetFocus(), 0
    host.panel = gui.Panel {
        id = "overland-map-fullscreen",
        classes = minimized and { "overlandMapRoot", "collapsed" } or { "overlandMapRoot" },
        styles = ThemeEngine.MergeStyles(OverlandMapStyles.Build()),
        halign = "left", valign = "top", x = 0, y = 0, floating = true,
        swallowPress = true, thinkTime = C.canvasThinkIdle,
        data = host,
        multimonitor = { "fontsize", "iconrail", "hideactionbar" },
        monitor = function() host:Fit() end,
        create = function(element)
            OverlandMapStyles.Subscribe(element)
            host:Fit()
        end,
        rendered = function() host:LayoutContent() end,
        hover = function() host.hovered = true; host:UpdateThink(); host:SyncEngaged() end,
        dehover = function() host.hovered = false; host:UpdateThink(); host:SyncEngaged() end,
        childfocus = function() host:Raise() end,
        overlandMapInitialFocus = function(element)
            if host:Visible() and host.allowFocus and gui.GetFocus() == host.openFocus then Session.FocusHostControl(element, nil, 1) end
            host.openFocus = nil
        end,
        overlandMapCheckFocus = function(element)
            if not host:Visible() or not host.allowFocus then return end
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
            host:CancelAtlasDrag()
            OverlandMapTabletop.Release(host.external)
            -- Destroyed by something else (HUD rebuild): let reconciliation bring it back.
            if presence.host == host then
                if host.gameId == dmhub.gameid then OverlandMapHost.AllowAutomatic() end
                Enter(host, "closed")
            end
            host.allowFocus = false
            OverlandMapStyles.Unsubscribe(host.panel)
            RestoreActionBar()
        end,
        frame, title, border, grip, resizer,
    }
    layer:AddChild(host.panel)
    -- A presentation or other viewer action during construction outranks a saved minimized layout.
    local superseded = savedState ~= nil and openingGeneration ~= intent.generation
    if superseded then
        focus = true
        if host:State() == "restoring" then Enter(host, "open") end
        host.allowFocus = true
        host.panel:SetClass("collapsed", false)
        host.content:FireEvent("overlandMapHostVisibility", true)
    end
    if not focus then host.panel:SetAsFirstSibling() end
    host:Fit(true)
    host:SyncEngaged()
    if minimized and not superseded then host:Minimize(true) end
    if focus then Prefs.SaveHostState("open") end
    if focus then host.panel:ScheduleEvent("overlandMapInitialFocus", 0.01) end
    return host
end
