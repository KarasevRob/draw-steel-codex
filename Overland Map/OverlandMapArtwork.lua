local mod = dmhub.GetModLoading()

--- Selected-object artwork; image requests and chooser results belong to one binding.
--- @class OverlandMapArtwork: GameType
--- @field new fun(o?: table): OverlandMapArtwork
OverlandMapArtwork = RegisterGameType("OverlandMapArtwork")
local C, R, Model = OverlandMapConstants, OverlandMapRecords, OverlandMapModel
local Session, Copy, Undo = OverlandMapControls, OverlandMapCopy, OverlandMapUndo
local T = Copy.T

--- @alias OverlandMapArtworkKind "location"|"path"
--- @class OverlandMapArtworkOperation
--- @field id string
--- @field generation integer
--- @field expected any
--- @field original any
--- @field chosen boolean
--- @field value nil|string
--- @field write nil|OverlandMapWrite
--- @field entry nil|OverlandMapUndoEntry
--- @field finished boolean

--- @class OverlandMapArtworkState
--- @field id nil|string
--- @field value any
--- @field generation integer
--- @field request integer
--- @field status "empty"|"loading"|"ready"|"unavailable"
--- @field assetKey any
--- @field assetLoaded boolean
--- @field image nil|Panel
--- @field picker nil|IconEditorPanel
--- @field operation nil|OverlandMapArtworkOperation

--- @param kind OverlandMapArtworkKind
--- @param id nil|string
--- @return nil|OverlandMapLocationRecord|OverlandMapPathRecord
function OverlandMapArtwork.Current(kind, id)
    if kind == "path" then return OverlandMapPaths.Get(id) end
    return Model.GetLocation(id)
end

--- Availability comes from the documented asset API and the actual image request.
--- @param value any
--- @return nil|ImageAssetLua
local function ReadableAsset(value)
    local asset = R.ArtworkAsset(value)
    if asset == nil then return nil end
    local ok, allowed = pcall(function() return asset:HaveReadPermissions() end)
    if not ok or not allowed then return nil end
    return asset
end

-- Read-mode instances by panel, so the shell can hand Enter to the one showing now.
local readers = setmetatable({}, { __mode = "k" })

--- The read-mode artwork panel this window shows now, or nil; Enter opens its image.
--- @param ctx OverlandMapContext
--- @return nil|Panel
function OverlandMapArtwork.ActiveReader(ctx)
    for panel, reader in pairs(readers) do
        if reader.ctx == ctx and panel.valid and not panel:HasClass("collapsed") and reader.Active() then return panel end
    end
    return nil
end

