local mod = dmhub.GetModLoading()

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
--- The native input gate failed right-button dragging; one controller polls all gestures.
--- @class OverlandMapCanvas: GameType
--- @field new fun(o?: table): OverlandMapCanvas
OverlandMapCanvas = RegisterGameType("OverlandMapCanvas")
local C = OverlandMapConstants
local Model = OverlandMapModel
local Tools = OverlandMapCanvasTools
local Session = OverlandMapControls
local Copy = OverlandMapCopy

local Clamp = Model.Clamp
local IsFinite = Model.IsFinite
local ImageToPanel = OverlandMapGeometry.ImageToPanel

--- A press on the map, a pin or the Party, tracked until the button is released.
--- @class OverlandMapDrag
--- @field kind "pan"|"pin"|"party"|"ruler"|"bend"|"labelMove"|"labelResize"|"labelRotate"|"aidMove"|"aidResize"|"aidRotate"
--- @field aidStart nil|table
--- @field aidChanges nil|table
--- @field aidMapId nil|string
--- @field labelStart nil|OverlandMapLabelRecord
--- @field labelChanges nil|table
--- @field labelDistance nil|number
--- @field labelPointerAngle nil|number
--- @field id nil|string the pin being dragged, or the path whose bend is
--- @field index nil|integer bend drags: the bend, or the segment whose "+" was pulled
--- @field insert nil|boolean bend drags: a new bend from a "+"
--- @field button integer 0 left, 1 right, 2 middle
--- @field startX number
--- @field startY number
--- @field startCamera OverlandMapCamera
--- @field startU number
--- @field startV number
--- @field allowed boolean the viewer may move what was pressed
--- @field moved boolean past the drag threshold
--- @field previewU nil|number
--- @field previewV nil|number
--- @field snapId nil|string the pin a dropped Party would snap to

--- A camera move animated in think (Open map, going up).
--- @class OverlandMapCameraAnimation
--- @field from OverlandMapCamera
--- @field to OverlandMapCamera
--- @field start number dmhub.Time() when it began
--- @field onDone nil|fun()
--- @field noSave boolean true when the end view must not become the map's saved camera

--- The Party banner walking the line of a leg or stop that was just logged.
--- @class OverlandMapPartyMove
--- @field route OverlandMapRoutePoint[] the entry's line in travel order, image units
--- @field lengths number[] each segment's length in image pixels, so the walk keeps one speed
--- @field total number
--- @field start number dmhub.Time() when it began
--- @field seconds number
--- @field startOffset number px right of the line at the start (beside the pin it left)
--- @field endOffset number px right of the line at the end (beside the pin it reaches)
--- @field u number where the banner is drawn now
--- @field v number
--- @field offset number

--- What the Party stood on, kept to tell which logged move explains a change.
--- @class OverlandMapPartySpot
--- @field locationId nil|string
--- @field pathId nil|string

--- The canvas's own view state: what is loaded and what the pointer is doing.
--- @class OverlandMapCanvasState
--- @field mapId nil|string the map whose image is loaded
--- @field imageId nil|string
--- @field imageRevision nil|integer
--- @field imageWidth nil|number known once the image has loaded
--- @field imageHeight nil|number
--- @field layout nil|OverlandMapLayout nil until the image has loaded
--- @field imageRequest integer drops imageLoaded events of replaced image panels
--- @field imageStatus nil|string
--- @field crossfade boolean the new image fades in over the old one once loaded
--- @field fadeStart nil|number
--- @field animOnLoad nil|OverlandMapCamera camera to ease to once the image loads (going up)
--- @field drag nil|OverlandMapDrag
--- @field lastDrag nil|OverlandMapDrag the drag the latest release ended
--- @field showNames boolean cached Show names preference
--- @field anim nil|OverlandMapCameraAnimation
--- @field cameraDirty boolean
--- @field cameraSaveScheduled boolean
--- @field hovered boolean
--- @field lastPointerX nil|number
--- @field lastPointerY nil|number
--- @field lastPointerMove number
--- @field keyEdges table<string, boolean>
--- @field scale number Font Size scale for pins and the Party
--- @field pinsShown nil|boolean whether pins were last shown (nil forces an update)
--- @field pinRef nil|OverlandMapLayout the layout pins were last placed against
--- @field pinsDirty boolean pins must be placed again on the next Layout
--- @field pinInputs string what the pins were last bound from
--- @field lastWheel number dmhub.Time() of the last wheel zoom step
--- @field zoomMoving boolean the last Layout stretched the line layers mid-zoom
--- @field imageSizeW nil|number the size last written to the image and border (nil: write it)
--- @field imageSizeH nil|number
--- @field layerX number the pin layer's offset from pinRef (the pan since then)
--- @field layerY number
--- @field border "none"|"fade"|"torn"|"frame" the open map's border
--- @field fadeShown nil|boolean whether the Soft fade was last shown (nil forces an update)
--- @field hoverPathId nil|string the path under the pointer, which shows its label (F3)
--- @field hoverX nil|number the pointer position the hover was last worked out for
--- @field hoverY nil|number
--- @field draftKey string what the drawn draft line was last placed for
--- @field move nil|OverlandMapPartyMove the banner walking a leg, drawn instead of its stored place
--- @field partyKey string where the Party stands, to notice a change
--- @field partyLook string where the banner was last placed and how it looked
--- @field partyNow nil|OverlandMapPartySpot
--- @field partyBefore nil|OverlandMapPartySpot where it stood before its latest change
--- @field moveWatchUntil number dmhub.Time() until which a newly logged leg may still play
--- @field movedIds table<string, boolean> log entries already played

