local mod = dmhub.GetModLoading()

--- @class RegionMapPinText: GameType
--- @field new fun(o?: table): RegionMapPinText
RegionMapPinText = RegisterGameType("RegionMapPinText")
local PinText = RegionMapPinText
local C, R, Model = RegionMapConstants, RegionMapRecords, RegionMapModel
local Session, Copy = RegionMapSession, RegionMapCopy

--- Sparse overrides belong to the map, never to one of its pins.
--- @class RegionMapPinNameFormat
--- @field font nil|string
--- @field majorSize nil|number
--- @field normalSize nil|number
--- @field minorSize nil|number
--- @field bold nil|boolean
--- @field italics nil|boolean
--- @field anchor nil|string
--- @field spacing nil|number
--- @field color nil|string
--- @field background nil|string
--- @field backgroundColor nil|string
local fields = { "font", "majorSize", "normalSize", "minorSize", "bold", "italics", "anchor",
    "spacing", "color", "background", "backgroundColor" }
local known = {}; for _, key in ipairs(fields) do known[key] = true end

local function Valid(key, value)
    if key == "font" then return type(value) == "string" and #value > 0 and #value <= 128 end
    if key == "bold" or key == "italics" then return type(value) == "boolean" end
    if key == "majorSize" or key == "normalSize" or key == "minorSize" then
        return R.IsFinite(value) and value >= 6 and value <= 72 and math.abs(value * 10 - math.floor(value * 10 + 0.5)) < 0.00001
    end
    if key == "anchor" then return value == "left" or value == "center" or value == "right" end
    if key == "spacing" then return R.IsFinite(value) and value >= 0 and value <= 1 end
    if key == "background" then return value == "auto" or value == "plate" or value == "none" end
    if key == "color" or key == "backgroundColor" then
        return type(value) == "string" and (value:match("^#%x%x%x%x%x%x$") ~= nil or value:match("^#%x%x%x%x%x%x%x%x$") ~= nil)
    end
    return false
end

--- Bad optional leaves fall back independently; they never affect Location validity.
function RegionMapPinText.Overrides(map)
    local stored, result = R.Field(map, "pinNameFormat", nil), {}
    for _, key in ipairs(fields) do
        local value = R.Field(stored, key, nil)
        if Valid(key, value) then result[key] = value end
    end
    return result
end

local function ValidPatch(patch)
    if type(patch) ~= "table" then return false end
    for key, value in pairs(patch) do
        if not known[key] or (value ~= false and not Valid(key, value)) then return false end
        if key == "font" and value ~= false and RegionMapLabels.DisplayFont(value) ~= value then return false end
    end
    return true
end

local function Merge(format, patch)
    for key, value in pairs(patch) do
        if value == false and key ~= "bold" and key ~= "italics" then format[key] = nil else format[key] = value end
    end
    return format
end

function RegionMapPinText.ApplyPatch(map, patch, reset)
    if not ValidPatch(patch) or type(reset) ~= "boolean" then return nil end
    return Merge(reset and {} or PinText.Overrides(map), patch)
end

function RegionMapPinText.CanEdit(id)
    local map = Model.GetLocation(id)
    return not mod.unloaded and Model.IsDirector() and map ~= nil and map.imageId ~= ""
end

local queues = {}
local function Notify(q) if q.notify then q.notify() end end
function RegionMapPinText.CancelPending(id)
    local q = queues[id]
    if q == nil then return end
    q.pending, q.reset, q.failed = {}, false, false
    if not q.running then q.batch = nil end
    q.status = "denied"
end

function RegionMapPinText.CancelUnauthorized()
    for id in pairs(queues) do if not PinText.CanEdit(id) then PinText.CancelPending(id) end end
end

function RegionMapPinText.Snapshot(map)
    local result = PinText.Overrides(map)
    local id = R.Field(map, "id", nil)
    local q = queues[id]
    if q == nil then return result end
    if not PinText.CanEdit(id) then PinText.CancelPending(id); return result end
    if q.batch then result = Merge(q.batch.reset and {} or result, q.batch.patch) end
    return Merge(q.reset and {} or result, q.pending)
end

function RegionMapPinText.Status(id)
    if not PinText.CanEdit(id) then PinText.CancelPending(id) end
    return queues[id] and queues[id].status or "saved"
end

function RegionMapPinText.Observe(id, callback)
    if queues[id] == nil then queues[id] = { pending = {}, reset = false, status = "saved" } end
    queues[id].notify = callback
end

