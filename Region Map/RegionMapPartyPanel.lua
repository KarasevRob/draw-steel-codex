local mod = dmhub.GetModLoading()

--- Party travel on point crawl maps (V21-17): the Party section at the right
--- edge (opened by clicking the banner or the status chip, G1), the Party's
--- right-click "Travel to" menu, the hidden-path question (W1) and the
--- Director's stop card for placing the Party partway along a path (G3, G7).
--- It uses the side panel's look and place; the shell shows one panel at a time.
---
--- Events on the panel from Create:
---   bind()   redraw for ctx.data.panelMode "party"
--- @class RegionMapPartyPanel: GameType
--- @field new fun(o?: table): RegionMapPartyPanel
RegionMapPartyPanel = RegisterGameType("RegionMapPartyPanel")
local C = RegionMapConstants
local Model = RegionMapModel
local Paths = RegionMapPaths
local Travel = RegionMapTravel
local Session = RegionMapSession
local Copy = RegionMapCopy

local SetText = Session.SetText
local T = Copy.T
local Label = Session.Label

local NameOf = Model.NameOf
local PathLabel = Paths.ShownName

--- Travel one option. A hidden path asks the Director first whether to reveal
--- it (W1). The toast names the leg the way the log does (Q19).
--- @param ctx RegionMapContext
--- @param option RegionMapTravelOption
function RegionMapPartyPanel.Travel(ctx, option)
    local path = Paths.Get(option.pathId)
    if path == nil then return end
    local function Go(reveal)
        local current = Paths.Get(option.pathId)
        if current == nil or not ctx.IsAlive() then return end
        local pathName = Paths.DisplayName(current)
        local ok, reason, entry = Travel.Travel(option, reveal)
        if not ctx.Report(ok, reason) then return end
        -- From partway "from" would name an end the Party never left from, so the toast
        -- reads like the log line: "Traveled on to ..." or "Turned back to ...".
        local copyId, args = RegionMapLog.LegCopy(option.rest, NameOf(option.fromId), NameOf(option.toId), pathName,
            option.time, "toast.traveled")
        args.party = Model.PartyName()
        ctx.Push(entry, copyId, args)
        ctx.RefreshAll()
    end
    if option.hidden and Model.IsDirector() then
        ctx.Confirm {
            title = T("dlg.hiddenTravel.title", { path = PathLabel(path) }),
            message = T("dlg.hiddenTravel.body", { party = Model.PartyName() }),
            confirm = T("dlg.hiddenTravel.reveal"),
            onConfirm = function() Go(true) end,
            alternate = T("dlg.hiddenTravel.keep"),
            onAlternate = function() Go(false) end,
        }
        return
    end
    Go(false)
end

--- The Party banner's right-click menu: one "Travel to" submenu (manifest
--- 25.5), each entry ctx.party.travel without its leading "Travel to", which
--- the submenu already says: "{dest} by {path} ({time})". Empty when the
--- viewer has nowhere to take the Party.
--- @param ctx RegionMapContext
--- @return ContextMenuEntry[]
function RegionMapPartyPanel.MenuEntries(ctx)
    local options = Travel.Options()
    local submenu = {} --- @type ContextMenuEntry[]
    for _, option in ipairs(options) do
        local path = Paths.Get(option.pathId)
        if path ~= nil then
            -- The core menu's shortcut slot hugs the text in the same colour, so the time goes in brackets.
            submenu[#submenu + 1] = {
                text = T("party.travel.row", { dest = NameOf(option.toId), path = PathLabel(path) })
                    .. " (" .. Paths.FormatTime(option.time) .. ")",
                click = function() RegionMapPartyPanel.Travel(ctx, option) end,
            }
        end
    end
    if #submenu == 0 then return {} end
    return { { text = T("ctx.party.travelMenu"), submenu = submenu } }
end

--- Whether the Party section has something to show: the Party on the open
--- point crawl map.
--- @param ctx RegionMapContext
--- @return boolean
function RegionMapPartyPanel.Available(ctx)
    local party = Model.Party()
    if party == nil or party.mapId ~= ctx.data.mapId then return false end
    return Model.IsPointCrawl(Model.GetLocation(party.mapId))
end

-- The Party section ----------------------------------------------------------------------------------

