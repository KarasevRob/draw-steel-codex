# Map aids verification, 2026-10-18

Implements the [approved design](../docs/MAP_AIDS_BRIEF.md). The new runtime component
was registered through the live bridge in Overland Map
`ec447c62-03db-4416-a5a2-0b013c0f3893`, after CanvasTools and before Canvas. Registration
survived restarting the app: Aids is file 19 and Canvas is file 20 of 32.

## Offline checks

All eight offline suites pass: **146 checks**, comprising the existing 118 and
28 MapAidsChecks. Run from the repository root:

```powershell
& '..\dependencies\lua\bin\lua.exe' 'Overland Map/tests/RunOffline.lua'
```

The aid suite executes production Records, Model, SaveQueue, Session, CanvasTools,
renderer and editor code with isolated transport/GUI fixtures. It covers:

- Independent opt-in aids, unchanged schema, malformed optional fields, unknown nested
  settings, strict new values and retention of missing image references.
- Horizontal, vertical and diagonal rectangular calibration; nice initial distances;
  zoom, units and recalibration; tiny/oversized distances and invalid geometry.
- Upright north labels on rectangular artwork at cardinal and intermediate angles;
  measured clearance, text collision rows and tick gaps. Font, padding and background
  changes preserve bar endpoints. Finite tall artwork does not shift its anchor.
- Director/player/View-as-player writes; one Undo per gesture; busy-row rebasing,
  failed-add Retry, revoked queues, remote removal, concurrent changes and stale Undo.
- Image replacement, map removal and subtree deletion/Undo; viewer preference isolation;
  immediate scoped tooltip dismissal; passive rendering and locked edit surfaces.
- Cold image loading, Retry, late callbacks after map/asset changes, exact camera
  centering at edge anchors, typed-field flush before View as player and draft
  cancellation through Undo. Panning translates existing panels.

All **42** runtime/test Lua files pass `luac -p` and ASCII checks. Full-repository
LuaLS 3.19.2 reports **zero problems**, with all four worker results verified by the
CI reporter. The checked snapshot matches all 985 source/configuration files.
The parent
checkout's `tools/lua-typing/check.ps1` is absent, so the repository CI runner and
`.github/scripts/luals_report.py` are used instead.
The 13 changed runtime files match their deployed copies, final reload reports all
modules loaded, and 45 local documentation links plus diff whitespace checks pass.

## Connected-app evidence

Tested through the live bridge in a Director game, using one disposable map with
8400x6300 artwork. The two pre-existing maps and Party state were preserved.

- Added the aids through Settings and used actual input events for placement and
  gestures. Enter placed at the visible centre; Escape from placement left the
  saved position unchanged. A single map click placed the selected aid.
- An unlocked drag advanced the row revision once; one Undo restored the earlier
  position and exhausted that gesture's Undo. Holding a drag left the revision
  unchanged; Escape then release saved nothing. Locked selections had no hit surface.
- Compass resize and rotation handles changed width/angle while retaining X/Y.
  Find centered the camera, including X=0. Closing Settings hid editing handles.
  A pending numeric field committed on editor exit and before View as player.
- Personal compass visibility off still revealed the actively edited compass.
  View as player displayed only Only for you; the Director editor was destroyed
  and direct aid writes were refused.
- A real pin tooltip existed before disabling Show hover text and was nil immediately
  afterwards. The preference does not modify pin interaction or button-help handlers.
- Default artwork loaded on a fresh game entry. A custom 4:3 image with the longer
  label "True North" was visually checked at 0, 90, 180, 270 and 37 degrees. Text
  remained upright, outside the image's original top edge.
- A 0.1-unit bar used three readable rows; ticks broke around earlier labels. A
  1,000-unit bar was hidden with `aids.tooLong`, retaining 1,000. Degenerate calibration
  hid it with `aids.calibrate`, retaining its entered distance.
- Recalibrating the rectangular image to a vertical 50 km span kept the bar's
  represented distance at 20 and recalculated its reference width to 1,228.8.
  Changing font, doubling text size and changing background/padding left endpoints
  exactly -614.4 and +614.4. Zoom retained distance.
- Visually inspected fullscreen and minimum 720x480 in-app windows, with 120 pins,
  at Font Size 80/Warm Gold, 100/Default and 140/High Contrast. Settings scrolled to
  the aid controls without horizontal clipping. The map-relative scale geometry
  was identical at Font Size 80 and 140. Artwork included bright fields and dark
  mountain areas; automatic contrast backings remained readable.
- Native popout opened with approximately 1000x719 logical canvas dimensions;
  compass availability was ready and scale endpoints matched the in-app host.
  Return to app restored the in-app window.
- Deleting the test map produced 121 Undo steps. One Undo restored both aids and all
  120 pins. The final deletion settled, leaving exactly the two original maps.

## Findings fixed during verification

- A collapsed loading root prevented native compass image loading on a cold start.
  It now stays active but hidden until ready, matching the shared image loader.
- Tiny-distance tick lines crossed staggered text; they now break around the measured
  bounds of intervening labels.
- The canvas Enter handler referenced a missing module local. It now captures the
  loading module, and keyboard placement was retested after verifying deployed source.
