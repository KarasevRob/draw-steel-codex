local mod = dmhub.GetModLoading()

--- What the Region Map components share: the context contract, the viewer's
--- own preferences (last map, cameras, Show names, last pin style) and the
--- Font Size scale for pins and panels.
--- @class RegionMapSession: GameType
--- @field new fun(o?: table): RegionMapSession
RegionMapSession = RegisterGameType("RegionMapSession")
local C = RegionMapConstants
local Model = RegionMapModel

--- A saved per-viewer camera. zoom 1 fits the whole map in the canvas.
--- @class RegionMapCamera
--- @field zoom number
--- @field centerX number 0..1 across the image
--- @field centerY number 0..1 down the image

--- The shell's state. Components read it; only the shell and the functions on
--- the context change it.
--- @class RegionMapShellData
--- @field mapId nil|string the open map; nil shows the Atlas
--- @field selectedId nil|string the Location in the side panel
--- @field panelMode "none"|"read"|"edit"|"pickImage"|"pickMap"|"pickJournal"|"log" "log" is the session log panel
--- @field pickKind nil|"add"|"replace" what pickImage does with the image
--- @field locked boolean pins cannot be dragged (R6); per viewer, true on every map open
--- @field tool "none"|"add"|"move"|"ruler"|"scale" "add" and "ruler" stay on until Esc (R10, R7)
--- @field toolTargetId nil|string the Location "move" places
--- @field camera RegionMapCamera
--- @field focusName boolean the side panel puts the caret in the name field once
--- @field popover nil|"search"|"settings" the popover open under the toolbar
--- @field ruler nil|RegionMapMeasure the ruler's points (local, never written)
--- @field scaleDraft nil|RegionMapMeasure the two scale points picked so far, until a distance is entered
--- @field expanded boolean the window fills the play area (D13a)

--- Two points on the open map. The second is absent while only a start is picked.
--- @class RegionMapMeasure
--- @field mapId string
--- @field u1 number
--- @field v1 number
--- @field u2 nil|number
--- @field v2 nil|number
--- @field unit nil|"mi"|"km" scale drafts only: the unit picked before the distance

--- Shared services handed to every component. Components call these; the
--- shell answers by firing events on component roots.
--- @class RegionMapContext
--- @field data RegionMapShellData
--- @field root Panel
--- @field IsAlive fun(): boolean
--- @field CurrentMap fun(): nil|RegionMapLocationRecord
--- @field OpenMap fun(id: string, how: nil|"down"|"up"|"jump"|"fit"|"restore")
--- @field GoAtlas fun()
--- @field GoUp fun()
--- @field Select fun(id: nil|string, mode: nil|string)
--- @field SetTool fun(tool: string, targetId: nil|string)
--- @field RefreshAll fun()
--- @field FlushEdits fun()
--- @field ShowMenu fun(element: Panel, id: string)
--- @field Report fun(ok: boolean, reason: nil|string): boolean shows a toast for a failed write
--- @field Push fun(entry: nil|RegionMapUndoEntry, copyId: string, args: nil|table)
--- @field ShowToPlayers fun()
--- @field Confirm fun(args: {title: string, message: nil|string, confirm: string, onConfirm: fun()}) compact in-window confirm dialog
--- @field FocusLocation fun(id: string) open the map a Location is on, center it and select it (Search)
--- @field SetPopover fun(popover: nil|"search"|"settings") open or close a toolbar popover
--- @field ToggleLog fun() open or close the session log panel
--- @field CanExpand fun(): boolean
--- @field ToggleExpand fun()

-- Preferences (per viewer and game) ------------------------------------------------------------

local function ReadPreferences()
    local prefs = dmhub.GetSettingValue(C.preferencesSettingId)
    return type(prefs) == "table" and DeepCopy(prefs) or {}
end

local function WritePreferences(prefs)
    dmhub.SetSettingValue(C.preferencesSettingId, prefs)
end

-- Cameras are keyed by map and image revision, so a replaced image starts fitted.
local function CameraKey(location)
    return string.format("%s:%.0f", location.id, location.imageRevision)
end

--- The camera this viewer last used on a map.
--- @param location RegionMapLocationRecord
--- @return RegionMapCamera camera
--- @return boolean restored false when nothing was saved for the current image
function RegionMapSession.ReadCamera(location)
    local prefs = ReadPreferences()
    local camera = type(prefs.cameras) == "table" and prefs.cameras[CameraKey(location)] or nil
    if type(camera) ~= "table" or not Model.IsFinite(camera.zoom) or not Model.IsFinite(camera.centerX)
        or not Model.IsFinite(camera.centerY) then
        return { zoom = C.minZoom, centerX = 0.5, centerY = 0.5 }, false
    end
    return {
        zoom = Model.Clamp(camera.zoom, C.minZoom, C.maxZoom),
        centerX = Model.Clamp(camera.centerX, 0, 1),
        centerY = Model.Clamp(camera.centerY, 0, 1),
    }, true
end

--- Keeps one camera per map the viewer can open, so the setting stays small.
--- @param location RegionMapLocationRecord
--- @param camera RegionMapCamera
function RegionMapSession.SaveCamera(location, camera)
    local prefs = ReadPreferences()
    local cameras = {}
    if type(prefs.cameras) == "table" then
        for key, value in pairs(prefs.cameras) do
            local id = type(key) == "string" and key:match("^(.*):%d+$") or nil
            local other = id ~= nil and id ~= location.id and Model.GetLocation(id) or nil
            if other ~= nil and Model.CanOpenMap(other) and key == CameraKey(other) then cameras[key] = value end
        end
    end
    cameras[CameraKey(location)] = { zoom = camera.zoom, centerX = camera.centerX, centerY = camera.centerY }
    prefs.cameras = cameras
    WritePreferences(prefs)
