-- Isolated production-code checks: no game tables, UI roots, or global types are changed.
local checks = {}
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = source:match("^(.*)/tests/[^/]+$") or "Overland Map"

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end

local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function Fixture()
    local f = { tables = {}, timers = {}, time = 0, sequence = 0, writes = {}, requests = {}, views = {}, pushes = {}, notices = {} }
    local env = setmetatable({}, { __index = _G }) --[[@as table<string, any>]]
    env._G = env
    f.env = env
    f.mod = { unloaded = false, enterGameHandlers = {}, unloadHandlers = {}, RegisterDocumentForCheckpointBackups = function() end }
    local document = { data = {}, path = "fixture", BeginChange = function() end, CompleteChange = function() end }
    function f.mod:GetDocumentSnapshot() return document end
    function env.RegisterGameType()
        local result = {}
        result.new = function(args) return args or {} end
        return result
    end
    env.setting = function() end
    env.DeepCopy = Copy
    env.ServerTimestamp = function() return f.time end
    env.OverlandMapJournal = {}
    env.dmhub = {
        isDM = true, loginUserid = "viewer", userDisplayName = "Fixture", tablesUpdateId = 0,
        GetModLoading = function() return f.mod end,
        GetSettingValue = function() return {} end,
        SetSettingValue = function() end,
        DeepEqual = Equal,
        GenerateGuid = function() f.sequence = f.sequence + 1; return "fixture-" .. f.sequence end,
        Time = function() return f.now or 0 end,
        GetTable = function(name) f.tables[name] = f.tables[name] or {}; return f.tables[name] end,
        Schedule = function(delay, callback) f.timers[#f.timers + 1] = { at = f.time + delay, callback = callback } end,
        SetAndUploadTableItem = function(name, row, callbacks)
            f.writes[#f.writes + 1] = { name = name, row = row, callbacks = callbacks }
            env.dmhub.GetTable(name)[row.id] = Copy(row)
            env.dmhub.tablesUpdateId = env.dmhub.tablesUpdateId + 1
            if f.writeMode == "refused" then return nil end
            if f.writeMode ~= "pending" then
                if f.writeMode == "fail" then callbacks.failure("fixture failure") else callbacks.success() end
            end
            return row.id
        end,
    }
    function f.Advance(seconds)
        local untilTime = f.time + seconds
        for _ = 1, 10000 do
            local index, nextTimer
            for i, timer in ipairs(f.timers) do
                if timer.at <= untilTime and (nextTimer == nil or timer.at < nextTimer.at) then index, nextTimer = i, timer end
            end
            if nextTimer == nil then f.time = untilTime; return end
            table.remove(f.timers, index)
            f.time = nextTimer.at
            nextTimer.callback()
        end
        error("timer loop did not settle")
    end
    local images = {}
    for _, id in ipairs({ "portrait", "landscape", "third", "video", "restricted" }) do
        images[id] = { imageid = id .. "-bytes", loaded = true, isVideo = id == "video",
            HaveReadPermissions = function() return id ~= "restricted" end }
    end
    env.assets = { imagesTable = images }
    local function Load(name) assert(loadfile(directory .. "/" .. name .. ".lua", "t", env))() end
    for _, name in ipairs({ "OverlandMapConstants", "OverlandMapCopy", "OverlandMapLifetime", "OverlandMapImages", "OverlandMapRecords", "OverlandMapModel", "OverlandMapCommands", "OverlandMapPaths" }) do Load(name) end
    f.C, f.R, f.M, f.P = env.OverlandMapConstants, env.OverlandMapRecords, env.OverlandMapModel, env.OverlandMapPaths
    env.OverlandMapLog = { Add = function() end }
    env.OverlandMapUndo = { Notify = function(id, _, retry) f.notices[#f.notices + 1] = { id = id, retry = retry } end }

    local methods = {}
    local MakePanel
    function methods:FireEvent(name, ...) if self.events[name] then return self.events[name](self, ...) end end
    function methods:SetClass(name, on) self.classes[name] = on end
    function methods:HasClass(name) return self.classes[name] == true end
    function methods:AddChild(child) self.children[#self.children + 1] = child; child.parent = self end
    function methods:RemoveChild(child)
        for i, item in ipairs(self.children) do if item == child then table.remove(self.children, i); child:DestroySelf(); return end end
    end
    function methods:DestroySelf()
        if not self.valid then return end
        self.valid = false
        self:FireEvent("destroy")
        self.popup = nil
        for _, child in ipairs(self.children) do child:DestroySelf() end
    end
    function methods:FindChildRecursive(predicate)
        if predicate(self) then return self end
        for _, child in ipairs(self.children) do local found = child:FindChildRecursive(predicate); if found then return found end end
    end
    function methods:Get(id) return self:FindChildRecursive(function(child) return child.id == id end) end
    MakePanel = function(args)
        local props = { data = args.data or {}, classes = {}, events = {}, children = {}, valid = true, text = args.text, selfStyle = {} }
        local panel
        panel = setmetatable({}, {
            __index = function(_, key)
                if key == "root" then return props.parent and props.parent.root or panel end
                if key == "enabled" then
                    return props.valid and not props.classes.collapsed and not props.classes.hidden
                        and (props.parent == nil or props.parent.enabled)
                end
                return methods[key] or props[key]
            end,
            __newindex = function(self, key, value)
                if key == "children" then
                    for _, child in ipairs(props.children) do child:DestroySelf() end
                    props.children = value
                    for _, child in ipairs(value) do child.parent = self end
                elseif key == "popup" then
                    local old = props.popup
                    props.popup = value
                    if old ~= nil and old ~= value then old:DestroySelf() end
                elseif key == "bgimageStreamed" then
                    props.bgimage = value
                    f.requests[#f.requests + 1] = { panel = self, value = value }
                else props[key] = value end
            end,
        })
        for _, name in ipairs(args.classes or {}) do props.classes[name] = true end
        for key, value in pairs(args) do
            if type(key) == "string" and key ~= "classes" and key ~= "children" then
                if type(value) == "function" then props.events[key] = value else props[key] = value end
            end
        end
        for _, child in ipairs(args.children or args) do panel:AddChild(child) end
        return panel
    end
    env.gui = {
        Panel = MakePanel, Label = MakePanel, Button = MakePanel,
        GetFocus = function() return f.focus end,
        GetModal = function() return f.modal end,
        IconEditor = function(args)
            local panel = MakePanel(args)
            panel.SetValue = function(self, value, fire)
                local changed = self.value ~= value
                self.value = value
                if changed and fire ~= false then self:FireEvent("change") end
            end
            panel.events.press = function(self) self.popup = MakePanel({}) end
            return panel
        end,
    }
    env.GameHud = { instance = { ViewJournalEntry = function(_, args) f.views[#f.views + 1] = args end } }
    env.OverlandMapControls = {
        SetText = function(element, text) element.text = text end,
        Label = function(classes, text) return MakePanel { classes = classes, text = text } end,
        Button = function(text, click) return MakePanel { text = text, click = click } end,
    }
    Load("OverlandMapArtwork")
    local root = MakePanel({})
    f.ctx = {
        root = root, data = { panelMode = "none" },
        IsAlive = function() return root.valid end,
        Push = function(entry, text) f.pushes[#f.pushes + 1] = { entry = entry, text = text } end,
        RefreshAll = function()
            for _, panel in ipairs(root.children) do
                if panel.data.kind ~= nil then
                    local data = f.ctx.data
                    local selected = panel.data.kind == "path" and data.selectedPathId or data.selectedId
                    panel:FireEvent("bind", data.panelMode == panel.data.mode and selected or nil)
                end
            end
        end,
    }
    function f.Component(kind, editing, id)
        local data = f.ctx.data
        local mode = kind == "path" and (editing and "pathEdit" or "path") or (editing and "edit" or "read")
        data.panelMode = mode
        if kind == "path" then data.selectedPathId = id else data.selectedId = id end
        local panel = env.OverlandMapArtwork.Create(f.ctx, kind, editing, function(selected)
            local current = kind == "path" and f.ctx.data.selectedPathId or f.ctx.data.selectedId
            return current == selected and f.ctx.data.panelMode == mode
        end)
        panel.data.kind, panel.data.mode = kind, mode
        root:AddChild(panel)
        f.ctx.RefreshAll()
        return panel
    end
    function f.Click(panel, text)
        local child = assert(panel:FindChildRecursive(function(item) return item.text == text end), "missing control " .. text)
        assert(child.enabled, "disabled/hidden control " .. text)
        child:FireEvent("click")
        return child
    end
    function f.Pick(panel, value)
        local picker = assert(panel.data.picker, "missing picker")
        picker:SetValue(value)
        picker.popup = nil
        f.Advance(0)
        return picker
    end
    function f.Ready(panel, width, height)
        local image = assert(panel.data.image, "missing image request")
        image.bgimageWidth, image.bgimageHeight = width or 900, height or 600
        image:FireEvent("imageLoaded")
        return image
    end
    local ok, _, _, map = f.M.CreateMap("Fixture map", "map-image", nil, "pointcrawl")
    assert(ok)
    f.M.SetMapShared(map, true)
    local a, b
    ok, _, _, a = f.M.CreateLocation(map, 0.2, 0.3, { visibility = "revealed" }, nil, "A")
    assert(ok)
    ok, _, _, b = f.M.CreateLocation(map, 0.8, 0.7, { visibility = "revealed" }, nil, "B")
    assert(ok)
    local path
    ok, _, _, path = f.P.CreatePath(map, a, b)
    assert(ok)
    f.map, f.a, f.b, f.path = map, a, b, path
    return f
end

function checks.Run()
    local passed = 0
    local function Check(name, run)
        run(Fixture())
        passed = passed + 1
        print("ARTWORK PASS: " .. name)
    end
    for _, kind in ipairs({ "location", "path" }) do
        Check(kind .. ": attach, replace, remove, no-op, Undo, stale Undo", function(f)
            local id = kind == "path" and f.path or f.a
            local update = kind == "path" and f.P.UpdatePath or f.M.UpdateLocation
            local get = function() return f.env.OverlandMapArtwork.Current(kind, id) end
            assert(f.R.ArtworkValue(get()) == "")
            local ok, _, entry = update(id, { artworkImageId = "portrait" })
            assert(ok and #entry.steps == 1 and get().artworkImageId == "portrait")
            local count = #f.writes
            local same, _, none = update(id, { artworkImageId = "portrait" })
            assert(same and none == nil and #f.writes == count)
            assert(f.M.Revert(entry) and f.R.ArtworkValue(get()) == "")
            assert(update(id, { artworkImageId = "portrait" }))
            ok, _, entry = update(id, { artworkImageId = "landscape" })
            assert(ok and f.M.Revert(entry) and get().artworkImageId == "portrait")
            ok, _, entry = update(id, { artworkImageId = "" })
            assert(ok and f.M.Revert(entry) and get().artworkImageId == "portrait")
            assert(f.env.assets.imagesTable.portrait ~= nil)
            assert(update(id, { name = "Newer" }))
            assert(not f.M.CanRevert(entry))
        end)
        Check(kind .. ": player and View as player model permissions", function(f)
            local id = kind == "path" and f.path or f.a
            local update = kind == "path" and f.P.UpdatePath or f.M.UpdateLocation
            f.env.dmhub.isDM = false
            local before = #f.writes
            local ok, reason = update(id, { artworkImageId = "portrait" })
            assert(not ok and reason == "permission" and #f.writes == before)
            if kind == "location" then assert(f.M.CanEdit(f.M.GetLocation(id))) end
            f.env.dmhub.isDM = true
            f.M.SetViewAsPlayer(true)
            assert(not update(id, { artworkImageId = "" }))
        end)
        Check(kind .. ": artwork Undo cannot bypass Director permission", function(f)
            local id = kind == "path" and f.path or f.a
            local update = kind == "path" and f.P.UpdatePath or f.M.UpdateLocation
            local ok, _, entry = update(id, { artworkImageId = "portrait" })
            assert(ok and f.M.CanRevert(entry))
            f.env.dmhub.isDM = false
            assert(not f.M.IsDirector())
            assert(not f.M.CanRevert(entry), "role loss must refuse an Undo that changes artwork")
        end)
        Check(kind .. ": invalid assets and malformed legacy attachments", function(f)
            local id = kind == "path" and f.path or f.a
            local update = kind == "path" and f.P.UpdatePath or f.M.UpdateLocation
            local tableName = kind == "path" and f.C.pathTableName or f.C.locationTableName
            for _, value in ipairs({ "md5:raw", "https://image", "missing", "video", false, 5, {} }) do
                assert(not update(id, { artworkImageId = value }))
                f.tables[tableName][id].artworkImageId = value
                f.M.InvalidateIndex()
                assert(f.env.OverlandMapArtwork.Current(kind, id) ~= nil)
                assert(update(id, { artworkImageId = "" }))
            end
        end)
        Check(kind .. ": local open, close/reopen, timeout and late success", function(f)
            local id = kind == "path" and f.path or f.a
            local update = kind == "path" and f.P.UpdatePath or f.M.UpdateLocation
            assert(update(id, { artworkImageId = "portrait" }))
            local panel = f.Component(kind, false, id)
            assert(panel.data.status == "loading" and #f.requests == 1)
            f.Ready(panel, 0, 0)
            assert(panel.data.status == "loading")
            f.Advance(10)
            assert(panel.data.status == "unavailable")
            f.Ready(panel, 400, 1000)
            assert(panel.data.status == "ready")
            local writes = #f.writes
            local button = f.Click(panel, "Open image")
            assert(#f.views == 1 and f.views[1].owner == button)
            panel:FireEvent("enter")
            assert(#f.views == 2 and #f.writes == writes)
            f.focus = {}
            panel:FireEvent("enter")
            f.focus = nil
            f.modal = {}
            panel:FireEvent("enter")
            f.modal = nil
            f.ctx.data.popover = "search"
            panel:FireEvent("enter")
            f.ctx.data.popover = nil
            assert(#f.views == 2)
            local canvas = f.env.gui.Panel { id = "overland-map-canvas" }
            f.ctx.root:AddChild(canvas)
            f.focus = canvas
            panel:FireEvent("enter")
            assert(#f.views == 3, "the normal map-canvas focus must allow Enter")
            f.focus = nil
            assert(update(id, { artworkImageId = "landscape" }))
            button:FireEvent("click")
            assert(#f.views == 3 and f.views[1].image == "portrait")
            f.ctx.RefreshAll()
            f.Ready(panel, 1200, 400)
            f.Click(panel, "Open image")
            assert(f.views[4].image == "landscape")
        end)
        Check(kind .. ": picker None, cancellation, duplicate callbacks and unrelated edits", function(f)
            local id = kind == "path" and f.path or f.a
            local update = kind == "path" and f.P.UpdatePath or f.M.UpdateLocation
            local panel = f.Component(kind, true, id)
            local before = #f.writes
            f.Click(panel, "Choose image...")
            local canceled = panel.data.picker
            canceled.popup = nil
            canceled:SetValue("portrait")
            assert(#f.writes == before)
            f.Click(panel, "Choose image...")
            assert(update(id, kind == "path" and { description = "Unrelated edit" } or { name = "Unrelated edit" }))
            local picker = f.Pick(panel, "portrait")
            picker:FireEvent("change")
            assert(#f.pushes == 1 and f.pushes[1].text == "artwork.updated")
            f.Click(panel, "Replace image...")
            f.Pick(panel, "")
            assert(#f.pushes == 2 and f.pushes[2].text == "artwork.removed")
            assert(f.M.Revert(f.pushes[2].entry))
            assert(f.env.OverlandMapArtwork.Current(kind, id).artworkImageId == "portrait")
        end)
        Check(kind .. ": chooser conflicts and cancellation on navigation or unload", function(f)
            local id = kind == "path" and f.path or f.a
            local update = kind == "path" and f.P.UpdatePath or f.M.UpdateLocation
            local panel = f.Component(kind, true, id)
            f.Click(panel, "Choose image...")
            assert(update(id, { artworkImageId = "third" }))
            f.Pick(panel, "portrait")
            assert(f.env.OverlandMapArtwork.Current(kind, id).artworkImageId == "third")
            assert(f.notices[#f.notices].id == "artwork.changed")
            f.ctx.RefreshAll()
            f.Click(panel, "Replace image...")
            local picker = panel.data.picker
            f.ctx.data.panelMode = "none"
            f.ctx.RefreshAll()
            picker:SetValue("landscape")
            assert(f.env.OverlandMapArtwork.Current(kind, id).artworkImageId == "third")
            f.ctx.data.panelMode = panel.data.mode
            f.ctx.RefreshAll()
            f.Click(panel, "Replace image...")
            f.mod.unloaded = true
            panel.data.picker:SetValue("landscape")
            assert(f.env.OverlandMapArtwork.Current(kind, id).artworkImageId == "third")
        end)
        Check(kind .. ": busy retry preserves newer attachment and rechecks permission", function(f)
            local id = kind == "path" and f.path or f.a
            local update = kind == "path" and f.P.UpdatePath or f.M.UpdateLocation
            local panel = f.Component(kind, true, id)
            f.Click(panel, "Choose image...")
            f.writeMode = "pending"
            assert(update(id, { name = "Pending edit" }))
            f.Pick(panel, "portrait")
            local write = f.writes[#f.writes]
            write.callbacks.success()
            f.writeMode = nil
            f.Advance(f.C.busyRetryDelay)
            assert(f.env.OverlandMapArtwork.Current(kind, id).artworkImageId == "portrait" and #f.pushes == 1)
            f.Click(panel, "Replace image...")
            f.writeMode = "pending"
            assert(update(id, { name = "Another pending edit" }))
            f.Pick(panel, "landscape")
            f.env.dmhub.isDM = false
            f.writes[#f.writes].callbacks.success()
            f.Advance(f.C.busyRetryDelay)
            assert(f.env.OverlandMapArtwork.Current(kind, id).artworkImageId == "portrait")
        end)
        Check(kind .. ": failed upload Retry and one Undo entry", function(f)
            local id = kind == "path" and f.path or f.a
            local panel = f.Component(kind, true, id)
            f.writeMode = "fail"
            f.Click(panel, "Choose image...")
            f.Pick(panel, "portrait")
            assert(#f.pushes == 0 and f.notices[#f.notices].id == "toast.saveFailed")
            local before = #f.writes
            f.writeMode = nil
            assert(f.notices[#f.notices].retry)()
            assert(#f.writes == before + 1 and #f.pushes == 1,
                string.format("failed optimistic retry: writes=%d expected=%d, Undo entries=%d, last=%s", #f.writes,
                    before + 1, #f.pushes, f.R.LastWrite(kind == "path" and f.C.pathTableName or f.C.locationTableName, id).status))
            assert(f.M.Revert(f.pushes[1].entry))
            assert(f.R.ArtworkValue(f.env.OverlandMapArtwork.Current(kind, id)) == "")
        end)
        Check(kind .. ": a started write keeps Undo after the editor closes", function(f)
            local id = kind == "path" and f.path or f.a
            local panel = f.Component(kind, true, id)
            f.writeMode = "pending"
            f.Click(panel, "Choose image...")
            f.Pick(panel, "portrait")
            f.ctx.data.panelMode = "none"
            f.ctx.RefreshAll()
            f.writes[#f.writes].callbacks.success()
            f.Advance(f.C.saveRecheckDelay)
            assert(#f.pushes == 1 and f.M.CanRevert(f.pushes[1].entry))
        end)
        Check(kind .. ": an immediately refused optimistic upload can retry", function(f)
            local id = kind == "path" and f.path or f.a
            local panel = f.Component(kind, true, id)
            f.writeMode = "refused"
            f.Click(panel, "Choose image...")
            f.Pick(panel, "portrait")
            local before = #f.writes
            assert(f.notices[#f.notices].id == "toast.saveFailed")
            f.writeMode = nil
            f.notices[#f.notices].retry()
            assert(#f.writes == before + 1 and #f.pushes == 1,
                "refused upload retry notice: " .. f.notices[#f.notices].id)
        end)
    end
    Check("visibility, unavailable assets, retry and stale image callbacks", function(f)
        assert(f.P.UpdatePath(f.path, { artworkImageId = "portrait" }))
        local panel = f.Component("path", false, f.path)
        local stale = panel.data.image
        f.M.SetVisibility(f.a, "hidden")
        f.M.SetViewAsPlayer(true)
        f.ctx.RefreshAll()
        assert(panel:HasClass("collapsed") and f.env.OverlandMapArtwork.Current("path", f.path) == nil)
        f.M.SetViewAsPlayer(false)
        assert(f.P.UpdatePath(f.path, { artworkImageId = "landscape" }))
        f.ctx.RefreshAll()
        stale.bgimageWidth, stale.bgimageHeight = 500, 500
        stale:FireEvent("imageLoaded")
        assert(panel.data.status == "loading")
        f.Advance(10)
        local before = #f.requests
        f.Click(panel, "Retry")
        assert(#f.requests == before + 1 and panel.data.status == "loading")
        for _, value in ipairs({ "missing", "video", "restricted", 123 }) do
            f.tables[f.C.pathTableName][f.path].artworkImageId = value
            f.M.InvalidateIndex()
            f.ctx.RefreshAll()
            assert(panel.data.status == "unavailable")
            panel:FireEvent("enter")
        end
        assert(#f.views == 0)
        f.tables[f.C.pathTableName][f.path].artworkImageId = "recovering"
        f.M.InvalidateIndex()
        f.ctx.RefreshAll()
        f.env.assets.imagesTable.recovering = { imageid = "recovered-bytes", loaded = true, HaveReadPermissions = function() return true end }
        panel:FireEvent("refreshAssets")
        f.Ready(panel)
        assert(panel.data.status == "ready")
    end)
    Check("player-owned edit preview and view-only controls", function(f)
        assert(f.M.UpdateLocation(f.a, { artworkImageId = "portrait" }))
        f.env.dmhub.isDM = false
        local panel = f.Component("location", true, f.a)
        f.Ready(panel)
        local choose = panel:FindChildRecursive(function(child) return child.text == "Replace image..." end)
        assert(choose ~= nil and not choose.enabled)
        f.Click(panel, "Open image")
        choose:FireEvent("click")
        assert(panel.data.picker == nil and #f.views == 1)
    end)
    Check("the existing viewer fits its window and retains its size cap", function(f)
        assert(f.M.UpdateLocation(f.a, { artworkImageId = "portrait" }))
        local panel = f.Component("location", false, f.a)
        f.ctx.root.renderedWidth, f.ctx.root.renderedHeight = 720, 480
        f.Ready(panel, 600, 800)
        f.Click(panel, "Open image")
        local view = f.views[#f.views]
        assert((view.height or 800) <= 480 and (view.width or 600) <= 720, "portrait must fit the native viewport")
        assert(math.abs(view.width / view.height - 0.75) < 0.001)
        f.ctx.root.renderedWidth, f.ctx.root.renderedHeight = 3000, 2000
        f.Ready(panel, 4000, 2000)
        f.Click(panel, "Open image")
        view = f.views[#f.views]
        assert(view.width == 1024 and view.height == 512, "keep the existing 1024-pixel viewer cap")
    end)
    Check("map operations and deletion Undo preserve full artwork rows", function(f)
        assert(f.M.UpdateLocation(f.a, { artworkImageId = "portrait" }))
        assert(f.M.AddMap(f.a, "nested-map"))
        assert(f.M.ReplaceImage(f.a, "replacement-map"))
        assert(f.M.GetLocation(f.a).artworkImageId == "portrait")
        assert(f.M.RemoveMap(f.a))
        assert(f.M.GetLocation(f.a).artworkImageId == "portrait")
        assert(f.P.UpdatePath(f.path, { artworkImageId = "landscape" }))
        f.env.dmhub.isDM = false
        local ok, _, entry = f.M.DeleteLocation(f.a)
        assert(ok and f.M.GetLocation(f.a) == nil and f.P.Get(f.path) == nil)
        assert(f.M.Revert(entry))
        assert(f.M.GetLocation(f.a).artworkImageId == "portrait" and f.P.Get(f.path).artworkImageId == "landscape")
    end)
    Check("large map indexes never load artwork", function(f)
        local original = f.tables[f.C.locationTableName][f.a]
        for i = 1, 3000 do
            local row = Copy(original)
            row.id, row.artworkImageId = "large-" .. i, "portrait"
            f.tables[f.C.locationTableName][row.id] = row
        end
        f.M.InvalidateIndex()
        assert(#f.M.Children(f.map) == 3002)
        f.P.Index()
        assert(#f.requests == 0)
    end)
    print("ARTWORK CHECKS: " .. passed .. " isolated checks passed")
    return passed
end

if ... == "run" then checks.Run() end
return checks
