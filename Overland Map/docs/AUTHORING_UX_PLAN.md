# Overland Map: authoring UX fixes (stable map, one object grammar, prep styling)

## Context

In a blind usability test, an agent filled the Broadhurst map through the UI only. The three biggest sources of friction were:

1. **The tool competes with the map.**
   - The 320 px side panel covers the map's right edge.
   - `ctx.Select` pans the camera through `keepVisible`.
   - When the panel closes, `CalculateImageLayout` re-clamps instantly, so the view jumps.
2. **Locations, labels and aids follow different rules.**
   - Click opens read mode for a location but the editor for a label.
   - Done returns a location to read mode but closes a label.
   - An unselected label pans instead of dragging.
   - While locked, a label or aid can't be selected and a blocked drag gives no feedback.
3. **Hidden styling marks the common case.**
   - Everything starts Hidden, so every item carries a fade plus an eye badge. The fade is opacity on a parent panel, so the engine may not even apply it to children.
   - Label eyes float 10 px off the corner.
   - Nothing shows a total for the map.

**Goal:** placing and naming 25 items never moves or hides the map, every object type follows the same rules, and names stay readable while visibility is still easy to check.

**User decisions:**
- A Director's (editor's) click on any object opens its editor.
- **Position Lock stays on by default** and still re-locks on map open. Only add feedback and clearer state.

**Hard constraint:** change only files under `Overland Map/`. Register the new Lua file through `mcp__dmhub__register_lua_file`. All Lua is ASCII only.

---

## Phase 1: The map never moves by itself

**1.1 Remove `keepVisible`.**
- Delete the `keepVisible` call in `ctx.Select` (`OverlandMapPanel.lua:337-341`).
- Delete the event in `OverlandMapCanvas.lua:587-597` and its header doc line 11.
- Search already centres the result through `centerOn`, so it needs no extra pan.

**1.2 Ease the panel inset instead of snapping.**
- The canvas keeps its own `state.inset` and passes it to `CalculateImageLayout` in `Layout()` (Canvas ~209) and in `WheelZoom` (`OverlandMapCamera.lua:109`), instead of `data.panelInset`.
- In the canvas think, `state.inset` moves toward `data.panelInset`:
  - over `C.transitionSeconds` with the same ease-out as `LerpCamera` (`OverlandMapCamera.lua:15-23`);
  - instantly under Reduce Motion.
- Opening only widens the clamp range, so nothing moves. Closing narrows it gradually, so the camera glides back instead of jumping.
- Raise the think rate while easing, through the same `wake()` path `StartAnimation` uses.
- Save the camera once easing ends, if the clamp changed it.

**1.3 Ignore stray clicks.**
- The canvas `click` (`OverlandMapCanvas.lua:465-490`) proceeds only if the canvas saw the matching press. Set a flag per button in the press handler (~428) and consume it in click.
- This stops the Add menu's press-fired entry (`gui.ContextMenuItem` fires on press) from placing a location or label under the toolbar on release.

---

## Phase 2: One set of rules for every object

**2.1 Click opens the editor, for every type, for anyone who can edit.**

| Object | Change | Where |
|---|---|---|
| Pin | Click opens `ctx.Select(id, Model.CanEdit(loc) and "edit" or "read")`. Double-click stays, and still sets `focusName`. | `OverlandMapGestures.lua:308`, `:310-321` |
| Label | Already opens the editor. | `OverlandMapCanvas.lua:477` |
| Aid | `ctx.SelectAid(aid, true)` (opens the aids popover). | `OverlandMapCanvas.lua:476` |
| Selection while locked | Allowed for labels and aids. The lock blocks only moving, resizing and rotating. Remove the locked-only branch at Canvas:473-478 and fall through to the same selection calls. | `OverlandMapCanvas.lua:473` |

Players, View as player, the breadcrumb and Search keep read mode.

