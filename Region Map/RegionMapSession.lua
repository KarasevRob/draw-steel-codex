local mod = dmhub.GetModLoading()

--- What the Region Map components share: the context contract, the viewer's
--- own preferences (last map, cameras, Show names, last pin style), the
--- Font Size scale for pins and panels, and the small controls every panel
--- builds (labels, buttons, segments, text areas, icon buttons).
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
--- @field selectedPathId nil|string the path in the path panel (panelMode "path")
--- @field selectedLabelId nil|string selected map lettering, including a local creation draft
--- @field panelMode "none"|"read"|"edit"|"pickMode"|"pickImage"|"pickMap"|"pickJournal"|"log"|"path"|"pathEdit"|"pickPathEnd"|"party"|"labelEdit"
--- @field pickKind nil|"add"|"replace" what pickImage does with the image
--- @field newMapMode nil|"free"|"pointcrawl" the kind picked for Add map (A1), until its image is chosen
--- @field locked boolean pins cannot be dragged (R6); per viewer, true on every map open
--- @field tool "none"|"add"|"move"|"ruler"|"scale"|"path"|"redraw"|"labelAdd"|"labelMove"
--- @field toolTargetId nil|string the Location "move" places, or the path "redraw" redraws
--- @field pathDraft nil|RegionMapPathDraft the line the Path tool or Redraw line is drawing
--- @field camera RegionMapCamera
--- @field panelInset number pixels of the map's right edge an open panel covers; the camera may pan that much further
--- @field focusName boolean the side panel puts the caret in the name field once
--- @field popover nil|"search"|"settings" the popover open under the toolbar
--- @field ruler nil|RegionMapMeasure the ruler's points (local, never written)
--- @field scaleDraft nil|RegionMapMeasure the two scale points picked so far, until a distance is entered

--- Two points on the open map. The second is absent while only a start is picked.
--- @class RegionMapMeasure
--- @field mapId string
--- @field u1 number
--- @field v1 number
--- @field u2 nil|number
--- @field v2 nil|number
--- @field unit nil|"mi"|"km" scale drafts only: the unit picked before the distance

--- A path being drawn (V21-11). The Path tool fills startId with the first pin
--- clicked; Redraw line (V21-14) starts with both ends fixed.
--- @class RegionMapPathDraft
--- @field mapId string
--- @field startId nil|string the a end, once picked
--- @field endId nil|string Redraw line: the only pin that finishes
--- @field pathId nil|string Redraw line: the path whose bends are replaced
--- @field bends RegionMapBend[]

--- What ctx.Confirm shows. alternate adds a third button between the confirm
--- and Cancel (the hidden-path travel question, W1).
--- @class RegionMapConfirmArgs
--- @field title string
--- @field message nil|string
--- @field confirm string
--- @field onConfirm fun()
--- @field alternate nil|string
--- @field onAlternate nil|fun()

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
--- @field SelectPath fun(id: nil|string, mode: nil|"path"|"pathEdit") show a path in the path panel; nil closes it
--- @field SelectLabel fun(id: nil|string, edit?: boolean)
--- @field CreateLabel fun(u: number, v: number)
--- @field FocusLabel fun(id: string, edit?: boolean)
--- @field SetTool fun(tool: string, targetId: nil|string)
--- @field RefreshAll fun()
--- @field FlushEdits fun()
--- @field ShowMenu fun(element: Panel, id: string)
--- @field Report fun(ok: boolean, reason: nil|string): boolean shows a toast for a failed write
--- @field Push fun(entry: nil|RegionMapUndoEntry, copyId: string, args: nil|table)
--- @field CheckImageSize fun(mapId: string, imageId: string) warns with a toast when a newly picked map image is outside the size range (J3)
--- @field ImageHint fun(): string the size guidance line shown by image pickers (J2)
--- @field ImportLocations fun() Director: open the JSON import card for the current map
--- @field ShowToPlayers fun()
--- @field Confirm fun(args: RegionMapConfirmArgs) compact in-window confirm dialog
--- @field ShowParty fun() open the Party section (point crawl maps, G1)
--- @field StopOnPath fun(pathId: string) Director: open the stop card for a path (G3)
--- @field FocusLocation fun(id: string) open the map a Location is on, center it and select it (Search)
--- @field SetPopover fun(popover: nil|"search"|"settings") open or close a toolbar popover
--- @field ToggleLog fun() open or close the session log panel

