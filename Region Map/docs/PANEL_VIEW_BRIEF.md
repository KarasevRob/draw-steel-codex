# Overland Map: in-app window view

Status: LOCKED. User approved the reviewed defaults with "Continue" on 2026-10-14.
Implemented and deployed to the development app. Window movement, resizing, mode
changes and minimum-size layouts were verified live. The final keyboard correction
awaits a live retest; native popout wheel delivery needs an engine change.

## Goal and constraints

Let Directors and players keep Overland Map open at a smaller size while using the
rest of Codex, without opening another OS window. The full map remains available:
this is a hosting mode, not a separate reduced-feature map.

- Changes stay inside `Region Map/`; no engine or core UI edits.
- Preserve fullscreen and native popout, permissions, presentation, and map tools.
- Keep one live map interface per client. Changing its view does not change other
  clients' window preferences or shared map records.
- The user released the engine for live verification, then reserved it for the
  concurrent label feature. No further engine calls or deployment during that work.

## Confirmed decisions

| Date | Decision | Reason |
|---|---|---|
| 2026-10-14 | Movable, resizable window inside the app | User selected this over a side dock. |
| 2026-10-14 | Reopening remembers the last in-app view; initial view is fullscreen | User selected this over always-window or always-fullscreen. |
| 2026-10-14 | Separate Window/Fullscreen toggle and Pop out buttons | User prefers direct switching to a View menu. |
| 2026-10-14 | Proceed with the reviewed size, state, return, and control defaults | User instructed "Continue" after the final design check. |

## Decided behavior

### Window and controls

- The existing toolbar gains one view toggle: **Window view** in fullscreen,
  **Fullscreen** in the smaller window. **Pop out** remains separate.
- Window view initially opens centered at 900 x 600 logical UI units, with the
  existing 720 x 480 minimum. Use the app work area between persistent rails,
  leaving the visible action bar accessible. Clamp the actual window to that area.
  If the usable area cannot support the minimum at the current Font Size, use
  fullscreen temporarily without overwriting the preferred mode or window geometry.
- A themed title bar provides a dedicated drag target and guarded Close control.
  Existing map drag gestures keep panning the image. Resize all edges and corners
  with the core resize helper; include a visible corner grip.
- Provide a keyboard-accessible **Reset window size and position** action in the
  title's window menu. The new host controls must have keyboard activation,
  descriptive tooltips and a visible focus indicator; recovery cannot require dragging.
- Remember window size and position per viewer/game, independently of fullscreen
  and native popout geometry. Clamp restored geometry when the viewport changes.
- Keep the tactical board, action bar, and other windows usable around the window.
  Clicks and wheel input outside its bounds pass through normally. Wheel over the
  canvas zooms; wheel over a scrolling detail/log control scrolls it; title and
  resize chrome consume input without panning or zooming either map.
- Window mode participates in normal window stacking. Fullscreen continues to sit
  behind the icon rails and other documents, with the action bar hidden.
- Preserve all current toolbar actions. Keep the breadcrumb clear of the extra
  button at the minimum width; details retain their existing narrow-layout behavior.

### View changes and state

- Fullscreen <-> Window changes the existing host's geometry without rebuilding
  `RegionMapPanel`. Preserve the exact current map (including Atlas), camera,
  selection, side panel, import text, log editor, and unfinished path.
- Cancel only the active pointer gesture before changing geometry, without
  committing a pin/Party/bend move. Retain already placed draft-path points.
  Changing view neither commits a draft path nor discards an import draft. Close
  only transient menus that cannot be repositioned safely, never the draft/editor.
- Preserve focused editors during an in-app mode change. Restore canvas focus
  after layout only if the canvas previously owned it; changing view must not
  steal focus from import/log/name inputs.
- Closing still uses the existing edit flush and import-discard guard. Reopening
  restores the preferred in-app view and saved map/camera as it does today.
