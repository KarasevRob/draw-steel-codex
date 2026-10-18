local mod = dmhub.GetModLoading()

--- @class OverlandMapGestures: GameType
--- @field new fun(o?: table): OverlandMapGestures
OverlandMapGestures = RegisterGameType("OverlandMapGestures")

--- One polling adapter owns pointer threshold, release consumption and cancellation.
--- Feature adapters preview and validate their own domain operation.
--- @param valid fun(): boolean
--- @return table
function OverlandMapGestures.Create(valid)
    local api = { current = nil, last = nil }
    local generation = OverlandMapLifetime.Capture()

    function api.Cancel()
        local current = api.current
        api.current = nil
        if current ~= nil then
            current.phase = "cancelled"
            current.moved = true
            api.last = current
        end
        return current
    end

    function api.Begin(capture)
        api.Cancel()
        if not valid() or not OverlandMapLifetime.Valid(generation) then return nil end
        capture.phase = "active"
        api.current, api.last = capture, nil
        return capture
    end

    function api.Update(x, y, down)
        local current = api.current
        if current == nil then return "idle" end
        if not valid() or not OverlandMapLifetime.Valid(generation) then api.Cancel(); return "cancelled" end
        if not down then return "released" end
        if x ~= nil and y ~= nil and not current.moved then
            current.moved = math.abs(x - current.startX) >= OverlandMapConstants.canvasDragThreshold
                or math.abs(y - current.startY) >= OverlandMapConstants.canvasDragThreshold
        end
        return "active"
    end

    function api.Commit()
        if not valid() or not OverlandMapLifetime.Valid(generation) then api.Cancel(); return nil end
        local current = api.current
        if current == nil then return nil end
        api.current, api.last = nil, current
        current.phase = "committed"
        return current
    end

    function api.ConsumeRelease(button)
        local last = api.last
        api.last = nil
        return last ~= nil and last.moved and (button == nil or last.button == button)
    end
    return api
end

