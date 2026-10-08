local mod = dmhub.GetModLoading()

-- Region Map bootstrap: checks the host once, registers the panel and the
-- presentable dialog, and adapts the host window to the map's size. Region Map
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
    Need(type(rawget(_G, "RegisterDockablePanelOpenHandler")) == "function", "RegisterDockablePanelOpenHandler")
    Need(dockable ~= nil and type(dockable.Register) == "function"
        and type(dockable.ShowPanelByName) == "function" and type(dockable.LaunchPanelByName) == "function", "DockablePanel")
    Need(panelDocument ~= nil and type(panelDocument.Get) == "function"
        and type(panelDocument.IsPinned) == "function", "PanelDocument")
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

-- Host window adapter ---------------------------------------------------------------
-- Everything below reads documented host details that are not a formal API:
-- PanelDocument._tmp_location (remembered window geometry), the window's
-- "journalViewer" class, dialog.data.resizePanel (DialogResize.lua) and
-- RailModeActive. Each is guarded; if one disappears the window simply keeps
-- the host's default size.

local function ScreenKey()
    return dmhub.screenDimensionsBelowTitlebar.x, dmhub.screenDimensionsBelowTitlebar.y
end

-- The first open of a session carries the map's default size. Seeded only when
-- nothing is remembered, so a size the user chose is never overwritten.
local function SeedWindowSize(doc)
    local ok, remembered = pcall(function() return doc:try_get("_tmp_location") end)
    if not ok or remembered ~= nil then return end
    local sx, sy = ScreenKey()
    pcall(function()
        doc._tmp_location = { width = C.windowWidth, height = C.windowHeight, screenx = sx, screeny = sy }
    end)
end

local function RailMode()
    local railModeActive = rawget(_G, "RailModeActive")
    if type(railModeActive) ~= "function" then return false end
    local ok, active = pcall(railModeActive)
    return ok and active == true
end

local function WindowSize(window)
    local w, h = window.selfStyle.width, window.selfStyle.height
    if type(w) ~= "number" then w = window.renderedWidth end
    if type(h) ~= "number" then h = window.renderedHeight end
    return w, h
end

--- Grow the host window to the map's minimum size (or to its default size on a
--- first open at the host's generic size) and keep it on screen. Follows the
--- resize overlay's contract in DialogResize.lua: write the size, then announce
--- it as deltas so the resize handles stay on the window edges. Native popouts
--- have no journalViewer ancestor, so this is a no-op there.
--- @param root Panel the Region Map content root
local function FitHostWindow(root)
    if mod.unloaded or not root.valid or PanelDocument.IsPinned(C.panelName) then return end
    local window = root:FindParentWithClass("journalViewer")
    local doc = PanelDocument.Get(C.panelName)
    if window == nil or not window.valid or doc == nil then return end
    local w, h = WindowSize(window)
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return end
    local remembered = doc:try_get("_tmp_location")
    local targetW = math.max(w, C.windowMinWidth)
    local targetH = math.max(h, C.windowMinHeight)
    if remembered == nil and math.abs(w - PanelDocument.DefaultWidth) < 1 then
        targetW, targetH = C.windowWidth, C.windowHeight
    end
    local sx, sy = ScreenKey()
    -- PresentDocument places windows in a space 1080 tall and as wide as the screen's aspect.
    local virtualWidth = C.hostVirtualHeight * sx / sy
    -- In rail mode the window is drawn scaled by Font Size, growing down and
    -- right from its top-left corner, so its on-screen extent is size * scale.
    local scale = 1
    local scaleOk, value = pcall(PanelDocument.WindowUIScale)
    if scaleOk and type(value) == "number" and value > 0 then scale = value end
    local extentW, extentH = targetW * scale, targetH * scale
    local x, y = window.x, window.y
    local maxRight, maxBottom = virtualWidth - C.hostEdgeMargin, C.hostVirtualHeight - C.hostEdgeMargin
    if type(x) == "number" and x + extentW > maxRight then x = math.max(0, maxRight - extentW) end
    if type(y) == "number" and y + extentH > maxBottom then y = math.max(0, maxBottom - extentH) end
    if targetW == w and targetH == h and x == window.x and y == window.y then return end
    window.selfStyle.width, window.selfStyle.height = targetW, targetH
    if x ~= window.x then window.x = x end
    if y ~= window.y then window.y = y end
    local overlay = window.data.resizePanel
    if overlay ~= nil and overlay.valid and (targetW ~= w or targetH ~= h) then
        overlay:FireEventTree("resize", nil, { deltax = targetW - w, deltay = targetH - h })
    end
    doc._tmp_location = {
        x = window.x, y = window.y, width = targetW, height = targetH,
        moved = remembered ~= nil and remembered.moved == true,
        screenx = sx, screeny = sy,
    }
