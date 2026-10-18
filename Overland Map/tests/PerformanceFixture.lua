local fixture = {}
local Base = dofile("Overland Map/tests/LabelChecks.lua")

--- Deterministic in-memory data; the transport never reaches a live game's tables.
--- @param dense boolean
--- @return table
function fixture.Create(dense)
    local f = Base.Fixture()
    f.R.LocationsTable()[f.map].mode = "pointcrawl"
    f.M.InvalidateIndex()
    local items = {}
    for i = 1, 250 do
        items[i] = { name = string.format("Pin %03d", i), u = 0.04 + ((i - 1) % 25) * 0.038,
            v = 0.05 + math.floor((i - 1) / 25) * 0.1,
            style = { visibility = i % 11 == 0 and "hidden" or "revealed",
                importance = ({ "major", "normal", "minor" })[(i - 1) % 3 + 1] } }
    end
    local ok, _, pins = f.M.CreateLocations(f.map, items)
    assert(ok and #pins == 250)
    local paths = f.env.OverlandMapPaths
    local types = paths.Types()
    local bendCount = dense and f.C.pathBendLimit or 2
    for i = 1, 150 do
        local a, b = items[i], items[i + 1]
        local bends = {}
        for j = 1, bendCount do
            local t = j / (bendCount + 1)
            bends[j] = { u = a.u + (b.u - a.u) * t,
                v = math.max(0, math.min(1, a.v + (b.v - a.v) * t + math.sin(t * math.pi * 2) * 0.035)) }
        end
        assert(paths.CreatePath(f.map, pins[i].id, pins[i + 1].id, {
            bends = bends, name = string.format("Path %03d", i),
            typeId = types[(i - 1) % #types + 1].id,
            visibility = i % 9 == 0 and "hidden" or "revealed",
        }))
    end
    for i = 1, 50 do
        assert(f.L.Create(f.map, 0.05 + ((i - 1) % 10) * 0.1, 0.1 + math.floor((i - 1) / 10) * 0.18,
            { text = string.format("Label %02d", i), background = "none" }))
    end
    assert(f.M.UpdateLocation(f.map, { scale = { u1 = 0, v1 = 0, u2 = 1, v2 = 0, distance = 100, unit = "mi" } }))
    assert(f.M.SetMapAid(f.map, "compass", {}, "add"))
    assert(f.M.SetMapAid(f.map, "scaleBar", { distance = 20 }, "add"))
    f.fixture = { pins = 250, paths = 150, labels = 50, aids = 2, bends = bendCount,
        imageWidth = 4000, imageHeight = 2000, viewportWidth = 1200, viewportHeight = 720 }
    return f
end

return fixture
