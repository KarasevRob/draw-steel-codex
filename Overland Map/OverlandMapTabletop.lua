local mod = dmhub.GetModLoading()

-- Everything Overland asks of the shared Tabletop (DMHub Game Hud/Tabletop.lua) goes through
-- this file, so it alone decides what the running build supports. Builds without Tabletop,
-- or with only part of it, switch off the matching feature and keep the plain in-app window.
OverlandMapTabletop = {}
local Adapter = OverlandMapTabletop
local C = OverlandMapConstants
local T = OverlandMapCopy.T
local Hosts = OverlandMapHost
-- The minimized button's rail slot: a RailEntryTypes key ("<type>:<id>", registered below).
local RAIL_KEY = "overlandmapwindow:main"

-- The Tabletop functions each feature calls. A feature is available only when all are present.
--   provider: Ctrl+Tab and the Windows menu list the window (raiseOnPress feeds their order)
--   minimize: the window collapses into a table button or rail slot
--   place:    an Atlas card dragged onto the table opens the window there
local FEATURES = {
    provider = { "RegisterWindowProvider" },
    minimize = { "IsActive", "CanMinimizeExternal", "PanelRect", "MinimizeExternal", "RestoreExternal",
        "RefreshExternal", "ReleaseExternal", "CloseExternal", "UndockExternal" },
    place = { "IsActive", "ScreenToLayer" },
}

--- @return table|nil
local function API()
    local api = rawget(_G, "Tabletop")
    return type(api) == "table" and api or nil
end

--- Whether this build has every Tabletop function a feature needs.
--- @param feature "provider"|"minimize"|"place"
--- @return boolean
function OverlandMapTabletop.Has(feature)
    local api = API()
    if api == nil then return false end
    for _, name in ipairs(FEATURES[feature]) do
        if type(api[name]) ~= "function" then return false end
    end
    return true
end

--- Minimizing is possible right now: supported, and the table's button layer is up.
--- @return boolean
function OverlandMapTabletop.CanMinimize()
    return Adapter.Has("minimize") and API().CanMinimizeExternal()
end

--- Screen pixels (top-left origin) to documents-layer units; nil until the layer is laid out.
--- @return number|nil x
--- @return number|nil y
function OverlandMapTabletop.ScreenToLayer(x, y)
    if not Adapter.Has("place") then return nil, nil end
    return API().ScreenToLayer(x, y)
end

--- Older panels reject raiseOnPress; the switcher builds that understand it also order
--- windows by the activation it stamps.
--- @param panel Panel
--- @param on boolean
function OverlandMapTabletop.SetRaiseOnPress(panel, on)
    if Adapter.Has("provider") and panel.raiseOnPress ~= on then panel.raiseOnPress = on end
end

--- Mark the panel as most recently used without changing its sibling order (fullscreen
--- stays behind other windows). Turning raiseOnPress on stamps activationOrder.
--- @param panel Panel
function OverlandMapTabletop.StampActivation(panel)
    if not Adapter.Has("provider") then return end
    panel.raiseOnPress = true
    panel.raiseOnPress = false
end

-- Minimized button -------------------------------------------------------------------------

--- The record Tabletop keeps the host's minimized button on (see "Windows this file does
--- not own" in Tabletop.lua). Its position is the viewer's preference.
--- @param host OverlandMapWindowHost
--- @return table
function OverlandMapTabletop.NewRecord(host)
    local position = OverlandMapPreferences.MinimizedPosition()
    return {
        id = "overland-map", railKey = RAIL_KEY,
        iconX = position and position.x, iconY = position and position.y,
        buttonOps = {
            icon = mod.images["compass-icon"] or C.panelIcon,
            image = function() return host:Image() end,
            restore = function() host:Restore(true) end,
            close = function() host:RequestClose() end,
            closeText = T("tb.close"),
            hover = function(_, element) host:HoverPreview(element) end,
            chatItems = function() return {} end,
            badge = { icon = C.panelIcon, color = "clear" },
            badgeShown = function() return false end,
            placementChanged = function(rec)
                if host:Valid() then OverlandMapPreferences.SaveMinimizedPosition(rec.iconX, rec.iconY) end
            end,
        },
    }
end

--- Fly the window into its button. Tabletop does not report the landing; lifecycle
--- reconciliation notices when the flight is over (Animating) and settles the state.
--- @param rec table
--- @param from nil|{x: number, y: number, w: number, h: number}
--- @param animate boolean
function OverlandMapTabletop.Minimize(rec, from, animate)
    if not Adapter.Has("minimize") then return end
    API().MinimizeExternal(rec, from, { animate = animate })
