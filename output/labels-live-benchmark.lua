-- Run through the MCP bridge after the label test fixture is installed; that fixture sets this global at runtime.
---@diagnostic disable-next-line: undefined-global
local f = assert(CodexLabelFixture)
local canvas = f.Open(nil)
f.ctx.SetPopover(nil)
f.ctx.SelectLabel(nil)
local M, P, L, S = RegionMapModel, RegionMapPaths, RegionMapLabels, RegionMapSession
local originals = { get = M.GetLocation, children = M.Children, paths = P.Paths, labels = L.ForMap, names = S.ShowNames }
local map = DeepCopy(M.GetLocation(f.mapId)); map.mode = "pointcrawl"
local camera = DeepCopy(f.ctx.data.camera)
local pins, byId, paths, lettering = {}, {}, {}, {}
for i = 1, 250 do
    local pin = { id = "label-bench-pin-" .. i, parentId = f.mapId, name = "Pin " .. i, u = ((i-1)%25 + 0.5)/25,
        v = (math.floor((i-1)/25)+0.5)/10, pinStyle = "iconOnly", importance = "normal", icon = "",
        visibility = "revealed", imageId = "", artworkImageId = "", imageRevision = 0, mapShared = false,
        ownerId = dmhub.loginUserid, ownerName = "Fixture", createdByDirector = true, revision = 1, hidden = false }
    pins[#pins+1], byId[pin.id] = pin, pin
end
for i = 1, 150 do
    paths[#paths+1] = { id = "label-bench-path-" .. i, mapId = f.mapId, aId = pins[i].id, bId = pins[i+25].id,
        bends = {}, name = "Path " .. i, typeId = "", time = 1, back = "same", backTime = 1,
        visibility = "revealed", revision = 1, hidden = false }
end
local mockGet = function(id) return byId[id] or (id == f.mapId and map) or originals.get(id) end
local mockChildren = function(id) if id == f.mapId then return pins end return originals.children(id) end
local mockPaths = function(id) if id == f.mapId then return paths end return originals.paths(id) end
local mockLabels = function(id) if id == f.mapId then return lettering end return originals.labels(id) end
local mockNames = function() return false end
M.GetLocation, M.Children, P.Paths, L.ForMap, S.ShowNames = mockGet, mockChildren, mockPaths, mockLabels, mockNames
local report = { pins = #pins, paths = #paths, rows = {} }
local bench = { report = report }
function bench.SetCount(count)
    lettering = {}
    for i = 1, count do
        local row = L.Format({})
        row.id, row.mapId, row.text = "label-bench-text-" .. i, f.mapId, "Region " .. i
        row.u, row.v = ((i-1)%20+0.5)/20, (math.floor((i-1)/20)+0.5)/math.max(1,math.ceil(count/20))
        row.angle, row.visibility, row.revision, row.hidden = (i%5-2)*15, "revealed", 1, false
        row.ownerId = dmhub.loginUserid
        lettering[#lettering+1] = row
    end
    f.ctx.data.camera = { zoom = 1, centerX = 0.5, centerY = 0.5 }
    M.InvalidateIndex()
    f.ctx.RefreshAll()
end
function bench.Measure()
    local layer = canvas.data.labelLayer
    local row = { labels = #lettering, textPanels = #layer.layer.children / 2 }
    local writes = layer.metrics.styleWrites
    local start = os.clock()
    for i=1,60 do f.ctx.data.camera.centerX = 0.48 + (i%10)*0.004; canvas:FireEvent("relayout") end
    row.panLayoutMs = (os.clock()-start)*1000/60
    row.panStyleWrites = layer.metrics.styleWrites-writes
    start = os.clock()
    for i=1,40 do f.ctx.data.camera.zoom = 1+(i%20); canvas:FireEvent("relayout") end
    row.zoomLayoutMs = (os.clock()-start)*1000/40
    f.ctx.data.camera = { zoom = 1, centerX = 0.5, centerY = 0.5 }
    canvas:FireEvent("relayout")
    report.rows[#report.rows+1] = row
    return row
end
function bench.Restore()
    if M.GetLocation == mockGet then M.GetLocation = originals.get end
    if M.Children == mockChildren then M.Children = originals.children end
    if P.Paths == mockPaths then P.Paths = originals.paths end
    if L.ForMap == mockLabels then L.ForMap = originals.labels end
    if S.ShowNames == mockNames then S.ShowNames = originals.names end
    f.ctx.data.camera = camera
    M.InvalidateIndex()
    if f.ctx.IsAlive() then f.ctx.RefreshAll() end
end
CodexLabelBenchmark = bench
bench.SetCount(0)
return report
