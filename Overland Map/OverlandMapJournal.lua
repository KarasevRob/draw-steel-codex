local mod = dmhub.GetModLoading()

--- Journal access for Overland Map locations. The journal's own browsing policy
--- is checked here, because CustomDocument:ShowDocument does not check it.
--- @class OverlandMapJournal: GameType
--- @field new fun(o?: table): OverlandMapJournal
OverlandMapJournal = RegisterGameType("OverlandMapJournal")
local Journal = OverlandMapJournal
local C = OverlandMapConstants

--- A journal link as one viewer may see it.
--- @class OverlandMapJournalView
--- @field status "none"|"unsupported"|"missing"|"hidden"|"inaccessible"|"available"
--- @field id nil|string
--- @field title nil|string

-- Journal rows are game types; reading a field they do not declare raises.
local function Field(object, key, default)
    local ok, value = pcall(function() return object[key] end)
    if ok and value ~= nil then return value end
    return default
end

--- @return table<string, CustomDocument>
local function DocumentsTable()
    return (dmhub.GetTable(CustomDocument.tableName) or {}) --[[@as table<string, CustomDocument>]]
end

--- True when the host has the journal APIs this file needs.
--- @return boolean
function OverlandMapJournal.Available()
    local document = rawget(_G, "CustomDocument")
    return not mod.unloaded and document ~= nil
        and type(document.GetAccessibleRoots) == "function"
        and type(document.IsDocInAccessibleRoot) == "function"
        and type(document.tableName) == "string"
end

--- Resolve a stored journal document id for the local viewer.
--- @param id nil|string
--- @return OverlandMapJournalView
function OverlandMapJournal.ResolveForViewer(id)
    if id == nil or id == "" then return { status = "none" } end
    if not Journal.Available() then return { status = "unsupported" } end
    if type(id) ~= "string" or #id > C.journalIdLimit then return { status = "missing" } end
    local doc = DocumentsTable()[id]
    if doc == nil then return { status = "missing" } end
    if Field(doc, "hidden", false) then return { status = "hidden" } end
    if Field(doc, "nodeType", "") ~= "custom" or type(Field(doc, "ShowDocument")) ~= "function" then
        return { status = "unsupported" }
    end
    local ok, accessible = pcall(function()
        return CustomDocument.IsDocInAccessibleRoot(doc, CustomDocument.GetAccessibleRoots())
    end)
    if not ok or not accessible or (not dmhub.isDM and Field(doc, "hiddenFromPlayers", false)) then
        return { status = "inaccessible" }
    end
    local title = Field(doc, "description", "")
    if type(title) ~= "string" or title:match("^%s*$") then title = "Untitled" end
    return { status = "available", id = id, title = title }
end

--- Journal entries a Director may link, sorted by title.
--- @param query nil|string case-insensitive title filter
--- @return OverlandMapJournalView[]
function OverlandMapJournal.ListLinkTargets(query)
    local result = {} --- @type OverlandMapJournalView[]
    if not dmhub.isDM or not Journal.Available() then return result end
    query = string.lower(query or "")
    for id in pairs(DocumentsTable()) do
        local view = Journal.ResolveForViewer(id)
        if view.status == "available" and (query == "" or string.find(string.lower(view.title), query, 1, true)) then
            result[#result + 1] = view
        end
    end
    table.sort(result, function(a, b)
        if a.title == b.title then return a.id < b.id end
        return a.title < b.title
    end)
    return result
end

--- Open a linked journal entry when the viewer may read it.
--- @param id string
--- @return boolean opened
function OverlandMapJournal.Open(id)
    local view = Journal.ResolveForViewer(id)
    if view.status ~= "available" then return false end
    local doc = DocumentsTable()[id]
    if doc == nil then return false end
    doc:ShowDocument()
    return true
end