--- bind(id) activates this instance; bind(nil) cancels all outstanding chooser work.
--- @param ctx OverlandMapContext
--- @param kind OverlandMapArtworkKind
--- @param editing boolean
--- @param isActive fun(id: string): boolean the owning panel says whether it still shows this object in this mode
--- @return Panel
function OverlandMapArtwork.Create(ctx, kind, editing, isActive)
    local panel, frame, openButton, chooseButton, removeButton, controls, pickerSlot, message, retryButton
    local saveLine, saveRetry, saveRow, heading
    local Bind, Load, Write
    local state = {
        generation = 0, request = 0, value = "", status = "empty", assetLoaded = false,
    } --[[@as OverlandMapArtworkState]]

    local function Active()
        if mod.unloaded or not ctx.IsAlive() or panel == nil or not panel.valid or state.id == nil then return false end
        return isActive(state.id)
    end

    local function Current()
        if not Active() then return nil end
        return OverlandMapArtwork.Current(kind, state.id)
    end

    local function Matches(value)
        local row = Current()
        return row ~= nil and dmhub.DeepEqual(R.ArtworkValue(row), value)
    end

    local function ShowStatus(status)
        state.status = status
        frame:SetClass("collapsed", status == "empty")
        frame:SetClass("ready", status == "ready")
        message:SetClass("collapsed", status == "empty" or status == "ready")
        Session.SetText(message, T(status == "loading" and "artwork.loading" or "artwork.unavailable"))
        retryButton:SetClass("collapsed", status ~= "unavailable")
        openButton:SetClass("collapsed", status == "empty")
        openButton:SetClass("disabled", status ~= "ready")
        if state.image ~= nil and state.image.valid then state.image:SetClass("hidden", status ~= "ready") end
    end

    local function ClosePicker()
        local picker = state.picker
        state.picker = nil
        if picker ~= nil and picker.valid then picker.popup = nil end
        pickerSlot.children = {}
        pickerSlot:SetClass("collapsed", true)
    end

    local function Cancel()
        state.generation = state.generation + 1
        state.operation = nil
        ClosePicker()
        saveRow:SetClass("collapsed", true)
    end

    local function OperationCurrent(operation)
        return Active() and editing and Model.IsDirector() and state.operation == operation
            and operation.generation == state.generation and state.id == operation.id and not operation.finished
    end

    local function Conflict(operation)
        if not OperationCurrent(operation) then return end
        Cancel()
        Undo.Notify("artwork.changed")
        ctx.RefreshAll()
    end

    local function SaveStatus(status)
        saveRow:SetClass("collapsed", status == nil)
        saveRetry:SetClass("collapsed", status ~= "failed")
        saveLine:SetClass("danger", status == "failed")
        Session.SetText(saveLine, status == "failed" and T("edit.notSaved") or T("edit.saving"))
    end

    -- The toast outlives the editor: its Retry rechecks the row and the Director's rights
    -- instead of whether this editor is still open.
    local function Failed(operation)
        if not OperationCurrent(operation) then return end
        SaveStatus("failed")
        Undo.Notify("toast.saveFailed", nil, function()
            if mod.unloaded or operation.finished then return end
            if OperationCurrent(operation) then Write(operation, 1) else Write(operation, 1, true) end
        end)
    end

    local function Observe(operation)
        if mod.unloaded or operation.finished then return end
        local write = operation.write
        if write == nil or write.status == "failed" then
            if OperationCurrent(operation) then Failed(operation)
            else Undo.Notify("toast.saveFailed", nil, function() Write(operation, 1, true) end) end
            return
        end
        if write.status == "pending" then
            OverlandMapLifetime.Schedule(C.saveRecheckDelay, function() Observe(operation) end)
            return
        end
        operation.finished = true
        if Active() and state.operation == operation then SaveStatus(nil) end
        ctx.Push(operation.entry, operation.value == "" and "artwork.removed" or "artwork.updated")
        if ctx.IsAlive() then ctx.RefreshAll() end
    end

    -- detached: a toast Retry after this editor moved on; only the row and permission are checked.
    Write = function(operation, attempt, detached)
        if mod.unloaded or operation.finished then return end
        if not detached and not OperationCurrent(operation) then return end
        local row = detached and OverlandMapArtwork.Current(kind, operation.id) or Current()
        if row == nil or (detached and not Model.IsDirector()) then
            if detached then Undo.Notify("artwork.changed") else Cancel() end
            return
        end
        if not dmhub.DeepEqual(R.ArtworkValue(row), operation.expected) then
            if detached then Undo.Notify("artwork.changed") else Conflict(operation) end
            return
        end
        local value = operation.value
        if value == nil or not R.ValidArtwork(value) then
            local _, reason = R.ArtworkAsset(value)
            if not detached then Cancel() end
            Undo.Notify(reason == "video" and "artwork.still" or "artwork.unavailable")
            return
        end
        if not detached then SaveStatus("pending") end
        local update = kind == "path" and OverlandMapCommands.UpdatePath or OverlandMapCommands.UpdateLocation
        local tableName = kind == "path" and C.pathTableName or C.locationTableName
        local previousWrite = R.LastWrite(tableName, operation.id)
        -- Undo of a retried upload restores the row from before the first attempt.
        local retry = { operation = operation.write, before = operation.entry and operation.entry.steps[1].before }
        local result = update(operation.id, { artworkImageId = value },
            value == "" and "Remove image" or "Update image", retry)
        local ok, reason, entry = OverlandMapCommands.Accepted(result), result.reason, result.undo
        if reason == "busy" and attempt < C.busyRetries then
            OverlandMapLifetime.Schedule(C.busyRetryDelay, function() Write(operation, attempt + 1, detached) end)
            return
        end
        if not ok then
            local failedWrite = R.LastWrite(tableName, operation.id)
            if failedWrite ~= nil and failedWrite ~= previousWrite and failedWrite.status == "failed" then
                operation.write = failedWrite
                local now = OverlandMapArtwork.Current(kind, operation.id)
                if R.Field(now, "mutationId", nil) == failedWrite.mutationId then operation.expected = value end
            end
            if detached then Undo.Notify("toast.saveFailed", nil, function() Write(operation, 1, true) end)
            elseif reason == "permission" then Cancel() else Failed(operation) end
            return
        end
        operation.expected = value
        operation.entry = entry
        if entry == nil then
            operation.finished = true
            if not detached then SaveStatus(nil) end
            return
        end
        operation.write = R.LastWrite(tableName, operation.id)
        if ctx.IsAlive() then ctx.RefreshAll() end
        Observe(operation)
    end

    local function Begin()
        local row = Current()
        if row == nil or not editing or not Model.IsDirector() then return nil end
        Cancel()
        local value = R.ArtworkValue(row)
        local operation = {
            id = row.id, generation = state.generation, expected = DeepCopy(value), original = DeepCopy(value),
            chosen = false, finished = false,
        } --[[@as OverlandMapArtworkOperation]]
        state.operation = operation
        return operation
    end

    local function Choose()
        local operation = Begin()
        if operation == nil then return end
        local picker = gui.IconEditor {
            width = "100%", height = 96, library = "journal", categoriesHidden = true,
            allowNone = true, allowPaste = true, hideIcon = true, liveEdit = false,
            rightClick = function() end,
            change = function(element)
                if not OperationCurrent(operation) or operation.chosen then return end
                operation.chosen = true
                operation.value = element.value or ""
                Write(operation, 1)
                -- IconEditor finishes its own selection callback before its anchor is removed.
                OverlandMapLifetime.Schedule(0, function()
                    if not mod.unloaded and panel.valid and state.picker == element then ClosePicker() end
                end)
            end,
        }
        state.picker = picker
        pickerSlot.children = { picker }
        pickerSlot:SetClass("collapsed", false)
        picker:SetValue(R.IsArtworkId(operation.expected) and operation.expected or "", false)
        local press = picker.events.press
        -- The library owns uploads; this disposable anchor cannot start a second chooser or drop.
        picker.events.press = function() end
        picker.events.dropfiles = function() end
        if type(press) == "function" then press(picker) end
        local popup = picker.popup
        if popup ~= nil then
            popup.events.destroy = function()
                if OperationCurrent(operation) and not operation.chosen then Cancel() end
            end
        end
    end

    local function Open(owner)
        if not Active() or state.status ~= "ready" or not Matches(state.value) then return end
        local asset = ReadableAsset(state.value)
        if asset == nil or asset.imageid ~= state.assetKey then Load(); return end
        local preview = state.image
        if preview == nil or not preview.valid then return end
        local width, height = tonumber(preview.bgimageWidth), tonumber(preview.bgimageHeight)
        if not R.IsFinite(width) or not R.IsFinite(height) or width <= 0 or height <= 0 then return end
        -- The shared viewer's 1024px cap alone can overflow a smaller native window.
        local maxWidth, maxHeight = 1024, 1024
        local viewport = owner.root
        if viewport ~= nil then
            if R.IsFinite(viewport.renderedWidth) and viewport.renderedWidth > 0 then maxWidth = math.min(maxWidth, viewport.renderedWidth) end
            if R.IsFinite(viewport.renderedHeight) and viewport.renderedHeight > 0 then maxHeight = math.min(maxHeight, viewport.renderedHeight) end
        end
        local scale = math.min(1, maxWidth / width, maxHeight / height)
        GameHud.instance:ViewJournalEntry { image = state.value, owner = owner, width = width * scale, height = height * scale }
    end

    Load = function()
        if not Active() then return end
        if state.loader then state.loader.Cancel() end
        state.request = state.request + 1
        local request, value = state.request, DeepCopy(state.value)
        local asset = ReadableAsset(value)
        state.assetKey = asset and asset.imageid or nil
        state.assetLoaded = asset ~= nil and asset.loaded == true
        if state.image ~= nil then frame:RemoveChild(state.image); state.image = nil end
        if value == "" then ShowStatus("empty"); return end
        if asset == nil then ShowStatus("unavailable"); return end
        ShowStatus("loading")
        local loader = OverlandMapImages.Request {
            id = value, source = state.assetKey,
            valid = function()
                local current = ReadableAsset(value)
                return request == state.request and Matches(value) and current ~= nil and current.imageid == state.assetKey
            end,
            changed = function(result) ShowStatus(result.status) end,
        }
        state.loader = loader
        local imagePanel = gui.Panel {
            classes = { "image", "hidden" }, interactable = false,
            width = "auto", height = "auto", maxWidth = "100%", maxHeight = "100%",
            autosizeimage = true, halign = "center", valign = "center",
            imageLoaded = function(element)
                if request ~= state.request or not element.valid or not Matches(value) then return end
                local currentAsset = ReadableAsset(value)
                if currentAsset == nil or currentAsset.imageid ~= state.assetKey then return end
                local width, height = tonumber(element.bgimageWidth), tonumber(element.bgimageHeight)
                if not R.IsFinite(width) or not R.IsFinite(height) or width <= 0 or height <= 0 then return end
                state.assetLoaded = currentAsset.loaded == true
                loader.Loaded(width, height)
            end,
        }
        state.image = imagePanel
        frame:AddChild(imagePanel)
        -- Streamed images do not report the picker's white placeholder as a finished load.
        imagePanel.bgimageStreamed = value

    end

    Bind = function(id)
        local row = id ~= nil and OverlandMapArtwork.Current(kind, id) or nil
        if row == nil then id = nil end
        if state.id ~= id then
            Cancel()
            state.request = state.request + 1
            state.id, state.value = id, nil
        end
        if id == nil then
            if state.image ~= nil then frame:RemoveChild(state.image); state.image = nil end
            panel:SetClass("collapsed", true)
            return
        end
        local value = R.ArtworkValue(row)
        local manage = editing and Model.IsDirector()
        if not manage and state.operation ~= nil then Cancel() end
        local operation = state.operation
        if operation ~= nil and not operation.finished and not dmhub.DeepEqual(value, operation.expected) then
            Conflict(operation)
        end
        heading:SetClass("collapsed", not manage)
        controls:SetClass("collapsed", not manage)
        removeButton:SetClass("collapsed", value == "")
        Session.SetText(chooseButton, T(value == "" and "artwork.choose" or "artwork.replace"))
        panel:SetClass("collapsed", not manage and value == "")
        if not dmhub.DeepEqual(state.value, value) then
            state.value = DeepCopy(value)
            Load()
        end
    end

    heading = Session.Label({ "overlandMapFormLabel", "sizeXs" }, T("artwork.section"))
    message = Session.Label({ "overlandMapArtworkMessage", "sizeS" })
    retryButton = Session.Button(T("artwork.retry"), function()
        local row = Current()
        if row == nil then return end
        Bind(row.id)
        Load()
    end)
    frame = gui.Panel {
        classes = { "overlandMapArtworkFrame" },
        click = function(element) Open(element) end,
        message,
        gui.Panel { width = "auto", height = "auto", halign = "center", valign = "bottom", retryButton },
    }
    openButton = gui.Button {
        classes = { "overlandMapButton", "sizeS" }, text = T("artwork.open"), canFocus = true,
        click = function(element) Open(element) end,
    }
    chooseButton = Session.Button(T("artwork.choose"), Choose)
    removeButton = Session.Button(T("artwork.remove"), function()
        local operation = Begin()
        if operation == nil then return end
        operation.chosen, operation.value = true, ""
        Write(operation, 1)
    end)
    controls = gui.Panel { classes = { "overlandMapButtonRow" }, chooseButton, removeButton }
    pickerSlot = gui.Panel { width = "100%", height = "auto", classes = { "collapsed" } }
    saveLine = Session.Label({ "overlandMapStateLine", "sizeXs" })
    saveRetry = Session.Button(T("artwork.retry"), function()
        if state.operation ~= nil then Write(state.operation, 1) end
    end)
    saveRow = gui.Panel { classes = { "overlandMapSideRow", "collapsed" }, saveLine, saveRetry }
    panel = gui.Panel {
        id = "overland-map-artwork-" .. kind .. (editing and "-edit" or "-read"),
        width = "100%", height = "auto", flow = "vertical", classes = { "collapsed" },
        data = state, monitorAssets = "images", inputEvents = editing and {} or { "enter" },
        bind = function(_, id) if not mod.unloaded then Bind(id) end end,
        refreshAssets = function()
            if not Active() then return end
            local row = Current()
            if row == nil then Bind(nil); return end
            Bind(row.id)
            local asset = ReadableAsset(state.value)
            local key = asset and asset.imageid or nil
            local loaded = asset ~= nil and asset.loaded == true
            if key ~= state.assetKey or loaded ~= state.assetLoaded then Load() end
        end,
        enter = function()
            if not Active() or not panel.enabled or ctx.data.popover ~= nil or gui.GetModal(panel) ~= nil then return end
            local focus = gui.GetFocus()
            if focus ~= nil and focus ~= openButton and focus ~= ctx.root:Get("overland-map-canvas") then return end
            local confirm = ctx.root:Get("overland-map-confirm")
            if confirm ~= nil and not confirm:HasClass("collapsed") then return end
            local popup = ctx.root:FindChildRecursive(function(child) return child.popup ~= nil end)
            if popup == nil then Open(openButton) end
        end,
        destroy = function(element)
            readers[element] = nil
            state.generation, state.request = state.generation + 1, state.request + 1
            state.id, state.operation = nil, nil
        end,
        heading, frame,
        gui.Panel { classes = { "overlandMapButtonRow" }, openButton },
        controls, pickerSlot, saveRow,
    }
    if not editing then readers[panel] = { ctx = ctx, Active = Active } end
    return panel
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function OverlandMapArtwork.Styles()
    return {
        {
            selectors = { "overlandMapArtworkFrame" },
            width = "100%",
            height = C.artworkHeight,
            flow = "none",
            tmargin = 8,
            bgimage = true,
            bgcolor = "@bgAlt",
            borderWidth = 1,
            borderColor = "@border",
        },
        {
            selectors = { "overlandMapArtworkFrame", "ready", "hover" },
            borderColor = "@accentHover",
        },
        {
            selectors = { "overlandMapArtworkFrame", "ready", "press" },
            borderColor = "@accent",
        },
        {
            selectors = { "overlandMapArtworkMessage" },
            width = "100%-16",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
            textWrap = true,
            color = "@fgMuted",
        },
    }
