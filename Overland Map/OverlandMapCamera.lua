local mod = dmhub.GetModLoading()

--- @class OverlandMapCameraController: GameType
--- @field new fun(o?: table): OverlandMapCameraController
OverlandMapCameraController = RegisterGameType("OverlandMapCameraController")
local C, Model = OverlandMapConstants, OverlandMapModel
local Session, Copy = OverlandMapControls, OverlandMapCopy
local Clamp, IsFinite = Model.Clamp, Model.IsFinite
local ImageToPanel = OverlandMapGeometry.ImageToPanel

--- @param a OverlandMapCamera
--- @param b OverlandMapCamera
--- @param t number 0..1
--- @return OverlandMapCamera
local function LerpCamera(a, b, t)
    -- Ease out: fast start, gentle landing.
    local e = 1 - (1 - t) * (1 - t)
    return {
        zoom = a.zoom + (b.zoom - a.zoom) * e,
        centerX = a.centerX + (b.centerX - a.centerX) * e,
        centerY = a.centerY + (b.centerY - a.centerY) * e,
    }
end

--- @param ctx OverlandMapContext
--- @param state OverlandMapCanvasState
--- @param layout fun()
--- @param schedule fun()
--- @param wake fun()
function OverlandMapCameraController.Create(ctx, state, layout, schedule, wake)
    local data, Layout = ctx.data, layout
    -- Camera ---------------------------------------------------------------------------------

    local function OpenLocation()
        return Model.GetLocation(state.mapId)
    end

    -- Camera saves are debounced: wheel notches and pans only mark it dirty.
    local function FlushCamera()
        if not state.cameraDirty then return end
        state.cameraDirty = false
        local map = OpenLocation()
        if map ~= nil and map.imageRevision == state.imageRevision then OverlandMapPreferences.SaveCamera(map, data.camera) end
    end

    local function SaveCamera()
        if state.mapId == nil then return end
        state.cameraDirty = true
        if not state.cameraSaveScheduled then
            state.cameraSaveScheduled = true
            schedule()
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
        if OverlandMapPreferences.ReduceMotion() then
            data.camera = to
            Layout()
            if onDone ~= nil then onDone() end
            return
        end
        state.anim = {
            from = { zoom = data.camera.zoom, centerX = data.camera.centerX, centerY = data.camera.centerY },
            to = to, start = dmhub.Time(), onDone = onDone, noSave = noSave == true,
        }
        -- Started from outside the canvas, think may still be at the idle rate: its
        -- next tick would come most of the way through the 0.3 s animation.
        wake()
    end

    local function Zoom(factor)
        if state.layout == nil or StopAnimation() then return end
        data.camera.zoom = Clamp(data.camera.zoom * factor, C.minZoom, C.maxZoom)
        Layout()
        SaveCamera()
    end

    local function WheelZoom(wheel, mouseX, mouseY)
        local layout = state.layout
        if mouseX == nil or mouseY == nil or layout == nil or wheel == 0 or StopAnimation() then return end
        local beforeU = (mouseX - layout.x) / layout.width
        local beforeV = (mouseY - layout.y) / layout.height
        local oldZoom = data.camera.zoom
        local step = wheel > 0 and C.zoomWheelStep or 1 / C.zoomWheelStep
        data.camera.zoom = Clamp(oldZoom * step, C.minZoom, C.maxZoom)
        if data.camera.zoom == oldZoom then return end
        -- A layout only exists once the image size is known.
        local newLayout = OverlandMapGeometry.CalculateImageLayout(layout.viewWidth, layout.viewHeight,
            state.imageWidth --[[@as number]], state.imageHeight --[[@as number]], data.camera, data.panelInset)
        if newLayout == nil then return end
        data.camera.centerX = beforeU + (layout.viewWidth * 0.5 - mouseX) / newLayout.width
        data.camera.centerY = beforeV + (layout.viewHeight * 0.5 - mouseY) / newLayout.height
        state.lastWheel = dmhub.Time()
        Layout()
        SaveCamera()
    end

    local function TickAnimation()
        local anim = state.anim
        if anim == nil then return end
        local t = Clamp((dmhub.Time() - anim.start) / C.transitionSeconds, 0, 1)
        data.camera = LerpCamera(anim.from, anim.to, t)
        -- The last frame lays out with the animation over, so the lines are placed for real.
        if t >= 1 then state.anim = nil end
        Layout()
        if t >= 1 then
            if not anim.noSave then SaveCamera() end
            if anim.onDone ~= nil then anim.onDone() end
        end
    end

    return { Flush = FlushCamera, Save = SaveCamera, Fit = FitCamera, Stop = StopAnimation,
        Animate = StartAnimation, Zoom = Zoom, Wheel = WheelZoom, Tick = TickAnimation }
end
