-- Exercise production persistence, permissions and preview text without live game writes.
local checks = {}
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = source:match("^(.*)/tests/[^/]+$") or "Region Map"
local Base = dofile(directory .. "/tests/LabelChecks.lua")
local function Fixture()
    local f = Base.Fixture()
    f.theme = { fontFace = "berling", color = "#ffffffff", bgcolor = "#111111ff" }
    f.env.ThemeEngine = {
        MergeTokens = function() return { f.env.DeepCopy(f.theme) } end,
        OnThemeChanged = function(_, callback) f.themeChanged = callback end,
    }
    f.env.RegionMapSession = Base.SessionStub(f.env, directory)
    f.env.RegionMapJournal.ResolveForViewer = function() return { status = "empty" } end
    for _, file in ipairs({ "RegionMapPinText", "RegionMapLabelLayer" }) do
        assert(loadfile(directory .. "/" .. file .. ".lua", "t", f.env))()
    end
    f.P = f.env.RegionMapPinText
    function f.Row(id) return f.M.GetLocation(id or f.map) end
    function f.Format(id) return f.P.Format(f.Row(id)) end
    function f.Pin(map, name, style)
        local ok, reason, _, id = f.M.CreateLocation(map or f.map, 0.4, 0.5, style, nil, name or "A place")
        assert(ok, tostring(reason)); return id
    end
    function f.Finish()
        f.writes[#f.writes].callbacks.success(); f.Advance(0)
    end
    return f
end

function checks.Run()
    local passed = 0
    local function Check(name, fn) fn(Fixture()); passed = passed + 1; print("PIN TEXT PASS: " .. name) end
    Check("sparse tier edits preserve all legacy defaults", function(f)
        local before = f.Format()
        assert(before.majorSize == 18 and before.normalSize == 15 and before.minorSize == 13)
        assert(before.bold and not before.italics and before.background == "default")
        assert(f.P.Commit(f.map, { normalSize = 23.4 })); f.Advance(0)
        local stored = f.Row().pinNameFormat
        assert(stored.normalSize == 23.4 and stored.majorSize == nil and stored.font == nil and stored.background == nil)
        local after = f.Format()
        assert(after.majorSize == 18 and after.minorSize == 13 and after.bold and after.color == before.color)
        local n = #f.writes
        assert(f.P.Commit(f.map, { normalSize = 23.4 })); f.Advance(0)
        assert(#f.writes == n)
    end)
    Check("strict new values and safe optional data", function(f)
        for _, patch in ipairs({ { majorSize = 0 }, { minorSize = 72.1 }, { normalSize = 12.34 }, { spacing = 1.01 },
            { font = "unavailable" }, { color = "red" }, { background = "default" }, { anchor = "top" },
            { bold = 1 }, { italics = "yes" }, { other = true }, { majorSize = 0 / 0 } }) do
            assert(not f.P.Commit(f.map, patch))
            assert(not f.M.SetPinNameFormat(f.map, patch, false))
        end
        local row = f.R.LocationsTable()[f.map]
        row.pinNameFormat = { normalSize = "bad", majorSize = 21, font = "missing", bold = "bad", color = "bad" }
        f.M.InvalidateIndex()
        local format = f.Format()
        assert(f.Row() ~= nil and format.normalSize == 15 and format.majorSize == 21 and format.bold and format.font == "berling")
        assert(row.pinNameFormat.font == "missing")
        row.pinNameFormat = 42; f.M.InvalidateIndex(); assert(f.Row() ~= nil and f.Format().normalSize == 15)
    end)
    Check("map ownership and no parent or child inheritance", function(f)
        local nested = f.Pin(); assert(f.M.AddMap(nested, "nested-image"))
        local child = f.Pin(nested)
        assert(f.P.Commit(f.map, { normalSize = 30 })); f.Advance(0)
        assert(f.Format(f.Row(nested).parentId).normalSize == 30)
        assert(f.Format(f.Row(child).parentId).normalSize == 15)
        assert(f.P.Commit(nested, { normalSize = 10 })); f.Advance(0)
        assert(f.Format().normalSize == 30 and f.Format(nested).normalSize == 10)
        local ok, _, _, other = f.M.CreateMap("Other", "other-image"); assert(ok)
        assert(f.M.MoveToMap(nested, other))
        assert(f.Format(f.Row(nested).parentId).normalSize == 15 and f.Format(nested).normalSize == 10)
    end)
    Check("Director-only format writes and Undo; player view read-only", function(f)
        assert(f.P.Commit(f.map, { bold = false })); f.Advance(0)
        f.env.dmhub.isDM = false
        assert(not f.P.Commit(f.map, { color = "#123456" }))
        assert(not f.M.SetPinNameFormat(f.map, { bold = true }, false))
        assert(not f.M.UpdateLocation(f.map, { pinNameFormat = { bold = true } }))
        assert(not f.U.UndoLast())
        f.env.dmhub.isDM = true; f.M.SetViewAsPlayer(true)
        assert(not f.P.Commit(f.map, {}, true))
        f.M.SetViewAsPlayer(false)
        local pin = f.Pin(); assert(not f.P.Commit(pin, { bold = false }))
    end)
    Check("one in-flight write coalesces latest leaves and preserves remote fields", function(f)
        f.mode = "pending"
        assert(f.P.Commit(f.map, { color = "#111111" }))
        local n = #f.writes
        f.P.Commit(f.map, { color = "#222222" }); f.P.Commit(f.map, { color = "#333333", bold = false })
        assert(#f.writes == n and f.Format().color == "#333333")
        local row = f.R.LocationsTable()[f.map]
        row.name, row.border = "Remote name", "fade"
        row.pinNameFormat.minorSize = 9
        row.revision, row.mutationId = row.revision + 1, "remote"
        f.M.InvalidateIndex(); f.Finish()
        assert(#f.writes == n + 1)
        assert(f.Row().name == "Remote name" and f.Row().border == "fade")
        assert(f.Row().pinNameFormat.minorSize == 9 and f.Row().pinNameFormat.color == "#333333")
        f.Finish(); assert(f.P.Status(f.map) == "saved")
        f.mode = nil; assert(f.U.UndoLast()); f.Advance(0)
        assert(f.Row().name == "Remote name" and f.Row().pinNameFormat.minorSize == 9)
    end)
    Check("busy unrelated map write retains rapid edits", function(f)
        f.mode = "pending"; assert(f.M.UpdateLocation(f.map, { name = "Renamed" }))
        local n = #f.writes
        f.P.Commit(f.map, { majorSize = 31 }); f.P.Commit(f.map, { minorSize = 8 })
        assert(#f.writes == n)
        f.writes[n].callbacks.success(); f.Advance(f.C.busyRetryDelay)
        assert(#f.writes == n + 1 and f.Row().name == "Renamed")
        assert(f.Row().pinNameFormat.majorSize == 31 and f.Row().pinNameFormat.minorSize == 8)
        f.Finish()
    end)
    Check("failed write Retry preserves original Undo and newest pending color", function(f)
        f.mode = "fail"; f.P.Commit(f.map, { color = "#111111" }); f.Advance(0)
        assert(f.P.Status(f.map) == "failed" and not f.U.UndoLast())
        local n = #f.writes
        f.P.Commit(f.map, { color = "#333333", minorSize = 7 }); assert(#f.writes == n)
        f.mode = nil; f.P.Retry(f.map); f.Advance(0)
        assert(f.P.Status(f.map) == "saved" and f.Row().pinNameFormat.color == "#333333")
        assert(f.U.UndoLast()); f.Advance(0); assert(f.Row().pinNameFormat == nil)
    end)
    Check("reset supersedes pending edits and remains undoable", function(f)
        f.mode = "pending"; f.P.Commit(f.map, { color = "#111111" })
        f.P.Commit(f.map, { color = "#222222", font = "courier" })
        f.P.Commit(f.map, {}, true); f.P.Commit(f.map, { bold = false })
        assert(f.Format().color == "#ffffffff" and not f.Format().bold)
        f.Finish(); f.Finish(); assert(f.Row().pinNameFormat.color == nil and not f.Row().pinNameFormat.bold)
        f.mode = nil; assert(f.U.UndoLast()); f.Advance(0)
        assert(f.Row().pinNameFormat.color == "#111111")
    end)
    Check("permission loss and unload discard unsent changes", function(f)
        f.mode = "pending"; f.P.Commit(f.map, { color = "#111111" }); f.P.Commit(f.map, { color = "#222222" })
        local n = #f.writes
        f.M.SetViewAsPlayer(true); f.Finish(); f.Advance(2)
        assert(#f.writes == n and f.Row().pinNameFormat.color == "#111111")
        f.M.SetViewAsPlayer(false)
        f.P.Commit(f.map, { color = "#333333" }); f.P.Commit(f.map, { color = "#444444" })
        n = #f.writes; f.mod.unloaded = true; f.Finish(); f.Advance(2)
        assert(#f.writes == n)
    end)
    Check("replace preserves, remove clears, Delete Undo restores", function(f)
        local nested = f.Pin(); assert(f.M.AddMap(nested, "nested-image"))
        f.P.Commit(nested, { font = "courier", normalSize = 25 }); f.Advance(0)
        assert(f.M.ReplaceImage(nested, "new-image") and f.Format(nested).normalSize == 25)
        local ok, _, entry = f.M.DeleteLocation(nested); assert(ok)
        assert(f.M.Revert(entry) and f.Format(nested).normalSize == 25)
        assert(f.M.RemoveMap(nested)); assert(f.Row(nested).pinNameFormat == nil)
        assert(f.M.AddMap(nested, "again") and f.Format(nested).normalSize == 15)
    end)
    Check("stale Undo never overwrites a newer map update", function(f)
        f.P.Commit(f.map, { minorSize = 22 }); f.Advance(0)
        assert(f.M.UpdateLocation(f.map, { name = "Newer" }))
        assert(not f.U.UndoLast() and f.Row().name == "Newer")
    end)
    Check("all name forms restore effective defaults and follow theme", function(f)
        local label = { selfStyle = {}, classes = {} }
        f.P.Commit(f.map, { font = "courier", bold = false, italics = true, spacing = 0.2, background = "plate", color = "#000000ff" })
        f.Advance(0)
        for _, plate in ipairs({ false, true }) do
            f.P.Apply(label, "<Town>", f.Format(), "normal", plate, 1.4)
            assert(label.selfStyle.fontFace == "courier" and label.selfStyle.fontSize == 21 and label.selfStyle.italics)
            assert(label.classes.customPinBackground and label.selfStyle.textOutlineWidth == 0)
        end
        f.P.Commit(f.map, {}, true); f.Advance(0)
        f.P.Apply(label, "Town", f.Format(), "normal", false, 1)
        assert(label.selfStyle.bold and not label.selfStyle.italics and label.selfStyle.fontFace == "berling")
        assert(label.selfStyle.bgcolor == "clear" and label.selfStyle.hpad == 0 and label.selfStyle.textOutlineWidth == 0.3)
        f.P.Apply(label, "Town", f.Format(), "normal", true, 1)
        assert(label.selfStyle.bgcolor == "#111111ff" and label.selfStyle.hpad == 7 and not label.classes.customPinBackground)
        local _, before = f.Format()
        f.theme.fontFace, f.theme.color = "courier", "#eeeeeeff"; f.themeChanged()
        local format, after = f.Format()
        assert(before ~= after and format.font == "courier" and format.color == "#eeeeeeff")
    end)
    Check("two sentences, paragraphs, abbreviations and decimal numbers", function(f)
        local p = f.P.DescriptionPreview
        assert(p(nil) == "" and p("  \n\t ") == "")
        assert(p("One.\n\nTwo! Three?") == "One. Two!...")
        assert(p("Dr. Moss lives 1.5 miles away.\nVisit Mt. Oak. Then return.") == "Dr. Moss lives 1.5 miles away. Visit Mt. Oak...")
        assert(p('A "town." Next! Still more.') == 'A "town." Next!...')
        assert(p("One short sentence") == "One short sentence")
    end)
    Check("Unicode cap includes ellipsis and never splits a character", function(f)
        local p = f.P.DescriptionPreview
        local char = utf8.char(0x1F332)
        local text = p(string.rep(char, 301))
        assert(utf8.len(text) == 300 and text:sub(-3) == "...")
        assert(p(string.rep(char, 300)) == string.rep(char, 300))
        local words = p(string.rep("somewhere ", 90))
        assert(utf8.len(words) <= 300 and words:sub(-13) == " somewhere...")
        assert(p("bad" .. string.char(255)) == "")
    end)
    Check("hover exposes only accessible description, never Director notes", function(f)
        local pin = f.Pin(nil, "Visible name", { visibility = "revealed" })
        assert(f.M.SaveDetails(pin, { description = "First. Second. Third." }))
        assert(f.M.SaveDirectorNote(pin, "SECRET"))
        f.env.dmhub.isDM = false
        local hover = f.P.HoverText(pin)
        assert(hover:find("Visible name", 1, true) and hover:find("First. Second...", 1, true) and not hover:find("SECRET", 1, true))
        f.env.dmhub.isDM = true; assert(f.M.SetVisibility(pin, "hidden")); f.env.dmhub.isDM = false
        assert(f.P.HoverText(pin) == nil)
    end)
    print("PIN TEXT CHECKS: " .. passed .. " passed")
    return passed
end
if ... == "run" then checks.Run() end
return checks
