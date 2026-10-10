# Overland Map - Cleanup audit (2026-10-10)

A read-only audit of the mod's Lua for cleanup, abstraction, generalization and duplicated
functionality. Five auditors each took one lane; their findings were then checked against
the code (about 25 claims spot-checked, all held) and merged here. Line numbers are as of
commit `622b674` on `region-map-v2`; later commits move them.

| Lane | Files |
|---|---|
| 1. Data and rules | Records, Model, Paths, Log, Undo, Travel, Journal, Present, Import (checks) |
| 2. Canvas and tools | Canvas, CanvasTools, PathLayer, PathTool, Session (camera, preferences) |
| 3. UI panels | SidePanel, PathPanel, PartyPanel, LogPanel, Popovers, Atlas, Panel, Import (preview) |
| 4. Styles, Copy, Constants, dead code | Styles, Copy, Constants, plus a mod-wide dead-code sweep |
| 5. Architecture and codex reuse | Cross-file structure, the context contract, shared codex libraries |

Nothing was run: there is no DMHub here. Every item below needs an in-app check before it
ships.

## 1. Verdict

The core design is sound: one uploader (`RegionMapRecords.UploadRecord`), one undo system
with refusal after a remote edit, one data revision (`RegionMapModel.Revision`) that all
three caches key on, load order respected everywhere, every one of the 138 style classes in
use, and every copy id the code looks up present in `RegionMapCopy.lua`.

The weak spot is how V2.1 was added: mostly by copying V2 code and editing the copy.

- `RegionMapPathPanel.lua` is a fork of `RegionMapSidePanel.lua` (autosave, name input,
  text areas, state line, "..." menu, width fit).
- `WritePath` (Paths:415) and `WriteEntry` (Log:158) are forks of `WriteLocation`
  (Model:495); `SaveSidecar` (Model:1335) repeats the same core.
- `RegionMapPathLayer.lua` re-declares the route layer's segment clipping (byte-identical),
  panel pooling and slide/stretch/re-place logic.
- `Label` (5 files), `Button` (4), `Segments` (3, byte-identical) and the form `TextArea`
  (2, byte-identical) are pasted per file.

Deduplicated across the lanes, roughly 500-800 lines (4-5%) can go with no behavior
change. The larger gain is one implementation each of autosave, menus, the side panel
frame, row writes and undo plumbing.

## 2. Bugs found along the way

These change behavior, so each needs a decision rather than a silent refactor.

| # | Issue | Where | Status |
|---|---|---|---|
| B1 | Under Reduce motion, Go to the Party moves the camera but never saves it: the instant branch of `StartAnimation` skips `SaveCamera`, and `centerOnParty` passes no `onDone` | Canvas:227-231, 1478 | Confirmed |
| B2 | An arrow-key pan during a camera ease is overwritten: `PollKeys` does not call `StopAnimation`, and `TickAnimation` rewrites `data.camera` | Canvas:1140-1145 vs 1184-1186 | Confirmed |
| B3 | Import rejects a name with a line break inside it; a typed name folds the break into a space. The comment says "the same rules as a typed edit apply" | Import:58, 71-72 vs Records:247-253, 271-273 | Confirmed |
| B4 | The Travel to list sorts by raw `DisplayName` (case-sensitive); every other Location list uses the folded name key | Travel:169-173 | Confirmed |
| B5 | Every log row's "..." button has the same element id `region-map-log-more` | LogPanel:205 | Confirmed |
| B6 | The first route draw assigns `route.children` once per new dot (up to `C.routeDotLimit` = 600) | CanvasTools:403-407, 442 | Fixed in T1c (`2ce9f51`) |
| B7 | `Session.ReduceMotion()` deep-copies all preferences (every camera included) on every canvas think | Session:100-103, Canvas:1247 | Fixed in T1d (`3d3d4b5`); cost was never measured |
| B8 | A log note being typed may be lost when the whole window closes: the root `destroy` flushes only the Location and path forms | Panel:109-112, 858-859 | Not confirmed: depends on whether the engine fires the editor's `change` on destroy |
| B9 | `keepVisible` gets the raw side panel width while the camera clamp uses `panelInset`, which is 0 below 720 px | Panel:226 vs 641-644 | Reported by lane 2, not re-checked |
| B10 | Import creates Locations in a loop; each write invalidates the index, so each `CanAdd` rebuilds it | Import:238-259 | Reported by lane 1, not re-checked (performance) |

## 3. Tier 1 - safe, mostly mechanical

