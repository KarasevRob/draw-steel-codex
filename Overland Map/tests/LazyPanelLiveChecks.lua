-- Run with LazyPanelBenchmark.CreateView's isolated records and the real engine GUI.
local checks = {}
local function Find(root, predicate)
    if predicate(root) then return root end
    for _, child in ipairs(root.children) do local result = Find(child, predicate); if result then return result end end
end
local function ById(root, id)
    return assert(Find(root, function(panel) return panel.id == id end))
end

function checks.Start(f, parent)
    local result = { done = false, passed = {}, progress = "starting" }
    local steps, index = {}, 0
    local state = {}
    local function Add(name, action) steps[#steps + 1] = { name, action } end
    Add("current Location binds and all three save lanes start once", function()
        f.ctx.Select(f.pin, "edit")
        local panel = f.editorPanels.SidePanel
        state.location = panel
        local function Input(class, text)
            return assert(Find(panel, function(p) return p:HasClass(class) and p.placeholderText == text end))
        end
        local copy = f.env.OverlandMapCopy.T
        local name = Input("overlandMapInput", copy("edit.name.placeholder"))
        local desc = Input("overlandMapTextArea", copy("edit.desc.placeholder"))
        local note = Input("overlandMapTextArea", copy("edit.notes.placeholder"))
        f.mode = "pending"
        name.text = "Accepted name"; name:FireEvent("edit")
        desc.textNoNotify = "Accepted description"; desc:FireEvent("edit")
        note.textNoNotify = "Accepted note"; note:FireEvent("edit")
        state.before = #f.writes
        f.ctx.FlushEdits()
        assert(#f.writes == state.before + 3)
        state.oldContext = f.ctx
        f.panel:DestroySelf()
        f.panel = f.env.OverlandMapPanel.Create { mode = "window" }
        parent:AddChild(f.panel)
    end)
    Add("accepted saves finish after teardown without reopening replacement editors", function()
        assert(not state.oldContext.IsAlive() and f.ctx.IsAlive())
        assert(f.ctx.data.panelMode == "none" and not state.location.valid)
        for i = state.before + 1, #f.writes do f.writes[i].callbacks.success() end
        f.mode = nil
    end)
    Add("all Location lanes retain their original target", function()
        assert(f.M.GetLocation(f.pin).name == "Accepted name")
        assert(f.M.Details(f.pin).description == "Accepted description")
        assert(f.M.DirectorNote(f.pin) == "Accepted note")
        assert(f.factoryCalls.SidePanel == 1 and f.ctx.data.panelMode == "none")
        f.ctx.Select(f.pin, "read"); state.location = f.editorPanels.SidePanel
        f.ctx.Select(nil); f.ctx.Select(f.pin, "read")
        assert(f.editorPanels.SidePanel == state.location and f.factoryCalls.SidePanel == 2)
    end)
    Add("Log close commits the note through the production closing bind", function()
        local log = f.env.OverlandMapLog
        assert(log.Record(nil, { mapId = f.map, u = 0.3, v = 0.4 }, true))
        state.logId = assert(log.Entries()[1]).id
        f.ctx.ToggleLog()
        local panel = f.editorPanels.LogPanel
        local add = assert(Find(panel, function(p)
            return p:HasClass("overlandMapButton") and p.text == f.env.OverlandMapCopy.T("log.addNote")
        end))
        add:FireEvent("click")
        local input = assert(Find(panel, function(p) return p:HasClass("overlandMapTextArea") end))
        input.textNoNotify = "Saved when the log closes"; input:FireEvent("edit")
        assert(panel.data.editing)
        f.ctx.data.panelMode = "none"; f.ctx.Refresh("selection")
        assert(not panel.data.editing and panel:HasClass("collapsed"))
    end)
    Add("Log note survives closing and reopening", function()
        assert(f.env.OverlandMapLog.Get(state.logId).note == "Saved when the log closes")
        f.ctx.ToggleLog(); f.ctx.ToggleLog(); assert(f.factoryCalls.LogPanel == 1)
    end)
    Add("Import cancel retains draft and blocks host teardown", function()
        f.ctx.ImportLocations(); state.import = f.editorPanels.Import
        local input = ById(f.panel, "overland-map-import-text")
        input.textNoNotify = "draft"; input:FireEvent("edit")
        state.hostClosed = false
        f.panel:FireEvent("requestClose", function() state.hostClosed = true end)
        assert(not state.hostClosed and not ById(f.panel, "overland-map-confirm"):HasClass("collapsed"))
        ById(f.panel, "overland-map-confirm-cancel"):FireEvent("click")
        assert(not state.hostClosed and input.text == "draft")
        local target = state.import.data.mapId
        f.ctx.GoAtlas(); assert(state.import.data.mapId == target)
        f.panel:FireEvent("requestClose", function() state.hostClosed = true end)
        ById(f.panel, "overland-map-confirm-ok"):FireEvent("click")
        assert(state.hostClosed)
        f.ctx.OpenMap(f.map); f.ctx.ImportLocations(); assert(f.editorPanels.Import == state.import)
        state.import.data.close()
    end)
    Add("blank label drafts and Escape keep retained identity", function()
        f.ctx.CreateLabel(0.2, 0.3); local id = f.ctx.data.selectedLabelId
        local panel = f.editorPanels.LabelPanel
        f.panel:FireEvent("escape")
        assert(f.L.Snapshot(id) == nil and f.ctx.data.panelMode == "none")
        f.ctx.SelectLabel(f.label, true); assert(f.editorPanels.LabelPanel == panel)
        f.env.dmhub.isDM = false; f.ctx.Refresh("permissions")
        assert(f.ctx.data.panelMode == "none" and panel:HasClass("collapsed"))
        f.env.dmhub.isDM = true
    end)
    Add("host changes keep slots and existing components", function()
        f.ctx.SelectPath(f.path, "pathEdit"); local panel = f.editorPanels.PathPanel
        local slot = panel.parent
        f.panel:FireEvent("overlandMapHostMode", "fullscreen")
        f.panel:FireEvent("overlandMapHostMode", "window")
        assert(panel.valid and panel.parent == slot and f.editorPanels.PathPanel == panel)
        f.panel:FireEvent("escape"); assert(f.ctx.data.panelMode == "path")
        f.panel:FireEvent("escape"); assert(f.ctx.data.panelMode == "none")
    end)
    local function Next()
        index = index + 1
        local step = steps[index]
        if step == nil then result.done, result.progress = true, "complete"; return end
        result.progress = step[1]
        local ok, message = xpcall(step[2], debug.traceback)
        if not ok then result.done, result.error = true, tostring(message); return end
        result.passed[#result.passed + 1] = step[1]
        dmhub.Schedule(0.3, Next)
    end
    Next()
    return result
end

return checks
