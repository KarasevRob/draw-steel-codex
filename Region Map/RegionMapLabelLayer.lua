local mod = dmhub.GetModLoading()

--- Lettering uses leaf transforms while zooming; panning slides the whole layer without style writes.
--- @class RegionMapLabelLayer: GameType
--- @field new fun(o?: table): RegionMapLabelLayer
RegionMapLabelLayer = RegisterGameType("RegionMapLabelLayer")
local Labels, Tools, Session = RegionMapLabels, RegionMapCanvasTools, RegionMapSession
local C, Copy = RegionMapConstants, RegionMapCopy
local Appearance = RegionMapTextAppearance
local baseFont = 64

--- @param color string
--- @return string
function RegionMapLabelLayer.Contrast(color)
    local function Channel(at)
        local n = (tonumber(color:sub(at, at + 1), 16) or 255) / 255
        if n <= 0.04045 then return n / 12.92 end
        return ((n + 0.055) / 1.055) ^ 2.4
    end
    local luminance = 0.2126 * Channel(2) + 0.7152 * Channel(4) + 0.0722 * Channel(6)
    return luminance > 0.179 and "#000000ff" or "#ffffffff"
end

--- @param ctx RegionMapContext
function RegionMapLabelLayer.Create(ctx)
    local entries, order = {}, {}
    local layout, reference, signature = nil, nil, nil
    local dirty = true
    local measureRefreshPending = false
    local previewId, preview = nil, nil
    local layer = gui.Panel { classes = { "regionMapOverlay" }, floating = true, interactable = false }
    local outline = gui.Panel { classes = { "regionMapLabelOutline", "collapsed" }, floating = true, interactable = false }
    local resize = gui.Panel { classes = { "regionMapLabelHandle", "collapsed" }, floating = true, interactable = false }
    local rotate = gui.Panel { classes = { "regionMapLabelHandle", "collapsed" }, floating = true, interactable = false,
        gui.Label { classes = { "label", "sizeS" }, text = "R", interactable = false } }
    local handles = gui.Panel { classes = { "regionMapOverlay" }, floating = true, interactable = false, outline, resize, rotate }
    local api = { layer = layer, handles = handles, metrics = { builds = 0, styleWrites = 0, layouts = 0 } }

    local function Style(element, property, value)
        if element.data.written[property] == value then return end
        element.data.written[property] = value
        element.selfStyle[property] = value
        api.metrics.styleWrites = api.metrics.styleWrites + 1
    end

    local function Measure(entry)
        if mod.unloaded or not entry.panel.valid then return end
        local w, h = entry.panel.renderedWidth, entry.panel.renderedHeight
        if w > 0 and h > 0 and (not entry.measured or w ~= entry.width or h ~= entry.height) then
            entry.width, entry.height, entry.measured = w, h, true
            dirty = true
            if not measureRefreshPending then
                measureRefreshPending = true
                dmhub.Schedule(C.afterLayoutDelay, function()
                    measureRefreshPending = false
                    if not mod.unloaded and layer.valid and layout ~= nil then api.Layout(layout) end
                end)
            end
        end
    end

    local function NewEntry(id)
        local entry = { id = id, measured = false, width = 0, height = 0 }
        entry.image = Appearance.CreateImage(function()
            if entry.panel and entry.panel.valid then
                dirty = true
                signature = nil
                entry.look = nil
                dmhub.Schedule(C.afterLayoutDelay, function()
                    if not mod.unloaded and entry.panel.valid then ctx.RefreshAll() end
                end)
            end
        end)
        entry.text = gui.Label { width = "auto", height = "auto", textWrap = false, text = "", interactable = false,
            data = { written = {} } }
        entry.panel = gui.Panel { floating = true, halign = "center", valign = "center",
            bgimage = "panels/square.png",
            classes = { "regionMapLettering" }, width = "auto", height = "auto", borderBox = true,
            interactable = false, data = { written = {} },
            rendered = function() Measure(entry) end,
            entry.image.panel, entry.text }
        layer:AddChild(entry.panel)
        entry.eye = gui.Panel { classes = { "regionMapLabelEye", "collapsed" }, floating = true, interactable = false,
            gui.Panel { classes = { "regionMapIconGlyph" }, bgimage = C.iconEyeSlash, interactable = false } }
        layer:AddChild(entry.eye)
        api.metrics.builds = api.metrics.builds + 1
        return entry
    end

    local function BindEntry(entry, row)
        local format = Labels.Format(row)
        local text = Copy.Literal(row.text ~= "" and row.text or Copy.T("label.new"))
        local display = string.format("<cspace=%.4fem>%s</cspace>", format.spacing, text)
        local font = Labels.DisplayFont(format.font)
        local key = table.concat({ display, font, tostring(format.bold), tostring(format.italics), format.alignment,
            format.color, format.background, format.backgroundColor, tostring(Session.UIScale()) }, "|")
        for field in pairs(Appearance.defaults) do key = key .. "|" .. field .. "=" .. tostring(format[field]) end
        entry.row = DeepCopy(row)
        for field, value in pairs(format) do entry.row[field] = value end
        entry.size, entry.angle = format.size, row.angle or 0
        if entry.look ~= key then
            entry.look, entry.measured = key, false
            local material = Appearance.MaterialKey(format, 0, RegionMapLabelLayer.Contrast(format.color))
            if entry.material and entry.material ~= material then
                entry.text = gui.Label { width = "auto", height = "auto", textWrap = false, text = "", interactable = false,
                    data = { written = {} } }
                entry.panel.children = { entry.image.panel, entry.text }
            end
            entry.material = material
            entry.text.text = display
            Style(entry.text, "fontFace", font)
            Style(entry.text, "fontSize", baseFont / Session.UIScale())
            Style(entry.text, "bold", format.bold)
            Style(entry.text, "italics", format.italics)
            Style(entry.text, "textAlignment", format.alignment)
            Style(entry.text, "color", format.color)
            local outlineWidth, outlineColor = Appearance.Outline(format, 0, RegionMapLabelLayer.Contrast(format.color))
            Style(entry.text, "textOutlineWidth", outlineWidth)
            Style(entry.text, "textOutlineColor", outlineColor)
            -- The backing contrasts with the text, never with moving map pixels.
            local backing = RegionMapLabelLayer.Contrast(format.color)
            local fill, hpad, vpad, radius = "clear", 0, 0, 0
            if format.background == "auto" then
                fill, hpad, vpad, radius = backing, baseFont * 0.04, baseFont * 0.02, baseFont * 0.02
            elseif format.background == "plate" then
                fill, hpad, vpad, radius = format.backgroundColor, baseFont * 0.2, baseFont * 0.12, baseFont * 0.1
            end
            entry.image.Bind(format)
            if format.background == "image" and entry.image.status ~= "ready" then fill = backing end
            Style(entry.panel, "bgcolor", fill)
            Style(entry.panel, "hpad", hpad)
            Style(entry.panel, "vpad", vpad)
            Style(entry.panel, "cornerRadius", radius)
            local captured = key
            dmhub.Schedule(C.afterLayoutDelay, function()
                if not mod.unloaded and entry.look == captured then Measure(entry) end
            end)
        end
        Session.SetClassIf(entry.panel, "hiddenForPlayers", row.visibility == "hidden")
        Session.SetClassIf(entry.eye, "collapsed", row.visibility ~= "hidden")
    end

    function api.Bind(mapId)
        local selected = ctx.data.selectedLabelId
        local selectedRow = selected and Labels.Snapshot(selected) or nil
        local key = table.concat({ tostring(mapId), tostring(RegionMapModel.Revision()), tostring(selected),
            tostring(RegionMapRecords.Field(selectedRow, "_tmp_labelVersion", 0)), tostring(Session.ShowLabels()),
            tostring(RegionMapModel.IsDirector()), tostring(ctx.data.locked), tostring(Session.UIScale()) }, ":")
        if key == signature then return end
        signature, dirty = key, true
        local rows = Session.ShowLabels() and Labels.ForMap(mapId) or {}
        local wanted = {}
        order = {}
        for _, row in ipairs(rows) do wanted[row.id] = row end
        if selected ~= nil and selectedRow ~= nil and selectedRow.mapId == mapId then wanted[selected] = selectedRow end
        for id, entry in pairs(entries) do
            if wanted[id] == nil then entry.panel:DestroySelf(); entry.eye:DestroySelf(); entries[id] = nil end
        end
        for id, row in pairs(wanted) do
            local entry = entries[id] or NewEntry(id)
            entries[id] = entry
            BindEntry(entry, row)
            order[#order + 1] = id
        end
        table.sort(order)
        local children = {}
        for _, id in ipairs(order) do
            children[#children + 1] = entries[id].panel
            children[#children + 1] = entries[id].eye
        end
        layer.children = children
    end

    local function Row(entry)
        if previewId == entry.id and preview ~= nil then
            local row = DeepCopy(entry.row)
            for k, v in pairs(preview) do row[k] = v end
            return row
        end
        return entry.row
    end

    local function Box(entry)
        if layout == nil or entry == nil or not entry.measured then return nil end
        local row = Row(entry)
        local x, y = Tools.ImageToPanel(layout, row.u, row.v)
        local scale = row.size * layout.width / baseFont
        local geometry
        if row.background == "image" then
            geometry = Appearance.Geometry(row, entry.width, entry.height, baseFont / Session.UIScale(), baseFont / row.size)
        else
            geometry = { x1 = -entry.width / 2, x2 = entry.width / 2, y1 = -entry.height / 2, y2 = entry.height / 2 }
            geometry.text = DeepCopy(geometry)
        end
        local cx, cy = (geometry.x1 + geometry.x2) * scale / 2, (geometry.y1 + geometry.y2) * scale / 2
        local a = math.rad(row.angle)
        return { x = x + cx * math.cos(a) - cy * math.sin(a), y = y + cx * math.sin(a) + cy * math.cos(a),
            originX = x, originY = y, geometry = geometry, scale = scale,
            width = (geometry.x2 - geometry.x1) * scale, height = (geometry.y2 - geometry.y1) * scale,
            angle = row.angle, id = row.id }
    end

    local function Offset(box, x, y)
        local angle = math.rad(box.angle)
        return box.x + x * math.cos(angle) - y * math.sin(angle), box.y + x * math.sin(angle) + y * math.cos(angle)
    end

    function api.Layout(current)
        layout = current
        Session.SetClassIf(layer, "collapsed", layout == nil)
        Session.SetClassIf(handles, "collapsed", layout == nil)
        if layout == nil then reference = nil; return end
        if not dirty and reference and reference.width == layout.width and reference.height == layout.height
            and reference.viewWidth == layout.viewWidth and reference.viewHeight == layout.viewHeight then
            layer.x, layer.y = layout.x - reference.x, layout.y - reference.y
            handles.x, handles.y = layer.x, layer.y
            return
        end
        api.metrics.layouts = api.metrics.layouts + 1
        dirty, reference = false, current
        layer.x, layer.y, handles.x, handles.y = 0, 0, 0, 0
        for _, id in ipairs(order) do
            local entry = entries[id]
            local row = Row(entry)
            Tools.PlaceCentered(entry.panel, layout, Tools.ImageToPanel(layout, row.u, row.v))
            Style(entry.panel, "scale", row.size * layout.width / baseFont)
            Style(entry.panel, "rotate", -row.angle)
            local box = Box(entry)
            if box then
                if box.geometry.image then entry.image.Layout(box.geometry.image) end
                Tools.PlaceCentered(entry.eye, layout, Offset(box, box.width / 2 + 10, -box.height / 2))
            end
        end
        local entry = entries[ctx.data.selectedLabelId]
        local box = Box(entry)
        Session.SetClassIf(outline, "collapsed", box == nil)
        local editable = box ~= nil and not ctx.data.locked and ctx.data.tool == "none" and Labels.CanEdit(entry.row)
        Session.SetClassIf(resize, "collapsed", not editable)
        Session.SetClassIf(rotate, "collapsed", not editable)
        if box then
            outline.selfStyle.width, outline.selfStyle.height = math.max(8, box.width), math.max(8, box.height)
            outline.selfStyle.rotate = -box.angle
            Tools.PlaceCentered(outline, layout, box.x, box.y)
            if editable then
                local size = C.labelHandleSize * Session.UIScale()
                resize.selfStyle.width, resize.selfStyle.height = size, size
                rotate.selfStyle.width, rotate.selfStyle.height = size, size
                local textBox = { x = box.originX, y = box.originY, angle = box.angle }
                Tools.PlaceCentered(resize, layout, Offset(textBox, entry.width * box.scale / 2, entry.height * box.scale / 2))
                Tools.PlaceCentered(rotate, layout, Offset(box, 0, -box.height / 2 - size))
            end
        end
    end

    function api.Hit(x, y)
        for i = #order, 1, -1 do
            local entry = entries[order[i]]
            local box = Box(entry)
            if box then
                local a, dx, dy = math.rad(box.angle), x - box.originX, y - box.originY
                local localX, localY = (dx * math.cos(a) + dy * math.sin(a)) / box.scale, (-dx * math.sin(a) + dy * math.cos(a)) / box.scale
                local imageVisible = entry.image.status == "ready" and entry.row.backgroundOpacity > 0
                if Appearance.Contains(box.geometry.text, localX, localY)
                    or (box.geometry.image and imageVisible and Appearance.Contains(box.geometry.image, localX, localY)) then
                    return entry.id
                end
            end
        end
        return nil
    end

    function api.HandleAt(x, y)
        local entry = entries[ctx.data.selectedLabelId]
        if ctx.data.locked or ctx.data.tool ~= "none" or entry == nil or not Labels.CanEdit(entry.row) then return nil end
        local box = Box(entry)
        if box == nil then return nil end
        local size = C.labelHandleSize * Session.UIScale()
        for _, kind in ipairs({ "resize", "rotate" }) do
            local hx, hy
            if kind == "resize" then hx, hy = Offset({ x = box.originX, y = box.originY, angle = box.angle }, entry.width * box.scale / 2, entry.height * box.scale / 2)
            else hx, hy = Offset(box, 0, -box.height / 2 - size) end
            if math.abs(x - hx) <= size / 2 and math.abs(y - hy) <= size / 2 then return kind, entry.id end
        end
        return nil
    end

    function api.Preview(id, values)
        previewId, preview, dirty = id, values, true
    end

    function api.Bounds(id) return Box(entries[id]) end
    function api.ImageDimensions(id)
        local entry = entries[id]
        local box = Box(entry)
        if box == nil or layout == nil then return nil end
        local geometry = box.geometry.image or box.geometry.text
        return (geometry.x2 - geometry.x1) * box.scale / layout.width, (geometry.y2 - geometry.y1) * box.scale / layout.width
    end
    return api
end
