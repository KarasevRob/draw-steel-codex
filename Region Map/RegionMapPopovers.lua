local mod = dmhub.GetModLoading()

--- The two toolbar popovers, drawn inside the window under the toolbar:
--- Search (V2-13, every Location the viewer can see on any map) and the
--- Director's Settings (V2-16, manifest section 13). ctx.data.popover says
--- which one is open; the shell closes it with Esc or a press on the map.
---
--- Events on the returned panel:
---   bind()   redraw for ctx.data.popover and the current map
--- @class RegionMapPopovers: GameType
--- @field new fun(o?: table): RegionMapPopovers
RegionMapPopovers = RegisterGameType("RegionMapPopovers")
local C = RegionMapConstants
local Model = RegionMapModel
local Session = RegionMapSession
local Copy = RegionMapCopy

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
    local results = gui.Panel { classes = { "regionMapPopoverList" } }
    local none = Label({ "regionMapHint", "collapsed" })
    local top = nil --- @type nil|RegionMapLocationRecord the result Enter opens

    -- The ancestors of a result (the levels the viewer can see), with crumb icons between.
    local function PathRow(location)
        local parts = {} --- @type Panel[]
        local path = Model.Ancestors(location.id)
        for i = 1, #path - 1 do
            if Model.CanOpenMap(path[i]) then
                if #parts > 0 then
                    parts[#parts + 1] = gui.Panel { classes = { "regionMapCrumbSep", "small" }, bgimage = C.iconCrumb, interactable = false }
                end
                parts[#parts + 1] = Label({ "regionMapResultPath" }, Copy.Literal(Model.DisplayName(path[i])))
            end
        end
        return gui.Panel { classes = { "regionMapResultPathRow" }, interactable = false, children = parts }
    end

    local function Open(location)
        ctx.SetPopover(nil)
        ctx.FocusLocation(location.id)
    end

    local input
    local function Run(query)
        local found = Model.Search(query, C.searchResultLimit)
        top = found[1]
        local rows = {} --- @type Panel[]
        for _, location in ipairs(found) do
            rows[#rows + 1] = gui.Panel {
                classes = { "regionMapResult" },
                click = function() Open(location) end,
                Label({ "regionMapRowName" }, Copy.Literal(Model.DisplayName(location))),
                PathRow(location),
            }
        end
        results.children = rows
        local trimmed = Model.TrimSingleLine(query)
        none:SetClass("collapsed", #found > 0 or trimmed == "")
        SetText(none, T("search.none", { query = trimmed }))
    end

    input = gui.SearchInput {
        classes = { "regionMapPopoverInput" },
        placeholderText = T("search.placeholder"), editlag = 0.15,
        edit = function(element) Run(element.text) end,
        change = function(element) Run(element.text) end,
        -- Enter opens the top result (R9).
        submit = function(element)
            Run(element.text)
            if top ~= nil then Open(top) end
        end,
    }

    local body = gui.Panel {
        classes = { "regionMapPopoverBody", "collapsed" },
        input,
        Label({ "regionMapHint" }, T("search.hint")),
        none,
        results,
    }
    body.data.open = function()
        if input.text ~= "" then input.text = "" end
        Run("")
        Session.FocusSoon(input, function() return ctx.data.popover == "search" end)
    end
    return body
end

-- Settings ------------------------------------------------------------------------------------------

local function BuildSettings(ctx)
    local data = ctx.data
    -- True while bind writes model values into the controls, so their change handlers stay quiet.
    local binding = false

    local function Section(text)
        return gui.Panel {
            classes = { "regionMapSectionHeader" },
            Label({ "regionMapSectionLabel" }, text),
        }
    end

    local function Check(text, onChange)
        return gui.Check {
            classes = { "regionMapCheck" }, text = text, value = false, fontSize = 14,
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
        classes = { "input", "bordered", "regionMapInput" }, characterLimit = C.textLimit,
        placeholderText = T("party.defaultName"),
        change = function(element)
            Model.SetPartyName(element.text)
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
                Model.SetPartyImageId(imageId)
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
        Model.SetPartyImageId("")
        ctx.RefreshAll()
    end)
    local playersMove = Check(T("set.party.playersMove"), function(value)
        Model.SetPlayersCanMoveParty(value)
        ctx.RefreshAll()
    end)
    local playersAdd = Check(T("set.playersAdd"), function(value)
        Model.SetPlayersCanAddLocations(value)
        ctx.RefreshAll()
    end)

    -- This map
    local function WriteMap(changes, description)
        local map = ctx.CurrentMap()
        if map == nil then return end
        ctx.Report(Model.UpdateLocation(map.id, changes, description))
        ctx.RefreshAll()
    end
    local scaleValue = Label({ "regionMapBody" })
    local setScale = Button(T("set.map.scale.set"), function()
        data.scaleDraft = nil
        ctx.SetPopover(nil)
        ctx.SetTool("scale")
    end)
    local distance = gui.Input {
        classes = { "input", "bordered", "regionMapInput", "regionMapNumber" }, characterLimit = 10, placeholderText = "",
        change = function(element)
            local value = ParsePositive(element.text)
            local map = ctx.CurrentMap()
            if value == nil or map == nil then return end
            local draft = data.scaleDraft
            local old = Model.Field(map, "scale", nil) --[[@as nil|RegionMapScale]]
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
        local old = Model.Field(map, "scale", nil) --[[@as nil|RegionMapScale]]
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
        Label({ "regionMapFormLabel" }, T("set.map.scale.distance")),
        distance,
        units,
    }
    local pace = gui.Input {
        classes = { "input", "bordered", "regionMapInput", "regionMapNumber" }, characterLimit = 10, placeholderText = "",
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
        Label({ "regionMapFormLabel" }, T("set.map.pace")),
        pace,
    }

    -- Border tiles (K1, K6): a small preview of the open map in each look. Torn edge
    -- and Frame stay disabled until their art is in Constants (K3).
    local borderTiles = {} --- @type Panel[]
    local borderArt = { none = true, fade = true, torn = C.borderTornMask ~= "", frame = C.borderFrameImage ~= "" }
    for _, border in ipairs(C.borders) do
        local look = {} --- @type Panel[]
        if border == "fade" then
            local fade = RegionMapCanvasTools.CreateFade()
            -- Inset so the tile's selection frame stays visible around the fade.
            fade.selfStyle.width, fade.selfStyle.height = "100%-4", "100%-4"
            fade.selfStyle.halign, fade.selfStyle.valign = "center", "center"
            RegionMapCanvasTools.SetFadeBand(fade, 10)
            look[1] = fade
        end
        local preview = gui.Panel { classes = { "regionMapBorderPreview" }, interactable = false, children = look }
        local available = borderArt[border] == true
        borderTiles[#borderTiles + 1] = gui.Panel {
            -- Not "disabled": the theme styles that class and would draw the tile as active.
            classes = { "regionMapBorderTile", available and "available" or "needsArt" },
            data = { border = border, preview = preview, imageId = nil },
            hover = function(element)
                if not available then gui.Tooltip(T("set.border.needsArt"))(element) end
            end,
            click = function(element)
                local map = ctx.CurrentMap()
                if mod.unloaded or not available or map == nil or Model.Border(map) == element.data.border then return end
                ctx.Report(Model.SetBorder(map.id, element.data.border))
                ctx.RefreshAll()
            end,
            preview,
            Label({ "regionMapBorderName" }, T("set.border." .. border)),
        }
    end

    local mapSection = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        Section(T("set.map")),
        Label({ "regionMapFormLabel" }, T("set.map.scale")),
        scaleValue,
        gui.Panel { classes = { "regionMapButtonRow" }, setScale },
        scaleFields,
        paceFields,
        Label({ "regionMapFormLabel" }, T("set.map.border")),
        gui.Panel { classes = { "regionMapBorderTiles" }, children = borderTiles },
        Label({ "regionMapHint" }, T("set.map.border.hint")),
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
    }

    -- Whole game: travel time unit and path types (C6, C9, Q22) ----------------------------------

    -- Setting edits keep an undo entry ("Undo last change" in the log reaches it); only a delete gets a toast.
    local function Kept(ok, reason, entry)
        if ctx.Report(ok, reason) and entry ~= nil then RegionMapUndo.Remember(entry) end
        ctx.RefreshAll()
    end

    local unitSegments = Segments(C.pathTimeUnits, "set.timeUnit.", function(unit)
        if binding then return end
        Kept(RegionMapPaths.SetTimeUnit(unit))
    end)

    local editingTypeId = nil --- @type nil|string the one type whose editor is open (Q22)
    local typeRows = {} --- @type table<string, Panel>
    local typesShape = ""

    local function EditType(changes)
        if editingTypeId == nil or binding then return end
        Kept(RegionMapPaths.UpdateType(editingTypeId, changes))
    end

    local typeName = gui.Input {
        classes = { "input", "bordered", "regionMapInput" }, characterLimit = C.textLimit,
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
            classes = { "regionMapSwatch", key == "ink" and "ink" or nil },
            data = { color = key },
            hover = function(element) gui.Tooltip(T("color." .. element.data.color))(element) end,
            click = function(element) EditType({ color = element.data.color }) end,
            gui.Panel { classes = { "regionMapSwatchFill" }, bgcolor = C.pathColors[key], interactable = false },
            gui.Panel { classes = { "regionMapSwatchCheck" }, bgimage = "phosphor/check-bold.png", interactable = false },
        }
    end
    local widthSegments = Segments(C.pathWidthOrder, "width.", function(value) EditType({ width = value }) end)
    local sameLook = Label({ "regionMapHint" })

    local function DeleteType()
        local item = RegionMapPaths.TypeById(editingTypeId)
        if item == nil then return end
        local function Delete()
            local ok, reason, entry = RegionMapPaths.DeleteType(item.id)
            if ctx.Report(ok, reason) then
                editingTypeId = nil
                ctx.Push(entry, "toast.typeDeleted", { type = item.name })
            end
            ctx.RefreshAll()
        end
        -- Only a type in use asks first (N3); undo covers the rest.
        local count = RegionMapPaths.CountUsing(item.id)
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
        classes = { "regionMapTypeEditor" },
        Label({ "regionMapFormLabel" }, T("set.pathType.name")),
        typeName,
        Label({ "regionMapFormLabel" }, T("set.pathType.pattern")),
        patternRows[1],
        patternRows[2],
        Label({ "regionMapFormLabel" }, T("set.pathType.color")),
        gui.Panel { classes = { "regionMapSwatches" }, children = swatches },
        Label({ "regionMapFormLabel" }, T("set.pathType.width")),
        widthSegments,
        sameLook,
        gui.Label { classes = { "regionMapLink", "danger" }, tmargin = 8, text = T("set.pathType.delete"), click = DeleteType },
    }
    -- The editor always lives in the list (collapsed when closed): a panel left
    -- without a parent warns and misses the root's styles.
    local typesList = gui.Panel { width = "100%", height = "auto", flow = "vertical", tmargin = 4, typeEditor }

    local function TypeRow(id)
        local sample = RegionMapPathLayer.Sample(40)
        local name = Label({ "regionMapRowName", "regionMapTypeName" })
        local edit = Label({ "regionMapTypeEdit" }, T("set.pathType.edit"))
        return gui.Panel {
            classes = { "regionMapRow", "regionMapTypeRow" },
            data = { id = id, sample = sample, name = name },
            click = function(element)
                editingTypeId = editingTypeId ~= element.data.id and element.data.id or nil
                ctx.RefreshAll()
            end,
            sample, name, edit,
        }
    end

    local addType = Button(T("set.pathType.add"), function()
        local ok, reason, entry, id = RegionMapPaths.AddType()
        if ok then editingTypeId = id end
        Kept(ok, reason, entry)
    end)

    local function BindTypes()
        unitSegments.data.select(RegionMapPaths.TimeUnit())
        local types = RegionMapPaths.Types()
        local wanted, shape, children = {}, { tostring(editingTypeId) }, {} --- @type table<string, boolean>, string[], Panel[]
        local editing = nil --- @type nil|RegionMapPathType
        for _, item in ipairs(types) do
            wanted[item.id] = true
            shape[#shape + 1] = item.id
            local row = typeRows[item.id]
            if row == nil or not row.valid then
                row = TypeRow(item.id)
                typeRows[item.id] = row
            end
            row.data.sample.data.set(RegionMapPathLayer.LookOfType(item))
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
        addType:SetClass("collapsed", #types >= C.pathTypeLimit)
        if editing == nil then return end
        SetInput(typeName, editing.name)
        for _, row in ipairs(patternRows) do row.data.select(editing.pattern) end
        for _, swatch in ipairs(swatches) do swatch:SetClass("selected", swatch.data.color == editing.color) end
        widthSegments.data.select(editing.width)
        local twin = RegionMapPaths.SameLook(editing)
        sameLook:SetClass("collapsed", twin == nil)
        if twin ~= nil then SetText(sameLook, T("set.pathType.sameLook", { type = twin.name })) end
    end

    local gameSection = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        Section(T("set.game")),
        playersAdd,
        Label({ "regionMapFormLabel" }, T("set.timeUnit")),
        unitSegments,
        Label({ "regionMapHint" }, T("set.timeUnit.hint")),
        Label({ "regionMapFormLabel" }, T("set.pathTypes")),
        Label({ "regionMapHint" }, T("set.pathTypes.hint")),
        typesList,
        gui.Panel { classes = { "regionMapButtonRow" }, addType },
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
    }

    -- Only for you
    local reduceMotion = Check(T("set.reduceMotion"), function(value)
        Session.SetReduceMotion(value)
        ctx.RefreshAll()
    end)

    -- Sections run from the narrowest scope a Director changes most to the personal
    -- one (Q22): the open map, the whole game, the Party, then only this viewer.
    local body = gui.Panel {
        classes = { "regionMapPopoverBody", "collapsed" },
        Label({ "regionMapPopoverTitle" }, T("set.title")),
        mapSection,
        gameSection,
        Section(T("set.party")),
        Label({ "regionMapFormLabel" }, T("set.party.name")),
        partyName,
        Label({ "regionMapFormLabel" }, T("set.party.image")),
        gui.Panel {
            classes = { "regionMapSideRow" },
            partyImageSlot,
            gui.Panel { width = "auto", height = "auto", valign = "center", lmargin = 8, resetImage },
        },
        playersMove,
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
        Section(T("set.you")),
        reduceMotion,
    }

    body.data.bind = function()
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
        reduceMotion.value = Session.ReduceMotion()

        local map = ctx.CurrentMap()
        mapSection:SetClass("collapsed", map == nil)
        if map ~= nil then
            local scale = Model.Field(map, "scale", nil) --[[@as nil|RegionMapScale]]
            local draft = data.scaleDraft
            local drafting = draft ~= nil and draft.mapId == map.id and draft.u2 ~= nil
            if scale ~= nil then
                SetText(scaleValue, T("set.map.scale.value", {
                    distance = RegionMapCanvasTools.FormatNumber(scale.distance),
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
                SetInput(distance, RegionMapCanvasTools.FormatNumber(scale.distance))
                units.data.select(scale.unit)
            end
            -- Pace is in the scale's unit, so it shows once a scale exists.
            paceFields:SetClass("collapsed", scale == nil)
            local paceValue = Model.Field(map, "pace", nil)
            SetInput(pace, Model.IsFinite(paceValue) and RegionMapCanvasTools.FormatNumber(paceValue) or "")
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
    return body
end

--- Build the popover container.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapPopovers.Create(ctx)
    local panel
    local scroll
    local search = BuildSearch(ctx)
    -- Settings costs tens of ms to build (each checkbox ~9 ms) and players never see
    -- it, so it is built the first time a Director opens it.
    local settings = nil --- @type nil|Panel

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
        classes = { "regionMapPopoverScroll" }, vscroll = true,
        data = { maxHeight = nil },
        search,
    }
    panel = gui.Panel {
        id = "region-map-popover",
        classes = { "regionMapPopover", "collapsed" },
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
            if which == "settings" and not Model.IsDirector() then which = nil end
            element:SetClass("collapsed", which == nil)
            if which == "settings" and settings == nil then
                settings = BuildSettings(ctx)
                scroll.children = { search, settings }
            end
            search:SetClass("collapsed", which ~= "search")
            if settings ~= nil then settings:SetClass("collapsed", which ~= "settings") end
            local opened = which ~= nil and element.data.shown ~= which
            element.data.shown = which
            if which == "search" then
                if opened then search.data.open() end
            elseif which == "settings" and settings ~= nil then
                settings.data.bind()
                if opened then settings.data.open() end
            end
        end,
        scroll,
    }
    return panel
end
