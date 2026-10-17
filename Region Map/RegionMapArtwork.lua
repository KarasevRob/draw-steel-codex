local mod = dmhub.GetModLoading()

--- Selected-object artwork; image requests and chooser results belong to one binding.
--- @class RegionMapArtwork: GameType
--- @field new fun(o?: table): RegionMapArtwork
RegionMapArtwork = RegisterGameType("RegionMapArtwork")
local C, R, Model = RegionMapConstants, RegionMapRecords, RegionMapModel
local Session, Copy, Undo = RegionMapSession, RegionMapCopy, RegionMapUndo
local T = Copy.T

--- @alias RegionMapArtworkKind "location"|"path"
--- @class RegionMapArtworkOperation
--- @field id string
--- @field generation integer
--- @field expected any
--- @field original any
--- @field chosen boolean
--- @field value nil|string
--- @field write nil|RegionMapWrite
--- @field entry nil|RegionMapUndoEntry
--- @field finished boolean

--- @class RegionMapArtworkState
--- @field id nil|string
--- @field value any
--- @field generation integer
--- @field request integer
--- @field status "empty"|"loading"|"ready"|"unavailable"
--- @field assetKey any
--- @field assetLoaded boolean
--- @field image nil|Panel
--- @field picker nil|IconEditorPanel
--- @field operation nil|RegionMapArtworkOperation

--- @param kind RegionMapArtworkKind
--- @param id nil|string
--- @return nil|RegionMapLocationRecord|RegionMapPathRecord
function RegionMapArtwork.Current(kind, id)
    if kind == "path" then return RegionMapPaths.Get(id) end
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
--- @param ctx RegionMapContext
--- @return nil|Panel
function RegionMapArtwork.ActiveReader(ctx)
    for panel, reader in pairs(readers) do
        if reader.ctx == ctx and panel.valid and not panel:HasClass("collapsed") and reader.Active() then return panel end
    end
    return nil
end

--- bind(id) activates this instance; bind(nil) cancels all outstanding chooser work.
--- @param ctx RegionMapContext
--- @param kind RegionMapArtworkKind
--- @param editing boolean
--- @param isActive fun(id: string): boolean the owning panel says whether it still shows this object in this mode
--- @return Panel
function RegionMapArtwork.Create(ctx, kind, editing, isActive)
    local panel, frame, openButton, chooseButton, removeButton, controls, pickerSlot, message, retryButton
    local saveLine, saveRetry, saveRow, heading
    local Bind, Load, Write
    local state = {
        generation = 0, request = 0, value = "", status = "empty", assetLoaded = false,
    } --[[@as RegionMapArtworkState]]

    local function Active()
        if mod.unloaded or not ctx.IsAlive() or panel == nil or not panel.valid or state.id == nil then return false end
        return isActive(state.id)
    end

    local function Current()
        if not Active() then return nil end
        return RegionMapArtwork.Current(kind, state.id)
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
            dmhub.Schedule(C.saveRecheckDelay, function() Observe(operation) end)
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
        local row = detached and RegionMapArtwork.Current(kind, operation.id) or Current()
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
        local update = kind == "path" and RegionMapPaths.UpdatePath or Model.UpdateLocation
        local tableName = kind == "path" and C.pathTableName or C.locationTableName
        local previousWrite = R.LastWrite(tableName, operation.id)
        -- Undo of a retried upload restores the row from before the first attempt.
        local retry = { operation = operation.write, before = operation.entry and operation.entry.steps[1].before }
        local ok, reason, entry = update(operation.id, { artworkImageId = value },
            value == "" and "Remove image" or "Update image", retry)
        if reason == "busy" and attempt < C.busyRetries then
            dmhub.Schedule(C.busyRetryDelay, function() Write(operation, attempt + 1, detached) end)
            return
        end
        if not ok then
            local failedWrite = R.LastWrite(tableName, operation.id)
            if failedWrite ~= nil and failedWrite ~= previousWrite and failedWrite.status == "failed" then
                operation.write = failedWrite
                local now = RegionMapArtwork.Current(kind, operation.id)
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
        } --[[@as RegionMapArtworkOperation]]
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
                dmhub.Schedule(0, function()
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
        state.request = state.request + 1
        local request, value = state.request, DeepCopy(state.value)
        local asset = ReadableAsset(value)
        state.assetKey = asset and asset.imageid or nil
        state.assetLoaded = asset ~= nil and asset.loaded == true
        if state.image ~= nil then frame:RemoveChild(state.image); state.image = nil end
        if value == "" then ShowStatus("empty"); return end
        if asset == nil then ShowStatus("unavailable"); return end
        ShowStatus("loading")
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
                ShowStatus("ready")
            end,
        }
        state.image = imagePanel
        frame:AddChild(imagePanel)
        -- Streamed images do not report the picker's white placeholder as a finished load.
        imagePanel.bgimageStreamed = value
        dmhub.Schedule(C.artworkTimeout, function()
            if request == state.request and Matches(value) and state.status == "loading" then ShowStatus("unavailable") end
        end)
    end

    Bind = function(id)
        local row = id ~= nil and RegionMapArtwork.Current(kind, id) or nil
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

    heading = Session.Label({ "regionMapFormLabel", "sizeXs" }, T("artwork.section"))
    message = Session.Label({ "regionMapArtworkMessage", "sizeS" })
    retryButton = Session.Button(T("artwork.retry"), function()
        local row = Current()
        if row == nil then return end
        Bind(row.id)
        Load()
    end)
    frame = gui.Panel {
        classes = { "regionMapArtworkFrame" },
        click = function(element) Open(element) end,
        message,
        gui.Panel { width = "auto", height = "auto", halign = "center", valign = "bottom", retryButton },
    }
    openButton = gui.Button {
        classes = { "regionMapButton", "sizeS" }, text = T("artwork.open"), canFocus = true,
        click = function(element) Open(element) end,
    }
    chooseButton = Session.Button(T("artwork.choose"), Choose)
    removeButton = Session.Button(T("artwork.remove"), function()
        local operation = Begin()
        if operation == nil then return end
        operation.chosen, operation.value = true, ""
        Write(operation, 1)
    end)
    controls = gui.Panel { classes = { "regionMapButtonRow" }, chooseButton, removeButton }
    pickerSlot = gui.Panel { width = "100%", height = "auto", classes = { "collapsed" } }
    saveLine = Session.Label({ "regionMapStateLine", "sizeXs" })
    saveRetry = Session.Button(T("artwork.retry"), function()
        if state.operation ~= nil then Write(state.operation, 1) end
    end)
    saveRow = gui.Panel { classes = { "regionMapSideRow", "collapsed" }, saveLine, saveRetry }
    panel = gui.Panel {
        id = "region-map-artwork-" .. kind .. (editing and "-edit" or "-read"),
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
            if focus ~= nil and focus ~= openButton and focus ~= ctx.root:Get("region-map-canvas") then return end
            local confirm = ctx.root:Get("region-map-confirm")
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
        gui.Panel { classes = { "regionMapButtonRow" }, openButton },
        controls, pickerSlot, saveRow,
    }
    if not editing then readers[panel] = { ctx = ctx, Active = Active } end
    return panel
end

--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function RegionMapArtwork.Styles()
    return {
        {
            selectors = { "regionMapArtworkFrame" },
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
            selectors = { "regionMapArtworkFrame", "ready", "hover" },
            borderColor = "@accentHover",
        },
        {
            selectors = { "regionMapArtworkFrame", "ready", "press" },
            borderColor = "@accent",
        },
        {
            selectors = { "regionMapArtworkMessage" },
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