- Native popout keeps its current separate-host lifecycle and draft protection.
  Its return button becomes **Return to app**, returning to the remembered
  in-app view. Popping out does not overwrite that preference.
- Activating the map's rail/menu entry raises an existing native popout. A smaller
  in-app window behind another window is brought forward first; activating it
  while already foremost closes it through the guard. Fullscreen retains the
  existing toggle. Never create a second map interface.
- Show to players changes the displayed map while preserving an already-open
  client's host mode. If closed, open its remembered in-app view. Each client
  keeps control of its own window and can close it independently.
- Esc retains the current order: stop/close the innermost interaction, then side
  panel, then go up to Atlas, then close. Other foreground dialogs retain priority.

### Copy manifest

| Purpose | Text | Status |
|---|---|---|
| Window title | Overland Map | Existing |
| Toggle from fullscreen tooltip | Switch to window view inside the app | Approved |
| Toggle from window tooltip | Switch to fullscreen | Approved |
| Native popout action | Pop out into its own window | Existing tooltip |
| Native return action | Return to app | Approved replacement for Return to fullscreen |
| Close tooltip | Close the map | Existing |
| Title/window menu tooltip | Window options | Approved |
| Geometry recovery action | Reset window size and position | Approved |

Window outline (theme classes supply colors and fonts):

```text
+------------------------------------------------------------+
| Overland Map / Window options                         Close |
| Atlas > Current map    [map tools] [Fullscreen] [Pop out]    |
|                                                            |
|                         map                                |
|                                                            |
| [camera controls]                       [Party status]   // |
+------------------------------------------------------------+
```

In window mode the title-bar Close replaces the duplicate toolbar Close. The
toggle and Pop out remain in the map toolbar as confirmed by the user.

No new destructive action, confirmation, shared setting, or map content field is
introduced. All controls use existing theme vocabulary and distinct icons with tooltips.

## Implementation direction

Keep the existing action registration and extend its in-app host to support both
modes. The current `frame -> zoom -> content` tree can remain attached throughout
an in-app switch. Reuse `gui.WindowResizePanel` for edge/corner resizing and the
existing mod preference storage for mode and geometry.

- `RegionMap.lua`: own host mode, window geometry, title-bar drag, resize lifecycle,
  stacking, action-bar restoration, native return destination, and launch routing.
- `RegionMapPanel.lua`: view-toggle callback/button and mode-aware Escape priority;
  view changes must bypass destructive `RunHostHook` behavior.
- `RegionMapSession.lua`: validated per-viewer/game mode and geometry accessors.
- `RegionMapConstants.lua`, `RegionMapCopy.lua`, `RegionMapStyles.lua`: dimensions,
  icons, strings, themed host chrome, and toolbar clearance.
- README and existing copy documentation: update the two-mode hosting description.

The current fullscreen host draws a full-screen background and swallows presses.
Window mode must remove that full-screen input/render surface, not merely shrink
its visible child. The implementation shrinks the outer host itself, retaining
frame/zoom/content inside it. Fullscreen fitting must stop overwriting window
geometry. Reset fullscreen margins before applying window x/y. Attach the resize
helper as the host's last child and announce external size changes through its
resize event.

Use mode-aware Escape priorities; `options.close` alone no longer identifies
fullscreen. Ensure title-bar dragging never steals map panning. Save geometry at
gesture completion, not every frame, and restore only valid finite values.

Keep saved x/y/width/height in one unscaled logical host coordinate space; convert
through the same `PanelDocument.WindowUIScale()` used by the current fullscreen
host. Both rail and non-rail mode must keep the canvas-local pointer calculation
and pin/side-panel scale consistent. Apply host-mode callbacks and Escape priority
together before the next interaction. Compute breadcrumb clearance from visible
toolbar controls rather than accumulating another magic width.

## Decision map and exclusions