--- Build the canvas component.
--- @param ctx OverlandMapContext
--- @return Panel
function OverlandMapCanvas.Create(ctx)
    local data = ctx.data
    local canvas
    -- Pins and the Party live in one layer that slides as a whole while the
    -- map pans, so a pan moves one panel instead of every pin. The
    -- layer must stay interactable: a non-interactable layer stops its pins' clicks.
    local pinLayer
    local partyPanel
    local controls
    local namesButton
    local labelsButton
    local overlay = OverlandMapGuideLayer.Create(ctx)
    -- Point crawl paths draw above the border and below the route and pins.
    local pathLayer = OverlandMapPathLayer.Create()
    local labelLayer = OverlandMapLabelLayer.Create(ctx)
    local aidLayer = OverlandMapAidLayer.Create(ctx)
    local pins
    local pinRenderer
    local state = OverlandMapSession.CanvasState()
    local gestures = OverlandMapGestures.Create(ctx.IsAlive)
    local releaseSession
    local PathTool = OverlandMapPathTool

    local Layout

    local camera = OverlandMapCameraController.Create(ctx, state, function() Layout() end,
        function() canvas:ScheduleEvent("overlandMapSaveCamera", C.cameraSaveDelay) end,
        function() if canvas ~= nil then canvas.thinkTime = C.canvasThinkActive end end)
    local FlushCamera, SaveCamera, FitCamera = camera.Flush, camera.Save, camera.Fit
    local StopAnimation, StartAnimation, Zoom = camera.Stop, camera.Animate, camera.Zoom
    local TickAnimation = camera.Tick
    local artwork = OverlandMapArtwork.MapLayer(ctx, state, {
        FlushCamera = FlushCamera, FitCamera = FitCamera, Animate = StartAnimation,
        Layout = function() Layout() end,
        Wake = function() if canvas then canvas.thinkTime = C.canvasThinkActive end end,
    })
    local LoadImage, ClearMap, TickFade = artwork.Bind, artwork.Clear, artwork.Tick
    local function WheelZoom(delta, x, y)
        if gestures.current and (gestures.current.labelStart or gestures.current.aidStart) then return end
        camera.Wheel(delta, x, y)
    end

    local layers = { path = pathLayer, labels = labelLayer, aids = aidLayer }
    local input = OverlandMapGestures.Canvas(ctx, state, gestures, layers, {
        Canvas = function() return canvas end, Layout = function() Layout() end, camera = camera,
    })
    local PointerInCanvas, GestureActive, GesturePermitted = input.Pointer, input.Active, input.Permitted
    local BeginDrag, BeginLabelDrag, TrySelectionHandle = input.Begin, input.BeginLabel, input.SelectionHandle
    local ReleasedDragMoved = input.Released
    local PollDrag, PollButtonPan, PollKeys = input.Poll, input.PollButtons, input.PollKeys

    pinRenderer = OverlandMapPinLayer.Create(ctx, state, input.PinHandlers)
    pins = pinRenderer.items
    layers.pins, layers.pin = pins, pinRenderer
    local UpdatePins, PlacePin = pinRenderer.Bind, pinRenderer.SetPreview
    local OnPin, SnapTarget = pinRenderer.HitTest, pinRenderer.SnapTarget

    local partyRenderer = OverlandMapPartyLayer.Create(ctx, state, pins, input.PartyHandlers,
        function() Layout() end, function() canvas.thinkTime = C.canvasThinkActive end)
    layers.party = partyRenderer
    partyPanel = partyRenderer.layer
    local UpdateParty, PlaceParty, TickPartyMove = partyRenderer.Bind, partyRenderer.Layout, partyRenderer.Tick

    -- Layout -----------------------------------------------------------------------------------

    -- Center-aligned placement also keeps auto-sized name plates centered without knowing their size.
    local PlaceCentered = OverlandMapDrawing.PlaceCentered

    Layout = function()
        if not ctx.IsAlive() or canvas == nil then return end
        local viewWidth, viewHeight = canvas.renderedWidth or 0, canvas.renderedHeight or 0
        local layout = nil
        if state.mapId ~= nil and IsFinite(state.imageWidth) and IsFinite(state.imageHeight) then
            layout = OverlandMapGeometry.CalculateImageLayout(viewWidth, viewHeight, state.imageWidth --[[@as number]],
                state.imageHeight --[[@as number]], data.camera, data.panelInset)
        end
        state.layout = layout
        -- Pins wait, invisible, until the image is laid out.
        if state.pinsShown ~= (layout ~= nil) then
            state.pinsShown = layout ~= nil
            pinLayer:SetClass("overlandMapWaiting", layout == nil)
        end
        -- While a zoom is in motion the line and route layers stretch instead of being
        -- placed again; think places them for real once it settles (ZoomSettled).
        local moving = state.anim ~= nil or dmhub.Time() - state.lastWheel < C.zoomSettleSeconds
        state.zoomMoving = moving
        overlay.Layout(layout, state.imageWidth, state.imageHeight, moving)
        pathLayer.Layout(layout, state.scale, moving)
        labelLayer.Layout(layout)
        aidLayer.Metrics(state.imageWidth, state.imageHeight)
        aidLayer.Layout(layout)
        artwork.Layout(layout)
        if layout == nil then return end

        -- A pan keeps the image's size, so pins keep their places in the layer and
        -- only the layer moves. Zoom, a resize or a model change places them again.
        local ref = state.pinRef
        if state.pinsDirty or ref == nil or ref.width ~= layout.width or ref.height ~= layout.height
            or ref.viewWidth ~= layout.viewWidth or ref.viewHeight ~= layout.viewHeight then
            ref = layout
            state.pinRef, state.pinsDirty = layout, false
            pinRenderer.Layout(ref)
            PlaceParty(ref, nil)
        end
        local layerX, layerY = layout.x - ref.x, layout.y - ref.y
        if layerX ~= state.layerX or layerY ~= state.layerY then
            state.layerX, state.layerY = layerX, layerY
            pinLayer.x, pinLayer.y = layerX, layerY
        end

        -- A dragged pin or Party follows the pointer (in the layer's frame, which is ref's).
        local drag = gestures.current
        if drag ~= nil and drag.moved and drag.previewU ~= nil and drag.previewV ~= nil then
            if drag.kind == "pin" and drag.id ~= nil and pins[drag.id] ~= nil then
                PlacePin(pins[drag.id], ref, drag.previewU, drag.previewV)
            elseif drag.kind == "party" then
                PlaceParty(ref, drag)
            end
        end
    end

    -- Paths of the open map, with the hovered and selected ones marked.
    local function BindPaths()
        pathLayer.Bind(state.mapId)
        local open = data.panelMode == "path" or data.panelMode == "pathEdit"
        local selected = open and data.selectedPathId or nil
        pathLayer.SetFocus(state.hoverPathId, selected, state.showNames)
        -- A handle drag keeps its preview until it is dropped.
        if gestures.current == nil or gestures.current.kind ~= "bend" then pathLayer.SetHandles(PathTool.HandlesFor(ctx), nil) end
    end

    -- The line being drawn follows the pointer from its last point.
    local function UpdateDraft(mouseX, mouseY)
        local layout = state.layout
        local points, look = nil, nil
        if layout ~= nil then points, look = PathTool.DraftPoints(ctx) end
        local cursor = nil
        if points ~= nil and layout ~= nil and state.hovered and mouseX ~= nil and mouseY ~= nil then
            cursor = {
                u = Clamp((mouseX - layout.x) / layout.width, 0, 1), v = Clamp((mouseY - layout.y) / layout.height, 0, 1),
            }
        end
        local key = ""
        if points ~= nil then
            local last = points[#points]
            key = table.concat({ #points, last.u, last.v, tostring(cursor and cursor.u), tostring(cursor and cursor.v) }, ":")
        end
        if key == state.draftKey then return end
        state.draftKey = key
        pathLayer.SetPreview(points, cursor, look)
    end

    -- Refresh from the model. A remote image replacement reloads the image.
    local function Bind()
        state.scale = Session.UIScale()
        state.showNames = OverlandMapPreferences.ShowNames()
        local map = ctx.CurrentMap()
        if map == nil then
            if state.mapId ~= nil then ClearMap() end
        elseif map.id ~= state.mapId or map.imageId ~= state.imageId or map.imageRevision ~= state.imageRevision then
            LoadImage(map, "restore")
        end
        state.border = map ~= nil and Model.Border(map) or "none"
        UpdatePins()
        UpdateParty()
        overlay.Bind()
        BindPaths()
        labelLayer.Bind(state.mapId)
        aidLayer.Bind(map)
        namesButton:SetClass("on", state.showNames)
        labelsButton:SetClass("on", OverlandMapPreferences.ShowLabels())
        Layout()
    end

    -- Input polling ------------------------------------------------------------------------------

    local function UpdateThinkRate(element)
        local active = state.hovered or element.hasFocus or gestures.current ~= nil or state.anim ~= nil
            or state.move ~= nil or state.fadeStart ~= nil or (state.mapId ~= nil and state.layout == nil)
            or state.zoomMoving
        local rate = active and C.canvasThinkActive or C.canvasThinkIdle
        if element.thinkTime ~= rate then element.thinkTime = rate end
    end

    -- The path under the pointer, or nil (tools, drags and pins take precedence).
    local function PathUnder(x, y)
        if x == nil or y == nil or state.layout == nil or data.tool ~= "none" or OnPin(x, y) then return nil end
        return pathLayer.HitTest(state.layout, x, y, state.scale)
    end

    -- Hovering a path shows its label (F3); worked out only when the pointer moves.
    local function PollPathHover(mouseX, mouseY)
        local hover = nil
        if state.hovered and gestures.current == nil and mouseX ~= nil then
            if mouseX == state.hoverX and mouseY == state.hoverY then return end
            hover = PathUnder(mouseX, mouseY)
        end
        state.hoverX, state.hoverY = mouseX, mouseY
        if hover == state.hoverPathId then return end
        state.hoverPathId = hover
        local selected = (data.panelMode == "path" or data.panelMode == "pathEdit") and data.selectedPathId or nil
        pathLayer.SetFocus(hover, selected, state.showNames)
        Layout()
    end

    -- The wheel stopped a moment ago: place the stretched lines for real.
    local function ZoomSettled()
        if state.zoomMoving and state.anim == nil and dmhub.Time() - state.lastWheel >= C.zoomSettleSeconds then
            Layout()
        end
    end

    -- Camera controls fade to about 3:1 after the pointer rests (R9), never under Reduce motion.
    local function TickControlsFade(mouseX, mouseY)
        if state.hovered and mouseX ~= nil and (mouseX ~= state.lastPointerX or mouseY ~= state.lastPointerY) then
            state.lastPointerX, state.lastPointerY = mouseX, mouseY
            state.lastPointerMove = dmhub.Time()
        end
        local faded = not OverlandMapPreferences.ReduceMotion() and dmhub.Time() - state.lastPointerMove > C.controlsFadeSeconds
        Session.SetClassIf(controls, "faded", faded)
    end

    -- Controls -----------------------------------------------------------------------------------

    namesButton = Session.IconButton("overland-map-names", C.iconNames, Copy.T("cam.names"), function(element)
        state.showNames = not state.showNames
        OverlandMapPreferences.SetShowNames(state.showNames)
        element:SetClass("on", state.showNames)
        UpdatePins()
        BindPaths()
        Layout()
    end)
    labelsButton = Session.IconButton("overland-map-labels", "phosphor/text-t.png", Copy.T("label.show"), function(element)
        OverlandMapPreferences.SetShowLabels(not OverlandMapPreferences.ShowLabels())
        element:SetClass("on", OverlandMapPreferences.ShowLabels())
        ctx.RefreshAll()
    end)
    controls = gui.Panel {
        classes = { "overlandMapCameraControls" }, floating = true,
        Session.IconButton("overland-map-fit", C.iconFit, Copy.T("cam.fit"), function()
            StartAnimation(FitCamera(), function() SaveCamera() end)
        end),
        Session.IconButton("overland-map-zoom-out", C.iconZoomOut, Copy.T("cam.zoomOut"), function()
            Zoom(1 / C.zoomButtonStep)
        end),
        Session.IconButton("overland-map-zoom-in", C.iconZoomIn, Copy.T("cam.zoomIn"), function()
            Zoom(C.zoomButtonStep)
        end),
        namesButton,
        labelsButton,
    }

    pinLayer = gui.Panel { classes = { "overlandMapOverlay" }, floating = true, pinRenderer.layer, partyPanel }

    canvas = gui.Panel {
        id = "overland-map-canvas",
        classes = { "overlandMapCanvas" },
        enter = function(element) if not mod.unloaded and ctx.HandleEnter then ctx.HandleEnter(element) end end,
        bgimage = "panels/square.png", clip = true, flow = "none",
        -- Not draggable (drags are polled); swallowPress keeps a press on the map
        -- from reaching the window, which would otherwise drag the whole window.
        swallowPress = true,
        canFocus = true, thinkTime = C.canvasThinkIdle,
        data = { labelLayer = labelLayer, aidLayer = aidLayer,
            hasGesture = function() return gestures.current ~= nil end,
            visibleNames = function()
                local count = 0
                for _, pin in pairs(pins) do if pin.data.pinStyle == "plate" or pin.data.showName then count = count + 1 end end
                return count
            end },
        hover = function(element)
            state.hovered = true
            UpdateThinkRate(element)
        end,
        dehover = function(element)
            state.hovered = false
            UpdateThinkRate(element)
        end,
        focus = UpdateThinkRate,
        defocus = function(element)
            if gestures.current then element:FireEvent("cancelGesture") end
            UpdateThinkRate(element)
        end,
        -- Use panel-scoped wheel events; dmhub.mouseWheel only reads the main window.
        wheel = function(element, delta)
            if ctx.IsAlive() then
                local mouseX, mouseY = PointerInCanvas()
                WheelZoom(delta, mouseX, mouseY)
                UpdateThinkRate(element)
            end
            return true
        end,
        press = function(element)
            if element:GetMouseButton(0) then Session.CloseContextMenu() end
            gui.SetFocus(element)
            if element:GetMouseButton(0) then
                if TrySelectionHandle() then return end
                local x, y = PointerInCanvas()
                if data.tool == "none" and not data.locked and x ~= nil and y ~= nil
                    and not OnPin(x, y) and PathUnder(x, y) == nil and labelLayer.HitTest(x, y) == nil then
                    local aid = aidLayer.HitTest(x, y)
                    if aid ~= nil then
                        if data.selectedAid ~= aid or data.popover ~= nil then ctx.SelectAid(aid, false, false) end
                        if aidLayer.Begin("aidMove") then return end
                    end
                end
            end
            -- A press away from an aid closes its editor, like the other toolbar menus.
            if data.popover ~= nil then ctx.SetPopover(nil) end
            if element:GetMouseButton(0) then
                if TrySelectionHandle() then return end
                -- With the ruler on, a left drag measures (R7); right or middle drags still pan.
                local x, y = PointerInCanvas()
                local u, v = nil, nil
                if data.tool == "ruler" and state.layout ~= nil and x ~= nil and y ~= nil then
                    u, v = OverlandMapGeometry.PanelToImage(state.layout, x, y)
                end
                if data.tool == "none" and not data.locked and x ~= nil and y ~= nil and not OnPin(x, y)
                    and PathUnder(x, y) == nil and labelLayer.HitTest(x, y) == data.selectedLabelId
                    and BeginLabelDrag("labelMove", data.selectedLabelId) then
                    -- BeginLabelDrag owns this press; unselected text still pans.
                elseif u ~= nil and v ~= nil then
                    BeginDrag("ruler", nil, u, v, true)
                else
                    BeginDrag("pan", nil, 0, 0, true)
                end
            end
            UpdateThinkRate(element)
        end,
        click = function()
            if ReleasedDragMoved() or state.layout == nil then return end
            local x, y = PointerInCanvas()
            if x == nil or y == nil then return end
            if data.tool == "none" then
                -- A click within a path's band selects it.
                local pathId = PathUnder(x, y)
                if pathId ~= nil then ctx.SelectPath(pathId)
                elseif not data.locked then
                    local id = labelLayer.HitTest(x, y)
                    local aid = id == nil and aidLayer.HitTest(x, y) or nil
                    if aid then ctx.SelectAid(aid, false)
                    else ctx.SelectLabel(id, id ~= nil and OverlandMapLabels.CanEdit(OverlandMapLabels.Snapshot(id))) end
                elseif data.selectedLabelId ~= nil then ctx.SelectLabel(nil) end
                return
            end
            if data.tool == "path" or data.tool == "redraw" then
                -- Close to a pin counts as the pin; elsewhere the click adds a bend.
                local u, v = OverlandMapGeometry.PanelToImage(state.layout, x, y)
                PathTool.Click(ctx, u, v, SnapTarget(x, y))
                Layout()
                return
            end
            Tools.PlaceAt(ctx, OverlandMapGeometry.PanelToImage(state.layout, x, y))
            Layout()
        end,
        rightClick = function(element)
            if ReleasedDragMoved(1) then return end
            if input.RemoveHandle() then return end
            if data.tool == "path" or data.tool == "redraw" then
                if PathTool.Back(ctx) then Layout() end
                return
            end
            local x, y = PointerInCanvas()
            if x == nil or y == nil or state.layout == nil then return end
            local u, v = OverlandMapGeometry.PanelToImage(state.layout, x, y)
            if u == nil or v == nil then return end
            -- Near a path, the Director gets the path's own menu; anyone else the map's.
            local pathId = PathUnder(x, y)
            local entries = pathId ~= nil and OverlandMapPathPanel.MenuEntries(ctx, pathId) or {}
            if pathId == nil and not OnPin(x, y) and data.tool == "none" then
                local id = labelLayer.HitTest(x, y)
                if id ~= nil then entries = OverlandMapLabelPanel.MenuEntries(ctx, id) end
            end
            if #entries == 0 then entries = Tools.MapMenu(ctx, u, v, SnapTarget(x, y)) end
            if #entries == 0 then return end
            for _, entry in ipairs(entries) do
                local action = entry.click
                entry.click = function()
                    element.popup = nil
                    action()
                end
            end
            element.popupsInheritStyles = false
            element.popup = Session.ContextMenu(element, { entries = entries })
        end,
        rendered = function() Layout() end,
        think = function(element)
            if not ctx.IsAlive() then return end
            local mouseX, mouseY = PointerInCanvas()
            PollButtonPan(element, mouseX, mouseY)
            PollDrag(element, mouseX, mouseY)
            PollKeys(element)
            PollPathHover(mouseX, mouseY)
            UpdateDraft(mouseX, mouseY)
            TickAnimation()
            ZoomSettled()
            TickPartyMove()
            TickFade()
            TickControlsFade(mouseX, mouseY)
            UpdateThinkRate(element)
        end,
        overlandMapSaveCamera = function(element)
            state.cameraSaveScheduled = false
            if GestureActive() or state.anim ~= nil then
                state.cameraSaveScheduled = true
                element:ScheduleEvent("overlandMapSaveCamera", C.cameraSaveDelay)
                return
            end
            FlushCamera()
        end,
        destroy = function() gestures.Cancel(); FlushCamera(); if releaseSession then releaseSession() end end,

        bind = function() Bind() end,
        overlandMapThemeChanged = function() if ctx.IsAlive() then UpdatePins(); Layout() end end,
        showMap = function(_, how)
            state.scale = Session.UIScale()
            state.showNames = OverlandMapPreferences.ShowNames()
            gestures.Cancel()
            -- A leg never plays across a map change; the new map starts from where the Party is.
            state.move, state.partyKey, state.partyNow, state.partyBefore = nil, "", nil, nil
            state.partyLook, state.pinsDirty, state.pinInputs = "", true, ""
            local map = ctx.CurrentMap()
            if map == nil then
                ClearMap()
            elseif map.id == state.mapId and map.imageId == state.imageId and map.imageRevision == state.imageRevision then
                if how == "fit" or how == "jump" then StartAnimation(FitCamera(), function() SaveCamera() end) end
            else
                LoadImage(map, how or "restore")
            end
            state.hoverPathId = nil
            UpdatePins()
            UpdateParty()
            BindPaths()
            labelLayer.SetPreview(nil, nil)
            labelLayer.Bind(state.mapId)
            aidLayer.SetPreview(nil)
            aidLayer.Bind(map)
            labelsButton:SetClass("on", OverlandMapPreferences.ShowLabels())
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
        centerOnLabel = function(_, id)
            local row = OverlandMapLabels.Get(id)
            if row == nil or row.mapId ~= state.mapId or StopAnimation() then return end
            data.camera.centerX, data.camera.centerY = row.u, row.v
            Layout()
            SaveCamera()
        end,
        centerOnAid = function(_, kind)
            local row = OverlandMapAids.Snapshot(ctx.CurrentMap(), kind)
            if row == nil or StopAnimation() then return end
            data.camera.centerX, data.camera.centerY = row.u, row.v
            data.camera.allowEdgeFocus = true
            Layout()
            SaveCamera()
        end,
        keepAidVisible = function(_, kind, area)
            local layout, bounds = state.layout, aidLayer.EditBounds(kind)
            if layout == nil or bounds == nil or data.selectedAid ~= kind then return end
            local dx, dy = OverlandMapGeometry.RevealOffset(bounds, area)
            if (dx == 0 and dy == 0) or StopAnimation() then return end
            data.camera.centerX = data.camera.centerX - dx / layout.width
            data.camera.centerY = data.camera.centerY - dy / layout.height
            data.camera.allowEdgeFocus = true
            Layout()
            SaveCamera()
        end,
        -- The status chip's "go to the Party": ease the camera onto it, zoomed in at least
        -- partyFocusZoom, centered in the part of the map an open side panel leaves visible.
        -- Right after a map change the image is still loading, so the move waits for it.
        centerOnParty = function()
            local party = Model.Party()
            if party == nil or party.mapId ~= state.mapId then return end
            --- @type OverlandMapCamera
            local target = { zoom = math.max(data.camera.zoom, C.partyFocusZoom), centerX = party.u, centerY = party.v }
            local layout = state.layout
            if layout == nil or state.imageWidth == nil or state.imageHeight == nil then
                state.animOnLoad = target
                return
            end
            local inset = data.panelInset or 0
            if inset > 0 then
                local at = OverlandMapGeometry.CalculateImageLayout(layout.viewWidth, layout.viewHeight,
                    state.imageWidth --[[@as number]], state.imageHeight --[[@as number]], target, inset)
                if at ~= nil and at.width > 0 then target.centerX = party.u + inset / 2 / at.width end
            end
            StartAnimation(target, nil)
        end,
        relayout = function() Layout() end,
        cancelGesture = function()
            local drag = gestures.current
            gestures.Cancel()
            aidLayer.SetPreview(nil)
            if drag and drag.aidStart then drag.moved = true; gestures.last = drag end
            if drag ~= nil and drag.labelStart ~= nil then
                drag.moved = true
                gestures.last = drag
                labelLayer.SetPreview(nil, nil)
            end
            if drag ~= nil and drag.snapId ~= nil and pins[drag.snapId] ~= nil then pins[drag.snapId]:SetClass("snapTarget", false) end
            if drag ~= nil and drag.kind == "pan" then data.camera = drag.startCamera end
            if drag ~= nil and drag.kind == "bend" then pathLayer.SetHandles(PathTool.HandlesFor(ctx), nil) end
            state.pinsDirty = true
            Layout()
        end,

        artwork.layer, aidLayer.layer, labelLayer.layer, pathLayer.layer, pathLayer.top,
        overlay.route, pinLayer, labelLayer.handles, aidLayer.handles, overlay.ruler, overlay.label, controls,
    }
    releaseSession = OverlandMapSession.Register {
        scope = ctx, valid = function() return canvas.valid end,
        gesture = function(reason)
            if reason ~= "permission" or not GesturePermitted() then canvas:FireEvent("cancelGesture") end
        end,
    }
    return canvas
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function OverlandMapCanvas.Styles()
    return {
        {
            selectors = { "overlandMapCanvas" },
            width = "100%",
            height = "100%",
            minWidth = 0,
            minHeight = 0,
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "overlandMapImage" },
            bgcolor = "white",
        },
        {
            selectors = { "overlandMapFadeEdge" },
            bgimage = true,
            bgcolor = "@bgAlt",
        },
        OverlandMapStyles.FadeEdge("overlandMapFadeLeft", { halign = "left", height = "100%" }, { x = 0, y = 0.5 }, { x = 1, y = 0.5 }),
        OverlandMapStyles.FadeEdge("overlandMapFadeRight", { halign = "right", height = "100%" }, { x = 1, y = 0.5 }, { x = 0, y = 0.5 }),
        OverlandMapStyles.FadeEdge("overlandMapFadeTop", { valign = "top", width = "100%" }, { x = 0.5, y = 1 }, { x = 0.5, y = 0 }),
        OverlandMapStyles.FadeEdge("overlandMapFadeBottom", { valign = "bottom", width = "100%" }, { x = 0.5, y = 0 }, { x = 0.5, y = 1 }),
        {
            selectors = { "overlandMapPin" },
            flow = "none",
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = { "overlandMapPin", "hiddenPin" },
            opacity = 0.55,
        },
        {
            selectors = { "overlandMapWaiting" },
            opacity = 0,
            priority = 10,
        },
        {
            selectors = { "overlandMapPinDisc" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@fgStrong",
            borderWidth = 2,
        },
        {
            selectors = { "overlandMapPinDisc", "parent:hover" },
            borderColor = "@accent",
        },
        {
            selectors = { "overlandMapPinDisc", "parent:selected" },
            borderColor = "@accent",
            borderWidth = 3,
        },
        {
            selectors = { "overlandMapPinDisc", "parent:snapTarget" },
            bgcolor = "@accent",
            borderColor = "@fgStrong",
            borderWidth = 3,
        },
        {
            selectors = { "overlandMapPinGlyph" },
            width = "62%",
            height = "62%",
            halign = "center",
            valign = "center",
            bgcolor = "@fgStrong",
        },
        {
            selectors = { "overlandMapPinGlyph", "image" },
            width = "80%",
            height = "80%",
            bgcolor = "white",
        },
        {
            selectors = { "overlandMapPinName" },
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "top",
            color = "@fgStrong",
            fontFace = "@label",
            bold = true,
            textAlignment = "center",
            textWrap = false,
            -- Outline width is a 0..1 fraction of the glyph; larger values erode the text.
            textOutlineWidth = 0.3,
            textOutlineColor = "@bg",
        },
        {
            selectors = { "overlandMapPinName", "plate" },
            valign = "center",
            hpad = 7,
            vpad = 2,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 4,
            textOutlineWidth = 0,
        },
        {
            selectors = { "overlandMapPinName", "plate", "customPinBackground" },
            borderWidth = 0,
        },
        {
            selectors = { "overlandMapPinName", "plate", "parent:hover" },
            borderColor = "@accent",
            borderWidth = 1,
        },
        {
            selectors = { "overlandMapPinName", "plate", "parent:selected" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "overlandMapPinName", "plate", "parent:snapTarget" },
            borderColor = "@accent",
            borderWidth = 3,
        },
        {
            selectors = { "overlandMapPinBadge" },
            width = 14,
            height = 14,
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@fgStrong",
            borderWidth = 1,
            cornerRadius = 7,
        },
        {
            selectors = { "overlandMapPinBadgeGlyph" },
            width = "72%",
            height = "72%",
            halign = "center",
            valign = "center",
            bgcolor = "@fgStrong",
        },
        {
            selectors = { "overlandMapParty" },
            flow = "none",
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = { "overlandMapPartyDisc" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "@accent",
            borderColor = "@fgStrong",
            borderWidth = 3,
        },
        {
            selectors = { "overlandMapPartyDisc", "parent:hover" },
            borderColor = "@accentHover",
        },
        {
            selectors = { "overlandMapPartyGlyph" },
            width = "60%",
            height = "60%",
            halign = "center",
            valign = "center",
            bgcolor = "@bg",
        },
        {
            selectors = { "overlandMapPartyGlyph", "image" },
            width = "100%",
            height = "100%",
            bgcolor = "white",
        },
        {
            selectors = { "overlandMapPartyName" },
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "top",
            hpad = 6,
            vpad = 1,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@accent",
            borderWidth = 1,
            cornerRadius = 4,
            color = "@fgStrong",
            bold = true,
            textWrap = false,
        },
    }
end
