-- Offline host checks: production bootstrap, preferences, buttons and core resize helper.
-- The GUI, game connection and map content are isolated in memory; no live app is used.
local checks = {}
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local directory = source:match("^(.*)/tests/[^/]+$") or "Region Map"
local repository = directory:match("^(.*)/[^/]+$") or "."

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Copy(item) end
    return result
end

local function Near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001, string.format("expected %s, got %s", expected, actual))
end

local function Fixture()
    --- @type table<string, any>
    local f = { settings = { hideactionbar = false }, keys = {}, scale = 1, rail = true, builds = 0, raises = 0 }
    local env = setmetatable({}, { __index = _G }) --[[@as table<string, any>]]
    env._G = env
    local mod = { unloaded = false }
    f.mod = mod
    env.print = function() end
    env.RegisterGameType = function() return {} end
    env.DeepCopy = Copy
    env.dmhub = {
        GetModLoading = function() return mod end,
        GetSettingValue = function(key) return f.settings[key] end,
        SetSettingValue = function(key, value) f.settings[key] = Copy(value) end,
        KeyPressed = function(key) return f.keys[key] == true end,
        -- Each call is a second later, so every think also runs the idle-rate refit.
        Time = function() f.clock = (f.clock or 0) + 1; return f.clock end,
        cursorIds = {}, screenDimensionsBelowTitlebar = { x = 1600, y = 1000 },
    }
    env.RailModeActive = function() return f.rail end
    env.RegionMapModel = {
        Clamp = function(value, lo, hi) return math.max(lo, math.min(hi, value)) end,
        IsFinite = function(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end,
    }
    local methods = {}
    local function IsEnabled(panel)
        return panel.valid and not panel.classSet.collapsed and not panel.classSet.hidden
            and (panel.parent == nil or IsEnabled(panel.parent))
    end
    local function RemoveChild(parent, child)
        for i, item in ipairs(parent.children) do
            if item == child then table.remove(parent.children, i); return end
        end
    end
    function methods:SetClass(name, on) self.classSet[name] = on end
    function methods:HasClass(name) return self.classSet[name] == true end
    function methods:AddChild(child) self.children[#self.children + 1] = child; child.parent = self end
    function methods:SetAsLastSibling()
        if self.parent then RemoveChild(self.parent, self); table.insert(self.parent.children, self) end
    end
    function methods:SetAsFirstSibling()
        if self.parent then RemoveChild(self.parent, self); table.insert(self.parent.children, 1, self) end
    end
    function methods:FireEvent(name, ...)
        if self.events[name] then return self.events[name](self, ...) end
    end
    function methods:FireEventTree(name, ...)
        self:FireEvent(name, ...)
        for _, child in ipairs(self.children) do child:FireEventTree(name, ...) end
    end
    function methods:FireEventOnParents(name, ...)
        local parent = self.parent
        while parent do parent:FireEvent(name, ...); parent = parent.parent end
    end
    function methods:ScheduleEvent() end
    function methods:GetMouseButton(button) return f.keys[button] == true end
    function methods:transferDragTo(target) f.dragTarget = target end
    function methods:IsDescendantOf(other)
        local parent = self.parent
        while parent do if parent == other then return true end; parent = parent.parent end
        return false
    end
    function methods:RaiseNativeWindow() f.raises = f.raises + 1 end
    function methods:DestroySelf()
        self:FireEvent("destroy")
        while #self.children > 0 do self.children[#self.children]:DestroySelf() end
        self.valid = false
        if self.parent then RemoveChild(self.parent, self) end
    end
    function methods:Get(id)
        if self.id == id then return self end
        for _, child in ipairs(self.children) do
            local found = child:Get(id)
            if found then return found end
        end
    end
    function methods:GetChildrenWithClassRecursive(name)
        local found = {}
        local function Visit(panel)
            for _, child in ipairs(panel.children) do
                if child.classSet[name] then found[#found + 1] = child end
                Visit(child)
            end
        end
        Visit(self)
        return found
    end
    local mt = { __index = function(panel, key)
        if methods[key] then return methods[key] end
        if key == "enabled" then return IsEnabled(panel) end
        if key == "hasFocus" then return f.focus == panel end
        if key == "siblingIndex" then
            for i, child in ipairs(panel.parent and panel.parent.children or {}) do if child == panel then return i end end
            return 1
        end
        if key == "renderedWidth" then return panel.selfStyle.width or panel.width or 0 end
        if key == "renderedHeight" then return panel.selfStyle.height or panel.height or 0 end
    end }
    local function Panel(args)
        local p = setmetatable({ valid = true, selfStyle = {}, data = args.data or {}, classSet = {},
            events = {}, children = {}, x = 0, y = 0, xdrag = 0, ydrag = 0 }, mt)
        for key, value in pairs(args) do
            if type(value) == "function" then p.events[key] = value
            elseif type(key) ~= "number" and key ~= "children" then p[key] = value end
        end
        for _, class in ipairs(args.classes or {}) do p.classSet[class] = true end
        for _, child in ipairs(args.children or args) do p:AddChild(child) end
        return p
    end
    f.Panel = Panel
    env.gui = {
        Panel = Panel, Label = Panel,
        Button = function(args)
            args[1] = Panel { classes = { "buttonIcon" }, bgimage = args.icon }
            return Panel(args)
        end,
        IconEditor = function() end, SearchInput = function() end, ExpandoArrow = function() end,
        Tooltip = function() return function() end end,
        ContextMenu = Panel,
        GetFocus = function() if f.focus and f.focus.valid then return f.focus end end,
        SetFocus = function(panel)
            if f.focus then f.focus:SetClass("focus", false); f.focus:FireEvent("defocus") end
            f.focus = panel
            if panel then panel:SetClass("focus", true); panel:FireEvent("focus") end
        end,
    }
    f.layer = Panel { width = 1600, height = 1000 }
    local bar = Panel { height = 100 }
    env.GameHud = {
        instance = { documentsPanel = f.layer, try_get = function(_, key) if key == "actionBarPanel" then return bar end end },
        GetPresentDialogDocRaw = function() end,
        RegisterPresentableDialog = function(args) f.presentation = args end,
    }
    env.ThemeEngine = { MergeStyles = function(value) return value end }
    env.RegionMapStyles = { Build = function() return {} end, Subscribe = function() end, Unsubscribe = function() end }
    env.DockablePanel = {
        Register = function(args) f.registration = args end,
        Deregister = function() end, LaunchPanelByName = function() end,
    }
    env.PanelDocument = {
        WindowUIScale = function() return f.scale end,
        PopoutHost = function() if f.popout and f.popout.valid then return f.popout end end,
        PopoutForgetWindow = function() f.forgotPopout = true end,
        OpenPopout = function()
            f.popout = Panel { f.registration.content() }
        end,
    }
    local function Load(name) assert(loadfile(directory .. "/" .. name .. ".lua", "t", env))() end
    Load("RegionMapConstants")
    Load("RegionMapCopy")
    Load("RegionMapSession")
    f.C, f.S = env.RegionMapConstants, env.RegionMapSession
    assert(loadfile(repository .. "/DMHub Core UI/DialogResize.lua", "t", env))()
    env.RegionMapPanel = { Create = function(options)
        f.builds = f.builds + 1
        local canvas = Panel { id = "region-map-canvas", canFocus = true }
        local button = f.S.IconButton("fixture-view", f.C.iconWindow, "view", function() options.toggleView() end,
            { "regionMapHostControl" })
        button:SetClass("collapsed", options.toggleView == nil)
        return Panel {
            id = "region-map-panel", canvas, button,
            data = { options = options, mapId = "atlas", camera = { zoom = 3 }, draft = "unsaved JSON",
                logDraft = "unsaved note", pathDraft = { { u = 0.2, v = 0.3 } }, selectedId = "place" },
            requestClose = function(_, proceed)
                f.closeRequests = (f.closeRequests or 0) + 1
                if f.blockClose then f.pendingClose = proceed else proceed() end
            end,
            regionMapHostMode = function(panel, mode) panel.data.mode = mode end,
            regionMapHostActive = function(panel, active) panel.data.active = active end,
        }
    end }
    Load("RegionMap")
    f.env = env
    function f.Open() f.registration.launch(); return f.layer:Get("region-map-fullscreen") end
    function f.Window()
        local h = f.Open()
        h.data.content.data.options.toggleView()
        return h
    end
    function f.DragTo(h, x, y)
        f.keys[0] = true
        f.layer.mousePoint = { x = (h.x + 100) / f.layer.width, y = 1 - (h.y + 20) / f.layer.height }
        h.data.title:FireEvent("press")
        assert(h.data.titleDrag ~= nil)
        -- The engine's transferred-drag coordinates can jump; they are not our input.
        h.xdrag, h.ydrag = -4000, -8000
        f.layer.mousePoint = { x = (x + 100) / f.layer.width, y = 1 - (y + 20) / f.layer.height }
        h:FireEvent("think")
        f.keys[0] = false
        h:FireEvent("think")
    end
    return f
end

local cases = {
    { "same content and drafts survive repeated view changes", function()
        local f = Fixture()
        local h = f.Open()
        assert(h.data.mode == "fullscreen" and f.settings.hideactionbar)
        local content, state = h.data.content, h.data.content.data
        for _ = 1, 4 do content.data.options.toggleView() end
        assert(h.data.content == content and content.data == state and f.builds == 1)
        assert(state.mapId == "atlas" and state.draft == "unsaved JSON" and state.logDraft == "unsaved note")
        assert(state.selectedId == "place" and #state.pathDraft == 1 and state.camera.zoom == 3)
    end },
    { "window bounds replace the fullscreen input surface", function()
        local f = Fixture()
        local h = f.Window()
        assert(h.data.mode == "window" and not f.settings.hideactionbar and #f.layer.children == 1)
        Near(h.selfStyle.width, 900); Near(h.selfStyle.height, 600)
        assert(h.x > 0 and h.y > 0 and h.x + h.selfStyle.width < 1600)
        assert(not h.data.title:HasClass("collapsed") and h.data.frame.selfStyle.lmargin == 0)
        assert(h.data.zoom.selfStyle.height == 600 - f.C.panelTitleHeight)
        assert(h:FireEvent("wheel") == true and h.data.title:FireEvent("wheel") == true)
    end },
    { "close guard and remembered mode/placement", function()
        local f = Fixture()
        local h = f.Window()
        f.DragTo(h, 150, 120)
        f.blockClose = true
        h:Get("region-map-window-close"):FireEvent("click")
        assert(h.valid and f.pendingClose and f.closeRequests == 1)
        f.pendingClose()
        assert(not h.valid)
        f.blockClose = false
        h = f.Open()
        assert(h.data.mode == "window")
        Near(h.x, 150); Near(h.y, 120)
    end },
    { "title drag uses stable layer coordinates and clamps offscreen placement", function()
        local f = Fixture()
        local h = f.Window()
        assert(not h.draggable)
        f.DragTo(h, 10000, -10000)
        assert(f.dragTarget == nil)
        assert(not h.draggable and not h.data.dragging)
        Near(h.x + h.selfStyle.width, h.data.area.right); Near(h.y, h.data.area.upper)
        Near(f.S.ReadWindowGeometry().x, h.x)
    end },
    { "real resize helper integrates with switching and persistence", function()
        local f = Fixture()
        local h = f.Window()
        local right = h.data.resizer.children[4]
        right:FireEvent("beginDrag")
        right.xdrag = right.data.homeX + 120
        right:FireEvent("dragging")
        right:FireEvent("drag")
        Near(h.selfStyle.width, 1020)
        Near(right.data.homeX, 1017)
        Near(f.S.ReadWindowGeometry().width, 1020)
        h.data.content.data.options.toggleView()
        h.data.content.data.options.toggleView()
        Near(h.selfStyle.width, 1020); Near(right.data.homeX, 1017)
        assert(h.children[#h.children] == h.data.resizer)
    end },
    { "tiny viewport fallback preserves the desired window", function()
        local f = Fixture()
        local h = f.Window()
        f.DragTo(h, 100, 100)
        local geometry = f.S.ReadWindowGeometry()
        f.layer.width, f.layer.height = 600, 400
        h:FireEvent("monitor")
        assert(h.data.mode == "fullscreen" and f.S.InAppView() == "window")
        f.layer.width, f.layer.height = 1600, 1000
        h:FireEvent("monitor")
        assert(h.data.mode == "window" and f.builds == 1)
        Near(h.x, geometry.x); Near(h.selfStyle.width, geometry.width)
    end },
    { "scaling uses one coordinate space in both UI modes", function()
        for _, rail in ipairs({ true, false }) do
            for _, scale in ipairs({ 0.8, 1, 1.4 }) do
                local f = Fixture()
                f.rail, f.scale = rail, scale
                f.layer.width, f.layer.height = 2200, 1600
                local h = f.Window()
                Near(h.selfStyle.width, 900 * scale)
                Near(h.data.zoom.selfStyle.width, 900)
                Near(h.data.title.selfStyle.width, 900)
                Near(h.data.resizeOptions.minWidth, 720 * scale)
                f.DragTo(h, 200 * scale, 150 * scale)
                Near(f.S.ReadWindowGeometry().x, 200)
                Near(f.S.ReadWindowGeometry().width, 900)
            end
        end
    end },
    { "presentation respects the current host and native return preference", function()
        local f = Fixture()
        local h = f.Window()
        f.presentation.create()
        assert(f.builds == 1 and h.data.mode == "window")
        h.data.content.data.options.popOut()
        assert(not h.valid and f.popout.valid and #f.layer.children == 0)
        f.registration.launch()
        assert(f.raises == 1 and f.builds == 2)
        f.popout.children[1].data.options.popIn()
        h = f.layer:Get("region-map-fullscreen")
        assert(h and h.data.mode == "window" and f.forgotPopout and not f.popout.valid)
        f.registration.launch()
        assert(not h.valid)
        f.presentation.create()
        assert(f.layer:Get("region-map-fullscreen").data.mode == "window")
    end },
    { "covered window is raised before a second activation closes it", function()
        local f = Fixture()
        local h = f.Window()
        local other = f.Panel {}
        f.layer:AddChild(other)
        h:FireEvent("think")
        assert(h.data.content.data.active == false)
        f.registration.launch()
        assert(h.valid and h.siblingIndex == #f.layer.children and f.builds == 1)
        h:FireEvent("think")
        assert(h.data.content.data.active == true)
        f.registration.launch()
        assert(not h.valid and other.valid)
    end },
    { "native keyboard controls and reset recovery", function()
        local f = Fixture()
        local h = f.Window()
        local menu = h:Get("region-map-window-options")
        f.env.gui.SetFocus(menu)
        assert(menu:HasClass("focus"))
        assert(menu.canFocus and menu.events.enter == nil and menu.events.think == nil)
        menu:FireEvent("click")
        assert(menu.popup and #menu.popup.entries == 1)
        f.DragTo(h, 400, 200)
        assert(menu.popup == nil)
        menu:FireEvent("click")
        menu.popup.entries[1].click()
        Near(h.selfStyle.width, 900)
        Near(h.x, (h.data.area.left + h.data.area.right - 900) / 2)
        f.S.FocusHostControl(h, menu, 1)
        assert(f.focus.id == "region-map-window-close")
        f.S.FocusHostControl(h, f.focus, 1)
        assert(f.focus.id == "region-map-canvas")
        f.S.FocusHostControl(h, f.focus, 1)
        assert(f.focus.id == "fixture-view")
        assert(f.focus.canFocus and f.focus.events.enter == nil and f.focus.events.think == nil)
        f.focus:FireEvent("click")
        assert(h.data.mode == "fullscreen" and f.builds == 1)
    end },
    { "invalid preferences and existing action-bar preference are safe", function()
        local f = Fixture()
        f.settings[f.C.preferencesSettingId] = { inAppView = "bad", windowGeometry = { width = math.huge, height = 20 } }
        assert(f.S.InAppView() == "fullscreen" and f.S.ReadWindowGeometry() == nil)
        f.settings.hideactionbar = true
        local h = f.Window()
        assert(f.settings.hideactionbar)
        h:Get("region-map-window-close"):FireEvent("click")
        assert(f.settings.hideactionbar)
    end },
    { "mode changes preserve editor focus and recover hidden host controls", function()
        local f = Fixture()
        local h = f.Window()
        local editor = f.Panel { id = "fixture-editor", canFocus = true }
        h.data.content:AddChild(editor)
        f.env.gui.SetFocus(editor)
        h.data.content.data.options.toggleView()
        h:FireEvent("regionMapCheckFocus")
        assert(f.focus == editor)
        h.data.content.data.options.toggleView()
        f.env.gui.SetFocus(h:Get("region-map-window-options"))
        h.data.content.data.options.toggleView()
        h:FireEvent("regionMapCheckFocus")
        assert(f.focus.enabled and f.focus.id == "fixture-view")
    end },
    { "Esc belongs to the window only with focus or pointer inside", function()
        local f = Fixture()
        local h = f.Window()
        f.env.gui.SetFocus(nil)
        h.data.hovered = false
        h:FireEvent("think")
        assert(h.data.content.data.active == false)
        h.data.hovered = true
        h:FireEvent("think")
        assert(h.data.content.data.active == true)
        h.data.hovered = false
        f.env.gui.SetFocus(h.data.content)
        h:FireEvent("think")
        assert(h.data.content.data.active == true)
        local other = f.Panel {}
        f.layer:AddChild(other)
        h:FireEvent("think")
        assert(h.data.content.data.active == false)
    end },
    { "leaving the document layer during title drag keeps the last position", function()
        local f = Fixture()
        local h = f.Window()
        f.keys[0] = true
        f.layer.mousePoint = { x = (h.x + 100) / f.layer.width, y = 1 - (h.y + 20) / f.layer.height }
        h.data.title:FireEvent("press")
        local x, y = h.x, h.y
        f.layer.mousePoint = { x = 0, y = 0 }
        h:FireEvent("think")
        Near(h.x, x); Near(h.y, y)
        f.keys[0] = false
        h:FireEvent("think")
    end },
    { "reload cleanup restores the action bar", function()
        local f = Fixture()
        local h = f.Open()
        f.mod.unloaded = true
        h:FireEvent("think")
        assert(not h.valid and not f.settings.hideactionbar)
    end },
}

function checks.Run()
    local failed = 0
    for _, case in ipairs(cases) do
        local ok, err = pcall(case[2])
        print((ok and "PASS " or "FAIL ") .. case[1] .. (ok and "" or ": " .. tostring(err)))
        if not ok then failed = failed + 1 end
    end
    print(string.format("Window host: %d/%d passed", #cases - failed, #cases))
    return failed == 0
end

return checks