local Drain
Drain = function(id)
    local q = queues[id]
    if mod.unloaded or q == nil or q.running or q.failed then return end
    if not PinText.CanEdit(id) then PinText.CancelPending(id); Notify(q); return end
    if q.batch == nil and not q.reset and next(q.pending) == nil then q.status = "saved"; return end
    if R.PendingWrite(C.locationTableName, id) then
        if not q.waiting then
            q.waiting = true
            dmhub.Schedule(C.busyRetryDelay, function()
                q.waiting = false
                if not mod.unloaded then Drain(id) end
            end)
        end
        return
    end
    -- Fold the latest picker values into the retry, so Retry cannot briefly resend an obsolete color.
    local batch = q.batch or { patch = {}, reset = false }
    if q.reset then batch.patch, batch.reset = {}, true end
    for key, value in pairs(q.pending) do batch.patch[key] = value end
    q.pending, q.reset, q.batch = {}, false, batch
    q.running, q.status = true, "saving"
    local function Receipt(success, operation)
        -- Upload callbacks may run before SetPinNameFormat returns its Undo entry.
        dmhub.Schedule(0, function()
            if mod.unloaded or queues[id] ~= q or q.batch ~= batch or not q.running then return end
            q.running = false
            if success then
                if batch.entry then RegionMapUndo.Remember(batch.entry) end
                q.batch, q.status = nil, "saved"
                Drain(id)
            elseif PinText.CanEdit(id) then
                q.failed, q.status = true, "failed"
                batch.retry = { operation = operation, before = batch.before }
            else PinText.CancelPending(id) end
            Notify(q)
        end)
    end
    batch.before = batch.retry and batch.retry.before or DeepCopy(Model.GetLocation(id))
    local ok, reason, entry, operation = Model.SetPinNameFormat(id, batch.patch, batch.reset, {
        success = function(op) Receipt(true, op) end,
        failure = function(op) Receipt(false, op) end,
    }, batch.retry)
    batch.entry = entry
    if entry then batch.before = entry.steps[1].before end
    if not ok and (reason == "permission" or reason == "invalid") then
        q.running = false; PinText.CancelPending(id)
    elseif not ok then Receipt(false, operation) end
    Notify(q)
end

function RegionMapPinText.Commit(id, patch, reset)
    if not PinText.CanEdit(id) then PinText.CancelPending(id); return false end
    if not ValidPatch(patch) then return false end
    if queues[id] == nil then PinText.Observe(id, nil) end
    local q = queues[id]
    if reset then q.pending, q.reset = {}, true end
    for key, value in pairs(patch) do q.pending[key] = value end
    if not q.failed then q.status = "saving" end
    Drain(id)
    Notify(q)
    return true
end

function RegionMapPinText.Retry(id)
    local q = queues[id]
    if q == nil or not q.failed then return end
    q.failed = false
    Drain(id)
end

local theme, themeVersion = nil, 0
local function Theme()
    if theme == nil then
        theme = ThemeEngine.MergeTokens({ { fontFace = "@label", color = "@fgStrong", bgcolor = "@bg" } })[1]
    end
    return theme
end
ThemeEngine.OnThemeChanged(mod, function() theme, themeVersion = nil, themeVersion + 1 end)

function RegionMapPinText.Format(map)
    local format, tokens = PinText.Snapshot(map), Theme()
    local font = format.font or tokens.fontFace
    format.font = RegionMapLabels.DisplayFont(font) == font and font or RegionMapLabels.DisplayFont(tokens.fontFace)
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
function RegionMapPinText.Apply(label, text, format, importance, plate, scale)
    local fontSize = format[importance .. "Size"] * scale
    local tokens = Theme()
    local fill, hpad, vpad, radius, outline = "clear", 0, 0, 0, 0
    if format.background == "default" then
        if plate then fill, hpad, vpad, radius = tokens.bgcolor, 7, 2, 4 else outline = 0.3 end
    elseif format.background == "auto" then
        fill, hpad, vpad, radius = RegionMapLabelLayer.Contrast(format.color), fontSize * 0.04, fontSize * 0.02, fontSize * 0.02
    elseif format.background == "plate" then
        fill, hpad, vpad, radius = format.backgroundColor, fontSize * 0.2, fontSize * 0.12, fontSize * 0.1
    end
    Session.SetText(label, string.format("<cspace=%.4fem>%s</cspace>", format.spacing, Copy.Literal(text)))
    label.selfStyle.fontFace, label.selfStyle.fontSize = format.font, fontSize
    label.selfStyle.bold, label.selfStyle.italics = format.bold, format.italics
    label.selfStyle.color, label.selfStyle.textAlignment = format.color, "center"
    label.selfStyle.bgcolor, label.selfStyle.bgimage = fill, true
    label.selfStyle.hpad, label.selfStyle.vpad, label.selfStyle.borderBox = hpad, vpad, true
    label.selfStyle.cornerRadius = radius
    label.selfStyle.textOutlineWidth, label.selfStyle.textOutlineColor = outline, tokens.bgcolor
    Session.SetClassIf(label, "customPinBackground", format.background ~= "default")