**2.2 A location's edit view gets the read view's frame and actions.** All in `OverlandMapSidePanel.lua`.
- Move `readIcon`, `readTitle` and `closeButton` (:290-294) into one shared header shown in read and edit (and keep the pick header).
- Edit mode gets a compact secondary action row: `openMapButton`, `movePartyButton` and `moreButton`, with the same collapse rules as `BindRead` (:443-449). `pathsSection` (:371) shows under the form for the Director.
  - These widgets have only one instance each, so `Bind()` (:820) moves them into the active view's slot by reassigning `children`, as `OverlandMapPinLayer.SetPinChildren` does.
- Read mode keeps `editButton`, for players who can edit their own pins.

**2.3 Same footer and close rules for location and label panels.**
- Both panels become `flow = vertical`: the scroll area fills the height, and a pinned footer sits below it.
- Footer contents:
  - Location: `stateLine` + `retryButton`, **Delete** (`OverlandMapSidePanel.RequestDelete(ctx, id)`, :98), **Done**.
  - Label: status + retry, **Delete label**, **Done** (moved out of the body at `OverlandMapLabelPanel.lua:141-154`).
- Location Done → `Flush(); ctx.Select(nil)` (`SidePanel.lua:577-580`).
- Escape in location `edit` → `ctx.Select(nil)`. Pickers still go back (escape handler `OverlandMapPanel.lua:1279-1323`, the "other edit modes" branch).
- Reset the scroll position to the top whenever the bound id changes, in both panels. Reuse the scroll reset in `OverlandMapPopovers.lua:754-760`. This gets the Name/Text field into view.
- Add the matching footer and Done rule to the Path panel if it differs. Check `OverlandMapPathPanel.lua`.

**2.4 Drag parity (only while unlocked).**
- Pressing any label, selected or not, starts `labelMove`.
- Canvas:453: replace `labelLayer.HitTest(x, y) == data.selectedLabelId and BeginLabelDrag("labelMove", data.selectedLabelId)` with a hit on any label → `BeginLabelDrag("labelMove", hit)`.
- A release without movement still selects through the existing click path.

**2.5 Lock feedback and state.**
- When a press on an editable pin, label or aid crosses the drag threshold while locked, show the toast once per gesture: "Positions are locked", with an **Unlock** action. Its click does what the lock button does.
  - Use `OverlandMapUndo.Notify(copyId, nil, nil, {copyId, click})` (`OverlandMapUndo.lua:125-129`).
  - Hook into `PollDrag` in `OverlandMapGestures.lua`. A pin gesture with `allowed = false` exists already. For labels and aids, start a dead gesture the same way instead of panning.
- Lock button (`OverlandMapPanel.lua:664-667`):
  - The `on` (highlighted) class means **locked**, so the highlight shows the current state.
  - Shorter tooltips: "Positions locked - click to unlock" / "Positions unlocked - click to lock".
- Update `chip.unlocked` (Copy:209) to "Positions unlocked - drag locations, labels or map aids to move", matching 2.4.

**2.6 Placement tools behave the same.**
- `ctx.CreateLabel` (`OverlandMapPanel.lua:373-381`) no longer calls `SetTool("none")`. Add label stays on until Esc or a toolbar toggle, like Add location.

---

## Phase 3: Preparation view keeps names readable

**3.1 Remove the fades.** Delete:
- the `hiddenPin` opacity rule (`OverlandMapCanvas.lua:714-717`);
- the `hiddenForPlayers` opacity rule (`OverlandMapLabelLayer.lua:327-330`);
- the hidden path mark fade (`C.pathHiddenOpacity` use at `OverlandMapPathLayer.lua:233`; keep the constant only if the overlay uses it).

Text is never faded.