local contextMenuOwner = nil --- @type Panel|nil
local contextMenu = nil --- @type Panel|nil

--- Canvas presses keep native popups open, so dismiss the mod's menu explicitly.
function RegionMapSession.CloseContextMenu()
    local owner, menu = contextMenuOwner, contextMenu
    contextMenuOwner, contextMenu = nil, nil
    if owner ~= nil and owner.valid and owner.popup == menu then owner.popup = nil end
end

--- @param owner Panel
--- @param args table
--- @return Panel|nil
function RegionMapSession.ContextMenu(owner, args)
    RegionMapSession.CloseContextMenu()
    local menu = gui.ContextMenu(args)
    if menu ~= nil then contextMenuOwner, contextMenu = owner, menu end
    return menu
end

-- Preferences (per viewer and game) ------------------------------------------------------------

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
function RegionMapSession.InAppView()
    return Preferences().inAppView == "window" and "window" or "fullscreen"
end

--- @param mode "fullscreen"|"window"
function RegionMapSession.SetInAppView(mode)
    if mode ~= "fullscreen" and mode ~= "window" then return end
    local prefs = ReadPreferences()
    if prefs.inAppView == mode then return end
    prefs.inAppView = mode
    WritePreferences(prefs)
end

--- Geometry is in unscaled UI units; the host converts it through WindowUIScale.
--- @class RegionMapWindowGeometry
--- @field x number
--- @field y number
--- @field width number
--- @field height number

local function ValidWindowGeometry(value)
    return type(value) == "table" and Model.IsFinite(value.x) and Model.IsFinite(value.y)
        and Model.IsFinite(value.width) and Model.IsFinite(value.height)
        and value.width > 0 and value.height > 0
end

--- @return nil|RegionMapWindowGeometry
function RegionMapSession.ReadWindowGeometry()
    local value = Preferences().windowGeometry
    if not ValidWindowGeometry(value) then return nil end
    return { x = value.x, y = value.y, width = value.width, height = value.height }
end

--- @param value RegionMapWindowGeometry
function RegionMapSession.SaveWindowGeometry(value)
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
--- @param location RegionMapLocationRecord
--- @return RegionMapCamera camera
--- @return boolean restored false when nothing was saved for the current image
function RegionMapSession.ReadCamera(location)
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
    local id = Preferences().selectedMapId
    return type(id) == "string" and id or nil
end

--- @param id nil|string nil when the viewer left for the Atlas
function RegionMapSession.SaveLastMap(id)
    local prefs = ReadPreferences()
    if prefs.selectedMapId == id then return end
    prefs.selectedMapId = id
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
RegionMapSession.ShowNames, RegionMapSession.SetShowNames = OnOffPreference("showNames", false)
RegionMapSession.ShowLabels, RegionMapSession.SetShowLabels = OnOffPreference("showLabels", true)
-- "Reduce motion" turns off the map transitions and the control fade (R9).
RegionMapSession.ReduceMotion, RegionMapSession.SetReduceMotion = OnOffPreference("reduceMotion", false)
-- "Show route" draws the Party's past route from the session log (D14d).
RegionMapSession.ShowRoute, RegionMapSession.SetShowRoute = OnOffPreference("showRoute", false)

--- The icon, importance, style and visibility the next new pin copies (R10).
--- @return RegionMapPinStyle
function RegionMapSession.LastPinStyle()
    local style = Preferences().lastPinStyle
    if type(style) ~= "table" then return {} end
    return DeepCopy(style)
