-- Run from the repository root with Lua 5.4; any failed assertion fails the process.
for _, name in ipairs({ "LabelChecks", "TextAppearanceChecks", "PinTextChecks", "ArtworkChecks",
    "CanvasToolsChecks", "WindowHostChecks", "TabletopIntegrationChecks", "TabletopContentChecks",
    "ImportOfflineChecks", "MapAidsChecks", "LifetimeChecks", "LazyPanelChecks", "JournalChecks", "AuthoringFlowChecks" }) do
    assert(dofile("Overland Map/tests/" .. name .. ".lua").Run(), name .. " failed")
end
print("OVERLAND MAP: all offline suites passed")
