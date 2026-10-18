local mod = dmhub.GetModLoading()

--- The Atlas: a gallery of the top-level maps the viewer can open (D8b), plus
--- the Director's "New map" card (D12c). Shown while no map is open.
---
--- Events on the returned panel:
---   bind()             redraw the cards from the model
---   bannerRows(rows)   how many shell banners are showing; content moves below them
--- @class OverlandMapAtlas: GameType
--- @field new fun(o?: table): OverlandMapAtlas
OverlandMapAtlas = RegisterGameType("OverlandMapAtlas")
local Model = OverlandMapModel
local Session = OverlandMapControls
local Copy = OverlandMapCopy
local C = OverlandMapConstants

local T = Copy.T
local SetText = Session.SetText

local TOP_CLEARANCE = 44 -- the breadcrumb row
local BANNER_ROW = 34    -- one single-line banner plus its gap

--- Build the Atlas.
--- @param ctx OverlandMapContext
--- @return Panel
function OverlandMapAtlas.Create(ctx)
    local panel
    local grid
    local cards = {} --- @type table<string, Panel>
    local newCard
    local newPicker
    local newModeStep
    local newImageStep
    local newModeName
    local emptyTitle
    local emptyBody
    local emptyBox

    -- The New map card has two steps (A1): the map kind, then its image.
    local function ShowNewStep(step, mode)
        newCard.data.step, newCard.data.mode = step, mode
        newModeStep:SetClass("collapsed", step ~= "mode")
        newImageStep:SetClass("collapsed", step ~= "image")
        if mode ~= nil then SetText(newModeName, T("mode." .. mode)) end
    end

    -- Create the map once an image is chosen; it opens with its name ready to edit.
    local function CreateMap(imageId)
        if type(imageId) ~= "string" or imageId == "" then return end
        local mode = newCard.data.mode
        ShowNewStep("mode", nil)
        local valid = OverlandMapSession.Guard(ctx, Model.IsDirector)
        local result = OverlandMapCommands.CreateMap(T("atlas.new.defaultName", nil, true), imageId, {
            success = function(write)
                local newId = write.record.id
                if not valid() or not Model.IsDirector() or not Model.CanOpenMap(Model.GetLocation(newId)) then return end
                ctx.OpenMap(newId, "fit")
                ctx.data.focusName = true
                ctx.Select(newId, "edit")
                ctx.CheckImageSize(newId, imageId)
            end,
            failure = function() if valid() then ctx.Report(false, "unavailable") end end,
        }, mode)
        local ok, reason = OverlandMapCommands.Accepted(result), result.reason
        ctx.Report(ok, reason)
    end

    local function Card(id)
        local function ShowActions(element)
            if not ctx.IsAlive() or not Model.IsDirector() then return end
            ctx.ShowMenu(element, id)
        end
        local actions = gui.Panel {
            classes = { "overlandMapCardActions" }, floating = true, swallowPress = true,
            Session.IconButton("overland-map-atlas-more-" .. id, C.iconMore, T("panel.more"), ShowActions),
        }
        local pointcrawl = gui.Label {
            classes = { "overlandMapChip", "overlandMapThumbChip", "collapsed", "sizeXs" }, text = T("chip.pointcrawl"), interactable = false,
        }
        local sharing = gui.Label {
            id = "overland-map-atlas-sharing-" .. id,
            classes = { "overlandMapChip", "overlandMapThumbChip", "collapsed", "sizeXs" },
            floating = true, valign = "bottom", tmargin = 0, bmargin = 4,
            text = "", interactable = false,
        }
        local request
        local thumb = gui.Panel {
            classes = { "overlandMapCardThumb" }, interactable = false,
            imageLoaded = function(element)
                if request then request.Loaded(element.bgimageWidth, element.bgimageHeight) end
            end,
            destroy = function() if request then request.Cancel() end end,
            pointcrawl, sharing,
        }
        thumb.data.load = function(imageId)
            if request then request.Cancel() end
            request = OverlandMapImages.Request {
                id = id, source = imageId,
                valid = function()
                    local row = Model.GetLocation(id)
                    return ctx.IsAlive() and thumb.valid and row ~= nil and Model.CanOpenMap(row) and row.imageId == imageId
                end,
                changed = function() end,
            }
            thumb.bgimageStreamed = imageId
        end
        local name = gui.Label { classes = { "overlandMapCardName", "sizeS" }, text = "", interactable = false }
        local count = gui.Label { classes = { "overlandMapCardText", "sizeXs" }, text = "", interactable = false }
        local party = gui.Label { classes = { "overlandMapChip", "collapsed", "sizeXs" }, text = T("atlas.card.party"), interactable = false }
        return gui.Panel {
            id = "overland-map-atlas-card-" .. id,
            classes = { "overlandMapCard" },
            data = {
                id = id, thumb = thumb, name = name, count = count, party = party, sharing = sharing,
                pointcrawl = pointcrawl, imageId = nil, actions = actions,
            },
            hover = function(element)
                local location = Model.GetLocation(element.data.id)
                if location ~= nil then Session.HoverText(element, T("atlas.card.open", { map = Model.DisplayName(location) })) end
            end,
            click = function(element)
                if not mod.unloaded then ctx.OpenMap(element.data.id, "restore") end
            end,
            rightClick = ShowActions,
            thumb,
            name,
            gui.Panel { classes = { "overlandMapCardMeta" }, count, party },
            actions,
        }
    end

    local function Bind()
        local maps = OverlandMapReaders.Atlas()
        local director = Model.IsDirector()
        local party = Model.Party()
        local desired = {}
        local children = {} --- @type Panel[]
        for _, view in ipairs(maps) do
            local map = view.row
            desired[map.id] = true
            local card = cards[map.id]
            if card == nil or not card.valid then
                card = Card(map.id)
                cards[map.id] = card
            end
            if card.data.imageId ~= map.imageId then
                card.data.imageId = map.imageId
                card.data.thumb.data.load(map.imageId)
            end
            SetText(card.data.name, Copy.Literal(Model.DisplayName(map)))
            local visible = view.count
            SetText(card.data.count, T("atlas.card.count", { count = visible }))
            card.data.party:SetClass("collapsed", not view.partyHere)
            SetText(card.data.sharing, T(map.mapShared and "atlas.card.revealed" or "atlas.card.hidden"))
            card.data.sharing:SetClass("collapsed", not director)
            card.data.pointcrawl:SetClass("collapsed", not Model.IsPointCrawl(map))
            card.data.actions:SetClass("collapsed", not director)
            card:SetClass("notShared", director and not map.mapShared)
            children[#children + 1] = card
        end
        for id, card in pairs(cards) do
            if not desired[id] then
                if card.valid then card:DestroySelf() end
                cards[id] = nil
            end
        end
        newCard:SetClass("collapsed", not director)
        children[#children + 1] = newCard
        grid.children = children
        local empty = #maps == 0
        emptyBox:SetClass("collapsed", not empty)
        if empty then
            SetText(emptyTitle, T(director and "atlas.empty.director.title" or "atlas.empty.player.title"))
            SetText(emptyBody, T(director and "atlas.empty.director.body" or "atlas.empty.player.body"))
        end
    end

    newPicker = gui.IconEditor {
        width = "100%", height = C.atlasThumbHeight, library = "journal", categoriesHidden = true,
        -- A "none image" hides the editor's "(none)" label; it still reads back as "".
        noneImage = "panels/square.png",
        allowPaste = true, allowNone = true, hideIcon = true,
        -- The IconEditor reads stretch as a flag; the shared stub types it as a border.
        ---@diagnostic disable-next-line: assign-type-mismatch
        stretch = true,
        aspect = 9 / 16,
        change = function(element)
            local imageId = element.value
            if type(imageId) == "string" and imageId ~= "" then
                element.value = ""
                CreateMap(imageId)
            end
        end,
    }
    -- Empty, the editor draws a solid white box (its style rules lose to the theme);
    -- a faint tint set on selfStyle reads as a drop slot. It never holds an image:
    -- choosing one creates the map and clears the editor.
    newPicker.selfStyle.bgcolor = "#ffffff14"
    newModeStep = gui.Panel {
        width = "100%", height = "auto", flow = "vertical", valign = "top",
        gui.Label { classes = { "overlandMapCardName", "sizeS" }, text = T("mode.title"), interactable = false },
        Session.ModeChoice(function(mode) ShowNewStep("image", mode) end),
    }
    newModeName = gui.Label {
        classes = { "overlandMapCardName", "sizeS" }, width = "auto", halign = "left", text = "", interactable = false,
    }
    newImageStep = gui.Panel {
        classes = { "collapsed" }, width = "100%", height = "auto", flow = "vertical", valign = "top",
        -- The card has no room for the size guidance, so its tooltip carries it (J2).
        hover = gui.Tooltip(T("atlas.new.picker") .. "\n" .. ctx.ImageHint()),
        -- The plus floats over the picker and ignores the pointer, so clicks reach the picker.
        gui.Panel {
            width = "100%", height = C.atlasThumbHeight, halign = "left", valign = "top",
            newPicker,
            gui.Panel {
                floating = true, interactable = false, width = 32, height = 32,
                halign = "center", valign = "center", bgimage = C.iconAdd, bgcolor = "#ffffff99",
            },
        },
        gui.Panel {
            classes = { "overlandMapCardMeta" },
            newModeName,
            gui.Label {
                classes = { "overlandMapLink", "overlandMapCardBack", "sizeXs" }, text = T("mode.back"),
                click = function() ShowNewStep("mode", nil) end,
            },
        },
    }
    newCard = gui.Panel {
        classes = { "overlandMapCard" },
        height = "auto", minHeight = C.atlasCardHeight,
        data = { step = "mode", mode = nil },
        gui.Label {
            id = "overland-map-atlas-hidden-notice",
            classes = { "overlandMapModeDesc", "bold", "sizeXs" }, tmargin = 4, bmargin = 6,
            text = T("map.new.hidden"), interactable = false,
        },
        newModeStep,
        newImageStep,
    }

    emptyTitle = gui.Label { classes = { "overlandMapEmptyTitle", "sizeM" }, text = "" }
    emptyBody = gui.Label { classes = { "overlandMapEmptyBody", "sizeS" }, text = "" }
    emptyBox = gui.Panel { classes = { "overlandMapEmpty", "collapsed" }, emptyTitle, emptyBody }
    -- The New map card starts as a static child: a panel built here but only
    -- attached later through .children never picked up the root's styles.
    grid = gui.Panel { classes = { "overlandMapAtlasGrid" }, newCard }

    -- The breadcrumb and banners float over the Atlas, so its content starts below them.
    local body = gui.Panel {
        classes = { "overlandMapAtlasBody" }, tmargin = TOP_CLEARANCE, data = { rows = 0 }, emptyBox, grid,
    }

    panel = gui.Panel {
        id = "overland-map-atlas",
        classes = { "overlandMapAtlas", "collapsed" },
        floating = true, vscroll = true,
        bind = function() Bind() end,
        bannerRows = function(_, rows)
            if body.data.rows == rows then return end
            body.data.rows = rows
            body.selfStyle.tmargin = TOP_CLEARANCE + rows * BANNER_ROW
        end,
        body,
    }
    return panel
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function OverlandMapAtlas.Styles()
    return {
        {
            selectors = { "overlandMapAtlas" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "overlandMapAtlasBody" },
            width = "100%",
            height = "auto",
            valign = "top",
            flow = "vertical",
            hpad = 16,
            vpad = 16,
            borderBox = true,
        },
        {
            selectors = { "overlandMapAtlasGrid" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
        },
        OverlandMapStyles.Chrome("overlandMapCard", {
            width = C.atlasCardWidth,
            height = C.atlasCardHeight,
            halign = "left",
            valign = "top",
            flow = "vertical",
            rmargin = 12,
            bmargin = 12,
            pad = 6,
            borderBox = true,
        }),
        {
            selectors = { "overlandMapCard", "hover" },
            borderColor = "@accent",
            transitionTime = 0.1,
        },
        {
            selectors = { "overlandMapCard", "notShared" },
            opacity = 0.75,
        },
        {
            selectors = { "overlandMapCardThumb" },
            width = "100%",
            height = C.atlasThumbHeight,
            bgcolor = "white",
            cornerRadius = 4,
        },
        {
            selectors = { "overlandMapCardName" },
            width = "100%",
            height = "auto",
            tmargin = 6,
            bold = true,
            color = "@fgStrong",
            textWrap = false,
            textOverflow = "ellipsis",
        },
        OverlandMapStyles.Chrome("overlandMapCardActions", {
            width = 34,
            height = 34,
            halign = "right",
            valign = "top",
            flow = "none",
            margin = 4,
        }),
        {
            selectors = { "overlandMapCardMeta" },
            width = "100%",
            height = "auto",
            tmargin = 2,
            flow = "horizontal",
        },
        {
            selectors = { "overlandMapCardText" },
            width = "auto",
            height = "auto",
            rmargin = 6,
            color = "@fgMuted",
            textWrap = false,
        },
        {
            selectors = { "overlandMapChip" },
            width = "auto",
            height = "auto",
            rmargin = 4,
            hpad = 5,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bgAlt",
            cornerRadius = 3,
            color = "@fg",
        },
        OverlandMapStyles.Chrome("overlandMapEmpty", {
            width = "90%",
            maxWidth = 460,
            height = "auto",
            halign = "center",
            valign = "center",
            bmargin = 16,
            flow = "vertical",
            pad = 18,
            borderBox = true,
        }),
        {
            selectors = { "overlandMapEmptyTitle" },
            width = "100%",
            height = "auto",
            textAlignment = "center",
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "overlandMapEmptyBody" },
            width = "100%",
            height = "auto",
            tmargin = 6,
            textAlignment = "center",
            color = "@fgMuted",
            textWrap = true,
        },
        {
            selectors = { "overlandMapCardBack" },
            halign = "right",
            tmargin = 0,
        },
    }
end
