local mod = dmhub.GetModLoading()

--- @class OverlandMapPinText: GameType
--- @field new fun(o?: table): OverlandMapPinText
OverlandMapPinText = RegisterGameType("OverlandMapPinText")
local PinText = OverlandMapPinText
local C, R, Model = OverlandMapConstants, OverlandMapRecords, OverlandMapModel
local Session, Copy = OverlandMapControls, OverlandMapCopy

local A = OverlandMapTextAppearance
local fields = A.pinFields

--- The overrides this client understands for a map; bad leaves fall back independently.
--- @param map any
--- @return table<string, any>
function OverlandMapPinText.Overrides(map)
    return A.PinOverrides(R.Field(map, "pinNameFormat", nil))
end

function OverlandMapPinText.CanEdit(id)
    local map = Model.GetLocation(id)
    return not mod.unloaded and Model.IsDirector() and map ~= nil and map.imageId ~= ""
end

-- One queue per map: every change saves at once (sliders on release), one write at a time.
local queue = OverlandMapSaveQueue.Create {
    canEdit = function(id) return PinText.CanEdit(id) end,
    busy = function(id) return R.PendingWrite(C.locationTableName, id) ~= nil end,
    send = function(id, batch, callbacks)
        return OverlandMapCommands.SetPinNameFormat(id, batch.changes, batch.kind == "reset", callbacks, batch.retry)
    end,
    mergeKinds = { edit = true },
    -- Changes queued behind a write in flight go out as one write. A failed batch is never
    -- merged: Retry resends exactly its values, and later changes follow it.
    coalesce = function(first, later)
        if later.kind == "reset" then return { changes = DeepCopy(later.changes), kind = "reset", retry = first.retry } end
        local changes = DeepCopy(first.changes)
        for key, value in pairs(later.changes) do changes[key] = value end
        return { changes = changes, kind = first.kind, retry = first.retry }
    end,
}

--- Drop unsent changes to a map's pin text (map removed, permission lost).
--- @param id string
function OverlandMapPinText.CancelPending(id)
    queue.Cancel(id)
end

function OverlandMapPinText.CancelUnauthorized()
    for id in pairs(queue.All()) do if not PinText.CanEdit(id) then queue.Cancel(id) end end
end

--- The map's overrides with every change not yet confirmed on top. Reading never cancels anything.
--- @param map any
--- @return table<string, any>
function OverlandMapPinText.Snapshot(map)
    local result = PinText.Overrides(map)
    local id = R.Field(map, "id", nil)
    if id == nil then return result end
    local batches, pending = queue.Unconfirmed(id)
    for _, batch in ipairs(batches) do
        result = A.MergePinPatch(batch.kind == "reset" and {} or result, batch.changes)
    end
    return A.MergePinPatch(result, pending)
end

--- @param id nil|string
--- @return string
function OverlandMapPinText.Status(id)
    if id == nil then return "saved" end
    return queue.Status(id)
end

--- @param id nil|string
--- @param callback nil|fun()
function OverlandMapPinText.Observe(id, callback)
    if id ~= nil then return queue.Observe(id, callback) end
end

--- Queue a change (reset = start from the theme defaults); false when invalid or not permitted.
--- @param id nil|string
--- @param patch table
--- @param reset nil|boolean
--- @return boolean
function OverlandMapPinText.Commit(id, patch, reset)
    if id == nil then return false end
    if not PinText.CanEdit(id) then queue.Cancel(id); return false end
    if not A.ValidPinPatch(patch) then return false end
    if not A.CanChange(PinText.Snapshot(Model.GetLocation(id)), patch, Model.IsDirector(), reset) then return false end
    queue.Commit(id, patch, reset and "reset" or "edit")
    return true
end

--- @param id nil|string
function OverlandMapPinText.Retry(id)
    if id ~= nil then queue.Retry(id) end
end

--- Forget idle map queues once Settings is gone.
function OverlandMapPinText.Prune()
    queue.Prune()
end

