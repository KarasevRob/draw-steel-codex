local mod = dmhub.GetModLoading()

--- Shared text outline and uploaded-background behavior for Overland Map.
--- @class RegionMapTextAppearance: GameType
--- @field new fun(o?: table): RegionMapTextAppearance
--- @field defaults table<string, any>
RegionMapTextAppearance = RegisterGameType("RegionMapTextAppearance")
local A, R = RegionMapTextAppearance, RegionMapRecords

--- Optional leaves use legacy defaults; manual lengths are map-width fractions for labels and points for pins.
--- @class RegionMapTextAppearanceFormat
--- @field outlineMode nil|"default"|"none"|"custom"
--- @field outlineWidth nil|number Native 0-1 thickness, displayed on a relative 0-100 scale.
--- @field outlineColor nil|string
--- @field backgroundImageId nil|string
--- @field backgroundFit nil|"fit"|"fill"|"stretch"
--- @field backgroundSizing nil|"auto"|"manual"
--- @field backgroundPadX nil|number Horizontal padding per side, in font-size multiples.
--- @field backgroundPadY nil|number Vertical padding per side, in font-size multiples.
--- @field backgroundWidth nil|number
--- @field backgroundHeight nil|number
--- @field backgroundX nil|number
--- @field backgroundY nil|number
--- @field backgroundOpacity nil|number
--- @field backgroundManualSet nil|boolean

A.defaults = {
    outlineMode = "default", outlineWidth = 0.1, outlineColor = "",
    backgroundImageId = "", backgroundFit = "fit", backgroundSizing = "auto",
    backgroundPadX = 0.5, backgroundPadY = 0.25, backgroundWidth = 0.1, backgroundHeight = 0.03,
    backgroundX = 0, backgroundY = 0, backgroundOpacity = 1,
    backgroundManualSet = false,
}

function RegionMapTextAppearance.IsImageField(key)
    return A.defaults[key] ~= nil and key:sub(1, 10) == "background"
end

function RegionMapTextAppearance.Valid(key, value)
    if key == "outlineMode" then return value == "default" or value == "none" or value == "custom" end
    if key == "outlineColor" then
        return type(value) == "string" and (value == "" or value:match("^#%x%x%x%x%x%x$") ~= nil or value:match("^#%x%x%x%x%x%x%x%x$") ~= nil)
    end
    if key == "backgroundImageId" then return value == "" or R.IsArtworkId(value) end
    if key == "backgroundFit" then return value == "fit" or value == "fill" or value == "stretch" end
    if key == "backgroundSizing" then return value == "auto" or value == "manual" end
    if key == "backgroundManualSet" then return type(value) == "boolean" end
    if not R.IsFinite(value) then return false end
    if key == "outlineWidth" or key == "backgroundOpacity" then return value >= 0 and value <= 1 end
    if key == "backgroundPadX" or key == "backgroundPadY" then return value >= 0 and value <= 10 end
    if key == "backgroundWidth" or key == "backgroundHeight" then return value > 0 and value <= 4096 end
    if key == "backgroundX" or key == "backgroundY" then return math.abs(value) <= 4096 end
    return false
end

--- Asset availability never erases a stored reference or invalidates its owning row.
function RegionMapTextAppearance.Format(source, pins)
    local result = {}
    for key, default in pairs(A.defaults) do
        if pins and key == "backgroundWidth" then default = 180 end
        if pins and key == "backgroundHeight" then default = 30 end
        local value = R.Field(source, key, nil)
        result[key] = A.Valid(key, value) and value or default
    end
    return result
end

function RegionMapTextAppearance.ReadableAsset(id)
    local asset, reason = R.ArtworkAsset(id)
    if asset == nil then return nil, reason end
    local ok, allowed = pcall(function() return asset:HaveReadPermissions() end)
    if not ok or not allowed then return nil, "invalid" end
    return asset, nil
end

function RegionMapTextAppearance.CanChange(current, changes, director, reset)
    if not director then
        for key, value in pairs(changes) do
            if A.IsImageField(key) then return false end
            if key == "background" and value ~= R.Field(current, key, "auto")
                and (value == "image" or R.Field(current, key, "auto") == "image") then return false end
        end
        if reset and R.Field(current, "background", "auto") == "image" then return false end
    end
    local image = changes.backgroundImageId
    if image ~= nil and image ~= false and image ~= "" and image ~= R.Field(current, "backgroundImageId", "") then
        if A.ReadableAsset(image) == nil then return false end
    end
    local mode = changes.background
    if mode == nil and not reset then mode = R.Field(current, "background", "auto") end
    if mode == "image" and (changes.background ~= nil or image ~= nil) then
        local id = image
        if id == nil then id = reset and "" or R.Field(current, "backgroundImageId", "") end
        if id == false or id == "" then return false end
    end
    return true