| # | Change | Evidence |
|---|---|---|
| 1a | Remove dead code: `Model.LiteralText` (same as `Copy.Literal`), `Model.WriteStatus`, the unused re-exports `Model.IsPositiveInteger` / `TextLength` / `ValidText`, the never-passed `guard` argument of `UpdateLocation` (with `CanCommit` and the `RegionMapGuard` alias), `C.imageTimeout`, `C.iconImage`, the copy ids `atlas.new`, `atlas.new.hint`, `search.result.path`, the class `regionMapCardNew`, the Search popover's empty `data.bind`, PathLayer's unread `path` field and its unreachable stretched reset | Model:31-43, 50-52, 559-566, 585; Constants:204, 252; Copy:37-38, 181; Atlas:190; Popovers:130; PathLayer:32, 481-484, 511 |
| 1b | Shared controls in `RegionMapSession.lua`: `Label`, `Button`, `Segments`, `TextArea`, `FocusSoon`, `SetClassIf` | Label: SidePanel:22, PathPanel:25, PartyPanel:24, LogPanel:22, Popovers:21. Button: SidePanel:26, PathPanel:29, Popovers:25, LogPanel:26. Segments: SidePanel:221, PathPanel:37, Popovers:33. TextArea: SidePanel:569, PathPanel:503. Focus after 0.05 s: SidePanel:689, PathPanel:723, PartyPanel:356, Popovers:126, 587 |
| 1c | One `ClipSegment` and one panel `Pool` in `RegionMapCanvasTools.lua`; route dots use the pool (fixes B6) | CanvasTools:330-350 = PathLayer:116-135; PathLayer:147-178 vs CanvasTools:402-419 |
| 1d | Preference getters read without deep-copying (fixes B7); one factory for the on/off preferences | Session:100-103, 165-202 |
| 1e | One ordered list per allowed-value set in Constants; Records and Paths build lookups from them; the UI iterates them | Records:505-511, Paths:30-34, SidePanel:497, 553, 556, PathPanel:432, 488, Popovers:239, 357-358, Session:329-330 |
| 1f | Data helpers out of the UI: `Paths.OtherEnd` (5 copies), `Model.NameOf` and a nil-safe `Model.DisplayName` (about 11 copies), `Paths.ShownName` (5), `ParseTime` / `TimeInputText` moved from PathPanel to Paths (PartyPanel reaches into PathPanel for them today), one leg-wording builder (LogPanel:51-65 and PartyPanel:53-62) | Travel:119-126, Model:1007, PartyPanel:28-38, 283, 320, PathPanel:64-87, 112, 147, 192-196, Panel:487-494, Paths:364-367, 396-397 |
| 1g | Named literals: the bend handle and swatch colours in Styles are `C.pathCasingLight` / `C.pathCasingDark`; layout numbers derived from the toolbar and breadcrumb (54, 48, 44, 34, 104) and the repeated focus and recheck delays become constants | Styles:1346-1347, 1561, 1570, 241, 367, 581-582, 904, 1039; Atlas:20-21, 139, 173 |

## 4. Tier 2 - consolidation (needs in-app checks)

- **`RegionMapRecords.WriteRow(spec, current, changes, description, callbacks)`** replacing
  `WriteLocation`, `WritePath`, `WriteEntry` and the core of `SaveSidecar`. Traps: the set of
  fields a `false` removes must be per table (Location only: scale, pace, mode; a global
  rule would drop `hidden=false` and fail `IsValidLocationFields`); the log keeps its own
  narrow `Invalidate` (switching it to `Model.InvalidateIndex` rebuilds the indexes on every
  Party move); `Model.Revert`'s table branch stays separate because undo replaces whole rows.
- **Undo plumbing**: `Entry` is defined twice (Model:571, Paths:38) and built inline three
  more times; the "nil step means unavailable" tail repeats at 10 sites; appending steps at
  about 14. Add `R.Entry`, `R.StepResult`, `R.AddStep(s)`.
- **One autosave form controller** (`Session.Form`) for the Location and path forms
  (SidePanel:255-315, 501-513, 632-685 vs PathPanel:240-288, 436-448, 570-625). Each form
  keeps its own save function: a Location writes three stores and settles each field
  separately with async callbacks; a path writes one row.
- **One side panel frame and width fit** (SidePanel:850-889, PathPanel:741-783,
  PartyPanel:166-244, LogPanel:304-363) plus `ctx.ClosePanel()`, so PartyPanel:127 stops
  writing `data.panelMode` (Session:18-19 says only the shell does).
