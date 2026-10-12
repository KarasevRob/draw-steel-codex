local mod = dmhub.GetModLoading()

-- Region Map bootstrap: checks the host once, registers the panel and the
-- presentable dialog, and hosts the map fullscreen or in a native popout. Region Map
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

-- Fullscreen host ----------------------------------------------------------------------
-- The map opens over the whole game screen, on each client separately: the rail
-- button and the Game menu toggle it, Esc at the Atlas closes it, and Show to
-- players opens it on every client, where each player closes it when they like.
-- It sits at the bottom of the documents layer, so the icon rails, the chat
-- bubble and any window opened over it (a journal page, a character sheet) stay
-- on top. It can also move into its own OS window (the host's native popout).

local POPOUT_KEY = string.lower(C.panelName)

local fullscreen = nil --- @type Panel|nil the open fullscreen host, if any

-- The action bar draws above the documents layer, so it would cover the bottom
-- of the map; hide it through the transient setting it monitors while the map is up.
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
    local railModeActive = rawget(_G, "RailModeActive")
    if type(railModeActive) ~= "function" then return false end
    local ok, active = pcall(railModeActive)
    return ok and active == true
end

local function IsFullscreen()
    return fullscreen ~= nil and fullscreen.valid
end

local function CloseFullscreen()
    if IsFullscreen() then fullscreen:DestroySelf() end
    fullscreen = nil
end

local OpenFullscreen

local function PopOut()
    CloseFullscreen()
    PanelDocument.OpenPopout(C.panelName, { width = C.windowWidth, height = C.windowHeight, scale = 1 })
end

-- The popout's own "return to the app" button cannot reopen an action
-- registration, so the map offers this in its toolbar instead.
local function PopIn()
    PanelDocument.PopoutForgetWindow(POPOUT_KEY)
    local host = PanelDocument.PopoutHost(POPOUT_KEY)
    if host ~= nil then host:DestroySelf() end
    OpenFullscreen()
end

--- Lay the map out in the documents layer: between the icon rails in rail mode
--- (measured like the rails themselves, DocumentSystem.lua ICON_RAIL_* and
--- IconRailTop), the whole layer otherwise. In rail mode Font Size zooms the
--- map as it zooms windows (PanelDocument.WindowUIScale), so `zoom` carries
--- that scale and a size that is the frame's divided by it.
--- @param host Panel
local function FitFullscreen(host)
    local layer = host.parent
    local frame, zoom = host.data.frame, host.data.zoom
    if layer == nil or frame == nil or zoom == nil then return end
    local layerW, layerH = layer.renderedWidth, layer.renderedHeight
    if type(layerW) ~= "number" or type(layerH) ~= "number" or layerW <= 0 or layerH <= 0 then return end
    local scale = 1
    local ok, value = pcall(PanelDocument.WindowUIScale)
    if ok and type(value) == "number" and value > 0 then scale = value end
    local side, top, bottom = 0, 0, 0
    if RailMode() then
        side = C.railInset + C.railButton * scale + C.railGap
        top = math.max(C.railTopMin, (C.railButton + C.railStopGap) * scale + C.railStopGap)
        bottom = C.railGap
    end
    local width, height = math.max(1, layerW - 2 * side), math.max(1, layerH - top - bottom)
    local key = string.format("%.3f %.1f %.1f %.1f %.1f", scale, side, top, width, height)
    if host.data.fit == key then return end
    host.data.fit = key
    frame.selfStyle.lmargin, frame.selfStyle.tmargin = side, top
    frame.selfStyle.width, frame.selfStyle.height = width, height
    -- Named pivot on the top-left corner, the same recipe as the host's rail windows.
    zoom.selfStyle.pivot = { x = 0, y = 1 }
    zoom.selfStyle.uiscale = scale
    zoom.selfStyle.width, zoom.selfStyle.height = width / scale, height / scale
end

OpenFullscreen = function()
    if mod.unloaded then return end
    if IsFullscreen() then return end
    local layer = nil
    pcall(function() layer = GameHud.instance.documentsPanel end)
    if layer == nil or not layer.valid then return end
    local zoom = gui.Panel {
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
        RegionMapPanel.Create { close = CloseFullscreen, popOut = PopOut },
    }
    local frame = gui.Panel {
        floating = true,
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
        zoom,
    }
    local host
    host = gui.Panel {
        id = "region-map-fullscreen",
        -- The root's styles and class give the margins under the rails the map's background.
        classes = { "regionMapRoot" },
        styles = ThemeEngine.MergeStyles(RegionMapStyles.Build()),
        halign = "left",
        valign = "top",
        -- The board below must not take presses meant for the map.
        swallowPress = true,
        thinkTime = 0.25,
        data = { fit = nil, frame = frame, zoom = zoom },
        multimonitor = { "fontsize", "iconrail" },
        monitor = function(element) FitFullscreen(element) end,
        create = function(element)
            RegionMapStyles.Subscribe(element)
            HideActionBar()
            FitFullscreen(element)
        end,
        think = function(element)
            -- A Lua reload builds a new host; this one goes with the old code.
            if mod.unloaded then
                element:DestroySelf()
                return
            end
            -- Stay under everything else on the layer (the chat bubble parks itself at the bottom).
            if element.siblingIndex ~= 1 then element:SetAsFirstSibling() end
            FitFullscreen(element)
        end,
        destroy = function(element)
            if fullscreen == host then fullscreen = nil end
            RegionMapStyles.Unsubscribe(element)
            RestoreActionBar()
        end,
        frame,
    }
    fullscreen = host
    layer:AddChild(host)
    host:SetAsFirstSibling()
end

local function ShowFullscreen()
    -- Popped out: bring that window forward rather than opening a second map.
    local popout = PanelDocument.PopoutHost(POPOUT_KEY)
    if popout ~= nil then
        pcall(function() popout:RaiseNativeWindow() end)
        return
    end
    OpenFullscreen()
end

local function ToggleFullscreen()
    if IsFullscreen() then
        CloseFullscreen()
    else
        ShowFullscreen()
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
    launch = ToggleFullscreen,
    content = function()
        return RegionMapPanel.Create { popIn = PopIn }
    end,
}

-- keeplocal = false: every client, the presenter included, opens its own
-- map; the panel then reads the presentation itself. Show, never toggle:
-- a map that is already open stays open.
GameHud.RegisterPresentableDialog {
    id = C.panelName,
    keeplocal = false,
    create = function()
        ShowFullscreen()
        return nil
    end,
}

print("REGION_MAP: addon loaded")
