local mod = dmhub.GetModLoading()

--- The Atlas: a gallery of the top-level maps the viewer can open (D8b), plus
--- the Director's "New map" card (D12c). Shown while no map is open.
---
--- Events on the returned panel:
---   bind()             redraw the cards from the model
---   bannerRows(rows)   how many shell banners are showing; content moves below them
--- @class RegionMapAtlas: GameType
--- @field new fun(o?: table): RegionMapAtlas
RegionMapAtlas = RegisterGameType("RegionMapAtlas")
local Model = RegionMapModel
local Session = RegionMapSession
local Copy = RegionMapCopy
local C = RegionMapConstants

local T = Copy.T
local SetText = Session.SetText

local TOP_CLEARANCE = 44 -- the breadcrumb row
local BANNER_ROW = 34    -- one single-line banner plus its gap

--- Build the Atlas.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapAtlas.Create(ctx)
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
        local newId = nil
        local ok, reason, _, id = Model.CreateMap(T("atlas.new.defaultName", nil, true), imageId, {
            success = function()
                if not ctx.IsAlive() or newId == nil then return end
                ctx.OpenMap(newId, "fit")
                ctx.data.focusName = true
                ctx.Select(newId, "edit")
                ctx.CheckImageSize(newId, imageId)
            end,
            failure = function() ctx.Report(false, "unavailable") end,
        }, mode)
        newId = id
        ctx.Report(ok, reason)
    end

    local function Card(id)
        local function ShowActions(element)
            if not ctx.IsAlive() or not Model.IsDirector() then return end
            ctx.ShowMenu(element, id)
        end
        local actions = gui.Panel {
            classes = { "regionMapCardActions" }, floating = true, swallowPress = true,
            Session.IconButton("region-map-atlas-more-" .. id, C.iconMore, T("panel.more"), ShowActions),
        }
        local pointcrawl = gui.Label {
            classes = { "regionMapChip", "regionMapThumbChip", "collapsed" }, text = T("chip.pointcrawl"), interactable = false,
        }
        local thumb = gui.Panel { classes = { "regionMapCardThumb" }, interactable = false, pointcrawl }
        local name = gui.Label { classes = { "regionMapCardName" }, text = "", interactable = false }
        local count = gui.Label { classes = { "regionMapCardText" }, text = "", interactable = false }
        local party = gui.Label { classes = { "regionMapChip", "collapsed" }, text = T("atlas.card.party"), interactable = false }
        local notShared = gui.Label { classes = { "regionMapChip", "collapsed" }, text = T("atlas.card.notShared"), interactable = false }
        return gui.Panel {
            id = "region-map-atlas-card-" .. id,
            classes = { "regionMapCard" },
            data = {
                id = id, thumb = thumb, name = name, count = count, party = party, notShared = notShared,
                pointcrawl = pointcrawl, imageId = nil, actions = actions,
            },
            hover = function(element)
                local location = Model.GetLocation(element.data.id)
                if location ~= nil then gui.Tooltip(T("atlas.card.open", { map = Model.DisplayName(location) }))(element) end
            end,
            click = function(element)
                if not mod.unloaded then ctx.OpenMap(element.data.id, "restore") end
            end,
            rightClick = ShowActions,
            thumb,
            name,
            gui.Panel { classes = { "regionMapCardMeta" }, count, party, notShared },
            actions,
        }
    end

    local function Bind()
        local maps = Model.TopLevel()
        local director = Model.IsDirector()
        local party = Model.Party()
        local desired = {}
        local children = {} --- @type Panel[]
        for _, map in ipairs(maps) do
            desired[map.id] = true
            local card = cards[map.id]
            if card == nil or not card.valid then
                card = Card(map.id)
                cards[map.id] = card
            end
            if card.data.imageId ~= map.imageId then
                card.data.imageId = map.imageId
                card.data.thumb.bgimageStreamed = map.imageId
            end
            SetText(card.data.name, Copy.Literal(Model.DisplayName(map)))
            local visible = Model.VisibleDescendantCount(map.id)
            SetText(card.data.count, T("atlas.card.count", { count = visible }))
            card.data.party:SetClass("collapsed", party == nil or not Model.IsInSubtree(map.id, party.mapId))
            card.data.notShared:SetClass("collapsed", not director or map.mapShared)
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
        gui.Label { classes = { "regionMapCardName" }, text = T("mode.title"), interactable = false },
        Session.ModeChoice(function(mode) ShowNewStep("image", mode) end),
    }
    newModeName = gui.Label {
        classes = { "regionMapCardName" }, width = "auto", halign = "left", text = "", interactable = false,
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
            classes = { "regionMapCardMeta" },
            newModeName,
            gui.Label {
                classes = { "regionMapLink", "regionMapCardBack" }, text = T("mode.back"),
                click = function() ShowNewStep("mode", nil) end,
            },
        },
    }
    newCard = gui.Panel {
        classes = { "regionMapCard" },
        data = { step = "mode", mode = nil },
        newModeStep,
        newImageStep,
    }

    emptyTitle = gui.Label { classes = { "regionMapEmptyTitle" }, text = "" }
    emptyBody = gui.Label { classes = { "regionMapEmptyBody" }, text = "" }
    emptyBox = gui.Panel { classes = { "regionMapEmpty", "collapsed" }, emptyTitle, emptyBody }
    -- The New map card starts as a static child: a panel built here but only
    -- attached later through .children never picked up the root's styles.
    grid = gui.Panel { classes = { "regionMapAtlasGrid" }, newCard }

    -- The breadcrumb and banners float over the Atlas, so its content starts below them.
    local body = gui.Panel {
        classes = { "regionMapAtlasBody" }, tmargin = TOP_CLEARANCE, data = { rows = 0 }, emptyBox, grid,
    }

    panel = gui.Panel {
        id = "region-map-atlas",
        classes = { "regionMapAtlas", "collapsed" },
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
