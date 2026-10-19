local mod = dmhub.GetModLoading()

--- Journal access for Overland Map locations. A Location may link any journal entry:
--- a document, PDF, image or PDF bookmark. The journal's own browsing policy is checked
--- here, because opening an entry does not check it.
--- @class OverlandMapJournal: GameType
--- @field new fun(o?: table): OverlandMapJournal
OverlandMapJournal = RegisterGameType("OverlandMapJournal")
local Journal = OverlandMapJournal
local C = OverlandMapConstants

--- A journal link as one viewer may see it.
--- @class OverlandMapJournalView
--- @field status "none"|"unsupported"|"missing"|"inaccessible"|"available"
--- @field id nil|string
--- @field title nil|string
--- @field kind nil|string the entry's nodeType: "custom", "negotiation", "pdf", "image" or "pdffragment"
--- @field icon nil|string

-- The journal glyph for each kind of entry; documents use the generic page.
local KIND_ICONS = {
    custom = "phosphor/file-text.png",
    negotiation = "phosphor/file-text.png",
    pdf = "phosphor/file-pdf.png",
    image = "phosphor/image.png",
    pdffragment = "phosphor/bookmark-simple.png",
}

-- Journal rows are game types or engine assets; reading a field they do not declare raises.
local function Field(object, key, default)
    local ok, value = pcall(function() return object[key] end)
    if ok and value ~= nil then return value end
    return default
end

--- A CustomDocument helper, or nil on builds that predate it.
--- @param name string
--- @return nil|function
local function Helper(name)
    local document = rawget(_G, "CustomDocument")
    if document == nil then return nil end
    local value = Field(document, name)
    return type(value) == "function" and value or nil
end

--- The four tables journal entries live in. Their ids are guids, so one id names one entry.
--- @return table[]
local function EntryTables()
    local tables = {} --- @type table[]
    tables[1] = dmhub.GetTable(CustomDocument.tableName) or {}
    local pdfs, images = Field(assets, "pdfDocumentsTable"), Field(assets, "imagesByTypeTable")
    tables[#tables + 1] = pdfs or {}
    tables[#tables + 1] = images ~= nil and Field(images, "Document") or {}
    local fragment = rawget(_G, "PDFFragment")
    tables[#tables + 1] = fragment ~= nil and dmhub.GetTable(fragment.tableName) or {}
    return tables
end

--- The entry with this id, or nil when it is missing or deleted. Uses the journal's own
--- lookup when this build has it.
--- @param id string
--- @return any
local function FindEntry(id)
    local find = Helper("FindJournalEntry")
    if find ~= nil then return find(id) end
    for _, entries in ipairs(EntryTables()) do
        local entry = entries[id]
        if entry ~= nil then
            if Field(entry, "hidden", false) then return nil end
            return entry
        end
    end
    return nil
end

--- True when the host has the journal APIs this file needs.
--- @return boolean
function OverlandMapJournal.Available()
    return not mod.unloaded and Helper("GetAccessibleRoots") ~= nil and Helper("IsDocInAccessibleRoot") ~= nil
        and Helper("OpenContent") ~= nil and type(Field(CustomDocument, "tableName")) == "string"
end

--- Resolve a stored journal entry id for the local viewer.
--- @param id nil|string
--- @return OverlandMapJournalView
function OverlandMapJournal.ResolveForViewer(id)
    if id == nil or id == "" then return { status = "none" } end
    if not Journal.Available() then return { status = "unsupported" } end
    if type(id) ~= "string" or #id > C.journalIdLimit then return { status = "missing" } end
    local entry = FindEntry(id)
    if entry == nil then return { status = "missing" } end
    local kind = Field(entry, "nodeType", "")
    if KIND_ICONS[kind] == nil then return { status = "unsupported" } end
    -- Every kind sits in the same folder tree, so one root check covers them all. A PDF
    -- the viewer has no right to read (canView) stays closed to them as well.
    local ok, accessible = pcall(function()
        return CustomDocument.IsDocInAccessibleRoot(entry, CustomDocument.GetAccessibleRoots())
    end)
    if not ok or not accessible or (not dmhub.isDM and Field(entry, "hiddenFromPlayers", false))
        or (kind == "pdf" and Field(entry, "canView", true) == false) then
        return { status = "inaccessible" }
    end
    local title = Field(entry, "description", "")
    if type(title) ~= "string" or title:match("^%s*$") then title = Field(entry, "name", "") end
    if type(title) ~= "string" or title:match("^%s*$") then title = "Untitled" end
    return { status = "available", id = id, title = title, kind = kind, icon = KIND_ICONS[kind] }
end

--- Journal entries a Director may link, sorted by title.
--- @param query nil|string case-insensitive title filter
--- @return OverlandMapJournalView[]
function OverlandMapJournal.ListLinkTargets(query)
    local result = {} --- @type OverlandMapJournalView[]
    if not dmhub.isDM or not Journal.Available() then return result end
    query = string.lower(query or "")
    local seen = {}
    for _, entries in ipairs(EntryTables()) do
        for id in pairs(entries) do
            if type(id) == "string" and not seen[id] then
                seen[id] = true
                local view = Journal.ResolveForViewer(id)
                if view.status == "available" and (query == "" or string.find(string.lower(view.title), query, 1, true)) then
                    result[#result + 1] = view
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.title == b.title then return a.id < b.id end
        return a.title < b.title
    end)
    return result
end

--- Open a linked journal entry the way the journal itself would, when the viewer may read it.
--- @param id string
--- @return boolean opened
function OverlandMapJournal.Open(id)
    local view = Journal.ResolveForViewer(id)
    if view.status ~= "available" then return false end
    local entry = FindEntry(id)
    if entry == nil then return false end
    CustomDocument.OpenContent(entry)
    return true
end
