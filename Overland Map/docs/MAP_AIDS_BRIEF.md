# Map aids: approved design and implementation contract

Combines ideas 20, 16 and 17. The Director authors each map's aids; every viewer
controls their own visibility. Existing and new maps start with neither aid.

The rewrite separates this contract into `OverlandMapAids` (domain and saves),
`OverlandMapAidLayer` (rendering/hits), `OverlandMapAidEditor` (controls), and the
shared geometry/gesture services. Fresh storage and current verification are recorded
in [REWRITE_PLAN.md](REWRITE_PLAN.md).

## Controls

Settings is available to everyone. Players and View as player receive only **Only
for you**, with Show names, Show labels, Show compass, Show scale bar, Show hover
text and Reduce motion. The three new preferences default on and apply across
maps in the current game. Director sections are constructed separately and all
writes recheck permissions.

The **Map aids** compass button in the top toolbar opens a dedicated Director panel to add,
edit or remove one compass and one scale bar. Each has Place on map, Find on map,
and numeric X/Y percentages. A single click places; Enter places at the visible
map centre; Escape cancels without saving a new position. Find moves the camera.

Unlock positions to click-drag an aid directly on the map; this selects it without
opening its editor. Use the toolbar for appearance settings. A selected compass has resize and rotation handles with equivalent
numeric fields. Scale-bar length changes through Distance. A selected aid is
temporarily shown even with its personal visibility switch off. Ordinary drawing
passes input through to pins, paths and labels. Anchors stay in the image; visual
extents may cross its edges. Rotation and resizing do not move anchors.
After selection or a completed drag, the camera reveals controls hidden by the canvas
edge or window chrome without changing saved positions. It stays still during a drag.
Escape clears a map-only selection. The editor includes an Unlock positions button.

Navigation, tool changes, permission changes and closing the editor cancel unfinished
gestures and clear handles. Placement temporarily closes Map aids, then returns
to the editor when the position is confirmed.

## Rendering

Both aids belong to the artwork and follow its pan, zoom and resizing. Application
Font Size affects controls and handles, without changing map-relative proportions.

The compass starts with the uploaded `compass-icon`, width 6% of map width and
clockwise rotation 0 degrees. A custom still image preserves its aspect ratio.
The image rectangle's original top edge defines north, regardless of its drawn
arrow. The optional label defaults to N. Its anchor follows the rotated top centre;
the text stays upright, outside the image, with clearance derived from measured
text bounds. Text size, font, emphasis, alignment, spacing, colour and outline are
independent of the scale bar's text.

The scale bar requires nondegenerate map calibration. Its length uses image-pixel
calibration, including the image's aspect ratio. Its initial distance is the largest
1, 2 or 5 times a power of ten that fits within 20% of map width. Four equal segments
alternate black/white. Labels show 0, midpoint and total with the map's units.
There is no travel-time estimate or separate unit setting/conversion. Recalibration
changes width while retaining distance; zoom changes display size only.

Text starts at 1.5% of map width; bar thickness follows text size. Measured endpoints
never change with typography or decoration. Colliding labels use additional rows;
ticks stay at their marks and break around intervening text bounds.

Both aids default to **None** for their background. Explicit saved backgrounds remain
unchanged. They reuse Auto contrast, Plate, None and Image backgrounds, plus existing
image fitting, padding, manual dimensions, offsets and opacity. Decoration cannot
change compass orientation, calibration or bar endpoints.

## Data and recovery

Map records carry optional `mapAids.compass` and `mapAids.scaleBar` objects without a
schema change. Known leaf patches preserve unknown nested fields. Malformed optional
aid fields cannot invalidate a map. Validation and authorization remain in Records
and Model. The registered runtime component `RegionMapAids.lua` loads after canvas
geometry helpers and before the canvas.

Each confirmed numeric change or released gesture uses the shared row writer and
save queue with Retry and one guarded Undo. Gestures preview locally; numeric fields
commit on confirmation or field exit. Navigation flushes typed edits; Undo and lost
permissions cancel unsent work. Map deletion/removal includes aids in its existing
Undo. Image replacement retains aids and reminds the Director to review them.

Missing compass artwork hides the compass and offers Retry without losing the
reference. Missing decorative images fall back to automatic contrast. Missing or
degenerate calibration hides the scale bar and explains the prerequisite in Map aids.
A bar longer than the map width retains its distance but is hidden with a sizing
message. Non-finite geometry is never drawn. Image callbacks are scoped to the map,
asset and component lifetime. Pans translate existing layers without rebuilding aids
or refreshing the window.

Hover text off suppresses pin popups, hover-only path names, breadcrumb previews and
Atlas-card popups, immediately dismissing tracked popups. Button help, Party hints,
hit testing, highlighting, selection and Show names remain active.

## Approved explanatory copy

- "Only affects your view, across all maps in this game."
- "North follows the image's original top edge. The label stays upright."
- "Set the map scale to add a scale bar."
- "Check compass alignment and map scale after replacing the image."

Runtime wording lives under `aids.*` in RegionMapCopy; formatting, validation, save
and Retry controls reuse the existing copy vocabulary.

## Verification contract

Run the seven existing offline suites plus MapAidsChecks, ASCII/syntax checks and
full LuaLS. Test rectangular calibration, zoom, unit changes, recalibration, tiny and
oversized distances, malformed optional data, all cardinal/intermediate compass
rotations, non-square artwork, long labels, collisions and fixed measurement endpoints.
Cover preference isolation, player/View-as-player writes, tooltip dismissal, keyboard
placement, Escape, locked dragging, pending saves, Retry and Undo.

Inspect fullscreen, window and popout; minimum size; Font Size 80-140%; contrasting
themes; bright/dark and dense maps. Simulate concurrent changes offline. Two-client
live tests remain explicitly skipped. Actual results and limitations belong in
[the verification record](../tests/MAP_AIDS.md).
