-- Exercise real format/permission/geometry code without writing live game data.
local checks = {}
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = source:match("^(.*)/tests/[^/]+$") or "Region Map"
local Base = dofile(directory .. "/tests/LabelChecks.lua")
local function Fixture()
    local f = Base.Fixture()
    f.A = f.env.RegionMapTextAppearance
    f.env.assets = { imagesTable = {
        art = { imageid = "art-source", HaveReadPermissions = function() return true end },
        second = { imageid = "second-source", HaveReadPermissions = function() return true end },
        video = { imageid = "video-source", isVideo = true, HaveReadPermissions = function() return true end },
        private = { imageid = "private-source", HaveReadPermissions = function() return false end },
    } }
    f.env.RegionMapSession = { SetText = function(p, text) p.text = text end, SetClassIf = function(p, key, value) p.classes[key] = value end }
    f.env.ThemeEngine = { MergeTokens = function() return { { fontFace = "berling", color = "#ffffffff", bgcolor = "#111111ff" } } end,
        OnThemeChanged = function() end }
    for _, file in ipairs({ "RegionMapLabelLayer", "RegionMapPinText" }) do assert(loadfile(directory .. "/" .. file .. ".lua", "t", f.env))() end
    f.P = f.env.RegionMapPinText
    function f.Player()
        f.env.dmhub.isDM, f.env.dmhub.loginUserid = true, "player"
        assert(f.L.SetPlayersCanManage(true))
        f.env.dmhub.isDM = false
        return f.Create("Player label")
    end
    return f
end

