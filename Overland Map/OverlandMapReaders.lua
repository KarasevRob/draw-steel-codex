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

--- Counts hidden content on this map only, using the same viewer-filtered lists as the canvas.
function OverlandMapReaders.HiddenCount(mapId)
    if not Model.IsDirector() or Model.GetLocation(mapId) == nil then return 0 end
    local count = 0
    for _, rows in ipairs({ Model.Children(mapId), OverlandMapLabels.ForMap(mapId), Paths.Paths(mapId) }) do
        for _, row in ipairs(rows) do
            if row.visibility == "hidden" then count = count + 1 end
        end
    end
    return count
end