- The normal camera clamp prevented Find from centering edge anchors at Fit zoom.
  Find enables a temporary camera mode; ordinary cameras retain their prior clamp.
- Aid fields needed their own before-View-as-player flush and Undo cancellation hooks.
  Both now use the model companion lifecycle and have editor regression coverage.
- A queued image-button action could run between remote aid removal and the UI refresh.
  The editor now rechecks that the aid exists before accepting any action.

## Scope

Two-client live tests remain explicitly skipped. Concurrent edits, failed uploads,
timeouts and Retry use isolated transport tests; the real transport was not disconnected.
Player permissions use the offline player fixture and live View as player.

Native popout rendering could not be visually captured: both desktop capture attempts
returned uniform gray images, despite the live canvas reporting ready images and valid
geometry. Its native visual appearance remains unverified. The pre-existing native
popout wheel-routing limitation is unchanged. Custom image rendering was exercised
with a known still-image asset; native image-picker cancellation was not exercised.

This is a development deployment, not publication of a new installable CodeMod package.

## Cleanup

The disposable map and its 120 pins were deleted through the model. Viewer preferences,
last map, window placement, Font Size, theme and mod monitoring were restored, and the
map window was closed. Party remained unplaced. Only the intended runtime file was
added to the CodeMod; offline helpers were not registered.

## Requested adjustments, 2026-10-18

- New aids default to None backgrounds; explicit saved backgrounds are preserved.
  The scale bar was added through the new toolbar editor and saved `background=none`.
- The top-toolbar compass button opens the dedicated Map aids editor. Settings retains
  personal visibility preferences. View as player hides the toolbar button and editor.
- A real click-drag selected an unselected compass and moved it from (50%, 50%) to
  approximately (43.02%, 59.31%). Resize changed width from 6% to 12.39%; rotation
  changed angle to 90.14 degrees without moving its anchor. Undo restored the angle.
  The scale bar also moved directly; locked dragging left its position unchanged.
- The reported text-size failure was reproduced: changing 1.5% to 3% saved the value,
  but the native glyph bounds remained 49.67 by 73.73 until text content changed.
  Aid text now uses the label renderer's fixed-font approach. Its transform changes
  immediately (0.96 to 1.92), and measured clearance follows that transform. Scale
  labels resize too; their measured endpoints remained -409.6 and 409.6.
- Rotation handles clear the north label. A native rotated-border artifact at 90
  degrees was reproduced in high contrast; four thin themed edges replace that shader.
  Live 90/180-degree rotation now leaves the compass visible and the north text upright.
- Enter placement returns to the dedicated editor; Escape from placement and from
  an active drag leaves the saved position unchanged. Closing the editor clears handles.
- Inspected window/fullscreen layouts, 720 by 480 minimum window size, 80/100/140%
  Font Size, and MCDM, Warm Gold and High Contrast themes. The earlier popout capture
  limitation and two-client live-test exclusion still apply.
- The new regression checks cover unchanged-glyph resizing, cardinal/intermediate
  clearance, passive hit testing, translated handles, locks and player permissions.
  All eight suites pass (144 checks); syntax/ASCII checks pass on 42 files.
  The final full LuaLS run reports zero problems across the matching 985-file snapshot;
  all four worker results were checked by the CI reporter. All 13 changed runtime
  files match the development deployment, and the live map-aid error log is empty.
- Deleted the second disposable map and restored viewer preferences, last map,
  Font Size, theme and monitoring; the map window is closed.

## Map-edge handle regression, 2026-10-18

The user's existing compass at (12%, 15%) was behind the breadcrumb and unlocked
banner at their saved camera position. The rotation handle was outside the canvas.
Selecting it constructed the handles, but they were obscured. Earlier centred-map
gesture tests did not cover this placement.

- Map clicks now select aids without opening the editor. Selection/release pans the
  camera only when required to expose their artwork and handles. Drag previews do not
  move the camera; saved anchors, width and angle are unchanged by camera adjustments.
- The settings editor now uses the top-aligned popover body, fixing controls that
  started above the scroll viewport. It includes explicit Unlock positions guidance.
- A real click on the existing compass revealed both handles with the editor closed.
  Its control bounds moved from above the viewport to Y=109.61 through 254.23.
- Direct move, resize and rotate previews were driven with pointer down/move events:
  moving shifted the bounds by 67.5 logical pixels per axis; resizing changed preview
  width from 245.76 to 433.77; rotating reached 90.05 degrees. Each was cancelled with
  Escape before release. The stored aid remained (12%, 15%), width 6%, angle 0.
- Added isolated checks for camera reveal geometry and Undo cancellation when no
  settings editor was constructed. All eight offline suites pass, now 146 checks.
- Verified the deployed editor starts at its title and exposes Unlock positions in
  the scroll viewport. Left the user's map open with the compass selected, editor
  closed, and both handles visible. No map data or other viewer preferences changed;
  only the camera was panned to reveal the controls. Mod monitoring was restored.
- Final LuaLS 3.19.2: zero problems, all four worker reports present, with the checked
  snapshot matching all 985 Lua/config files. Syntax and ASCII checks pass on all 42
  Region Map runtime/test files; 13 changed runtime files match the deployment.