**3.2 New per-viewer preference `showVisibility`, default false.**
- Add `OnOffPreference("showVisibility", false)` in `OverlandMapPreferences.lua:173-197`.
- Add a checkbox in Settings (`OverlandMapPopovers.lua:643-660`).
- When off: no hidden badges on pins (`PlaceBadge("hiddenBadge", ...)`, `PinLayer.lua:160`), no label eyes (`LabelLayer.lua:145`) and no path badges (`PathLayer.lua:417-425`).
- When on: today's badges, plus the path fade.
- Add the preference to each layer's bind or signature key so toggling rebinds: PinLayer:111/172, LabelLayer:154, PathLayer:443.

**3.3 Label eye attached to the label.**
- Place it centred on the label box's top-left corner (`Offset(box, -box.width/2, -box.height/2)` at `LabelLayer.lua:244`), mirroring the pin badge corner.
- Size it to `C.pinBadgeSize * UIScale` with the round pin-badge style instead of the fixed 20×20.

**3.4 One count for the whole map.**
- New `OverlandMapReaders.HiddenCount(mapId)`: hidden pins + labels + paths on that map, read from the lists the layers already bind (pin children, `OverlandMapLabels.ForMap`, the path layer's source).
- A clickable chip at the top of the banner stack (`RefreshBanners`, `OverlandMapPanel.lua:727-760`). It shows only to the Director, only on an open map, and only when the count is above 0.
  - Text: "{count} hidden from players", with a `.one` form, since Copy picks `.one` when count == 1.
  - Clicking toggles `showVisibility`. The `on` class shows when the overlay is on.

---

## Phase 4: Quick add (click, type, Enter)

**New file `Overland Map/OverlandMapQuickAdd.lua`.**
- Register it first with `register_lua_file`, after `OverlandMapPopovers.lua`.
- Build it lazily through `Slot("quick", ...)` and `Ensure` in `OverlandMapPanel.lua:955-966`, like the other components.

**Behaviour**

| Step | What happens |
|---|---|
| Open | `CanvasTools.AddAt` success (`OverlandMapCanvasTools.lua:59-75`) calls `ctx.QuickAdd("location", newId)` instead of `ctx.Select(newId, "edit")`. `ctx.CreateLabel` calls `ctx.QuickAdd("label", id)` instead of `SelectLabel(id, true)`. |
| State | `data.quick = {kind, id}`. The item is selected (`selectedId` or `selectedLabelId`) with `panelMode = "none"`, so no side panel and no inset. |
| Widget | About 260 × UIScale wide. One single-line input (Name / Label text) and an **All options** link. |
| Placement | Beside the anchor, right side by default, left if it would overflow, vertically clamped below the chrome. Hidden while the anchor is off-screen. Repositioned on each canvas `Layout()` through a new `ctx.CanvasLayout(layout)` callback, using `OverlandMapGeometry.ImageToPanel` and `OverlandMapDrawing.PositionPanel`. |
| Enter | Commit, close, keep the tool on, call `FocusCanvas()`. |
| Commit | A location stages the name through its own `OverlandMapEditors.Create("location", ...)` instance (as `SidePanel.lua:280`). A label stages through `OverlandMapLabels.Stage` and `Flush`. An empty label text discards the draft through `OverlandMapLabels.Leave`. |
| Other ways out | Register with `OverlandMapSession.Register{flush, cancel}`, so any `ctx.Transition` (clicking elsewhere, placing the next item, map change) commits first. `ctx.Select`, `SelectLabel`, `SelectPath`, `SelectAid` and `SetTool("none")` clear `data.quick`. `RefreshAll` clears it if the item is gone or the map changed. |
| All options | `ctx.Select(id, "edit")` with `focusName`, or `ctx.SelectLabel(id, true)`. |
| Escape | New `quick` layer in `EscapeLayer()` (`OverlandMapPanel.lua:776-792`), just above `tool`. The first Esc commits and closes the popover; the next stops the tool. |

The new-item defaults stay as they are: Hidden, `LastPinStyle`, `LastLabelFormat`.

---

## Copy (`OverlandMapCopy.lua`, mirrored in `docs/V2_COPY.md`)

New keys:
- `quick.name.placeholder` "Name"
- `quick.label.placeholder` "Label text"
- `quick.more` "All options"
- `toast.locked` "Positions are locked"
- `toast.locked.unlock` "Unlock"
- `vis.chip` / `vis.chip.one` "{count} hidden from players"
- `vis.chip.tooltip` "Show or hide which items players cannot see"
- `set.showVisibility` "Show player visibility"

Changed keys: `tb.lock.on`, `tb.lock.off`, `chip.unlocked`.

---

## Tests (`Overland Map/tests/`)

**Update**
- `LifetimeChecks.lua:207-219`: a click on an editable pin now gives `"edit"`. Add a non-editable pin case that gives `"read"`.
- `LazyPanelChecks.lua`: add `quick` to the component/factory lists (around :64-68 and :98) and to `LazyPanelBenchmark.lua`.
- Any canvas-click fixture that clicks without a press: add the press (1.3).

**New `AuthoringFlowChecks.lua`**
- Built on the gesture fixture in `LifetimeChecks.lua` and the shell fixture in `LazyPanelChecks.lua`.
- Added to `RunOffline.lua`, with the counts updated in `tests/README.md`.
- Checks:
  - `Select` never changes `data.camera`.
  - The inset eases over several ticks to the clamp, and is instant under Reduce Motion.
  - A click without a canvas press is ignored.
  - Location Done and Esc deselect; Esc in a picker returns.
  - The footer Delete calls `RequestDelete`.
  - An unselected label drags while unlocked.
  - While locked, a label or aid click selects but does not drag.
  - A locked drag notifies once with the Unlock action.
  - The label tool stays on after placement.
  - Quick add, location: no side-panel factory call; Enter commits the name; All options opens edit; Esc closes the popover, then the tool.
  - Quick add, label: empty text discards the draft.
  - `showVisibility` false hides badges and eyes; true shows them.
  - `HiddenCount` counts pins, labels and paths.

---

## Docs
- `README.md`:
  - hidden styling (196-197, 289);
  - toolbar and lock (72-78);
  - status and banners (336-347);
  - the file table row for `OverlandMapQuickAdd.lua`.
- `docs/V2_COPY.md`: new and changed copy.
- New short test report `tests/AUTHORING_UX_<date>.md`: offline results, live checks, and the usability re-run.

---

## Verification

**1. Static checks**
- `../dependencies/lua/bin/luac.exe -p` on every changed file.
- `../dependencies/lua/bin/lua.exe "Overland Map/tests/RunOffline.lua"`: all suites pass.
- `..\dependencies\check-mod.ps1 -Mod "Overland Map"`: no new problems.

**2. Deploy and smoke test**
- Copy the changed files to `C:\Users\ElderHex\codex-dev-mods\Overland Map\` and touch them.
- Confirm "CodeMod: Local file changed" in Player.log, then run `reload_lua`.
- Ask before any start or stop of DMHub.

**3. Live checks** (MCP `screenshot` / `mouse` / `key`, on Broadhurst)
- Add 5 pins along the right edge: the map never shifts.
- A panel closing glides rather than jumps.
- Click a pin opens the editor with its actions; Done closes it.
- Drag an unselected label while unlocked.
- A locked drag shows the toast; Unlock works.
- The chip shows the hidden count and toggles the overlay.
- Quick add: click, type, Enter, click the next spot.

**4. Usability re-run**
- Run the same blind-agent prompt (UI-only, log of criticisms without solutions, no repeated feedback) on a fresh unlabeled copy of the Broadhurst image.
- Compare its log with `scratchpad/broadhurst-usertest-log.md`.

**5. Commit**
- Before committing, `git diff --cached --name-only` must list only `Overland Map/` paths.
- Commit per phase. Publish the CodeMod only when the user asks.