end

function RegionMapTextAppearance.PlayerFormat(format)
    local result = DeepCopy(format or {})
    if result.background == "image" then result.background = "auto" end
    for key in pairs(A.defaults) do if A.IsImageField(key) then result[key] = nil end end
    return result
end

function RegionMapTextAppearance.RemoveImagePatch(pins)
    local changes = {} --- @type table<string, any>
    changes.background = "auto"
    if pins then changes.background = false end
    for key, value in pairs(A.defaults) do
        if A.IsImageField(key) then
            if pins then changes[key] = false else changes[key] = value end
        end
    end
    return changes
end

function RegionMapTextAppearance.SameImages(a, b)
    if R.Field(a, "background", "auto") ~= R.Field(b, "background", "auto")
        and (R.Field(a, "background", "auto") == "image" or R.Field(b, "background", "auto") == "image") then return false end
    for key in pairs(A.defaults) do
        if A.IsImageField(key) and not dmhub.DeepEqual(R.Field(a, key, nil), R.Field(b, key, nil)) then return false end
    end
    return true
end

function RegionMapTextAppearance.Outline(format, defaultWidth, defaultColor)
    if format.outlineMode == "none" then return 0, defaultColor end
    if format.outlineMode == "custom" then
        local color = format.outlineColor
        if color == nil or color == "" then color = RegionMapLabelLayer.Contrast(format.color) end
        return format.outlineWidth or 0.1, color
    end
    return defaultWidth, defaultColor
end

function RegionMapTextAppearance.MaterialKey(format, defaultWidth, defaultColor)
    local width, color = A.Outline(format, defaultWidth, defaultColor)
    return table.concat({ tostring(format.font), tostring(width), tostring(color) }, "|")
end

--- Rectangles stay in text-local coordinates; unit converts map fractions or pin points.
function RegionMapTextAppearance.Geometry(format, textWidth, textHeight, fontSize, unit)
    local width = textWidth + 2 * format.backgroundPadX * fontSize
    local height = textHeight + 2 * format.backgroundPadY * fontSize
    if format.backgroundSizing == "manual" then
        width, height = format.backgroundWidth * unit, format.backgroundHeight * unit
    end
    local x, y = format.backgroundX * unit, format.backgroundY * unit
    local text = { x1 = -textWidth / 2, x2 = textWidth / 2, y1 = -textHeight / 2, y2 = textHeight / 2 }
    local image = { x1 = x - width / 2, x2 = x + width / 2, y1 = y - height / 2, y2 = y + height / 2 }
    return { text = text, image = image,
        x1 = math.min(text.x1, image.x1), x2 = math.max(text.x2, image.x2),
        y1 = math.min(text.y1, image.y1), y2 = math.max(text.y2, image.y2) }
end

function RegionMapTextAppearance.Contains(rect, x, y)
    return x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2
end

function RegionMapTextAppearance.Fit(mode, boxWidth, boxHeight, imageWidth, imageHeight)
    if mode == "fit" then
        local scale = math.min(boxWidth / imageWidth, boxHeight / imageHeight)
        return imageWidth * scale, imageHeight * scale, nil
    end
    if mode == "fill" then
        local imageAspect, boxAspect = imageWidth / imageHeight, boxWidth / boxHeight
        local w, h = math.min(1, boxAspect / imageAspect), math.min(1, imageAspect / boxAspect)
        return boxWidth, boxHeight, { x1 = (1 - w) / 2, x2 = (1 + w) / 2, y1 = (1 - h) / 2, y2 = (1 + h) / 2 }
    end
    return boxWidth, boxHeight, nil
end

local images, views = {}, {}
function RegionMapTextAppearance.ImageStatus(id)
    return images[id] or "loading"
end

function RegionMapTextAppearance.RetryImage(id)
    for view in pairs(views) do if view.id == id and view.panel.valid then view.Load() end end
end