| Category | Treatment |
|---|---|
| Data | Viewer/game preferences only; shared map records unchanged. |
| Audience | Directors and players; existing permission checks remain. |
| Surface | Confirmed in-app floating window, fullscreen, or existing OS popout. |
| Controls | Confirmed separate mode toggle and Pop out; themed drag/resize chrome. |
| States | Empty Atlas, loading/error, active edits, remote updates, reload, close/reopen. |
| Accessibility | Respect Font Size; keyboard host controls and visible focus; reset size/position without dragging; existing keyboard/Esc navigation. |
| Performance | Reuse content; no duplicate subscriptions; persist geometry after gestures. |
| Regression | All map actions retained; presentation and native return use viewer's mode. |
| Scope | No side docking, tabs, multiple simultaneous map windows, snapping system, or engine changes. |

## Evidence

Source line anchors below record the design audit before implementation.

- The user's request is the demand evidence: reduced size without popping out.
  No community vote counts or broader demand claims are inferred.
- `RegionMap.lua:96-109`: current native transfer destroys the old host and opens
  the other one. `:143-204`: fullscreen already separates frame, scaled content,
  and outer host. `:230-249`: the single action registration also supplies content.
- `RegionMapPanel.lua:316-324`: `RunHostHook` closes an import draft before host
  destruction; use a separate nondestructive route for in-app mode changes.
- `RegionMapPanel.lua:576-594`, `:881-883`, `:929-965`: existing Escape order and
  creation-time priority require a mode-aware update.
- `RegionMapSession.lua:92-117`: existing preferences are viewer/game scoped;
  `:120-178` already saves map cameras and last-map selection.
- `DMHub Core UI/DialogResize.lua:27-56`: generic eight-edge/corner resize helper;
  it resizes its direct parent, supports bounds and completion callbacks, and must
  be the last child. `DMHub Core UI/CommandBuilder.lua:1568-1577` uses a scratch
  geometry holder.
- Alternative supported route: `PanelDocument.Get(name):PresentPanel{...}`.
  `DocumentSystem.lua:7341`, `:7604`, `:7982`, `:8296-8330` reach `reg.content()`
  without rejecting action registrations. Normal rail/menu activation separately
  honors `reg.launch`. This route is viable, but rebuilding the content would add
  state-transfer work for drafts and selections; retaining the present host avoids it.
- Native popouts likewise call the registration's content factory directly:
  `DocumentSystem.lua:12191-12260`. No additional registration is needed.