end

function RegionMapSession.LastLabelFormat()
    return RegionMapLabels.Format(Preferences().lastLabelFormat)
end

function RegionMapSession.RememberLabelFormat(row)
    local value = RegionMapLabels.Format(row)
    local prefs = ReadPreferences()
    if dmhub.DeepEqual(prefs.lastLabelFormat, value) then return end
    prefs.lastLabelFormat = value
    WritePreferences(prefs)
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

--- The type and time the next new path copies (Q8). The first path of a game
--- gets Road and 1 day, or the first type when Road was deleted.
--- @return {typeId: string, time: number}
function RegionMapSession.LastPathStyle()
    local style = Preferences().lastPathStyle
    local typeId = type(style) == "table" and style.typeId or nil
    local time = type(style) == "table" and style.time or nil
    if RegionMapPaths.TypeById(typeId) == nil then
        local first = RegionMapPaths.TypeById(C.firstPathType) or RegionMapPaths.Types()[1]
        typeId = first ~= nil and first.id or ""
    end
    if not RegionMapRecords.ValidTime(time) then time = C.firstPathTime end
    return { typeId = typeId, time = time }
end

--- Remember a path's type and time for the next new path.
--- @param path RegionMapPathRecord
function RegionMapSession.RememberPathStyle(path)
    local prefs = ReadPreferences()
    local old = prefs.lastPathStyle
    if type(old) == "table" and old.typeId == path.typeId and old.time == path.time then return end
    prefs.lastPathStyle = { typeId = path.typeId, time = path.time }
    WritePreferences(prefs)
end

-- Font Size ------------------------------------------------------------------------------------

