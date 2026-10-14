-- Production model/queue checks in an isolated Lua environment; no live game data.
local checks = {}
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = source:match("^(.*)/tests/[^/]+$") or "Region Map"
local function Copy(v)
    if type(v) ~= "table" then return v end
    local r = {}; for k, x in pairs(v) do r[k] = Copy(x) end; return r
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function Fixture()
    local f = { tables = {}, timers = {}, writes = {}, now = 0, sequence = 0, notices = {} }
    local env = setmetatable({}, { __index = _G }) --[[@as table<string, any>]]
    env._G = env; f.env = env
    local document = { data = {}, path = "labels-fixture", BeginChange = function() end, CompleteChange = function() end }
    f.mod = { unloaded = false, GetDocumentSnapshot = function() return document end, RegisterDocumentForCheckpointBackups = function() end }
    env.setting = function() end
    env.RegisterGameType = function() return { new = function(v) return v or {} end } end
    env.DeepCopy, env.ServerTimestamp = Copy, function() return f.now end
    env.RegionMapJournal, env.RegionMapLog = {}, { Add = function() end }
    env.gui = { availableFonts = { "berling", "courier", "liberationsans" } }
    env.dmhub = {
        isDM = true, loginUserid = "director", userDisplayName = "Fixture", tablesUpdateId = 0,
        GetModLoading = function() return f.mod end,
        GenerateGuid = function() f.sequence = f.sequence + 1; return "label-test-" .. f.sequence end,
        GetTable = function(n) f.tables[n] = f.tables[n] or {}; return f.tables[n] end,
        DeepEqual = Equal,
        Schedule = function(delay, fn) table.insert(f.timers, { at = f.now + delay, fn = fn }) end,
        SetAndUploadTableItem = function(n, row, cb)
            f.writes[#f.writes + 1] = { row = Copy(row), callbacks = cb }
            env.dmhub.GetTable(n)[row.id] = Copy(row)
            env.dmhub.tablesUpdateId = env.dmhub.tablesUpdateId + 1
            if f.mode == "fail" then cb.failure("test failure") elseif f.mode ~= "pending" then cb.success() end
            return row.id
        end,
    }
    function f.Advance(seconds)
        local untilTime = f.now + seconds
        for _ = 1, 10000 do
            local nextIndex, nextTimer
            for i, t in ipairs(f.timers) do
                if t.at <= untilTime and (nextTimer == nil or t.at < nextTimer.at) then nextIndex, nextTimer = i, t end
            end
            if not nextTimer then f.now = untilTime; return end
            table.remove(f.timers, nextIndex); f.now = nextTimer.at; nextTimer.fn()
        end
        error("timer did not settle")
    end
    for _, name in ipairs({ "RegionMapConstants", "RegionMapCopy", "RegionMapRecords", "RegionMapModel", "RegionMapUndo", "RegionMapLabels", "RegionMapPaths" }) do
        assert(loadfile(directory .. "/" .. name .. ".lua", "t", env))()
    end
    f.C, f.R, f.M, f.L, f.U = env.RegionMapConstants, env.RegionMapRecords, env.RegionMapModel, env.RegionMapLabels, env.RegionMapUndo
    local ok, _, _, id = f.M.CreateMap("Label fixture", "map-image")
    assert(ok and id ~= nil); f.map = id; assert(f.M.SetMapShared(id, true))
    function f.Create(text, map)
        local yes, reason, entry, labelId = f.L.Create(map or f.map, 0.4, 0.6, { text = text or "Northern\nKingdom" })
        assert(yes, tostring(reason)); return labelId, entry
    end
    return f
end

function checks.Run()
    local passed = 0
    local function Check(name, fn)
        fn(Fixture()); passed = passed + 1; print("LABEL PASS: " .. name)
    end
    Check("create multiline, format, no-op, delete and Undo", function(f)
        local id = f.Create()
        assert(f.L.Get(id).visibility == "hidden")
        assert(f.L.Update(id, { font = "courier", size = 0.08, angle = 225, bold = true, background = "plate" }))
        assert(f.L.Get(id).angle == -135)
        local n = #f.writes
        assert(f.L.Update(id, { size = 0.08 })); assert(#f.writes == n)
        local ok, _, entry = f.L.Delete(id); assert(ok and f.L.Get(id) == nil)
        assert(f.M.Revert(entry)); assert(f.L.Get(id).font == "courier")
    end)
    Check("permission off, own-only, visibility, player preview and Undo revocation", function(f)
        local directorId = f.Create("Director")
        assert(f.L.Update(directorId, { visibility = "revealed" }))
        f.env.dmhub.isDM, f.env.dmhub.loginUserid = false, "player"
        assert(not f.L.CanAdd(f.map)); assert(not f.L.Create(f.map, 0, 0, { text = "No" }))
        f.env.dmhub.isDM = true; assert(f.L.SetPlayersCanManage(true)); f.env.dmhub.isDM = false
        local id = f.Create("Player")
        assert(f.L.Get(id).visibility == "revealed")
        assert(not f.L.Update(directorId, { text = "Stolen" }))
        assert(not f.L.Update(id, { visibility = "hidden" }))
        local ok, _, entry = f.L.Update(id, { text = "Own" }); assert(ok)
        f.env.dmhub.isDM = true; assert(f.L.SetPlayersCanManage(false)); f.env.dmhub.isDM = false
        assert(not f.L.Update(id, { text = "Frozen" })); assert(not f.M.Revert(entry))
        f.env.dmhub.isDM = true; f.M.SetViewAsPlayer(true)
        assert(not f.L.Update(id, { text = "Preview" })); assert(not f.L.SetPlayersCanManage(true))
    end)
    Check("hidden labels and unshared maps never enter search", function(f)
        local id = f.Create("Secret")
        f.env.dmhub.isDM = false
        assert(f.L.Get(id) == nil and #f.L.Search("Secret", 20) == 0)
        f.env.dmhub.isDM = true; assert(f.L.Update(id, { visibility = "revealed" }))
        f.env.dmhub.isDM = false; assert(#f.L.Search("secret", 20) == 1)
        f.env.dmhub.isDM = true; assert(f.M.SetMapShared(f.map, false)); f.env.dmhub.isDM = false
        assert(#f.L.ForMap(f.map) == 0 and #f.L.Search("Secret", 20) == 0)
    end)
    Check("invalid writes preserve rows and optional fonts recover", function(f)
        local id = f.Create()
        for _, changes in ipairs({ { text = "  \n " }, { size = 0 / 0 }, { spacing = 2 }, { font = "missing" },
            { color = "red" }, { ownerId = "other" }, { mapId = "other" }, { text = string.rep("x", 257) } }) do
            assert(not f.L.Update(id, changes))
        end
        f.L.Table()[id].font = "missing"
        f.M.InvalidateIndex()
        assert(f.L.Get(id) ~= nil and f.L.DisplayFont("missing") == "berling")
    end)
    Check("map replacement, subtree deletion and Undo", function(f)
        local id = f.Create()
        assert(f.M.ReplaceImage(f.map, "other-image"))
        assert(f.L.Get(id).u == 0.4)
        local ok, _, entry = f.M.DeleteLocation(f.map)
        assert(ok and f.L.Get(id) == nil and f.M.CanRevert(entry))
        assert(f.M.Revert(entry)); assert(f.L.Get(id) ~= nil)
    end)
    Check("autosave creates once and coalesces fields; close flushes", function(f)
        local id = f.L.NewDraft(f.map, 0.3, 0.7)
        assert(f.L.Get(id) == nil)
        assert(f.L.Stage(id, { text = "New" })); f.Advance(0.5)
        assert(f.L.Stage(id, { bold = true })); f.L.Leave(id); f.Advance(0)
        assert(f.L.Get(id).text == "New" and f.L.Get(id).bold)
        assert(f.L.Status(id) == "saved")
        assert(f.U.UndoLast()); f.Advance(0)
        assert(f.L.Get(id) == nil)
    end)
    Check("queued drag follows pending text, with chained Undo", function(f)
        local id = f.Create("Before")
        f.mode = "pending"
        f.L.Stage(id, { text = "After" }); f.L.Flush(id)
        local first = #f.writes
        f.L.Commit(id, { u = 0.9 }, "moved"); assert(#f.writes == first)
        f.writes[first].callbacks.success(); f.Advance(0)
        assert(#f.writes == first + 1)
        f.writes[#f.writes].callbacks.success(); f.Advance(0)
        f.mode = nil
        assert(f.U.UndoLast()); f.Advance(0); assert(f.L.Get(id).u == 0.4)
        assert(f.U.UndoLast()); f.Advance(0); assert(f.L.Get(id).text == "Before")
    end)
    Check("failed create Retry keeps id and correct creation Undo", function(f)
        local id = f.L.NewDraft(f.map, 0.1, 0.2)
        f.mode = "fail"; f.L.Stage(id, { text = "Retry" }); f.L.Flush(id); f.Advance(0)
        assert(f.L.Status(id) == "failed" and f.L.Get(id) == nil)
        f.mode = nil; f.L.Retry(id); f.Advance(0)
        assert(f.L.Get(id).text == "Retry")
        assert(f.U.UndoLast()); f.Advance(0); assert(f.L.Get(id) == nil)
    end)
    Check("revocation cancels unsent work without deleting accepted create", function(f)
        assert(f.L.SetPlayersCanManage(true)); f.env.dmhub.isDM, f.env.dmhub.loginUserid = false, "player"
        local id = f.L.NewDraft(f.map, 0.1, 0.2)
        f.mode = "pending"; f.L.Stage(id, { text = "Accepted" }); f.L.Flush(id)
        f.L.Stage(id, { text = "Unsent" })
        f.env.dmhub.isDM = true; assert(f.L.SetPlayersCanManage(false)); f.env.dmhub.isDM = false
        local n = #f.writes
        f.writes[n].callbacks.success(); f.Advance(2)
        assert(#f.writes == n and f.L.Get(id).text == "Accepted")
    end)
    Check("blank drafts and stale Undo never write", function(f)
        local id = f.L.NewDraft(f.map, 0, 0); local n = #f.writes
        f.L.Leave(id); assert(#f.writes == n and f.L.Snapshot(id) == nil)
        id = f.Create("First")
        local ok, _, entry = f.L.Update(id, { text = "Second" }); assert(ok)
        assert(f.L.Update(id, { text = "Remote" })); assert(not f.M.Revert(entry))
    end)
    Check("invalid preview and direct transforms cannot poison the canvas", function(f)
        local id = f.Create()
        assert(not f.L.Stage(id, { u = 0/0 }))
        assert(not f.L.Stage(id, { mapId = "other" }))
        assert(not f.L.Commit(id, { size = -1 }, "resized"))
        assert(f.L.Snapshot(id).u == 0.4 and f.L.Snapshot(id).size == 0.03)
    end)
    Check("duplicate receipts and unload never produce additional writes", function(f)
        local id = f.Create()
        f.mode = "pending"; f.L.Stage(id, { text = "One write" }); f.L.Flush(id)
        local n = #f.writes
        f.writes[n].callbacks.success(); f.writes[n].callbacks.success(); f.Advance(0)
        assert(#f.writes == n and f.L.Status(id) == "saved")
        f.L.Stage(id, { text = "Unloaded" }); f.mod.unloaded = true; f.Advance(3)
        assert(#f.writes == n)
    end)
    Check("cancelled failed batches do not poison later editing", function(f)
        local id = f.Create("Before")
        f.mode = "fail"; f.L.Stage(id, { text = "Failed" }); f.L.Flush(id); f.Advance(0)
        assert(f.L.Status(id) == "failed")
        f.L.CancelPending(id); f.mode = nil
        assert(f.L.Stage(id, { text = "Recovered" })); f.L.Flush(id); f.Advance(0)
        assert(f.L.Status(id) == "saved" and f.L.Get(id).text == "Recovered")
    end)
    Check("player deletion Undo and permission-setting bypass are guarded", function(f)
        assert(f.L.SetPlayersCanManage(true))
        f.env.dmhub.isDM, f.env.dmhub.loginUserid = false, "player"
        local id = f.Create("Own label")
        local ok, _, entry = f.L.Delete(id)
        assert(ok and f.M.Revert(entry) and f.L.Get(id).ownerId == "player")
        assert(f.M.WriteStateKey("playersCanManageLabels", true, "Bypass") == nil)
        assert(not f.L.SetPlayersCanManage(false))
    end)
    Check("Unicode character and byte limits remain distinct", function(f)
        local text = string.rep(utf8.char(0x1F30A), 256)
        local id = f.Create(text)
        assert(f.L.Get(id).text == text and #text == 1024)
        assert(not f.L.Update(id, { text = text .. "x" }))
        assert(not f.L.Update(id, { text = "Sea" .. string.char(0) .. "Name" }))
        assert(f.L.Update(id, { text = "Northern\r\nKingdom" }))
        assert(f.L.Get(id).text == "Northern\nKingdom")
    end)
    Check("removing a nested map includes its own labels and restores them", function(f)
        local ok, _, _, child = f.M.CreateLocation(f.map, 0.2, 0.2, nil, nil, "Nested")
        assert(ok and f.M.AddMap(child, "nested-image"))
        local id = f.Create("Inside", child)
        local removed, _, entry = f.M.RemoveMap(child)
        assert(removed and f.L.Get(id) == nil and f.M.GetLocation(child).imageId == "")
        assert(f.M.CanRevert(entry) and f.M.Revert(entry))
        assert(f.L.Get(id).mapId == child and f.M.GetLocation(child).imageId == "nested-image")
    end)
    Check("search keyboard scope and field-exit preserve the chosen result", function(f)
        local alpha = f.Create("Coast Alpha")
        local beta = f.Create("Coast Beta")
        local function Panel(args)
            local p = { data = args.data or {}, children = args.children or {}, text = args.text or "", classes = {}, valid = true, enabled = true }
            if args.children == nil then for _, child in ipairs(args) do p.children[#p.children + 1] = child end end
            for _, class in ipairs(args.classes or {}) do p.classes[class] = true end
            p.SetClass = function(self, name, on) self.classes[name] = on end
            p.HasClass = function(self, name) return self.classes[name] == true end
            p.FireEvent = function(self, name, ...) if args[name] then return args[name](self, ...) end end
            return p
        end
        f.keys = {}
        f.env.dmhub.KeyPressed = function(key) return f.keys[key] == true end
        f.env.gui.Panel, f.env.gui.Label, f.env.gui.SearchInput = Panel, Panel, Panel
        f.env.gui.SetFocus = function(p) p.hasFocus = true; p:FireEvent("focus") end
        f.env.RegionMapSession = {
            Label = function(classes, text) return Panel { classes = classes, text = text } end,
            Button = function(text, click) return Panel { text = text, click = click } end,
            SetText = function(p, text) p.text = text end,
            FocusSoon = function(p) f.env.gui.SetFocus(p) end,
        }
        assert(loadfile(directory .. "/RegionMapPopovers.lua", "t", f.env))()
        local build
        for i = 1, 30 do
            local name, value = debug.getupvalue(f.env.RegionMapPopovers.Create, i)
            if name == nil then break end
            if name == "BuildSearch" then build = value end
        end
        assert(build)
        local ctx = { data = { popover = "search" } }
        ctx.SetPopover = function(value) ctx.data.popover = value end
        ctx.FocusLabel = function(id, edit) ctx.opened = { id = id, edit = edit } end
        ctx.FocusLocation = function(id) ctx.opened = { id = id } end
        local body = build(ctx)
        local input, results = body.children[1], body.children[4]
        body.data.open(); input.text = "Coast"; input:FireEvent("edit")
        assert(#results.children == 2)
        f.keys.DownArrow = true; input:FireEvent("think"); f.keys.DownArrow = false; input:FireEvent("think")
        assert(results.children[2]:HasClass("keyboardSelected"))
        local row = results.children[2]
        input:FireEvent("change"); assert(results.children[2] == row)
        input:FireEvent("submit"); assert(ctx.opened.id == beta and not ctx.opened.edit)
        ctx.data.popover = "search"; body.data.open(); input.text = "Coast Alpha"; input:FireEvent("edit")
        f.keys.LeftControl = true; input:FireEvent("submit"); assert(ctx.opened.id == alpha and ctx.opened.edit)
        ctx.opened = nil; ctx.data.popover = "search"; input.hasFocus = false
        input:FireEvent("submit"); assert(ctx.opened == nil)
    end)
    Check("automatic backing contrasts with dark and light text", function(f)
        assert(loadfile(directory .. "/RegionMapLabelLayer.lua", "t", f.env))()
        local contrast = f.env.RegionMapLabelLayer.Contrast
        assert(contrast("#000000ff") == "#ffffffff")
        assert(contrast("#ffffffff") == "#000000ff")
        assert(contrast("#808080ff") == "#000000ff")
    end)
    print("LABEL CHECKS: " .. passed .. " passed")
    return passed
end
if ... == "run" then checks.Run() end
return checks