local function MockPanels(f)
    local function Panel(args)
        local p = { data = args.data or {}, selfStyle = {}, valid = true, children = {}, classes = {}, events = {} }
        for key, value in pairs(args) do
            if type(key) == "number" then p.children[#p.children + 1] = value
            elseif type(value) == "function" then p.events[key] = value end
        end
        function p:SetClass(key, value) self.classes[key] = value end
        function p:AddChild(child) self.children[#self.children + 1] = child end
        function p:FireEvent(event, ...) if self.events[event] then self.events[event](self, ...) end end
        function p:DestroySelf() self:FireEvent("destroy"); self.valid = false end
        return p
    end
    f.env.gui.Panel, f.env.gui.Label = Panel, Panel
    return Panel
end

function checks.Run()
    local passed = 0
    local function Check(name, fn) fn(Fixture()); passed = passed + 1; print("APPEARANCE PASS: " .. name) end
    Check("legacy defaults and independent outline modes", function(f)
        local format = f.L.Format({ color = "#ffffffff" })
        assert(format.outlineMode == "default" and f.A.Outline(format, 0, "#000000") == 0)
        assert(f.A.Outline(format, 0.3, "#000000") == 0.3)
        format.outlineMode = "none"; assert(f.A.Outline(format, 0.3, "#000000") == 0)
        format.outlineMode, format.outlineWidth, format.background = "custom", 0.17, "image"
        local width, color = f.A.Outline(format, 0, "#000000")
        assert(width == 0.17 and color == "#000000ff")
        local pin = f.P.Format(f.M.GetLocation(f.map))
        assert(pin.backgroundWidth == 180 and pin.backgroundHeight == 30 and pin.background == "default")
    end)
    Check("invalid optional fields never invalidate the owning label", function(f)
        local id = f.Create()
        for key, value in pairs({ outlineWidth = 0 / 0, outlineColor = "red", backgroundFit = "tile", backgroundSizing = "bad", backgroundWidth = -1 }) do
            assert(not f.L.Update(id, { [key] = value }))
            f.L.Table()[id][key] = value
        end
        f.M.InvalidateIndex()
        assert(f.L.Get(id) and f.L.Format(f.L.Get(id)).backgroundFit == "fit")
    end)
    Check("image activation is atomic and rejects video/private assets", function(f)
        local id = f.Create()
        assert(not f.L.Update(id, { background = "image" }))
        for _, imageId in ipairs({ "video", "private", "missing", "bad/path" }) do
            assert(not f.L.Update(id, { background = "image", backgroundImageId = imageId }))
            assert(not f.P.Commit(f.map, { background = "image", backgroundImageId = imageId }))
        end
        assert(f.L.Update(id, { background = "image", backgroundImageId = "art" }))
        assert(f.L.Get(id).backgroundImageId == "art")
        assert(not f.L.Update(id, { backgroundImageId = "" }))
        assert(f.P.Commit(f.map, { background = "image", backgroundImageId = "art" }))
        f.Advance(0)
        assert(f.P.Format(f.M.GetLocation(f.map)).backgroundImageId == "art")
        assert(not f.P.Commit(f.map, { background = "image", backgroundImageId = false }))
        assert(not f.P.Commit(f.map, { backgroundImageId = false }))
    end)
    Check("all image controls are guarded for player owners", function(f)
        local id = f.Player()
        f.env.dmhub.isDM = true
        assert(f.L.Update(id, { background = "image", backgroundImageId = "art" }))
        f.env.dmhub.isDM = false
        for key, default in pairs(f.A.defaults) do
            if f.A.IsImageField(key) then
                assert(not f.L.Update(id, { [key] = default }))
                assert(not f.L.Stage(id, { [key] = default }))
            end
        end
        assert(not f.L.Update(id, { background = "none" }))
        assert(not f.L.Stage(id, { background = "plate" }))
        assert(f.L.Update(id, { text = "Allowed", outlineMode = "custom", outlineWidth = 0.2 }))
        assert(f.L.Get(id).backgroundImageId == "art")
        local ok, _, entry = f.L.Update(id, { text = "Undo this" }); assert(ok and f.M.Revert(entry))
    end)
    Check("player creation and remembered formats cannot import images", function(f)
        f.Player()
        assert(not f.L.Create(f.map, 0, 0, { text = "No", background = "image", backgroundImageId = "art" }))
        local id = f.L.NewDraft(f.map, 0.2, 0.2, { background = "image", backgroundImageId = "art", backgroundOpacity = 0.2, outlineMode = "custom" })
        f.L.Stage(id, { text = "New" }); f.L.Flush(id); f.Advance(0)
        assert(f.L.Get(id).background == "auto" and f.L.Get(id).backgroundImageId == "")
        assert(f.L.Get(id).outlineMode == "custom")
    end)
    Check("permission loss cancels unsent image changes and guarded Undo", function(f)
        local id = f.Player(); f.env.dmhub.isDM = true
        local ok, _, entry = f.L.Update(id, { background = "image", backgroundImageId = "art" }); assert(ok)
        f.L.Stage(id, { backgroundImageId = "second" })
        local writes = #f.writes
        f.env.dmhub.isDM = false
        assert(f.L.Snapshot(id).backgroundImageId == "art")
        f.Advance(2); assert(#f.writes == writes and not f.M.Revert(entry))
    end)
    Check("missing assets retain configuration and allow unrelated edits", function(f)
        local id = f.Create()
        assert(f.L.Update(id, { background = "image", backgroundImageId = "art", backgroundOpacity = 0.4 }))
        assert(f.P.Commit(f.map, { background = "image", backgroundImageId = "art" })); f.Advance(0)
        f.env.assets.imagesTable.art = nil
        assert(f.A.ReadableAsset("art") == nil)
        assert(f.L.Update(id, { text = "Still here" }))
        assert(f.L.Format(f.L.Get(id)).backgroundImageId == "art")
        assert(f.P.Commit(f.map, { bold = false })); f.Advance(0)
        assert(f.P.Format(f.M.GetLocation(f.map)).backgroundImageId == "art")
    end)
    Check("queued text rebases over a Director image replacement", function(f)
        local id = f.Player(); f.env.dmhub.isDM = true
        assert(f.L.Update(id, { background = "image", backgroundImageId = "art" }))
        f.env.dmhub.isDM = false; f.L.Stage(id, { text = "Edited" })
        f.env.dmhub.isDM = true; assert(f.L.Update(id, { backgroundImageId = "second" }))
        f.env.dmhub.isDM = false; f.L.Flush(id); f.Advance(0)
        assert(f.L.Get(id).text == "Edited" and f.L.Get(id).backgroundImageId == "second")
    end)
    Check("Fit contains, Fill centre crops, Stretch fills", function(f)
        local w, h, crop = f.A.Fit("fit", 100, 100, 400, 200)
        assert(w == 100 and h == 50 and crop == nil)
        w, h, crop = f.A.Fit("fill", 100, 100, 400, 200)
        assert(w == 100 and h == 100 and crop.x1 == 0.25 and crop.x2 == 0.75 and crop.y1 == 0)
        w, h, crop = f.A.Fit("stretch", 100, 100, 400, 200)
        assert(w == 100 and h == 100 and crop == nil)
    end)
    Check("remove image resets only image settings and restores the pin default", function(f)
        assert(f.P.Commit(f.map, { background = "image", backgroundImageId = "art", outlineMode = "custom", outlineWidth = 0.2 }))
        f.Advance(0)
        assert(f.P.Commit(f.map, f.A.RemoveImagePatch(true))); f.Advance(0)
        local format = f.P.Format(f.M.GetLocation(f.map))
        assert(format.background == "default" and format.backgroundImageId == "" and format.outlineWidth == 0.2)
        assert(f.env.assets.imagesTable.art ~= nil)
        local id = f.Create()
        assert(f.L.Update(id, { background = "image", backgroundImageId = "art", outlineWidth = 0.2 }))
        assert(f.L.Update(id, f.A.RemoveImagePatch(false)))
        assert(f.L.Get(id).background == "auto" and f.L.Get(id).backgroundImageId == "" and f.L.Get(id).outlineWidth == 0.2)
    end)
    Check("manual dimensions stay fixed and hit geometry excludes empty corridors", function(f)
        local format = f.A.Format({}, true)
        format.backgroundSizing, format.backgroundWidth, format.backgroundHeight, format.backgroundX = "manual", 30, 20, 100
        local a = f.A.Geometry(format, 80, 15, 15, 1)
        local b = f.A.Geometry(format, 160, 30, 30, 1)
        assert(a.image.x2 - a.image.x1 == 30 and b.image.x2 - b.image.x1 == 30)
        assert(a.text.x2 - a.text.x1 == 80 and b.text.x2 - b.text.x1 == 160)
        assert(not f.A.Contains(a.image, 60, 0) and not f.A.Contains(a.text, 60, 0))
        format.backgroundSizing, format.backgroundX = "auto", 0
        a = f.A.Geometry(format, 80, 15, 15, 1)
        assert(a.image.x2 - a.image.x1 == 95 and a.image.y2 - a.image.y1 == 22.5)
    end)
    Check("late image callbacks cannot replace a newer asset; timeout Retry recovers", function(f)
        MockPanels(f)
        local view = f.A.CreateImage(function() end)
        local format = f.A.Format({}, true)
        format.background, format.backgroundImageId = "image", "art"
        view.Bind(format)
        local old = view.leaf
        local replacement = f.env.DeepCopy(format); replacement.backgroundImageId = "second"
        view.Bind(replacement)
        old.bgimageWidth, old.bgimageHeight = 200, 100; old:FireEvent("imageLoaded")
        assert(view.status == "loading" and view.id == "second")
        f.Advance(10); assert(view.status == "unavailable")
        f.A.RetryImage("second")
        assert(view.status == "loading")
        local leaf = view.leaf
        leaf.bgimageWidth, leaf.bgimageHeight = 400, 200; leaf:FireEvent("imageLoaded")
        view.Layout({ x1 = -50, x2 = 50, y1 = -50, y2 = 50 })
        assert(view.status == "ready" and view.panel.selfStyle.width == 100 and view.panel.selfStyle.height == 50)
        view.panel:DestroySelf(); f.Advance(10)
    end)
    Check("image hover owns and clears its tooltip instead of leaking it onto the pin", function(f)
        local Panel = MockPanels(f)
        local owner = Panel { hover = function(element, target) (target or element).tooltip = {} end,
            press = function(element) element.data.pressed = true end }
        local name = f.P.CreateName(true, false, owner)
        local hit = name.data.appearance.hit
        hit:FireEvent("hover")
        assert(hit.tooltip ~= nil and owner.tooltip == nil)
        hit:FireEvent("dehover"); assert(hit.tooltip == nil)
        hit:FireEvent("hover"); hit:FireEvent("press"); assert(hit.tooltip == nil and owner.data.pressed)
        hit:FireEvent("hover"); hit:DestroySelf(); assert(hit.tooltip == nil)
        name.data.appearance.image.panel:DestroySelf()
    end)
    print("APPEARANCE CHECKS: " .. passed .. " passed")
    return passed
end
if ... == "run" then checks.Run() end
return checks
