local mod = dmhub.GetModLoading()

--- @class OverlandMapPinLayer: GameType
--- @field new fun(o?: table): OverlandMapPinLayer
OverlandMapPinLayer = RegisterGameType("OverlandMapPinLayer")
local C, Model = OverlandMapConstants, OverlandMapModel
local Session, Copy = OverlandMapControls, OverlandMapCopy
local Clamp, IsFinite = Model.Clamp, Model.IsFinite
local ImageToPanel = OverlandMapGeometry.ImageToPanel

-- The icon of a pin: a curated key, a library image id, or the default glyph.
local function PinIcon(location)
    local key = location.icon
    if C.pinIcons[key] ~= nil then return C.pinIcons[key], false end
    if key ~= "" then return key, true end
    return C.pinIcons[C.defaultPinIcon], false
end

--- @param ctx OverlandMapContext
--- @param state OverlandMapCanvasState
--- @param input table
function OverlandMapPinLayer.Create(ctx, state, input)
    local data = ctx.data
    local pins, pinChildren = {}, {}
    local pinLayer = gui.Panel { classes = { "overlandMapOverlay" }, floating = true }
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

    -- The name plate and the badges are made the first time a pin shows them:
    -- most pins never do, and a dense map builds hundreds of pins at once.
    local function SetPinChildren(pin)
        local children = { pin.data.disc, pin.data.name }
        for _, key in ipairs({ "plate", "mapBadge", "hiddenBadge" }) do
            if pin.data[key] ~= nil then children[#children + 1] = pin.data[key] end
        end
        pin.children = children
    end

    local function PinPart(pin, key)
        local part = pin.data[key]
        if part ~= nil then return part end
        if key == "plate" then
            part = OverlandMapPinText.CreateName(true, false, pin)
        else
            local isMap = key == "mapBadge"
            part = gui.Panel {
                classes = { "overlandMapPinBadge" }, floating = true, halign = isMap and "right" or "left",
                valign = "top", interactable = false,
                gui.Panel {
                    classes = { "overlandMapPinBadgeGlyph" }, bgimage = isMap and C.iconMap or C.iconEyeSlash,
                    interactable = false,
                },
            }
        end
        pin.data[key] = part
        -- Later children draw on top, so badges stay above the plate whatever order they were made in.
        SetPinChildren(pin)
        return part
    end

    local function ShowPart(pin, key, show)
        if show then
            Session.SetClassIf(PinPart(pin, key), "collapsed", false)
        elseif pin.data[key] ~= nil then
            Session.SetClassIf(pin.data[key], "collapsed", true)
        end
    end

    local function CreatePin(id)
        local glyph = gui.Panel { classes = { "overlandMapPinGlyph" }, interactable = false }
        local disc = gui.Panel { classes = { "overlandMapPinDisc" }, interactable = false, glyph }
        local name = OverlandMapPinText.CreateName(false, true, nil)
        -- Centered so x/y place the pin's middle on its point (see PlaceCentered).
        return gui.Panel {
            classes = { "overlandMapPin" },
            floating = true, halign = "center", valign = "center",
            swallowPress = true,
            data = {
                id = id, disc = disc, glyph = glyph, name = name, plate = nil,
                mapBadge = nil, hiddenBadge = nil, u = 0, v = 0, signature = nil, showName = nil,
            },
            hover = input.hover,
            dehover = input.dehover,
            destroy = input.destroy,
            press = input.press,
            click = input.click,
            doubleclick = input.doubleclick,
            rightClick = input.rightClick,
            disc, name,
        }
    end

    -- Restyling a pin costs engine work even when nothing changed, so a pin is
    -- rebound only when its row (revision), selection, size or badge changed.
    -- Returns true when it did, so the pins are placed again.
    local function BindPin(pin, location, format, formatKey)
        local canOpen = location.imageId ~= "" and Model.CanOpenMap(location)
        local selected = data.selectedId == location.id
        local signature = table.concat({
            tostring(location.revision), tostring(selected), tostring(state.scale), tostring(canOpen), formatKey,
        }, ":")
        if pin.data.signature == signature then return false end
        pin.data.signature = signature
        local disc, hit = PinSize(location)
        local plateStyle = location.pinStyle == "plate"
        pin.data.u, pin.data.v = location.u, location.v
        pin.data.hit = hit
        pin.data.importance, pin.data.pinStyle = location.importance, location.pinStyle
        pin.data.disc:SetClass("collapsed", plateStyle)
        ShowPart(pin, "plate", plateStyle)
        local text = Model.DisplayName(location)
        pin.data.anchor = plateStyle and format.anchor or "center"
        pin.selfStyle.halign = pin.data.anchor
        if plateStyle then
            pin.data.name:SetClass("collapsed", true)
            pin.selfStyle.width, pin.selfStyle.height = "auto", "auto"
            OverlandMapPinText.Apply(pin.data.plate, text, format, location.importance, true, state.scale)
        else
            pin.selfStyle.width, pin.selfStyle.height = hit, hit
            pin.data.disc.selfStyle.width, pin.data.disc.selfStyle.height = disc, disc
            pin.data.disc.selfStyle.halign, pin.data.disc.selfStyle.valign = "center", "center"
            pin.data.disc.selfStyle.cornerRadius = disc / 2
            local icon, isImage = PinIcon(location)
            if pin.data.glyph.bgimage ~= icon then pin.data.glyph.bgimage = icon end
            pin.data.glyph:SetClass("image", isImage)
            OverlandMapPinText.Apply(pin.data.name, text, format, location.importance, false, state.scale)
            pin.data.name.selfStyle.halign = format.anchor
            pin.data.name.selfStyle.x = format.anchor == "left" and hit / 2 or format.anchor == "right" and -hit / 2 or 0
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
        return true
    end

    local function UpdatePins()
        -- Every refresh comes here, and reading 250 rows costs ms even when none changed.
        -- A pin's look depends only on these, so the same inputs mean the same pins.
        local format, formatKey = OverlandMapPinText.Format(Model.GetLocation(state.mapId))
        local inputs = table.concat({ tostring(state.mapId), tostring(Model.Revision()), tostring(data.selectedId),
            tostring(state.scale), tostring(Model.IsDirector()), formatKey }, "|")
        if inputs == state.pinInputs then return end
        state.pinInputs = inputs
        local desired = {}
        local children = {} --- @type Panel[]
        -- Placing every pin again costs a few ms on a full map; only do it when one changed.
        local changed = false
        if state.mapId ~= nil then
            for _, location in ipairs(Model.Children(state.mapId)) do
                desired[location.id] = true
                local pin = pins[location.id]
                if pin == nil or not pin.valid then
                    pin = CreatePin(location.id)
                    pins[location.id] = pin
                end
                if BindPin(pin, location, format, formatKey) then changed = true end
                children[#children + 1] = pin
            end
        end
        for id, pin in pairs(pins) do
            if not desired[id] then
                if pin.valid then pin:DestroySelf() end
                pins[id] = nil
                changed = true
            end
        end
        -- Assigning children costs engine work, so it happens only when the pin list changed.
        local same = #children == #pinChildren
        for i = 1, #children do
            if not same then break end
            same = children[i] == pinChildren[i]
        end
        if not same then
            pinChildren = children
            pinLayer.children = children
            changed = true
        end
        if changed then state.pinsDirty = true end
    end

    local function PlacePin(pin, layout, u, v)
        local x, y = ImageToPanel(layout, u, v)
        -- halign selects which edge sits at the Location point; the point itself never moves.
        local anchor = pin.data.anchor
        local origin = anchor == "left" and 0 or anchor == "right" and layout.viewWidth or layout.viewWidth / 2
        OverlandMapDrawing.PositionPanel(pin, x - origin, y - layout.viewHeight / 2)
    end

    -- True when (x, y) is on a pin's hit area: pins win over the paths under them (Q4).
    local function OnPin(x, y)
        local layout = state.layout
        if layout == nil then return false end
        for _, pin in pairs(pins) do
            if pin.valid then
                local px, py = ImageToPanel(layout, pin.data.u, pin.data.v)
                local radius = (pin.data.hit or C.pinHitMin * state.scale) / 2
                if math.abs(px - x) <= radius and math.abs(py - y) <= radius then return true end
            end
        end
        return false
    end

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

    return {
        layer = pinLayer, items = pins, Bind = UpdatePins, HitTest = OnPin, SnapTarget = SnapTarget,
        SetPreview = PlacePin,
        Layout = function(ref)
            for _, pin in pairs(pins) do
                if pin.valid then
                    PlacePin(pin, ref, pin.data.u, pin.data.v)
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
        end,
        Destroy = function() if pinLayer.valid then pinLayer:DestroySelf() end end,
    }
end
