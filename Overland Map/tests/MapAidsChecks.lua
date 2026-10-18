-- Production data, queue and geometry checks; no live game data is written.
local checks = {}
local directory = "Overland Map"
local Base = dofile(directory .. "/tests/LabelChecks.lua")

local function Fixture()
    local f = Base.Fixture()
    f.mod.images = { ["compass-icon"] = "default-compass" }
    local preferences = {}
    f.env.dmhub.GetSettingValue = function(key)
        if key == f.C.preferencesSettingId then return preferences[f.env.dmhub.loginUserid] or {} end
        return 100
    end
    f.env.dmhub.SetSettingValue = function(_, value) preferences[f.env.dmhub.loginUserid] = value end
    for _, name in ipairs({ "OverlandMapPreferences", "OverlandMapControls", "OverlandMapDrawing", "OverlandMapCanvasTools", "OverlandMapAids", "OverlandMapAidLayer", "OverlandMapAidEditor" }) do
        assert(loadfile(directory .. "/" .. name .. ".lua", "t", f.env))()
    end
    f.A, f.S = f.env.OverlandMapAids, f.env.OverlandMapControls
    function f.Row() return f.M.GetLocation(f.map) end
    function f.Aid(kind) return f.A.Snapshot(f.Row(), kind or "compass") end
    function f.Add(kind, patch)
        assert(f.A.Commit(f.map, kind or "compass", patch or {}, "add")); f.Advance(0)
    end
    function f.Scale(scale)
        assert(f.M.UpdateLocation(f.map, { scale = scale or { u1 = 0, v1 = 0, u2 = 0, v2 = 1, distance = 50, unit = "mi" } }))
    end
    function f.Finish() f.writes[#f.writes].callbacks.success(); f.Advance(0) end
    return f
end

local function Near(a, b) assert(math.abs(a - b) < 1e-8, tostring(a) .. " != " .. tostring(b)) end

local function Panels(f)
    local function Panel(args)
        local p = { valid = true, data = args.data or {}, selfStyle = {}, children = {}, classes = {}, events = {}, renderedWidth = 80, renderedHeight = 32 }
        for key, value in pairs(args) do
            if type(key) == "number" then p.children[#p.children + 1] = value
            elseif type(value) == "function" then p.events[key] = value
            elseif key == "classes" then for _, class in ipairs(value) do p.classes[class] = true end
            else p[key] = value end
        end
        function p:SetClass(key, value) self.classes[key] = value end
        function p:HasClass(key) return self.classes[key] == true end
        function p:AddChild(child) self.children[#self.children + 1] = child; child.parent = self end
        function p:SetAsFirstSibling() end
        function p:FireEvent(key, ...) if self.events[key] then self.events[key](self, ...) end end
        function p:DestroySelf() self.valid = false; self:FireEvent("destroy") end
        return p
    end
    f.env.gui.Panel, f.env.gui.Label = Panel, Panel
    f.S.UIScale = function() return 1 end
    return Panel
end

function checks.Run()
    local passed = 0
    local function Check(name, run) run(Fixture()); passed = passed + 1; print("MAP AIDS PASS: " .. name) end
    Check("maps start empty; aids are independent and schema stays unchanged", function(f)
        assert(f.Row().mapAids == nil and f.Aid() == nil)
        f.Add(); assert(f.Aid().width == 0.06 and f.Aid().angle == 0 and f.Aid().text == "N")
        assert(f.Aid("scaleBar") == nil and f.Row().schemaVersion == f.C.locationSchemaVersion)
        f.Scale(); f.Add("scaleBar", { distance = 20 })
        assert(f.Aid().text == "N" and f.Aid("scaleBar").size == 0.015)
        assert(f.Aid().background == "none" and f.Aid("scaleBar").background == "none")
    end)
    Check("rectangular horizontal, vertical and diagonal calibration", function(f)
        f.Scale(); Near(f.env.OverlandMapGeometry.Calibration(f.Row(), 4000, 2000), 100)
        Near(f.env.OverlandMapGeometry.InitialDistance(f.Row(), 4000, 2000), 20)
        Near(f.env.OverlandMapGeometry.ScaleWidth(f.Row(), { distance = 20 }, 4000, 2000), 0.2)
        f.Scale({ u1 = 0, v1 = 0, u2 = 0.5, v2 = 1, distance = math.sqrt(2) * 50, unit = "km" })
        Near(f.env.OverlandMapGeometry.Calibration(f.Row(), 4000, 2000), 100)
        f.Scale({ u1 = 0.2, v1 = 0.5, u2 = 0.7, v2 = 0.5, distance = 50, unit = "mi" })
        Near(f.env.OverlandMapGeometry.Calibration(f.Row(), 2000, 4000), 100)
    end)
    Check("initial distances are the largest nice number within twenty percent", function(f)
        for _, units in ipairs({ 0.00003, 0.19, 3, 9, 24, 100, 1001, 1e20 }) do
            f.Scale({ u1 = 0, v1 = 0, u2 = 1, v2 = 0, distance = units, unit = "mi" })
            local value = f.env.OverlandMapGeometry.InitialDistance(f.Row(), 3000, 1500)
            assert(value > 0 and value <= units * 0.2)
            local exponent = 10 ^ math.floor(math.log(value, 10))
            local factor = value / exponent
            assert(math.abs(factor - 1) < 1e-8 or math.abs(factor - 2) < 1e-8 or math.abs(factor - 5) < 1e-8 or math.abs(factor - 10) < 1e-8)
            local nextValue = value * (factor < 1.5 and 2 or factor < 3 and 2.5 or 2)
            assert(nextValue > units * 0.2)
        end
    end)
    Check("zoom, unit changes and recalibration preserve represented distance", function(f)
        f.Scale(); f.Add("scaleBar", { distance = 20 })
        local fraction = f.env.OverlandMapGeometry.ScaleWidth(f.Row(), f.Aid("scaleBar"), 4000, 2000)
        Near(fraction * 800 * 3, 480)
        f.Scale({ u1 = 0, v1 = 0, u2 = 0, v2 = 1, distance = 100, unit = "km" })
        local width, _, unit = f.env.OverlandMapGeometry.ScaleWidth(f.Row(), f.Aid("scaleBar"), 4000, 2000)
        Near(width, 0.1); assert(unit == "km" and f.Aid("scaleBar").distance == 20)
    end)
    Check("tiny and oversized distances stay finite and retain their stored value", function(f)
        f.Scale(); f.Add("scaleBar", { distance = 1e-12 })
        assert(f.env.OverlandMapGeometry.ScaleWidth(f.Row(), f.Aid("scaleBar"), 4000, 2000) > 0)
        f.A.Commit(f.map, "scaleBar", { distance = 1e300 }); f.Advance(0)
        local width, reason = f.env.OverlandMapGeometry.ScaleWidth(f.Row(), f.Aid("scaleBar"), 4000, 2000)
        assert(width == nil and reason == "aids.tooLong" and f.Aid("scaleBar").distance == 1e300)
    end)
    Check("missing or degenerate calibration cannot add or render a scale bar", function(f)
        assert(not f.M.SetMapAid(f.map, "scaleBar", { distance = 10 }, "add"))
        assert(f.env.OverlandMapGeometry.Calibration(f.Row(), 4000, 2000) == nil)
        f.Scale({ u1 = 0.5, v1 = 0.5, u2 = 0.5, v2 = 0.5, distance = 10, unit = "mi" })
        assert(not f.M.SetMapAid(f.map, "scaleBar", { distance = 10 }, "add"))
        assert(f.env.OverlandMapGeometry.ScaleWidth(f.Row(), { distance = 10 }, 4000, 2000) == nil)
        f.Scale(); assert(f.env.OverlandMapGeometry.Calibration(f.Row(), 0, 2000) == nil)
        assert(f.env.OverlandMapGeometry.Calibration(f.Row(), math.huge, 2000) == nil)
    end)
    Check("malformed optional aid leaves never invalidate the map", function(f)
        local row = f.R.LocationsTable()[f.map]
        for _, value in ipairs({ 42, "bad", { compass = false }, { compass = { angle = 0/0, width = -1, u = math.huge } },
            { scaleBar = { distance = math.huge, size = 0 } } }) do
            row.mapAids = value; f.M.InvalidateIndex(); assert(f.Row())
            local compass = f.Aid(); if compass then assert(compass.angle == 0 and compass.u == 0.12 and compass.width == 0.06) end
        end
        assert(f.env.OverlandMapGeometry.ScaleWidth(f.Row(), f.Aid("scaleBar"), 4000, 2000) == nil)
    end)
    Check("unknown nested data survives leaf edits and removing the other aid", function(f)
        f.Add()
        f.R.LocationsTable()[f.map].mapAids.future = { nested = { 7, 8 } }
        f.R.LocationsTable()[f.map].mapAids.compass.future = { nested = { mode = "keep" } }
        f.M.InvalidateIndex()
        f.A.Commit(f.map, "compass", { angle = 90 }); f.Advance(0)
        assert(f.Row().mapAids.compass.future.nested.mode == "keep")
        f.A.Commit(f.map, "compass", {}, "remove"); f.Advance(0)
        assert(f.Row().mapAids.future.nested[2] == 8)
    end)
    Check("Director, player, View as player and Undo authorization", function(f)
        f.Add()
        f.env.dmhub.isDM = false
        assert(not f.A.Commit(f.map, "compass", { angle = 90 }))
        assert(not f.M.SetMapAid(f.map, "compass", {}, "remove"))
        assert(not f.U.UndoLast())
        f.env.dmhub.isDM = true; f.M.SetViewAsPlayer(true)
        assert(not f.M.SetMapAid(f.map, "compass", { angle = 90 }, "edit"))
        f.M.SetViewAsPlayer(false)
        -- A refused UndoLast drops that stack entry; a fresh permitted edit remains undoable.
        assert(not f.U.HasUndo())
        f.A.Commit(f.map, "compass", { angle = 45 }); f.Advance(0)
        assert(f.U.UndoLast()); f.Advance(0); assert(f.Aid().angle == 0)
    end)
    Check("invalid writes and missing artwork preserve the existing reference", function(f)
        f.images.art = { imageid = "asset", HaveReadPermissions = function() return true end }
        f.Add("compass", { imageId = "art" }); f.images.art = nil
        assert(f.A.Commit(f.map, "compass", { angle = 90 })); f.Advance(0)
        assert(f.Aid().imageId == "art")
        for _, patch in ipairs({ { imageId = "missing" }, { u = -1 }, { v = 2 }, { width = 0/0 }, { opacity = 2 }, { unknown = true } }) do
            assert(not f.A.Commit(f.map, "compass", patch))
        end
    end)
    Check("each confirmed gesture has one Undo; repeated no-ops have none", function(f)
        f.Add()
        f.A.Commit(f.map, "compass", { u = 0.3, v = 0.8 }); f.Advance(0)
        local n = #f.writes
        f.A.Commit(f.map, "compass", { u = 0.3, v = 0.8 }); f.Advance(0); assert(#f.writes == n)
        assert(f.U.UndoLast()); f.Advance(0); assert(f.Aid().u == 0.12 and f.Aid().v == 0.15)
        assert(f.U.UndoLast()); f.Advance(0); assert(f.Aid() == nil)
    end)
    Check("busy saves rebase each gesture on fresh remote fields", function(f)
        f.Add(); f.mode = "pending"
        f.A.Commit(f.map, "compass", { angle = 90 })
        f.A.Commit(f.map, "compass", { u = 0.4 }); f.A.Commit(f.map, "compass", { v = 0.7 })
        local n = #f.writes
        local row = f.R.LocationsTable()[f.map]
        row.name, row.mapAids.compass.text = "Remote name", "North"
        row.revision, row.mutationId = row.revision + 1, "remote"; f.M.InvalidateIndex()
        f.Finish(); assert(#f.writes == n + 1); f.Finish(); f.Finish()
        assert(f.Row().name == "Remote name" and f.Aid().text == "North" and f.Aid().u == 0.4 and f.Aid().v == 0.7)
    end)
    Check("failed add Retry retains the original Undo baseline", function(f)
        f.mode = "fail"; f.Add(); assert(f.A.Status(f.map) == "failed")
        f.A.Commit(f.map, "compass", { angle = 180 })
        f.mode = nil; f.A.Retry(f.map); f.Advance(0)
        assert(f.A.Status(f.map) == "saved" and f.Aid().angle == 180)
        assert(f.U.UndoLast()); f.Advance(0); assert(f.Aid().angle == 0)
        assert(f.U.UndoLast()); f.Advance(0); assert(f.Aid() == nil)
    end)
    Check("permission changes cancel queued gestures; remote removal is not resurrected", function(f)
        f.Add(); f.mode = "pending"
        f.A.Commit(f.map, "compass", { angle = 90 }); f.A.Commit(f.map, "compass", { u = 0.7 })
        local n = #f.writes; f.M.SetViewAsPlayer(true); f.Finish(); f.Advance(2)
        assert(#f.writes == n and f.Row().mapAids.compass.u == 0.12)
        f.M.SetViewAsPlayer(false); f.mode = nil
        f.R.LocationsTable()[f.map].mapAids.compass = nil; f.M.InvalidateIndex()
        assert(not f.M.SetMapAid(f.map, "compass", { angle = 45 }, "edit"))
    end)
    Check("image replacement preserves aids and subtree/removal Undo restores them", function(f)
        local ok, _, _, id = f.M.CreateLocation(f.map, 0.5, 0.5, nil, nil, "Child"); assert(ok)
        assert(f.M.AddMap(id, "child")); f.map = id; f.Add()
        assert(f.M.ReplaceImage(id, "replacement") and f.Aid().text == "N")
        local removed, _, entry = f.M.RemoveMap(id); assert(removed and f.Row().mapAids == nil)
        assert(f.M.Revert(entry) and f.Aid().text == "N")
        local deleted, _, undo = f.M.DeleteLocation(id); assert(deleted)
        assert(f.M.Revert(undo) and f.Aid().text == "N")
    end)
    Check("stale Undo cannot overwrite a concurrent map edit", function(f)
        f.Add(); f.M.UpdateLocation(f.map, { name = "Newer" }); assert(not f.U.UndoLast())
    end)
    Check("north follows rectangular art at cardinal and intermediate angles", function(f)
        for _, angle in ipairs({ 0, 90, 180, 270, 33, 147, 315 }) do
            for _, dimensions in ipairs({ { 60, 120, 20, 12 }, { 120, 40, 180, 24 } }) do
                local _, h, tw, th = table.unpack(dimensions)
                local x, y = f.env.OverlandMapGeometry.NorthAnchor(h, angle, tw, th, 5)
                local a = math.rad(angle)
                Near(x * math.cos(a) + y * math.sin(a), 0)
                Near(x * math.sin(a) - y * math.cos(a), h/2 + math.abs(math.sin(a))*tw/2 + math.abs(math.cos(a))*th/2 + 5)
            end
        end
    end)
    Check("colliding scale labels stagger with fixed ticks and endpoints", function(f)
        for _, length in ipairs({ 0.0001, 12, 100, 1000 }) do
            local labels = f.env.OverlandMapGeometry.ScaleLabels(length, { {width=80,height=20}, {width=90,height=30}, {width=180,height=24} }, 6)
            Near(labels[1].x, -length/2); Near(labels[2].x, 0); Near(labels[3].x, length/2)
            for i, a in ipairs(labels) do for j, b in ipairs(labels) do
                if i ~= j then assert(a.x+a.width/2+6 <= b.x-b.width/2 or b.x+b.width/2+6 <= a.x-a.width/2 or a.row ~= b.row) end
            end end
            if length < 100 then assert(labels[3].row == 3) end
            for _, label in ipairs(labels) do
                for _, span in ipairs(f.env.OverlandMapGeometry.TickSegments(label, labels, 6)) do
                    assert(span.last > span.first and span.first >= 0 and span.last <= label.top)
                    for _, other in ipairs(labels) do
                        if other.row < label.row and math.abs(label.x-other.x) <= other.width/2 then
                            assert(span.last <= other.top or span.first >= other.top+other.height)
                        end
                    end
                end
            end
        end
    end)
    Check("personal preferences are isolated per viewer and do not write map rows", function(f)
        local n = #f.writes
        assert(f.env.OverlandMapPreferences.ShowCompass() and f.env.OverlandMapPreferences.ShowScaleBar() and f.env.OverlandMapPreferences.ShowHoverText())
        f.env.OverlandMapPreferences.SetShowCompass(false); f.env.OverlandMapPreferences.SetShowScaleBar(false); f.env.OverlandMapPreferences.SetShowHoverText(false)
        f.env.dmhub.loginUserid = "player"
        assert(f.env.OverlandMapPreferences.ShowCompass() and f.env.OverlandMapPreferences.ShowScaleBar() and f.env.OverlandMapPreferences.ShowHoverText())
        f.env.dmhub.loginUserid = "director"
        assert(not f.env.OverlandMapPreferences.ShowCompass() and not f.env.OverlandMapPreferences.ShowHoverText() and #f.writes == n)
    end)
    Check("hover dismissal affects tracked map text only", function(f)
        f.env.gui.Tooltip = function(text) return function(panel) panel.tooltip = text end end
        local pin, button = { valid = true }, { valid = true, tooltip = "Button help" }
        f.S.HoverText(pin, "Name"); assert(pin.tooltip == "Name")
        f.env.OverlandMapPreferences.SetShowHoverText(false); f.S.DismissHoverText()
        assert(pin.tooltip == nil and button.tooltip == "Button help")
        f.S.HoverText(pin, "Name"); assert(pin.tooltip == nil)
    end)
    Check("rendered endpoints survive font, padding and background changes; pans only translate", function(f)
        Panels(f); f.Scale(); f.Add("scaleBar", { distance = 20 })
        local ctx = { data = { selectedAid = "scaleBar", locked = true, tool = "none" }, IsAlive = function() return true end }
        local layer = f.env.OverlandMapAidLayer.Create(ctx)
        layer.Metrics(4000, 2000); layer.Bind(f.Row())
        local layout = { x=0,y=0,width=1000,height=500,viewWidth=1000,viewHeight=500 }
        layer.Layout(layout)
        local before = f.env.DeepCopy(layer.Geometry("scaleBar").endpoints)
        for _, patch in ipairs({ { size = 0.08, font = "courier" }, { background = "plate", backgroundPadX = 10 },
            { backgroundSizing = "manual", backgroundWidth = 2, backgroundHeight = 1, backgroundX = 1 } }) do
            f.A.Commit(f.map, "scaleBar", patch); f.Advance(0); layer.Bind(f.Row()); layer.Layout(layout)
            local after = layer.Geometry("scaleBar").endpoints
            Near(after[1], before[1]); Near(after[2], before[2])
        end
        local children = layer.layer.children
        layer.Layout({ x=23,y=31,width=1000,height=500,viewWidth=1000,viewHeight=500 })
        assert(layer.layer.x == 23 and layer.layer.y == 31 and layer.layer.children == children)
        layer.Layout({ x=0,y=0,width=3000,height=1500,viewWidth=1000,viewHeight=500 })
        Near(layer.Geometry("scaleBar").endpoints[2], before[2])
    end)
    Check("passive aids support canvas selection without intercepting other map content", function(f)
        Panels(f); f.Scale(); f.Add("scaleBar", { distance = 20 })
        local ctx = { data = { locked = false, tool = "none" }, IsAlive = function() return true end }
        local layer = f.env.OverlandMapAidLayer.Create(ctx)
        layer.Metrics(4000, 2000); layer.Bind(f.Row())
        local layout = { x=0,y=0,width=1000,height=500,viewWidth=1000,viewHeight=500 }
        layer.Layout(layout)
        assert(not layer.layer.interactable and layer.handles.children[2]:HasClass("collapsed"))
        assert(layer.HitTest(200, 425) == "scaleBar" and layer.HitTest(800, 100) == nil)
        ctx.data.selectedAid = "scaleBar"; layer.Bind(f.Row()); layer.Layout(layout)
        assert(not layer.handles.children[1]:HasClass("collapsed"))
        for _, handle in ipairs(layer.handles.children) do assert(handle.interactable == false) end
        ctx.data.locked = true; layer.Bind(f.Row()); layer.Layout(layout)
        assert(layer.handles.children[2]:HasClass("collapsed"))
        f.env.OverlandMapPreferences.SetShowScaleBar(false); ctx.data.selectedAid = nil; layer.Bind(f.Row()); layer.Layout(layout)
        assert(layer.Geometry("scaleBar") == nil)
        assert(layer.HitTest(200, 425) == nil)
    end)
    Check("text resizing scales unchanged glyphs and measured clearance at every rotation", function(f)
        Panels(f); f.Add("compass", { u = 0.5, v = 0.5 })
        local ctx = { data = { selectedAid = "compass", locked = false, tool = "none" }, IsAlive = function() return true end }
        local layer = f.env.OverlandMapAidLayer.Create(ctx)
        layer.Metrics(4000, 2000); layer.Bind(f.Row())
        local layout = { x=0,y=0,width=1000,height=500,viewWidth=1000,viewHeight=500 }
        layer.Layout(layout)
        local root = layer.layer.children[1]
        local art = root.children[#root.children]
        art.bgimageWidth, art.bgimageHeight = 200, 100
        art:FireEvent("imageLoaded"); f.Advance(0.1)
        local text = root.children[2]
        local original = text.selfStyle.scale
        for _, angle in ipairs({ 0, 90, 180, 270, 37 }) do
            layer.SetPreview("compass", { size = 0.03, angle = angle }); layer.Layout(layout)
            local box = layer.Geometry("compass")
            Near(text.selfStyle.scale, original * 2)
            Near(text.selfStyle.fontSize, 64)
            Near(box.text.x2 - box.text.x1, text.renderedWidth * original * 2)
            Near(box.text.y2 - box.text.y1, text.renderedHeight * original * 2)
            assert(layer.HitTest(500, 250) == "compass")
            local a = math.rad(angle)
            local hx, hy = 500 + 30*math.cos(a) - 15*math.sin(a), 250 + 30*math.sin(a) + 15*math.cos(a)
            assert(layer.HandleAt(hx, hy) == "resize")
            local moved = { x=20,y=10,width=1000,height=500,viewWidth=1000,viewHeight=500 }
            layer.Layout(moved)
            assert(layer.HandleAt(hx+20, hy+10) == "resize" and layer.HitTest(520, 260) == "compass")
            layer.Layout(layout)
        end
        ctx.data.locked = true; layer.Bind(f.Row()); layer.Layout(layout)
        assert(layer.HandleAt(530, 265) == nil)
        f.M.SetViewAsPlayer(true)
        assert(layer.HitTest(500, 250) == nil and layer.HandleAt(530, 265) == nil)
    end)
    Check("edge selections reveal artwork and handles without changing saved anchors", function(f)
        Panels(f); f.Add()
        local ctx = { data = { selectedAid = "compass", locked = false, tool = "none" }, IsAlive = function() return true end }
        local layer = f.env.OverlandMapAidLayer.Create(ctx)
        layer.Metrics(4000, 2000); layer.Bind(f.Row())
        local layout = { x=0,y=0,width=1000,height=500,viewWidth=1000,viewHeight=500 }
        layer.Layout(layout)
        local root = layer.layer.children[1]
        local art = root.children[#root.children]
        art.bgimageWidth, art.bgimageHeight = 200, 100
        art:FireEvent("imageLoaded"); f.Advance(0.1)
        local bounds = layer.EditBounds("compass")
        local area = { x1=8,x2=992,y1=110,y2=446 }
        local dx, dy = f.env.OverlandMapGeometry.RevealOffset(bounds, area)
        assert(dy > 0)
        layer.Layout({ x=dx,y=dy,width=1000,height=500,viewWidth=1000,viewHeight=500 })
        local visible = layer.EditBounds("compass")
        Near(visible.x1, bounds.x1 + dx); Near(visible.y1, bounds.y1 + dy)
        assert(visible.x1 >= area.x1 and visible.x2 <= area.x2 and visible.y1 >= area.y1 and visible.y2 <= area.y2)
        local nx, ny = f.env.OverlandMapGeometry.RevealOffset(visible, area); Near(nx, 0); Near(ny, 0)
        Near(f.Aid().u, 0.12); Near(f.Aid().v, 0.15)
        local _, bottom = f.env.OverlandMapGeometry.RevealOffset({x1=20,x2=40,y1=470,y2=500}, area); Near(bottom, -54)
        local right = f.env.OverlandMapGeometry.RevealOffset({x1=980,x2=1010,y1=120,y2=140}, area); Near(right, -18)
    end)
    Check("Undo cancels map-only selection without constructing the settings editor", function(f)
        Panels(f); f.Add(); f.A.Commit(f.map, "compass", { u = 0.6 }); f.Advance(0)
        local ctx = { data = { selectedAid = "compass", locked = false, tool = "none" }, IsAlive = function() return true end }
        ctx.ClearAid = function() ctx.data.selectedAid = nil end
        local layer = f.env.OverlandMapAidLayer.Create(ctx)
        layer.Bind(f.Row())
        assert(f.U.UndoLast()); f.Advance(0)
        assert(ctx.data.selectedAid == nil)
        Near(f.Aid().u, 0.12)
        layer.layer:DestroySelf()
    end)
    Check("cold compass loading stays active; late callbacks cannot affect a new map", function(f)
        Panels(f); f.Add()
        local ctx = { data = { locked = true, tool = "none" }, IsAlive = function() return true end }
        local layer = f.env.OverlandMapAidLayer.Create(ctx)
        layer.Metrics(4000, 2000); layer.Bind(f.Row())
        local layout = { x=0,y=0,width=1000,height=500,viewWidth=1000,viewHeight=500 }
        layer.Layout(layout)
        local root = layer.layer.children[1]
        assert(root:HasClass("hidden") and not root:HasClass("collapsed"))
        local art = root.children[#root.children]
        art.bgimageWidth, art.bgimageHeight = 120, 240
        art:FireEvent("imageLoaded"); f.Advance(0.1)
        assert(layer.Availability("compass") == "ready" and not root:HasClass("hidden"))
        Near(layer.Geometry("compass").height, layer.Geometry("compass").width * 2)
        layer.Retry(); layer.Layout(layout)
        local replacement = root.children[#root.children]
        assert(not art.valid and layer.Availability("compass") == "loading")
        art:FireEvent("imageLoaded")
        assert(layer.Availability("compass") == "loading")
        local nextMap = f.env.DeepCopy(f.Row()); nextMap.id = "different-map"
        layer.Bind(nextMap); layer.Layout(layout)
        replacement:FireEvent("imageLoaded")
        assert(not root.valid and layer.Availability("compass") == "loading")
        f.Advance(f.C.artworkTimeout + 0.1)
        assert(layer.Availability("compass") == "unavailable" and f.Aid().imageId == "")
        f.images.custom = { imageid = "old-source", HaveReadPermissions = function() return true end }
        f.A.Commit(f.map, "compass", { imageId = "custom" }); f.Advance(0)
        layer.Bind(f.Row()); layer.Layout(layout)
        root = layer.layer.children[#layer.layer.children]
        art = root.children[#root.children]
        art.bgimageWidth, art.bgimageHeight = 120, 12000
        f.images.custom.imageid = "new-source"
        art:FireEvent("imageLoaded")
        assert(layer.Availability("compass") == "loading")
        layer.Bind(f.Row())
        art = root.children[#root.children]
        art.bgimageWidth, art.bgimageHeight = 120, 12000
        art:FireEvent("imageLoaded"); f.Advance(0.1)
        Near(layer.Geometry("compass").height, layer.Geometry("compass").width * 100)
        Near(f.Aid().u, 0.12)
    end)
    Check("Find centres edge anchors without changing the aid or ordinary camera clamping", function(f)
        local tools = f.env.OverlandMapCanvasTools
        f.Add("compass", { u = 0, v = 1 })
        local camera = { centerX = 0, centerY = 1, zoom = 1, allowEdgeFocus = true }
        local layout = f.env.OverlandMapGeometry.CalculateImageLayout(1000, 800, 4000, 2000, camera)
        local x, y = f.env.OverlandMapGeometry.ImageToPanel(layout, f.Aid().u, f.Aid().v)
        Near(x, 500); Near(y, 400)
        assert(f.Aid().u == 0 and f.Aid().v == 1)
        camera.allowEdgeFocus = nil
        f.env.OverlandMapGeometry.CalculateImageLayout(1000, 800, 4000, 2000, camera)
        Near(camera.centerX, 0.5); Near(camera.centerY, 0.5)
    end)
    Check("View as player flushes typed fields; Undo cancels a later editor draft", function(f)
        local Panel = Panels(f)
        for _, name in ipairs({ "Button", "Input", "Check", "ColorPicker", "Dropdown" }) do f.env.gui[name] = Panel end
        f.S.ScaleColorPopup = function() end
        f.S.AppearanceEditor = function() return Panel { data = {
            bind = function() end, suspend = function() end, invalid = function() return false end,
        } } end
        f.Add()
        local settings
        local canvas = Panel { data = { aidLayer = { SetPreview = function() end, Availability = function() return "ready" end } } }
        local ctx = { data = { mapId = f.map, selectedAid = "compass", popover = "aids" },
            IsAlive = function() return true end, CurrentMap = f.Row, root = { Get = function() return canvas end } }
        ctx.ClearAid = function() ctx.data.selectedAid = nil end
        ctx.RefreshAll = function() if settings then settings.data.bind(f.Row()) end end
        settings = f.env.OverlandMapAidEditor.Create(ctx); settings.data.bind(f.Row())
        local function Find(panel, id)
            if panel.id == id or panel.text == id then return panel end
            for _, child in ipairs(panel.children) do local found = Find(child, id); if found then return found end end
        end
        local width = assert(Find(settings, "overland-map-aid-width"))
        width.text = "15"; width:FireEvent("edit")
        f.M.SetViewAsPlayer(true)
        Near(f.Aid().width, 0.15)
        f.M.SetViewAsPlayer(false); f.Advance(0); settings.data.bind(f.Row())
        width.text = "25"; width:FireEvent("edit")
        assert(f.U.UndoLast()); f.Advance(0)
        Near(f.Aid().width, 0.06)
        local writes = #f.writes
        width:FireEvent("change"); f.Advance(5)
        assert(ctx.data.selectedAid == nil and #f.writes == writes)
        ctx.data.selectedAid = "compass"; settings.data.bind(f.Row())
        f.R.LocationsTable()[f.map].mapAids = nil; f.M.InvalidateIndex()
        assert(Find(settings, "Choose image...")):FireEvent("click")
        settings:DestroySelf()
    end)
    print("MAP AIDS CHECKS: " .. passed .. " passed")
    return passed
end
if ... == "run" then checks.Run() end
return checks