end

local abbreviations = { mr = true, mrs = true, ms = true, dr = true, prof = true, st = true, mt = true,
    sr = true, jr = true, vs = true, etc = true, e = true, g = true, i = true, fig = true, no = true }

--- Fold paragraphs and return two sentence-like spans, never cutting through a UTF-8 character.
function RegionMapPinText.DescriptionPreview(value)
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

function RegionMapPinText.HoverText(id)
    local location = Model.GetLocation(id)
    if location == nil then return nil end
    local details = Model.Details(id)
    local preview = PinText.DescriptionPreview(details and details.description)
    return Copy.T(preview == "" and "pin.hover.nameOnly" or "pin.hover",
        { name = Model.DisplayName(location), description = preview })
end

--- A single settings section in the existing popover scroller.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapPinText.CreateSettings(ctx)
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
        return gui.Panel { classes = { "regionMapLabelField" },
            Session.Label({ "regionMapFormLabel" }, T(copyId)), child }
    end
    local options = {}
    for _, font in ipairs(gui.availableFonts or {}) do options[#options + 1] = { id = font, text = font } end
    table.sort(options, function(a, b) return a.text < b.text end)
    table.insert(options, 1, { id = "default", text = T("pinText.themeFont") })
    local font = gui.Dropdown {
        id = "region-map-pin-font", classes = { "regionMapLabelInput" }, options = options, width = "100%", minWidth = 0,
        change = function(e) Changed("font", e.idChosen ~= "default" and e.idChosen or false) end,
    }
    local function Numeric(key, multiplier, low, high)
        local function Check(e, commit)
            if binding or not Active() then return end
            local value = tonumber(e.text)
            local valid = R.IsFinite(value) and value >= low and value <= high and Valid(key, value / multiplier)
            invalid[key] = not valid or nil
            e:SetClass("invalid", not valid)
            if commit and valid then Changed(key, value / multiplier) else ctx.RefreshAll() end
        end
        local input = gui.Input {
            id = "region-map-pin-" .. key, classes = { "input", "bordered", "regionMapLabelInput" },
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
            Session.Label({ "regionMapHint" }, T("edit.importance." .. importance)),
            Numeric(importance .. "Size", 1, 6, 72) }
    end
    local bold = gui.Check { classes = { "regionMapCheck" }, text = T("label.bold"), width = "50%", minWidth = 0, borderBox = true,
        change = function(e) Changed("bold", e.value == true) end }
    local italics = gui.Check { classes = { "regionMapCheck" }, text = T("label.italics"), width = "50%", minWidth = 0, borderBox = true,
        change = function(e) Changed("italics", e.value == true) end }
    local anchor = Session.Segments({ "left", "center", "right" }, "label.", function(value) Changed("anchor", value) end)
    local spacing = Numeric("spacing", 100, 0, 100)
    local function ColorField(key, copyId)
        local hex = gui.Input {
            id = "region-map-pin-" .. key, classes = { "input", "bordered", "regionMapLabelInput" },
            width = "100%-44", minWidth = 0, borderBox = true, characterLimit = 9,
            change = function(e)
                if binding or not Active() then return end
                local valid = Valid(key, e.text)
                invalid[key] = not valid or nil
                e:SetClass("invalid", not valid)
                if valid then Changed(key, e.text) else ctx.RefreshAll() end
            end,
        }
        local picker = gui.ColorPicker {
            id = "region-map-pin-" .. key .. "-picker", width = 32, height = 32, lmargin = 8, hasAlpha = true, value = "#ffffffff",
            popupAlignment = "left",
            change = function(e)
                if e.data.openId ~= boundId or e.data.generation ~= generation then return end
                local value = e.value
                Changed(key, type(value) == "string" and value or value.tostring)
            end,
        }
        local open = picker.events.click
        picker.events.click = function(e)
            if open == nil or not Active() then return end
            e.data.openId, e.data.generation = boundId, generation
            open(e)
            if e.popup then
                e.popup.constrainToScreen = true
                e.popup.selfStyle.scale = math.min(1, (ctx.root.renderedWidth - 16) / 512, (ctx.root.renderedHeight - 16) / 280)
            end
        end
        inputs[key], colors[key] = hex, picker
        return Field(copyId, gui.Panel { classes = { "regionMapLabelColor" }, hex, picker })
    end
    local color = ColorField("color", "label.color")
    local themeColor = gui.Check { classes = { "regionMapCheck" }, text = T("pinText.themeColor"), width = "100%", minWidth = 0,
        change = function(e)
            if binding or not Active() then return end
            local format = PinText.Format(ctx.CurrentMap())
            local value = format.color
            if e.value then value = false end
            Changed("color", value)
        end,
    }
    local background = gui.Dropdown {
        id = "region-map-pin-background", classes = { "regionMapLabelInput" }, width = "100%", minWidth = 0,
        options = { { id = "default", text = T("pinText.default") }, { id = "auto", text = T("label.auto") },
            { id = "plate", text = T("label.plate") }, { id = "none", text = T("label.none") } },
        change = function(e) Changed("background", e.idChosen ~= "default" and e.idChosen or false) end,
    }
    local plateColor = ColorField("backgroundColor", "pinText.plateColor")
    local appearance = gui.Panel { classes = { "regionMapLabelField", "collapsed" },
        Field("label.spacing", spacing), themeColor, color, Field("label.background", background), plateColor }
    local arrow = gui.ExpandoArrow { halign = "left", valign = "center", interactable = false }
    local disclosure = gui.Panel { classes = { "regionMapSectionHeader" },
        click = function()
            local expand = appearance:HasClass("collapsed")
            appearance:SetClass("collapsed", not expand); arrow:SetClass("expanded", expand)
        end,
        arrow, Session.Label({ "regionMapSectionLabel" }, T("pinText.appearance")) }
    local status = Session.Label({ "regionMapHint" })
    local retry = Session.Button(T("toast.retry"), function() if Active() then PinText.Retry(boundId) end end)
    local reset = Session.Button(T("pinText.reset"), function()
        if not Active() then return end
        invalid = {}
        generation = generation + 1
        for _, picker in pairs(colors) do picker.data.openId = nil; picker.popup = nil end
        PinText.Commit(boundId, {}, true)
    end)
    local function Suspend()
        boundId, generation = nil, generation + 1
        for _, picker in pairs(colors) do picker.data.openId = nil; picker.popup = nil end
    end
    local function Bind(map)
        if map == nil or not PinText.CanEdit(map.id) then Suspend(); return end
        binding = true
        local changedMap = boundId ~= map.id
        if changedMap then Suspend(); invalid = {}; boundId = map.id end
        -- Keep receipts refreshing the canvas after Settings closes, until this host is destroyed.
        observed[map.id] = true
        PinText.Observe(boundId, Refresh)
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
        background.idChosen = format.background
        themeColor.value = overrides.color == nil
        plateColor:SetClass("collapsed", format.background ~= "plate")
        for key, picker in pairs(colors) do picker.value = format[key] end
        reset:SetClass("collapsed", next(overrides) == nil)
        local state = PinText.Status(boundId)
        local copyId = (next(invalid) ~= nil or state == "failed" or state == "denied") and "edit.notSaved"
            or state == "saving" and "edit.saving" or "edit.saved"
        Session.SetText(status, T(copyId))
        retry:SetClass("collapsed", state ~= "failed")
        binding = false
    end
    panel = gui.Panel {
        id = "region-map-pin-text-settings", classes = { "regionMapLabelField" },
        data = { bind = Bind, suspend = Suspend },
        destroy = function()
            Suspend()
            for id in pairs(observed) do
                local q = queues[id]
                if q and q.notify == Refresh then q.notify = nil end
            end
        end,
        regionMapThemeChanged = function() if Active() then Bind(ctx.CurrentMap()) end end,
        Session.Label({ "regionMapFormLabel" }, T("pinText.title")),
        Session.Label({ "regionMapHint" }, T("pinText.scope")),
        Field("label.font", font),
        Field("pinText.size", gui.Panel { width = "100%", height = "auto", flow = "horizontal", children = tiers }),
        gui.Panel { width = "100%", height = "auto", flow = "horizontal", bold, italics },
        Field("pinText.anchor", anchor), disclosure, appearance,
        gui.Panel { classes = { "regionMapButtonRow" }, reset, retry }, status,
    }
    return panel
end
