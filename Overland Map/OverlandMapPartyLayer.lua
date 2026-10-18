local mod = dmhub.GetModLoading()

--- @class OverlandMapPartyLayer: GameType
--- @field new fun(o?: table): OverlandMapPartyLayer
OverlandMapPartyLayer = RegisterGameType("OverlandMapPartyLayer")
local C, Model = OverlandMapConstants, OverlandMapModel
local Session, Copy = OverlandMapControls, OverlandMapCopy
local Clamp, IsFinite = Model.Clamp, Model.IsFinite
local ImageToPanel = OverlandMapGeometry.ImageToPanel

--- @param ctx OverlandMapContext
--- @param state OverlandMapCanvasState
--- @param pins table<string, Panel>
--- @param input table
--- @param layout fun()
--- @param wake fun()
function OverlandMapPartyLayer.Create(ctx, state, pins, input, layout, wake)
    local data = ctx.data
    local partyPanel, partyGlyph, partyName
    local Layout = layout
    local PlaceCentered = OverlandMapDrawing.PlaceCentered
    -- The Party --------------------------------------------------------------------------------

    -- How far right of a pin the banner stands when the Party is at it (R3), in canvas px.
    local function BesideOffset(locationId)
        local pin = locationId ~= nil and pins[locationId] or nil
        if pin == nil then return 0 end
        local disc = (C.pinDisc[pin.data.importance] or C.pinDisc.normal) * state.scale
        return disc / 2 + C.partySize * state.scale / 2 + 4
    end

    -- The newest leg or stop, when it is the move from where the Party stood
    -- before to where it stands now, logged moments ago, and its line is one the
    -- viewer may see (a secret leg stays a jump for players, W1).
    local function LoggedMove(party)
        local before = state.partyBefore
        if before == nil or OverlandMapPreferences.ReduceMotion() or state.layout == nil or state.imageWidth == nil then return nil end
        local entry = OverlandMapLog.Entries()[1]
        if entry == nil or state.movedIds[entry.id] or entry.mapId ~= party.mapId or #entry.route < 2 then return nil end
        if entry.kind ~= "leg" and entry.kind ~= "stopped" then return nil end
        if not OverlandMapLog.ShowsPath(entry) then return nil end
        if dmhub.serverTimeMilliseconds - OverlandMapLog.Time(entry) > C.partyMoveFresh * 1000 then return nil end
        local startsHere, endsHere
        if entry.kind == "leg" then
            -- A leg from partway (rest "on" or "back") sets out from the Party's spot on the path.
            if entry.rest == "" then startsHere = before.locationId == entry.fromId else startsHere = before.pathId == entry.pathId end
            endsHere = party.locationId == entry.toId
        else
            startsHere = before.locationId == entry.fromId
            endsHere = party.pathId == entry.pathId
        end
        if not startsHere or not endsHere then return nil end
        return entry
    end

    local function StartPartyMove(entry)
        local route = entry.route
        local width, height = state.imageWidth or 1, state.imageHeight or 1
        local lengths, total = {}, 0
        for i = 1, #route - 1 do
            local a, b = route[i], route[i + 1]
            lengths[i] = math.sqrt(((b.u - a.u) * width) ^ 2 + ((b.v - a.v) * height) ^ 2)
            total = total + lengths[i]
        end
        state.movedIds[entry.id] = true
        local layout = state.layout
        if total <= 0 or layout == nil then return end
        local seconds = Clamp(total * layout.width / width / C.partyMoveSpeed, C.partyMoveMinSeconds, C.partyMoveMaxSeconds)
        -- A whole leg or a stop leaves from beside a pin; a leg from partway leaves from the line.
        local startOffset = (entry.kind == "stopped" or entry.rest == "") and BesideOffset(entry.fromId) or 0
        state.move = {
            route = route, lengths = lengths, total = total, start = dmhub.Time(), seconds = seconds,
            startOffset = startOffset, endOffset = entry.kind == "leg" and BesideOffset(entry.toId) or 0,
            u = route[1].u, v = route[1].v, offset = startOffset,
        }
        wake()
    end

    -- Notice where the Party moved and play the leg that moved it. The Party and
    -- its log entry sync separately, so a leg arriving a moment after the Party
    -- still plays (from where the Party stood before) while the watch is open.
    local function WatchPartyMove(party)
        local key = table.concat({ tostring(party.locationId), tostring(party.pathId), tostring(party.spent),
            tostring(party.u), tostring(party.v) }, "|")
        if key ~= state.partyKey then
            state.partyKey = key
            state.partyBefore = state.partyNow
            state.partyNow = { locationId = party.locationId, pathId = party.pathId }
            -- An undo or another move mid-walk ends the old walk.
            state.move = nil
            state.moveWatchUntil = dmhub.Time() + C.partyMoveFresh
        end
        if state.move ~= nil or dmhub.Time() > state.moveWatchUntil then return end
        local entry = LoggedMove(party)
        if entry ~= nil then StartPartyMove(entry) end
    end

    local function UpdateParty()
        local party = Model.Party()
        local visible = party ~= nil and party.mapId == state.mapId
        partyPanel:SetClass("collapsed", not visible)
        partyPanel.data.party = visible and party or nil
        if not visible or party == nil then
            state.move, state.partyKey, state.partyNow, state.partyBefore = nil, "", nil, nil
            state.partyLook = ""
            return
        end
        Session.SetText(partyName, Copy.Literal(Model.PartyName()))
        local imageId = Model.PartyImageId()
        -- Restyle and place the banner again only when where it stands or how it looks changed.
        local look = table.concat({ tostring(party.u), tostring(party.v), tostring(party.locationId),
            tostring(party.pathId), tostring(state.scale), imageId }, "|")
        if look ~= state.partyLook then
            state.partyLook = look
            local size = C.partySize * state.scale
            partyPanel.selfStyle.width, partyPanel.selfStyle.height = size, size
            partyPanel.data.disc.selfStyle.cornerRadius = size / 2
            -- Layout picks the label's side (above or below) from where the Party stands.
            partyPanel.data.labelAbove = nil
            local icon = imageId ~= "" and imageId or C.iconParty
            if partyGlyph.bgimage ~= icon then partyGlyph.bgimage = icon end
            partyGlyph:SetClass("image", imageId ~= "")
            state.pinsDirty = true
        end
        WatchPartyMove(party)
    end

    partyGlyph = gui.Panel { classes = { "overlandMapPartyGlyph" }, bgimage = C.iconParty, interactable = false }
    partyName = gui.Label {
        classes = { "overlandMapPartyName", "sizeS" }, floating = true, interactable = false, text = "",
    }
    local partyDisc = gui.Panel { classes = { "overlandMapPartyDisc" }, interactable = false, partyGlyph }

    -- Where the Party is drawn, in image units. At a Location the banner sits beside the
    -- pin, so this differs from party.u/v. Its x/y are offsets in the pin layer, measured against pinRef.
    local function PartyDrawnPoint(element, party)
        local ref = state.pinRef
        if ref ~= nil and state.layout ~= nil then
            local u, v = OverlandMapGeometry.PanelToImage(ref, element.x + ref.viewWidth * 0.5, element.y + ref.viewHeight * 0.5)
            if u ~= nil and v ~= nil then return u, v end
        end
        return party.u, party.v
    end

    partyPanel = gui.Panel {
        classes = { "overlandMapParty", "collapsed" },
        floating = true, halign = "center", valign = "center",
        swallowPress = true,
        data = { party = nil, disc = partyDisc, labelAbove = nil },
        hover = input.hover,
        rightClick = input.rightClick,
        press = input.press,
        click = input.click,
        partyDisc, partyName,
    }

    -- Places the Party banner in the pin layer: at the drag preview while
    -- dragged, along its leg while it walks one, else at its point, or beside
    -- its pin when it is at a Location.
    local function PlaceParty(ref, drag)
        local party = partyPanel.data.party
        if party == nil then return end
        local x, y
        local besidePin = false
        local move = state.move
        if drag ~= nil then
            x, y = ImageToPanel(ref, drag.previewU, drag.previewV)
        elseif move ~= nil then
            x, y = ImageToPanel(ref, move.u, move.v)
            x = x + move.offset
            -- The label keeps its side while walking, so it does not jump at the first step.
            besidePin = partyPanel.data.labelAbove == true or (partyPanel.data.labelAbove == nil and move.startOffset > 0)
        else
            x, y = ImageToPanel(ref, party.u, party.v)
            -- At a Location the banner stands beside the pin, never on it (R3).
            if party.locationId ~= nil and pins[party.locationId] ~= nil then
                x = x + BesideOffset(party.locationId)
                besidePin = true
            end
        end
        PlaceCentered(partyPanel, ref, x, y)
        -- Beside a pin, the Party's label goes above it so it never covers the pin's name below.
        if partyPanel.data.labelAbove ~= besidePin then
            partyPanel.data.labelAbove = besidePin
            local size = C.partySize * state.scale
            partyName.selfStyle.valign = besidePin and "bottom" or "top"
            partyName.selfStyle.y = besidePin and -(size + 2) or size + 2
        end
    end

    -- Walk the banner along its leg: eased in and out, at one speed along the line,
    -- stepping off the pin it left and onto the side of the pin it reaches.
    local function TickPartyMove()
        local move = state.move
        if move == nil then return end
        local t = Clamp((dmhub.Time() - move.start) / move.seconds, 0, 1)
        local e = t * t * (3 - 2 * t)
        local goal, walked = e * move.total, 0
        local last = move.route[#move.route]
        local u, v = last.u, last.v
        for i, length in ipairs(move.lengths) do
            if length > 0 and walked + length >= goal then
                local a, b = move.route[i], move.route[i + 1]
                local f = (goal - walked) / length
                u, v = a.u + (b.u - a.u) * f, a.v + (b.v - a.v) * f
                break
            end
            walked = walked + length
        end
        local edge = C.partyMoveEdge
        move.u, move.v = u, v
        move.offset = move.startOffset * (1 - Clamp(e / edge, 0, 1)) + move.endOffset * Clamp((e - 1 + edge) / edge, 0, 1)
        if t >= 1 then
            -- Done: the banner goes back to being drawn from the stored Party.
            state.move = nil
            state.pinsDirty = true
            Layout()
        elseif state.pinRef ~= nil then
            PlaceParty(state.pinRef, nil)
        end
    end

    return {
        layer = partyPanel, Bind = UpdateParty, Layout = PlaceParty, SetPreview = PlaceParty,
        DrawnPoint = PartyDrawnPoint, Tick = TickPartyMove,
        HitTest = function(x, y)
            local ref = state.pinRef
            if ref == nil or partyPanel.data.party == nil then return false end
            local px = partyPanel.x + ref.viewWidth / 2 + state.layerX
            local py = partyPanel.y + ref.viewHeight / 2 + state.layerY
            local radius = C.partySize * state.scale / 2
            return math.abs(px - x) <= radius and math.abs(py - y) <= radius
        end,
        Destroy = function() if partyPanel.valid then partyPanel:DestroySelf() end end,
    }
end