end

--- Grow the window back out of its button, then call done. Without Tabletop, done runs now.
--- @param rec table
--- @param to {x: number, y: number, w: number, h: number}
--- @param animate boolean
--- @param done fun()
function OverlandMapTabletop.Restore(rec, to, animate, done)
    if not Adapter.Has("minimize") then done(); return end
    API().RestoreExternal(rec, to, done, { animate = animate })
end

--- A panel's rectangle in documents-layer units: where a minimize animation starts.
--- @param panel Panel
--- @return nil|{x: number, y: number, w: number, h: number}
function OverlandMapTabletop.PanelRect(panel)
    if not Adapter.Has("minimize") then return nil end
    return API().PanelRect(panel)
end

--- Reconcile the button after a viewport, scale or rail change.
--- @param rec table
function OverlandMapTabletop.Refresh(rec)
    if Adapter.Has("minimize") then API().RefreshExternal(rec) end
end

--- Teardown: the button goes, the rail slot stays for when the window comes back.
--- @param rec table
function OverlandMapTabletop.Release(rec)
    if rec ~= nil and Adapter.Has("minimize") then API().ReleaseExternal(rec) end
end

--- The viewer closed the window: the rail slot goes too.
--- @param rec table
function OverlandMapTabletop.Close(rec)
    if rec ~= nil and Adapter.Has("minimize") then API().CloseExternal(rec) end
end

--- @param rec table
--- @return boolean
function OverlandMapTabletop.Animating(rec)
    return rec.externalAnimating == true
end

-- Atlas placement --------------------------------------------------------------------------
-- These extend the host class: dragging an Atlas card onto the table opens the map there.

--- @class OverlandMapWindowHost
--- @field atlasDrag OverlandMapAtlasDrag|nil
local Host = Hosts.Host

--- @class OverlandMapAtlasDrag
--- @field card Panel
--- @field id string
--- @field preview Panel|nil

function Host:CanPlace()
    return self:Visible() and Adapter.Has("place") and API().IsActive() and API().ScreenToLayer(0, 0) ~= nil
end

--- @return boolean cancelled whether a drag was in progress
function Host:CancelAtlasDrag()
    local drag = self.atlasDrag
    self.atlasDrag = nil
    if drag == nil then return false end
    if drag.card ~= nil and drag.card.valid then drag.card.data.placementCancelled = true end
    if drag.preview ~= nil and drag.preview.valid then drag.preview:DestroySelf() end
    return true
end

--- Both the preview and the accepted drop use this same placement calculation.
--- @param id string
--- @param atPointer nil|boolean centre on the pointer (a drop) instead of the saved placement
function Host:TablePlacement(id, atPointer)
    if not self:CanPlace() then return end
    local map = OverlandMapModel.GetLocation(id)
    local area = self:WorkArea()
    if map == nil or not OverlandMapModel.CanOpenMap(map) or area == nil or not Hosts.WindowFits(area) then return end
    local x, y
    if atPointer then
        if self.mode ~= "window" or dmhub.panelDropSurface ~= "table" then return end
        local mouse = dmhub.mouseScreenPosition
        x, y = Adapter.ScreenToLayer(mouse.x, mouse.y)
        if x == nil or y == nil then return end
    end
    return self:Placement(self.geometry, x, y)
end

--- @param card Panel
--- @param id string
function Host:AtlasDragging(card, id)
    if card.data.placementCancelled then return end
    if self.atlasDrag ~= nil and self.atlasDrag.card ~= card then self:CancelAtlasDrag() end
    local placement = self:TablePlacement(id, true)
    local drag = self.atlasDrag or { card = card, id = id }
    self.atlasDrag = drag
    if placement == nil then
        if drag.preview ~= nil and drag.preview.valid then drag.preview:DestroySelf() end
        drag.preview = nil
        return
    end
    if drag.preview == nil or not drag.preview.valid then
        local layer = self.panel.parent
        if layer == nil or not layer.valid then self:CancelAtlasDrag(); return end
        local map = OverlandMapModel.GetLocation(id)
        if map == nil or not OverlandMapModel.CanOpenMap(map) then self:CancelAtlasDrag(); return end
        drag.preview = gui.Panel {
            id = "overland-map-placement-preview", classes = { "bordered", "bgAlt" },
            styles = ThemeEngine.GetStyles(), floating = true, interactable = false,
            halign = "left", valign = "top", flow = "vertical",
            captureEscape = true, escapePriority = EscapePriority.DMHUB_POPUP,
            escape = function() self:CancelAtlasDrag() end,
            gui.Label { classes = { "label", "sizeM" }, text = OverlandMapCopy.Literal(OverlandMapModel.DisplayName(map)),
                width = "100%", height = "auto", textOverflow = "ellipsis", textWrap = false },
            gui.Panel { classes = { "panel", "image" }, bgimageStreamed = map.imageId, width = "100%", height = "100% available" },
        }
        layer:AddChild(drag.preview)
        drag.preview:MakeNonInteractiveRecursive()
    end
    drag.preview.x, drag.preview.y = placement.x * self.scale, placement.y * self.scale
    drag.preview.selfStyle.width, drag.preview.selfStyle.height = placement.width * self.scale, placement.height * self.scale
