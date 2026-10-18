-- Production import UI/model with an in-memory transport and deterministic coroutine clock.
local checks = {}
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = source:match("^(.*)/tests/[^/]+$") or "Overland Map"
local Base = dofile(directory .. "/tests/LabelChecks.lua")

local function Fixture()
    local f = Base.Fixture()
    local env = f.env
    f.panels, f.pushes, f.reads, f.parses = {}, {}, 0, 0
    local methods = {}
    function methods:SetClass(name, value) self.classSet[name] = value end
    function methods:HasClass(name) return self.classSet[name] == true end
    function methods:AddChild(child) self.children[#self.children + 1] = child end
    function methods:SetAsFirstSibling() end
    function methods:ScheduleEvent() end
    function methods:FireEvent(name, ...) if self[name] then return self[name](self, ...) end end
    local function Panel(args)
        local p = setmetatable({ valid = true, children = {}, data = {}, classSet = {}, selfStyle = {} }, { __index = methods })
        for k, v in pairs(args) do
            if type(k) == "number" then p.children[#p.children + 1] = v
            elseif k == "classes" then for _, c in ipairs(v) do p.classSet[c] = true end
            else p[k] = v end
        end
        f.panels[#f.panels + 1] = p
        return p
    end
    env.gui.Panel, env.gui.Label, env.gui.Button, env.gui.Check = Panel, Panel, Panel, Panel
    env.OverlandMapControls = {
        SetText = function(p, text) p.text = text end,
        TextArea = function(_, args) return Panel(args) end,
        FocusSoon = function() end,
        UIScale = function() return 1 end,
        ShowRoute = function() return false end,
        IconButton = function(id, _, _, click) return Panel { id = id, click = click } end,
    }
    env.OverlandMapJournal.ResolveForViewer = function() return { status = "empty" } end
    env.gui.TryGetImageDimensions = function() return { width = 900, height = 600 } end
    env.dmhub.ReadTextFile = function() f.reads = f.reads + 1; return f.text or "fixture JSON" end
    env.dmhub.FromJson = function(text)
        f.parses = f.parses + 1; f.parsedText = text
        return { success = f.parseSuccess ~= false, result = f.input }
    end
    env.dmhub.Coroutine = function(fn)
        local thread = coroutine.create(fn)
        local function Resume()
            local ok, delay = coroutine.resume(thread)
            assert(ok, delay)
            if coroutine.status(thread) ~= "dead" then env.dmhub.Schedule(delay, Resume) end
        end
        Resume()
    end
    env.print = function() end
    env.OverlandMapUndo.Notify = function(id) f.notice = id end
    f.ctx = {
        data = { mapId = f.map }, root = { renderedWidth = 1000 },
        IsAlive = function() return not f.closed end,
        CurrentMap = function() return f.M.GetLocation(f.map) end,
        RefreshAll = function() f.refreshes = (f.refreshes or 0) + 1 end,
        Confirm = function(args) args.onConfirm() end,
        Report = function(_, reason) f.report = reason end,
        Push = function(entry, toast, args) f.pushes[#f.pushes + 1] = { entry = entry, toast = toast, args = args } end,
    }
    assert(loadfile(directory .. "/OverlandMapImport.lua", "t", env))()
    f.I = env.OverlandMapImport
    f.layer = f.I.Create(f.ctx)
    function f.Panel(id)
        for _, p in ipairs(f.panels) do if p.id == id then return p end end
        error("missing panel " .. id)
    end
    function f.Start(input)
        f.input = input
        f.layer.data.openFile("fixture.json", f.map)
        f.Panel("overland-map-import-ok"):FireEvent("click")
    end
    function f.Entry(n)
        return { name = "Imported " .. n, description = "Description " .. n, note = "Note " .. n }
    end
    return f
end

function checks.Run()
    local passed, failed = 0, 0
    local function Check(name, fn)
        local ok, err = pcall(fn, Fixture())
        if ok then passed = passed + 1 else failed = failed + 1 end
        print((ok and "IMPORT PASS: " or "IMPORT FAIL: ") .. name .. (ok and "" or ": " .. tostring(err)))
    end
    Check("50,000 invalid entries keep exact totals and bounded preview panels", function(f)
        local input = {}; for i = 1, 50000 do input[i] = {} end
        f.input = input
        f.layer.data.openFile("fixture.json", f.map)
        local plan = f.I.Check(input, f.map)
        assert(plan.skippedCount == 50000 and #plan.skipped <= 100)
        assert(#f.panels < 250, "preview constructed " .. #f.panels .. " panels")
    end)
    Check("file is read once and parsed from exactly that text", function(f)
        f.input, f.text = { f.Entry(1) }, "\239\187\191fixture JSON"
        local data, err = f.I.ReadFile("fixture.json")
        assert(data == f.input and err == nil and f.reads == 1 and f.parses == 1)
        assert(f.parsedText == "fixture JSON")
    end)
    Check("file input is uncapped while pasted input respects the constant", function(f)
        f.input, f.text = { f.Entry(1) }, string.rep("x", f.C.importTextLimit + 1)
        assert(f.I.ReadFile("fixture.json") == f.input)
        local _, err = f.I.ReadText(f.text); assert(err == "tooLong")
        f.text = " \n"; local _, empty = f.I.ReadFile("fixture.json"); assert(empty == "empty")
        f.text, f.parseSuccess = "broken", false
        local _, invalid = f.I.ReadFile("fixture.json"); assert(invalid == "json")
    end)
    Check("names reject controls and bidi overrides", function(f)
        for _, suffix in ipairs({ "\0", "\27", "\n", utf8.char(0x202e), utf8.char(0x2066) }) do
            assert(f.I.CheckEntry({ name = "Bad" .. suffix .. "name" }, 1) == nil)
        end
        assert(f.I.CheckEntry({ name = string.rep(utf8.char(0x416), f.C.textLimit) }, 1))
    end)
    Check("two batches include sidecars and partial Undo preserves an edited pin", function(f)
        local input = {}; for i = 1, 12 do input[i] = f.Entry(i) end
        f.Start(input); f.Advance(1)
        assert(not f.I.IsRunning() and #f.pushes == 1)
        local entry = f.pushes[1].entry
        assert(#entry.steps == 12 and entry.partial and #f.M.Children(f.map) == 12)
        for _, step in ipairs(entry.steps) do
            assert(f.M.Details(step.id).description:match("^Description "))
            assert(f.M.DirectorNote(step.id):match("^Note "))
        end
        assert(f.M.UpdateLocation(entry.steps[1].id, { name = "Edited" }))
        assert(f.M.Revert(entry) and #f.M.Children(f.map) == 1)
    end)
    Check("failed row stops subsequent batches but successful rows receive sidecars", function(f)
        local upload, calls = f.env.dmhub.SetAndUploadTableItem, 0
        f.env.dmhub.SetAndUploadTableItem = function(name, row, cb)
            if name == f.C.locationTableName then
                calls = calls + 1
                if calls == 2 then cb.failure(); return nil end
            end
            return upload(name, row, cb)
        end
        local input = {}; for i = 1, 12 do input[i] = f.Entry(i) end
        f.Start(input); f.Advance(1)
        assert(calls == 10 and #f.M.Children(f.map) == 9 and not f.I.IsRunning())
        assert(#f.pushes == 1 and #f.pushes[1].entry.steps == 9)
        assert(f.pushes[1].toast == "toast.importStopped")
        for _, row in ipairs(f.M.Children(f.map)) do assert(f.M.Details(row.id).description ~= "") end
    end)
    Check("editing an imported description protects that pin from import Undo", function(f)
        f.Start({ f.Entry(1), f.Entry(2) }); f.Advance(1)
        local entry = f.pushes[1].entry
        assert(f.M.SaveDetails(entry.steps[1].id, { description = "Edited afterwards" }))
        assert(f.M.Revert(entry))
        assert(f.M.GetLocation(entry.steps[1].id) ~= nil and #f.M.Children(f.map) == 1)
    end)
    Check("log rows have distinct menu IDs", function(f)
        local session = f.env.OverlandMapControls
        session.Label = function(classes, text) return f.env.gui.Label { classes = classes, text = text } end
        session.Button = function(text, click) return f.env.gui.Button { text = text, click = click } end
        f.env.dmhub.serverTimeMilliseconds = 1700000000000
        f.env.OverlandMapLog.Entries = function()
            return {
                { id = "first", kind = "placed", mapId = f.map, byDirector = true, note = "", mergedCount = 0 },
                { id = "second", kind = "placed", mapId = f.map, byDirector = true, note = "", mergedCount = 0 },
            }
        end
        f.env.OverlandMapLog.Time = function() return 1700000000000 end
        f.ctx.data.panelMode = "log"
        assert(loadfile(directory .. "/OverlandMapEditors.lua", "t", f.env))()
        assert(loadfile(directory .. "/OverlandMapLogPanel.lua", "t", f.env))()
        local panel = f.env.OverlandMapLogPanel.Create(f.ctx)
        panel:FireEvent("bind")
        assert(f.Panel("overland-map-log-more-first") ~= f.Panel("overland-map-log-more-second"))
    end)
    Check("a description edited between import batches keeps its pin", function(f)
        local edited
        f.ctx.RefreshAll = function()
            local rows = f.M.Children(f.map)
            if #rows == f.C.importBatch and edited == nil then
                edited = rows[1].id
                assert(f.M.SaveDetails(edited, { description = "Edited during import" }))
            end
        end
        local input = {}; for i = 1, 12 do input[i] = f.Entry(i) end
        f.Start(input); f.Advance(1)
        assert(edited and f.M.Revert(f.pushes[1].entry))
        assert(f.M.GetLocation(edited) and #f.M.Children(f.map) == 1)
    end)
    Check("pending uploads block a second import and time out without a permanent lock", function(f)
        f.mode = "pending"; f.Start({ f.Entry(1) })
        assert(f.I.IsRunning())
        local writes = #f.writes
        f.layer.data.start(); f.Panel("overland-map-import-ok"):FireEvent("click")
        assert(#f.writes == writes)
        f.Advance(f.C.importWait + 1)
        assert(not f.I.IsRunning())
    end)
    Check("an exception releases Import even when reporting also throws", function(f)
        f.M.CreateLocations = function() error("fixture failure") end
        f.ctx.Report = function() error("closed UI") end
        pcall(f.Start, { f.Entry(1) })
        assert(not f.I.IsRunning(), "Import stayed locked")
    end)
    Check("Travel uses case-insensitive destination order and stable ties", function(f)
        local names = { a = "alpha", b = "Zulu", c = "ALPHA" }
        f.M.Party = function() return { mapId = f.map, locationId = "origin" } end
        f.M.IsPointCrawl = function() return true end
        f.M.GetLocation = function(id) return { id = id } end
        f.M.NameOf = function(id) return names[id] or "" end
        f.env.OverlandMapPaths.PathsOf = function()
            return {
                { id = "3", aId = "origin", bId = "b", time = 1 },
                { id = "2", aId = "origin", bId = "a", time = 1 },
                { id = "1", aId = "origin", bId = "c", time = 1 },
            }
        end
        assert(loadfile(directory .. "/OverlandMapTravel.lua", "t", f.env))()
        local options = f.env.OverlandMapTravel.Options()
        assert(options[1].pathId == "1" and options[2].pathId == "2" and options[3].pathId == "3")
    end)
    print(string.format("IMPORT OFFLINE CHECKS: %d passed, %d failed", passed, failed))
    assert(failed == 0, "import regressions")
    return passed
end

checks.Fixture = Fixture
return checks
