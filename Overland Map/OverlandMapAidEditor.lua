local mod = dmhub.GetModLoading()

--- @class OverlandMapAidEditor: GameType
--- @field new fun(o?: table): OverlandMapAidEditor
OverlandMapAidEditor = RegisterGameType("OverlandMapAidEditor")
local Aids = OverlandMapAids
local R, Model, Session = OverlandMapRecords, OverlandMapModel, OverlandMapControls
local A, Tools, C = OverlandMapTextAppearance, OverlandMapCanvasTools, OverlandMapConstants
local T = OverlandMapCopy.T
local kinds = { "compass", "scaleBar" }

local function Number(value)
    return string.format("%.6g", value)
end

local function Style(panel, key, value)
    panel.data.written = panel.data.written or {}
    if panel.data.written[key] ~= value then panel.data.written[key] = value; panel.selfStyle[key] = value end
end

--- One editor is rebound to the selected aid; pickers capture both its map and lifetime.
function OverlandMapAidEditor.Create(ctx)
    local release
    local boundId, boundKind, binding, generation = nil, nil, false, 0
    local inputs, invalid, colors, observed, rows = {}, {}, {}, {}, {}
    local picker, panel, editor, appearance, status, issue, retryImage
    local pickerSlot = gui.Panel { width = "100%", height = "auto", classes = { "collapsed" } }
    local function Canvas() return ctx.root:Get("overland-map-canvas") end
    local function Layer() local canvas = Canvas(); return canvas and canvas.data.aidLayer end
    local function Current() return Aids.Snapshot(Model.GetLocation(boundId), boundKind) end
    local function Active()
        return ctx.IsAlive() and ctx.data.popover == "aids" and ctx.data.mapId == boundId
            and ctx.data.selectedAid == boundKind and boundKind ~= nil and Aids.CanEdit(boundId)
            and Current() ~= nil
    end
    local function Refresh() if ctx.IsAlive() then ctx.RefreshAll() end end
    local function Commit(changes)
        if binding or not Active() then return false end
        local layer = Layer()
        if layer then layer.SetPreview(nil) end
        return Aids.Commit(boundId, boundKind, changes)
    end
    local function Field(text, child)
        return gui.Panel { classes = { "overlandMapLabelField" }, Session.Label({ "overlandMapFormLabel", "sizeXs" }, text), child }
    end
    local function ClosePicker()
        generation = generation + 1
        if picker then picker.popup = nil; picker = nil end
        pickerSlot.children = {}; pickerSlot:SetClass("collapsed", true)
        for _, color in pairs(colors) do color.popup = nil end
    end
    local function Numeric(key, multiplier, low, high)
        local function Save(e)
            if binding or not Active() then return end
            e.data.dirty = false
            local value = tonumber(e.text)
            local valid = R.IsFinite(value) and value >= low and value <= high
                and R.ValidMapAidField(assert(boundKind), key, value / multiplier)
            invalid[key] = not valid or nil; e:SetClass("invalid", not valid)
            if valid then Commit({ [key] = value / multiplier }) end
        end
        local input = gui.Input { id = "overland-map-aid-" .. key, classes = { "input", "bordered", "overlandMapLabelInput" },
            width = "100%", minWidth = 0, characterLimit = 32, borderBox = true, data = { dirty = false },
            edit = function(e) if not binding then e.data.dirty = true end end, change = Save }
        inputs[key] = { panel = input, multiplier = multiplier }
        return input
    end
    local function Check(key, title)
        local check = gui.Check { classes = { "overlandMapCheck", "sizeS" }, text = T(title),
            change = function(e) Commit({ [key] = e.value == true }) end }
        inputs[key] = { panel = check, boolean = true }
        return check
    end
    local function Color(key, title)
        local input = gui.Input { id = "overland-map-aid-" .. key, classes = { "input", "bordered", "overlandMapLabelInput" },
            width = "100%-44", minWidth = 0, borderBox = true, characterLimit = 9, data = { dirty = false },
            edit = function(e) if not binding then e.data.dirty = true end end,
            change = function(e)
                if binding or not Active() then return end
                e.data.dirty = false
                local valid = A.ValidColor(e.text)
                invalid[key] = not valid or nil; e:SetClass("invalid", not valid)
                if valid then Commit({ [key] = e.text }) end
            end }
        inputs[key] = { panel = input }
        local color = gui.ColorPicker { width = 32, height = 32, lmargin = 8, hasAlpha = true, popupAlignment = "left",
            change = function(e)
                if not Active() or e.data.generation ~= generation then return end
                local value = e.value
                if type(value) ~= "string" then value = value.tostring end
                Commit({ [key] = value })
            end }
        colors[key] = color
        Session.ScaleColorPopup(ctx, color, function(e)
            if not Active() then return false end
            e.data.generation = generation
            return true
        end)
        return Field(T(title), gui.Panel { width = "100%", height = "auto", flow = "horizontal", input, color })
    end
    local function Flush()
        if not Active() then return end
        for _, field in pairs(inputs) do
            if field.panel.data.dirty then field.panel:FireEvent("change") end
        end
    end
    local function Suspend()
        Flush(); ClosePicker()
        if appearance then appearance.data.suspend() end
        if boundId then Aids.Leave(boundId) end
        boundId, boundKind = nil, nil
    end
    local function ChooseImage()
        if not Active() then return end
        ClosePicker()
        local id, kind, token, expected = boundId, boundKind, generation, Current().imageId
        local chosen = false
        picker = gui.IconEditor { width = "100%", height = 1, library = "journal", categoriesHidden = true,
            allowNone = false, allowPaste = true, hideIcon = true, liveEdit = false,
            rightClick = function() end,
            change = function(e)
                if chosen or not Active() or boundId ~= id or boundKind ~= kind or generation ~= token
                    or picker == nil or picker.popup == nil or Current().imageId ~= expected then return end
                chosen = true
                local value = e.value or ""
                if A.ReadableAsset(value) then Commit({ imageId = value })
                else OverlandMapUndo.Notify("appearance.invalidImage") end
                OverlandMapLifetime.Schedule(0, function() if not mod.unloaded and panel.valid and generation == token then ClosePicker(); Refresh() end end)
            end }
        pickerSlot.children = { picker }; pickerSlot:SetClass("collapsed", false)
        picker:SetValue(expected, false)
        local press = picker.events.press
        picker.events.press, picker.events.dropfiles = function() end, function() end
        if press then press(picker) end
    end
    local northText = gui.Input { id = "overland-map-aid-text", classes = { "input", "bordered", "overlandMapLabelInput" },
        width = "100%", minWidth = 0, characterLimit = C.labelTextLimit, data = { dirty = false },
        edit = function(e) if not binding then e.data.dirty = true end end,
        change = function(e)
            if binding or not Active() then return end
            e.data.dirty = false
            local value = R.NormalizeMultiline(e.text, C.labelTextLimit, C.labelByteLimit)
            invalid.text = value == nil or nil
            e:SetClass("invalid", value == nil)
            if value then Commit({ text = value }) end
        end }
    inputs.text = { panel = northText }
    local compassFields = gui.Panel { classes = { "overlandMapLabelField" },
        Session.Button(T("appearance.choose"), ChooseImage),
        Session.Button(T("aids.defaultImage"), function() Commit({ imageId = "" }) end), pickerSlot,
        Field(T("aids.width"), Numeric("width", 100, 0.1, 100)),
        Field(T("aids.angle"), Numeric("angle", 1, -360, 360)),
        Field(T("aids.opacity"), Numeric("opacity", 100, 0, 100)),
        Check("north", "aids.north"), Field(T("aids.northText"), northText),
        Session.Label({ "overlandMapHint", "sizeXs" }, T("aids.northHint")) }
    local distanceTitle = Session.Label({ "overlandMapFormLabel", "sizeXs" }, "")
    local scaleFields = gui.Panel { classes = { "overlandMapLabelField" }, distanceTitle, Numeric("distance", 1, 0, math.huge) }
    local fonts = {}
    for _, name in ipairs(gui.availableFonts or {}) do fonts[#fonts + 1] = { id = name, text = name } end
    table.sort(fonts, function(a, b) return a.text < b.text end)
    local font = gui.Dropdown { id = "overland-map-aid-font", classes = { "overlandMapLabelInput" }, width = "100%", minWidth = 0,
        options = fonts, change = function(e) Commit({ font = e.idChosen }) end }
    local alignment = Session.Segments({ "left", "center", "right" }, "label.", function(value) Commit({ alignment = value }) end)
    appearance = Session.AppearanceEditor(ctx, false, {
        prefix = "overland-map-aid-appearance-",
        Active = function(id) return Active() and id == boundId .. ":" .. boundKind end,
        Format = Current, Commit = Commit,
        Preview = function(changes)
            local layer, canvas = Layer(), Canvas()
            if Active() and layer then layer.SetPreview(boundKind, changes); canvas:FireEvent("relayout") end
        end,
        ImageDimensions = function() local layer = Layer(); if layer then return layer.ImageDimensions(boundKind) end end,
    })
    local plate = Color("backgroundColor", "pinText.plateColor")
    local retry = Session.Button(T("toast.retry"), function() if Active() then Aids.Retry(boundId) end end)
    status = Session.Label({ "overlandMapHint", "sizeXs" }, "")
    issue = Session.Label({ "overlandMapHint", "sizeXs" }, "")
    retryImage = Session.Button(T("toast.retry"), function() local layer = Layer(); if Active() and layer then layer.Retry() end end)
    local unlock = Session.Button(T("aids.unlock"), function()
        if not Active() or not ctx.data.locked then return end
        ctx.root:Get("overland-map-lock"):FireEvent("click")
        ctx.KeepAidVisible(boundKind)
    end)
    editor = gui.Panel { classes = { "overlandMapLabelField", "collapsed" },
        Session.Label({ "overlandMapHint", "sizeXs" }, T("aids.editHint")), unlock,
        Session.Button(T("aids.place"), function()
            if not Active() then return end
            Flush(); ctx.SetTool("aidPlace"); ctx.SetPopover(nil)
        end),
        Session.Button(T("aids.find"), function() if Active() then ctx.FindAid(boundKind) end end),
        Field(T("aids.x"), Numeric("u", 100, 0, 100)), Field(T("aids.y"), Numeric("v", 100, 0, 100)),
        compassFields, scaleFields, issue, retryImage,
        Field(T("label.font"), font), Field(T("aids.size"), Numeric("size", 100, C.labelMinSize * 100, C.labelMaxSize * 100)),
        Check("bold", "label.bold"), Check("italics", "label.italics"),
        alignment,
        Field(T("label.spacing"), Numeric("spacing", 100, 0, 100)), Color("color", "label.color"), appearance, plate,
        status, retry, Session.Button(T("aids.done"), function() ctx.SelectAid(nil) end) }
    local children = { Session.Label({ "overlandMapPopoverTitle", "sizeM" }, T("aids.title")) }
    for _, kind in ipairs(kinds) do
        local add = Session.Button(T("aids.add"), function()
            local map, layer = ctx.CurrentMap(), Layer()
            if not map or not layer or not Aids.CanEdit(map.id) then return end
            local patch = {}
            if kind == "scaleBar" then
                patch.distance = OverlandMapGeometry.InitialDistance(map, layer.imageWidth, layer.imageHeight)
                if patch.distance == nil then return end
            end
            if not observed[map.id] then observed[map.id] = Aids.Observe(map.id, Refresh) end
            if Aids.Commit(map.id, kind, patch, "add") then ctx.SelectAid(kind) end
        end)
        local edit = Session.Button(T("aids.edit"), function() ctx.SelectAid(kind) end)
        local remove = Session.Button(T("aids.remove"), function()
            local map = ctx.CurrentMap()
            if map == nil or not Aids.CanEdit(map.id) then return end
            Flush()
            Aids.Commit(map.id, kind, {}, "remove")
            if ctx.data.selectedAid == kind then ctx.SelectAid(nil) end
            Refresh()
        end)
        local hint = Session.Label({ "overlandMapHint", "sizeXs" }, T("aids.calibrate"))
        rows[kind] = { add = add, edit = edit, remove = remove, hint = hint }
        children[#children + 1] = gui.Panel { classes = { "overlandMapLabelField" },
            Session.Label({ "overlandMapFormLabel", "sizeXs" }, T("aids." .. kind)),
            gui.Panel { classes = { "overlandMapButtonRow" }, add, edit, remove }, hint }
    end
    children[#children + 1] = editor
    local function Status()
        if not ctx.IsAlive() or ctx.data.popover ~= "aids" then return end
        local currentMap, currentLayer = ctx.CurrentMap(), Layer()
        if currentMap and Aids.CanEdit(currentMap.id) then
            local row = rows.scaleBar
            local calibrated = currentLayer and OverlandMapGeometry.InitialDistance(currentMap, currentLayer.imageWidth, currentLayer.imageHeight) ~= nil
            row.add.interactable = calibrated == true
            Session.SetClassIf(row.add, "disabled", not calibrated)
            Session.SetClassIf(row.hint, "collapsed", calibrated or Aids.Snapshot(currentMap, "scaleBar") ~= nil)
        end
        if not Active() then return end
        local state = Aids.Status(boundId)
        Session.SetText(status, T((next(invalid) or appearance.data.invalid() or state == "failed" or state == "invalid" or state == "denied")
            and "edit.notSaved" or state == "saving" and "edit.saving" or "edit.saved"))
        retry:SetClass("collapsed", state ~= "failed")
        local layer = Layer()
        local availability = layer and layer.Availability(boundKind)
        local message
        if boundKind == "compass" then
            message = availability == "unavailable" and "appearance.unavailable" or availability == "loading" and "appearance.loading" or nil
        else message = availability end
        Session.SetText(issue, message and T(message) or "")
        issue:SetClass("collapsed", message == nil)
        retryImage:SetClass("collapsed", boundKind ~= "compass" or availability ~= "unavailable")
    end
    local function Bind(map)
        local selected = ctx.data.selectedAid
        if not map or not Aids.CanEdit(map.id) then Suspend(); return end
        if not observed[map.id] then observed[map.id] = Aids.Observe(map.id, Refresh) end
        local layer = Layer()
        for _, kind in ipairs(kinds) do
            local exists = Aids.Snapshot(map, kind) ~= nil
            local row = rows[kind]
            row.add:SetClass("collapsed", exists); row.edit:SetClass("collapsed", not exists); row.remove:SetClass("collapsed", not exists)
            local calibrated = kind ~= "scaleBar" or (layer and OverlandMapGeometry.InitialDistance(map, layer.imageWidth, layer.imageHeight) ~= nil)
            row.add.interactable = calibrated == true; row.add:SetClass("disabled", not calibrated)
            row.hint:SetClass("collapsed", kind ~= "scaleBar" or calibrated or exists)
        end
        local value = selected and Aids.Snapshot(map, selected)
        editor:SetClass("collapsed", value == nil)
        unlock:SetClass("collapsed", not ctx.data.locked)
        if value == nil then Suspend(); return end
        if boundId ~= map.id or boundKind ~= selected then Suspend(); invalid = {}; boundId, boundKind = map.id, selected end
        binding = true
        for key, field in pairs(inputs) do
            local input, current = field.panel, value[key]
            if current ~= nil then
                if field.boolean then input.value = current
                elseif not input.hasFocus and not invalid[key] then
                    Session.SetText(input, field.multiplier and Number(current * field.multiplier) or current)
                    input:SetClass("invalid", false); input.data.dirty = false
                end
            end
        end
        font.idChosen = A.DisplayFont(value.font)
        alignment.data.select(value.alignment)
        for key, color in pairs(colors) do color.value = value[key] end
        compassFields:SetClass("collapsed", selected ~= "compass"); scaleFields:SetClass("collapsed", selected ~= "scaleBar")
        Session.SetText(distanceTitle, T("aids.distance", { unit = R.Field(R.Field(map, "scale", nil), "unit", "mi") }))
        appearance.data.bind(boundId .. ":" .. boundKind, value)
        plate:SetClass("collapsed", value.background ~= "plate")
        binding = false
        Status()
    end
    panel = gui.Panel { id = "overland-map-aid-settings", classes = { "overlandMapPopoverBody" }, children = children,
        data = { bind = Bind, suspend = Suspend }, flushAids = Flush, thinkTime = 0.25, think = Status,
        destroy = function()
            if release then release() end
            Suspend()
            for _, unsubscribe in pairs(observed) do unsubscribe() end
            Aids.Prune()
        end }
    release = OverlandMapSession.Register { scope = ctx, valid = function() return panel.valid end, flush = Flush, cancel = function(_, id) if boundId == id then ctx.ClearAid() end end }
    return panel
end