--- Build the Party section panel.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapPartyPanel.Create(ctx)
    local data = ctx.data
    local panel
    local signature = nil --- @type nil|string the rows were last built from this

    local icon = gui.Panel { classes = { "regionMapSideIcon" }, bgimage = C.iconParty, interactable = false }
    local title = gui.Label { classes = { "regionMapSideTitle" }, text = T("party.section") }
    local closeButton = Session.IconButton("region-map-party-close", C.iconClose, T("panel.close"), function()
        if data.panelMode == "party" then
            data.panelMode = "none"
            ctx.RefreshAll()
        end
    end)
    local status = Label({ "regionMapBody" })
    local message = Label({ "regionMapBody" })
    local heading = gui.Panel {
        width = "100%", height = "auto", flow = "vertical",
        gui.Panel { classes = { "regionMapRule" }, interactable = false },
        Label({ "regionMapSectionLabel" }, T("party.travelTo")),
    }
    local rows = gui.Panel { width = "100%", height = "auto", flow = "vertical", tmargin = 4 }

    local function Row(option, path)
        local children = {
            gui.Panel {
                classes = { "regionMapTravelText" }, interactable = false,
                Label({ "regionMapRowName" }, T("party.travel.row", { dest = NameOf(option.toId), path = PathLabel(path) })),
                Label({ "regionMapMeta" }, Paths.FormatTime(option.time)),
            },
        } --- @type Panel[]
        -- The Director sees which ways players don't know yet (W1).
        if option.hidden then
            children[#children + 1] = gui.Panel { classes = { "regionMapPathRowEye" }, bgimage = C.iconEyeSlash, interactable = false }
        end
        return gui.Panel {
            classes = { "regionMapRow", "regionMapPathRow" },
            click = function() if not mod.unloaded then RegionMapPartyPanel.Travel(ctx, option) end end,
            children = children,
        }
    end

    local function Bind()
        local open = data.panelMode == "party" and RegionMapPartyPanel.Available(ctx)
        panel:SetClass("collapsed", not open)
        if not open then
            signature = nil
            return
        end
        local rootWidth = ctx.root.renderedWidth or 0
        local width = C.sidePanelWidth * Session.UIScale()
        if rootWidth > 0 and rootWidth < C.narrowWidth then width = rootWidth end
        if panel.data.width ~= width then
            panel.data.width = width
            panel.selfStyle.width = width
        end

        local party = Model.Party()
        local partyName = Model.PartyName()
        local statusText = ""
        if party ~= nil and party.locationId ~= nil then
            statusText = T("party.status.at", { party = partyName, name = NameOf(party.locationId) })
        elseif party ~= nil and party.pathId ~= nil then
            local path = Paths.Get(party.pathId)
            if path ~= nil then
                statusText = T("party.status.onPath", {
                    party = partyName, path = PathLabel(path), time = Paths.FormatTime(party.spent or 0),
                    name = NameOf(party.pathFrom or ""),
                })
            end
        end
        SetText(status, statusText)
        status:SetClass("collapsed", statusText == "")

        local options, block = Travel.Options()
        local messageText = ""
        if block == "noPermission" then
            messageText = T("party.travel.noPermission", { party = partyName })
        elseif block == "offPath" then
            messageText = T(Model.IsDirector() and "party.travel.offPath" or "party.travel.offPath.player", { party = partyName })
        elseif #options == 0 then
            messageText = T("party.travel.none")
        end
        SetText(message, messageText)
        message:SetClass("collapsed", messageText == "")
        heading:SetClass("collapsed", #options == 0)

        -- Rebuilt only when a row changed, so a refresh does not relayout the list.
        local parts = { Paths.TimeUnit() }
        local items = {} --- @type {option: RegionMapTravelOption, path: RegionMapPathRecord}[]
        for _, option in ipairs(options) do
            local path = Paths.Get(option.pathId)
            if path ~= nil then
                items[#items + 1] = { option = option, path = path }
                parts[#parts + 1] = table.concat({
                    option.pathId, option.toId, option.rest, tostring(option.time), tostring(option.hidden),
                    PathLabel(path), NameOf(option.toId),
                }, "|")
            end
        end
        local key = table.concat(parts, "\n")
        if key == signature then return end
        signature = key
        local children = {} --- @type Panel[]
        for _, item in ipairs(items) do children[#children + 1] = Row(item.option, item.path) end
        rows.children = children
    end

    panel = gui.Panel {
        id = "region-map-party-panel",
        classes = { "regionMapSide", "collapsed" },
        floating = true,
        width = C.sidePanelWidth,
        popupsInheritStyles = true,
        data = { width = nil },
        bind = function() if not mod.unloaded then Bind() end end,
        gui.Panel {
            classes = { "regionMapSideScroll" }, vscroll = true,
            gui.Panel {
                classes = { "regionMapSideBody" },
                gui.Panel { classes = { "regionMapSideHeader" }, icon, title, closeButton },
                status,
                message,
                heading,
                rows,
            },
        },
    }
    return panel
end

-- The stop card (G3, G7, Q14) --------------------------------------------------------------------------

--- Build the Director's stop card: the time already spent along a path from
--- one end, half the path's time to start with. data.open(pathId) shows it for
--- a path; data.close() hides it.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapPartyPanel.CreateStopCard(ctx)
    local layer
    local state = { pathId = nil, fromId = nil } --- @type {pathId: nil|string, fromId: nil|string}

    local title = gui.Label { classes = { "regionMapConfirmTitle" }, text = "", interactable = false }
    local fieldLabel = Label({ "regionMapFormLabel" })
    local Place
    local input = gui.Input {
        id = "region-map-stop-time", classes = { "input", "bordered", "regionMapInput", "regionMapTimeInput" },
        characterLimit = 8,
        edit = function() if layer ~= nil then layer.data.showError(false) end end,
        -- Enter places the Party, like the Place Party button.
        submit = function() if not mod.unloaded and Place ~= nil then Place() end end,
    }
    local of = Label({ "regionMapBody", "regionMapTimeUnit" })
    local errorLine = Label({ "regionMapHint", "danger", "collapsed" })
    local swapButton

    local function Close()
        state.pathId, state.fromId = nil, nil
        layer:SetClass("collapsed", true)
        ctx.RefreshAll()
    end

    -- Show the card counting from fromId, the field reset to half that way's time (G7).
    local function Fill(path, fromId)
        state.pathId, state.fromId = path.id, fromId
        local total = Travel.Duration(path, fromId) or 0
        local other = Paths.OtherEnd(path, fromId)
        SetText(title, T("dlg.stop.title", { party = Model.PartyName(), path = PathLabel(path) }))
        SetText(fieldLabel, T("dlg.stop.field", { name = NameOf(fromId) }))
        SetText(of, T("dlg.stop.of", { time = Paths.FormatTime(total) }))
        input.text = Paths.TimeInputText(total / 2)
        SetText(errorLine, T("dlg.stop.range", { time = Paths.FormatTime(total) }))
        errorLine:SetClass("collapsed", true)
        -- Counting from the far end only makes sense when that way has a time (W2).
        local otherTime = Travel.Duration(path, other)
        swapButton:SetClass("collapsed", otherTime == nil or otherTime <= 0)
        SetText(swapButton, T("dlg.stop.swap", { name = NameOf(other) }))
    end

    Place = function()
        local path = Paths.Get(state.pathId)
        local fromId = state.fromId
        if path == nil or fromId == nil then
            Close()
            return
        end
        local total = Travel.Duration(path, fromId) or 0
        local spent = Paths.ParseTime(input.text)
        if spent == nil or spent <= 0 or spent >= total then
            errorLine:SetClass("collapsed", false)
            return
        end
        local ok, reason, entry = Travel.StopPartway(path.id, fromId, spent)
        if not ctx.Report(ok, reason) then return end
        ctx.Push(entry, "toast.stopped", { party = Model.PartyName(), path = PathLabel(path) })
        Close()
    end

    swapButton = gui.Button {
        classes = { "regionMapButton", "sizeS", "regionMapStopSwap" }, text = "",
        click = function()
            local path = Paths.Get(state.pathId)
            if path == nil or state.fromId == nil or mod.unloaded then return end
            Fill(path, Paths.OtherEnd(path, state.fromId))
        end,
    }

    layer = gui.Panel {
        id = "region-map-stop", classes = { "regionMapConfirmLayer", "collapsed" }, floating = true,
        swallowPress = true, data = {},
        gui.Panel {
            classes = { "regionMapConfirm" },
            title,
            fieldLabel,
            gui.Panel { classes = { "regionMapTimeRow" }, input, of },
            errorLine,
            swapButton,
            Label({ "regionMapHint" }, T("dlg.stop.hint")),
            gui.Panel {
                classes = { "regionMapConfirmButtons" },
                gui.Button {
                    id = "region-map-stop-ok", classes = { "regionMapButton", "sizeS" }, text = T("dlg.stop.ok"),
                    click = function() if not mod.unloaded then Place() end end,
                },
                gui.Button {
                    id = "region-map-stop-cancel", classes = { "regionMapButton", "sizeS" }, text = T("dlg.cancel"),
                    click = function() if not mod.unloaded then Close() end end,
                },
            },
        },
    }

    layer.data.showError = function(shown) errorLine:SetClass("collapsed", not shown) end
    layer.data.open = function(pathId)
        local path = Paths.Get(pathId)
        if path == nil or not Travel.CanStopOn(path) then return end
        Fill(path, Travel.StopFrom(path))
        layer:SetClass("collapsed", false)
        ctx.RefreshAll()
        Session.FocusSoon(input, function() return not layer:HasClass("collapsed") end)
    end
    layer.data.close = Close
    return layer
end
