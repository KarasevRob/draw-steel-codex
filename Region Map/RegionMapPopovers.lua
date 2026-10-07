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

local function Label(classes, text)
    return gui.Label { classes = classes, text = text or "", interactable = false }
end

local function Button(text, action)
    return gui.Button {
        classes = { "regionMapButton", "sizeS" }, text = text,
        click = function() if not mod.unloaded then action() end end,
    }
end

-- A row of segment buttons, one per value (same control as the side panel's).
local function Segments(values, copyPrefix, onPick)
    local buttons = {}
    local row = gui.Panel { classes = { "regionMapSegments" }, data = {} }
    for _, value in ipairs(values) do
        buttons[#buttons + 1] = gui.Label {
            classes = { "regionMapSegment" }, text = T(copyPrefix .. value),
            width = string.format("%.4f%%", 100 / #values),
            data = { value = value },
            click = function(element) onPick(element.data.value) end,
        }
    end
    row.children = buttons
    row.data.select = function(current)
        for _, button in ipairs(buttons) do button:SetClass("selected", button.data.value == current) end
    end
    return row
end

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
        dmhub.Schedule(0.05, function()
            if not mod.unloaded and input.valid and ctx.data.popover == "search" then gui.SetFocus(input) end
        end)
    end
    body.data.bind = function() end
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
    local units = Segments({ "mi", "km" }, "set.map.scale.unit.", function(unit)
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
    local mapSection = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
        Section(T("set.map")),
        Label({ "regionMapFormLabel" }, T("set.map.scale")),
        scaleValue,
        gui.Panel { classes = { "regionMapButtonRow" }, setScale },
        scaleFields,
        paceFields,
    }

    -- Only for you
    local reduceMotion = Check(T("set.reduceMotion"), function(value)
        Session.SetReduceMotion(value)
        ctx.RefreshAll()
    end)

    local body = gui.Panel {
        classes = { "regionMapPopoverBody", "collapsed" },
        Label({ "regionMapPopoverTitle" }, T("set.title")),
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
        playersAdd,
        mapSection,
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
        Section(T("set.you")),
        reduceMotion,
    }

    -- Typed fields follow the model unless the Director is typing in them.
    local function SetInput(input, value)
        if input.hasFocus then return end
        if input.text ~= value then input.text = value end
    end

    body.data.bind = function()
        binding = true
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
        end
        binding = false
    end
    body.data.open = function()
        -- Fresh from the scale tool: put the caret in Distance.
        local draft = data.scaleDraft
        if draft ~= nil and draft.u2 ~= nil then
            dmhub.Schedule(0.05, function()
                if not mod.unloaded and distance.valid and data.popover == "settings" then gui.SetFocus(distance) end
            end)
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
    local settings = BuildSettings(ctx)

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
        search, settings,
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
            search:SetClass("collapsed", which ~= "search")
            settings:SetClass("collapsed", which ~= "settings")
            local opened = which ~= nil and element.data.shown ~= which
            element.data.shown = which
            if which == "search" then
                if opened then search.data.open() end
            elseif which == "settings" then
                settings.data.bind()
                if opened then settings.data.open() end
            end
        end,
        scroll,
    }
    return panel
end