end

-- Expand (D13a) ------------------------------------------------------------------------
-- Fills the play area: the screen minus the two icon rails and the title-bar
-- gap, measured like the rail itself (DocumentSystem.lua ICON_RAIL_* and
-- IconRailTop). The window's previous geometry is kept here, not in
-- _tmp_location, so Restore returns exactly to it.

local expandedFrom = nil --- @type nil|{x: number, y: number, width: number, height: number}
local expandedTo = nil --- @type nil|{width: number, height: number}

local function HostWindow(root)
    if mod.unloaded or not root.valid or PanelDocument.IsPinned(C.panelName) then return nil, nil end
    local window = root:FindParentWithClass("journalViewer")
    local doc = PanelDocument.Get(C.panelName)
    if window == nil or not window.valid or doc == nil then return nil, nil end
    return window, doc
end

local function UIScale()
    local ok, value = pcall(PanelDocument.WindowUIScale)
    if ok and type(value) == "number" and value > 0 then return value end
    return 1
end

-- Move and resize the window, then announce the size change to the resize
-- overlay (same contract as FitHostWindow) and remember it like a user resize.
local function SetWindowGeometry(window, doc, x, y, width, height)
    local w, h = WindowSize(window)
    window.selfStyle.width, window.selfStyle.height = width, height
    window.x, window.y = x, y
    local overlay = window.data.resizePanel
    if overlay ~= nil and overlay.valid and type(w) == "number" and type(h) == "number" and (width ~= w or height ~= h) then
        overlay:FireEventTree("resize", nil, { deltax = width - w, deltay = height - h })
    end
    local sx, sy = ScreenKey()
    doc._tmp_location = { x = x, y = y, width = width, height = height, moved = true, screenx = sx, screeny = sy }
end

