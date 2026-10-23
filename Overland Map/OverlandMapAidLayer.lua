local mod = dmhub.GetModLoading()

--- @class OverlandMapAidLayer: GameType
--- @field new fun(o?: table): OverlandMapAidLayer
OverlandMapAidLayer = RegisterGameType("OverlandMapAidLayer")
local Aids = OverlandMapAids
local R, Model, Session = OverlandMapRecords, OverlandMapModel, OverlandMapControls
local A, Tools, C = OverlandMapTextAppearance, OverlandMapCanvasTools, OverlandMapConstants
local T = OverlandMapCopy.T
local kinds = { "compass", "scaleBar" }

local referenceWidth, baseFont = 4096, 64

local function Number(value)
    return string.format("%.6g", value)
end

local function Style(panel, key, value)
    panel.data.written = panel.data.written or {}
    if panel.data.written[key] ~= value then panel.data.written[key] = value; panel.selfStyle[key] = value end
end

--- Passive artwork and handles; the canvas arbitrates hits against pins, paths and labels.
function OverlandMapAidLayer.Create(ctx)
    local api = {}
    local release
    local entries, map, layout, reference, preview = {}, nil, nil, nil, nil
    local dirty, scheduled = true, false
    local layer = gui.Panel { classes = { "overlandMapOverlay" }, floating = true, interactable = false,
        destroy = function() if release then release() end end }
    local handles = gui.Panel { classes = { "overlandMapOverlay" }, floating = true, interactable = false }
    api.layer, api.handles = layer, handles
    release = OverlandMapSession.Register { scope = ctx, valid = function() return layer.valid end, cancel = function(_, id)
        if map and map.id == id and ctx.data.selectedAid then ctx.ClearAid() end
    end }
    local function Relayout()
        dirty = true
        if scheduled then return end
        scheduled = true
        OverlandMapLifetime.Schedule(C.afterLayoutDelay, function()
            scheduled = false
            if not mod.unloaded and layer.valid and ctx.IsAlive() then api.Layout(layout) end
        end)
    end
    local function Text(entry)
        local panel = gui.Label { width = "auto", height = "auto", floating = true, halign = "center", valign = "center",
            textWrap = false, interactable = false, text = "", data = { written = {} }, rendered = Relayout }
        entry.root:AddChild(panel)
        return panel
    end
    local function NewEntry(kind)
        local entry = { kind = kind, generation = 0, texts = {}, bars = {}, ticks = {}, imageKey = nil, imageStatus = "empty" }
        entry.back = gui.Panel { classes = { "overlandMapAidBacking" }, floating = true, halign = "center", valign = "center",
            width = 1, height = 1, interactable = false, data = { written = {} } }
        entry.root = gui.Panel { width = 1, height = 1, floating = true, halign = "center", valign = "center",
            interactable = false, data = { written = {} }, entry.back }
        entry.background = Session.AppearanceImage(Relayout)
        entry.background.Mount(entry.back)
        layer:AddChild(entry.root)
        for i = 1, kind == "compass" and 1 or 3 do entry.texts[i] = Text(entry) end
        if kind == "scaleBar" then
            for i = 1, 4 do
                entry.bars[i] = gui.Panel { classes = { "overlandMapAidSegment", i % 2 == 0 and "light" or "dark" },
                    floating = true, halign = "center", valign = "center", interactable = false, data = { written = {} } }
                entry.root:AddChild(entry.bars[i])
            end
            for i = 1, 9 do
                entry.ticks[i] = gui.Panel { classes = { "overlandMapAidTick" }, floating = true, halign = "center", valign = "center",
                    interactable = false, data = { written = {} } }
                entry.root:AddChild(entry.ticks[i])
            end
        end
        entries[kind] = entry
        return entry
    end
    local function LoadCompass(entry, row)
        local id = row.imageId
        local asset = id ~= "" and A.ReadableAsset(id) or nil
        local imageId = id == "" and mod.images["compass-icon"] or (asset and asset.imageid)
        local key = tostring(map and map.id) .. ":" .. tostring(id) .. ":" .. tostring(imageId)
        if key == entry.imageKey then return end
        if entry.request then entry.request.Cancel() end
        entry.imageKey, entry.generation = key, entry.generation + 1
        local generation, mapId = entry.generation, map and map.id
        entry.imageStatus, entry.imageWidth, entry.imageHeight = "unavailable", nil, nil
        if entry.art and entry.art.valid then entry.art:DestroySelf() end
        entry.art = nil
        if imageId == nil or imageId == "" then Relayout(); return end
        entry.imageStatus = "loading"
        local request = OverlandMapImages.Request {
            id = id, source = imageId,
            valid = function()
                local current = id ~= "" and A.ReadableAsset(id) or nil
                return layer.valid and entry.generation == generation and map ~= nil and map.id == mapId
                    and (id == "" or (current ~= nil and current.imageid == imageId))
            end,
            changed = function(result)
                entry.imageWidth, entry.imageHeight, entry.imageStatus = result.width, result.height, result.status
                Relayout()
            end,
        }
        entry.request = request
        local art = gui.Panel { classes = { "overlandMapAidImage" }, floating = true, halign = "center", valign = "center",
            width = 1, height = 1, interactable = false, data = { written = {} },
            imageLoaded = function(e)
                if not e.valid or not layer.valid or mod.unloaded or entry.generation ~= generation
                    or map == nil or map.id ~= mapId or entry.imageKey ~= key then return end
                if id ~= "" then
                    local currentAsset = A.ReadableAsset(id)
                    if currentAsset == nil or currentAsset.imageid ~= imageId then return end
                end
                local w, h = tonumber(e.bgimageWidth), tonumber(e.bgimageHeight)
                if not R.IsFinite(w) or not R.IsFinite(h) or w <= 0 or h <= 0 then return end
                request.Loaded(w, h)
            end }
        entry.art = art
        entry.root:AddChild(art)
        if id == "" then art.bgimage = imageId else art.bgimageStreamed = id end

    end
    local function BindText(entry, row, strings)
        local format = DeepCopy(row)
        format.font = A.DisplayFont(row.font)
        local material = A.MaterialKey(format, 0, A.Contrast(row.color))
        for i, text in ipairs(strings) do
            if entry.material ~= nil and entry.material ~= material then
                entry.texts[i]:DestroySelf(); entry.texts[i] = Text(entry)
            end
            local label = entry.texts[i]
            Session.SetText(label, string.format("<cspace=%.4fem>%s</cspace>", row.spacing, OverlandMapCopy.Literal(text)))
            Style(label, "fontFace", format.font)
            -- Native font-size changes do not remeasure unchanged text; scale the fixed font like map labels.
            Style(label, "fontSize", baseFont / Session.UIScale())
            Style(label, "scale", row.size * referenceWidth / baseFont)
            Style(label, "bold", row.bold); Style(label, "italics", row.italics)
            Style(label, "textAlignment", row.alignment)
            Style(label, "color", row.color)
            local width, color = A.Outline(row, 0, A.Contrast(row.color))
            Style(label, "textOutlineWidth", width); Style(label, "textOutlineColor", color)
        end
        entry.material = material
    end
    local function Row(entry)
        if preview and preview.kind == entry.kind then
            local result = DeepCopy(entry.row)
            for key, value in pairs(preview.changes) do result[key] = value end
            return result
        end
        return entry.row
    end
    function api.Bind(current)
        if map == nil or current == nil or map.id ~= current.id then
            preview = nil
            for _, entry in pairs(entries) do
                entry.generation = entry.generation + 1
                entry.root:DestroySelf()
            end
            entries = {}
        end
        map = current
        for _, kind in ipairs(kinds) do
            local row = current and Aids.Snapshot(current, kind) or nil
            local visible = kind == "compass" and OverlandMapPreferences.ShowCompass() or kind == "scaleBar" and OverlandMapPreferences.ShowScaleBar()
            if row and (visible or (Model.IsDirector() and ctx.data.selectedAid == kind)) then
                local entry = entries[kind] or NewEntry(kind)
                if not dmhub.DeepEqual(entry.row, row) then dirty = true end
                entry.row = row
                if kind == "compass" then LoadCompass(entry, row) end
                local unit = R.Field(R.Field(current, "scale", nil), "unit", "mi")
                local distance = row.distance or 0
                BindText(entry, row, kind == "compass" and { row.north and row.text or "" }
                    or { "0", Number(distance / 2), Number(distance) .. " " .. unit })
            elseif entries[kind] then
                entries[kind].generation = entries[kind].generation + 1
                entries[kind].root:DestroySelf(); entries[kind] = nil; dirty = true
            end
        end
        dirty = true
    end
    local function Union(box, x, y, width, height)
        box.x1, box.x2 = math.min(box.x1, x - width / 2), math.max(box.x2, x + width / 2)
        box.y1, box.y2 = math.min(box.y1, y - height / 2), math.max(box.y2, y + height / 2)
    end
    local function Geometry(entry)
        local row = Row(entry)
        local unit = R.Field(R.Field(map, "scale", nil), "unit", "mi")
        local distance = row.distance or 0
        BindText(entry, row, entry.kind == "compass" and { row.north and row.text or "" }
            or { "0", Number(distance / 2), Number(distance) .. " " .. unit })
        local size = row.size * referenceWidth
        local box = { x1 = 0, x2 = 0, y1 = 0, y2 = 0 }
        if entry.kind == "compass" then
            if entry.imageStatus ~= "ready" then return nil end
            local width, height = row.width * referenceWidth, row.width * referenceWidth * entry.imageHeight / entry.imageWidth
            if not R.IsFinite(height) or height <= 0 then return nil end
            Style(entry.art, "width", width); Style(entry.art, "height", height)
            Style(entry.art, "rotate", -row.angle); Style(entry.art, "opacity", row.opacity)
            local a = math.rad(row.angle)
            Union(box, 0, 0, math.abs(width * math.cos(a)) + math.abs(height * math.sin(a)),
                math.abs(width * math.sin(a)) + math.abs(height * math.cos(a)))
            local label = entry.texts[1]
            Session.SetClassIf(label, "collapsed", not row.north or row.text == "")
            if row.north and row.text ~= "" then
                local textScale = size / baseFont
                local w, h = label.renderedWidth * textScale, label.renderedHeight * textScale
                local x, y = OverlandMapGeometry.NorthAnchor(height, row.angle, w, h, size * 0.25)
                label.x, label.y = x, y
                Union(box, x, y, w, h)
                box.text = { x1 = x - w / 2, x2 = x + w / 2, y1 = y - h / 2, y2 = y + h / 2 }
            end
            box.width, box.height, box.angle = width, height, row.angle
        else
            local fraction, reason = OverlandMapGeometry.ScaleWidth(map, row, api.imageWidth, api.imageHeight)
            entry.reason = reason
            if fraction == nil then return nil end
            local length, thickness = fraction * referenceWidth, size * 0.4
            Union(box, 0, 0, length, thickness)
            for i, bar in ipairs(entry.bars) do
                Style(bar, "width", length / 4); Style(bar, "height", thickness)
                bar.x, bar.y = -length / 2 + (i - 0.5) * length / 4, 0
            end
            local sizes = {}
            for i, label in ipairs(entry.texts) do
                sizes[i] = { width = label.renderedWidth * size / baseFont, height = label.renderedHeight * size / baseFont }
            end
            local labels = OverlandMapGeometry.ScaleLabels(length, sizes, size * 0.3)
            for i, pos in ipairs(labels) do
                entry.texts[i].x, entry.texts[i].y = pos.x, pos.y + thickness / 2
                local spans = OverlandMapGeometry.TickSegments(pos, labels, size * 0.3)
                for j = 1, 3 do
                    local tick, span = entry.ticks[(i - 1) * 3 + j], spans[j]
                    Session.SetClassIf(tick, "collapsed", span == nil)
                    if span then
                        Style(tick, "width", size * 0.04); Style(tick, "height", span.last - span.first)
                        tick.x, tick.y = pos.x, thickness / 2 + (span.first + span.last) / 2
                    end
                end
                Union(box, pos.x, pos.y + thickness / 2, pos.width, pos.height)
            end
            box.width, box.height, box.angle = length, thickness, 0
            box.endpoints = { -length / 2, length / 2 }
        end
        local cx, cy = (box.x1 + box.x2) / 2, (box.y1 + box.y2) / 2
        local width, height = box.x2 - box.x1, box.y2 - box.y1
        local fill, padX, padY = "clear", 0, 0
        if row.background == "auto" then fill, padX, padY = A.Contrast(row.color), size * 0.1, size * 0.05
        elseif row.background == "plate" then fill, padX, padY = row.backgroundColor, size * 0.3, size * 0.2 end
        entry.background.Bind(row)
        if row.background == "image" then
            local geometry = A.Geometry(row, width, height, size, referenceWidth)
            entry.background.Layout(geometry.image)
            if entry.background.status ~= "ready" then fill = A.Contrast(row.color) end
        end
        entry.back.x, entry.back.y = cx, cy
        Style(entry.back, "width", width + 2 * padX); Style(entry.back, "height", height + 2 * padY)
        Style(entry.back, "bgcolor", fill)
        return box
    end
    -- Native border shaders fill a rotated rectangle at cardinal angles; plain edges stay transparent.
    local outline = gui.Panel { classes = { "collapsed" }, floating = true, halign = "center", valign = "center",
        width = 1, height = 1, interactable = false,
        gui.Panel { classes = { "bgAccent" }, width = "100%", height = 1, halign = "center", valign = "top", interactable = false },
        gui.Panel { classes = { "bgAccent" }, width = "100%", height = 1, halign = "center", valign = "bottom", interactable = false },
        gui.Panel { classes = { "bgAccent" }, width = 1, height = "100%", halign = "left", valign = "center", floating = true, interactable = false },
        gui.Panel { classes = { "bgAccent" }, width = 1, height = "100%", halign = "right", valign = "center", floating = true, interactable = false } }
    local resize = gui.Panel { classes = { "overlandMapLabelHandle", "collapsed" }, floating = true, interactable = false }
    local rotate = gui.Panel { classes = { "overlandMapLabelHandle", "collapsed" }, floating = true, interactable = false,
        Session.Label({ "label", "sizeS" }, "R") }
    handles.children = { outline, resize, rotate }
    local handlePositions = {}
    function api.Layout(current)
        layout = current
        Session.SetClassIf(layer, "collapsed", current == nil)
        Session.SetClassIf(handles, "collapsed", current == nil)
        if current == nil then reference = nil; handlePositions = {}; return end
        if not dirty and reference and reference.width == current.width and reference.height == current.height
            and reference.viewWidth == current.viewWidth and reference.viewHeight == current.viewHeight then
            layer.x, layer.y = current.x - reference.x, current.y - reference.y
            handles.x, handles.y = layer.x, layer.y
            return
        end
        dirty, reference = false, current
        layer.x, layer.y, handles.x, handles.y = 0, 0, 0, 0
        local selected, selectedRow = nil, nil
        for kind, entry in pairs(entries) do
            local row = Row(entry)
            local box = Geometry(entry)
            entry.box = box
            -- A collapsed ancestor prevents the native image loader from starting.
            Session.SetClassIf(entry.root, "hidden", box == nil)
            if box then
                OverlandMapDrawing.PlaceCentered(entry.root, current, OverlandMapGeometry.ImageToPanel(current, row.u, row.v))
                Style(entry.root, "scale", current.width / referenceWidth)
                if ctx.data.selectedAid == kind then selected, selectedRow = box, row end
            end
        end
        local editable = selected ~= nil and Model.IsDirector() and ctx.data.tool == "none"
        Session.SetClassIf(outline, "collapsed", not editable)
        handlePositions = {}
        local compass = editable and ctx.data.selectedAid == "compass" and not ctx.data.locked
        Session.SetClassIf(resize, "collapsed", not compass); Session.SetClassIf(rotate, "collapsed", not compass)
        if editable and selected ~= nil and selectedRow ~= nil then
            local box, row = selected, selectedRow
            local scale, handle = current.width / referenceWidth, C.labelHandleSize * Session.UIScale()
            local x, y = OverlandMapGeometry.ImageToPanel(current, row.u, row.v)
            local w, h = math.max(8, box.width * scale), math.max(8, box.height * scale)
            outline.selfStyle.width, outline.selfStyle.height, outline.selfStyle.rotate = w, h, -box.angle
            OverlandMapDrawing.PlaceCentered(outline, current, x, y)
            if compass then
                local a = math.rad(box.angle)
                local north = h / 2
                if box.text then
                    local nx, ny = math.sin(a), -math.cos(a)
                    north = math.max(north, (math.max(nx * box.text.x1, nx * box.text.x2)
                        + math.max(ny * box.text.y1, ny * box.text.y2)) * scale)
                end
                for _, panel in ipairs({ resize, rotate }) do panel.selfStyle.width, panel.selfStyle.height = handle, handle end
                handlePositions.resize = { x = x + w / 2 * math.cos(a) - h / 2 * math.sin(a), y = y + w / 2 * math.sin(a) + h / 2 * math.cos(a) }
                handlePositions.rotate = { x = x + (north + handle) * math.sin(a), y = y - (north + handle) * math.cos(a) }
                OverlandMapDrawing.PlaceCentered(resize, current, handlePositions.resize.x, handlePositions.resize.y)
                OverlandMapDrawing.PlaceCentered(rotate, current, handlePositions.rotate.x, handlePositions.rotate.y)
            end
        end
    end
    function api.HitTest(x, y)
        if layout == nil or not Model.IsDirector() then return nil end
        for _, kind in ipairs(kinds) do
            local entry = entries[kind]
            local box = entry and entry.box
            if box then
                local row, scale = Row(entry), layout.width / referenceWidth
                local cx, cy = OverlandMapGeometry.ImageToPanel(layout, row.u, row.v)
                local dx, dy = (x - cx) / scale, (y - cy) / scale
                if kind == "scaleBar" then
                    if A.Contains(box, dx, dy) then return kind end
                else
                    local angle = math.rad(box.angle)
                    local lx, ly = dx * math.cos(angle) + dy * math.sin(angle), -dx * math.sin(angle) + dy * math.cos(angle)
                    if (math.abs(lx) <= box.width / 2 and math.abs(ly) <= box.height / 2)
                        or (box.text and A.Contains(box.text, dx, dy)) then return kind end
                end
            end
        end
    end
    function api.HandleAt(x, y)
        if layout == nil or reference == nil or ctx.data.locked or ctx.data.tool ~= "none" or not Model.IsDirector() then return nil end
        local half = C.labelHandleSize * Session.UIScale() / 2
        for kind, position in pairs(handlePositions) do
            if math.abs(x - position.x - (layout.x - reference.x)) <= half
                and math.abs(y - position.y - (layout.y - reference.y)) <= half then return kind end
        end
    end
    function api.EditBounds(kind)
        local entry = entries[kind]
        if layout == nil or entry == nil or entry.box == nil then return nil end
        local row, box, scale = Row(entry), entry.box, layout.width / referenceWidth
        local x, y = OverlandMapGeometry.ImageToPanel(layout, row.u, row.v)
        local bounds = { x1 = x + box.x1 * scale, x2 = x + box.x2 * scale,
            y1 = y + box.y1 * scale, y2 = y + box.y2 * scale }
        if kind == ctx.data.selectedAid and reference then
            local size = C.labelHandleSize * Session.UIScale()
            for _, position in pairs(handlePositions) do
                Union(bounds, position.x + layout.x - reference.x, position.y + layout.y - reference.y, size, size)
            end
        end
        return bounds
    end
    function api.SetPreview(kind, changes) preview = kind and { kind = kind, changes = changes } or nil; dirty = true end
    function api.Metrics(width, height)
        if api.imageWidth ~= width or api.imageHeight ~= height then dirty = true end
        api.imageWidth, api.imageHeight = width, height
    end
    function api.Availability(kind)
        local entry = entries[kind]
        return entry and (kind == "compass" and entry.imageStatus or entry.reason) or nil
    end
    function api.Retry()
        local entry = entries.compass
        if entry and entry.row then entry.imageKey = nil; LoadCompass(entry, entry.row) end
    end
    function api.ImageDimensions(kind)
        local entry = entries[kind]
        local box = entry and entry.box
        if box then return (box.x2 - box.x1) / referenceWidth, (box.y2 - box.y1) / referenceWidth end
    end
    function api.Geometry(kind) return entries[kind] and entries[kind].box end
    function api.Destroy()
        layer:DestroySelf()
        handles:DestroySelf()
    end
    return api
end

function OverlandMapAidLayer.Styles()
    return {
        {
            selectors = { "overlandMapAidImage" },
            bgcolor = "white",
        },
        {
            selectors = { "overlandMapAidBacking" },
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = { "overlandMapAidSegment" },
            bgimage = true,
            borderWidth = 0.5,
            borderColor = "black",
        },
        {
            selectors = { "overlandMapAidSegment", "dark" },
            bgcolor = "black",
        },
        {
            selectors = { "overlandMapAidSegment", "light" },
            bgcolor = "white",
        },
        {
            selectors = { "overlandMapAidTick" },
            bgimage = true,
            bgcolor = "black",
            borderWidth = 0.5,
            borderColor = "white",
        },
    }
end
