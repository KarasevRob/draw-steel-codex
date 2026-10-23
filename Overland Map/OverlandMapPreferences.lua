local mod = dmhub.GetModLoading()

--- @class OverlandMapPreferences: GameType
--- @field new fun(o?: table): OverlandMapPreferences
OverlandMapPreferences = RegisterGameType("OverlandMapPreferences")
local C = OverlandMapConstants
local Model = OverlandMapModel

local noPreferences = {}

-- The stored preferences, for reading only: the canvas asks for Reduce motion on
-- every think, and a copy of every saved camera each time was pure garbage.
local function Preferences()
    local prefs = dmhub.GetSettingValue(C.preferencesSettingId)
    return type(prefs) == "table" and prefs or noPreferences
end

-- A copy to change and write back, so the setting's own table is never edited in place.
local function ReadPreferences()
    local prefs = Preferences()
    return prefs ~= noPreferences and DeepCopy(prefs) or {}
end

local function WritePreferences(prefs)
    dmhub.SetSettingValue(C.preferencesSettingId, prefs)
end

--- @return "fullscreen"|"window"
function OverlandMapPreferences.InAppView()
    return Preferences().inAppView == "window" and "window" or "fullscreen"
end

--- @param mode "fullscreen"|"window"
function OverlandMapPreferences.SetInAppView(mode)
    if mode ~= "fullscreen" and mode ~= "window" then return end
    local prefs = ReadPreferences()
    if prefs.inAppView == mode then return end
    prefs.inAppView = mode
    WritePreferences(prefs)
end

--- Geometry is in unscaled UI units; the host converts it through WindowUIScale.
--- @class OverlandMapWindowGeometry
--- @field x number
--- @field y number
--- @field width number
--- @field height number

local function ValidWindowGeometry(value)
    return type(value) == "table" and Model.IsFinite(value.x) and Model.IsFinite(value.y)
        and Model.IsFinite(value.width) and Model.IsFinite(value.height)
        and value.width > 0 and value.height > 0
end

--- @return nil|OverlandMapWindowGeometry
function OverlandMapPreferences.ReadWindowGeometry()
    local value = Preferences().windowGeometry
    if not ValidWindowGeometry(value) then return nil end
    return { x = value.x, y = value.y, width = value.width, height = value.height }
end

--- @param value OverlandMapWindowGeometry
function OverlandMapPreferences.SaveWindowGeometry(value)
    if not ValidWindowGeometry(value) then return end
    local prefs = ReadPreferences()
    local old = prefs.windowGeometry
    if ValidWindowGeometry(old) and old.x == value.x and old.y == value.y
        and old.width == value.width and old.height == value.height then return end
    prefs.windowGeometry = { x = value.x, y = value.y, width = value.width, height = value.height }
    WritePreferences(prefs)
end

-- Cameras are keyed by map and image revision, so a replaced image starts fitted.
local function CameraKey(location)
    return string.format("%s:%.0f", location.id, location.imageRevision)
end

--- The camera this viewer last used on a map.
--- @param location OverlandMapLocationRecord
--- @return OverlandMapCamera camera
--- @return boolean restored false when nothing was saved for the current image
function OverlandMapPreferences.ReadCamera(location)
    local prefs = Preferences()
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
--- @param location OverlandMapLocationRecord
--- @param camera OverlandMapCamera
function OverlandMapPreferences.SaveCamera(location, camera)
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
function OverlandMapPreferences.LastMapId()
    local id = Preferences().selectedMapId
    return type(id) == "string" and id or nil
end

--- Nil preserves the legacy first-map fallback until the viewer chooses explicitly.
--- @return nil|"atlas"|"map"
function OverlandMapPreferences.SelectionKind()
    local kind = Preferences().selectionKind
    if kind == "atlas" or kind == "map" then return kind end
end

--- @return nil|"closed"|"open"|"minimized"|"native"
function OverlandMapPreferences.HostState()
    local state = Preferences().hostState
    if state == "closed" or state == "open" or state == "minimized" or state == "native" then return state end
end

--- @param state "closed"|"open"|"minimized"|"native"
function OverlandMapPreferences.SaveHostState(state)
    local prefs = ReadPreferences()
    if prefs.hostState == state then return end
    prefs.hostState = state
    WritePreferences(prefs)
end

--- @return nil|{x: number, y: number}
function OverlandMapPreferences.MinimizedPosition()
    local value = Preferences().minimizedPosition
    if type(value) == "table" and Model.IsFinite(value.x) and Model.IsFinite(value.y) then
        return { x = value.x, y = value.y }
    end
end