Model.RegisterCompanion {
    cancelMap = function(id) queue.Cancel(id) end,
    afterViewChange = function() PinText.CancelUnauthorized() end,
}

local theme, themeVersion = nil, 0
local function Theme()
    if theme == nil then
        theme = ThemeEngine.MergeTokens({ { fontFace = "@label", color = "@fgStrong", bgcolor = "@bg" } })[1]
    end
    return theme
end
ThemeEngine.OnThemeChanged(mod, function() theme, themeVersion = nil, themeVersion + 1 end)

function OverlandMapPinText.Format(map)
    local format, tokens = PinText.Snapshot(map), Theme()
    for key, value in pairs(OverlandMapTextAppearance.Format(format, true)) do format[key] = value end
    local font = format.font or tokens.fontFace
    format.font = A.DisplayFont(font) == font and font or A.DisplayFont(tokens.fontFace)
    for importance, size in pairs(C.pinNameSize) do format[importance .. "Size"] = format[importance .. "Size"] or size end
    if format.bold == nil then format.bold = true end
    if format.italics == nil then format.italics = false end
    format.anchor, format.spacing = format.anchor or "center", format.spacing or 0
    format.color, format.background = format.color or tokens.color, format.background or "default"
    format.backgroundColor = format.backgroundColor or "#000000bf"
    local key = { tostring(themeVersion) }
    for _, field in ipairs(fields) do key[#key + 1] = tostring(format[field]) end
    return format, table.concat(key, "|")
end

--- All native properties are assigned effective values, including after reset.
function OverlandMapPinText.Apply(label, text, format, importance, plate, scale)
    local fontSize = format[importance .. "Size"] * scale
    local host = label
    local composition = label.data and label.data.appearance
    if composition then
        local material = PinText.MaterialKey(format, plate)
        if composition.material and composition.material ~= material then composition.ReplaceText() end
        composition.material = material
        label = composition.text
        composition.format, composition.fontSize, composition.scale = format, fontSize, scale
    end
    local tokens = Theme()
    local fill, hpad, vpad, radius, outline = "clear", 0, 0, 0, 0
    if format.background == "default" then
        if plate then fill, hpad, vpad, radius = tokens.bgcolor, 7, 2, 4 else outline = 0.3 end
    elseif format.background == "auto" then
        fill, hpad, vpad, radius = A.Contrast(format.color), fontSize * 0.04, fontSize * 0.02, fontSize * 0.02
    elseif format.background == "plate" then
        fill, hpad, vpad, radius = format.backgroundColor, fontSize * 0.2, fontSize * 0.12, fontSize * 0.1
    end
    Session.SetText(label, string.format("<cspace=%.4fem>%s</cspace>", format.spacing, Copy.Literal(text)))
    label.selfStyle.fontFace, label.selfStyle.fontSize = format.font, fontSize
    label.selfStyle.bold, label.selfStyle.italics = format.bold, format.italics
    label.selfStyle.color, label.selfStyle.textAlignment = format.color, "center"
    host.selfStyle.bgcolor, host.selfStyle.bgimage = fill, true
    host.selfStyle.hpad, host.selfStyle.vpad, host.selfStyle.borderBox = hpad, vpad, true
    host.selfStyle.cornerRadius = radius
    label.selfStyle.textOutlineWidth, label.selfStyle.textOutlineColor = A.Outline(format, outline, tokens.bgcolor)
    Session.SetClassIf(host, "customPinBackground", format.background ~= "default")
    if composition then
        composition.image.Bind(format)
        composition.Layout()
        -- Image placement needs the text's rendered size; plain text needs nothing more.
        if format.background == "image" then
            OverlandMapLifetime.Schedule(C.afterLayoutDelay, function()
                if not mod.unloaded and host.valid then composition.Layout() end
            end)
        end
    end
end

function OverlandMapPinText.MaterialKey(format, plate)
    local width = format.background == "default" and not plate and 0.3 or 0
    return OverlandMapTextAppearance.MaterialKey(format, width, Theme().bgcolor)
end

--- A pin name: text, plus an image backing and (on name plates) its click area, which are
--- built only when the map's format first asks for an image background.
--- @param plate boolean
--- @param floating boolean
--- @param owner nil|Panel the pin, which receives clicks on the image area
--- @return Panel
function OverlandMapPinText.CreateName(plate, floating, owner)
    local host
    local composition = {}
    local function Forward(event)
        return function(element)
            if event == "press" then element.tooltip = nil end
            if owner and owner.valid then owner:FireEvent(event) end
        end
    end
    local function Hit()
        if composition.hit ~= nil and composition.hit.valid then return composition.hit end
        composition.hit = gui.Panel { classes = { "overlandMapImageHit", "collapsed" },
            floating = true, halign = "center", valign = "center", width = 1, height = 1, interactable = plate,
            swallowPress = true, press = Forward("press"), click = Forward("click"), doubleclick = Forward("doubleclick"),
            rightClick = Forward("rightClick"),
            -- The engine dismisses tooltips on the hovered element, not a forwarded parent.
            hover = function(element) if owner and owner.valid then owner:FireEvent("hover", element) end end,
            dehover = function(element) element.tooltip = nil end,
            destroy = function(element) element.tooltip = nil end }
        host:AddChild(composition.hit)
        return composition.hit
    end
    --- A new native text label in place of the old one (font or outline changed).
    function composition.ReplaceText()
        local old = composition.text
        composition.text = gui.Label { width = "auto", height = "auto", textWrap = false, interactable = false, text = "" }
        host:AddChild(composition.text)
        if old ~= nil and old.valid then old:DestroySelf() end
        if composition.hit ~= nil and composition.hit.valid then composition.hit:SetAsLastSibling() end
    end
    function composition.Layout()
        if mod.unloaded or host == nil or not host.valid or composition.format == nil then return end
        local format, text = composition.format, composition.text
        if format.background ~= "image" then
            if composition.hit ~= nil and composition.hit.valid then Session.SetClassIf(composition.hit, "collapsed", true) end
            return
        end
        local geometry = A.Geometry(format, text.renderedWidth, text.renderedHeight, composition.fontSize, composition.scale)
        composition.image.Layout(geometry.image)
        host.selfStyle.bgcolor = composition.image.status == "ready" and "clear" or A.Contrast(format.color)
        local hit = Hit()
        if plate and composition.image.status == "ready" and format.backgroundOpacity > 0 then
            local rect = geometry.image
            hit.selfStyle.width, hit.selfStyle.height = rect.x2 - rect.x1, rect.y2 - rect.y1
            hit.selfStyle.x, hit.selfStyle.y = (rect.x1 + rect.x2) / 2, (rect.y1 + rect.y2) / 2
            Session.SetClassIf(hit, "collapsed", false)
        else
            Session.SetClassIf(hit, "collapsed", true)
        end
    end
    composition.image = Session.AppearanceImage(function()
        if host and host.valid then composition.Layout() end
    end)
    composition.text = gui.Label { width = "auto", height = "auto", textWrap = false, interactable = false, text = "" }
    local classes = { "overlandMapPinName" }
    if plate then classes[#classes + 1] = "plate" end
    host = gui.Panel { classes = classes, floating = floating, interactable = false,
        width = "auto", height = "auto", data = { appearance = composition },
        rendered = function() composition.Layout() end,
        composition.text }
    composition.image.Mount(host)
    return host
end

local abbreviations = { mr = true, mrs = true, ms = true, dr = true, prof = true, st = true, mt = true,
    sr = true, jr = true, vs = true, etc = true, e = true, g = true, i = true, fig = true, no = true }

--- Fold paragraphs and return two sentence-like spans, never cutting through a UTF-8 character.
function OverlandMapPinText.DescriptionPreview(value)
    if type(value) ~= "string" or R.TextLength(value) == math.huge then return "" end
    local text = value:gsub("%s+", " "):gsub("^ +", ""):gsub(" +$", "")
    if text == "" then return "" end
    local finish, sentences, at = #text, 0, 1
    while at <= #text do
        local first, last = text:find("[.!?]+", at)
        if first == nil then break end
        local ending = last
        while text:sub(ending + 1, ending + 1):match('["\'%)%]]') do ending = ending + 1 end
        local follows = text:sub(ending + 1, ending + 1)
        local word = text:sub(1, first - 1):match("([%a%.]+)$") or ""
        local period = text:sub(first, last) == "."
        local abbreviation = period and (abbreviations[word:lower()] or word:match("^%u$") or word:match("%.%a$"))
        if (follows == " " or follows == "") and not abbreviation then
            sentences = sentences + 1
            if sentences == 2 then finish = ending; break end
        end
        at = ending + 1
    end
    local shortened = finish < #text
    local preview = text:sub(1, finish)
    if R.TextLength(preview) > (shortened and 297 or 300) then
        local boundary = utf8.offset(preview, 298)
        preview = preview:sub(1, boundary - 1)
        local wordEnd = preview:match("^.*() ")
        if wordEnd and R.TextLength(preview:sub(wordEnd)) < 40 then preview = preview:sub(1, wordEnd - 1) end
        shortened = true
    end
    preview = preview:gsub(" +$", "")
    return shortened and (preview:gsub("%.+$", "") .. "...") or preview
end

function OverlandMapPinText.HoverText(id)
    local location = Model.GetLocation(id)
    if location == nil then return nil end
    local details = Model.Details(id)
    local preview = PinText.DescriptionPreview(details and details.description)
    return Copy.T(preview == "" and "pin.hover.nameOnly" or "pin.hover",
        { name = Model.DisplayName(location), description = preview })
end

--- A single settings section in the existing popover scroller.
--- @param ctx OverlandMapContext
--- @return Panel
function OverlandMapPinText.CreateSettings(ctx)
    local T = Copy.T
    local panel, boundId, binding, generation = nil, nil, false, 0
    local inputs, colors, invalid = {}, {}, {}
    local observed = {}
    local function Refresh() if ctx.IsAlive() then ctx.RefreshAll() end end
    local function Active()
        local map = ctx.CurrentMap()
        return ctx.IsAlive() and ctx.data.popover == "settings" and map ~= nil and map.id == boundId and PinText.CanEdit(boundId)
    end
    local function Changed(key, value)
        if binding or not Active() then return end
        invalid[key] = nil
        PinText.Commit(boundId, { [key] = value })
    end
    local function Field(copyId, child)
        return gui.Panel { classes = { "overlandMapLabelField" },
            Session.Label({ "overlandMapFormLabel", "sizeXs" }, T(copyId)), child }
    end
    local options = {}
    for _, font in ipairs(gui.availableFonts or {}) do options[#options + 1] = { id = font, text = font } end
    table.sort(options, function(a, b) return a.text < b.text end)
    table.insert(options, 1, { id = "default", text = T("pinText.themeFont") })
    local font = gui.Dropdown {
        id = "overland-map-pin-font", classes = { "overlandMapLabelInput" }, options = options, width = "100%", minWidth = 0,
        change = function(e) Changed("font", e.idChosen ~= "default" and e.idChosen or false) end,
    }
    local function Numeric(key, multiplier, low, high)
        -- Typing only marks the field; the window refreshes when its validity flips or on commit.
        local function Check(e, commit)
            if binding or not Active() then return end
            local value = tonumber(e.text)
            local valid = R.IsFinite(value) and value >= low and value <= high and A.ValidPin(key, value / multiplier)
            local flipped = (invalid[key] == true) == valid
            invalid[key] = not valid or nil
            e:SetClass("invalid", not valid)
            if commit and valid then Changed(key, value / multiplier) elseif flipped or commit then ctx.RefreshAll() end
        end
        local input = gui.Input {
            id = "overland-map-pin-" .. key, classes = { "input", "bordered", "overlandMapLabelInput" },
            width = "100%", minWidth = 0, borderBox = true, characterLimit = 12,
            edit = function(e) Check(e, false) end,
            change = function(e) Check(e, true) end,
        }
        inputs[key] = input
        return input
    end
    local tiers = {}
    for _, importance in ipairs({ "major", "normal", "minor" }) do
        tiers[#tiers + 1] = gui.Panel { width = "33.333%", height = "auto", flow = "vertical", borderBox = true, rpad = 4,
            Session.Label({ "overlandMapHint", "sizeXs" }, T("edit.importance." .. importance)),
            Numeric(importance .. "Size", 1, 6, 72) }
    end
    local bold = gui.Check { classes = { "overlandMapCheck" }, text = T("label.bold"), width = "50%", minWidth = 0, borderBox = true,
        change = function(e) Changed("bold", e.value == true) end }
    local italics = gui.Check { classes = { "overlandMapCheck" }, text = T("label.italics"), width = "50%", minWidth = 0, borderBox = true,
        change = function(e) Changed("italics", e.value == true) end }
    local anchor = Session.Segments({ "left", "center", "right" }, "label.", function(value) Changed("anchor", value) end)
    local spacing = Numeric("spacing", 100, 0, 100)
    local function ColorField(key, copyId)
        local hex = gui.Input {
            id = "overland-map-pin-" .. key, classes = { "input", "bordered", "overlandMapLabelInput" },
            width = "100%-44", minWidth = 0, borderBox = true, characterLimit = 9,
            change = function(e)
                if binding or not Active() then return end
                local valid = A.ValidPin(key, e.text)
                invalid[key] = not valid or nil
                e:SetClass("invalid", not valid)
                if valid then Changed(key, e.text) else ctx.RefreshAll() end
            end,
        }
        local picker = gui.ColorPicker {
            id = "overland-map-pin-" .. key .. "-picker", width = 32, height = 32, lmargin = 8, hasAlpha = true, value = "#ffffffff",
            popupAlignment = "left",
            change = function(e)
                if e.data.openId ~= boundId or e.data.generation ~= generation then return end
                local value = e.value
                Changed(key, type(value) == "string" and value or value.tostring)
            end,
        }
        Session.ScaleColorPopup(ctx, picker, function(e)
            if not Active() then return false end
            e.data.openId, e.data.generation = boundId, generation
            return true
        end)
        inputs[key], colors[key] = hex, picker
        return Field(copyId, gui.Panel { classes = { "overlandMapLabelColor" }, hex, picker })
    end
    local color = ColorField("color", "label.color")
    local themeColor = gui.Check { classes = { "overlandMapCheck" }, text = T("pinText.themeColor"), width = "100%", minWidth = 0,
        change = function(e)
            if binding or not Active() then return end
            local format = PinText.Format(ctx.CurrentMap())
            local value = format.color
            if e.value then value = false end
            Changed("color", value)
        end,
    }
    local appearanceControls = Session.AppearanceEditor(ctx, true, {
        Active = function(id) return Active() and id == boundId end,
        Format = function() return PinText.Format(ctx.CurrentMap()) end,
        Commit = function(changes) return PinText.Commit(boundId, changes) end,
    })
    local plateColor = ColorField("backgroundColor", "pinText.plateColor")
    local previewHint = Session.Label({ "overlandMapHint", "collapsed", "sizeXs" })
    local appearance = gui.Panel { classes = { "overlandMapLabelField", "collapsed" },
        Field("label.spacing", spacing), themeColor, color, previewHint, appearanceControls, plateColor }
    local arrow = gui.ExpandoArrow { halign = "left", valign = "center", interactable = false }
    local disclosure = gui.Panel { classes = { "overlandMapSectionHeader" },
        click = function()
            local expand = appearance:HasClass("collapsed")
            appearance:SetClass("collapsed", not expand); arrow:SetClass("expanded", expand)
        end,
        arrow, Session.Label({ "overlandMapSectionLabel", "sizeS" }, T("pinText.appearance")) }
    local status = Session.Label({ "overlandMapHint", "sizeXs" })
    local retry = Session.Button(T("toast.retry"), function() if Active() then PinText.Retry(boundId) end end)
    local reset = Session.Button(T("pinText.reset"), function()
        if not Active() then return end
        invalid = {}
        generation = generation + 1
        for _, picker in pairs(colors) do picker.data.openId = nil; picker.popup = nil end
        appearanceControls.data.suspend()
        PinText.Commit(boundId, {}, true)
    end)
    local function Suspend()
        boundId, generation = nil, generation + 1
        appearanceControls.data.suspend()
        for _, picker in pairs(colors) do picker.data.openId = nil; picker.popup = nil end
    end
    local function Bind(map)
        if map == nil or not PinText.CanEdit(map.id) then Suspend(); return end
        binding = true
        local changedMap = boundId ~= map.id
        if changedMap then Suspend(); invalid = {}; boundId = map.id end
        -- Keep receipts refreshing the canvas after Settings closes, until this host is destroyed.
        if not observed[map.id] then observed[map.id] = PinText.Observe(map.id, Refresh) end
        local format, overrides = PinText.Format(map), PinText.Snapshot(map)
        local values = { majorSize = string.format("%.1f", format.majorSize), normalSize = string.format("%.1f", format.normalSize),
            minorSize = string.format("%.1f", format.minorSize), spacing = string.format("%.4g", format.spacing * 100),
            color = format.color, backgroundColor = format.backgroundColor }
        for key, input in pairs(inputs) do
            if changedMap or (not input.hasFocus and not invalid[key]) then
                Session.SetText(input, values[key]); input:SetClass("invalid", false)
            end
        end
        font.idChosen = overrides.font and format.font or "default"
        bold.value, italics.value = format.bold, format.italics
        anchor.data.select(format.anchor)
        appearanceControls.data.bind(boundId, format)
        local canvas = ctx.root:Get("overland-map-canvas")
        local visible = canvas and canvas.data.visibleNames and canvas.data.visibleNames() or 0
        local empty = #Model.Children(map.id) == 0
        previewHint:SetClass("collapsed", visible > 0)
        Session.SetText(previewHint, T(empty and "appearance.previewEmpty" or "appearance.previewHidden"))
        themeColor.value = overrides.color == nil
        plateColor:SetClass("collapsed", format.background ~= "plate")
        for key, picker in pairs(colors) do picker.value = format[key] end
        reset:SetClass("collapsed", next(overrides) == nil)
        local state = PinText.Status(boundId)
        local copyId = (next(invalid) ~= nil or appearanceControls.data.invalid() or state == "failed" or state == "denied") and "edit.notSaved"
            or state == "saving" and "edit.saving" or "edit.saved"
        Session.SetText(status, T(copyId))
        retry:SetClass("collapsed", state ~= "failed")
        binding = false
    end
    panel = gui.Panel {
        id = "overland-map-pin-text-settings", classes = { "overlandMapLabelField" },
        data = { bind = Bind, suspend = Suspend },
        destroy = function()
            Suspend()
            for _, unsubscribe in pairs(observed) do unsubscribe() end
            PinText.Prune()
        end,
        overlandMapThemeChanged = function() if Active() then Bind(ctx.CurrentMap()) end end,
        Session.Label({ "overlandMapFormLabel", "sizeXs" }, T("pinText.title")),
        Session.Label({ "overlandMapHint", "sizeXs" }, T("pinText.scope")),
        Field("label.font", font),
        Field("pinText.size", gui.Panel { width = "100%", height = "auto", flow = "horizontal", children = tiers }),
        gui.Panel { width = "100%", height = "auto", flow = "horizontal", bold, italics },
        Field("pinText.anchor", anchor), disclosure, appearance,
        gui.Panel { classes = { "overlandMapButtonRow" }, reset, retry }, status,
    }
    return panel
end