--- Feature adapters share release arbitration and call domain services only on commit.
--- @param ctx OverlandMapContext
--- @param state OverlandMapCanvasState
--- @param gestures table
--- @param layers table
--- @param view table
function OverlandMapGestures.Canvas(ctx, state, gestures, layers, view)
    local C, Model, Tools = OverlandMapConstants, OverlandMapModel, OverlandMapCanvasTools
    local Session, PathTool, Copy = OverlandMapControls, OverlandMapPathTool, OverlandMapCopy
    local Clamp, ImageToPanel = Model.Clamp, OverlandMapGeometry.ImageToPanel
    local data, Layout = ctx.data, view.Layout
    local pathLayer, labelLayer, aidLayer = layers.path, layers.labels, layers.aids
    local StopAnimation, SaveCamera = view.camera.Stop, view.camera.Save
    -- Pointer helpers ------------------------------------------------------------------------

    local function PointerInCanvas()
        local point = view.Canvas().mousePoint
        local width, height = view.Canvas().renderedWidth or 0, view.Canvas().renderedHeight or 0
        if point == nil or width <= 0 or height <= 0 then return nil, nil end
        return point.x * width, (1 - point.y) * height
    end

    local function GestureActive()
        return gestures.current ~= nil and gestures.current.moved
    end

    local function GesturePermitted()
        local drag = gestures.current
        if drag == nil then return true end
        if ctx.CurrentMap() == nil then return false end
        if drag.aidStart then return OverlandMapAids.CanEdit(drag.aidMapId) and OverlandMapAids.Snapshot(ctx.CurrentMap(), drag.id) ~= nil end
        if drag.labelStart then return OverlandMapLabels.CanEdit(OverlandMapLabels.Snapshot(drag.id)) end
        if drag.kind == "pin" then return Model.CanEdit(Model.GetLocation(drag.id)) or not drag.allowed end
        if drag.kind == "party" then return Model.CanMovePartyOn(state.mapId) and Model.Party() ~= nil end
        if drag.kind == "bend" then return Model.IsDirector() and OverlandMapPaths.Get(drag.id) ~= nil end
        return true
    end

    -- Pins -----------------------------------------------------------------------------------

    -- Ends the drag in progress on release and commits what it moved. Both
    -- think (button up) and the click event can see the release first.
    local function FinishDrag()
        if not GesturePermitted() then
            view.Canvas():FireEvent("cancelGesture")
            return nil
        end
        local drag = gestures.Commit()
        if drag == nil then return nil end
        -- A dragged pin or Party was drawn at its preview; put everything back at its stored place.
        if drag.kind == "pin" or drag.kind == "party" then state.pinsDirty = true end
        if drag.snapId ~= nil and layers.pins[drag.snapId] ~= nil then layers.pins[drag.snapId]:SetClass("snapTarget", false) end
        if drag.kind == "pan" then
            if drag.moved then SaveCamera() end
            return drag
        end
        -- A ruler drag already wrote both points while it moved.
        if drag.kind == "ruler" then return drag end
        if drag.aidStart ~= nil then
            aidLayer.SetPreview(nil)
            if drag.moved and drag.aidChanges and not data.locked and data.tool == "none"
                and data.selectedAid == drag.id and data.mapId == drag.aidMapId then
                OverlandMapAids.Commit(drag.aidMapId, drag.id, drag.aidChanges)
            end
            ctx.RefreshAll()
            if drag.moved and data.selectedAid == drag.id then ctx.KeepAidVisible(drag.id) end
            return drag
        end
        if drag.labelStart ~= nil then
            labelLayer.SetPreview(nil, nil)
            if drag.moved and drag.labelChanges ~= nil then
                local kind = drag.kind == "labelResize" and "resized" or drag.kind == "labelRotate" and "rotated" or "moved"
                OverlandMapLabels.Commit(drag.id, drag.labelChanges, kind)
            end
            ctx.RefreshAll()
            return drag
        end
        -- A bend handle writes once, on drop (Q5); the preview line goes either way.
        if drag.kind == "bend" then
            pathLayer.SetHandles(PathTool.HandlesFor(ctx), nil)
            if drag.moved and drag.id ~= nil and drag.index ~= nil and drag.previewU ~= nil and drag.previewV ~= nil then
                PathTool.DropBend(ctx, drag.id, drag.index, drag.insert == true, drag.previewU, drag.previewV)
            end
            return drag
        end
        if not drag.moved or not drag.allowed or state.mapId == nil then return drag end
        if drag.kind == "pin" and drag.previewU ~= nil and drag.previewV ~= nil and drag.id ~= nil then
            local location = Model.GetLocation(drag.id)
            local result = OverlandMapCommands.MoveLocation(drag.id, drag.previewU, drag.previewV)
            local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
            if ctx.Report(ok, reason) and location ~= nil then
                ctx.Push(entry, "toast.moved", { name = Model.DisplayName(location) })
            end
        elseif drag.kind == "party" and drag.previewU ~= nil and drag.previewV ~= nil then
            local party = Model.PartyName()
            if Model.IsPointCrawl(Model.GetLocation(state.mapId)) then
                -- On a point crawl map the Party moves only along paths: the banner goes back and says how (Q17).
                OverlandMapUndo.Notify("hint.dragTravel", { party = party })
            elseif drag.snapId ~= nil then
                local target = Model.GetLocation(drag.snapId)
                local result = OverlandMapCommands.WriteParty{ mapId = state.mapId, locationId = drag.snapId }
                local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
                if ctx.Report(ok, reason) and target ~= nil then
                    ctx.Push(entry, "toast.partyAt", { party = party, name = Model.DisplayName(target) })
                end
            else
                local result = OverlandMapCommands.WriteParty{ mapId = state.mapId, u = drag.previewU, v = drag.previewV }
                local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
                if ctx.Report(ok, reason) then ctx.Push(entry, "toast.partyTraveling", { party = party }) end
            end
        end
        ctx.RefreshAll()
        return drag
    end

    -- The drag a click or right-click event belongs to: still open, or just
    -- finished by think. True means the release ended a drag, not a click.
    -- A right-click passes button 1: the engine sends no click after a left drag,
    -- so that drag is still kept here and must not swallow the right-click.
    local function ReleasedDragMoved(button)
        FinishDrag()
        return gestures.ConsumeRelease(button)
    end

    local function BeginDrag(kind, id, u, v, allowed)
        local x, y = PointerInCanvas()
        if x == nil or y == nil or StopAnimation() then return end
        -- Grabbing the Party mid-walk ends the walk where the Party really is.
        if kind == "party" and state.move ~= nil then
            state.move = nil
            state.pinsDirty = true
        end
        gestures.last = nil
        gestures.Begin {
            kind = kind, id = id, button = 0, startX = x, startY = y,
            startCamera = { zoom = data.camera.zoom, centerX = data.camera.centerX, centerY = data.camera.centerY },
            startU = u or 0, startV = v or 0, allowed = allowed, moved = false,
        }
    end

    local function BeginLabelDrag(kind, id)
        local row = OverlandMapLabels.Snapshot(id)
        if row == nil or data.locked or data.tool ~= "none" or not OverlandMapLabels.CanEdit(row) or state.layout == nil then return false end
        OverlandMapLabels.Flush(id)
        BeginDrag(kind, id, row.u, row.v, true)
        local drag = gestures.current
        if drag == nil then return false end
        drag.labelStart = DeepCopy(row)
        local x, y = ImageToPanel(state.layout, row.u, row.v)
        drag.labelDistance = math.max(1, math.sqrt((drag.startX - x)^2 + (drag.startY - y)^2))
        drag.labelPointerAngle = math.atan(drag.startY - y, drag.startX - x)
        return true
    end

    aidLayer.Begin = function(kind)
        ctx.FlushEdits()
        local row = OverlandMapAids.Snapshot(ctx.CurrentMap(), data.selectedAid)
        if row == nil or data.locked or data.tool ~= "none" or not OverlandMapAids.CanEdit(data.mapId) or state.layout == nil then return end
        gui.SetFocus(view.Canvas())
        BeginDrag(kind, data.selectedAid, row.u, row.v, true)
        local drag = gestures.current
        if drag == nil then return end
        drag.aidStart, drag.aidMapId = DeepCopy(row), data.mapId
        local x, y = ImageToPanel(state.layout, row.u, row.v)
        drag.labelDistance = math.max(1, math.sqrt((drag.startX - x)^2 + (drag.startY - y)^2))
        drag.labelPointerAngle = math.atan(drag.startY - y, drag.startX - x)
        view.Canvas().thinkTime = C.canvasThinkActive
        return true
    end

    local function PathHandleAt()
        local x, y = PointerInCanvas()
        local id = PathTool.HandlesFor(ctx)
        if id == nil or x == nil or y == nil or state.layout == nil then return nil, nil end
        return id, pathLayer.HandleAt(x, y, state.scale)
    end

    local function RemovePathHandle()
        local id, handle = PathHandleAt()
        if id == nil or handle == nil or handle.kind ~= "bend" then return false end
        PathTool.RemoveBend(ctx, id, handle.index)
        return true
    end

    local function TrySelectionHandle()
        local x, y = PointerInCanvas()
        if x == nil or y == nil then return false end
        local aidHandle = aidLayer.HandleAt(x, y)
        if aidHandle then return aidLayer.Begin(aidHandle == "resize" and "aidResize" or "aidRotate") end
        local kind, id = labelLayer.HandleAt(x, y)
        if kind ~= nil then return BeginLabelDrag(kind == "resize" and "labelResize" or "labelRotate", id) end
        local pathId, handle = PathHandleAt()
        local points = handle ~= nil and pathLayer.HandlePoints() or nil
        if pathId ~= nil and handle ~= nil and points ~= nil then
            local a, b = points[handle.index], points[handle.index + 1]
            if a == nil or b == nil then return false end
            local u, v = b.u, b.v
            if handle.kind == "plus" then u, v = (a.u + b.u) / 2, (a.v + b.v) / 2 end
            gui.SetFocus(view.Canvas())
            BeginDrag("bend", pathId, u, v, true)
            if gestures.current == nil then return false end
            gestures.current.index, gestures.current.insert = handle.index, handle.kind == "plus"
            view.Canvas().thinkTime = C.canvasThinkActive
            return true
        end
        return false
    end

    local PinHandlers = {
            hover = function(element, tooltipOwner)
                if gestures.current ~= nil then return end
                local text = OverlandMapPinText.HoverText(element.data.id)
                if text then Session.HoverText(tooltipOwner or element, text) end
            end,
            dehover = function(element) element.tooltip = nil end,
            destroy = function(element) element.tooltip = nil end,
            press = function(element)
                if element:GetMouseButton(0) ~= true then return end
                element.data.doubleClickHandled = nil
                Session.CloseContextMenu()
                if TrySelectionHandle() then return end
                local location = Model.GetLocation(element.data.id)
                if location == nil then return end
                -- A tooltip shown on hover would stay behind at the drag's start.
                element.tooltip = nil
                gui.SetFocus(view.Canvas())
                local canDrag = data.tool == "none" and not data.locked and Model.CanEdit(location)
                BeginDrag("pin", location.id, location.u, location.v, canDrag)
            end,
            click = function(element)
                local doubleClickHandled = element.data.doubleClickHandled
                element.data.doubleClickHandled = nil
                if ReleasedDragMoved() or doubleClickHandled then return end
                -- The ruler and the scale tool measure to a pin's point instead of selecting it.
                if data.tool == "ruler" or data.tool == "scale" or data.tool == "labelAdd" then
                    Tools.PlaceAt(ctx, element.data.u, element.data.v)
                    Layout()
                    return
                end
                -- The Path tool and Redraw line take a pin as an end of the line.
                if data.tool == "path" or data.tool == "redraw" then
                    PathTool.Click(ctx, nil, nil, element.data.id)
                    Layout()
                    return
                end
                ctx.Select(element.data.id, "read")
            end,
            -- Rename only when pins are unlocked and the viewer may edit; else a click (R12).
            doubleclick = function(element)
                -- The engine sends the second release's click after doubleclick.
                element.data.doubleClickHandled = true
                local location = Model.GetLocation(element.data.id)
                if location ~= nil and not data.locked and Model.CanEdit(location) then
                    data.focusName = true
                    ctx.Select(location.id, "edit")
                else
                    ctx.Select(element.data.id, "read")
                end
            end,
            rightClick = function(element)
                if ReleasedDragMoved(1) then return end
                if RemovePathHandle() then return end
                -- While drawing a line, right-click anywhere drops the last bend.
                if data.tool == "path" or data.tool == "redraw" then
                    if PathTool.Back(ctx) then Layout() end
                    return
                end
                ctx.ShowMenu(element, element.data.id)
            end,
    }
    local PartyHandlers = {
        hover = function(element)
            if gestures.current ~= nil then return end
            local args = { party = Model.PartyName() }
            local id = Model.CanMovePartyOn(state.mapId or "") and "party.tooltip.move" or "party.tooltip"
            if Model.IsPointCrawl(Model.GetLocation(state.mapId)) then
                id = #(OverlandMapTravel.Options()) > 0 and "party.tooltip.travel" or "party.tooltip"
            end
            gui.Tooltip(Copy.T(id, args))(element)
        end,
        -- The "Travel to" menu (G1); the menu's own click closes it after any entry, submenus too.
        rightClick = function(element)
            if ReleasedDragMoved(1) or data.tool ~= "none" then return end
            if RemovePathHandle() then return end
            local entries = OverlandMapPartyPanel.MenuEntries(ctx)
            if #entries == 0 then return end
            element.tooltip = nil
            element.popupsInheritStyles = false
            element.popup = Session.ContextMenu(element, { entries = entries, click = function() element.popup = nil end })
        end,
        press = function(element)
            local party = element.data.party
            if party == nil or element:GetMouseButton(0) ~= true then return end
            Session.CloseContextMenu()
            if TrySelectionHandle() then return end
            element.tooltip = nil
            gui.SetFocus(view.Canvas())
            -- A viewer who may not move the Party gets no drag at all (no ghost).
            if not Model.CanMovePartyOn(party.mapId) then return end
            -- Start from where the banner is drawn. With a tool on, the press only clicks (like a pin).
            local u, v = layers.party.DrawnPoint(element, party)
            BeginDrag("party", nil, u, v, data.tool == "none")
        end,
        click = function(element)
            if ReleasedDragMoved() then return end
            local party = element.data.party
            if party == nil then return end
            -- The ruler and the scale tool measure to the Party instead of selecting its Location.
            if data.tool == "ruler" or data.tool == "scale" or data.tool == "labelAdd" then
                Tools.PlaceAt(ctx, layers.party.DrawnPoint(element, party))
                Layout()
                return
            end
            -- On a point crawl map the banner opens the Party section with its Travel to list (G1).
            if OverlandMapPartyPanel.Available(ctx) then
                ctx.ShowParty()
            elseif party.locationId ~= nil then
                ctx.Select(party.locationId, "read")
            end
        end,
    }
    local function PollDrag(element, mouseX, mouseY)
        local drag = gestures.current
        if drag == nil then return end
        if not GesturePermitted() then view.Canvas():FireEvent("cancelGesture"); return end
        local phase = gestures.Update(mouseX, mouseY, element:GetMouseButton(drag.button))
        if phase == "released" then FinishDrag(); return end
        if phase ~= "active" then return end
        local layout = state.layout
        if mouseX == nil or mouseY == nil or layout == nil then return end
        local dx, dy = mouseX - drag.startX, mouseY - drag.startY
        if not drag.moved then return end
        if drag.aidStart ~= nil then
            if not OverlandMapAids.CanEdit(drag.aidMapId) or data.mapId ~= drag.aidMapId
                or data.selectedAid ~= drag.id or data.locked or data.tool ~= "none" then
                aidLayer.SetPreview(nil); gestures.Cancel(); Layout(); return
            end
            local row = assert(drag.aidStart)
            if drag.kind == "aidMove" then
                drag.aidChanges = { u = Clamp(row.u + dx / layout.width, 0, 1), v = Clamp(row.v + dy / layout.height, 0, 1) }
            else
                local x, y = ImageToPanel(layout, row.u, row.v)
                if drag.kind == "aidResize" then
                    local distance = math.sqrt((mouseX - x)^2 + (mouseY - y)^2)
                    drag.aidChanges = { width = Clamp(row.width * distance / (drag.labelDistance or 1), 0.001, 1) }
                else
                    drag.aidChanges = { angle = (row.angle + math.deg(math.atan(mouseY - y, mouseX - x) - (drag.labelPointerAngle or 0))) % 360 }
                end
            end
            aidLayer.SetPreview(drag.id, drag.aidChanges)
        elseif drag.labelStart ~= nil then
            if not OverlandMapLabels.CanEdit(OverlandMapLabels.Snapshot(drag.id)) then
                labelLayer.SetPreview(nil, nil)
                gestures.Cancel()
                Layout()
                return
            end
            local row = assert(drag.labelStart)
            if drag.kind == "labelMove" then
                drag.labelChanges = { u = Clamp(row.u + dx / layout.width, 0, 1), v = Clamp(row.v + dy / layout.height, 0, 1) }
            else
                local x, y = ImageToPanel(layout, row.u, row.v)
                if drag.kind == "labelResize" then
                    local distance = math.sqrt((mouseX - x)^2 + (mouseY - y)^2)
                    drag.labelChanges = { size = Clamp(row.size * distance / (drag.labelDistance or 1), C.labelMinSize, C.labelMaxSize) }
                else
                    local angle = row.angle + math.deg(math.atan(mouseY - y, mouseX - x) - (drag.labelPointerAngle or 0))
                    if dmhub.KeyPressed("LeftShift") or dmhub.KeyPressed("RightShift") then angle = math.floor(angle / 15 + 0.5) * 15 end
                    drag.labelChanges = { angle = (angle + 180) % 360 - 180 }
                end
            end
            labelLayer.SetPreview(drag.id, drag.labelChanges)
        elseif drag.kind == "pan" then
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
            if drag.kind == "bend" and drag.index ~= nil then
                pathLayer.SetHandles(drag.id, {
                    index = drag.index, insert = drag.insert == true, u = drag.previewU, v = drag.previewV,
                })
            end
            if drag.kind == "party" then
                local snap = layers.pin.SnapTarget(mouseX, mouseY)
                if snap ~= drag.snapId then
                    if drag.snapId ~= nil and layers.pins[drag.snapId] ~= nil then layers.pins[drag.snapId]:SetClass("snapTarget", false) end
                    if snap ~= nil and layers.pins[snap] ~= nil then layers.pins[snap]:SetClass("snapTarget", true) end
                    drag.snapId = snap
                end
            end
        end
        Layout()
    end

    -- Right or middle button drags pan; a right press that never moved opens the menu.
    local function PollButtonPan(element, mouseX, mouseY)
        if gestures.current ~= nil or not state.hovered or mouseX == nil then return end
        local button = nil
        if element:GetMouseButton(1) then button = 1 elseif element:GetMouseButton(2) then button = 2 end
        if button == nil or StopAnimation() then return end
        gestures.last = nil
        gestures.Begin {
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
        -- Backspace drops the last bend of the line being drawn.
        if KeyEdge("Backspace") and PathTool.Back(ctx) then Layout() end
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

    return {
        Pointer = PointerInCanvas, Active = GestureActive, Permitted = GesturePermitted,
        Begin = BeginDrag, BeginLabel = BeginLabelDrag, SelectionHandle = TrySelectionHandle, RemoveHandle = RemovePathHandle,
        Released = ReleasedDragMoved, Poll = PollDrag, PollButtons = PollButtonPan, PollKeys = PollKeys,
        PinHandlers = PinHandlers, PartyHandlers = PartyHandlers,
    }
end