--- Each leaf owns its request lifetime; repeated pins share the engine's image cache.
function RegionMapTextAppearance.CreateImage(changed)
    local view = { generation = 0, status = "empty", id = "", format = nil, rect = nil }
    local function Notify(status)
        view.status = status
        if view.id ~= "" then images[view.id] = status end
        if changed then changed() end
    end
    local function Arrange()
        local panel, rect, format = view.panel, view.rect, view.format
        if not panel.valid or rect == nil or format == nil then return end
        local shown = view.status == "ready" and format.backgroundOpacity > 0
        panel:SetClass("hidden", not shown)
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
    function view.Load()
        if mod.unloaded or not view.panel.valid then return end
        view.generation = view.generation + 1
        local generation, id = view.generation, view.id
        view.layoutKey, view.width, view.height = nil, nil, nil
        view.panel:SetClass("hidden", true)
        if view.leaf then view.leaf:DestroySelf(); view.leaf = nil end
        local asset = A.ReadableAsset(id)
        view.assetKey = asset and asset.imageid or nil
        if asset == nil then Notify(id == "" and "empty" or "unavailable"); return end
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
        view.panel:AddChild(leaf)
        leaf.bgimageStreamed = id
        dmhub.Schedule(10, function()
            if not mod.unloaded and view.panel.valid and generation == view.generation and view.status == "loading" then Notify("unavailable") end
        end)
    end
    function view.Bind(format)
        view.format = format
        local id = format.background == "image" and format.backgroundImageId or ""
        if id ~= view.id then view.id = id; view.Load() end
        Arrange()
    end
    function view.Layout(rect)
        view.rect = rect
        Arrange()
    end
    view.panel = gui.Panel {
        floating = true, halign = "center", valign = "center", width = 1, height = 1,
        classes = { "hidden" }, interactable = false, monitorAssets = "images",
        refreshAssets = function()
            if view.id == "" then return end
            local asset = A.ReadableAsset(view.id)
            if (asset and asset.imageid or nil) ~= view.assetKey then view.Load() end
        end,
        destroy = function() view.generation = view.generation + 1; views[view] = nil end,
    }
    views[view] = true
    return view
end