- Precedent: floating application windows and resizing are established VTT UI
  patterns; see [Foundry's Application API](https://foundryvtt.com/api/v10/classes/client.Application.html).
  Local Codex behavior remains the implementation reference.

## Acceptance checks

1. Window/fullscreen toggles preserve the current map or Atlas, camera, selection,
   detail panel, JSON draft, log draft, and unfinished path.
2. Resize all edges/corners; drag only the title; pan/zoom remains cursor-anchored.
   After moving/resizing, test canvas, toolbar, side/log scrolling, title, resize
   edges, and outside-board clicks/wheel separately. Outside events reach their
   intended window; host chrome never pans/zooms the board.
3. Minimum/default/wide sizes at Font Size 80/100/140 and supported themes keep
   controls and dialogs accessible. Resize, font changes, and reopening clamp
   the window into the current viewport.
4. Closing/reopening restores local view and geometry. Fullscreen/native changes
   do not overwrite window geometry. Native return selects the remembered mode.
5. Director/player/View as player permissions and presentation continue working;
   Show to players never changes another client's preferred view.
6. Escape, import discard/cancel, edit saves, reload cleanup, action bar restore,
   and one-instance-only behavior remain correct. Preserve editor focus; test
   keyboard toggle, Pop out, Close, and geometry reset with visible focus.
7. Syntax, ASCII, diff hygiene, and the available mod type checker pass. Offline
   host/state tests supplement but do not replace live physical/visual checks.

## Review and validation

Default dimensions, presentation/return behavior, and copy are approved.
Independent Director/UX and accessibility critiques have been folded in: input
routing, work-area clamping, draft/gesture separation, title close/resize cues,
focus and Escape, keyboard recovery, and scale/toolbar geometry.

Source validation, 2026-10-14:

- `tests/WindowHostChecks.lua`: 13/13 offline checks passed. These execute the
  production host, preferences, host buttons and core resize helper against an
  in-memory GUI/content fixture. They do not prove engine hit-testing or rendering.
- Bundled `luac -p`, ASCII checks and `git diff --check` passed for changed Lua
  and the new helper.
- `../dependencies/check-mod.ps1 -Mod 'Region Map'`: latest run reported 0 problems
  in 35 seconds, including the test helper, with other modules loaded as libraries.
- The repository-standard `../tools/lua-typing/check.ps1` and its baseline remain
  absent. No standard full-repository baseline comparison is claimed.

Live verification, 2026-10-14, on the existing Broadhurst map:

- The view toggle opened the default 900 x 600 window. The root itself shrank,
  leaving the board visible around it, and switching retained the same content
  object and camera.
- Physical title dragging exposed an engine drag-transfer offset mismatch. The
  corrected title handler uses pointer deltas in the stationary document layer.
  A 120 x 60 screen-pixel drag moved the host by exactly 81 x 40.5 logical units
  at the measured display scale, without moving the map camera.
- Physical drags of all eight resize handles changed the expected edge(s), kept
  the opposite edge fixed, and saved geometry. A 30-pixel drag produced the
  expected 20.25-logical-unit change on each affected axis.
- Fullscreen/window changes preserved the exact import editor and its 407-character
  example draft. Title Close opened the existing discard confirmation; Cancel
  retained the host and draft. The test draft was cleared afterwards. No Import
  action was submitted and no map content or Locations were written.
- The minimum 720 x 480 logical window was inspected at Font Size 80/100/140 in
  Default and Warm Gold. All six combinations retained the draft and accessible
  title/toolbar controls; the short import body scrolled with its footer visible.
  Font, theme and geometry used for that sweep were restored afterwards.
- Pop out and Return to app restored the remembered window view.
- A real Windows wheel notch over the in-app canvas delivered one panel event
  and changed zoom from 2.66001988046875 to 3.05902286253906 (x1.15). The tactical
  board zoom remained 5.06805372238159. The native popout still received no canvas
  wheel event: see [the engine handoff](POPOUT_WHEEL_ENGINE_HANDOFF.md).

Keyboard correction and remaining verification:

- Live keyboard checks exposed duplicate handling: the engine already moves focus
  on Tab and clicks a focused panel on Enter/Space release. Added polling/input
  callbacks caused double movement or activation. Those extra handlers were removed;
  host controls retain the standard focusable button behavior and focus styling.
- The correction passed all 13 offline checks and was copied to the development
  files. F4 was requested, but its result identified an active label editor from
  the other development session. Loaded-text confirmation and the final physical
  Tab/Enter/Space retest were stopped at the user's request to leave that engine
  to label work. Do not count this keyboard correction as live-verified yet.
- Live player-client presentation/permission checks and the full Escape/focus/input
  matrix remain acceptance checks. The isolated tests cover host routing and
  preference preservation, not a second client or native input dispatch.
- No cloud publication or shared map-content edits were performed. Only local
  development deployment and viewer settings were used. Temporary diagnostic
  references may remain in the Lua globals until reload; final cleanup is deferred
  with engine access, rather than interrupting the other session.

Deployment uses the live CodeMod's `gitFolderPath`. A bridge reload can execute
cached file contents before `RefreshLocalFiles` runs. After copying/touching files,
use the app's F4 refresh and confirm the changed files' `localContents` match the
intended text before drawing conclusions from a test. Do not use `ImportLocal`
for this: it also uploads the module.
