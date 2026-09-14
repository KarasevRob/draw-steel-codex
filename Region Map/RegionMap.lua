local mod = dmhub.GetModLoading()

-- Region Map is an independent CodeMod. It intentionally depends only on
-- public DMHub UI/game services and does not alter tactical maps.
RegionMapAddon = rawget(_G, "RegionMapAddon") or {}
local Addon = RegionMapAddon
Addon.activeMod = mod

local Model = Addon.Model
local Styles = Addon.Styles
local Panel = Addon.Panel
local PANEL_NAME = Addon.panelName or "Region Map"

local DockablePanel = rawget(_G, "DockablePanel")
local PanelDocument = rawget(_G, "PanelDocument")
local ThemeEngine = rawget(_G, "ThemeEngine")
local GameHud = rawget(_G, "GameHud")
local gui = rawget(_G, "gui")
local RegisterDockablePanelOpenHandler = rawget(_G, "RegisterDockablePanelOpenHandler")
if DockablePanel == nil or type(DockablePanel.Register) ~= "function"
    or type(DockablePanel.Deregister) ~= "function" or type(DockablePanel.LaunchPanelByName) ~= "function"
    or type(DockablePanel.ShowPanelByName) ~= "function"
    or PanelDocument == nil or type(PanelDocument.Get) ~= "function"
    or type(PanelDocument.IsPinned) ~= "function"
    or ThemeEngine == nil or GameHud == nil
    or type(GameHud.RegisterPresentableDialog) ~= "function"
    or gui == nil or type(gui.IconEditor) ~= "function"
    or type(RegisterDockablePanelOpenHandler) ~= "function" then
    print("REGION_MAP: required DMHub UI services are unavailable; registration skipped")
    return
end

if Model == nil or Model.ready ~= true or Styles == nil or Styles.ready ~= true
    or Panel == nil or Panel.ready ~= true then
    print("REGION_MAP: required addon modules are unavailable; check CodeMod load order")
    return
end

Addon.CalculateImageLayout = Panel.CalculateImageLayout
Addon.ImageToPanel = Panel.ImageToPanel
Addon.PanelToImage = Panel.PanelToImage
Addon.CreatePanel = Panel.Create

-- Close any legacy side-dock instance before replacing its registration.
-- Region Map is hosted in a journal-style PanelDocument window below.
DockablePanel.LaunchPanelByName(PANEL_NAME, "hide")
DockablePanel.Deregister(PANEL_NAME)
local registration = {
    name = PANEL_NAME,
    icon = "phosphor/map-trifold.png",
    dmonly = false,
    vscroll = false,
    minWidth = 720,
    maxWidth = 1600,
    minHeight = 480,
    maxHeight = 1000,
    popoutHeight = 720,
    resizableWidth = true,
    resizableHeight = true,
    menu = "game",
    content = Panel.Create,
}
DockablePanel.Register(registration)
-- The host adds its header to content bounds. Derive that allowance from
-- the public resize contract rather than duplicating the host's constant.
local document = PanelDocument.Get(PANEL_NAME)
if document ~= nil then
    local ok, options = pcall(function() return document:WindowResizeOptions() end)
    if ok and type(options) == "table" and type(options.minHeight) == "number" then
        local headerHeight = options.minHeight - registration.minHeight
        if headerHeight >= 0 and headerHeight < 480 then
            registration.minHeight = 480 - headerHeight
            DockablePanel.Register(registration)
        end
    end
end

-- Take ownership before the ordinary dock and icon-rail handlers. This
-- uses the same draggable, resizable, pinnable and header-shade window host
-- as journal-style panel documents, but starts at region-map scale.
RegisterDockablePanelOpenHandler("00-region-map-window", function(panelName, operation)
    if mod.unloaded or string.lower(panelName or "") ~= string.lower(PANEL_NAME) then
        return false
    end

    local document = PanelDocument.Get(PANEL_NAME)
    if document == nil then return false end

    if document:PresentDocumentOpen() then
        if operation == "hide" or operation == nil then
            if PanelDocument.IsPinned(PANEL_NAME) then
                document:PresentPanel()
            else
                document:ClosePanel()
            end
        else
            document:PresentPanel()
        end
        return true
    end

    if operation ~= "hide" then
        document:PresentPanel { width = 1000, height = 800 }
    end
    return true
end)

Addon.Open = function()
    if mod.unloaded then return false end
    return DockablePanel.ShowPanelByName(PANEL_NAME)
end

GameHud.RegisterPresentableDialog {
    id = PANEL_NAME,
    keeplocal = false,
    create = function()
        if not mod.unloaded then Addon.Open() end
        return nil
    end,
}

print("REGION_MAP: addon loaded")
