-- Run from the repository root with Lua 5.4; any failed assertion fails the process.
for _, name in ipairs({ "LabelChecks", "TextAppearanceChecks", "PinTextChecks", "ArtworkChecks",
    "CanvasToolsChecks", "WindowHostChecks", "ImportOfflineChecks" }) do
    assert(dofile("Region Map/tests/" .. name .. ".lua").Run(), name .. " failed")
end
print("OVERLAND MAP: all seven offline suites passed")