- **`Session.ShowMenu(element, entries)`** for the five context-menu openers (Panel:317-332,
  Canvas:714-716, 1370-1378, LogPanel:143-152, PathPanel:353-368). Keep "close before the
  action": closing after could touch a pin panel the action destroyed.
- **`Session.ImageSlot`** for the three image drop wells (SidePanel:699-732,
  Atlas:138-179, Popovers:170-192).
- **One removal planner in Model**: the side panel re-derives the subtree from
  `Model.Index()` (SidePanel:64-81, 122, 814), so the confirm counts can drift from what the
  delete removes. Keep the rescue target `false` (not nil) and each function's write order.
- **State document**: one `BeginChange`/`CompleteChange` wrapper (Model:384-392, 412-416,
  895-906) and a shared settings reader and writer for the six reads and five setters.
- **`Model.GetMap(id)`** and **`Model.CanSeePinId(id)`** for 13 hand-built checks.
- **`Session.WhenNotBusy`** for the two busy-retry loops (SidePanel:49-62, PathPanel:304-320).

## 5. Tier 3 - structure (before the next feature, e.g. hex mode in IDEAS.md)

- **Map kind policy table**: 22 `IsPointCrawl` forks across 11 files each ask a different
  question (drag the Party, show paths, open the Party section, snap Place Party, log Move
  here as placed, ...). One row per kind makes a third kind one entry.
- **Tool registry**: the active tool's name is compared at about 25 sites in 4 files
  (Canvas, CanvasTools, PathTool, Panel). The per-target behavior is irregular (see lane 2
  notes below); a registry must keep it exactly.
- **Panel modes and Esc from one table**: `EscapeLayer` (Panel:567-580) and `escape`
  (Panel:894-926) mirror each other; the three modal cards each have their own close API.
- **Sliding layer helper** for the route, path and pin layers' slide/stretch/re-place
  logic (CanvasTools:452-478, PathLayer:529-564, Canvas:837-863). This is the measured hot
  path: re-check README section 5.
- **Move undo revert** (`CanRevert`, `Revert`, rebinds; Model:62-81, 1156-1269) into
  `RegionMapUndo.lua`.
- **Restore the context contract**: components call siblings (Canvas -> PartyPanel /
  PathPanel, SidePanel -> PathPanel) and data predicates live in UI files
  (`PartyPanel.Available`, `PathPanel.CanConnect`).

Tool behavior a registry must keep: a pin click measures (ruler, scale), ends the line
(path, redraw) or selects (add, move, none); a Party click measures (ruler, scale) and
otherwise opens the Party section; a Party right-click does nothing while any tool is on; a
right-click on a pin or the map drops the last bend (path, redraw) and otherwise opens the
menu.

## 6. Rule violations and doc drift

- **On-screen text outside `RegionMapCopy.lua`**: PartyPanel:93-94 (`" (" .. time .. ")"`;
  the copy id `ctx.party.travel` meant for it is unused), LogPanel:189-190 (`" - "`),
  Panel:371 (`"..."`), Journal:59 (`"Untitled"`), Records:381 (`"Unknown user"`).
- **Copy that hard-codes limits**: `import.tooMany` and `limit.locations` (250),
  `import.skip.name` (80), `set.timeUnit.hint` (6 watches). `image.hint` already shows the
  right pattern (placeholders filled from Constants).
- **The `danger` class**: the mod applies DefaultStyles' `danger` (red text) and overrides
  it back to `@fgStrong` in three compound rules for contrast (Styles:30-41). Any new use
  silently gets the low-contrast red. A mod-only class name removes the trap.
- **Image wells use white-alpha literals** (`#ffffff14`, `#ffffff99`), which nearly vanish
  on a light theme. A design decision, not a refactor.
- **Docs**: README section 2 puts the Esc layers in Session (they are in Panel) and says
  host APIs are checked once in `RegionMap.lua` (guards are also in Journal, CanvasTools,
  Panel, Present); the Records header says only Model and Undo use it (seven files do).

## 7. Leave alone

- `Model.Revert`'s whole-row restore; the three revision schemes (row `revision`,
  `stateMeta`, `partyRevision`; persisted); the log's narrow `Invalidate`.
- The three easing curves (camera ease-out, Party smoothstep, linear crossfade), the four
  hit tests (their shapes come from the spec) and the per-layer signatures.
- The in-window toast and confirm versus the codex `ViewsToast` and `Hud:ModalMessage`
  (anchoring, hover pause, Undo, size).
