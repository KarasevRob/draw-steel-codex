local mod = dmhub.GetModLoading()

--- Party travel on point crawl maps: which ways the Party can go
--- now (G1, G5, G6), travelling one path (a "leg", logged as one entry, I1),
--- and the Director's stop partway along a path (G3, Q13, Q14). The Party's
--- spot on a path is worked out from the time spent, never stored as a point.
--- @class RegionMapTravel: GameType
--- @field new fun(o?: table): RegionMapTravel
RegionMapTravel = RegisterGameType("RegionMapTravel")
local R = RegionMapRecords
local Model = RegionMapModel
local Paths = RegionMapPaths

--- One way the Party can travel now.
--- @class RegionMapTravelOption
--- @field pathId string
--- @field fromId string the end the leg sets out from; from partway, the end behind the Party
--- @field toId string the end it arrives at
--- @field time number watches the leg takes
--- @field rest ""|"on"|"back" "" for a whole path; "on" or "back" when leaving from partway (Q15)
--- @field hidden boolean the path is hidden from players (only the Director is offered these)

--- Why nothing is offered: no Party, not a point crawl map, the viewer may not
--- move it, or it is on no Location and no path (G6).
--- @alias RegionMapTravelBlock "none"|"free"|"noPermission"|"offPath"

-- The line ------------------------------------------------------------------------------------------

--- Watches from one end to the other, or nil when that way is not possible (W2).
--- @param path RegionMapPathRecord
--- @param fromId string
--- @return nil|number
function RegionMapTravel.Duration(path, fromId)
    if fromId == path.aId then return path.time end
    if fromId ~= path.bId or path.back == "none" then return nil end
    if path.back == "different" then return path.backTime end
    return path.time
end
local Duration = RegionMapTravel.Duration

-- The time a stopped Party is placed by. An edit that made its way impossible
-- falls back to the forward time, so the Party still has a spot.
local function PlacingTime(path, fromId)
    return Duration(path, fromId) or path.time
end

--- How far along the line from fromId the time spent takes the Party, 0..1.
--- @param path RegionMapPathRecord
--- @param fromId string
--- @param spent number
--- @return number
function RegionMapTravel.Fraction(path, fromId, spent)
    local total = PlacingTime(path, fromId)
    if not R.IsFinite(spent) or total <= 0 then return 0.5 end
    return R.Clamp(spent / total, 0, 1)
end
local Fraction = RegionMapTravel.Fraction

local function Reversed(points)
    local result = {} --- @type RegionMapRoutePoint[]
    for i = #points, 1, -1 do result[#result + 1] = points[i] end
    return result
end