--- The play area in window units: x, y, width, height. Measured against the
--- layer the window lives in (the screen below the app's title bar); the
--- 1080-tall placement space is only an estimate when that is not laid out.
local function PlayArea(window)
    local sx, sy = ScreenKey()
    local scale = UIScale()
    local layer = window.parent
    local layerW, layerH = C.hostVirtualHeight * sx / sy, C.hostVirtualHeight
    if layer ~= nil and type(layer.renderedWidth) == "number" and type(layer.renderedHeight) == "number"
        and layer.renderedWidth > 0 and layer.renderedHeight > 0 then
        layerW, layerH = layer.renderedWidth, layer.renderedHeight
    end
    local side = C.expandRailInset + C.expandRailButton * scale + C.expandGap
    local top = math.max(C.expandTopInset, (C.expandRailButton + C.expandRailInset) * scale + C.expandRailInset)
    local width = math.min(C.windowMaxWidth, (layerW - 2 * side) / scale)
    local height = math.min(C.windowMaxHeight, (layerH - top - C.expandGap) / scale)
    return side, top, width, height
end

local function CanExpand(root)
    return HostWindow(root) ~= nil
end

--- Whether the window is still expanded. A resize by the user since Expand
--- clears the state, so the toggle then offers Expand again.
local function IsExpanded(root)
    if expandedTo == nil then return false end
    local window = HostWindow(root)
    local w, h = nil, nil
    if window ~= nil then w, h = WindowSize(window) end
    if window == nil or type(w) ~= "number" or type(h) ~= "number"
        or math.abs(w - expandedTo.width) > 1 or math.abs(h - expandedTo.height) > 1 then
        expandedFrom, expandedTo = nil, nil
        return false
    end
    return true
end

local function ToggleExpand(root)
    local window, doc = HostWindow(root)
    if window == nil or doc == nil then return end
    if IsExpanded(root) and expandedFrom ~= nil then
        local from = expandedFrom
        expandedFrom, expandedTo = nil, nil
        SetWindowGeometry(window, doc, from.x, from.y, from.width, from.height)
        return
    end
    local w, h = WindowSize(window)
    if type(w) ~= "number" or type(h) ~= "number" then return end
    expandedFrom = { x = window.x, y = window.y, width = w, height = h }
    local x, y, width, height = PlayArea(window)
    expandedTo = { width = width, height = height }
    SetWindowGeometry(window, doc, x, y, width, height)
end

-- Registration -------------------------------------------------------------------------

-- Close any legacy instance before replacing its registration (Lua reloads).
DockablePanel.LaunchPanelByName(C.panelName, "hide")
DockablePanel.Deregister(C.panelName)
local registration = {
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
    content = function()
        return RegionMapPanel.Create {
            fitHost = FitHostWindow, canExpand = CanExpand, isExpanded = IsExpanded, toggleExpand = ToggleExpand,
        }
    end,
}
DockablePanel.Register(registration)

-- The registration's height bounds describe the content; the window adds its
-- header. Derive that header from the public resize options rather than
-- copying the host's constant, so the window's minimum is the mod's minimum.
local function ContentMinHeight()
    local doc = PanelDocument.Get(C.panelName)
    if doc == nil then return nil end
    local ok, resizeOptions = pcall(function() return doc:WindowResizeOptions() end)
    if not ok or type(resizeOptions) ~= "table" or type(resizeOptions.minHeight) ~= "number" then return nil end
    local header = resizeOptions.minHeight - registration.minHeight
    if header < 0 or header >= C.windowMinHeight then return nil end
    return C.windowMinHeight - header
end

local contentMinHeight = ContentMinHeight()
if contentMinHeight ~= nil then
    registration.minHeight = contentMinHeight
    DockablePanel.Register(registration)
end

-- Runs before the icon rail's "iconrail" handler (ids run in sorted order) so
-- the first open of a session can carry the map's default size. In rail mode it
-- only seeds geometry and returns false: the rail keeps the button, anchoring,
-- pinning and persistence. With the rail off, a 720px canvas cannot live in a
-- dock column, so the mod hosts its own floating window.
RegisterDockablePanelOpenHandler(C.openHandlerId, function(panelName, operation)
    if mod.unloaded or string.lower(panelName or "") ~= string.lower(C.panelName) then
        return false
    end
    local doc = PanelDocument.Get(C.panelName)
    if doc == nil then return false end
    if operation ~= "hide" then SeedWindowSize(doc) end
    if RailMode() then return false end

    if doc:PresentDocumentOpen() then
        if operation == "show" or PanelDocument.IsPinned(C.panelName) then
            doc:PresentPanel()
        else
            doc:ClosePanel()
        end
        return true
    end
    if operation ~= "hide" then
        doc:PresentPanel { width = C.windowWidth, height = C.windowHeight }
    end
    return true
end)

local function Open()
    if mod.unloaded then return false end
    return DockablePanel.ShowPanelByName(C.panelName)
end

-- keeplocal = false: every client, the presenter included, opens its own
-- Region Map window; the panel then reads the presentation itself.
GameHud.RegisterPresentableDialog {
    id = C.panelName,
    keeplocal = false,
    create = function()
        Open()
        return nil
    end,
}

print("REGION_MAP: addon loaded")
