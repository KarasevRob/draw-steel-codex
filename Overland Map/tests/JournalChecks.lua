-- Offline journal-link checks: every journal entry kind, viewer access, and builds that
-- predate the journal's own lookup. Runs the production OverlandMapJournal in a stub env.
local checks = {}

-- Game types and engine assets raise on fields they do not declare; so do these stand-ins.
local function Strict(fields)
    return setmetatable(fields, { __index = function(_, key) error("unknown field " .. tostring(key)) end })
end

local function Fixture(options)
    options = options or {}
    local f = { opened = {}, isDM = options.isDM ~= false }
    local env = setmetatable({}, { __index = _G }) --[[@as table<string, any>]]
    env._G = env
    local mod = { unloaded = false }
    f.docs = {
        doc = { id = "doc", nodeType = "custom", description = "Ruins", parentFolder = "public" },
        secret = { id = "secret", nodeType = "custom", description = "Secret", parentFolder = "private" },
        veiled = { id = "veiled", nodeType = "custom", description = "Veiled", parentFolder = "public", hiddenFromPlayers = true },
        deleted = { id = "deleted", nodeType = "custom", description = "Gone", parentFolder = "public", hidden = true },
        odd = { id = "odd", nodeType = "unknownKind", description = "Odd", parentFolder = "public" },
    }
    f.pdfs = {
        pdf = Strict { id = "pdf", nodeType = "pdf", description = "Atlas PDF", parentFolder = "public", hidden = false, canView = true },
        locked = Strict { id = "locked", nodeType = "pdf", description = "Locked", parentFolder = "public", hidden = false, canView = false },
    }
    f.images = { image = Strict { id = "image", nodeType = "image", description = " ", name = "Sketch", parentFolder = "public", hidden = false } }
    f.fragments = { mark = { id = "mark", nodeType = "pdffragment", description = "Page 4", parentFolder = false } }
    env.RegisterGameType = function() return {} end
    env.print = function() end
    env.dmhub = {
        GetModLoading = function() return mod end,
        GetTable = function(name)
            if name == "documents" then return f.docs elseif name == "pdfReferences" then return f.fragments end
        end,
    }
    setmetatable(env.dmhub, { __index = function(_, key) if key == "isDM" then return f.isDM end end })
    env.assets = Strict { pdfDocumentsTable = f.pdfs, imagesByTypeTable = { Document = f.images } }
    env.PDFFragment = { tableName = "pdfReferences" }
    local document = {
        tableName = "documents",
        GetAccessibleRoots = function()
            return f.isDM and { public = true, private = true } or { public = true }
        end,
        IsDocInAccessibleRoot = function(entry, roots) return roots[entry.parentFolder or "private"] == true end,
        OpenContent = function(entry) f.opened[#f.opened + 1] = entry.id end,
    }
    if options.findEntry then
        document.FindJournalEntry = function(id) f.coreLookups = (f.coreLookups or 0) + 1; return f.docs[id] end
    end
    if options.noOpen then document.OpenContent = nil end
    env.CustomDocument = Strict(document)
    local directory = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/tests/[^/]+$") or "Overland Map"
    for _, name in ipairs({ "OverlandMapConstants", "OverlandMapJournal" }) do
        assert(loadfile(directory .. "/" .. name .. ".lua", "t", env))()
    end
    f.J, f.env = env.OverlandMapJournal, env
    return f
end

local cases = {
    { "every journal entry kind resolves with its own icon", function()
        local f = Fixture()
        local expected = { doc = "file-text", pdf = "file-pdf", image = "image", mark = "bookmark-simple" }
        for id, icon in pairs(expected) do
            local view = f.J.ResolveForViewer(id)
            assert(view.status == "available" and view.id == id and view.icon:find(icon, 1, true), id)
        end
        assert(f.J.ResolveForViewer("image").title == "Sketch")
        assert(f.J.ResolveForViewer("odd").status == "unsupported")
        assert(f.J.ResolveForViewer("deleted").status == "missing" and f.J.ResolveForViewer("nope").status == "missing")
        assert(f.J.ResolveForViewer("").status == "none" and f.J.ResolveForViewer(string.rep("x", 600)).status == "missing")
    end },
    { "players see only what the journal shows them", function()
        local f = Fixture { isDM = false }
        for _, id in ipairs({ "secret", "veiled", "locked", "mark" }) do
            assert(f.J.ResolveForViewer(id).status == "inaccessible", id)
        end
        assert(f.J.ResolveForViewer("pdf").status == "available" and f.J.ResolveForViewer("doc").status == "available")
        assert(not f.J.Open("secret") and #f.opened == 0)
        assert(#f.J.ListLinkTargets("") == 0)
    end },
    { "the Director's picker lists all kinds, sorted and filtered", function()
        local f = Fixture()
        local titles = {}
        for _, view in ipairs(f.J.ListLinkTargets("")) do titles[#titles + 1] = view.title end
        assert(table.concat(titles, ",") == "Atlas PDF,Page 4,Ruins,Secret,Sketch,Veiled", table.concat(titles, ","))
        local filtered = f.J.ListLinkTargets("PAGE")
        assert(#filtered == 1 and filtered[1].kind == "pdffragment")
    end },
    { "opening goes through the journal's own opener", function()
        local f = Fixture()
        assert(f.J.Open("pdf") and f.J.Open("mark") and f.J.Open("doc"))
        assert(table.concat(f.opened, ",") == "pdf,mark,doc")
        assert(not f.J.Open("locked"))
    end },
    { "the journal's own lookup wins when the build has it", function()
        local f = Fixture { findEntry = true }
        assert(f.J.ResolveForViewer("doc").status == "available" and f.coreLookups == 1)
    end },
    { "a build without the journal opener reports unsupported without raising", function()
        local f = Fixture { noOpen = true }
        assert(not f.J.Available() and f.J.ResolveForViewer("doc").status == "unsupported")
        assert(#f.J.ListLinkTargets("") == 0 and not f.J.Open("doc"))
    end },
}

function checks.Run()
    local failed = 0
    for _, case in ipairs(cases) do
        local ok, err = pcall(case[2])
        print((ok and "JOURNAL PASS: " or "JOURNAL FAIL: ") .. case[1] .. (ok and "" or ": " .. tostring(err)))
        if not ok then failed = failed + 1 end
    end
    print(string.format("JOURNAL CHECKS: %d/%d passed", #cases - failed, #cases))
    return failed == 0
end

return checks