end

--- The map this viewer had open last (D13c).
--- @return nil|string
function RegionMapSession.LastMapId()
    local id = ReadPreferences().selectedMapId
    return type(id) == "string" and id or nil
end

--- @param id nil|string nil when the viewer left for the Atlas
function RegionMapSession.SaveLastMap(id)
    local prefs = ReadPreferences()
    if prefs.selectedMapId == id then return end
    prefs.selectedMapId = id
    WritePreferences(prefs)
end

--- "Show names" forces every pin name visible (R9).
--- @return boolean
function RegionMapSession.ShowNames()
    return ReadPreferences().showNames == true
end

--- @param value boolean
function RegionMapSession.SetShowNames(value)
    local prefs = ReadPreferences()
    prefs.showNames = value == true
    WritePreferences(prefs)
end

--- "Reduce motion" turns off the map transitions and the control fade (R9).
--- @return boolean
function RegionMapSession.ReduceMotion()
    return ReadPreferences().reduceMotion == true
end

--- @param value boolean
function RegionMapSession.SetReduceMotion(value)
    local prefs = ReadPreferences()
    prefs.reduceMotion = value == true
    WritePreferences(prefs)
end

--- "Show route" draws the Party's past route from the session log (D14d).
--- @return boolean
function RegionMapSession.ShowRoute()
    return ReadPreferences().showRoute ~= false
end

--- @param value boolean
function RegionMapSession.SetShowRoute(value)
    local prefs = ReadPreferences()
    prefs.showRoute = value == true
    WritePreferences(prefs)
end

--- The icon, importance, style and visibility the next new pin copies (R10).
--- @return RegionMapPinStyle
function RegionMapSession.LastPinStyle()
    local style = ReadPreferences().lastPinStyle
    if type(style) ~= "table" then return {} end
    return DeepCopy(style)
end

--- Remember a Location's look as the style for the next new pin.
--- @param location RegionMapLocationRecord
function RegionMapSession.RememberPinStyle(location)
    local prefs = ReadPreferences()
    local style = {
        icon = location.icon, importance = location.importance, pinStyle = location.pinStyle,
        visibility = location.visibility,
    }
    local old = prefs.lastPinStyle
    if type(old) == "table" and old.icon == style.icon and old.importance == style.importance
        and old.pinStyle == style.pinStyle and old.visibility == style.visibility then return end
    prefs.lastPinStyle = style
    WritePreferences(prefs)
end

-- Font Size ------------------------------------------------------------------------------------

--- How much bigger pins, the Party and the side panel draw than at Font Size
--- 100. In rail mode the host already zooms the whole window by Font Size
--- (WindowUIScale), so only the other hosts scale here.
--- @return number
function RegionMapSession.UIScale()
    local document = rawget(_G, "PanelDocument")
    if document ~= nil and type(document.WindowUIScale) == "function" then
        local ok, scale = pcall(document.WindowUIScale)
        if ok and type(scale) == "number" and math.abs(scale - 1) > 0.001 then return 1 end
    end
    local ok, fontSize = pcall(dmhub.GetSettingValue, "fontsize")
    if ok and Model.IsFinite(fontSize) and fontSize > 0 then
        return Model.Clamp(fontSize / 100, 0.5, 3)
    end
    return 1
end

-- Small shared controls -------------------------------------------------------------------------

--- An icon button with a tooltip that can change (toolbar, camera controls).
--- @param id string
--- @param icon string
--- @param tooltip string
--- @param action fun(element: Panel)
--- @param classes nil|string[]
--- @return Panel
function RegionMapSession.IconButton(id, icon, tooltip, action, classes)
    local allClasses = { "regionMapIconButton" }
    for _, class in ipairs(classes or {}) do allClasses[#allClasses + 1] = class end
    return gui.Panel {
        id = id,
        classes = allClasses,
        bgimage = "panels/square.png",
        data = { tooltip = tooltip, hovered = false },
        hover = function(element)
            element.data.hovered = true
            gui.Tooltip(element.data.tooltip)(element)
        end,
        dehover = function(element) element.data.hovered = false end,
        click = function(element)
            if not mod.unloaded and not element:HasClass("disabled") then action(element) end
        end,
        gui.Panel { classes = { "regionMapIconGlyph" }, bgimage = icon, interactable = false },
    }
end

--- @param button Panel an IconButton
--- @param tooltip string
--- @param icon nil|string swap the glyph too
function RegionMapSession.SetIconButton(button, tooltip, icon)
    -- A toggle's tooltip names its new state at once, not after the pointer leaves and returns.
    if button.data.tooltip ~= tooltip and button.data.hovered then gui.Tooltip(tooltip)(button) end
    button.data.tooltip = tooltip
    if icon ~= nil and button.children[1] ~= nil and button.children[1].bgimage ~= icon then
        button.children[1].bgimage = icon
    end
end

--- Set a label's text only when it changed (avoids relayout).
--- @param element Panel
--- @param value nil|string
function RegionMapSession.SetText(element, value)
    value = value or ""
    if element.text ~= value then element.text = value end
end
