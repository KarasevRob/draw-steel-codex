local mod = dmhub.GetModLoading()

--- @class OverlandMapControls: GameType
--- @field new fun(o?: table): OverlandMapControls
OverlandMapControls = RegisterGameType("OverlandMapControls")
local C = OverlandMapConstants
local Model = OverlandMapModel

local contextMenuOwner = nil --- @type Panel|nil
local contextMenu = nil --- @type Panel|nil

--- Canvas presses keep native popups open, so dismiss the mod's menu explicitly.
function OverlandMapControls.CloseContextMenu()
    local owner, menu = contextMenuOwner, contextMenu
    contextMenuOwner, contextMenu = nil, nil
    if owner ~= nil and owner.valid and owner.popup == menu then owner.popup = nil end
end

--- @param owner Panel
--- @param args table
--- @return Panel|nil
function OverlandMapControls.ContextMenu(owner, args)
    OverlandMapControls.CloseContextMenu()
    local menu = gui.ContextMenu(args)
    if menu ~= nil then contextMenuOwner, contextMenu = owner, menu end
    return menu
end

-- Hover text ------------------------------------------------------------------------------------

local hoverTextOwners = setmetatable({}, { __mode = "k" })

--- Track only map-content popups; button help and Party hints keep their own lifetime.
function OverlandMapControls.HoverText(element, text)
    if not OverlandMapPreferences.ShowHoverText() then element.tooltip = nil; return end
    hoverTextOwners[element] = true
    gui.Tooltip(text)(element)
end

function OverlandMapControls.DismissHoverText()
    for element in pairs(hoverTextOwners) do
        if element.valid then element.tooltip = nil end
        hoverTextOwners[element] = nil
    end
end

-- Font Size ------------------------------------------------------------------------------------

