local checks = {}
local Base = dofile("Overland Map/tests/LabelChecks.lua")

local function GestureFixture(f)
    f.env.OverlandMapControls = { CloseContextMenu = function() end }
    f.env.OverlandMapCanvasTools = {}
    f.env.gui.SetFocus = function() end
    assert(loadfile("Overland Map/OverlandMapPathTool.lua", "t", f.env))()
    local _, _, _, map = f.M.CreateMap("Gesture fixture", "map-image", nil, "pointcrawl")
    local _, _, _, a = f.M.CreateLocation(map, 0.2, 0.3)
    local _, _, _, b = f.M.CreateLocation(map, 0.8, 0.7)
    local _, _, _, pin = f.M.CreateLocation(map, 0.5, 0.5)
    local _, _, _, path = f.env.OverlandMapPaths.CreatePath(map, a, b, { bends = { { u = 0.5, v = 0.5 } } })
    local ctx = { data = { mapId = map, selectedPathId = path, panelMode = "pathEdit", tool = "none", locked = false,
        camera = { zoom = 1, centerX = 0.5, centerY = 0.5 } },
        CurrentMap = function() return f.M.GetLocation(map) end, RefreshAll = function() end,
        Report = function(ok, reason) assert(ok, tostring(reason)); return ok end }
    f.pushes = 0
    ctx.Push = function(entry) assert(#entry.steps == 1); f.pushes = f.pushes + 1 end
    f.down = true
    local canvas = { mousePoint = { x = 0.5, y = 0.5 }, renderedWidth = 100, renderedHeight = 100,
        GetMouseButton = function() return f.down end }
    local state = f.env.OverlandMapSession.CanvasState()
    state.mapId, state.layout = map, { x = 0, y = 0, width = 100, height = 100 }
    local gestures = f.env.OverlandMapGestures.Create(function() return true end)
    local handle = { kind = "bend", index = 1 }
    local layers = { path = { HandleAt = function() return handle end,
        HandlePoints = function() return { { u = 0.2, v = 0.3 }, { u = 0.5, v = 0.5 }, { u = 0.8, v = 0.7 } } end,
        SetHandles = function() end }, labels = { HandleAt = function() end }, aids = { HandleAt = function() end } }
    local input = f.env.OverlandMapGestures.Canvas(ctx, state, gestures, layers,
        { Canvas = function() return canvas end, Layout = function() end, camera = { Stop = function() return false end, Save = function() end } })
    return { input = input, gestures = gestures, canvas = canvas, path = path, pin = pin, ctx = ctx, handle = handle }
end

function checks.Run()
    local passed = 0
    local function Check(name, fn)
        local f = Base.Fixture()
        f.env.OverlandMapJournal.ResolveForViewer = function() return { status = "empty" } end
        assert(loadfile("Overland Map/OverlandMapEditors.lua", "t", f.env))()
        assert(loadfile("Overland Map/OverlandMapGestures.lua", "t", f.env))()
        fn(f)
        passed = passed + 1
        print("LIFETIME PASS: " .. name)
    end

    Check("fresh stores and sidecars leave old development rows alone", function(f)
        assert(f.C.locationTableName == "OverlandMapLocations")
        assert(f.C.labelTableName == "OverlandMapLabels")
        assert(f.C.stateDocumentId == "overlandMapState")
        assert(f.C.preferencesSettingId == "overlandmap:preferences")
        assert(f.M.SaveDetails(f.map, { description = "Independent description" }))
        assert(f.M.SaveDirectorNote(f.map, "Independent note"))
        for _, name in ipairs({ f.C.detailsTableName, f.C.notesTableName }) do
            assert(f.tables[name][f.map].locationId == f.map)
            assert(f.tables[name][f.map].labelId == nil and f.tables[name][f.map].schemaVersion == 1)
        end
        for name in pairs(f.tables) do assert(not name:match("^RegionMap")) end
    end)
    Check("multiple observers detach independently", function(f)
        local id = f.Create("Before")
        local first, second = 0, 0
        local detach = f.L.Observe(id, function() first = first + 1 end)
        local release = f.L.Observe(id, function() second = second + 1 end)
        f.L.Stage(id, { text = "One" })
        assert(first > 0 and first == second)
        detach(); detach()
        local oldFirst, oldSecond = first, second
        f.L.Stage(id, { text = "Two" })
        assert(first == oldFirst and second > oldSecond)
        release()
    end)
    Check("closing an editor detaches it while its three lanes finish", function(f)
        local notifications = 0
        local editor = f.env.OverlandMapEditors.Create("location", function() notifications = notifications + 1 end)
        editor.Bind(f.map)
        f.mode = "pending"
        editor.Stage(f.map, "name", "Renamed")
        editor.Stage(f.map, "description", "Description")
        editor.Stage(f.map, "note", "Secret")
        local before = #f.writes
        editor.Destroy()
        assert(#f.writes == before + 3)
        local closed = notifications
        for i = before + 1, #f.writes do f.writes[i].callbacks.success() end
        f.Advance(0)
        assert(notifications == closed)
        assert(f.M.GetLocation(f.map).name == "Renamed")
        assert(f.M.Details(f.map).description == "Description")
        assert(f.M.DirectorNote(f.map) == "Secret")
    end)
    Check("failed lane Retry retains the original Undo image", function(f)
        assert(f.M.SaveDetails(f.map, { description = "Before" }))
        local editor = f.env.OverlandMapEditors.Create("location", function() end)
        editor.Bind(f.map)
        f.mode = "fail"
        editor.Stage(f.map, "description", "After")
        editor.Flush(); f.Advance(0)
        assert(editor.Status(f.map) == "failed")
        f.mode = nil
        editor.Retry(f.map); f.Advance(0)
        assert(editor.Status(f.map) == "saved")
        assert(f.U.UndoLast()); f.Advance(0)
        assert(f.M.Details(f.map).description == "Before")
    end)
    Check("failed and pending table receipts cannot authorize Undo", function(f)
        f.mode = "pending"
        local ok, _, entry = f.M.UpdateLocation(f.map, { name = "Uncertain" })
        assert(ok and not f.M.CanRevert(entry))
        f.writes[#f.writes].callbacks.failure("Unavailable")
        assert(not f.M.CanRevert(entry))
    end)
    Check("old-game timers and receipts cannot reach a replacement game", function(f)
        local id = f.Create("Before")
        f.mode = "pending"
        f.L.Stage(id, { text = "Accepted" }); f.L.Flush(id)
        local pending = f.writes[#f.writes]
        f.L.Stage(id, { text = "Unsent" })
        f.env.dmhub.gameid = "replacement-game"
        for _, callback in ipairs(f.mod.enterGameHandlers) do callback() end
        local count = #f.writes
        pending.callbacks.success(); f.Advance(5)
        assert(#f.writes == count and not f.U.HasUndo())
        assert(f.L.Status(id) == "saved")
    end)
    Check("owner replacement and destruction invalidate image and view callbacks", function(f)
        local owner = f.env.OverlandMapLifetime.Owner("first")
        local first = owner:Guard()
        owner:Bind("second")
        assert(not first())
        local second = owner:Guard()
        assert(second())
        owner:Destroy()
        assert(not second())
    end)
    Check("dimensions do not confirm texture readiness and late success recovers", function(f)
        local events = {}
        local request = f.env.OverlandMapImages.Request {
            id = "asset", source = "source-1", valid = function() return true end,
            changed = function(result) events[#events + 1] = result.status end,
        }
        assert(request.Dimensions(4000, 2000) and request.dimensionsKnown and not request.textureReady)
        f.Advance(f.C.artworkTimeout)
        assert(request.status == "unavailable")
        assert(request.Loaded(4000, 2000) and request.status == "ready")
        assert(not request.Loaded(4000, 2000) and #events == 2)
        request.Cancel()
        assert(not request.Loaded(6000, 3000) and #events == 2)
    end)
    Check("asset replacement invalidates both success and failure", function(f)
        local active, calls = true, 0
        local request = f.env.OverlandMapImages.Request {
            id = "asset", source = "source-1", valid = function() return active end,
            changed = function() calls = calls + 1 end,
        }
        active = false
        request.Failed(); request.Loaded(20, 20); f.Advance(20)
        assert(calls == 0)
    end)
    Check("one release commits once and suppresses only its matching click", function(f)
        local gesture = f.env.OverlandMapGestures.Create(function() return true end)
        local capture = { startX = 10, startY = 10, moved = false, button = 0 }
        assert(gesture.Begin(capture))
        assert(gesture.Update(11, 11, true) == "active" and not capture.moved)
        gesture.Update(10 + f.C.canvasDragThreshold, 10, true)
        assert(capture.moved and gesture.Update(50, 50, false) == "released")
        assert(gesture.Commit() == capture and gesture.Commit() == nil)
        assert(gesture.ConsumeRelease(0) and not gesture.ConsumeRelease(0))
    end)
    Check("cancelled or revoked gestures never commit", function(f)
        local allowed = true
        local gesture = f.env.OverlandMapGestures.Create(function() return allowed end)
        gesture.Begin { startX = 0, startY = 0, moved = false, button = 2 }
        gesture.Cancel()
        assert(gesture.Commit() == nil)
        gesture.Begin { startX = 0, startY = 0, moved = false, button = 0 }
        allowed = false
        assert(gesture.Update(20, 20, false) == "cancelled" and gesture.Commit() == nil)
    end)
    Check("selected bend wins over an overlapping pin and commits one path operation", function(f)
        local g = GestureFixture(f)
        g.input.PinHandlers.press { data = { id = g.pin }, GetMouseButton = function() return true end }
        assert(g.gestures.current.kind == "bend" and g.gestures.current.id == g.path)
        g.input.Poll(g.canvas, 70, 80)
        f.down = false
        g.input.Poll(g.canvas, 70, 80); g.input.Poll(g.canvas, 70, 80)
        local path = f.env.OverlandMapPaths.Get(g.path)
        assert(path.revision == 2 and path.bends[1].u == 0.7 and path.bends[1].v == 0.8)
        assert(f.M.GetLocation(g.pin).revision == 1 and f.pushes == 1)
    end)
    Check("selected insertion handle wins over the Party without moving it", function(f)
        local g = GestureFixture(f)
        g.handle.kind = "plus"
        g.input.PartyHandlers.press { data = { party = { mapId = g.ctx.data.mapId } }, GetMouseButton = function() return true end }
        assert(g.gestures.current.kind == "bend" and g.gestures.current.insert)
        g.input.Poll(g.canvas, 70, 80)
        f.down = false; g.input.Poll(g.canvas, 70, 80)
        assert(#f.env.OverlandMapPaths.Get(g.path).bends == 2 and f.M.Party() == nil and f.pushes == 1)
    end)
    Check("right click deletes a selected bend beneath a pin without opening its menu", function(f)
        local g = GestureFixture(f)
        g.ctx.ShowMenu = function() error("overlapping pin consumed the bend action") end
        g.input.PinHandlers.rightClick { data = { id = g.pin } }
        assert(#f.env.OverlandMapPaths.Get(g.path).bends == 0 and f.pushes == 1)
        assert(f.M.GetLocation(g.pin).revision == 1)
    end)
    Check("double-click editing survives the second release and a later click still selects", function(f)
        local g = GestureFixture(f)
        g.ctx.data.selectedPathId = nil
        g.ctx.Select = function(id, mode) g.ctx.data.selectedId, g.ctx.data.panelMode = id, mode end
        local pin = { data = { id = g.pin }, GetMouseButton = function() return true end }
        local handlers = g.input.PinHandlers
        handlers.press(pin); handlers.click(pin)
        handlers.press(pin); handlers.doubleclick(pin); handlers.click(pin)
        assert(g.ctx.data.panelMode == "edit" and g.ctx.data.selectedId == g.pin)
        assert(f.M.GetLocation(g.pin).revision == 1)
        handlers.press(pin); handlers.click(pin)
        assert(g.ctx.data.panelMode == "read")
    end)
    Check("changed deletion consequences require refreshed confirmation", function(f)
        local plan = assert(f.M.PlanDeletion(f.map, false))
        assert(f.M.CreateLocation(f.map, 0.1, 0.2, {}, nil, "Added while dialog was open"))
        local before = #f.writes
        local ok, reason = f.M.DeleteLocation(f.map, plan)
        assert(not ok and reason == "changed" and #f.writes == before)
        local fresh = assert(f.M.PlanDeletion(f.map, false))
        assert(fresh.descendants == 1 and f.M.DeleteLocation(f.map, fresh))
    end)
    Check("domain outcomes distinguish acceptance from persistence", function(f)
        f.mode = "pending"
        local commands = f.env.OverlandMapCommands
        local result = commands.UpdateLocation(f.map, { name = "Submitted" })
        assert(result.outcome == "accepted" and result.receipt.status == "pending")
        assert(commands.Settlement(result).pending == 1)
        assert(commands.UpdateLocation(f.map, { name = "Busy" }).outcome == "busy")
        f.writes[#f.writes].callbacks.failure("Failed")
        assert(result.outcome == "accepted" and commands.Settlement(result).failed == 1)
    end)
    Check("host resizing cancels previews without flushing editor drafts", function(f)
        local session = f.env.OverlandMapSession
        local flushed, cancelled, scope = 0, 0, {}
        local release = session.Register { scope = scope, valid = function() return true end,
            flush = function() flushed = flushed + 1 end, gesture = function() cancelled = cancelled + 1 end }
        session.Transition("resize", scope)
        assert(flushed == 0 and cancelled == 1)
        session.Transition("navigation", scope)
        assert(flushed == 1 and cancelled == 2)
        release(); session.Transition("navigation", scope)
        assert(flushed == 1 and cancelled == 2)
    end)
    Check("withdrawing invalid input preserves other pending fields", function(f)
        local editor = f.env.OverlandMapEditors.Create("location", function() end)
        editor.Stage(f.map, "name", "Unsent name")
        editor.Stage(f.map, "description", "Kept description")
        editor.Withdraw(f.map, "name")
        editor.Destroy(); f.Advance(2)
        assert(f.M.GetLocation(f.map).name ~= "Unsent name")
        assert(f.M.Details(f.map).description == "Kept description")
    end)
    Check("Undo cannot restore Director notes after permission loss", function(f)
        local ok, _, entry = f.M.SaveDirectorNote(f.map, "Secret")
        assert(ok and f.M.CanRevert(entry))
        f.env.dmhub.isDM = false
        assert(not f.M.CanRevert(entry))
    end)
    Check("failed immutable batch retries before newer coalescible edits", function(f)
        local sent, fail = {}, true
        local queue = f.env.OverlandMapSaveQueue.Create {
            canEdit = function() return true end, busy = function() return false end,
            coalesce = function(first, later) return later end,
            send = function(_, batch, callbacks)
                sent[#sent + 1] = batch.changes.text
                local receipt = { status = fail and "failed" or "confirmed" }
                if fail then callbacks.failure(receipt) else callbacks.success(receipt) end
                return { outcome = "accepted", receipt = receipt, undoSteps = {} }
            end,
        }
        queue.Commit("row", { text = "First" }); f.Advance(0)
        queue.Commit("row", { text = "Second" })
        fail = false; queue.Retry("row"); f.Advance(0)
        assert(#sent == 3 and sent[1] == "First" and sent[2] == "First" and sent[3] == "Second")
    end)
    Check("first view in a changed game captures the new generation", function(f)
        local lifetime = f.env.OverlandMapLifetime
        local old = lifetime.Owner("old"):Guard()
        f.env.dmhub.gameid = "just-entered-game"
        local current = lifetime.Owner("new"):Guard()
        assert(not old() and current())
        lifetime.Schedule(0, function() assert(current()) end)
        f.Advance(0)
    end)
    Check("deletion reports every pending and refused row without unsafe Undo", function(f)
        assert(f.M.CreateLocation(f.map, 0.2, 0.3, {}, nil, "Child"))
        local label = f.Create("Inside")
        local upload = f.env.dmhub.SetAndUploadTableItem
        f.env.dmhub.SetAndUploadTableItem = function(name, row, callbacks)
            if name == f.C.labelTableName and row.id == label then return nil end
            return upload(name, row, callbacks)
        end
        f.mode = "pending"
        local start = #f.writes
        local result = f.env.OverlandMapCommands.DeleteLocation(f.map, f.M.PlanDeletion(f.map, false))
        local counts = f.env.OverlandMapCommands.Settlement(result)
        assert(result.outcome == "accepted" and counts.pending == 2 and counts.failed == 1)
        f.U.Push(result.undo, "toast.deleted", { name = "Fixture" })
        assert(f.U.Current().text == f.env.OverlandMapCopy.T("toast.saving"))
        for i = start + 1, #f.writes do f.writes[i].callbacks.success() end
        f.Advance(f.C.undoTick)
        counts = f.env.OverlandMapCommands.Settlement(result)
        assert(counts.confirmed == 2 and counts.failed == 1 and counts.pending == 0)
        assert(not f.M.CanRevert(result.undo))
        assert(f.U.Current().text == f.env.OverlandMapCopy.T("toast.partiallySaved"))
    end)
    Check("an uncertain receipt never becomes successful after the Undo timeout", function(f)
        f.mode = "pending"
        local result = f.env.OverlandMapCommands.UpdateLocation(f.map, { name = "Uncertain" })
        f.U.Push(result.undo, "toast.moved", { name = "Fixture" })
        f.Advance(f.C.undoSettleSeconds + 1)
        assert(result.receipt.status == "pending" and not f.U.ToastCanUndo())
        assert(f.U.Current().text == f.env.OverlandMapCopy.T("toast.saving"))
        f.writes[#f.writes].callbacks.failure("Disconnected")
        f.Advance(f.C.undoTick)
        assert(f.U.Current().text == f.env.OverlandMapCopy.T("toast.saveFailed"))
    end)
    Check("local row notifications reach independent observers and stop on detach", function(f)
        local seen, other = {}, 0
        local detach = f.R.Observe(function(name, id) seen[#seen + 1] = { name, id } end)
        local release = f.R.Observe(function() other = other + 1 end)
        f.mode = "pending"
        assert(f.M.UpdateLocation(f.map, { name = "Local change" }))
        assert(#seen == 1 and seen[1][1] == f.C.locationTableName and seen[1][2] == f.map)
        detach()
        f.writes[#f.writes].callbacks.success()
        f.writes[#f.writes].callbacks.success()
        assert(#seen == 1 and other == 2)
        release()
    end)
    Check("Party submission and refused log upload remain separate outcomes", function(f)
        assert(loadfile("Overland Map/OverlandMapLog.lua", "t", f.env))()
        f.mode = "refuse"
        local result = f.env.OverlandMapCommands.WriteParty { mapId = f.map, u = 0.2, v = 0.3, placed = true }
        local counts = f.env.OverlandMapCommands.Settlement(result)
        assert(result.outcome == "accepted" and counts.submitted == 1 and counts.failed == 1)
        assert(not f.M.CanRevert(result.undo))
        assert(f.M.Party().u == 0.2)
    end)
    Check("empty operations report unchanged", function(f)
        local result = f.env.OverlandMapCommands.Result(true, nil, { description = "No change", steps = {} })
        assert(result.outcome == "unchanged" and #result.operations == 0)
    end)
    local function MoveFixture(f)
        f.R.LocationsTable()[f.map].mode = "pointcrawl"
        f.M.InvalidateIndex()
        local _, _, _, target = f.M.CreateMap("Destination", "image")
        local _, _, _, a = f.M.CreateLocation(f.map, 0.2, 0.2, {}, nil, "A")
        local _, _, _, b = f.M.CreateLocation(f.map, 0.6, 0.2, {}, nil, "B")
        local ok, _, _, path = f.env.OverlandMapPaths.CreatePath(f.map, a, b, {})
        assert(ok)
        return target, a, b, path
    end
    for _, refused in ipairs({ "location", "path", "party" }) do
        Check("map move retains a refused " .. refused .. " result and blocks dependent Undo", function(f)
            local target, a, b, path = MoveFixture(f)
            local upload = f.env.dmhub.SetAndUploadTableItem
            f.env.dmhub.SetAndUploadTableItem = function(name, row, callbacks)
                if (refused == "location" and row.id == a) or (refused == "path" and row.id == path) then return nil end
                return upload(name, row, callbacks)
            end
            if refused == "party" then
                f.M.PartyOffPaths = function() return { mapId = f.map, locationId = b, u = 0.6, v = 0.2 } end
                local data = f.mod:GetDocumentSnapshot().data
                data.schemaVersion, data.partyRevision = f.C.schemaVersion, f.C.maxRevision
            end
            f.mode = "pending"
            local start = #f.writes
            local commands = f.env.OverlandMapCommands
            local result = commands.MoveToMap(a, target)
            local counts = commands.Settlement(result)
            local accepted = refused == "party" and 2 or 1
            assert(result.outcome == "accepted" and counts.failed == 1 and counts.pending == accepted)
            for i = start + 1, #f.writes do f.writes[i].callbacks.success() end
            assert(commands.Settlement(result).confirmed == accepted and not f.M.CanRevert(result.undo))
        end)
    end
    Check("successful map move waits for every row and restores its paths", function(f)
        local target, a, _, path = MoveFixture(f)
        f.mode = "pending"
        local start = #f.writes
        local result = f.env.OverlandMapCommands.MoveToMap(a, target)
        assert(result.outcome == "accepted" and not f.M.CanRevert(result.undo))
        f.writes[start + 1].callbacks.success()
        assert(not f.M.CanRevert(result.undo))
        f.writes[start + 2].callbacks.success()
        assert(f.M.CanRevert(result.undo))
        f.mode = nil
        assert(f.M.Revert(result.undo))
        assert(f.M.GetLocation(a).parentId == f.map and f.env.OverlandMapPaths.Get(path) ~= nil)
    end)
    Check("path deletion records a refused Party submission", function(f)
        local _, _, b, path = MoveFixture(f)
        f.M.PartyOffPaths = function() return { mapId = f.map, locationId = b, u = 0.6, v = 0.2 } end
        local data = f.mod:GetDocumentSnapshot().data
        data.schemaVersion, data.partyRevision = f.C.schemaVersion, f.C.maxRevision
        local commands = f.env.OverlandMapCommands
        local result = commands.DeletePath(path)
        local counts = commands.Settlement(result)
        assert(result.outcome == "accepted" and counts.failed == 1 and counts.confirmed == 1)
        assert(not f.M.CanRevert(result.undo))
    end)
    Check("UI continuations survive resize but expire on every identity transition", function(f)
        local session = f.env.OverlandMapSession
        local alive = true
        local scope = { IsAlive = function() return alive end }
        local valid = session.Guard(scope)
        session.Transition("resize", scope); session.Transition("flush", scope)
        assert(valid())
        for _, reason in ipairs({ "navigation", "selection", "tool", "editor", "viewAsPlayer", "permission", "undo", "close", "transfer", "game" }) do
            valid = session.Guard(scope)
            session.Transition(reason, scope)
            assert(not valid(), reason)
        end
        valid = session.Guard(scope)
        session.Transition("viewAsPlayer")
        assert(not valid())
        valid = session.Guard(scope)
        alive = false
        assert(not valid())
    end)
    Check("creation commands retain identities and individual batch receipts", function(f)
        local commands = f.env.OverlandMapCommands
        f.mode = "pending"
        local single = commands.CreateMap("New map", "image")
        assert(single.outcome == "accepted" and single.id == single.receipt.record.id)
        local result = commands.CreateLocations(f.map, {
            { name = "Accepted", u = 0.1, v = 0.2 }, { name = "Invalid", u = 0/0, v = 0.2 },
        })
        assert(result.outcome == "accepted" and #result.rows == 2)
        assert(result.rows[1].outcome == "accepted" and result.rows[1].receipt.status == "pending")
        assert(result.rows[2].outcome == "failed")
        local counts = commands.Settlement(result)
        assert(counts.pending == 1 and counts.failed == 1)
        f.writes[#f.writes].callbacks.success()
        assert(f.M.CanRevert(result.undo))
    end)
    Check("document settings report submission without a server receipt", function(f)
        local commands = f.env.OverlandMapCommands
        local result = commands.SetPartyName("Travelers")
        assert(result.outcome == "accepted" and result.receipt == nil and commands.Settlement(result).submitted == 1)
        assert(commands.SetPartyName(string.rep("x", f.C.textLimit + 1)).outcome == "invalid")
        f.env.dmhub.isDM = false
        assert(commands.SetPlayersCanAddLocations(false).outcome == "denied")
    end)
    Check("record reconciliation preserves allowed continuations and permanently revokes forbidden ones", function(f)
        local session, allowed = f.env.OverlandMapSession, true
        local scope = { IsAlive = function() return true end }
        local valid = session.Guard(scope, function() return allowed end)
        session.Transition("reconcile", scope)
        assert(valid())
        allowed = false
        session.Transition("reconcile", scope)
        allowed = true
        assert(not valid())
    end)
    Check("unrelated records preserve text while permission loss cancels unsent lanes", function(f)
        local session = f.env.OverlandMapSession
        local editor = f.env.OverlandMapEditors.Create("location", function() end)
        editor.Stage(f.map, "name", "Kept")
        session.Transition("reconcile")
        assert(editor.Pending(f.map).name == "Kept")
        f.env.dmhub.isDM, f.env.dmhub.loginUserid = false, "other-player"
        session.Transition("reconcile")
        f.env.dmhub.isDM = true
        editor.Destroy(); f.Advance(2)
        assert(f.M.GetLocation(f.map).name ~= "Kept")
    end)
    Check("field confirmation does not repeat an unchanged Location or path write", function(f)
        local _, _, _, path = MoveFixture(f)
        local commands = f.env.OverlandMapCommands
        local row = f.M.GetLocation(f.map)
        local before = #f.writes
        assert(commands.UpdateLocation(f.map, { name = row.name, scale = false }).outcome == "unchanged")
        assert(commands.UpdatePath(path, { name = "", bends = {} }).outcome == "unchanged")
        assert(#f.writes == before)
        f.mode = "fail"
        local failed = commands.UpdateLocation(f.map, { name = "Retry unchanged optimistic value" })
        f.mode = nil
        local retried = commands.UpdateLocation(f.map, { name = "Retry unchanged optimistic value" }, nil,
            { operation = failed.receipt, before = failed.undoSteps[1].before })
        assert(retried.outcome == "accepted" and retried.receipt.status == "confirmed")
        assert(f.M.Revert(retried.undo) and f.M.GetLocation(f.map).name == row.name)
    end)
    print("LIFETIME CHECKS: " .. passed .. " passed")
    return passed
end

return checks
