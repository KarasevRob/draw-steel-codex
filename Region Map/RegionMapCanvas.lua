--- The map canvas: the map image, pins, the Party banner, the camera and its
--- controls, pointer input (pan, wheel, pin and Party drags) and the zoom and
--- crossfade transitions between maps.
---
--- The shell talks to it with events on the returned panel:
---   bind()                    redraw from the model (pins, Party, image changes)
---   showMap(how)              the open map changed: "fit" | "restore" | "down" | "up" | "jump"
---   animateInto(id, onDone)   zoom into a pin, then call onDone (before "Open map")
---   keepVisible(id, inset)    pan just enough that a pin is not under the side panel
---   centerOn(id)              center the camera on a pin (Search)
---   cancelGesture()           drop a drag or pan in progress
---   relayout()                redraw the ruler and route after a tool click
--- Drags are polled in think rather than built on engine dragging: the engine
--- moves draggable panels physically (V1 lesson).
--- @class RegionMapCanvas: GameType
--- @field new fun(o?: table): RegionMapCanvas
RegionMapCanvas = RegisterGameType("RegionMapCanvas")
local C = RegionMapConstants
local Model = RegionMapModel
local Tools = RegionMapCanvasTools
local Session = RegionMapSession
local Copy = RegionMapCopy

local Clamp = Model.Clamp
local IsFinite = Model.IsFinite
local ImageToPanel = Tools.ImageToPanel

--- A press on the map, a pin or the Party, tracked until the button is released.
--- @class RegionMapDrag
--- @field kind "pan"|"pin"|"party"|"ruler"
--- @field id nil|string the pin being dragged
--- @field button integer 0 left, 1 right, 2 middle
--- @field startX number
--- @field startY number
--- @field startCamera RegionMapCamera
--- @field startU number
--- @field startV number
--- @field allowed boolean the viewer may move what was pressed
--- @field moved boolean past the drag threshold
--- @field previewU nil|number
--- @field previewV nil|number
--- @field snapId nil|string the pin a dropped Party would snap to

--- A camera move animated in think (Open map, going up).
--- @class RegionMapCameraAnimation
--- @field from RegionMapCamera
--- @field to RegionMapCamera
--- @field start number dmhub.Time() when it began
--- @field onDone nil|fun()
--- @field noSave boolean true when the end view must not become the map's saved camera

--- The canvas's own view state: what is loaded and what the pointer is doing.
--- @class RegionMapCanvasState
--- @field mapId nil|string the map whose image is loaded
--- @field imageId nil|string
--- @field imageRevision nil|integer
--- @field imageWidth nil|number known once the image has loaded
--- @field imageHeight nil|number
--- @field layout nil|RegionMapLayout nil until the image has loaded
--- @field imageRequest integer drops imageLoaded events of replaced image panels
--- @field crossfade boolean the new image fades in over the old one once loaded
--- @field fadeStart nil|number
--- @field animOnLoad nil|RegionMapCamera camera to ease to once the image loads (going up)
--- @field drag nil|RegionMapDrag
--- @field lastDrag nil|RegionMapDrag the drag the latest release ended
--- @field showNames boolean cached Show names preference
--- @field anim nil|RegionMapCameraAnimation
--- @field cameraDirty boolean
--- @field cameraSaveScheduled boolean
--- @field hovered boolean
--- @field lastPointerX nil|number
--- @field lastPointerY nil|number
--- @field lastPointerMove number
--- @field keyEdges table<string, boolean>
--- @field scale number Font Size scale for pins and the Party
--- @field pinsShown nil|boolean whether pins were last shown (nil forces an update)
--- @field pinRef nil|RegionMapLayout the layout pins were last placed against
--- @field pinsDirty boolean pins must be placed again on the next Layout
--- @field layerX number the pin layer's offset from pinRef (the pan since then)
--- @field layerY number

-- The icon of a pin: a curated key, a library image id, or the default glyph.
local function PinIcon(location)
    local key = location.icon
    if C.pinIcons[key] ~= nil then return C.pinIcons[key], false end
    if key ~= "" then return key, true end
    return C.pinIcons[C.defaultPinIcon], false
end

--- @param a RegionMapCamera
--- @param b RegionMapCamera
--- @param t number 0..1
--- @return RegionMapCamera
local function LerpCamera(a, b, t)
    -- Ease out: fast start, gentle landing.
    local e = 1 - (1 - t) * (1 - t)
    return {
        zoom = a.zoom + (b.zoom - a.zoom) * e,
        centerX = a.centerX + (b.centerX - a.centerX) * e,
        centerY = a.centerY + (b.centerY - a.centerY) * e,
    }
end