end

--- Retained map artwork owns its images, border and request lifetime; the camera stays in the view session.
--- @param ctx OverlandMapContext
--- @param state OverlandMapCanvasState
--- @param hooks table
--- @return table
function OverlandMapArtwork.MapLayer(ctx, state, hooks)
    local data, Tools = ctx.data, OverlandMapCanvasTools
    local Clamp = Model.Clamp
    local imagePanel, fadingPanel, edgeFade, layer
    local CreateImagePanel, LoadImage
    local function Rebuild()
        local children = {}
        if fadingPanel and fadingPanel.valid then children[#children + 1] = fadingPanel end
        children[#children + 1], children[#children + 2] = imagePanel, edgeFade
        layer.children = children
    end
    CreateImagePanel = function(request, opacity)
        -- A new image panel has no size yet, so the next Layout must write it.
        state.imageSizeW, state.imageSizeH = nil, nil
        local imageId, mapId = state.imageId, state.mapId
        local load = OverlandMapImages.Request {
            id = imageId or "", source = tostring(state.imageRevision),
            valid = function()
                local map = ctx.CurrentMap()
                return ctx.IsAlive() and request == state.imageRequest and map ~= nil
                    and map.id == mapId and map.imageId == imageId
            end,
            changed = function(result)
                state.imageStatus = result.status
                if result.status == "unavailable" then
                    OverlandMapUndo.Notify("artwork.unavailable", nil, function()
                        local map = ctx.CurrentMap()
                        if map and map.id == mapId and map.imageId == imageId then LoadImage(map, "restore") end
                    end)
                end
            end,
        }
        return gui.Panel {
            classes = { "overlandMapImage" },
            floating = true, halign = "left", valign = "top", interactable = false,
            opacity = opacity,
            destroy = function() load.Cancel() end,
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
                if not load.Loaded(width, height) then return end
                state.imageWidth, state.imageHeight = width, height
                if state.crossfade then
                    state.fadeStart = dmhub.Time()
                    hooks.Wake()
                end
                hooks.Layout()
                if state.animOnLoad ~= nil then
                    local target = state.animOnLoad
                    state.animOnLoad = nil
                    hooks.Animate(target, nil)
                end
            end,
        }
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
    LoadImage = function(map, how)
        hooks.FlushCamera()
        DropFadingPanel()
        local crossfade = (how == "down" or how == "up") and state.layout ~= nil and not OverlandMapPreferences.ReduceMotion()
        local fromId = state.mapId
        state.mapId, state.imageId, state.imageRevision = map.id, map.imageId, map.imageRevision
        state.imageWidth, state.imageHeight, state.layout = nil, nil, nil
        -- An animation still running ends here; its onDone runs once this map is set up.
        local interrupted = state.anim
        state.anim, state.animOnLoad = nil, nil
        local camera, restored = OverlandMapPreferences.ReadCamera(map)
        if how == "fit" or how == "jump" or not restored then camera = hooks.FitCamera() end
        data.camera = camera
        -- Going up starts zoomed into the pin we came from, then eases out to the saved view.
        local child = how == "up" and fromId ~= nil and Model.GetLocation(fromId) or nil
        if child ~= nil and child.parentId == map.id and not OverlandMapPreferences.ReduceMotion() then
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
        Rebuild()
        imagePanel.bgimageStreamed = map.imageId
        if interrupted ~= nil and interrupted.onDone ~= nil then interrupted.onDone() end
    end

    local function ClearMap()
        hooks.FlushCamera()
        DropFadingPanel()
        local interrupted = state.anim
        state.anim, state.animOnLoad = nil, nil
        state.mapId, state.imageId, state.imageRevision = nil, nil, nil
        state.imageWidth, state.imageHeight, state.layout = nil, nil, nil
        state.imageRequest = state.imageRequest + 1
        if imagePanel ~= nil and imagePanel.valid then imagePanel:DestroySelf() end
        imagePanel = CreateImagePanel(state.imageRequest, 1)
        Rebuild()
        if interrupted ~= nil and interrupted.onDone ~= nil then interrupted.onDone() end
    end

    local function TickFade()
        if state.fadeStart == nil then return end
        local t = Clamp((dmhub.Time() - state.fadeStart) / C.transitionSeconds, 0, 1)
        if imagePanel.valid then imagePanel.selfStyle.opacity = t end
        if t >= 1 then DropFadingPanel() end
    end

    local function Layout(layout)
        local fadeShown = layout ~= nil and state.border == "fade"
        if state.fadeShown ~= fadeShown then
            state.fadeShown = fadeShown
            edgeFade:SetClass("collapsed", not fadeShown)
        end
        if layout == nil then return end
        -- Position through panel.x/y and size only when it changes: every selfStyle
        -- write costs a style pass (see OverlandMapDrawing.PlaceCentered), and a pan changes only position.
        imagePanel.x, imagePanel.y = layout.x, layout.y
        if state.imageSizeW ~= layout.width or state.imageSizeH ~= layout.height then
            state.imageSizeW, state.imageSizeH = layout.width, layout.height
            imagePanel.selfStyle.width, imagePanel.selfStyle.height = layout.width, layout.height
            edgeFade.selfStyle.width, edgeFade.selfStyle.height = layout.width, layout.height
            Tools.SetFadeBand(edgeFade, OverlandMapGeometry.FadeBand(layout.width, layout.height))
        end
        if fadeShown then edgeFade.x, edgeFade.y = layout.x, layout.y end

    end
    imagePanel = CreateImagePanel(0, 1)
    edgeFade = Tools.CreateFade()
    edgeFade:SetClass("collapsed", true)
    layer = gui.Panel {
        width = "100%", height = "100%", floating = true, interactable = false,
        imagePanel, edgeFade,
    }
    return { layer = layer, Bind = LoadImage, Clear = ClearMap, Layout = Layout, Tick = TickFade,
        Destroy = function() if layer.valid then layer:DestroySelf() end end }
end
