local mod = dmhub.GetModLoading()

--- Search, Settings and the Director's Map aids editor share the toolbar popover host.
--- The shell closes them with Esc or any press on the map canvas.
---
--- Events on the returned panel:
---   bind()   redraw for ctx.data.popover and the current map
--- @class OverlandMapPopovers: GameType
--- @field new fun(o?: table): OverlandMapPopovers
OverlandMapPopovers = RegisterGameType("OverlandMapPopovers")
local C = OverlandMapConstants
local Model = OverlandMapModel
local Session = OverlandMapControls
local Copy = OverlandMapCopy

local T = Copy.T
local SetText = Session.SetText
local Label, Button, Segments = Session.Label, Session.Button, Session.Segments

-- A positive number typed by the user, or nil. Accepts a decimal comma.
local function ParsePositive(text)
    local value = tonumber((tostring(text or ""):gsub(",", ".")))
    if Model.IsFinite(value) and value > 0 then return value end
    return nil
end

-- Search ------------------------------------------------------------------------------------------

local function BuildSearch(ctx)
    local results = gui.Panel { classes = { "overlandMapPopoverList" } }
    local none = Label({ "overlandMapHint", "collapsed", "sizeXs" })
    local found, selected, lastQuery = {}, 1, nil
    local searchKey = nil

    -- The ancestors of a result (the levels the viewer can see), with crumb icons between.
    local function PathRow(location, includeSelf)
        local parts = {} --- @type Panel[]
        local path = OverlandMapReaders.Breadcrumbs(location.id)
        for i = 1, #path - (includeSelf and 0 or 1) do
            if Model.CanOpenMap(path[i]) then
                if #parts > 0 then
                    parts[#parts + 1] = gui.Panel { classes = { "overlandMapCrumbSep", "small" }, bgimage = C.iconCrumb, interactable = false }
                end
                parts[#parts + 1] = Label({ "overlandMapResultPath", "sizeXs" }, Copy.Literal(Model.DisplayName(path[i])))
            end
        end
        return gui.Panel { classes = { "overlandMapResultPathRow" }, interactable = false, children = parts }
    end

    local function Open(result, edit)
        if result == nil then return end
        ctx.SetPopover(nil)
        if result.kind == "label" then ctx.FocusLabel(result.id, edit) else ctx.FocusLocation(result.id) end
    end

    local input
    local function MarkSelection()
        for i, row in ipairs(results.children) do row:SetClass("keyboardSelected", i == selected) end
    end
    local function Run(query)
        local key = table.concat({ query, tostring(Model.Revision()), tostring(Model.IsDirector()),
            tostring(Model.ViewingAsPlayer()), tostring(OverlandMapLabels.PlayersCanManage()) }, "|")
        -- Defocusing an unchanged input must not destroy the result being clicked.
        if key == searchKey then return end
        searchKey = key
        if lastQuery ~= query then selected = 1; lastQuery = query end
        found = OverlandMapReaders.Search(query, C.searchResultLimit)
        selected = math.max(1, math.min(selected, #found))
        local rows = {} --- @type Panel[]
        for _, result in ipairs(found) do
            local children = {
                Label({ "overlandMapLabelKind", "sizeXs" }, T(result.kind == "label" and "label.title" or "label.location")),
                Label({ "overlandMapRowName", "sizeS" }, Copy.Literal(result.name)),
            }
            local location = result.kind == "label" and Model.GetLocation(result.row.mapId) or result.row
            if location ~= nil then children[#children + 1] = PathRow(location, result.kind == "label") end
            if result.kind == "label" and OverlandMapLabels.CanEdit(result.row) then
                children[#children + 1] = Button(T("label.edit"), function() Open(result, true) end)
            end
            rows[#rows + 1] = gui.Panel {
                classes = { "overlandMapResult" },
                click = function() Open(result, false) end,
                children = children,
            }
        end
        results.children = rows
        MarkSelection()
        local trimmed = Model.TrimSingleLine(query)
        none:SetClass("collapsed", #found > 0 or trimmed == "")
        SetText(none, T("label.searchNone", { query = trimmed }))
    end

    input = gui.SearchInput {
        classes = { "overlandMapPopoverInput" },
        placeholderText = T("label.search"), editlag = 0.15,
        edit = function(element) Run(element.text) end,
        change = function(element) Run(element.text) end,
        submit = function(element)
            if ctx.data.popover ~= "search" or not element.hasFocus then return end
            Run(element.text)
            local edit = dmhub.KeyPressed("LeftControl") or dmhub.KeyPressed("RightControl")
            Open(found[selected], edit)
        end,
        thinkTime = 0, data = { keys = {} },
        focus = function(element)
            element.data.keys = { UpArrow = dmhub.KeyPressed("UpArrow"), DownArrow = dmhub.KeyPressed("DownArrow") }
            element.thinkTime = C.canvasThinkActive
        end,
        defocus = function(element) element.thinkTime = 0; element.data.keys = {} end,
        think = function(element)
            if ctx.data.popover ~= "search" or not element.hasFocus then element.data.keys = {}; return end
            for _, key in ipairs({ "UpArrow", "DownArrow" }) do
                local down = dmhub.KeyPressed(key)
                if down and not element.data.keys[key] and #found > 0 then
                    selected = (selected - 1 + (key == "UpArrow" and -1 or 1)) % #found + 1
                    MarkSelection()
                end
                element.data.keys[key] = down
            end
        end,
    }

    local body = gui.Panel {
        classes = { "overlandMapPopoverBody", "collapsed" },
        input,
        Label({ "overlandMapHint", "sizeXs" }, T("label.searchHint")),
        none,
        results,
    }
    body.data.open = function()
        searchKey = nil
        if input.text ~= "" then input.text = "" end
        Run("")
        Session.FocusSoon(input, function() return ctx.data.popover == "search" end)
    end
    body.data.refresh = function() Run(input.text) end
    return body
end

-- Settings ------------------------------------------------------------------------------------------

local function BuildDirectorSettings(ctx)
    local data = ctx.data
    -- True while bind writes model values into the controls, so their change handlers stay quiet.
    local binding = false

    local function Section(text)
        return gui.Panel {
            classes = { "overlandMapSectionHeader" },
            Label({ "overlandMapSectionLabel", "sizeS" }, text),
        }
    end

    local function Check(text, onChange)
        return gui.Check {
            classes = { "overlandMapCheck", "sizeS" }, text = text, value = false,
            change = function(element) if not mod.unloaded then onChange(element.value == true) end end,
        }
    end

    -- Typed fields follow the model unless the Director is typing in them.
    local function SetInput(input, value)
        if input.hasFocus then return end
        if input.text ~= value then input.text = value end
    end

    -- Party
    local partyName = gui.Input {
        classes = { "input", "bordered", "overlandMapInput" }, characterLimit = C.textLimit,
        placeholderText = T("party.defaultName"),
        change = function(element)
            local result = OverlandMapCommands.SetPartyName(element.text)
            ctx.Report(OverlandMapCommands.Accepted(result), result.reason)
            ctx.RefreshAll()
        end,
    }
    local partyImage = gui.IconEditor {
        width = 64, height = 64, library = "journal", categoriesHidden = true,
        noneImage = "panels/square.png", allowPaste = true, allowNone = true, hideIcon = true,
        change = function(element)
            if binding then return end
            local imageId = element.value
            if type(imageId) == "string" and imageId ~= "" then
                local result = OverlandMapCommands.SetPartyImageId(imageId)
                ctx.Report(OverlandMapCommands.Accepted(result), result.reason)
                ctx.RefreshAll()
            end
        end,
    }
    -- Empty, it is a faint drop slot with a plus (the editor's own white box loses to a
    -- selfStyle tint, as in the side panel's picker); with an image it draws untinted.
    local partyImagePlus = gui.Panel {
        floating = true, interactable = false, width = 24, height = 24,
        halign = "center", valign = "center", bgimage = C.iconAdd, bgcolor = "#ffffff99",
    }
    local partyImageSlot = gui.Panel {
        width = 64, height = 64, halign = "left",
        hover = function(element) gui.Tooltip(T("set.party.image.choose"))(element) end,
        partyImage, partyImagePlus,
    }
    local resetImage = Button(T("set.party.image.reset"), function()
        local result = OverlandMapCommands.SetPartyImageId("")
        ctx.Report(OverlandMapCommands.Accepted(result), result.reason)
        ctx.RefreshAll()
    end)
    local playersMove = Check(T("set.party.playersMove"), function(value)
        local result = OverlandMapCommands.SetPlayersCanMoveParty(value)
        ctx.Report(OverlandMapCommands.Accepted(result), result.reason)
        ctx.RefreshAll()
    end)
    local playersAdd = Check(T("set.playersAdd"), function(value)
        local result = OverlandMapCommands.SetPlayersCanAddLocations(value)
        ctx.Report(OverlandMapCommands.Accepted(result), result.reason)
        ctx.RefreshAll()
    end)
    local playersLabels = Check(T("label.players"), function(value)
        if not binding then
            local result = OverlandMapCommands.SetPlayersCanManageLabels(value)
            ctx.Report(OverlandMapCommands.Accepted(result), result.reason)
            ctx.RefreshAll()
        end
    end)

    -- This map
    local function WriteMap(changes, description)
        local map = ctx.CurrentMap()
        if map == nil then return end
        local result = OverlandMapCommands.UpdateLocation(map.id, changes, description)
        ctx.Report(OverlandMapCommands.Accepted(result), result.reason)
        ctx.RefreshAll()
    end
    local scaleValue = Label({ "overlandMapBody", "sizeS" })
    local setScale = Button(T("set.map.scale.set"), function()
        data.scaleDraft = nil
        ctx.SetPopover(nil)
        ctx.SetTool("scale")
    end)
    local distance = gui.Input {
        classes = { "input", "bordered", "overlandMapInput", "overlandMapNumber" }, characterLimit = 10, placeholderText = "",
        change = function(element)
            local value = ParsePositive(element.text)
            local map = ctx.CurrentMap()
            if value == nil or map == nil then return end
            local draft = data.scaleDraft
            local old = Model.Field(map, "scale", nil) --[[@as nil|OverlandMapScale]]
            local scale
            if draft ~= nil and draft.mapId == map.id and draft.u2 ~= nil then
                scale = { u1 = draft.u1, v1 = draft.v1, u2 = draft.u2, v2 = draft.v2, distance = value,
                    unit = draft.unit or (old and old.unit) or "mi" }
                data.scaleDraft = nil
            elseif old ~= nil then
                scale = DeepCopy(old)
                scale.distance = value
            end
            if scale ~= nil then WriteMap({ scale = scale }, "Set map scale") end
        end,
    }
    local units = Segments(C.scaleUnits, "set.map.scale.unit.", function(unit)
        local map = ctx.CurrentMap()
        if map == nil then return end
        local draft = data.scaleDraft
        local old = Model.Field(map, "scale", nil) --[[@as nil|OverlandMapScale]]
        if draft ~= nil and draft.mapId == map.id then
            draft.unit = unit
            ctx.RefreshAll()
        elseif old ~= nil and old.unit ~= unit then
            local scale = DeepCopy(old)
            scale.unit = unit
            WriteMap({ scale = scale }, "Set map scale")
        end
    end)
    local scaleFields = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.map.scale.distance")),
        distance,
        units,
    }
    local pace = gui.Input {
        classes = { "input", "bordered", "overlandMapInput", "overlandMapNumber" }, characterLimit = 10, placeholderText = "",
        change = function(element)
            local text = Model.TrimSingleLine(element.text)
            if text == "" then
                WriteMap({ pace = false }, "Clear travel pace")
            else
                local value = ParsePositive(text)
                if value ~= nil then WriteMap({ pace = value }, "Set travel pace") end
            end
        end,
    }
    local paceFields = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.map.pace")),
        pace,
    }

    -- Border tiles (K1, K6): a small preview of the open map in each look. Torn edge
    -- and Frame stay disabled until their art is in Constants (K3).
    local borderTiles = {} --- @type Panel[]
    local borderArt = { none = true, fade = true, torn = C.borderTornMask ~= "", frame = C.borderFrameImage ~= "" }
    for _, border in ipairs(C.borders) do
        local look = {} --- @type Panel[]
        if border == "fade" then
            local fade = OverlandMapCanvasTools.CreateFade()
            -- Inset so the tile's selection frame stays visible around the fade.
            fade.selfStyle.width, fade.selfStyle.height = "100%-4", "100%-4"
            fade.selfStyle.halign, fade.selfStyle.valign = "center", "center"
            OverlandMapCanvasTools.SetFadeBand(fade, 10)
            look[1] = fade
        end
        local preview = gui.Panel { classes = { "overlandMapBorderPreview" }, interactable = false, children = look }
        local available = borderArt[border] == true
        borderTiles[#borderTiles + 1] = gui.Panel {
            -- Not "disabled": the theme styles that class and would draw the tile as active.
            classes = { "overlandMapBorderTile", available and "available" or "needsArt" },
            data = { border = border, preview = preview, imageId = nil },
            hover = function(element)
                if not available then gui.Tooltip(T("set.border.needsArt"))(element) end
            end,
            click = function(element)
                local map = ctx.CurrentMap()
                if mod.unloaded or not available or map == nil or Model.Border(map) == element.data.border then return end
                local result = OverlandMapCommands.SetBorder(map.id, element.data.border)
                ctx.Report(OverlandMapCommands.Accepted(result), result.reason)
                ctx.RefreshAll()
            end,
            preview,
            Label({ "overlandMapBorderName", "sizeXs" }, T("set.border." .. border)),
        }
    end

    local pinText = OverlandMapPinText.CreateSettings(ctx)
    local mapSection = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        Section(T("set.map")),
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.map.scale")),
        scaleValue,
        gui.Panel { classes = { "overlandMapButtonRow" }, setScale },
        scaleFields,
        paceFields,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.map.border")),
        gui.Panel { classes = { "overlandMapBorderTiles" }, children = borderTiles },
        Label({ "overlandMapHint", "sizeXs" }, T("set.map.border.hint")),
        pinText,
        gui.Panel { classes = { "overlandMapRule" }, interactable = false },
    }

    -- Whole game: travel time unit and path types (C6, C9, Q22) ----------------------------------

    -- Setting edits keep an undo entry ("Undo last change" in the log reaches it); only a delete gets a toast.
    local function Kept(result)
        if ctx.Report(OverlandMapCommands.Accepted(result), result.reason) and result.undo ~= nil then OverlandMapUndo.Remember(result.undo) end
        ctx.RefreshAll()
    end

    local unitSegments = Segments(C.pathTimeUnits, "set.timeUnit.", function(unit)
        if binding then return end
        Kept(OverlandMapCommands.SetTimeUnit(unit))
    end)
    local unitInputs, invalidUnits = {}, {}
    local unitError = Label({ "overlandMapHint", "collapsed", "sizeXs" }, T("set.timeUnit.invalid", { limit = C.textLimit }))
    local function UnitInput(key)
        local input = gui.Input {
            id = "overland-map-time-unit-" .. key, classes = { "input", "bordered", "overlandMapInput" }, characterLimit = C.textLimit,
            change = function(element)
                if binding or not ctx.IsAlive() or data.popover ~= "settings" then return end
                local value = Model.TrimSingleLine(element.text)
                local valid = OverlandMapRecords.ValidText(value)
                invalidUnits[key] = not valid or nil
                element:SetClass("invalid", not valid)
                unitError:SetClass("collapsed", next(invalidUnits) == nil)
                if valid then Kept(OverlandMapCommands.SetCustomTimeUnit({ [key] = value })) end
            end,
        }
        unitInputs[key] = input
        return input
    end
    local unitHint = Label({ "overlandMapHint", "sizeXs" }, T("set.timeUnit.hint"))
    local customUnits = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.timeUnit.singular")), UnitInput("singular"),
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.timeUnit.plural")), UnitInput("plural"), unitError,
    }

    local editingTypeId = nil --- @type nil|string the one type whose editor is open (Q22)
    local typeRows = {} --- @type table<string, Panel>
    local typesShape = ""

    local function EditType(changes)
        if editingTypeId == nil or binding then return end
        Kept(OverlandMapCommands.UpdatePathType(editingTypeId, changes))
    end

    local typeName = gui.Input {
        classes = { "input", "bordered", "overlandMapInput" }, characterLimit = C.textLimit,
        placeholderText = T("set.pathType.newName"),
        change = function(element)
            local name = Model.TrimSingleLine(element.text)
            if name ~= "" then EditType({ name = name }) end
        end,
    }
    -- Two rows (three patterns each today) keep every line choice readable at the popover's width.
    local half = math.ceil(#C.pathPatterns / 2)
    local patternRows = {
        Segments({ table.unpack(C.pathPatterns, 1, half) }, "pattern.", function(value) EditType({ pattern = value }) end),
        Segments({ table.unpack(C.pathPatterns, half + 1) }, "pattern.", function(value) EditType({ pattern = value }) end),
    }
    patternRows[2].selfStyle.tmargin = 4
    -- Swatches name their colour in a tooltip and mark the pick with a check, so colour is never the only cue (Q26).
    local swatches = {} --- @type Panel[]
    for _, key in ipairs(C.pathColorOrder) do
        swatches[#swatches + 1] = gui.Panel {
            classes = { "overlandMapSwatch", key == "ink" and "ink" or nil },
            data = { color = key },
            hover = function(element) gui.Tooltip(T("color." .. element.data.color))(element) end,
            click = function(element) EditType({ color = element.data.color }) end,
            gui.Panel { classes = { "overlandMapSwatchFill" }, bgcolor = C.pathColors[key], interactable = false },
            gui.Panel { classes = { "overlandMapSwatchCheck" }, bgimage = "phosphor/check-bold.png", interactable = false },
        }
    end
    local widthSegments = Segments(C.pathWidthOrder, "width.", function(value) EditType({ width = value }) end)
    local sameLook = Label({ "overlandMapHint", "sizeXs" })

    local function DeleteType()
        local item = OverlandMapPaths.TypeById(editingTypeId)
        if item == nil then return end
        local function Delete()
            local result = OverlandMapCommands.DeletePathType(item.id)
            local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
            if ctx.Report(ok, reason) then
                editingTypeId = nil
                ctx.Push(entry, "toast.typeDeleted", { type = item.name })
            end
            ctx.RefreshAll()
        end
        -- Only a type in use asks first (N3); undo covers the rest.
        local count = OverlandMapPaths.CountUsing(item.id)
        if count == 0 then
            Delete()
            return
        end
        ctx.Confirm {
            title = T("dlg.deleteType.title", { type = item.name }),
            message = T("dlg.deleteType.body", { count = count }),
            confirm = T("dlg.deleteType.ok"),
            onConfirm = Delete,
        }
    end

    local typeEditor = gui.Panel {
        classes = { "overlandMapTypeEditor" },
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.pathType.name")),
        typeName,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.pathType.pattern")),
        patternRows[1],
        patternRows[2],
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.pathType.color")),
        gui.Panel { classes = { "overlandMapSwatches" }, children = swatches },
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.pathType.width")),
        widthSegments,
        sameLook,
        gui.Label { classes = { "overlandMapLink", "danger", "sizeS" }, tmargin = 8, text = T("set.pathType.delete"), click = DeleteType },
    }
    -- The editor always lives in the list (collapsed when closed): a panel left
    -- without a parent warns and misses the root's styles.
    local typesList = gui.Panel { width = "100%", height = "auto", flow = "vertical", tmargin = 4, typeEditor }

    local function TypeRow(id)
        local sample = OverlandMapPathLayer.Sample(40)
        local name = Label({ "overlandMapRowName", "overlandMapTypeName", "sizeS" })
        local edit = Label({ "overlandMapTypeEdit", "sizeS" }, T("set.pathType.edit"))
        return gui.Panel {
            classes = { "overlandMapRow", "overlandMapTypeRow" },
            data = { id = id, sample = sample, name = name },
            click = function(element)
                editingTypeId = editingTypeId ~= element.data.id and element.data.id or nil
                ctx.RefreshAll()
            end,
            sample, name, edit,
        }
    end

    local addType = Button(T("set.pathType.add"), function()
        local result = OverlandMapCommands.AddPathType()
        if OverlandMapCommands.Accepted(result) then editingTypeId = result.id end
        Kept(result)
    end)

    local function BindTypes()
        local unit = OverlandMapPaths.TimeUnit()
        unitSegments.data.select(unit)
        customUnits:SetClass("collapsed", unit ~= "custom")
        SetText(unitHint, T(unit == "custom" and "set.timeUnit.customHint" or "set.timeUnit.hint"))
        local forms = OverlandMapPaths.CustomTimeUnit()
        for key, input in pairs(unitInputs) do
            if not invalidUnits[key] then SetInput(input, forms[key]) end
        end
        local types = OverlandMapPaths.Types()
        local wanted, shape, children = {}, { tostring(editingTypeId) }, {} --- @type table<string, boolean>, string[], Panel[]
        local editing = nil --- @type nil|OverlandMapPathType
        for _, item in ipairs(types) do
            wanted[item.id] = true
            shape[#shape + 1] = item.id
            local row = typeRows[item.id]
            if row == nil or not row.valid then
                row = TypeRow(item.id)
                typeRows[item.id] = row
            end
            row.data.sample.data.set(OverlandMapPathLayer.LookOfType(item))
            SetText(row.data.name, Copy.Literal(item.name))
            row:SetClass("selected", item.id == editingTypeId)
            children[#children + 1] = row
            if item.id == editingTypeId then
                editing = item
                children[#children + 1] = typeEditor
            end
        end
        for id, row in pairs(typeRows) do
            if not wanted[id] then
                if row.valid then row:DestroySelf() end
                typeRows[id] = nil
            end
        end
        if editing == nil then
            editingTypeId = nil
            children[#children + 1] = typeEditor
        end
        -- Children change only when rows come, go or the editor moves, so typing keeps its focus.
        local key = table.concat(shape, ",")
        if key ~= typesShape then
            typesShape = key
            typesList.children = children
        end
        typeEditor:SetClass("collapsed", editing == nil)
        if editing == nil then return end
        SetInput(typeName, editing.name)
        for _, row in ipairs(patternRows) do row.data.select(editing.pattern) end
        for _, swatch in ipairs(swatches) do swatch:SetClass("selected", swatch.data.color == editing.color) end
        widthSegments.data.select(editing.width)
        local twin = OverlandMapPaths.SameLook(editing)
        sameLook:SetClass("collapsed", twin == nil)
        if twin ~= nil then SetText(sameLook, T("set.pathType.sameLook", { type = twin.name })) end
    end

    local gameSection = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        Section(T("set.game")),
        playersAdd,
        playersLabels,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.timeUnit")),
        unitSegments,
        unitHint,
        customUnits,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.pathTypes")),
        Label({ "overlandMapHint", "sizeXs" }, T("set.pathTypes.hint")),
        typesList,
        gui.Panel { classes = { "overlandMapButtonRow" }, addType },
        gui.Panel { classes = { "overlandMapRule" }, interactable = false },
    }

    -- Sections run from the narrowest scope a Director changes most to the personal
    -- one (Q22): the open map, the whole game, the Party, then only this viewer.
    local body = gui.Panel {
        classes = { "overlandMapPopoverBody", "collapsed" },
        mapSection,
        gameSection,
        Section(T("set.party")),
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.party.name")),
        partyName,
        Label({ "overlandMapFormLabel", "sizeXs" }, T("set.party.image")),
        gui.Panel {
            classes = { "overlandMapSideRow" },
            partyImageSlot,
            gui.Panel { width = "auto", height = "auto", valign = "center", lmargin = 8, resetImage },
        },
        playersMove,
        gui.Panel { classes = { "overlandMapRule" }, interactable = false },
    }

    body.data.bind = function()
        if not Model.IsDirector() then return end
        binding = true
        BindTypes()
        local name = Model.PartyName()
        SetInput(partyName, name == T("party.defaultName", nil, true) and "" or name)
        local imageId = Model.PartyImageId()
        if partyImage.value ~= imageId then partyImage.value = imageId end
        resetImage:SetClass("collapsed", imageId == "")
        partyImagePlus:SetClass("collapsed", imageId ~= "")
        partyImage.selfStyle.bgcolor = imageId == "" and "#ffffff14" or "white"
        playersMove.value = Model.PlayersCanMoveParty()
        playersAdd.value = Model.PlayersCanAddLocations()
        playersLabels.value = OverlandMapLabels.PlayersCanManage()

        local map = ctx.CurrentMap()
        mapSection:SetClass("collapsed", map == nil)
        pinText.data.bind(map)
        if map ~= nil then
            local scale = Model.Field(map, "scale", nil) --[[@as nil|OverlandMapScale]]
            local draft = data.scaleDraft
            local drafting = draft ~= nil and draft.mapId == map.id and draft.u2 ~= nil
            if scale ~= nil then
                SetText(scaleValue, T("set.map.scale.value", {
                    distance = OverlandMapCanvasTools.FormatNumber(scale.distance),
                    unit = T("set.map.scale.unit." .. scale.unit),
                }))
            else
                SetText(scaleValue, T("set.map.scale.none"))
            end
            scaleFields:SetClass("collapsed", scale == nil and not drafting)
            if drafting then
                SetInput(distance, "")
                units.data.select(draft.unit or (scale and scale.unit) or "mi")
            elseif scale ~= nil then
                SetInput(distance, OverlandMapCanvasTools.FormatNumber(scale.distance))
                units.data.select(scale.unit)
            end
            paceFields:SetClass("collapsed", scale == nil or Model.IsPointCrawl(map))
            local paceValue = Model.Field(map, "pace", nil)
            SetInput(pace, Model.IsFinite(paceValue) and OverlandMapCanvasTools.FormatNumber(paceValue) or "")
            local border = Model.Border(map)
            for _, tile in ipairs(borderTiles) do
                tile:SetClass("selected", tile.data.border == border)
                if tile.data.imageId ~= map.imageId then
                    tile.data.imageId = map.imageId
                    tile.data.preview.bgimageStreamed = map.imageId
                end
            end
        end
        binding = false
    end
    body.data.open = function()
        -- Fresh from the scale tool: put the caret in Distance.
        local draft = data.scaleDraft
        if draft ~= nil and draft.u2 ~= nil then
            Session.FocusSoon(distance, function() return data.popover == "settings" end)
        end
    end
    body.data.suspend = function() pinText.data.suspend() end
    return body
end

-- Personal settings exist for every viewer. Director controls are constructed only with that permission.
local function BuildSettings(ctx)
    local binding, director = false, nil
    local directorSlot = gui.Panel { width = "100%", height = "auto", flow = "vertical" }
    local checks = {}
    local children = { Label({ "overlandMapPopoverTitle", "sizeM" }, T("set.title")), directorSlot,
        Label({ "overlandMapSectionLabel", "sizeS" }, T("set.you")),
        Label({ "overlandMapHint", "sizeXs" }, T("aids.personal")) }
    for _, item in ipairs({
        { "cam.names", OverlandMapPreferences.ShowNames, OverlandMapPreferences.SetShowNames },
        { "label.show", OverlandMapPreferences.ShowLabels, OverlandMapPreferences.SetShowLabels },
        { "aids.showCompass", OverlandMapPreferences.ShowCompass, OverlandMapPreferences.SetShowCompass },
        { "aids.showScaleBar", OverlandMapPreferences.ShowScaleBar, OverlandMapPreferences.SetShowScaleBar },
        { "aids.showHover", OverlandMapPreferences.ShowHoverText, OverlandMapPreferences.SetShowHoverText },
        { "set.reduceMotion", OverlandMapPreferences.ReduceMotion, OverlandMapPreferences.SetReduceMotion },
    }) do
        local check = gui.Check { id = "overland-map-setting-" .. item[1], classes = { "overlandMapCheck", "sizeS" }, text = T(item[1]),
            change = function(e)
                if binding or mod.unloaded then return end
                item[3](e.value == true)
                if not OverlandMapPreferences.ShowHoverText() then Session.DismissHoverText() end
                ctx.RefreshAll()
            end }
        checks[#checks + 1] = { panel = check, get = item[2] }
        children[#children + 1] = check
    end
    return gui.Panel { classes = { "overlandMapPopoverBody", "collapsed" }, children = children,
        data = {
            bind = function()
                binding = true
                if Model.IsDirector() and director == nil then
                    director = BuildDirectorSettings(ctx)
                    director:SetClass("collapsed", false)
                    directorSlot.children = { director }
                elseif not Model.IsDirector() and director ~= nil then
                    director.data.suspend(); directorSlot.children = {}; director = nil
                end
                if director then director.data.bind() end
                for _, check in ipairs(checks) do check.panel.value = check.get() end
                binding = false
            end,
            open = function() if director then director.data.open() end end,
            suspend = function() if director then director.data.suspend() end end,
        } }
end

--- Build the popover container.
--- @param ctx OverlandMapContext
--- @return Panel
function OverlandMapPopovers.Create(ctx)
    local panel
    local scroll
    local search = BuildSearch(ctx)
    -- Build Settings only on first use; each viewer receives their permitted sections.
    local settings = nil --- @type nil|Panel
    local aids = nil --- @type nil|Panel

    -- The popover grows with its content down to the bottom controls, then scrolls.
    -- A relative maxHeight is not available, so it follows the window's height.
    local function FitHeight()
        local height = ctx.root.renderedHeight or 0
        if height <= 0 then return end
        local maxHeight = math.max(120, height - 114)
        if scroll.data.maxHeight ~= maxHeight then
            scroll.data.maxHeight = maxHeight
            scroll.selfStyle.maxHeight = maxHeight
        end
    end

    scroll = gui.Panel {
        classes = { "overlandMapPopoverScroll" }, vscroll = true,
        data = { maxHeight = nil },
        search,
    }
    panel = gui.Panel {
        id = "overland-map-popover",
        classes = { "overlandMapPopover", "collapsed" },
        floating = true,
        swallowPress = true,
        thinkTime = 0.25,
        data = { shown = nil },
        think = function(element)
            if not element:HasClass("collapsed") then FitHeight() end
        end,
        bind = function(element)
            FitHeight()
            local which = ctx.data.popover
            if which == "aids" and not OverlandMapAids.CanEdit(ctx.data.mapId) then
                ctx.ClearAid()
                ctx.data.popover, which = nil, nil
            end
            element:SetClass("collapsed", which == nil)
            if which == "settings" and settings == nil then
                settings = BuildSettings(ctx)
                scroll:AddChild(settings)
            end
            if which == "aids" and aids == nil then
                aids = OverlandMapAidEditor.Create(ctx)
                scroll:AddChild(aids)
            end
            if aids ~= nil then
                aids:SetClass("collapsed", which ~= "aids")
                if which ~= "aids" then aids.data.suspend() end
            end
            search:SetClass("collapsed", which ~= "search")
            if settings ~= nil then
                settings:SetClass("collapsed", which ~= "settings")
                if which ~= "settings" then settings.data.suspend() end
            end
            local opened = which ~= nil and element.data.shown ~= which
            element.data.shown = which
            if which == "search" then
                if opened then search.data.open() else search.data.refresh() end
            elseif which == "settings" and settings ~= nil then
                settings.data.bind()
                if opened then settings.data.open() end
            elseif which == "aids" and aids ~= nil then
                aids.data.bind(ctx.CurrentMap())
            end
            if opened then
                scroll.vscrollPosition = 1
                OverlandMapLifetime.Schedule(C.afterLayoutDelay, function()
                    if not mod.unloaded and scroll.valid and ctx.IsAlive() and ctx.data.popover == which then
                        scroll.vscrollPosition = 1
                    end
                end)
            end
        end,
        scroll,
    }
    return panel
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function OverlandMapPopovers.Styles()
    return {
        OverlandMapStyles.Chrome("overlandMapPopover", {
            width = C.popoverWidth,
            maxWidth = "100%-16",
            -- Sized to its content; the scroll inside it caps the height at the
            -- space between the toolbar and the bottom controls (OverlandMapPopovers).
            height = "auto",
            halign = "right",
            valign = "top",
            rmargin = C.chromeInset,
            tmargin = C.belowChromeBar,
            flow = "vertical",
            borderColor = "@accent",
        }),
        {
            selectors = { "overlandMapPopoverScroll" },
            width = "100%",
            height = "auto",
            hpad = 12,
            vpad = 10,
            borderBox = true,
        },
        {
            selectors = { "overlandMapPopoverBody" },
            width = "100%",
            height = "auto",
            valign = "top",
            flow = "vertical",
        },
        {
            selectors = { "overlandMapPopoverTitle" },
            width = "100%",
            height = "auto",
            bmargin = 4,
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "overlandMapPopoverInput" },
            -- The theme's input padding lands outside the width on a gui.SearchInput, and
            -- borderBox does not take it back; 28 less fits the panel padding (measured live).
            width = "100%-28",
            height = 30,
            -- The search field's own hpad (room for the magnifier) must stay inside the 100%.
            borderBox = true,
        },
        {
            selectors = { "overlandMapPopoverList" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 6,
        },
        {
            selectors = { "overlandMapResult" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 8,
            vpad = 5,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 4,
        },
        {
            selectors = { "overlandMapResult", "hover" },
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = { "overlandMapResultPathRow" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 1,
        },
        {
            selectors = { "overlandMapResultPath" },
            halign = "left",
            width = "auto",
            height = "auto",
            maxWidth = 140,
            valign = "center",
            color = "@fgMuted",
            textWrap = false,
        },
        {
            selectors = { "overlandMapBorderTiles" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 2,
        },
        {
            selectors = { "overlandMapBorderTile" },
            width = "25%",
            height = "auto",
            flow = "vertical",
            hpad = 3,
            vpad = 3,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 4,
        },
        {
            selectors = { "overlandMapBorderTile", "available", "hover" },
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = { "overlandMapBorderPreview", "parent:needsArt" },
            opacity = 0.35,
        },
        {
            selectors = { "overlandMapBorderName", "parent:needsArt" },
            opacity = 0.6,
        },
        {
            selectors = { "overlandMapBorderPreview" },
            width = "100%",
            height = 44,
            bgimage = true,
            bgcolor = "white",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 3,
        },
        {
            selectors = { "overlandMapBorderPreview", "parent:selected" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "overlandMapBorderName" },
            width = "100%",
            height = "auto",
            tmargin = 3,
            textAlignment = "center",
            color = "@fgMuted",
        },
        {
            selectors = { "overlandMapBorderName", "parent:selected" },
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "overlandMapTypeRow" },
            cornerRadius = 4,
        },
        {
            selectors = { "overlandMapTypeRow", "selected" },
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "overlandMapTypeName" },
            width = "100%-90",
            lmargin = 8,
        },
        {
            selectors = { "overlandMapTypeName", "parent:selected" },
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "overlandMapTypeEdit" },
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            color = "@accent",
        },
        {
            selectors = { "overlandMapTypeEdit", "parent:hover" },
            color = "@accentHover",
        },
        {
            selectors = { "overlandMapTypeEditor" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            bmargin = 6,
            hpad = 8,
            vpad = 6,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bgAlt",
            cornerRadius = 4,
        },
        {
            selectors = { "overlandMapSwatches" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
        },
        {
            selectors = { "overlandMapSwatch" },
            width = 28,
            height = 28,
            rmargin = 6,
            flow = "none",
            bgimage = true,
            bgcolor = "clear",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 14,
        },
        {
            selectors = { "overlandMapSwatch", "hover" },
            borderColor = "@fgStrong",
        },
        {
            selectors = { "overlandMapSwatch", "selected" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "overlandMapSwatchFill" },
            width = 24,
            height = 24,
            halign = "center",
            valign = "center",
            bgimage = true,
            cornerRadius = 12,
        },
        {
            selectors = { "overlandMapSwatchFill", "parent:ink" },
            borderColor = "@fgStrong",
            borderWidth = 1,
        },
        {
            selectors = { "overlandMapSwatchCheck" },
            width = 14,
            height = 14,
            halign = "center",
            valign = "center",
            bgcolor = C.pathCasingDark,
            opacity = 0,
        },
        {
            selectors = { "overlandMapSwatchCheck", "parent:selected" },
            opacity = 1,
        },
        {
            selectors = { "overlandMapSwatchCheck", "parent:ink" },
            bgcolor = C.pathCasingLight,
        },
        {
            selectors = { "overlandMapResult", "keyboardSelected" },
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            borderWidth = 1,
        },
    }
end