--- How much bigger pins, the Party and the side panel draw than at Font Size
--- 100. In rail mode the host already zooms the whole map by Font Size
--- (WindowUIScale: the fullscreen host and the popout both apply it), so
--- this scales only outside rail mode.
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
    local keyboard = false
    for _, class in ipairs(classes or {}) do
        allClasses[#allClasses + 1] = class
        if class == "regionMapHostControl" then keyboard = true end
    end
    local args = {
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
    }
    if not keyboard then
        args[1] = gui.Panel { classes = { "regionMapIconGlyph" }, bgimage = icon, interactable = false }
        return gui.Panel(args)
    end
    -- The engine already handles Tab and clicks focused panels on Enter/Space release.
    args.canFocus = true
    args.swallowPress = true
    args.icon = icon
    local button = gui.Button(args)
    button.children[1].interactable = false
    return button
end

--- Tab between the visible host controls; called only from the canvas or a host button.
--- @param root Panel
--- @param from nil|Panel
--- @param direction number
function RegionMapSession.FocusHostControl(root, from, direction)
    local controls = {}
    local index = direction > 0 and 0 or 1
    for _, button in ipairs(root:GetChildrenWithClassRecursive("regionMapHostControl")) do
        if button.enabled and not button:HasClass("disabled") then
            controls[#controls + 1] = button
            if button == from then index = #controls end
        end
    end
    local canvas = root:Get("region-map-canvas")
    if canvas ~= nil and canvas.enabled then
        controls[#controls + 1] = canvas
        if canvas == from then index = #controls end
    end
    if #controls > 0 then gui.SetFocus(controls[(index - 1 + direction) % #controls + 1]) end
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

--- The map kind choice (A1, Q21): Free and Point crawl buttons, each with its
--- description, then the note that the kind is permanent. Shared by the Atlas
--- New map card and the side panel's Add map, so both read the same.
--- @param onPick fun(mode: "free"|"pointcrawl")
--- @return Panel
function RegionMapSession.ModeChoice(onPick)
    local T = RegionMapCopy.T
    local function ModeButton(mode)
        return gui.Panel {
            classes = { "regionMapModeButton" },
            click = function() if not mod.unloaded then onPick(mode) end end,
            gui.Label { classes = { "regionMapModeName" }, text = T("mode." .. mode), interactable = false },
            gui.Label { classes = { "regionMapModeDesc" }, text = T("mode." .. mode .. ".desc"), interactable = false },
        }
    end
    local children = {}
    for _, mode in ipairs(C.modes) do children[#children + 1] = ModeButton(mode) end
    children[#children + 1] = gui.Label { classes = { "regionMapModeNote" }, text = T("mode.permanent"), interactable = false }
    return gui.Panel { classes = { "regionMapModeChoice" }, children = children }
end

--- Set a label's text only when it changed (avoids relayout).
--- @param element Panel
--- @param value nil|string
function RegionMapSession.SetText(element, value)
    value = value or ""
    if element.text ~= value then element.text = value end
end

--- Add or remove a class only when it flips. A class change costs engine work
--- even when it changes nothing, and canvas layers run this every frame of a pan.
--- @param element Panel
--- @param class string
--- @param on boolean
function RegionMapSession.SetClassIf(element, class, on)
    if element:HasClass(class) ~= on then element:SetClass(class, on) end
end

--- A non-interactive label; text nil shows nothing until it is set.
--- @param classes string[]
--- @param text nil|string
--- @return Panel
function RegionMapSession.Label(classes, text)
    return gui.Label { classes = classes, text = text or "", interactable = false }
end

--- A small text button. A click is ignored after an unload or while the
--- button has the "disabled" class.
--- @param text string
--- @param action fun()
--- @return Panel
function RegionMapSession.Button(text, action)
    return gui.Button {
        classes = { "regionMapButton", "sizeS" }, text = text,
        click = function(element)
            if not mod.unloaded and not element:HasClass("disabled") then action() end
        end,
    }
end

--- A row of segment buttons, one per value, labeled by the copy id
--- copyPrefix .. value. onPick gets the clicked value; row.data.select(value)
--- marks the current one.
--- @param values string[]
--- @param copyPrefix string
--- @param onPick fun(value: string)
--- @return Panel
function RegionMapSession.Segments(values, copyPrefix, onPick)
    local T = RegionMapCopy.T
    local buttons = {}
    local row = gui.Panel { classes = { "regionMapSegments" }, data = {} }
    for _, value in ipairs(values) do
        buttons[#buttons + 1] = gui.Label {
            classes = { "regionMapSegment" }, text = T(copyPrefix .. value),
            width = string.format("%.4f%%", 100 / #values),
            data = { value = value },
            click = function(element) onPick(element.data.value) end,
        }
    end
    row.children = buttons
    row.data.select = function(current)
        for _, button in ipairs(buttons) do button:SetClass("selected", button.data.value == current) end
    end
    return row
end

--- A multi-line text field (descriptions and notes). args goes into the
--- editor as well, so the caller adds its text, placeholder and handlers.
--- @param limit integer characters
--- @param args table
--- @return TextEditor
function RegionMapSession.TextArea(limit, args)
    local editor = {
        classes = { "input", "bordered", "sizeS", "regionMapTextArea" }, borderBox = true,
        characterLimit = limit, multiline = true, verticalScrollbar = true, editlag = 0,
        selectAllOnFocus = false, resetOnDeActivation = false, textAlignment = "topleft",
    }
    for key, value in pairs(args) do editor[key] = value end
    return gui.TextEditor(editor)
end

--- Put keyboard focus in an input once the panel that shows it has laid out.
--- stillWanted, when given, is asked again then, so a panel closed meanwhile
--- does not take focus.
--- @param element Panel
--- @param stillWanted nil|fun(): boolean
function RegionMapSession.FocusSoon(element, stillWanted)
    dmhub.Schedule(C.afterLayoutDelay, function()
        if mod.unloaded or not element.valid then return end
        if stillWanted ~= nil and not stillWanted() then return end
        gui.SetFocus(element)
    end)
end
