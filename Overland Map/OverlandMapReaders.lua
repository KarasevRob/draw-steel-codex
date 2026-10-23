local mod = dmhub.GetModLoading()

--- @class OverlandMapReaders: GameType
--- @field new fun(o?: table): OverlandMapReaders
OverlandMapReaders = RegisterGameType("OverlandMapReaders")
local Model, Paths = OverlandMapModel, OverlandMapPaths

--- Read models are rebuilt through viewer filters before any rendering signature is reused.
function OverlandMapReaders.Location(id)
    local row = Model.GetLocation(id)
    if row == nil then return nil end
    return { row = row, details = Model.Details(id),
        note = Model.IsDirector() and Model.DirectorNote(id) or nil }
end

function OverlandMapReaders.Path(id)
    local row = Paths.Get(id)
    if row == nil then return nil end
    local a, b = Paths.Ends(row)
    if a == nil or b == nil then return nil end
    local visible = DeepCopy(row)
    if not Model.IsDirector() then visible.note = "" end
    return { row = visible, a = a, b = b }
end

function OverlandMapReaders.Atlas()
    local cards, party = {}, Model.Party()
    for _, map in ipairs(Model.TopLevel()) do
        cards[#cards + 1] = { row = map, count = Model.VisibleDescendantCount(map.id),
            partyHere = party ~= nil and Model.IsInSubtree(map.id, party.mapId) }
    end
    return cards
end

function OverlandMapReaders.Breadcrumbs(id)
    local result = {}
    for _, row in ipairs(Model.Ancestors(id)) do
        if Model.CanOpenMap(row) then result[#result + 1] = row end
    end
    return result
end

function OverlandMapReaders.Search(query, limit)
    return OverlandMapLabels.Search(query, limit)
end

--- Resolve a Quick Add target only while it remains editable on the current map.
--- @param quick {kind: string, id: string}|nil
--- @param mapId string|nil
--- @return table|nil
function OverlandMapReaders.QuickAddItem(quick, mapId)
    if quick == nil or mapId == nil then return nil end
    if quick.kind == "label" then
        local row = OverlandMapLabels.Snapshot(quick.id)
        if row ~= nil and row.mapId == mapId and OverlandMapLabels.CanEdit(row) then return row end
    elseif quick.kind == "location" then
        local row = Model.GetLocation(quick.id)
        if row ~= nil and row.parentId == mapId and Model.CanEdit(row) then return row end
    end
    return nil
end

local hiddenCounts, hiddenRevision = {}, nil

--- Counts hidden content on this map only, using the same viewer-filtered lists as the canvas.
function OverlandMapReaders.HiddenCount(mapId)
    if not Model.IsDirector() or Model.GetLocation(mapId) == nil then return 0 end
    local revision = Model.Revision()
    if revision ~= hiddenRevision then hiddenCounts, hiddenRevision = {}, revision end
    if hiddenCounts[mapId] ~= nil then return hiddenCounts[mapId] end
    local count = 0
    for _, rows in ipairs({ Model.Children(mapId), OverlandMapLabels.ForMap(mapId), Paths.Paths(mapId) }) do
        for _, row in ipairs(rows) do
            if row.visibility == "hidden" then count = count + 1 end
        end
    end
    hiddenCounts[mapId] = count
    return count
end