function OverlandMapPreferences.SaveMinimizedPosition(x, y)
    if not Model.IsFinite(x) or not Model.IsFinite(y) then return end
    local prefs = ReadPreferences()
    local old = prefs.minimizedPosition
    if type(old) == "table" and old.x == x and old.y == y then return end
    prefs.minimizedPosition = { x = x, y = y }
    WritePreferences(prefs)
end

--- @param id nil|string nil when the viewer left for the Atlas
function OverlandMapPreferences.SaveLastMap(id)
    local prefs = ReadPreferences()
    local kind = id == nil and "atlas" or "map"
    if prefs.selectedMapId == id and prefs.selectionKind == kind then return end
    prefs.selectedMapId, prefs.selectionKind = id, kind
    WritePreferences(prefs)
end

--- An on/off preference: the getter answers default until the viewer sets it.
--- @param key string
--- @param default boolean
--- @return fun(): boolean get
--- @return fun(value: boolean) set
local function OnOffPreference(key, default)
    local function Get()
        local value = Preferences()[key]
        if type(value) ~= "boolean" then return default end
        return value
    end
    local function Set(value)
        local prefs = ReadPreferences()
        prefs[key] = value == true
        WritePreferences(prefs)
    end
    return Get, Set
end

-- "Show names" forces every pin name visible (R9).
OverlandMapPreferences.ShowNames, OverlandMapPreferences.SetShowNames = OnOffPreference("showNames", false)
OverlandMapPreferences.ShowLabels, OverlandMapPreferences.SetShowLabels = OnOffPreference("showLabels", true)
OverlandMapPreferences.ShowCompass, OverlandMapPreferences.SetShowCompass = OnOffPreference("showCompass", true)
OverlandMapPreferences.ShowScaleBar, OverlandMapPreferences.SetShowScaleBar = OnOffPreference("showScaleBar", true)
OverlandMapPreferences.ShowHoverText, OverlandMapPreferences.SetShowHoverText = OnOffPreference("showHoverText", true)

-- "Reduce motion" turns off the map transitions and the control fade (R9).
OverlandMapPreferences.ReduceMotion, OverlandMapPreferences.SetReduceMotion = OnOffPreference("reduceMotion", false)
OverlandMapPreferences.ShowVisibility, OverlandMapPreferences.SetShowVisibility = OnOffPreference("showVisibility", false)
-- "Show route" draws the Party's past route from the session log (D14d).
OverlandMapPreferences.ShowRoute, OverlandMapPreferences.SetShowRoute = OnOffPreference("showRoute", false)

--- The icon, importance, style and visibility the next new pin copies (R10).
--- @return OverlandMapPinStyle
function OverlandMapPreferences.LastPinStyle()
    local style = Preferences().lastPinStyle
    if type(style) ~= "table" then return {} end
    return DeepCopy(style)
end

function OverlandMapPreferences.LastLabelFormat()
    local value = OverlandMapLabels.Format(Preferences().lastLabelFormat)
    if not OverlandMapModel.IsDirector() then value = OverlandMapTextAppearance.PlayerFormat(value) end
    return value
end

function OverlandMapPreferences.RememberLabelFormat(row)
    local value = OverlandMapLabels.Format(row)
    local prefs = ReadPreferences()
    if dmhub.DeepEqual(prefs.lastLabelFormat, value) then return end
    prefs.lastLabelFormat = value
    WritePreferences(prefs)
end

--- Remember a Location's look as the style for the next new pin.
--- @param location OverlandMapLocationRecord
function OverlandMapPreferences.RememberPinStyle(location)
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

--- The type and time the next new path copies (Q8). The first path of a game
--- gets Road and 1 day, or the first type when Road was deleted.
--- @return {typeId: string, time: number}
function OverlandMapPreferences.LastPathStyle()
    local style = Preferences().lastPathStyle
    local typeId = type(style) == "table" and style.typeId or nil
    local time = type(style) == "table" and style.time or nil
    if OverlandMapPaths.TypeById(typeId) == nil then
        local first = OverlandMapPaths.TypeById(C.firstPathType) or OverlandMapPaths.Types()[1]
        typeId = first ~= nil and first.id or ""
    end
    if not OverlandMapRecords.ValidTime(time) then time = C.firstPathTime end
    return { typeId = typeId, time = time }
end

--- Remember a path's type and time for the next new path.
--- @param path OverlandMapPathRecord
function OverlandMapPreferences.RememberPathStyle(path)
    local prefs = ReadPreferences()
    local old = prefs.lastPathStyle
    if type(old) == "table" and old.typeId == path.typeId and old.time == path.time then return end
    prefs.lastPathStyle = { typeId = path.typeId, time = path.time }
    WritePreferences(prefs)
end