- `R.Clamp` versus `math.clamp` (NaN handling differs) and `R.TrimSingleLine` versus
  `string.trim` (folds line breaks, nil to "").
- `Segments` versus `gui.EnumeratedSliderControl`: fires on press and looks different.
- Copy ids with the same text under different ids: each context may diverge later.
- The Director note blocks (Location: collapsible; path: always open) and pooled versus
  signature-rebuilt lists (deliberate performance choices).
- Splitting `RegionMapModel.lua`, `RegionMapCanvas.lua` or `RegionMapStyles.lua` into new
  files: each new file costs a CodeMod registration, and removal needs the in-app tools.

Where the lanes disagreed: lane 5 proposed a new `RegionMapUtil.lua` at load position 2;
the others kept helpers in Records and Session. Existing files win on registration cost.

## 8. Caveats

- The type checker named in the root `CLAUDE.md` (`tools/lua-typing`) was not available to
  the audit; only `luac -p` and a globals diff were.
- The performance items (B6, B7, five tables per `ClipSegment` call) are reasoned from the
  code, not measured. Measure before claiming a win.

## 9. Tier 1 status

Done on `region-map-v2`, one commit per item. Lua: 22 files, +443 / -516 (73 lines net).
The line count is modest by design; the gain is one owner for each piece. The larger
savings are in Tier 2.

| Item | Commit | What changed |
|---|---|---|
| 1a | `b0617fd` | Dead code removed as listed. `atlas.new`, `atlas.new.hint` and `search.result.path` are struck through in `V2_COPY.md` under its "dropped" convention |
| 1b | `ce63e22` | `Session.Label`, `Button`, `Segments`, `TextArea`, `FocusSoon`, `SetClassIf`; `C.afterLayoutDelay` names the 0.05 s wait. `Button` keeps the log's `disabled` guard (only the log's Undo button ever has that class) |
| 1c | `2ce9f51` | `CanvasTools.ClipSegment` (unrolled: no tables per call) and `CanvasTools.Pool`, used by the path layer, the route dots and the type samples |
| 1d | `3d3d4b5` | Preference getters read without copying; `OnOffPreference` builds the three on/off pairs |
| 1e | `417f261` | One ordered list per value set in Constants; `Records.SetOf` builds the checks; editors read the lists |
| 1f | `4333cba` | `Paths.OtherEnd`, `Paths.ShownName`, `Paths.TimeInputText` / `ParseTime`, `Model.NameOf`, nil-safe `Model.DisplayName`, `Log.LegCopy` |
| 1g | `acc824f` | Casing colours, chrome inset / bar / breadcrumb heights and `C.belowChromeBar`, Atlas thumbnail height, save recheck and undo timings |

How it was checked (no DMHub available):

- `luac -p` (Lua 5.4.6) on every file after every step, the ASCII-only rule, and a diff of
  the globals each file reads (from the bytecode) against the starting point: every change
  in that list is explained (a helper moved in or out), and no file reads an undefined
  name.
- Load order, from the bytecode: every namespace a file reads while loading belongs to a
  file earlier in README section 2.
- `ClipSegment`: the unrolled version against the original on 2,000,000 random segments
  (vertical, horizontal and zero-length included): identical results and return counts.
  In plain Lua 5.4 it is 0.20 us a call against 0.72 us; at about 2,000 calls per re-place
  that is around 1 ms of a 23-34 ms re-layout, so a small win.
- `Pool` for the route dots: the old and new route code run side by side on mock panels,
  2,000 trials of 12 passes: identical layer contents, visibility and placement. A first
  draw of 600 dots sets the layer's children once instead of 600 times.
- On/off preferences and the value sets: checked in plain Lua against the old literals
  and orders.
- Styles: `RegionMapStyles.Build()` built in plain Lua before and after 1g: the 198 rules
  are identical, and every changed constant keeps its value.

Not covered by those checks, so test in the app: the side panel and path panel forms
(type, pause, leave a field, Retry), segment rows (Location edit, path edit, Settings), the
Undo last change button disabled with nothing to undo, the stop card's time field, the
travel toast and log lines for a whole leg, an "on" leg and a "back" leg, Show route on a
long log, and the type samples in Settings and the path panel.

Left from 1g on purpose: the banners' 48 and the Atlas's 44 (their gaps under the
breadcrumb differ, so the intent is unclear) and the `height - 114` / `height - 220`
offsets in Popovers and Import.