--- Build the canvas component.
--- @param ctx RegionMapContext
--- @return Panel
function RegionMapCanvas.Create(ctx)
    local data = ctx.data
    local canvas
    local imagePanel
    local fadingPanel = nil --- @type nil|Panel the previous map, fading out under the new one
    -- Pins and the Party live in one layer that slides as a whole while the
    -- map pans, so a pan moves one panel instead of every pin (V2-21). The
    -- layer must stay interactable: a non-interactable layer stops its pins' clicks.
    local pinLayer
    local pinChildren = {} --- @type Panel[]
    local RebuildChildren
    local partyPanel
    local partyName
    local partyGlyph
    local controls
    local namesButton
    local overlay = Tools.CreateOverlay(ctx)
    local pins = {} --- @type table<string, Panel>
    --- @type RegionMapCanvasState
    local state = {
        mapId = nil, imageId = nil, imageRevision = nil,
        imageWidth = nil, imageHeight = nil, layout = nil,
        imageRequest = 0, crossfade = false, fadeStart = nil, animOnLoad = nil,
        drag = nil, lastDrag = nil, showNames = false, anim = nil,
        cameraDirty = false, cameraSaveScheduled = false,
        hovered = false, lastPointerX = nil, lastPointerY = nil, lastPointerMove = 0,
        keyEdges = {}, scale = 1,
        pinRef = nil, pinsDirty = true, layerX = 0, layerY = 0,
    }

    local Layout
    local CreateImagePanel

    -- Camera ---------------------------------------------------------------------------------

    local function OpenLocation()
        return Model.GetLocation(state.mapId)
    end

    -- Camera saves are debounced: wheel notches and pans only mark it dirty.
    local function FlushCamera()
        if not state.cameraDirty then return end
        state.cameraDirty = false
        local map = OpenLocation()
        if map ~= nil and map.imageRevision == state.imageRevision then Session.SaveCamera(map, data.camera) end
    end

    local function SaveCamera()
        if state.mapId == nil then return end
        state.cameraDirty = true
        if not state.cameraSaveScheduled then
            state.cameraSaveScheduled = true
            canvas:ScheduleEvent("regionMapSaveCamera", C.cameraSaveDelay)
        end
    end

    local function FitCamera()
        return { zoom = C.minZoom, centerX = 0.5, centerY = 0.5 }
    end

    --- End the camera animation where it is. Its onDone still runs: the shell
    --- waits for it (Open map opens in it), so a dropped onDone left the window
    --- refusing every later map change. True when onDone switched maps, so the
    --- caller's own camera change no longer applies.
    local function StopAnimation()
        local anim = state.anim
        state.anim = nil
        if anim == nil or anim.onDone == nil then return false end
        local mapId = state.mapId
        anim.onDone()
        return state.mapId ~= mapId
    end

    --- Ease the camera to `to`, then call onDone. The end view is saved as this
    --- map's camera unless noSave is true (the zoom into a pin before its map
    --- opens is transient: going back up should return to the real view).
    local function StartAnimation(to, onDone, noSave)
        StopAnimation()
        if Session.ReduceMotion() then
            data.camera = to
            Layout()
            if onDone ~= nil then onDone() end
            return
        end
        state.anim = {
            from = { zoom = data.camera.zoom, centerX = data.camera.centerX, centerY = data.camera.centerY },
            to = to, start = dmhub.Time(), onDone = onDone, noSave = noSave == true,
        }
    end

    local function Zoom(factor)
        if state.layout == nil or StopAnimation() then return end
        data.camera.zoom = Clamp(data.camera.zoom * factor, C.minZoom, C.maxZoom)
        Layout()
        SaveCamera()
    end

    -- Pointer helpers ------------------------------------------------------------------------

    local function PointerInCanvas()
        local point = canvas.mousePoint
        local width, height = canvas.renderedWidth or 0, canvas.renderedHeight or 0
        if point == nil or width <= 0 or height <= 0 then return nil, nil end
        return point.x * width, (1 - point.y) * height
    end

    local function GestureActive()
        return state.drag ~= nil and state.drag.moved
    end

    -- Pins -----------------------------------------------------------------------------------

    local function PinSize(location)
        local disc = (C.pinDisc[location.importance] or C.pinDisc.normal) * state.scale
        return disc, math.max(disc, C.pinHitMin * state.scale)
    end

    -- Whether a pin's name shows at the current zoom (D5c declutter, R9 Show names).
    -- Reads the pin's own data, since Layout calls it for every pin on every frame.
    local function NameVisible(pinData)
        if state.showNames or data.selectedId == pinData.id then return true end
        if pinData.pinStyle == "iconOnly" then return false end
        if pinData.pinStyle == "plate" then return true end
        local threshold = C.declutterZoom[pinData.importance]
        return threshold == nil or data.camera.zoom >= threshold
    end

    local function HoverText(location)
        local name = Model.DisplayName(location)
        local details = Model.Details(location.id)
        local firstLine = details ~= nil and details.description:match("^[^\n]*") or ""
        if firstLine == "" then return Copy.T("pin.hover.nameOnly", { name = name }) end
        return Copy.T("pin.hover", { name = name, description = firstLine })
    end

    -- Ends the drag in progress on release and commits what it moved. Both
    -- think (button up) and the click event can see the release first.
    local function FinishDrag()
        local drag = state.drag
        state.drag = nil
        if drag == nil then return nil end
        state.lastDrag = drag
        -- A dragged pin or Party was drawn at its preview; put everything back at its stored place.
        if drag.kind == "pin" or drag.kind == "party" then state.pinsDirty = true end
        if drag.snapId ~= nil and pins[drag.snapId] ~= nil then pins[drag.snapId]:SetClass("snapTarget", false) end
        if drag.kind == "pan" then
            if drag.moved then SaveCamera() end
            return drag
        end
        -- A ruler drag already wrote both points while it moved.
        if drag.kind == "ruler" then return drag end
        if not drag.moved or not drag.allowed or state.mapId == nil then return drag end
        if drag.kind == "pin" and drag.previewU ~= nil and drag.previewV ~= nil and drag.id ~= nil then
            local location = Model.GetLocation(drag.id)
            local ok, reason, entry = Model.MoveLocation(drag.id, drag.previewU, drag.previewV)
            if ctx.Report(ok, reason) and location ~= nil then
                ctx.Push(entry, "toast.moved", { name = Model.DisplayName(location) })
            end
        elseif drag.kind == "party" and drag.previewU ~= nil and drag.previewV ~= nil then
            local party = Model.PartyName()
            if drag.snapId ~= nil then
                local target = Model.GetLocation(drag.snapId)
                local ok, reason, entry = Model.WriteParty { mapId = state.mapId, locationId = drag.snapId }
                if ctx.Report(ok, reason) and target ~= nil then
                    ctx.Push(entry, "toast.partyAt", { party = party, name = Model.DisplayName(target) })
                end
            else
                local ok, reason, entry = Model.WriteParty { mapId = state.mapId, u = drag.previewU, v = drag.previewV }
                if ctx.Report(ok, reason) then ctx.Push(entry, "toast.partyTraveling", { party = party }) end
            end
        end
        ctx.RefreshAll()
        return drag
    end

    -- The drag a click or right-click event belongs to: still open, or just
    -- finished by think. True means the release ended a drag, not a click.
    local function ReleasedDragMoved()
        local drag = FinishDrag() or state.lastDrag
        state.lastDrag = nil
        return drag ~= nil and drag.moved
    end

    local function BeginDrag(kind, id, u, v, allowed)
        local x, y = PointerInCanvas()
        if x == nil or y == nil or StopAnimation() then return end
        state.lastDrag = nil
        state.drag = {
            kind = kind, id = id, button = 0, startX = x, startY = y,
            startCamera = { zoom = data.camera.zoom, centerX = data.camera.centerX, centerY = data.camera.centerY },
            startU = u or 0, startV = v or 0, allowed = allowed, moved = false,
        }
    end

    -- The name plate and the badges are made the first time a pin shows them:
    -- most pins never do, and a dense map builds hundreds of pins at once.
    local function PinPart(pin, key)
        local part = pin.data[key]
        if part ~= nil then return part end
        if key == "plate" then
            part = gui.Label { classes = { "regionMapPinName", "plate" }, interactable = false, text = "" }
        else
            local isMap = key == "mapBadge"
            part = gui.Panel {
                classes = { "regionMapPinBadge" }, floating = true, halign = isMap and "right" or "left",
                valign = "top", interactable = false,
                gui.Panel {
                    classes = { "regionMapPinBadgeGlyph" }, bgimage = isMap and C.iconMap or C.iconEyeSlash,
                    interactable = false,
                },
            }
        end
        pin.data[key] = part
        -- Later children draw on top, so badges stay above the plate whatever order they were made in.
        local children = { pin.data.disc, pin.data.name }
        for _, other in ipairs({ "plate", "mapBadge", "hiddenBadge" }) do
            if pin.data[other] ~= nil then children[#children + 1] = pin.data[other] end
        end
        pin.children = children
        return part
    end

    local function ShowPart(pin, key, show)
        if show then
            local part = PinPart(pin, key)
            if part:HasClass("collapsed") then part:SetClass("collapsed", false) end
        elseif pin.data[key] ~= nil and not pin.data[key]:HasClass("collapsed") then
            pin.data[key]:SetClass("collapsed", true)
        end
    end

    local function CreatePin(id)
        local glyph = gui.Panel { classes = { "regionMapPinGlyph" }, interactable = false }
        local disc = gui.Panel { classes = { "regionMapPinDisc" }, interactable = false, glyph }
        local name = gui.Label {
            classes = { "regionMapPinName" }, floating = true, interactable = false, text = "",
        }
        -- Centered so x/y place the pin's middle on its point (see PlaceCentered).
        return gui.Panel {
            classes = { "regionMapPin" },
            floating = true, halign = "center", valign = "center",
            swallowPress = true,
            data = {
                id = id, disc = disc, glyph = glyph, name = name, plate = nil,
                mapBadge = nil, hiddenBadge = nil, u = 0, v = 0, signature = nil, showName = nil,
            },
            hover = function(element)
                local location = Model.GetLocation(element.data.id)
                if location ~= nil and state.drag == nil then gui.Tooltip(HoverText(location))(element) end
            end,
            press = function(element)
                if element:GetMouseButton(0) ~= true then return end
                local location = Model.GetLocation(element.data.id)
                if location == nil then return end
                -- A tooltip shown on hover would stay behind at the drag's start.
                element.tooltip = nil
                gui.SetFocus(canvas)
                local canDrag = data.tool == "none" and not data.locked and Model.CanEdit(location)
                BeginDrag("pin", location.id, location.u, location.v, canDrag)
            end,
            click = function(element)
                if ReleasedDragMoved() then return end
                -- The ruler and the scale tool measure to a pin's point instead of selecting it.
                if data.tool == "ruler" or data.tool == "scale" then
                    Tools.PlaceAt(ctx, element.data.u, element.data.v)
                    Layout()
                    return
                end
                ctx.Select(element.data.id, "read")
            end,
            -- Rename only when pins are unlocked and the viewer may edit; else a click (R12).
            doubleclick = function(element)
                local location = Model.GetLocation(element.data.id)
                if location ~= nil and not data.locked and Model.CanEdit(location) then
                    data.focusName = true
                    ctx.Select(location.id, "edit")
                else
                    ctx.Select(element.data.id, "read")
                end
            end,
            rightClick = function(element)
                if ReleasedDragMoved() then return end
                ctx.ShowMenu(element, element.data.id)
            end,
            disc, name,
        }
    end

    -- Restyling a pin costs engine work even when nothing changed, so a pin is
    -- rebound only when its row (revision), selection, size or badge changed.
    local function BindPin(pin, location)
        local canOpen = location.imageId ~= "" and Model.CanOpenMap(location)
        local selected = data.selectedId == location.id
        local signature = table.concat({
            tostring(location.revision), tostring(selected), tostring(state.scale), tostring(canOpen),
        }, ":")
        if pin.data.signature == signature then return end
        pin.data.signature = signature
        local disc, hit = PinSize(location)
        local plateStyle = location.pinStyle == "plate"
        pin.data.u, pin.data.v = location.u, location.v
        pin.data.importance, pin.data.pinStyle = location.importance, location.pinStyle
        pin.data.disc:SetClass("collapsed", plateStyle)
        ShowPart(pin, "plate", plateStyle)
        local text = Copy.Literal(Model.DisplayName(location))
        local fontSize = (C.pinNameSize[location.importance] or C.pinNameSize.normal) * state.scale
        if plateStyle then
            pin.data.name:SetClass("collapsed", true)
            pin.selfStyle.width, pin.selfStyle.height = "auto", "auto"
            Session.SetText(pin.data.plate, text)
            pin.data.plate.selfStyle.fontSize = fontSize
        else
            pin.selfStyle.width, pin.selfStyle.height = hit, hit
            pin.data.disc.selfStyle.width, pin.data.disc.selfStyle.height = disc, disc
            pin.data.disc.selfStyle.halign, pin.data.disc.selfStyle.valign = "center", "center"
            pin.data.disc.selfStyle.cornerRadius = disc / 2
            local icon, isImage = PinIcon(location)
            if pin.data.glyph.bgimage ~= icon then pin.data.glyph.bgimage = icon end
            pin.data.glyph:SetClass("image", isImage)
            Session.SetText(pin.data.name, text)
            pin.data.name.selfStyle.fontSize = fontSize
            pin.data.name.selfStyle.y = (hit + disc) / 2 + 2
            pin.data.showName = NameVisible(pin.data)
            pin.data.name:SetClass("collapsed", not pin.data.showName)
        end
        -- Badges are centered on the corners of the disc's bounding box (or the
        -- plate's corners), outside the round disc, so the icon stays readable.
        local badge = C.pinBadgeSize * state.scale
        local inset = -badge / 2 + 2
        if not plateStyle then inset = (hit - disc) / 2 - badge / 2 end
        local function PlaceBadge(key, show, x)
            ShowPart(pin, key, show)
            if not show then return end
            local panel = pin.data[key]
            panel.selfStyle.width, panel.selfStyle.height = badge, badge
            panel.selfStyle.cornerRadius = badge / 2
            panel.selfStyle.x, panel.selfStyle.y = x, inset
        end
        -- The hidden badge is left-aligned and the map badge right-aligned, so their x offsets mirror.
        PlaceBadge("hiddenBadge", location.visibility == "hidden", inset)
        PlaceBadge("mapBadge", canOpen, -inset)
        pin:SetClass("hiddenPin", location.visibility == "hidden")
        pin:SetClass("selected", selected)
    end

    local function UpdatePins()
        local desired = {}
        local children = {} --- @type Panel[]
        if state.mapId ~= nil then
            for _, location in ipairs(Model.Children(state.mapId)) do
                desired[location.id] = true
                local pin = pins[location.id]
                if pin == nil or not pin.valid then
                    pin = CreatePin(location.id)
                    pins[location.id] = pin
                end
                BindPin(pin, location)
                children[#children + 1] = pin
            end
        end
        for id, pin in pairs(pins) do
            if not desired[id] then
                if pin.valid then pin:DestroySelf() end
                pins[id] = nil
            end
        end
        -- The Party is drawn above pins (D11a), so it goes last.
        children[#children + 1] = partyPanel
        local same = #children == #pinChildren
        for i = 1, #children do
            if not same then break end
            same = children[i] == pinChildren[i]
        end
        if not same then
            pinChildren = children
            pinLayer.children = children
        end
        state.pinsDirty = true
    end

    -- The Party --------------------------------------------------------------------------------

    local function UpdateParty()
        local party = Model.Party()
        local visible = party ~= nil and party.mapId == state.mapId
        partyPanel:SetClass("collapsed", not visible)
        partyPanel.data.party = visible and party or nil
        if not visible then return end
        local size = C.partySize * state.scale
        partyPanel.selfStyle.width, partyPanel.selfStyle.height = size, size
        partyPanel.data.disc.selfStyle.cornerRadius = size / 2
        -- Layout picks the label's side (above or below) from where the Party stands.
        partyPanel.data.labelAbove = nil
        Session.SetText(partyName, Copy.Literal(Model.PartyName()))
        local imageId = Model.PartyImageId()
        local icon = imageId ~= "" and imageId or C.iconParty
        if partyGlyph.bgimage ~= icon then partyGlyph.bgimage = icon end
        partyGlyph:SetClass("image", imageId ~= "")
        state.pinsDirty = true
    end

    partyGlyph = gui.Panel { classes = { "regionMapPartyGlyph" }, bgimage = C.iconParty, interactable = false }
    partyName = gui.Label {
        classes = { "regionMapPartyName" }, floating = true, interactable = false, text = "",
    }
    local partyDisc = gui.Panel { classes = { "regionMapPartyDisc" }, interactable = false, partyGlyph }

    -- Where the Party is drawn, in image units. At a Location the banner sits beside the
    -- pin, so this differs from party.u/v. Its x/y are offsets in the pin layer, measured against pinRef.
    local function PartyDrawnPoint(element, party)
        local ref = state.pinRef
        if ref ~= nil and state.layout ~= nil then
            local u, v = Tools.PanelToImage(ref, element.selfStyle.x + ref.viewWidth * 0.5,
                element.selfStyle.y + ref.viewHeight * 0.5)
            if u ~= nil and v ~= nil then return u, v end
        end
        return party.u, party.v
    end

    partyPanel = gui.Panel {
        classes = { "regionMapParty", "collapsed" },
        floating = true, halign = "center", valign = "center",
        swallowPress = true,
        data = { party = nil, disc = partyDisc, labelAbove = nil },
        hover = function(element)
            if state.drag ~= nil then return end
            local args = { party = Model.PartyName() }
            local id = Model.CanMovePartyOn(state.mapId or "") and "party.tooltip.move" or "party.tooltip"
            gui.Tooltip(Copy.T(id, args))(element)
        end,
        press = function(element)
            local party = element.data.party
            if party == nil or element:GetMouseButton(0) ~= true then return end
            element.tooltip = nil
            gui.SetFocus(canvas)
            -- A viewer who may not move the Party gets no drag at all (no ghost).
            if not Model.CanMovePartyOn(party.mapId) then return end
            -- Start from where the banner is drawn. With a tool on, the press only clicks (like a pin).
            local u, v = PartyDrawnPoint(element, party)
            BeginDrag("party", nil, u, v, data.tool == "none")
        end,
        click = function(element)
            if ReleasedDragMoved() then return end
            local party = element.data.party
            if party == nil then return end
            -- The ruler and the scale tool measure to the Party instead of selecting its Location.
            if data.tool == "ruler" or data.tool == "scale" then
                Tools.PlaceAt(ctx, PartyDrawnPoint(element, party))
                Layout()
                return
            end
            if party.locationId ~= nil then ctx.Select(party.locationId, "read") end
        end,
        partyDisc, partyName,
    }

    -- The nearest pin within the snap radius that the viewer can see (R3).
    local function SnapTarget(x, y)
        local layout = state.layout
        if layout == nil then return nil end
        local best, bestDistance = nil, C.partySnapRadius * state.scale
        for id, pin in pairs(pins) do
            if pin.valid then
                local px, py = ImageToPanel(layout, pin.data.u, pin.data.v)
                local distance = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
                if distance <= bestDistance then best, bestDistance = id, distance end
            end
        end
        return best
    end

    -- Layout -----------------------------------------------------------------------------------

    -- Center-aligned placement also keeps auto-sized name plates centered without knowing their size.
    local PlaceCentered = Tools.PlaceCentered

    -- Places the Party banner in the pin layer: at the drag preview while
    -- dragged, else at its point, or beside its pin when it is at a Location.
    local function PlaceParty(ref, drag)
        local party = partyPanel.data.party
        if party == nil then return end
        local x, y
        local besidePin = false
        if drag ~= nil then
            x, y = ImageToPanel(ref, drag.previewU, drag.previewV)
        else
            x, y = ImageToPanel(ref, party.u, party.v)
            -- At a Location the banner stands beside the pin, never on it (R3).
            local pin = party.locationId ~= nil and pins[party.locationId] or nil
            if pin ~= nil then
                local disc = (C.pinDisc[pin.data.importance] or C.pinDisc.normal) * state.scale
                x = x + disc / 2 + C.partySize * state.scale / 2 + 4
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

    Layout = function()
        if not ctx.IsAlive() or canvas == nil then return end
        local viewWidth, viewHeight = canvas.renderedWidth or 0, canvas.renderedHeight or 0
        local layout = nil
        if state.mapId ~= nil and IsFinite(state.imageWidth) and IsFinite(state.imageHeight) then
            layout = Tools.CalculateImageLayout(viewWidth, viewHeight, state.imageWidth --[[@as number]],
                state.imageHeight --[[@as number]], data.camera)
        end
        state.layout = layout
        -- Pins wait, invisible, until the image is laid out.
        if state.pinsShown ~= (layout ~= nil) then
            state.pinsShown = layout ~= nil
            pinLayer:SetClass("regionMapWaiting", layout == nil)
        end
        overlay.Layout(layout, state.imageWidth, state.imageHeight)
        if layout == nil then return end
        imagePanel.selfStyle.x, imagePanel.selfStyle.y = layout.x, layout.y
        imagePanel.selfStyle.width, imagePanel.selfStyle.height = layout.width, layout.height

        -- A pan keeps the image's size, so pins keep their places in the layer and
        -- only the layer moves. Zoom, a resize or a model change places them again.
        local ref = state.pinRef
        if state.pinsDirty or ref == nil or ref.width ~= layout.width or ref.height ~= layout.height
            or ref.viewWidth ~= layout.viewWidth or ref.viewHeight ~= layout.viewHeight then
            ref = layout
            state.pinRef, state.pinsDirty = layout, false
            for _, pin in pairs(pins) do
                if pin.valid then
                    PlaceCentered(pin, ref, ImageToPanel(ref, pin.data.u --[[@as number]], pin.data.v --[[@as number]]))
                    -- Declutter follows zoom; only touch the class when it flips.
                    if pin.data.pinStyle ~= "plate" then
                        local show = NameVisible(pin.data)
                        if show ~= pin.data.showName then
                            pin.data.showName = show
                            pin.data.name:SetClass("collapsed", not show)
                        end
                    end
                end
            end
            PlaceParty(ref, nil)
        end
        local layerX, layerY = layout.x - ref.x, layout.y - ref.y
        if layerX ~= state.layerX or layerY ~= state.layerY then
            state.layerX, state.layerY = layerX, layerY
            pinLayer.selfStyle.x, pinLayer.selfStyle.y = layerX, layerY
        end

        -- A dragged pin or Party follows the pointer (in the layer's frame, which is ref's).
        local drag = state.drag
        if drag ~= nil and drag.moved and drag.previewU ~= nil and drag.previewV ~= nil then
            if drag.kind == "pin" and drag.id ~= nil and pins[drag.id] ~= nil then
                PlaceCentered(pins[drag.id], ref, ImageToPanel(ref, drag.previewU, drag.previewV))
            elseif drag.kind == "party" then
                PlaceParty(ref, drag)
            end
        end
    end

    -- Image ------------------------------------------------------------------------------------

    CreateImagePanel = function(request, opacity)
        return gui.Panel {
            classes = { "regionMapImage" },
            floating = true, halign = "left", valign = "top", interactable = false,
            opacity = opacity,
            imageLoaded = function(element)
                if not ctx.IsAlive() or not element.valid or request ~= state.imageRequest then return end
                local width = tonumber(element.bgimageWidth)
                local height = tonumber(element.bgimageHeight)
                if (width == nil or width <= 0 or height == nil or height <= 0)
                    and element.bgsprite ~= nil and element.bgsprite.dimensions ~= nil then
                    width = tonumber(element.bgsprite.dimensions.x)
                    height = tonumber(element.bgsprite.dimensions.y)
                end
                if width == nil or height == nil or width <= 0 or height <= 0 then return end
                state.imageWidth, state.imageHeight = width, height
                if state.crossfade then state.fadeStart = dmhub.Time() end
                Layout()
                if state.animOnLoad ~= nil then
                    local target = state.animOnLoad
                    state.animOnLoad = nil
                    StartAnimation(target, nil)
                end
            end,
        }
    end

    RebuildChildren = function()
        local children = {} --- @type Panel[]
        if fadingPanel ~= nil and fadingPanel.valid then children[#children + 1] = fadingPanel end
        children[#children + 1] = imagePanel
        -- The route lies under pins and the Party; the ruler draws over them.
        children[#children + 1] = overlay.route
        children[#children + 1] = pinLayer
        children[#children + 1] = overlay.ruler
        children[#children + 1] = overlay.label
        children[#children + 1] = controls
        canvas.children = children
    end

    local function DropFadingPanel()
        if fadingPanel ~= nil and fadingPanel.valid then fadingPanel:DestroySelf() end
        fadingPanel = nil
        state.fadeStart = nil
        state.crossfade = false
        if imagePanel.valid then imagePanel.selfStyle.opacity = 1 end
    end

    -- Load a map's image. A "down" or "up" switch keeps the old image under the
    -- new one until the new one has loaded, then crossfades (D8c); a slow load
    -- shows the old map meanwhile instead of a blank canvas.
    local function LoadImage(map, how)
        FlushCamera()
        DropFadingPanel()
        local crossfade = (how == "down" or how == "up") and state.layout ~= nil and not Session.ReduceMotion()
        local fromId = state.mapId
        state.mapId, state.imageId, state.imageRevision = map.id, map.imageId, map.imageRevision
        state.imageWidth, state.imageHeight, state.layout = nil, nil, nil
        -- An animation still running ends here; its onDone runs once this map is set up.
        local interrupted = state.anim
        state.anim, state.animOnLoad = nil, nil
        local camera, restored = Session.ReadCamera(map)
        if how == "fit" or how == "jump" or not restored then camera = FitCamera() end
        data.camera = camera
        -- Going up starts zoomed into the pin we came from, then eases out to the saved view.
        local child = how == "up" and fromId ~= nil and Model.GetLocation(fromId) or nil
        if child ~= nil and child.parentId == map.id and not Session.ReduceMotion() then
            data.camera = { zoom = C.openZoom, centerX = child.u, centerY = child.v }
            state.animOnLoad = camera
        end
        state.imageRequest = state.imageRequest + 1
        if crossfade then
            fadingPanel = imagePanel
        elseif imagePanel ~= nil and imagePanel.valid then
            imagePanel:DestroySelf()
        end
        state.crossfade = crossfade
        imagePanel = CreateImagePanel(state.imageRequest, crossfade and 0 or 1)
        RebuildChildren()
        imagePanel.bgimageStreamed = map.imageId
        if interrupted ~= nil and interrupted.onDone ~= nil then interrupted.onDone() end
    end

    local function ClearMap()
        FlushCamera()
        DropFadingPanel()
        local interrupted = state.anim
        state.anim, state.animOnLoad = nil, nil
        state.mapId, state.imageId, state.imageRevision = nil, nil, nil
        state.imageWidth, state.imageHeight, state.layout = nil, nil, nil
        state.imageRequest = state.imageRequest + 1
        if imagePanel ~= nil and imagePanel.valid then imagePanel:DestroySelf() end
        imagePanel = CreateImagePanel(state.imageRequest, 1)
        RebuildChildren()
        if interrupted ~= nil and interrupted.onDone ~= nil then interrupted.onDone() end
    end

    -- Refresh from the model. A remote image replacement reloads the image.
    local function Bind()
        state.scale = Session.UIScale()
        state.showNames = Session.ShowNames()
        local map = ctx.CurrentMap()
        if map == nil then
            if state.mapId ~= nil then ClearMap() end
        elseif map.id ~= state.mapId or map.imageId ~= state.imageId or map.imageRevision ~= state.imageRevision then
            LoadImage(map, "restore")
        end
        UpdatePins()
        UpdateParty()
        overlay.Bind()
        namesButton:SetClass("on", state.showNames)
        Layout()
    end

    -- Input polling ------------------------------------------------------------------------------

    local function UpdateThinkRate(element)
        local active = state.hovered or element.hasFocus or state.drag ~= nil or state.anim ~= nil
            or state.fadeStart ~= nil or (state.mapId ~= nil and state.layout == nil)
        local rate = active and C.canvasThinkActive or C.canvasThinkIdle
        if element.thinkTime ~= rate then element.thinkTime = rate end
    end

    local function PollWheel(mouseX, mouseY)
        local layout = state.layout
        local wheel = dmhub.mouseWheel
        if not state.hovered or mouseX == nil or layout == nil or wheel == 0 or StopAnimation() then return end
        local beforeU = (mouseX - layout.x) / layout.width
        local beforeV = (mouseY - layout.y) / layout.height
        local oldZoom = data.camera.zoom
        local step = wheel > 0 and C.zoomWheelStep or 1 / C.zoomWheelStep
        data.camera.zoom = Clamp(oldZoom * step, C.minZoom, C.maxZoom)
        if data.camera.zoom == oldZoom then return end
        -- A layout only exists once the image size is known.
        local newLayout = Tools.CalculateImageLayout(layout.viewWidth, layout.viewHeight,
            state.imageWidth --[[@as number]], state.imageHeight --[[@as number]], data.camera)
        if newLayout == nil then return end
        data.camera.centerX = beforeU + (layout.viewWidth * 0.5 - mouseX) / newLayout.width
        data.camera.centerY = beforeV + (layout.viewHeight * 0.5 - mouseY) / newLayout.height
        Layout()
        SaveCamera()
    end

    local function PollDrag(element, mouseX, mouseY)
        local drag = state.drag
        if drag == nil then return end
        if not element:GetMouseButton(drag.button) then
            FinishDrag()
            return
        end
        local layout = state.layout
        if mouseX == nil or mouseY == nil or layout == nil then return end
        local dx, dy = mouseX - drag.startX, mouseY - drag.startY
        if not drag.moved and (math.abs(dx) >= C.canvasDragThreshold or math.abs(dy) >= C.canvasDragThreshold) then
            drag.moved = true
        end
        if not drag.moved then return end
        if drag.kind == "pan" then
            data.camera.centerX = drag.startCamera.centerX - dx / layout.width
            data.camera.centerY = drag.startCamera.centerY - dy / layout.height
        elseif drag.kind == "ruler" then
            if state.mapId ~= nil then
                data.ruler = {
                    mapId = state.mapId, u1 = drag.startU, v1 = drag.startV,
                    u2 = Clamp((mouseX - layout.x) / layout.width, 0, 1),
                    v2 = Clamp((mouseY - layout.y) / layout.height, 0, 1),
                }
            end
        elseif drag.allowed then
            drag.previewU = Clamp(drag.startU + dx / layout.width, 0, 1)
            drag.previewV = Clamp(drag.startV + dy / layout.height, 0, 1)
            if drag.kind == "party" then
                local snap = SnapTarget(mouseX, mouseY)
                if snap ~= drag.snapId then
                    if drag.snapId ~= nil and pins[drag.snapId] ~= nil then pins[drag.snapId]:SetClass("snapTarget", false) end
                    if snap ~= nil and pins[snap] ~= nil then pins[snap]:SetClass("snapTarget", true) end
                    drag.snapId = snap
                end
            end
        end
        Layout()
    end

    -- Right or middle button drags pan; a right press that never moved opens the menu.
    local function PollButtonPan(element, mouseX, mouseY)
        if state.drag ~= nil or not state.hovered or mouseX == nil then return end
        local button = nil
        if element:GetMouseButton(1) then button = 1 elseif element:GetMouseButton(2) then button = 2 end
        if button == nil or StopAnimation() then return end
        state.lastDrag = nil
        state.drag = {
            kind = "pan", button = button, startX = mouseX, startY = mouseY,
            startCamera = { zoom = data.camera.zoom, centerX = data.camera.centerX, centerY = data.camera.centerY },
            startU = 0, startV = 0, allowed = true, moved = false,
        }
    end

    local function PollKeys(element)
        if not element.hasFocus or state.layout == nil then
            state.keyEdges = {}
            return
        end
        local function KeyEdge(key)
            local down = dmhub.KeyPressed(key)
            local previous = state.keyEdges[key]
            state.keyEdges[key] = down
            return down and not previous
        end
        local horizontal, vertical = 0, 0
        if KeyEdge("LeftArrow") then horizontal = horizontal - 1 end
        if KeyEdge("RightArrow") then horizontal = horizontal + 1 end
        if KeyEdge("UpArrow") then vertical = vertical - 1 end
        if KeyEdge("DownArrow") then vertical = vertical + 1 end
        if horizontal == 0 and vertical == 0 then return end
        local coarse = dmhub.KeyPressed("LeftShift") or dmhub.KeyPressed("RightShift")
        local pixels = coarse and C.panCoarse or C.panFine
        data.camera.centerX = data.camera.centerX + horizontal * pixels / state.layout.width
        data.camera.centerY = data.camera.centerY + vertical * pixels / state.layout.height
        Layout()
        SaveCamera()
    end

    local function TickAnimation()
        local anim = state.anim
        if anim == nil then return end
        local t = Clamp((dmhub.Time() - anim.start) / C.transitionSeconds, 0, 1)
        data.camera = LerpCamera(anim.from, anim.to, t)
        Layout()
        if t >= 1 then
            state.anim = nil
            if not anim.noSave then SaveCamera() end
            if anim.onDone ~= nil then anim.onDone() end
        end
    end

    local function TickFade()
        if state.fadeStart == nil then return end
        local t = Clamp((dmhub.Time() - state.fadeStart) / C.transitionSeconds, 0, 1)
        if imagePanel.valid then imagePanel.selfStyle.opacity = t end
        if t >= 1 then DropFadingPanel() end
    end

    -- Camera controls fade to about 3:1 after the pointer rests (R9), never under Reduce motion.
    local function TickControlsFade(mouseX, mouseY)
        if state.hovered and mouseX ~= nil and (mouseX ~= state.lastPointerX or mouseY ~= state.lastPointerY) then
            state.lastPointerX, state.lastPointerY = mouseX, mouseY
            state.lastPointerMove = dmhub.Time()
        end
        local faded = not Session.ReduceMotion() and dmhub.Time() - state.lastPointerMove > C.controlsFadeSeconds
        if controls:HasClass("faded") ~= faded then controls:SetClass("faded", faded) end
    end

    -- Controls -----------------------------------------------------------------------------------

    namesButton = Session.IconButton("region-map-names", C.iconNames, Copy.T("cam.names"), function(element)
        state.showNames = not state.showNames
        Session.SetShowNames(state.showNames)
        element:SetClass("on", state.showNames)
        UpdatePins()
        Layout()
    end)
    controls = gui.Panel {
        classes = { "regionMapCameraControls" }, floating = true,
        Session.IconButton("region-map-fit", C.iconFit, Copy.T("cam.fit"), function()
            StartAnimation(FitCamera(), function() SaveCamera() end)
        end),
        Session.IconButton("region-map-zoom-out", C.iconZoomOut, Copy.T("cam.zoomOut"), function()
            Zoom(1 / C.zoomButtonStep)
        end),
        Session.IconButton("region-map-zoom-in", C.iconZoomIn, Copy.T("cam.zoomIn"), function()
            Zoom(C.zoomButtonStep)
        end),
        namesButton,
    }

    pinChildren = { partyPanel }
    pinLayer = gui.Panel { classes = { "regionMapOverlay" }, floating = true, partyPanel }
    imagePanel = CreateImagePanel(0, 1)

    canvas = gui.Panel {
        id = "region-map-canvas",
        classes = { "regionMapCanvas" },
        bgimage = "panels/square.png", clip = true, flow = "none",
        -- Not draggable (drags are polled); swallowPress keeps a press on the map
        -- from reaching the window, which would otherwise drag the whole window.
        swallowPress = true,
        canFocus = true, thinkTime = C.canvasThinkIdle,
        hover = function(element)
            state.hovered = true
            UpdateThinkRate(element)
        end,
        dehover = function(element)
            state.hovered = false
            UpdateThinkRate(element)
        end,
        focus = UpdateThinkRate,
        defocus = UpdateThinkRate,
        press = function(element)
            gui.SetFocus(element)
            -- A press on the map closes Search or Settings, like a click outside a menu.
            if data.popover ~= nil then ctx.SetPopover(nil) end
            if element:GetMouseButton(0) then
                -- With the ruler on, a left drag measures (R7); right or middle drags still pan.
                local x, y = PointerInCanvas()
                local u, v = nil, nil
                if data.tool == "ruler" and state.layout ~= nil and x ~= nil and y ~= nil then
                    u, v = Tools.PanelToImage(state.layout, x, y)
                end
                if u ~= nil and v ~= nil then
                    BeginDrag("ruler", nil, u, v, true)
                else
                    BeginDrag("pan", nil, 0, 0, true)
                end
            end
            UpdateThinkRate(element)
        end,
        click = function()
            if ReleasedDragMoved() then return end
            if data.tool == "none" or state.layout == nil then return end
            local x, y = PointerInCanvas()
            if x == nil or y == nil then return end
            Tools.PlaceAt(ctx, Tools.PanelToImage(state.layout, x, y))
            Layout()
        end,
        rightClick = function(element)
            if ReleasedDragMoved() then return end
            local x, y = PointerInCanvas()
            if x == nil or y == nil or state.layout == nil then return end
            local u, v = Tools.PanelToImage(state.layout, x, y)
            if u == nil or v == nil then return end
            local entries = Tools.MapMenu(ctx, u, v)
            if #entries == 0 then return end
            for _, entry in ipairs(entries) do
                local action = entry.click
                entry.click = function()
                    element.popup = nil
                    action()
                end
            end
            element.popupsInheritStyles = false
            element.popup = gui.ContextMenu { entries = entries }
        end,
        rendered = function() Layout() end,
        think = function(element)
            if not ctx.IsAlive() then return end
            local mouseX, mouseY = PointerInCanvas()
            PollButtonPan(element, mouseX, mouseY)
            PollWheel(mouseX, mouseY)
            PollDrag(element, mouseX, mouseY)
            PollKeys(element)
            TickAnimation()
            TickFade()
            TickControlsFade(mouseX, mouseY)
            UpdateThinkRate(element)
        end,
        regionMapSaveCamera = function(element)
            state.cameraSaveScheduled = false
            if GestureActive() or state.anim ~= nil then
                state.cameraSaveScheduled = true
                element:ScheduleEvent("regionMapSaveCamera", C.cameraSaveDelay)
                return
            end
            FlushCamera()
        end,
        destroy = function() FlushCamera() end,

        bind = function() Bind() end,
        showMap = function(_, how)
            state.scale = Session.UIScale()
            state.showNames = Session.ShowNames()
            state.drag = nil
            local map = ctx.CurrentMap()
            if map == nil then
                ClearMap()
            elseif map.id == state.mapId and map.imageId == state.imageId and map.imageRevision == state.imageRevision then
                if how == "fit" or how == "jump" then StartAnimation(FitCamera(), function() SaveCamera() end) end
            else
                LoadImage(map, how or "restore")
            end
            UpdatePins()
            UpdateParty()
            Layout()
        end,
        animateInto = function(_, id, onDone)
            local location = Model.GetLocation(id)
            if location == nil or location.parentId ~= state.mapId or state.layout == nil then
                StopAnimation()
                onDone()
                return
            end
            StartAnimation({
                zoom = math.max(data.camera.zoom, C.openZoom), centerX = location.u, centerY = location.v,
            }, onDone, true)
        end,
        keepVisible = function(_, id, inset)
            local pin = pins[id]
            local layout = state.layout
            if pin == nil or layout == nil or inset <= 0 then return end
            local x = ImageToPanel(layout, pin.data.u, pin.data.v)
            local limit = layout.viewWidth - inset - 40
            if x <= limit then return end
            data.camera.centerX = data.camera.centerX + (x - limit) / layout.width
            Layout()
            SaveCamera()
        end,
        centerOn = function(_, id)
            local location = Model.GetLocation(id)
            if location == nil or location.parentId ~= state.mapId or StopAnimation() then return end
            data.camera.centerX, data.camera.centerY = location.u, location.v
            Layout()
            SaveCamera()
        end,
        relayout = function() Layout() end,
        cancelGesture = function()
            local drag = state.drag
            state.drag = nil
            if drag ~= nil and drag.snapId ~= nil and pins[drag.snapId] ~= nil then pins[drag.snapId]:SetClass("snapTarget", false) end
            if drag ~= nil and drag.kind == "pan" then data.camera = drag.startCamera end
            state.pinsDirty = true
            Layout()
        end,

        imagePanel, pinLayer, controls,
    }
    return canvas
end
