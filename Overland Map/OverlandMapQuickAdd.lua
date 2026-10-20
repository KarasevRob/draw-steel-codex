local mod = dmhub.GetModLoading()

--- @class OverlandMapQuickAdd: GameType
--- @field new fun(o?: table): OverlandMapQuickAdd
OverlandMapQuickAdd = RegisterGameType("OverlandMapQuickAdd")
local C, Model, Labels = OverlandMapConstants, OverlandMapModel, OverlandMapLabels
local Controls, T = OverlandMapControls, OverlandMapCopy.T

--- @param ctx OverlandMapContext
--- @return Panel
function OverlandMapQuickAdd.Create(ctx)
    local panel, input
    local bound, layout, unsubscribe, releaseSession
    local binding, wantsFocus, refreshScheduled = false, false, false
    local function Refresh()
        if refreshScheduled then return end
        refreshScheduled = true
        OverlandMapLifetime.Schedule(C.afterLayoutDelay, function()
            refreshScheduled = false
            if not mod.unloaded and ctx.IsAlive() then ctx.RefreshAll() end
        end)
    end
    local editor = OverlandMapEditors.Create("location", Refresh)
    local function Current()
        if bound == nil then return nil end
        if bound.kind == "label" then return Labels.Snapshot(bound.id) end
        return Model.GetLocation(bound.id)
    end
    local function Editable()
        if bound == nil or bound ~= ctx.data.quick then return false end
        local row = Current()
        if bound.kind == "label" then return Labels.CanEdit(row) end
        return Model.CanEdit(row)
    end
    local function Stage(element)
        if binding or mod.unloaded or not Editable() then return end
        if bound.kind == "label" then Labels.Stage(bound.id, { text = element.text })
        else editor.Stage(bound.id, "name", element.text) end
    end
    local function Flush()
        editor.Flush()
        if bound ~= nil and bound.kind == "label" then Labels.Flush(bound.id) end
    end
    local function Place()
        local row = Current()
        local visible = false
        local x, y
        if bound ~= nil and bound == ctx.data.quick and row ~= nil and layout ~= nil then
            x, y = OverlandMapGeometry.ImageToPanel(layout, row.u, row.v)
            visible = x >= 0 and x <= layout.viewWidth and y >= 0 and y <= layout.viewHeight
        end
        panel:SetClass("collapsed", not visible)
        if not visible then return end
        local scale = Controls.UIScale()
        local gap = 12 * scale
        local width = math.min(260 * scale, math.max(1, layout.viewWidth - gap * 2))
        if panel.selfStyle.width ~= width then panel.selfStyle.width = width end
        local height = panel.renderedHeight or (80 * scale)
        local left = x + gap
        if left + width > layout.viewWidth - gap then left = x - gap - width end
        left = Model.Clamp(left, gap, math.max(gap, layout.viewWidth - gap - width))
        local top = Model.Clamp(y - height * 0.5, C.belowChromeBar * scale + gap,
            math.max(C.belowChromeBar * scale + gap, layout.viewHeight - gap - height))
        OverlandMapDrawing.PlaceCentered(panel, layout, left + width * 0.5, top + height * 0.5)
        if wantsFocus then
            wantsFocus = false
            local wanted = bound
            Controls.FocusSoon(input, function()
                return ctx.data.quick == wanted and panel.valid and not panel:HasClass("collapsed")
            end)
        end
    end
    local function Bind()
        local quick = ctx.data.quick
        if bound ~= quick then
            if unsubscribe ~= nil then unsubscribe(); unsubscribe = nil end
            if bound ~= nil and bound.kind == "label"
                and not (ctx.data.selectedLabelId == bound.id and ctx.data.panelMode == "labelEdit") then
                Labels.Leave(bound.id)
            end
            bound, wantsFocus = quick, quick ~= nil
            editor.Bind(quick ~= nil and quick.kind == "location" and quick.id or nil)
            local row = Current()
            if row ~= nil and quick ~= nil then
                binding = true
                if quick.kind == "label" then
                    input.text = row.text or ""
                    input.placeholderText = T("quick.label.placeholder")
                    input.characterLimit = C.labelTextLimit
                    unsubscribe = Labels.Observe(quick.id, Refresh)
                else
                    local pending = editor.Pending(quick.id)
                    input.text = pending and pending.name or row.name or ""
                    input.placeholderText = T("quick.name.placeholder")
                    input.characterLimit = C.textLimit
                end
                binding = false
            end
        end
        Place()
    end
    input = gui.Input {
        id = "overland-map-quick-input", classes = { "input", "bordered", "sizeS" },
        width = "100%", minWidth = 0, height = "auto", minHeight = 28, borderBox = true,
        multiline = false, lineType = "SingleLine", editlag = 0, selectAllOnFocus = true,
        restoreOriginalTextOnEscape = false,
        edit = Stage, change = Stage,
        submit = function(element)
            if not Editable() then return end
            Stage(element)
            ctx.CloseQuickAdd()
        end,
    }
    panel = gui.Panel {
        id = "overland-map-quick", classes = { "overlandMapQuick", "collapsed" },
        width = 260, height = "auto", flow = "vertical", halign = "center", valign = "center",
        floating = true, swallowPress = true, pad = 10, borderBox = true,
        bind = Bind,
        layout = function(_, nextLayout) layout = nextLayout; Place() end,
        rendered = Place,
        destroy = function()
            if releaseSession ~= nil then releaseSession() end
            if unsubscribe ~= nil then unsubscribe() end
            editor.Destroy()
            if bound ~= nil and bound.kind == "label" then Labels.Leave(bound.id) end
        end,
        input,
        gui.Label {
            id = "overland-map-quick-more", classes = { "overlandMapLink", "sizeS" },
            width = "auto", height = "auto", tmargin = 6, text = T("quick.more"),
            click = function()
                if not Editable() then return end
                if bound.kind == "label" then ctx.SelectLabel(bound.id, true)
                else ctx.data.focusName = true; ctx.Select(bound.id, "edit") end
            end,
        },
    }
    releaseSession = OverlandMapSession.Register {
        scope = ctx, valid = function() return panel.valid and ctx.IsAlive() end, flush = Flush,
        cancel = function(reason, mapId)
            local row = Current()
            if mapId ~= nil and (row == nil or (bound.kind == "label" and row.mapId or row.parentId) ~= mapId) then return end
            editor.Cancel(nil, reason == "permission")
            if bound ~= nil and bound.kind == "label" and (reason ~= "permission" or not Labels.CanEdit(row)) then
                Labels.CancelPending(bound.id)
            end
            if bound ~= nil and (reason ~= "permission" or not Editable()) then
                row = Current()
                if row ~= nil then
                    binding = true
                    input.text = bound.kind == "label" and row.text or row.name
                    binding = false
                end
            end
        end,
    }
    return panel
end

function OverlandMapQuickAdd.Styles()
    return { OverlandMapStyles.Chrome("overlandMapQuick", {}) }
end
