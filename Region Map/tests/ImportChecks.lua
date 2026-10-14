-- Run through the live bridge after deploying the mod; see tests/README.md.
local checks = {}
local Import = RegionMapImport
local Copy = RegionMapCopy
local Records = RegionMapRecords
local limit = RegionMapConstants.importTextLimit

local function Equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

function checks.Parse()
    local count = 0
    local function Read(text, expectedError)
        local data, err = Import.ReadText(text)
        Equal(err, expectedError, "read error")
        if expectedError == nil then assert(data ~= nil, "parsed data missing") end
        count = count + 1
        return data
    end
    Read("", "empty")
    Read(" \r\n\t", "empty")
    Read("\239\187\191 \n", "empty")
    Read("[{\"name\":}]", "json")
    Read("[// comment\n{\"name\":\"A\"}]", "json")
    Read("\255", "json")
    local example = Read(Copy.T("import.example", nil, true), nil)
    Equal(#example.locations, 2, "example size")
    for index, raw in ipairs(example.locations) do
        local entry, reason = Import.CheckEntry(raw, index)
        assert(entry ~= nil and reason == nil, "example entry must be valid")
        Equal(entry.style.visibility, "hidden", "example privacy")
    end
    local url = Read('[{"name":"Link","description":"https://example.test/a//b"}]', nil)
    Equal(url[1].description, "https://example.test/a//b", "URL remains literal")
    local bom = Read("\239\187\191" .. '[{"name":"BOM"}]', nil)
    Equal(bom[1].name, "BOM", "BOM removed")
    for _, char in ipairs({ "x", utf8.char(0x416), utf8.char(0x1f30d) }) do
        local name = string.rep(char, RegionMapConstants.textLimit)
        local named = Import.CheckEntry({ name = name }, 1)
        assert(named ~= nil and named.name == name, "256-character name must import intact")
        assert(Records.ValidText(name), "model must accept the same name boundary")
        local rejected, reason = Import.CheckEntry({ name = name .. char }, 1)
        assert(rejected == nil and not Records.ValidText(name .. char), "257-character name must be rejected")
        assert(reason ~= nil and reason:find("256", 1, true), "name error must give the current limit")
        local prefix, suffix = '[{"name":"Boundary","_padding":"', '"}]'
        local exact = prefix .. string.rep(char, limit - #prefix - #suffix) .. suffix
        Equal(Records.TextLength(exact), limit, "Unicode boundary")
        Read(exact, nil)
        Read(exact .. " ", "tooLong")
    end
    local _, missing = Import.CheckEntry({}, 1)
    assert(missing ~= nil, "missing name must be skipped")
    local _, coordinates = Import.CheckEntry({ name = "Invalid", u = 0.5 }, 2)
    assert(coordinates ~= nil, "one coordinate must be skipped")
    local entry = Import.CheckEntry({ name = "Hidden", ignored = "extra" }, 3)
    assert(entry ~= nil, "valid entry")
    Equal(entry.style.visibility, "hidden", "default visibility")
    print("IMPORT CHECKS: parsing passed (" .. count .. " inputs, ASCII/Cyrillic/emoji boundaries)")
end

local function Panel(id)
    return assert(gui.GetSheetById(id), "missing panel: " .. id)
end

local function Click(id) Panel(id):FireEvent("click") end

function checks.Editor()
    local card = Panel("region-map-import")
    if card.data.mode == "closed" then card.data.start() end
    local editor = Panel("region-map-import-text") --[[@as TextEditor]]
    assert(editor.text == "", "editor checks need an empty draft")
    local mapId = card.data.mapId
    local before = #RegionMapModel.Children(mapId)
    Equal(editor.characterLimit, 4 * (limit + 1), "native encoding headroom")
    print("IMPORT CHECKS: fill example")
    Click("region-map-import-example")
    local example = editor.text
    assert(example ~= "", "example should fill an empty editor")
    Click("region-map-import-preview")
    Equal(card.data.mode, "preview", "preview opens")
    Equal(#card.data.pending.plan.entries, 2, "preview count")
    print("IMPORT CHECKS: preview and Back")
    Click("region-map-import-back")
    Equal(editor.text, example, "Back preserves source")
    editor.text = '{"locations":[{"name":"Keep this draft"}]}'
    editor:FireEvent("edit")
    local draft = editor.text
    Click("region-map-import-example")
    assert(not Panel("region-map-confirm"):HasClass("collapsed"), "replace needs confirmation")
    Click("region-map-confirm-cancel")
    Equal(editor.text, draft, "cancel replacement preserves source")
    Click("region-map-import-cancel")
    assert(not Panel("region-map-confirm"):HasClass("collapsed"), "close needs confirmation")
    Click("region-map-confirm-cancel")
    Equal(card.data.mode, "edit", "cancel discard keeps editor")
    print("IMPORT CHECKS: replacement and discard cancel")
    editor.text = "[{"
    editor:FireEvent("edit")
    Click("region-map-import-preview")
    Equal(card.data.mode, "edit", "bad JSON stays editable")
    Equal(editor.text, "[{", "bad JSON remains intact")
    assert(not Panel("region-map-import-error"):HasClass("collapsed"), "bad JSON needs visible feedback")
    print("IMPORT CHECKS: malformed text recovery")
    editor.text = draft
    editor:FireEvent("edit")
    Click("region-map-import-cancel")
    Click("region-map-confirm-ok")
    Equal(card.data.mode, "closed", "confirmed discard closes")
    Equal(editor.text, "", "confirmed discard clears source")
    Equal(#RegionMapModel.Children(mapId), before, "preview and cancel write nothing")
    print("IMPORT CHECKS: editor, confirmations and recovery passed; no Locations written")
end

function checks.Oversized(char)
    local card = Panel("region-map-import")
    if card.data.mode == "closed" then card.data.start() end
    local editor = Panel("region-map-import-text") --[[@as TextEditor]]
    assert(editor.text == "", "oversize check needs an empty draft")
    print("IMPORT CHECKS: assign oversized editor text")
    editor.text = string.rep(char or "x", limit + 1)
    print("IMPORT CHECKS: oversized text assigned")
    editor:FireEvent("edit")
    assert(Panel("region-map-import-preview"):HasClass("disabled"), "oversized text disables Preview")
    Click("region-map-import-preview")
    Equal(card.data.mode, "edit", "oversized text cannot open preview")
    Equal(card.data.pending, nil, "oversized text cannot create an import plan")
    -- Clear the fixture without diffing unrelated 100k-character undo-history baselines.
    editor.textNoNotify = ""
    editor:FireEvent("edit")
    card.data.close()
    print("IMPORT CHECKS: oversized editor text rejected before preview")
end

function checks.ReplaceLargeDraft()
    local card = Panel("region-map-import")
    if card.data.mode == "closed" then card.data.start() end
    local editor = Panel("region-map-import-text") --[[@as TextEditor]]
    assert(editor.text == "", "replacement check needs an empty draft")
    editor.textNoNotify = string.rep("x", limit)
    editor:FireEvent("edit")
    Click("region-map-import-example")
    Equal(#editor.text, limit, "replacement awaits confirmation")
    Click("region-map-confirm-ok")
    Equal(editor.text, Copy.T("import.example", nil, true), "large draft replaced by example")
    editor.textNoNotify = ""
    editor:FireEvent("edit")
    card.data.close()
    print("IMPORT CHECKS: confirmed replacement of a 100k draft passed")
end

return checks