--- Shared controls delegate saves to the owning label/map queue.
function RegionMapTextAppearance.CreateEditor(ctx, pins, options)
    local Session, Model, T = RegionMapSession, RegionMapModel, RegionMapCopy.T
    local panel --- @type Panel|nil
    local boundId, format, binding, generation = nil, nil, false, 0
    local inputs, sliders, invalid = {}, {}, {}
    local pickerSlot, picker, outlinePicker
    local imageError, expanded = nil, false
    local prefix = pins and "region-map-pin-appearance-" or "region-map-label-appearance-"
    local function Active() return not mod.unloaded and boundId ~= nil and ctx.IsAlive() and options.Active(boundId) end
    local function Current() return options.Format() end
    local function Commit(changes)
        if binding or not Active() then return false end
        if not A.CanChange(Current(), changes, Model.IsDirector()) then return false end
        local ok = options.Commit(changes)
        ctx.RefreshAll()
        return ok
    end
    local function Field(key, child)
        return gui.Panel { classes = { "regionMapLabelField" },
            Session.Label({ "regionMapFormLabel" }, T(key)), child }
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
                local valid = R.IsFinite(value) and value >= low and value <= high and A.Valid(key, value / multiplier)
                invalid[key] = not valid or nil
                e:SetClass("invalid", not valid)
                if valid then Commit({ [key] = value / multiplier }) else ctx.RefreshAll() end
            end }
        inputs[key] = { panel = input, kind = "number", multiplier = multiplier }
        if not slider then return input end
        local track = gui.Slider { id = prefix .. key .. "-slider", width = "100%-80", height = 28,
            rmargin = 8, minValue = low, maxValue = high, round = true,
            change = function(e)
                if not binding then invalid[key] = nil; Commit({ [key] = e.value / multiplier }) end
            end }
        track:Get("slider-notch"):SetClass("regionMapAppearanceTrack", true)
        sliders[key] = { panel = track, multiplier = multiplier }
        return gui.Panel { width = "100%", height = "auto", flow = "horizontal", track, input }
    end
    local outline = Dropdown("outlineMode", { "default", "none", "custom" }, function(value)
        local changes = { outlineMode = value }
        local current = Current()
        if value == "custom" and current.outlineColor == "" then changes.outlineColor = RegionMapLabelLayer.Contrast(current.color) end
        Commit(changes)
    end)
    local outlineHint = Session.Label({ "regionMapHint" })
    local hex = gui.Input { id = prefix .. "outlineColor", classes = { "input", "bordered", "regionMapLabelInput" },
        width = "100%-44", minWidth = 0, characterLimit = 9, borderBox = true,
        change = function(e)
            if binding or not Active() then return end
            local valid = e.text ~= "" and A.Valid("outlineColor", e.text)
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
    local open = outlinePicker.events.click
    outlinePicker.events.click = function(e)
        if not Active() or open == nil then return end
        e.data.boundId, e.data.generation = boundId, generation
        open(e)
        if e.popup then
            e.popup.constrainToScreen = true
            e.popup.selfStyle.scale = math.min(1, (ctx.root.renderedWidth - 16) / 512, (ctx.root.renderedHeight - 16) / 280)
        end
    end
    local customOutline = gui.Panel { classes = { "regionMapLabelField" },
        Field("appearance.outlineColor", gui.Panel { classes = { "regionMapLabelColor" }, hex, outlinePicker }),
        Field("appearance.outlineWidth", Numeric("outlineWidth", 100, 0, 100, true)),
        Session.Label({ "regionMapHint" }, T("appearance.thicknessHint")) }
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
    local managed = Session.Label({ "regionMapHint" }, T("appearance.managed"))
    local choose = Session.Button(T("appearance.choose"), Choose)
    local remove = Session.Button(T("appearance.remove"), function()
        local changes = A.RemoveImagePatch(pins)
        ClosePicker(); imageError = nil; Commit(changes)
    end)
    pickerSlot = gui.Panel { width = "100%", height = "auto", classes = { "collapsed" } }
    local function Pair(title, first, second, multiplier, low, high)
        return Field(title, gui.Panel { width = "100%", height = "auto", flow = "horizontal",
            gui.Panel { width = "50%", height = "auto", flow = "vertical", rpad = 4, borderBox = true,
                Session.Label({ "regionMapHint" }, T("appearance." .. first)), Numeric(first, multiplier, low, high) },
            gui.Panel { width = "50%", height = "auto", flow = "vertical", lpad = 4, borderBox = true,
                Session.Label({ "regionMapHint" }, T("appearance." .. second)), Numeric(second, multiplier, low, high) } })
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
        arrow, Session.Label({ "regionMapSectionLabel" }, T("appearance.more")) }
    local imageSettings = gui.Panel { classes = { "regionMapLabelField" },
        Field("appearance.backgroundFit", fit), Session.Label({ "regionMapHint" }, T("appearance.fitHint")),
        Field("appearance.backgroundSizing", sizing), padding, dimensions, disclosure, more }
    local imageStatus = Session.Label({ "regionMapHint" })
    local retry = Session.Button(T("toast.retry"), function() if Active() then A.RetryImage(Current().backgroundImageId) end end)
    local probe = A.CreateImage(function() end)
    local probeSlot = gui.Panel { width = 1, height = 1, floating = true, interactable = false, classes = { "hidden" }, probe.panel }
    local controls = gui.Panel { classes = { "regionMapButtonRow" }, choose, remove }
    local imageArea = gui.Panel { classes = { "regionMapLabelField" }, controls, pickerSlot, imageSettings,
        imageStatus, retry, probeSlot }
    local function Status()
        if not Active() or format == nil then return end
        local state = format.background == "image" and A.ImageStatus(format.backgroundImageId) or nil
        local message = imageError or (state == "loading" and "appearance.loading" or state == "unavailable" and "appearance.unavailable" or nil)
        Session.SetText(imageStatus, message and T(message) or "")
        imageStatus:SetClass("collapsed", message == nil)
        retry:SetClass("collapsed", state ~= "unavailable")
    end
    local function Bind(id, value)
        if id ~= boundId then ClosePicker(); invalid = {}; imageError = nil end
        boundId, format, binding = id, value, true
        if id == nil then binding = false; return end
        local director = Model.IsDirector()
        if not director and picker ~= nil then ClosePicker() end
        for key, item in pairs(inputs) do
            local input, current = item.panel, value[key]
            if item.kind == "dropdown" then input.idChosen = current
            elseif not input.hasFocus and not invalid[key] then
                if item.kind == "number" then current = string.format("%.5g", current * item.multiplier)
                elseif current == "" then current = RegionMapLabelLayer.Contrast(value.color) end
                Session.SetText(input, current); input:SetClass("invalid", false)
            end
        end
        for key, slider in pairs(sliders) do slider.panel.value = value[key] * slider.multiplier end
        outlinePicker.value = value.outlineColor ~= "" and value.outlineColor or RegionMapLabelLayer.Contrast(value.color)
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
