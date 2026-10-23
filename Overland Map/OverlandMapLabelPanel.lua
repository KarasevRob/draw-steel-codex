local mod = dmhub.GetModLoading()

--- The editor previews through the label queue; rebinding never sends a change event.
--- @class OverlandMapLabelPanel: GameType
--- @field new fun(o?: table): OverlandMapLabelPanel
OverlandMapLabelPanel = RegisterGameType("OverlandMapLabelPanel")
local Labels, Session, Copy = OverlandMapLabels, OverlandMapControls, OverlandMapCopy
local C, Model = OverlandMapConstants, OverlandMapModel
local T = Copy.T

function OverlandMapLabelPanel.MenuEntries(ctx, id)
    local row = Labels.Get(id)
    if not Labels.CanEdit(row) then return {} end
    return {
        { text = T("label.edit"), click = function() if ctx.IsAlive() then ctx.SelectLabel(id, true) end end },
        { text = T("label.delete"), click = function()
            if ctx.IsAlive() and Labels.RequestDelete(id) then ctx.SelectLabel(nil) end
        end },
    }
end

--- @param ctx OverlandMapContext
--- @return Panel
function OverlandMapLabelPanel.Create(ctx)
    local panel
    local scroll
    local releaseSession
    local inputs, colors = {}, {}
    local binding, boundId, generation = false, nil, 0
    local unsubscribe = nil --- @type nil|fun()
    local invalid = {}
    local discards = 0
    local refreshScheduled = false
    -- Every keystroke changes the label's queue; refresh the window once per burst, not per key.
    local function QueueRefresh()
        if refreshScheduled then return end
        refreshScheduled = true
        OverlandMapLifetime.Schedule(C.afterLayoutDelay, function()
            refreshScheduled = false
            if not mod.unloaded and ctx.IsAlive() then ctx.RefreshAll() end
        end)
    end
    local function Current() return Labels.Snapshot(ctx.data.selectedLabelId) end
    local function Changed(key, value, flush)
        if binding or mod.unloaded or boundId ~= ctx.data.selectedLabelId or not Labels.CanEdit(Current()) then return end
        local ok = Labels.Stage(boundId, { [key] = value })
        invalid[key] = not ok or nil
        if ok and flush then Labels.Flush(boundId) end
        if not ok then ctx.RefreshAll() end
    end
    local function Field(key, child)
        return gui.Panel { classes = { "overlandMapLabelField" },
            Session.Label({ "overlandMapFormLabel", "sizeXs" }, T("label." .. key)), child }
    end
    local textInput = Session.TextArea(C.labelTextLimit, {
        id = "overland-map-label-text", minHeight = 72, maxHeight = 170,
        edit = function(e) Changed("text", e.text, false) end,
        change = function(e) Changed("text", e.text, true) end,
    })
    inputs.text = textInput
    local fontOptions = {}
    for _, font in ipairs(gui.availableFonts or {}) do fontOptions[#fontOptions + 1] = { id = font, text = font } end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)
    local font = gui.Dropdown {
        id = "overland-map-label-font", classes = { "overlandMapLabelInput" }, options = fontOptions,
        width = "100%", minWidth = 0, borderBox = true,
        change = function(e) Changed("font", e.idChosen, false) end,
    }
    local bold = gui.Check { classes = { "overlandMapCheck", "sizeS" }, text = T("label.bold"), width = "50%", minWidth = 0, borderBox = true,
        change = function(e) Changed("bold", e.value == true, false) end }
    local italics = gui.Check { classes = { "overlandMapCheck", "sizeS" }, text = T("label.italics"), width = "50%", minWidth = 0, borderBox = true,
        change = function(e) Changed("italics", e.value == true, false) end }
    local alignment = Session.Segments({ "left", "center", "right" }, "label.", function(value) Changed("alignment", value, false) end)
    local function Number(key, multiplier, low, high)
        local function Edit(e, flush)
            local n = tonumber(e.text)
            local valid = Model.IsFinite(n) and n >= low and n <= high
            invalid[key] = not valid or nil
            e:SetClass("invalid", not valid)
            if valid then Changed(key, n / multiplier, flush) else ctx.RefreshAll() end
        end
        local input = gui.Input {
            id = "overland-map-label-" .. key, classes = { "input", "bordered", "overlandMapLabelInput" }, characterLimit = 16,
            width = "100%", borderBox = true, minWidth = 0,
            edit = function(e) if not binding then Edit(e, false) end end,
            change = function(e) if not binding then Edit(e, true) end end,
        }
        inputs[key] = input
        return Field(key, input)
    end
    local size = Number("size", 100, 0.1, 25)
    local angle = Number("angle", 1, -180, 180)
    local spacing = Number("spacing", 100, 0, 100)

    local function ColorField(key)
        local hex = gui.Input {
            classes = { "input", "bordered", "overlandMapLabelInput" }, width = "100%-44", characterLimit = 9,
            borderBox = true, minWidth = 0,
            change = function(e)
                if binding then return end
                local valid = OverlandMapTextAppearance.ValidColor(e.text)
                invalid[key] = not valid or nil
                e:SetClass("invalid", not valid)
                if valid then Changed(key, e.text, true) else ctx.RefreshAll() end
            end,
        }
        local picker = gui.ColorPicker {
            id = "overland-map-label-" .. key .. "-picker", width = 32, height = 32, lmargin = 8, value = "#ffffffff", hasAlpha = true,
            change = function(e)
                if e.data.openId ~= boundId or e.data.generation ~= generation then return end
                local value = e.value
                Changed(key, type(value) == "string" and value or value.tostring, false)
            end,
        }
        Session.ScaleColorPopup(ctx, picker, function(e)
            if not Labels.CanEdit(Current()) then return false end
            e.data.openId, e.data.generation = boundId, generation
            return true
        end)
        colors[key] = picker
        inputs[key] = hex
        return Field(key, gui.Panel { classes = { "overlandMapLabelColor" }, hex, picker })
    end
    local color = ColorField("color")
    local backgroundColor = ColorField("backgroundColor")
    local appearance = Session.AppearanceEditor(ctx, false, {
        Active = function(id) return ctx.data.panelMode == "labelEdit" and id == ctx.data.selectedLabelId and Labels.CanEdit(Current()) end,
        Format = function() return Labels.Format(Current()) end,
        Commit = function(changes) return Labels.Stage(boundId, changes) end,
        -- Staged changes show on the map at once and save after the autosave delay.
        Preview = function(changes) Labels.Stage(boundId, changes) end,
    })
    local visibility = Session.Segments({ "hidden", "revealed" }, "edit.visibility.", function(value)
        Changed("visibility", value, true)
    end)
    local visibleText = Session.Label({ "overlandMapBody", "sizeS" }, T("edit.visibility.revealed"))
    local status = Session.Label({ "overlandMapHint", "sizeXs" })
    local retry = Session.Button(T("toast.retry"), function() if boundId then Labels.Retry(boundId) end end)
    local title = Session.Label({ "overlandMapSideTitle", "sizeL" }, T("label.title"))
    local header = gui.Panel { classes = { "overlandMapSideHeader" }, title,
        Session.IconButton("overland-map-label-close", C.iconClose, T("panel.close"), function() ctx.SelectLabel(nil) end) }
    local body = gui.Panel { classes = { "overlandMapSideBody" },
        header,
        Session.Label({ "overlandMapFormLabel", "sizeXs" }, T("edit.visibility")), visibility, visibleText,
        Field("text", textInput), Field("font", font),
        gui.Panel { width = "100%", height = "auto", flow = "horizontal", bold, italics },
        Field("alignment", alignment), size, angle, spacing, color, appearance, backgroundColor,
    }
    local footer = gui.Panel {
        id = "overland-map-label-footer", classes = { "overlandMapSideBody" },
        width = "100%", height = "auto", hpad = 14, vpad = 6, borderBox = true,
        gui.Panel { classes = { "overlandMapSideRow" }, status, retry },
        gui.Panel { classes = { "overlandMapButtonRow" },
            Session.Button(T("label.delete"), function()
                if boundId and Labels.RequestDelete(boundId) then ctx.SelectLabel(nil) end
            end),
            Session.Button(T("edit.done"), function() ctx.SelectLabel(nil) end),
        },
    }

    local function Bind()
        local row = Current()
        local shown = ctx.data.panelMode == "labelEdit" and Labels.CanEdit(row)
        panel:SetClass("collapsed", not shown)
        if not shown or row == nil then
            if unsubscribe then unsubscribe(); unsubscribe = nil end
            binding = true
            generation = generation + 1
            for _, picker in pairs(colors) do picker.data.openId = nil; picker.popup = nil end
            boundId = nil
            appearance.data.suspend()
            binding = false
            return
        end
        binding = true
        local changedId = boundId ~= row.id
        if changedId then
            if unsubscribe then unsubscribe(); unsubscribe = nil end
            invalid = {}
            generation = generation + 1
            for _, picker in pairs(colors) do picker.data.openId = nil; picker.popup = nil end
            scroll.vscrollPosition = 1
            local id = row.id
            OverlandMapLifetime.Schedule(C.afterLayoutDelay, function()
                if ctx.IsAlive() and scroll.valid and boundId == id then scroll.vscrollPosition = 1 end
            end)
        end
        boundId = row.id
        -- Unsent edits were dropped (Undo, lost permission): even a focused field shows the label again.
        local dropped = Labels.Discards(boundId) ~= discards
        discards = Labels.Discards(boundId)
        if not unsubscribe then unsubscribe = Labels.Observe(boundId, QueueRefresh) end
        local width = C.sidePanelWidth * Session.UIScale()
        if ctx.root.renderedWidth < C.narrowWidth then width = ctx.root.renderedWidth end
        if panel.data.width ~= width then panel.data.width = width; panel.selfStyle.width = width end
        local format = Labels.Format(row)
        local values = { text = row.text, size = string.format("%.3g", format.size * 100),
            angle = string.format("%.3g", row.angle), spacing = string.format("%.3g", format.spacing * 100),
            color = format.color, backgroundColor = format.backgroundColor }
        for key, input in pairs(inputs) do
            if changedId or dropped or (not input.hasFocus and not invalid[key]) then
                if input.text ~= values[key] then input.text = values[key] end
                input:SetClass("invalid", false)
            end
        end
        font.idChosen = Labels.DisplayFont(format.font)
        bold.value, italics.value = format.bold, format.italics
        alignment.data.select(format.alignment)
        appearance.data.bind(boundId, format)
        visibility.data.select(row.visibility)
        visibility:SetClass("collapsed", not Model.IsDirector())
        visibleText:SetClass("collapsed", Model.IsDirector())
        backgroundColor:SetClass("collapsed", format.background ~= "plate")
        for key, picker in pairs(colors) do picker.value = format[key] end
        local state = Labels.Status(boundId)
        if next(invalid) ~= nil or appearance.data.invalid() then state = "invalid" end
        local copyId = state == "saved" and "edit.saved" or (state == "saving" or state == "pending") and "edit.saving" or "edit.notSaved"
        Session.SetText(status, T(copyId))
        Session.SetText(title, T(Labels.Get(boundId) == nil and "label.new" or "label.title"))
        retry:SetClass("collapsed", state ~= "failed")
        binding = false
        if changedId then
            local id = boundId
            Session.FocusSoon(textInput, function() return ctx.IsAlive() and ctx.data.selectedLabelId == id and ctx.data.panelMode == "labelEdit" end)
        end
    end
    scroll = gui.Panel {
        classes = { "overlandMapSideScroll" }, vscroll = true, height = "100% available",
        width = "100%", rpad = 14, borderBox = true, body,
    }
    panel = gui.Panel {
        id = "overland-map-label-panel", classes = { "overlandMapSide", "collapsed" }, floating = true,
        width = C.sidePanelWidth, flow = "vertical", popupsInheritStyles = true, data = {},
        bind = function() if not mod.unloaded then Bind() end end,
        flush = function() if boundId then Labels.Flush(boundId) end end,
        destroy = function()
            if releaseSession then releaseSession() end
            if boundId then Labels.Leave(boundId) end
            if unsubscribe then unsubscribe(); unsubscribe = nil end
        end,
        scroll,
        footer,
    }
    releaseSession = OverlandMapSession.Register {
        scope = ctx, valid = function() return panel.valid end,
        flush = function() if boundId then Labels.Flush(boundId) end end,
        cancel = function(reason, id)
            if boundId and (id == nil or id == boundId)
                and (reason ~= "permission" or not Labels.CanEdit(Labels.Snapshot(boundId))) then Labels.CancelPending(boundId) end
        end,
    }
    return panel
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function OverlandMapLabelPanel.Styles()
    return {
        {
            selectors = { "overlandMapLabelField" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            bmargin = 8,
        },
        {
            selectors = { "overlandMapLabelInput" },
            width = "100%",
            height = "auto",
            minHeight = 28,
        },
        {
            selectors = { "overlandMapLabelInput", "invalid" },
            borderColor = "@danger",
        },
        {
            selectors = { "overlandMapLabelColor" },
            width = "100%",
            height = "auto",
            minHeight = 32,
            flow = "horizontal",
        },
        {
            selectors = { "overlandMapLabelKind" },
            color = "@fgMuted",
            height = "auto",
            width = "100%",
        },
    }
end