--- The part of a path's line between two fractions of its length, measured
--- from fromId's end: Slice(path, a, 0, 1) is the whole line from a. Lengths
--- are in image units, so on a long, narrow image the split is approximate.
--- @param path RegionMapPathRecord
--- @param fromId string
--- @param f0 number
--- @param f1 number
--- @return RegionMapRoutePoint[]
function RegionMapTravel.Slice(path, fromId, f0, f1)
    local points = Paths.Points(path)
    if fromId == path.bId then points = Reversed(points) end
    if #points < 2 then return points end
    local lengths, total = {}, 0
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        lengths[i] = math.sqrt((b.u - a.u) ^ 2 + (b.v - a.v) ^ 2)
        total = total + lengths[i]
    end
    local result = {} --- @type RegionMapRoutePoint[]
    local function Add(a, b, t)
        result[#result + 1] = { u = R.Clamp(a.u + (b.u - a.u) * t, 0, 1), v = R.Clamp(a.v + (b.v - a.v) * t, 0, 1) }
    end
    if total <= 0 then return { points[1] } end
    local start, stop = R.Clamp(f0, 0, 1) * total, R.Clamp(f1, 0, 1) * total
    local walked = 0
    for i = 1, #points - 1 do
        local a, b, length = points[i], points[i + 1], lengths[i]
        local s, e = walked, walked + length
        if e >= start and s <= stop and length > 0 then
            if #result == 0 then Add(a, b, math.max(0, (start - s) / length)) end
            Add(a, b, math.min(1, (stop - s) / length))
        end
        walked = e
    end
    if #result == 0 then result[1] = points[#points] end
    return result
end
local Slice = RegionMapTravel.Slice

--- Where a Party stopped partway is drawn: spent along the line from fromId (Q13).
--- @param path RegionMapPathRecord
--- @param fromId string
--- @param spent number
--- @return number u
--- @return number v
function RegionMapTravel.PositionOn(path, fromId, spent)
    local fraction = Fraction(path, fromId, spent)
    local point = Slice(path, fromId, fraction, fraction)[1]
    if point == nil then return 0.5, 0.5 end
    return point.u, point.v
end

-- What travel offers --------------------------------------------------------------------------------

local OtherEnd = Paths.OtherEnd

local function DestName(option)
    return R.MapNameKey(Model.NameOf(option.toId))
end

--- The ways the viewer may move the Party now, sorted by destination. The
--- Director sees hidden paths too (marked); a player only the paths they see,
--- and only while "Players can move the Party" is on (G5).
--- @return RegionMapTravelOption[] options
--- @return nil|RegionMapTravelBlock block set when options is empty for a reason other than "no paths"
function RegionMapTravel.Options()
    local options = {} --- @type RegionMapTravelOption[]
    local party = Model.Party()
    if party == nil then return options, "none" end
    if not Model.IsPointCrawl(Model.GetLocation(party.mapId)) then return options, "free" end
    if not Model.IsDirector() and not Model.PlayersCanMoveParty() then return options, "noPermission" end
    if party.locationId ~= nil then
        for _, path in ipairs(Paths.PathsOf(party.locationId)) do
            local time = Duration(path, party.locationId)
            local toId = OtherEnd(path, party.locationId)
            if time ~= nil and Model.GetLocation(toId) ~= nil then
                options[#options + 1] = {
                    pathId = path.id, fromId = party.locationId, toId = toId, time = time, rest = "",
                    hidden = path.visibility == "hidden",
                }
            end
        end
    elseif party.pathId ~= nil and party.pathFrom ~= nil and party.spent ~= nil then
        local path = Paths.Get(party.pathId)
        if path == nil then return options, "offPath" end
        local from, spent = party.pathFrom --[[@as string]], party.spent --[[@as number]]
        local far = OtherEnd(path, from)
        local hidden = path.visibility == "hidden"
        -- Going on takes the rest of the time; turning back takes the time spent (G3).
        if Duration(path, from) ~= nil then
            options[#options + 1] = {
                pathId = path.id, fromId = from, toId = far, time = math.max(0, PlacingTime(path, from) - spent),
                rest = "on", hidden = hidden,
            }
        end
        if Duration(path, far) ~= nil then
            options[#options + 1] = { pathId = path.id, fromId = far, toId = from, time = spent, rest = "back", hidden = hidden }
        end
    else
        return options, "offPath"
    end
    table.sort(options, function(x, y)
        local nx, ny = DestName(x), DestName(y)
        if nx ~= ny then return nx < ny end
        return x.pathId < y.pathId
    end)
    return options, nil
end

-- Writes ------------------------------------------------------------------------------------------------

--- Travel one option: the Party goes to its destination and the leg is logged,
--- as one undo entry. A Director travelling a hidden path either reveals it in
--- the same entry or travels without revealing, and players then see the leg
--- with no path name and no line (W1).
--- @param option RegionMapTravelOption
--- @param reveal boolean
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapTravel.Travel(option, reveal)
    if mod.unloaded then return false, "permission", nil end
    -- Checked against the options now: another client may have moved the Party since the list was drawn.
    local current = nil --- @type nil|RegionMapTravelOption
    for _, item in ipairs((RegionMapTravel.Options())) do
        if item.pathId == option.pathId and item.toId == option.toId and item.rest == option.rest then current = item end
    end
    local path = current and Paths.Get(current.pathId)
    if current == nil or path == nil then return false, "invalid", nil end
    local party = Model.StoredParty()
    if party == nil then return false, "invalid", nil end
    -- The route follows the line in travel order (I1); from partway it starts at the Party.
    local route
    if current.rest == "" then
        route = Slice(path, current.fromId, 0, 1)
    else
        local from = party.pathFrom or current.fromId
        local fraction = Fraction(path, from, party.spent or 0)
        if current.rest == "on" then route = Slice(path, from, fraction, 1) else route = Reversed(Slice(path, from, 0, fraction)) end
    end
    local description = "Travel along region map path"
    local ok, reason, entry = Model.WriteParty {
        mapId = path.mapId, locationId = current.toId, description = description, travel = true, noLog = true,
    }
    if not ok or entry == nil then return false, reason, nil end
    local secret = false
    if path.visibility == "hidden" then
        local revealed = false
        if reveal then
            local revealOk, _, revealEntry = Paths.SetVisibility(path.id, "revealed")
            if revealOk and revealEntry ~= nil then
                for _, step in ipairs(revealEntry.steps) do entry.steps[#entry.steps + 1] = step end
                revealed = true
            end
        end
        -- A reveal that could not be written leaves the leg as players would see it: anonymous.
        secret = not revealed
    end
    local logStep = RegionMapLog.RecordLeg {
        mapId = path.mapId, pathId = path.id, pathName = Paths.DisplayName(path), fromId = current.fromId,
        toId = current.toId, time = current.time, rest = current.rest, secret = secret, route = route,
    }
    if logStep ~= nil then entry.steps[#entry.steps + 1] = logStep end
    entry.description = description
    return true, nil, entry
end

--- Whether the Director can stop the Party on this path: a way with some time to it.
--- @param path nil|RegionMapPathRecord
--- @return boolean
function RegionMapTravel.CanStopOn(path)
    if path == nil or not Model.IsDirector() then return false end
    local a, b = Duration(path, path.aId), Duration(path, path.bId)
    return (a ~= nil and a > 0) or (b ~= nil and b > 0)
end

-- The newest log entry, when it is the leg that brought the Party to where it is
-- now along this path (Q14): a stop then replaces it.
local function ArrivalLeg(path, party)
    local newest = RegionMapLog.Newest()
    if newest == nil or party == nil or party.locationId == nil then return nil end
    if newest.kind ~= "leg" or newest.pathId ~= path.id or newest.rest ~= "" or newest.toId ~= party.locationId then return nil end
    return newest
end

--- The end the stop card counts from at first (Q14): where the Party's last leg
--- along this path started, else the end it stands at, else the path's a end.
--- @param path RegionMapPathRecord
--- @return string
function RegionMapTravel.StopFrom(path)
    local party = Model.StoredParty()
    local from = path.aId --- @type string
    if party ~= nil and party.mapId == path.mapId then
        local leg = ArrivalLeg(path, party)
        if party.pathId == path.id and party.pathFrom ~= nil then
            from = party.pathFrom --[[@as string]]
        elseif leg ~= nil then
            from = leg.fromId
        elseif party.locationId == path.aId or party.locationId == path.bId then
            from = party.locationId --[[@as string]]
        end
    end
    local time = Duration(path, from)
    if time == nil or time <= 0 then from = OtherEnd(path, from) end
    return from
end

--- Director: stop the Party on a path, spent watches from fromId (G3). It is
--- logged as a stop that counts toward travel time (Q15). When the Party just
--- arrived along this path from fromId, the stop replaces that arrival (Q14).
--- @param pathId string
--- @param fromId string
--- @param spent number watches, above 0 and under the time from fromId
--- @return boolean ok
--- @return nil|RegionMapWriteReason reason
--- @return nil|RegionMapUndoEntry undo
function RegionMapTravel.StopPartway(pathId, fromId, spent)
    if mod.unloaded or not Model.IsDirector() then return false, "permission", nil end
    local path = Paths.Get(pathId)
    if path == nil then return false, "invalid", nil end
    local total = Duration(path, fromId)
    if total == nil or not R.IsFinite(spent) or spent <= 0 or spent >= total then return false, "invalid", nil end
    local before = Model.StoredParty()
    local leg = ArrivalLeg(path, before)
    if leg ~= nil and leg.fromId ~= fromId then leg = nil end
    local description = "Stop Party on region map path"
    local ok, reason, entry = Model.WriteParty {
        mapId = path.mapId, pathId = path.id, pathFrom = fromId, spent = spent, description = description, noLog = true,
    }
    if not ok or entry == nil then return false, reason, nil end
    if leg ~= nil then
        local hideStep = RegionMapLog.HideStep(leg, description)
        if hideStep ~= nil then entry.steps[#entry.steps + 1] = hideStep end
    end
    local logStep = RegionMapLog.RecordStop {
        mapId = path.mapId, pathId = path.id, pathName = Paths.DisplayName(path), fromId = fromId,
        toId = OtherEnd(path, fromId), spent = spent, secret = path.visibility == "hidden",
        route = Slice(path, fromId, 0, spent / total),
    }
    if logStep ~= nil then entry.steps[#entry.steps + 1] = logStep end
    return true, nil, entry
end