end

--- Open a map in the window on the table: at the pointer for a drop, else where it was.
--- @param id string
--- @param atPointer nil|boolean
function Host:OpenOnTabletop(id, atPointer)
    local placement = self:TablePlacement(id, atPointer)
    if placement == nil then
        local area = self:WorkArea()
        if not atPointer and area ~= nil and not Hosts.WindowFits(area) then
            OverlandMapUndo.Notify("window.tooSmall", { width = C.windowMinWidth, height = C.windowMinHeight })
        end
        self:CancelAtlasDrag()
        return
    end
    self:UserIntent()
    self:CancelAtlasDrag()
    self.content:FireEvent("overlandMapNavigate", id, false, function()
        if not self:Valid() then return end
        self.requestedMode, self.geometry = "window", placement
        OverlandMapPreferences.SetInAppView("window")
        self:Fit(true)
        self:SavePlacement()
        OverlandMapPreferences.SaveHostState("open")
        self:Activate()
    end)
end

-- Window lists ------------------------------------------------------------------------------

local providerAPI, unsubscribe = nil, nil

--- Keep Overland listed in Ctrl+Tab and the Windows menu, re-registering if Tabletop was
--- reloaded (its table is replaced). Called from lifecycle reconciliation.
function OverlandMapTabletop.SyncProvider()
    local api = Adapter.Has("provider") and API() or nil
    if api == providerAPI then return end
    if unsubscribe ~= nil then unsubscribe(); unsubscribe = nil end
    providerAPI = api
    if api == nil then return end
    local host = Hosts.Current()
    if host ~= nil and host:Valid() then host:Fit(true) end
    unsubscribe = api.RegisterWindowProvider("overland-map", mod, function()
        local current = Hosts.Current()
        if current == nil or not current:Valid() then return {} end
        local image, placeholder = current:Image()
        return { {
            key = "external:overland-map", kind = "external", panel = current.panel,
            name = current:Name(), detail = T("window.title"), icon = mod.images["compass-icon"] or C.panelIcon,
            image = image, placeholder = placeholder, minimized = current:State() ~= "open",
            activate = function() current:Activate() end,
        } }
    end)
end

-- The movable rail entry; distinct from the permanent launcher, which DockablePanel owns.
RailEntryTypes = rawget(_G, "RailEntryTypes") or {}
RailEntryTypes.overlandmapwindow = {
    available = function(id)
        local host = Hosts.Current()
        return id == "main" and not mod.unloaded and host ~= nil and host:Valid()
    end,
    name = function() return T("window.title") end,
    icon = function() return mod.images["compass-icon"] or C.panelIcon end,
    isActive = function()
        local host = Hosts.Current()
        return host ~= nil and host:Visible()
    end,
    activate = function()
        local host = Hosts.Current()
        if host == nil or not host:Valid() then return end
        if host:State() == "open" then host:Minimize() else host:Restore(true) end
    end,
    hover = function(_, element)
        local host = Hosts.Current()
        if host ~= nil then host:HoverPreview(element) end
    end,
    menu = function(_, element)
        local host = Hosts.Current()
        if host == nil or not host:Valid() then return {} end
        return {
            { text = T(host:State() == "open" and "window.minimize" or "window.restore"), click = function()
                element.popup = nil
                if host:State() == "open" then host:Minimize() else host:Restore(true) end
            end },
            { text = T("tb.close"), click = function() element.popup = nil; host:RequestClose() end },
        }
    end,
    onRemove = function()
        local host = Hosts.Current()
        if host ~= nil and host:Valid() and Adapter.Has("minimize") then API().UndockExternal(host.external) end
    end,
}

mod.unloadHandlers[#mod.unloadHandlers + 1] = function()
    if unsubscribe ~= nil then unsubscribe(); unsubscribe = nil end
end
Adapter.SyncProvider()
