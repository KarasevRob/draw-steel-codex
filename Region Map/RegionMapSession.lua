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
--- @field locked boolean pins and labels cannot be dragged (R6); per viewer, true on every map open
--- @field tool "none"|"add"|"move"|"ruler"|"scale"|"path"|"redraw"|"labelAdd"
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

--- A path being drawn. The Path tool fills startId with the first pin
--- clicked; Redraw line starts with both ends fixed.
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
--- @field HandleEnter nil|fun(canvas: Panel) Enter on the canvas while the shell listens for it

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
    local value = RegionMapLabels.Format(Preferences().lastLabelFormat)
    if not RegionMapModel.IsDirector() then value = RegionMapTextAppearance.PlayerFormat(value) end
    return value
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
            gui.Label { classes = { "regionMapModeName", "sizeS" }, text = T("mode." .. mode), interactable = false },
            gui.Label { classes = { "regionMapModeDesc", "sizeXs" }, text = T("mode." .. mode .. ".desc"), interactable = false },
        }
    end
    local children = {}
    for _, mode in ipairs(C.modes) do children[#children + 1] = ModeButton(mode) end
    children[#children + 1] = gui.Label { classes = { "regionMapModeNote", "sizeXs" }, text = T("mode.permanent"), interactable = false }
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
            classes = { "regionMapSegment", "sizeS" }, text = T(copyPrefix .. value),
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

-- Text appearance controls ----------------------------------------------------------------------
-- The uploaded image behind a label or pin name, and the outline/background editor that
-- labels and Settings > Pin text share. The format rules they follow are in RegionMapTextAppearance.

local appearanceImages, appearanceViews = {}, {}

--- The last load state any view reported for an image id ("loading" until one does).
--- @param id string
--- @return string
function RegionMapSession.AppearanceImageStatus(id)
    return appearanceImages[id] or "loading"
end

--- Ask every view showing this image to load it again (the editor's Retry).
--- @param id string
function RegionMapSession.RetryAppearanceImage(id)
    for view in pairs(appearanceViews) do
        if view.id == id and view.panel ~= nil and view.panel.valid then view.Load() end
    end
end

--- The background image of one label or pin name. Its panel is built only once a format
--- asks for an image, so text without one costs nothing extra; Mount(host) says where it
--- goes, always behind the host's other children. changed() runs on every status change.
--- Each request owns its lifetime; repeated pins share the engine's image cache.
--- @param changed nil|fun()
--- @return table view
function RegionMapSession.AppearanceImage(changed)
    local A, R = RegionMapTextAppearance, RegionMapRecords
    local view = { generation = 0, status = "empty", id = "", format = nil, rect = nil, host = nil, panel = nil }
    local function Notify(status)
        view.status = status
        if view.id ~= "" then appearanceImages[view.id] = status end
        if changed then changed() end
    end
    local function Arrange()
        local panel, rect, format = view.panel, view.rect, view.format
        if panel == nil or not panel.valid or rect == nil or format == nil then return end
        local shown = view.status == "ready" and format.backgroundOpacity > 0
        RegionMapSession.SetClassIf(panel, "hidden", not shown)
        if not shown then return end
        local width, height, crop = A.Fit(format.backgroundFit, rect.x2 - rect.x1, rect.y2 - rect.y1, view.width, view.height)
        local key = table.concat({ width, height, rect.x1, rect.x2, rect.y1, rect.y2, format.backgroundFit, format.backgroundOpacity }, "|")
        if view.layoutKey == key then return end
        view.layoutKey = key
        panel.selfStyle.width, panel.selfStyle.height = width, height
        panel.selfStyle.x, panel.selfStyle.y = (rect.x1 + rect.x2) / 2, (rect.y1 + rect.y2) / 2
        if view.leaf then view.leaf.selfStyle.imageRect = crop end
        panel.selfStyle.opacity = format.backgroundOpacity
    end
    local function EnsurePanel()
        if view.panel ~= nil and view.panel.valid then return view.panel end
        if view.host == nil or not view.host.valid then return nil end
        view.panel = gui.Panel {
            floating = true, halign = "center", valign = "center", width = 1, height = 1,
            classes = { "hidden" }, interactable = false, monitorAssets = "images",
            refreshAssets = function()
                if view.id == "" then return end
                local asset = A.ReadableAsset(view.id)
                if (asset and asset.imageid or nil) ~= view.assetKey then view.Load() end
            end,
            destroy = function() view.generation = view.generation + 1; appearanceViews[view] = nil end,
        }
        appearanceViews[view] = true
        view.host:AddChild(view.panel)
        view.panel:SetAsFirstSibling()
        return view.panel
    end
    function view.Load()
        if mod.unloaded then return end
        view.generation = view.generation + 1
        local generation, id = view.generation, view.id
        view.layoutKey, view.width, view.height = nil, nil, nil
        if view.leaf then view.leaf:DestroySelf(); view.leaf = nil end
        if id == "" then
            if view.panel ~= nil and view.panel.valid then RegionMapSession.SetClassIf(view.panel, "hidden", true) end
            view.assetKey = nil
            Notify("empty")
            return
        end
        local panel = EnsurePanel()
        if panel == nil then return end
        RegionMapSession.SetClassIf(panel, "hidden", true)
        local asset = A.ReadableAsset(id)
        view.assetKey = asset and asset.imageid or nil
        if asset == nil then Notify("unavailable"); return end
        Notify("loading")
        local leaf = gui.Panel {
            classes = { "regionMapTextImage" }, width = "100%", height = "100%", interactable = false,
            imageLoaded = function(e)
                if mod.unloaded or not e.valid or generation ~= view.generation or view.id ~= id then return end
                local current = A.ReadableAsset(id)
                if current == nil or current.imageid ~= view.assetKey then return end
                local w, h = tonumber(e.bgimageWidth), tonumber(e.bgimageHeight)
                if not R.IsFinite(w) or not R.IsFinite(h) or w <= 0 or h <= 0 then return end
                view.width, view.height = w, h
                Notify("ready"); Arrange()
            end,
        }
        view.leaf = leaf
        panel:AddChild(leaf)
        leaf.bgimageStreamed = id
        dmhub.Schedule(C.artworkTimeout, function()
            if not mod.unloaded and view.panel ~= nil and view.panel.valid and generation == view.generation
                and view.status == "loading" then Notify("unavailable") end
        end)
    end
    --- @param host Panel
    function view.Mount(host)
        view.host = host
    end
    --- @param format table
    function view.Bind(format)
        view.format = format
        local id = format.background == "image" and format.backgroundImageId or ""
        if id ~= view.id then view.id = id; view.Load() end
        Arrange()
    end
    --- @param rect table
    function view.Layout(rect)
        view.rect = rect
        Arrange()
    end
    return view
end

--- Outline and background controls. They save through options, so a label editor stages
--- into its label's queue and Settings > Pin text commits to its map's queue.
--- options.Active(id): whether this editor still edits id
--- options.Format(): the current effective format
--- options.Commit(changes): save; false when refused
--- options.Preview(changes): nil, or show a value while a slider is dragged (saved on release)
--- @param ctx RegionMapContext
--- @param pins boolean true for map pin names (lengths in points), false for labels (map fractions)
--- @param options table
--- @return Panel
function RegionMapSession.AppearanceEditor(ctx, pins, options)
    local A, R, Model, T = RegionMapTextAppearance, RegionMapRecords, RegionMapModel, RegionMapCopy.T
    local Session = RegionMapSession
    local panel --- @type Panel|nil
    local boundId, format, binding, generation = nil, nil, false, 0
    local inputs, sliders, invalid = {}, {}, {}
    local pickerSlot, picker, outlinePicker
    local imageError, expanded = nil, false
    local prefix = pins and "region-map-pin-appearance-" or "region-map-label-appearance-"
    local function Active() return not mod.unloaded and boundId ~= nil and ctx.IsAlive() and options.Active(boundId) end
    local function Current() return options.Format() end
    -- The owner's queue refreshes the window on every change it accepts; a refusal needs a rebind here.
    local function Commit(changes)
        if binding or not Active() then return false end
        if not A.CanChange(Current(), changes, Model.IsDirector()) then ctx.RefreshAll(); return false end
        local ok = options.Commit(changes)
        if not ok then ctx.RefreshAll() end
        return ok
    end
    local function Field(key, child)
        return gui.Panel { classes = { "regionMapLabelField" },
            Session.Label({ "regionMapFormLabel", "sizeXs" }, T(key)), child }
    end
    local function ClosePicker()
        generation = generation + 1
        if picker then picker.popup = nil; picker = nil end
        if pickerSlot then pickerSlot.children = {}; pickerSlot:SetClass("collapsed", true) end
        if outlinePicker then outlinePicker.popup = nil end
    end
    local function Choose()
        if not Active() or not Model.IsDirector() then return end
        ClosePicker()
        local id, token, expected, expectedMode = boundId, generation, Current().backgroundImageId, Current().background
        local chosen = false
        picker = gui.IconEditor {
            width = "100%", height = 1, library = "journal", categoriesHidden = true,
            allowNone = false, allowPaste = true, hideIcon = true, liveEdit = false,
            rightClick = function() end,
            change = function(e)
                if chosen or not Active() or not Model.IsDirector() or id ~= boundId or token ~= generation
                    or picker == nil or picker.popup == nil then return end
                chosen = true
                if Current().backgroundImageId ~= expected or Current().background ~= expectedMode then ClosePicker(); ctx.RefreshAll(); return end
                local value = e.value or ""
                local asset, reason = A.ReadableAsset(value)
                if asset then imageError = nil; Commit({ background = "image", backgroundImageId = value })
                else imageError = reason == "video" and "appearance.video" or "appearance.invalidImage" end
                dmhub.Schedule(0, function()
                    if not mod.unloaded and panel and panel.valid and token == generation then ClosePicker(); ctx.RefreshAll() end
                end)
            end,
        }
        pickerSlot.children = { picker }
        pickerSlot:SetClass("collapsed", false)
        picker:SetValue(expected or "", false)
        local press = picker.events.press
        picker.events.press, picker.events.dropfiles = function() end, function() end
        if press then press(picker) end
        local anchor, popup = picker, picker.popup
        if popup then
            local destroy = popup.events.destroy
            popup.events.destroy = function(e)
                if destroy then destroy(e) end
                if chosen or generation ~= token or picker ~= anchor then return end
                generation = generation + 1
                local cancelled = generation
                dmhub.Schedule(0, function()
                    if not mod.unloaded and panel and panel.valid and generation == cancelled and picker == anchor then
                        ClosePicker(); ctx.RefreshAll()
                    end
                end)
            end
        end
    end
    local function Dropdown(key, values, changed)
        local entries = {}
        for _, value in ipairs(values) do entries[#entries + 1] = { id = value, text = T("appearance." .. value) } end
        local input = gui.Dropdown { id = prefix .. key, classes = { "regionMapLabelInput" },
            width = "100%", minWidth = 0, options = entries,
            change = function(e)
                if binding or not Active() then return end
                if changed then changed(e.idChosen) else Commit({ [key] = e.idChosen }) end
            end }
        inputs[key] = { panel = input, kind = "dropdown" }
        return input
    end
    local function Numeric(key, multiplier, low, high, slider)
        local input = gui.Input { id = prefix .. key, classes = { "input", "bordered", "regionMapLabelInput" },
            width = slider and 72 or "100%", minWidth = 0, characterLimit = 16, borderBox = true,
            change = function(e)
                if binding or not Active() then return end
                local value = tonumber(e.text)
                local valid = R.IsFinite(value) and value >= low and value <= high and A.Valid(key, value / multiplier, pins)
                invalid[key] = not valid or nil
                e:SetClass("invalid", not valid)
                if valid then Commit({ [key] = value / multiplier }) else ctx.RefreshAll() end
            end }
        inputs[key] = { panel = input, kind = "number", multiplier = multiplier }
        if not slider then return input end
        -- A drag fires change on every step: show the value then, save once on release (confirm).
        local committed = nil
        local track
        local function Dragging()
            local handle = track:Get("slider-handle")
            return handle ~= nil and handle.dragging == true
        end
        local function Save(value)
            if binding or not Active() or value == committed then return end
            committed = value
            invalid[key] = nil
            Commit({ [key] = value / multiplier })
        end
        track = gui.Slider { id = prefix .. key .. "-slider", width = "100%-80", height = 28,
            rmargin = 8, minValue = low, maxValue = high, round = true,
            change = function(e)
                if binding or not Active() then return end
                if Dragging() then
                    Session.SetText(input, string.format("%.5g", e.value))
                    if options.Preview then options.Preview({ [key] = e.value / multiplier }) end
                else Save(e.value) end
            end,
            confirm = function(e) Save(e.value) end }
        track:Get("slider-notch"):SetClass("regionMapAppearanceTrack", true)
        sliders[key] = { panel = track, multiplier = multiplier, reset = function() committed = nil end }
        return gui.Panel { width = "100%", height = "auto", flow = "horizontal", track, input }
    end
    local outline = Dropdown("outlineMode", { "default", "none", "custom" }, function(value)
        local changes = { outlineMode = value }
        local current = Current()
        if value == "custom" and current.outlineColor == "" then changes.outlineColor = A.Contrast(current.color) end
        Commit(changes)
    end)
    local outlineHint = Session.Label({ "regionMapHint", "sizeXs" })
    local hex = gui.Input { id = prefix .. "outlineColor", classes = { "input", "bordered", "regionMapLabelInput" },
        width = "100%-44", minWidth = 0, characterLimit = 9, borderBox = true,
        change = function(e)
            if binding or not Active() then return end
            local valid = e.text ~= "" and A.Valid("outlineColor", e.text, pins)
            invalid.outlineColor = not valid or nil
            e:SetClass("invalid", not valid)
            if valid then Commit({ outlineColor = e.text }) else ctx.RefreshAll() end
        end }
    inputs.outlineColor = { panel = hex, kind = "color" }
    outlinePicker = gui.ColorPicker { id = prefix .. "outlineColor-picker", width = 32, height = 32, lmargin = 8,
        value = "#ffffffff", hasAlpha = true, popupAlignment = "left",
        change = function(e)
            if e.data.boundId ~= boundId or e.data.generation ~= generation then return end
            local value = e.value
            Commit({ outlineColor = type(value) == "string" and value or value.tostring })
        end }
    Session.ScaleColorPopup(ctx, outlinePicker, function(e)
        if not Active() then return false end
        e.data.boundId, e.data.generation = boundId, generation
        return true
    end)
    local customOutline = gui.Panel { classes = { "regionMapLabelField" },
        Field("appearance.outlineColor", gui.Panel { classes = { "regionMapLabelColor" }, hex, outlinePicker }),
        Field("appearance.outlineWidth", Numeric("outlineWidth", 100, 0, 100, true)),
        Session.Label({ "regionMapHint", "sizeXs" }, T("appearance.thicknessHint")) }
    local background = gui.Dropdown { id = prefix .. "background", classes = { "regionMapLabelInput" },
        width = "100%", minWidth = 0, options = {},
        change = function(e)
            if binding or not Active() then return end
            if e.idChosen == "image" and Current().backgroundImageId == "" then Choose(); ctx.RefreshAll()
            else
                local value = e.idChosen
                if value == "default" then value = false end
                Commit({ background = value })
            end
        end }
    local managed = Session.Label({ "regionMapHint", "sizeXs" }, T("appearance.managed"))
    local choose = Session.Button(T("appearance.choose"), Choose)
    local remove = Session.Button(T("appearance.remove"), function()
        local changes = A.RemoveImagePatch(pins)
        ClosePicker(); imageError = nil; Commit(changes)
    end)
    pickerSlot = gui.Panel { width = "100%", height = "auto", classes = { "collapsed" } }
    local function Pair(title, first, second, multiplier, low, high)
        return Field(title, gui.Panel { width = "100%", height = "auto", flow = "horizontal",
            gui.Panel { width = "50%", height = "auto", flow = "vertical", rpad = 4, borderBox = true,
                Session.Label({ "regionMapHint", "sizeXs" }, T("appearance." .. first)), Numeric(first, multiplier, low, high) },
            gui.Panel { width = "50%", height = "auto", flow = "vertical", lpad = 4, borderBox = true,
                Session.Label({ "regionMapHint", "sizeXs" }, T("appearance." .. second)), Numeric(second, multiplier, low, high) } })
    end
    local fit = Dropdown("backgroundFit", { "fit", "fill", "stretch" })
    local sizing = Dropdown("backgroundSizing", { "auto", "manual" }, function(value)
        local changes = { backgroundSizing = value }
        local current = Current()
        if value == "manual" and not pins and not current.backgroundManualSet and current.backgroundSizing ~= "manual" then
            local canvas = ctx.root:Get("region-map-canvas")
            local layer = canvas and canvas.data.labelLayer
            if layer then
                local width, height = layer.ImageDimensions(boundId)
                if width and height then changes.backgroundWidth, changes.backgroundHeight = width, height end
            end
        end
        if value == "manual" or current.backgroundSizing == "manual" then changes.backgroundManualSet = true end
        Commit(changes)
    end)
    local padding = Pair("appearance.padding", "backgroundPadX", "backgroundPadY", 100, 0, 1000)
    local dimensions = Pair(pins and "appearance.dimensionsPin" or "appearance.dimensionsMap", "backgroundWidth", "backgroundHeight", pins and 1 or 100, 0.001, pins and 4096 or 400)
    local offsets = Pair(pins and "appearance.offsetPin" or "appearance.offsetMap", "backgroundX", "backgroundY", pins and 1 or 100, pins and -4096 or -400, pins and 4096 or 400)
    local more = gui.Panel { classes = { "regionMapLabelField", "collapsed" }, offsets,
        Field("appearance.backgroundOpacity", Numeric("backgroundOpacity", 100, 0, 100, true)) }
    local arrow = gui.ExpandoArrow { halign = "left", valign = "center", interactable = false }
    local disclosure = gui.Panel { classes = { "regionMapSectionHeader" },
        click = function() expanded = not expanded; more:SetClass("collapsed", not expanded); arrow:SetClass("expanded", expanded) end,
        arrow, Session.Label({ "regionMapSectionLabel", "sizeS" }, T("appearance.more")) }
    local imageSettings = gui.Panel { classes = { "regionMapLabelField" },
        Field("appearance.backgroundFit", fit), Session.Label({ "regionMapHint", "sizeXs" }, T("appearance.fitHint")),
        Field("appearance.backgroundSizing", sizing), padding, dimensions, disclosure, more }
    local imageStatus = Session.Label({ "regionMapHint", "sizeXs" })
    local retry = Session.Button(T("toast.retry"), function()
        if Active() then Session.RetryAppearanceImage(Current().backgroundImageId) end
    end)
    -- A hidden view of the chosen image, so Status can report loading/unavailable while nothing else shows it.
    local probeSlot = gui.Panel { width = 1, height = 1, floating = true, interactable = false, classes = { "hidden" } }
    local probe = Session.AppearanceImage(function() end)
    probe.Mount(probeSlot)
    local controls = gui.Panel { classes = { "regionMapButtonRow" }, choose, remove }
    local imageArea = gui.Panel { classes = { "regionMapLabelField" }, controls, pickerSlot, imageSettings,
        imageStatus, retry, probeSlot }
    local function Status()
        if not Active() or format == nil then return end
        local state = format.background == "image" and Session.AppearanceImageStatus(format.backgroundImageId) or nil
        local message = imageError or (state == "loading" and "appearance.loading" or state == "unavailable" and "appearance.unavailable" or nil)
        Session.SetText(imageStatus, message and T(message) or "")
        Session.SetClassIf(imageStatus, "collapsed", message == nil)
        Session.SetClassIf(retry, "collapsed", state ~= "unavailable")
    end
    local function Bind(id, value)
        if id ~= boundId then
            ClosePicker(); invalid = {}; imageError = nil
            for _, slider in pairs(sliders) do slider.reset() end
        end
        boundId, format, binding = id, value, true
        if id == nil then binding = false; return end
        local director = Model.IsDirector()
        if not director and picker ~= nil then ClosePicker() end
        for key, item in pairs(inputs) do
            local input, current = item.panel, value[key]
            if item.kind == "dropdown" then input.idChosen = current
            elseif not input.hasFocus and not invalid[key] then
                if item.kind == "number" then current = string.format("%.5g", current * item.multiplier)
                elseif current == "" then current = A.Contrast(value.color) end
                Session.SetText(input, current); input:SetClass("invalid", false)
            end
        end
        for key, slider in pairs(sliders) do
            local handle = slider.panel:Get("slider-handle")
            if handle == nil or not handle.dragging then slider.panel.value = value[key] * slider.multiplier end
        end
        outlinePicker.value = value.outlineColor ~= "" and value.outlineColor or A.Contrast(value.color)
        customOutline:SetClass("collapsed", value.outlineMode ~= "custom")
        outlineHint:SetClass("collapsed", value.outlineMode ~= "default")
        Session.SetText(outlineHint, T(pins and value.background == "default" and "appearance.outlineHalo" or "appearance.outlineOff"))
        local entries = {}
        if pins then entries[#entries + 1] = { id = "default", text = T("pinText.default") } end
        for _, key in ipairs({ "auto", "plate", "none" }) do entries[#entries + 1] = { id = key, text = T("label." .. key) } end
        if director or value.background == "image" then entries[#entries + 1] = { id = "image", text = T("appearance.image") } end
        local optionKey = tostring(director) .. ":" .. tostring(value.background == "image")
        if background.data.optionKey ~= optionKey then background.data.optionKey = optionKey; background.options = entries end
        background.idChosen = value.background
        background.interactable = director or value.background ~= "image"
        background:SetClass("disabled", not background.interactable)
        managed:SetClass("collapsed", director or value.background ~= "image")
        imageArea:SetClass("collapsed", value.background ~= "image" and value.backgroundImageId == "" and imageError == nil)
        controls:SetClass("collapsed", not director)
        imageSettings:SetClass("collapsed", not director or value.background ~= "image")
        Session.SetText(choose, T(value.backgroundImageId == "" and "appearance.choose" or "appearance.replace"))
        remove:SetClass("collapsed", value.backgroundImageId == "")
        padding:SetClass("collapsed", value.backgroundSizing ~= "auto")
        dimensions:SetClass("collapsed", value.backgroundSizing ~= "manual")
        probe.Bind(value)
        binding = false
        Status()
    end
    panel = gui.Panel { id = prefix .. "controls", classes = { "regionMapLabelField" },
        data = { bind = Bind, suspend = function() ClosePicker(); boundId = nil; probe.Bind({ background = "none" }) end,
            invalid = function() return next(invalid) ~= nil end },
        thinkTime = 0.25, think = Status, destroy = ClosePicker,
        Field("appearance.outline", outline), outlineHint, customOutline,
        Field("label.background", background), managed, imageArea }
    return panel
end

--- Color picker popups are 512x280; scale them down to fit a small window. allow(e) runs
--- before the popup opens and may refuse it (return false) or stamp the owner on e.data.
--- @param ctx RegionMapContext
--- @param picker Panel a gui.ColorPicker
--- @param allow fun(e: Panel): boolean
function RegionMapSession.ScaleColorPopup(ctx, picker, allow)
    local open = picker.events.click
    picker.events.click = function(e)
        if open == nil or not allow(e) then return end
        open(e)
        if e.popup then
            e.popup.constrainToScreen = true
            e.popup.selfStyle.scale = math.min(1, (ctx.root.renderedWidth - 16) / 512, (ctx.root.renderedHeight - 16) / 280)
        end
    end
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function RegionMapSession.Styles()
    return {
        {
            selectors = { "regionMapTextImage" },
            bgcolor = "white",
        },
        {
            selectors = { "regionMapAppearanceTrack" },
            bgcolor = "@border",
        },
        {
            selectors = { "regionMapModeChoice" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 4,
        },
        {
            selectors = { "regionMapModeButton" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            bmargin = 4,
            hpad = 6,
            vpad = 4,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 4,
        },
        {
            selectors = { "regionMapModeButton", "hover" },
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            transitionTime = 0.1,
        },
        {
            selectors = { "regionMapModeName" },
            width = "100%",
            height = "auto",
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "regionMapModeDesc" },
            width = "100%",
            height = "auto",
            color = "@fg",
            textWrap = true,
        },
        {
            selectors = { "regionMapModeNote" },
            width = "100%",
            height = "auto",
            color = "@fgMuted",
            textWrap = true,
        },
        {
            selectors = { "regionMapImageHit" },
            bgimage = true,
            bgcolor = "clear",
        },
    }
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function RegionMapSession.HostStyles()
    return {
        {
            selectors = { "regionMapWindowBorder" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "clear",
            borderColor = "@borderSolid",
            borderWidth = 2,
        },
        {
            selectors = { "regionMapWindowTitle" },
            bgimage = true,
            bgcolor = "@bg",
            width = "100%",
            height = C.panelTitleHeight,
            flow = "horizontal",
            halign = "left",
            valign = "top",
        },
        {
            selectors = { "regionMapResizeGrip" },
            width = 16,
            height = 16,
            halign = "right",
            valign = "bottom",
            color = "@fgMuted",
        },
        {
            selectors = { "regionMapHostControl", "focus" },
            borderWidth = 2,
            borderColor = "@accent",
        },
        {
            selectors = { "buttonIcon", "parent:regionMapHostControl" },
            width = 18,
            height = 18,
        },
    }
end