--- How much bigger pins, the Party and the side panel draw than at Font Size
--- 100. In rail mode the host already zooms the whole map by Font Size
--- (WindowUIScale: the fullscreen host and the popout both apply it), so
--- this scales only outside rail mode.
--- @return number
function OverlandMapControls.UIScale()
    if math.abs(PanelDocument.WindowUIScale() - 1) > 0.001 then return 1 end
    local fontSize = dmhub.GetSettingValue("fontsize")
    if Model.IsFinite(fontSize) and fontSize > 0 then
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
function OverlandMapControls.IconButton(id, icon, tooltip, action, classes)
    local allClasses = { "overlandMapIconButton" }
    local keyboard = false
    for _, class in ipairs(classes or {}) do
        allClasses[#allClasses + 1] = class
        if class == "overlandMapHostControl" then keyboard = true end
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
        args[1] = gui.Panel { classes = { "overlandMapIconGlyph" }, bgimage = icon, interactable = false }
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
function OverlandMapControls.FocusHostControl(root, from, direction)
    local controls = {}
    local index = direction > 0 and 0 or 1
    for _, button in ipairs(root:GetChildrenWithClassRecursive("overlandMapHostControl")) do
        if button.enabled and not button:HasClass("disabled") then
            controls[#controls + 1] = button
            if button == from then index = #controls end
        end
    end
    local canvas = root:Get("overland-map-canvas")
    if canvas ~= nil and canvas.enabled then
        controls[#controls + 1] = canvas
        if canvas == from then index = #controls end
    end
    if #controls > 0 then gui.SetFocus(controls[(index - 1 + direction) % #controls + 1]) end
end

--- @param button Panel an IconButton
--- @param tooltip string
--- @param icon nil|string swap the glyph too
function OverlandMapControls.SetIconButton(button, tooltip, icon)
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
function OverlandMapControls.ModeChoice(onPick)
    local T = OverlandMapCopy.T
    local function ModeButton(mode)
        return gui.Panel {
            classes = { "overlandMapModeButton" },
            click = function() if not mod.unloaded then onPick(mode) end end,
            gui.Label { classes = { "overlandMapModeName", "sizeS" }, text = T("mode." .. mode), interactable = false },
            gui.Label { classes = { "overlandMapModeDesc", "sizeXs" }, text = T("mode." .. mode .. ".desc"), interactable = false },
        }
    end
    local children = {}
    for _, mode in ipairs(C.modes) do children[#children + 1] = ModeButton(mode) end
    children[#children + 1] = gui.Label { classes = { "overlandMapModeNote", "sizeXs" }, text = T("mode.permanent"), interactable = false }
    return gui.Panel { classes = { "overlandMapModeChoice" }, children = children }
end

--- Set a label's text only when it changed (avoids relayout).
--- @param element Panel
--- @param value nil|string
function OverlandMapControls.SetText(element, value)
    value = value or ""
    if element.text ~= value then element.text = value end
end

--- Add or remove a class only when it flips. A class change costs engine work
--- even when it changes nothing, and canvas layers run this every frame of a pan.
--- @param element Panel
--- @param class string
--- @param on boolean
function OverlandMapControls.SetClassIf(element, class, on)
    if element:HasClass(class) ~= on then element:SetClass(class, on) end
end

--- A non-interactive label; text nil shows nothing until it is set.
--- @param classes string[]
--- @param text nil|string
--- @return Panel
function OverlandMapControls.Label(classes, text)
    return gui.Label { classes = classes, text = text or "", interactable = false }
end

--- A small text button. A click is ignored after an unload or while the
--- button has the "disabled" class.
--- @param text string
--- @param action fun()
--- @return Panel
function OverlandMapControls.Button(text, action)
    return gui.Button {
        classes = { "overlandMapButton", "sizeS" }, text = text,
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
function OverlandMapControls.Segments(values, copyPrefix, onPick)
    local T = OverlandMapCopy.T
    local buttons = {}
    local row = gui.Panel { classes = { "overlandMapSegments" }, data = {} }
    for _, value in ipairs(values) do
        buttons[#buttons + 1] = gui.Label {
            classes = { "overlandMapSegment", "sizeS" }, text = T(copyPrefix .. value),
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
function OverlandMapControls.TextArea(limit, args)
    local editor = {
        classes = { "input", "bordered", "sizeS", "overlandMapTextArea" }, borderBox = true,
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
function OverlandMapControls.FocusSoon(element, stillWanted)
    OverlandMapLifetime.Schedule(C.afterLayoutDelay, function()
        if mod.unloaded or not element.valid then return end
        if stillWanted ~= nil and not stillWanted() then return end
        gui.SetFocus(element)
    end)
end

-- Text appearance controls ----------------------------------------------------------------------
-- The uploaded image behind a label or pin name, and the outline/background editor that
-- labels and Settings > Pin text share. The format rules they follow are in OverlandMapTextAppearance.

local appearanceImages, appearanceViews = {}, {}

--- The last load state any view reported for an image id ("loading" until one does).
--- @param id string
--- @return string
function OverlandMapControls.AppearanceImageStatus(id)
    return appearanceImages[id] or "loading"
end

--- Ask every view showing this image to load it again (the editor's Retry).
--- @param id string
function OverlandMapControls.RetryAppearanceImage(id)
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
function OverlandMapControls.AppearanceImage(changed)
    local A, R = OverlandMapTextAppearance, OverlandMapRecords
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
        OverlandMapControls.SetClassIf(panel, "hidden", not shown)
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
            destroy = function()
                view.generation = view.generation + 1
                if view.request then view.request.Cancel() end
                appearanceViews[view] = nil
            end,
        }
        appearanceViews[view] = true
        view.host:AddChild(view.panel)
        view.panel:SetAsFirstSibling()
        return view.panel
    end
    function view.Load()
        if mod.unloaded then return end
        if view.request then view.request.Cancel() end
        view.generation = view.generation + 1
        local generation, id = view.generation, view.id
        view.layoutKey, view.width, view.height = nil, nil, nil
        if view.leaf then view.leaf:DestroySelf(); view.leaf = nil end
        if id == "" then
            if view.panel ~= nil and view.panel.valid then OverlandMapControls.SetClassIf(view.panel, "hidden", true) end
            view.assetKey = nil
            Notify("empty")
            return
        end
        local panel = EnsurePanel()
        if panel == nil then return end
        OverlandMapControls.SetClassIf(panel, "hidden", true)
        local asset = A.ReadableAsset(id)
        view.assetKey = asset and asset.imageid or nil
        if asset == nil then Notify("unavailable"); return end
        Notify("loading")
        local request = OverlandMapImages.Request {
            id = id, source = view.assetKey,
            valid = function()
                local current = A.ReadableAsset(id)
                return panel.valid and generation == view.generation and view.id == id
                    and current ~= nil and current.imageid == view.assetKey
            end,
            changed = function(result)
                view.width, view.height = result.width, result.height
                Notify(result.status); Arrange()
            end,
        }
        view.request = request
        local leaf = gui.Panel {
            classes = { "overlandMapTextImage" }, width = "100%", height = "100%", interactable = false,
            imageLoaded = function(e)
                if mod.unloaded or not e.valid or generation ~= view.generation or view.id ~= id then return end
                local current = A.ReadableAsset(id)
                if current == nil or current.imageid ~= view.assetKey then return end
                local w, h = tonumber(e.bgimageWidth), tonumber(e.bgimageHeight)
                if not R.IsFinite(w) or not R.IsFinite(h) or w <= 0 or h <= 0 then return end
                request.Loaded(w, h)
            end,
        }
        view.leaf = leaf
        panel:AddChild(leaf)
        leaf.bgimageStreamed = id

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
--- @param ctx OverlandMapContext
--- @param pins boolean true for map pin names (lengths in points), false for labels (map fractions)
--- @param options table
--- @return Panel
function OverlandMapControls.AppearanceEditor(ctx, pins, options)
    local A, R, Model, T = OverlandMapTextAppearance, OverlandMapRecords, OverlandMapModel, OverlandMapCopy.T
    local Session = OverlandMapControls
    local panel --- @type Panel|nil
    local boundId, format, binding, generation = nil, nil, false, 0
    local inputs, sliders, invalid = {}, {}, {}
    local pickerSlot, picker, outlinePicker
    local imageError, expanded = nil, false
    local prefix = options.prefix or (pins and "overland-map-pin-appearance-" or "overland-map-label-appearance-")
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
        return gui.Panel { classes = { "overlandMapLabelField" },
            Session.Label({ "overlandMapFormLabel", "sizeXs" }, T(key)), child }
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
                OverlandMapLifetime.Schedule(0, function()
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
                OverlandMapLifetime.Schedule(0, function()
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
        local input = gui.Dropdown { id = prefix .. key, classes = { "overlandMapLabelInput" },
            width = "100%", minWidth = 0, options = entries,
            change = function(e)
                if binding or not Active() then return end
                if changed then changed(e.idChosen) else Commit({ [key] = e.idChosen }) end
            end }
        inputs[key] = { panel = input, kind = "dropdown" }
        return input
    end
    local function Numeric(key, multiplier, low, high, slider)
        local input = gui.Input { id = prefix .. key, classes = { "input", "bordered", "overlandMapLabelInput" },
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
        local track
        local handle --- @type nil|Panel
        local function Save(value)
            if binding or not Active() then return end
            invalid[key] = nil
            Commit({ [key] = value / multiplier })
        end
        track = gui.Slider { id = prefix .. key .. "-slider", width = "100%-80", height = 28,
            rmargin = 8, minValue = low, maxValue = high, round = true,
            change = function(e)
                if binding or not Active() then return end
                Session.SetText(input, string.format("%.5g", e.value))
                if options.Preview then options.Preview({ [key] = e.value / multiplier }) end
            end,
            confirm = function(e) Save(e.value) end }
        -- Get searches the sheet's IDs; label and pin editors both contain core slider IDs.
        handle = track:FindChildRecursive(function(e) return e.id == "slider-handle" end)
        local notch = track:FindChildRecursive(function(e) return e.id == "slider-notch" end)
        if notch ~= nil then notch:SetClass("overlandMapAppearanceTrack", true) end
        sliders[key] = { panel = track, handle = handle, multiplier = multiplier }
        return gui.Panel { width = "100%", height = "auto", flow = "horizontal", track, input }
    end
    local outline = Dropdown("outlineMode", { "default", "none", "custom" }, function(value)
        local changes = { outlineMode = value }
        local current = Current()
        if value == "custom" and current.outlineColor == "" then changes.outlineColor = A.Contrast(current.color) end
        Commit(changes)
    end)
    local outlineHint = Session.Label({ "overlandMapHint", "sizeXs" })
    local hex = gui.Input { id = prefix .. "outlineColor", classes = { "input", "bordered", "overlandMapLabelInput" },
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
    local customOutline = gui.Panel { classes = { "overlandMapLabelField" },
        Field("appearance.outlineColor", gui.Panel { classes = { "overlandMapLabelColor" }, hex, outlinePicker }),
        Field("appearance.outlineWidth", Numeric("outlineWidth", 100, 0, 100, true)),
        Session.Label({ "overlandMapHint", "sizeXs" }, T("appearance.thicknessHint")) }
    local background = gui.Dropdown { id = prefix .. "background", classes = { "overlandMapLabelInput" },
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
    local managed = Session.Label({ "overlandMapHint", "sizeXs" }, T("appearance.managed"))
    local choose = Session.Button(T("appearance.choose"), Choose)
    local remove = Session.Button(T("appearance.remove"), function()
        local changes = A.RemoveImagePatch(pins)
        ClosePicker(); imageError = nil; Commit(changes)
    end)
    pickerSlot = gui.Panel { width = "100%", height = "auto", classes = { "collapsed" } }
    local function Pair(title, first, second, multiplier, low, high)
        return Field(title, gui.Panel { width = "100%", height = "auto", flow = "horizontal",
            gui.Panel { width = "50%", height = "auto", flow = "vertical", rpad = 4, borderBox = true,
                Session.Label({ "overlandMapHint", "sizeXs" }, T("appearance." .. first)), Numeric(first, multiplier, low, high) },
            gui.Panel { width = "50%", height = "auto", flow = "vertical", lpad = 4, borderBox = true,
                Session.Label({ "overlandMapHint", "sizeXs" }, T("appearance." .. second)), Numeric(second, multiplier, low, high) } })
    end
    local fit = Dropdown("backgroundFit", { "fit", "fill", "stretch" })
    local sizing = Dropdown("backgroundSizing", { "auto", "manual" }, function(value)
        local changes = { backgroundSizing = value }
        local current = Current()
        if value == "manual" and not pins and not current.backgroundManualSet and current.backgroundSizing ~= "manual" then
            local canvas = ctx.root:Get("overland-map-canvas")
            local layer = canvas and canvas.data.labelLayer
            if layer or options.ImageDimensions then
                local width, height
                if options.ImageDimensions then width, height = options.ImageDimensions()
                elseif layer then width, height = layer.ImageDimensions(boundId) end
                if width and height then changes.backgroundWidth, changes.backgroundHeight = width, height end
            end
        end
        if value == "manual" or current.backgroundSizing == "manual" then changes.backgroundManualSet = true end
        Commit(changes)
    end)
    local padding = Pair("appearance.padding", "backgroundPadX", "backgroundPadY", 100, 0, 1000)
    local dimensions = Pair(pins and "appearance.dimensionsPin" or "appearance.dimensionsMap", "backgroundWidth", "backgroundHeight", pins and 1 or 100, 0.001, pins and 4096 or 400)
    local offsets = Pair(pins and "appearance.offsetPin" or "appearance.offsetMap", "backgroundX", "backgroundY", pins and 1 or 100, pins and -4096 or -400, pins and 4096 or 400)
    local more = gui.Panel { classes = { "overlandMapLabelField", "collapsed" }, offsets,
        Field("appearance.backgroundOpacity", Numeric("backgroundOpacity", 100, 0, 100, true)) }
    local arrow = gui.ExpandoArrow { halign = "left", valign = "center", interactable = false }
    local disclosure = gui.Panel { classes = { "overlandMapSectionHeader" },
        click = function() expanded = not expanded; more:SetClass("collapsed", not expanded); arrow:SetClass("expanded", expanded) end,
        arrow, Session.Label({ "overlandMapSectionLabel", "sizeS" }, T("appearance.more")) }
    local imageSettings = gui.Panel { classes = { "overlandMapLabelField" },
        Field("appearance.backgroundFit", fit), Session.Label({ "overlandMapHint", "sizeXs" }, T("appearance.fitHint")),
        Field("appearance.backgroundSizing", sizing), padding, dimensions, disclosure, more }
    local imageStatus = Session.Label({ "overlandMapHint", "sizeXs" })
    local retry = Session.Button(T("toast.retry"), function()
        if Active() then Session.RetryAppearanceImage(Current().backgroundImageId) end
    end)
    -- A hidden view of the chosen image, so Status can report loading/unavailable while nothing else shows it.
    local probeSlot = gui.Panel { width = 1, height = 1, floating = true, interactable = false, classes = { "hidden" } }
    local probe = Session.AppearanceImage(function() end)
    probe.Mount(probeSlot)
    local controls = gui.Panel { classes = { "overlandMapButtonRow" }, choose, remove }
    local imageArea = gui.Panel { classes = { "overlandMapLabelField" }, controls, pickerSlot, imageSettings,
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
        end
        boundId, format, binding = id, value, true
        if id == nil then binding = false; return end
        local director = Model.IsDirector()
        if not director and picker ~= nil then ClosePicker() end
        for key, item in pairs(inputs) do
            local input, current = item.panel, value[key]
            if item.kind == "dropdown" then input.idChosen = current
            elseif not input.hasFocus and not invalid[key]
                and not (sliders[key] and sliders[key].handle and sliders[key].handle.dragging) then
                if item.kind == "number" then current = string.format("%.5g", current * item.multiplier)
                elseif current == "" then current = A.Contrast(value.color) end
                Session.SetText(input, current); input:SetClass("invalid", false)
            end
        end
        for key, slider in pairs(sliders) do
            local handle = slider.handle
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
    panel = gui.Panel { id = prefix .. "controls", classes = { "overlandMapLabelField" },
        data = { bind = Bind, suspend = function() ClosePicker(); boundId = nil; probe.Bind({ background = "none" }) end,
            invalid = function() return next(invalid) ~= nil end },
        thinkTime = 0.25, think = Status, destroy = ClosePicker,
        Field("appearance.outline", outline), outlineHint, customOutline,
        Field("label.background", background), managed, imageArea }
    return panel
end

--- Color picker popups are 512x280; scale them down to fit a small window. allow(e) runs
--- before the popup opens and may refuse it (return false) or stamp the owner on e.data.
--- @param ctx OverlandMapContext
--- @param picker Panel a gui.ColorPicker
--- @param allow fun(e: Panel): boolean
function OverlandMapControls.ScaleColorPopup(ctx, picker, allow)
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
function OverlandMapControls.Styles()
    return {
        {
            selectors = { "overlandMapTextImage" },
            bgcolor = "white",
        },
        {
            selectors = { "overlandMapAppearanceTrack" },
            bgcolor = "@border",
        },
        {
            selectors = { "overlandMapModeChoice" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 4,
        },
        {
            selectors = { "overlandMapModeButton" },
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
            selectors = { "overlandMapModeButton", "hover" },
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            transitionTime = 0.1,
        },
        {
            selectors = { "overlandMapModeName" },
            width = "100%",
            height = "auto",
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "overlandMapModeDesc" },
            width = "100%",
            height = "auto",
            color = "@fg",
            textWrap = true,
        },
        {
            selectors = { "overlandMapModeNote" },
            width = "100%",
            height = "auto",
            color = "@fgMuted",
            textWrap = true,
        },
        {
            selectors = { "overlandMapImageHit" },
            bgimage = true,
            bgcolor = "clear",
        },
    }
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function OverlandMapControls.HostStyles()
    return {
        {
            selectors = { "overlandMapWindowBorder" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "clear",
            borderColor = "@borderSolid",
            borderWidth = 2,
        },
        {
            selectors = { "overlandMapWindowTitle" },
            bgimage = true,
            bgcolor = "@bg",
            width = "100%",
            height = C.panelTitleHeight,
            flow = "horizontal",
            halign = "left",
            valign = "top",
        },
        {
            selectors = { "overlandMapResizeGrip" },
            width = 16,
            height = 16,
            halign = "right",
            valign = "bottom",
            color = "@fgMuted",
        },
        {
            selectors = { "overlandMapHostControl", "focus" },
            borderWidth = 2,
            borderColor = "@accent",
        },
        {
            selectors = { "buttonIcon", "parent:overlandMapHostControl" },
            width = 18,
            height = 18,
        },
    }
end
