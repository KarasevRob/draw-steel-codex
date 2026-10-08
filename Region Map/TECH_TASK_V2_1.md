# Overland Map V2.1 - Technical Task

Status: READY FOR BUILD once the V2.1 copy (V2_COPY.md sections 18-25) is signed off.
Written 2026-10-08. Source of truth: [docs/V2_1_BRIEF.md](docs/V2_1_BRIEF.md) (locked
2026-10-08). Where this file and the brief disagree, the brief wins; fix this file. Decision
IDs (A1, Q13, W2, ...) are the brief's ledger rows; copy IDs are V2_COPY.md's.
[TECH_TASK_V2.md](TECH_TASK_V2.md) stays the reference for everything V2.1 does not change.

## 1. Scope and constraints

V2.1 adds:
- image size guidance (idea 11);
- map image borders (idea 10);
- JSON import of Locations (idea 9);
- point crawl mode (7.2 and 7.3): a map's mode fixed at creation, paths between pins, Party
  travel along paths, one log entry per leg.

The order is M5: 11, 10 (soft fade first), 9, then point crawl in three slices.

| Constraint | Meaning |
|---|---|
| Zero core changes | Edit only `Region Map/`. The mod stays opt-in. |
| Standards | `CLAUDE.md`, `UI_BEST_PRACTICES.md`, `ThemeEngine.md`, `DefaultStyles.md`, `STYLE_GUIDE.md`. ASCII-only Lua. `borderBox = true` with padding. Style rules only in `RegionMapStyles.lua`. |
| Typing | Every new or changed file checks clean (0 problems). |
| Copy | Every on-screen string comes from `RegionMapCopy.lua`, keyed by its V2_COPY.md id. |
| Files | New files are registered with `mcp__dmhub__register_lua_file` in the section 3 order; Firebase persistence is confirmed. Never edit `main.lua`. |
| Data | Stored table and document names never change. Every change is additive: rows written before V2.1 read exactly as before (L3). |
| Roles | One Director per game (W4). Player writes are still checked at commit time. |
| DMHub process | Never start, stop or restart DMHub without asking the user. |
| Phases | Each phase ends deployed and verified live; work pauses for the user after each one. Commits only when the user asks. |

**Prerequisite: met 2026-10-08.** The app reads the mod from the dev-mod folder
`C:\Users\ElderHex\codex-dev-mods\Overland Map\`. Player.log shows `MONITORING LOCAL: True
for Overland Map`, and the live mod reports `checkedout = true`, `isUsingGit = true` and that
`gitFolderPath`. The rename is live: `RegionMapConstants.panelName` and `window.title` read
"Overland Map". It stays checked out until V2.1 is done; the user then commits it in the mod
tools.

## 2. Engine facts this task relies on

| Fact | Anchor | Use |
|---|---|---|
| u/v to canvas: `Tools.ImageToPanel(layout,u,v)`; canvas to u/v: `Tools.PanelToImage` (nil in the letterbox) | CanvasTools.lua:71, :79 | Paths, hit test, Path tool |
| A line is a rotated thin panel: width = length, `PlaceCentered` at the midpoint, `selfStyle.rotate = -deg(atan(dy,dx))` | CanvasTools.lua:374-415 (`LayoutRuler`) | Path segments and casing |
| Pooled overlay panels: `EnsurePool` / `SetDotCount`; `PlaceDots` with `ClipSegment`; re-laid out on zoom or after a pan of half a view | CanvasTools.lua:304-367 | Line patterns |
| Canvas layer order: `fadingPanel`, `imagePanel`, `overlay.route`, `pinLayer`, `overlay.ruler`, `overlay.label`, `controls` | Canvas.lua:699-710 | Path layer and border layer slot |
| A detached layer whose classes never change gets no class styles; give it an inline size | TECH_TASK_V2 7b, M4 lesson 1 | New layers |
| The tool dispatcher is `Tools.PlaceAt` on `ctx.data.tool`; the tools whitelist is in `ctx.SetTool` | CanvasTools.lua:156; Panel.lua:193-207 | Path and redraw tools |
| The map right-click menu is `Tools.MapMenu`, shown with `gui.ContextMenu` | CanvasTools.lua:453; Canvas.lua:996 | Path and Party menus |
| Image size is known only on `imageLoaded` (`bgimageWidth/Height`, fallback `bgsprite.dimensions`); `gui.IconEditor` gives only an id | Canvas.lua:672-697; Atlas.lua:117; SidePanel.lua:655 | Size probe |
| Masks and slices: `bgimageMask`, `bgimageMaskRect` (panel), `bgslice`, `imageRect` (style) | Definitions/Panel.lua:27-34; Style.lua:86 | Torn edge, frame |
| Keys: `dmhub.KeyPressed(key)`, edge-detected in `PollKeys` while the canvas has focus. Esc comes only through `captureEscape` and `EscapeLayer()` | Canvas.lua:869; Panel.lua:451-460, 690 | Backspace, Esc in the Path tool |
| Upload: `Records.UploadRecord` (one pending write per row), `Audit`, `NextRevision` | Records.lua:362, 336, 186 | Path rows |
| Game-wide settings: `Model.WriteState(desc, apply)` plus getter/setter pairs | Model.lua:362-414 | Unit, types, last border |
| An undo entry is `{description, steps}`; `Model.Revert` is all or nothing; `Undo.Push` / `Remember` | Model.lua:62-76, 987; Undo.lua:68-78 | Cascades, import, travel |
| The log kind is chosen in `RegionMapLog.Record`; kinds are validated at Records.lua:457/568; the player filter is `CanSeeEntry`; the text is `LogPanel.EntryText` | Log.lua:146, 72; LogPanel.lua:52 | Leg and stop entries |
| JSON: `dmhub.OpenFileDialog{extensions, open(path)}` and `dmhub.ParseJsonFile(path, onError)` | dmhub.lua:412, 422; ImportDialog.lua:1789 | Import |
| Settings popover parts: `Section`, `Check`, `Segments` and the `body.data.bind` guard | Popovers.lua:33-313 | New sections |
| Side panel: `MenuEntries`/`Add` builds the "..." and right-click menus; `Row` and `BindPick` build lists; the gate for Move Party here | SidePanel.lua:137, 706-748, 426 | Paths section, pickers |

## 3. Target architecture

### 3.1 New files (CodeMod order; each under about 800 lines)

| Register after | New file | Responsibility |
|---|---|---|
| `RegionMapLog.lua` | `RegionMapPaths.lua` | Path model: visibility (H1, View as player), create/update/delete, cascades, path types, time unit, `FormatTime` |
| `RegionMapPaths.lua` | `RegionMapTravel.lua` | Travel options, `Travel`, `StopPartway`, Party-on-path position, leg and stop log writes |
| `RegionMapCanvasTools.lua` | `RegionMapPathLayer.lua` | Path drawing (casing, patterns, labels, badges, halo), `PathAt` hit test, bend handles, the Path tool draft and rubber band |
| `RegionMapSidePanel.lua` | `RegionMapPathPanel.lua` | Path read and edit modes, a Location's Paths list, Connect to..., the Party travel section, the stop-partway and hidden-travel cards |
| `RegionMapPopovers.lua` | `RegionMapImport.lua` | File pick, parse, validate, preview, batch create, error card |

Changed files:
- Constants, Copy, Records, Model, Log, LogPanel, Undo;
- Session: tools `path` and `redraw`, `selectedPathId`, `pathDraft`, `panelMode` values
  `pickMode`, `path`, `pathEdit`, `pickPathEnd`, `party`;
- CanvasTools, Canvas, SidePanel, Atlas, Popovers, Panel;
- Styles: every new rule, through `ThemeEngine.MergeStyles`.

### 3.2 Data (all additive)

| Storage | Change |
|---|---|
| `RegionMapLocations` | Optional `mode` nil\|"free"\|"pointcrawl" (nil = free, L3). Optional `border` nil\|"none"\|"fade"\|"torn"\|"frame" (nil = none, K5). Both validated as enums when present |
| `RegionMapPaths` (new table) | One row per path (3.3) |
| `RegionMapLogEntries` | Kinds `leg` and `stopped`; optional fields `pathId`, `fromId`, `toId`, `time`, `rest` ("on" \| "back" when leaving from partway), `secret` (W1), `spent` (Q15) |
| `regionMapState` document | `timeUnit` "days"\|"watches" (default "days", C9). `pathTypes` list of `{id, name, pattern, color, width}`: the getter returns the C4 starter set while the field is nil, so nothing is written until the first edit. `lastBorder` (default "fade", K8). `party` gains `pathId`, `pathFrom`, `spent` (Q13) |

Times are stored in watches (1 watch = 4 hours, 6 watches = 1 day), so switching the unit
changes only the display (C9). `RegionMapPaths.FormatTime(watches)` is the only place that
converts.

The undo step shapes gain `{state = key, before = value}` for state-document edits (path types
and unit; N3 restores a deleted type).

### 3.3 Path record

```lua
--- One point crawl path between two pins on the same map. Paths are two-way;
--- `back` makes the other direction slower or impossible (W2).
--- @class RegionMapPathRecord: GameType, RegionMapAudit
--- @field new fun(o?: table): RegionMapPathRecord
--- @field id string
--- @field schemaVersion integer 1
--- @field mapId string the point crawl map both ends are pinned on
--- @field aId string one end (a Location id); times are "from a" unless stated
--- @field bId string the other end; never equal to aId
--- @field bends {u: number, v: number}[] at most C.pathBendLimit, in order from a to b
--- @field name string 0..80 characters; "" shows the type name
--- @field typeId string a pathTypes id; an unknown id draws as "No type" (N3)
--- @field time number watches from a to b, 0 or more
--- @field back "same"|"different"|"none" the b-to-a direction
--- @field backTime number watches from b to a when back == "different"
--- @field description string 0..4000, players read it (H5)
--- @field note string 0..8000, Director-only danger or requirement (C5; UI-hidden only)
--- @field visibility "hidden"|"revealed" new paths start revealed (W3)
--- @field revision integer
--- @field hidden boolean soft delete
RegionMapPathRecord = RegisterGameType("RegionMapPathRecord")
RegionMapPathRecord.tableName = C.pathTableName
```

`IsValidPath` follows the `IsValidLogEntry` order. It checks:
- both ends resolve to valid Locations whose `parentId == mapId`, and `aId ~= bId`;
- the map is a point crawl map;
- bends are in 0..1 and within the limit;
- the enums, lengths and numbers are in range.

A path that fails is skipped and logged once (`RejectMalformed`).

## 4. Task list

| ID | Phase | Title | Brief |
|---|---|---|---|
| V21-00 | 0 | Tech task, copy, J1 measurement, border art spec | M1, J1, K3 |
| V21-01 | 1 | Image size probe, toasts and hint | J1-J4, Q25 |
| V21-02 | 2 | Settings popover sections | Q22, K6 |
| V21-03 | 2 | Soft fade border | K1, K2, K4, K5, K8, Q23 |
| V21-04 | 2 | Torn edge and frame (waits for the art) | K1, K3, K7 |
| V21-05 | 3 | JSON import | IM1-IM6, Q24 |
| V21-06 | 4 | Map mode at creation | A1, A2, A4, L3, L4, Q21 |
| V21-07 | 4 | Path records, model and cascades | B3, B5, C1, C2, H1, H3, H5, W2, W3, Q28 |
| V21-08 | 4 | Path types and time unit | C3, C4, C6, C9, N1, N3, Q3, Q26 |
| V21-09 | 4 | Path layer: drawing and hit test | D1, F2, F3, Q1-Q4, Q11, Q12 |
| V21-10 | 4 | Path read panel | E2, H5 |
| V21-11 | 5 | Path tool | E1, D2, Q7, Q8, Q9 |
| V21-12 | 5 | Connect to... and the Location's Paths section | E1, Q10 |
| V21-13 | 5 | Path edit form and "..." menu | E2, E3, C1, C2, W2, H1 |
| V21-14 | 5 | Bend handles and Redraw line | D2, Q5, Q6 |
| V21-15 | 6 | Travel model | G1, G3-G7, Q13, Q14, Q16 |
| V21-16 | 6 | Leg and stop log entries | I1, N2, Q15, Q19, W1 |
| V21-17 | 6 | Travel UI | G1, G3, G6, G7, Q4, Q17, Q18, W1, Q27 |
| V21-18 | 7 | Accessibility and visual pass | M2, Q1, Q12, Q26 |
| V21-19 | 7 | Performance | F4 |
| V21-20 | 7 | Docs and acceptance | M1, section 6 |

**Milestones** (pause for the user after each one):

| Milestone | Tasks | Result |
|---|---|---|
| P0 Paperwork | V21-00 | Copy signed off, size numbers approved, art spec handed over |
| P1 Size guidance | V21-01 | Size hint and warnings live |
| P2 Borders | V21-02..03 (04 when the art arrives) | Soft fade live; Settings regrouped |
| P3 Import | V21-05 | JSON import live |
| P4 Point crawl maps | V21-06..10 | Point crawl maps exist; paths draw and read; types in Settings |
| P5 Path editing | V21-11..14 | The Director draws and edits paths without execute_lua |
| P6 Travel | V21-15..17 | The Party travels along paths; legs logged |
| P7 Finish | V21-18..20 | Release |

---

### V21-00 Paperwork

1. This file.
2. The copy: V2_COPY.md sections 18-25 (draft 2026-10-08). The user signs off before P1.
3. **J1 measurement** (needs the app running; ask first):
   - Load test images 1k, 2k, 4k, 8k and 16k wide through a probe panel.
   - Record the time to `imageLoaded` (first load and cached) and the frame times while
     panning at fit and at 20x.
   - Take screenshots at 20x to judge sharpness.
   - Propose `imageMinWidth`, `imageRecommendedWidth` and `imageMaxWidth` for approval.
4. **K3:** [docs/BORDER_ART.md](docs/BORDER_ART.md), the art format for Torn edge and Frame.

### V21-01 Image size probe, toasts and hint

- **Constants:** `imageMinWidth = 1500`, `imageRecommendedWidth = 4000`,
  `imageMaxWidth = 12000` (J1, approved by the user 2026-10-08, brief W5).
- **`Tools.ImageSize(imageId, onSize)`:**
  - Uses `gui.TryGetImageDimensions`, falling back to `gui.GetImageDimensionsCallback`
    (found in J1; no probe panel needed).
  - Calls `onSize(width, height)` once and guards `mod.unloaded`.
  - Both calls are pcall-guarded and feature-detected, so an older core simply shows no
    toast.
- **Hooks**, on new picks only (J4):
  - Atlas `CreateMap` (Atlas.lua:40).
  - Side panel `AddMap` / `ReplaceImage` (SidePanel.lua:670-671).
  - An image outside the range gets `toast.image.small` or `toast.image.large`; nothing is
    blocked (J3).
- **`Undo.Push`** gains an optional action button `{copyId, click}`. The size toast uses
  `toast.replaceImage`, which opens `pickImage` with `pickKind = "replace"` for that map (Q25).
- **`image.hint`** is always visible under the side panel `pickImage` editor, and is the
  Atlas New map card's tooltip (J2).

**Acceptance.**
- A small, a large and an in-range pick each give the right toast or none.
- The hint shows in both places.
- Opening an existing map shows no toast.
- Replace image... from the toast opens the picker for that map.

### V21-02 Settings popover sections

`BuildSettings` regroups into these sections (Q22):
- "This map" (scale, pace, border);
- "Whole game" (travel time unit and path types, from V21-08);
- "Party";
- "Only for you".

Path types show one editor open at a time.

**Acceptance.** Every V2 control still works and binds; the popover scrolls past the bottom
of a 720x480 window.

### V21-03 Soft fade border

- **Model:**
  - `SetBorder(id, border)` writes the Location and `lastBorder`.
  - `CreateMap` and `AddMap` copy `lastBorder` (K5, K8).
  - Older maps read `nil` and draw None.
- **Border tiles** in "This map":
  - None / Soft fade / Torn edge / Frame, each with a small preview.
  - Torn edge and Frame are disabled with `set.border.needsArt` until V21-04.
- **Drawing:**
  - Four edge panels over the image's edges, each a gradient from the canvas background
    (`@bgAlt`) to clear.
  - They go in a border layer between `imagePanel` and `overlay.route`, so pins, paths,
    labels and the Party are never covered (Q23).
  - The band stays narrow: a fraction of the image's shorter side, capped in px.
  - They are laid out with the image in `Canvas.Layout`.
- **Check first:** confirm inline gradients are possible (DefaultStyles gradient tokens). If
  they are not, the fallback is a `bgimageMask` fade image, which needs one uploaded asset;
  ask the user.

**Acceptance.**
- Fade at 720x480, 1000x800 and Expanded, in the Default and Warm Gold themes.
- Pins on the edge stay fully visible.
- Existing maps stay None.
- A new map gets the last pick, and Soft fade before any pick.

### V21-04 Torn edge and frame (waits for the art)

- The art ids live in Constants, so a missing id keeps the tile disabled.
- **Torn edge:** `bgimageMask` on `imagePanel` (and on `fadingPanel` during a crossfade).
- **Frame:** a `bgslice` panel around the image. `CalculateImageLayout` gains a margin
  argument, so Fit and the camera limits include the frame (K7).
- The art format is in [docs/BORDER_ART.md](docs/BORDER_ART.md).

**Acceptance.** Both looks at every zoom; Fit shows the whole frame; pins stay above.

### V21-05 JSON import

- **Format:** [docs/IMPORT_FORMAT.md](docs/IMPORT_FORMAT.md), with an example file.
  - A top-level array, or `{"locations": [...]}`.
  - Fields: `name` (required), `description`, `note`, `icon`, `pinStyle`, `importance`,
    `visibility` (default hidden, R1), `u`, `v` (both or neither).
- **`RegionMapImport.Start(ctx)`** (Director only):
  1. `dmhub.OpenFileDialog{extensions = {"json"}}`, then `dmhub.ParseJsonFile`.
  2. Validate each entry with the record validators, keeping a reason per entry index.
  3. Show the preview card (built like `ctx.Confirm`): count, skipped entries with reasons,
     names already on the map, and the placement note.
  4. Refuse the whole file when the visible pin count plus the entries exceeds
     `C.labelLimit` (IM6).

  One error card covers invalid JSON, a file with no entries, and a file where every entry
  is skipped.
- **Commit:**
  - A `dmhub.Coroutine` creates the Locations (then details and notes), yielding every 10
    writes, and gathers every step into one undo entry. Toast `toast.imported` with Undo (IM5).
  - Entries with no u/v go on a grid in rows around the center, in file order (Q24).
  - On a failed write it stops, shows `toast.saveFailed`, and the Undo covers what was written.
- **Entry point (IM1, open):** propose `menu.import` in the map right-click menu and in the
  open map's "..." menu. Confirm with the user at the start of P3.

**Acceptance.**
- Test files: 24 entries, duplicate names, over the limit, invalid JSON, empty, all skipped.
- One Undo removes the whole import.
- Placed rows don't overlap.

### V21-06 Map mode at creation

- **Atlas New map card:**
  - Step 1 shows `mode.title`, the Free and Point crawl buttons with their descriptions,
    `mode.permanent` and Cancel.
  - Step 2 is today's picker with Back.
- **Side panel Add map:** a new `panelMode = "pickMode"` comes before `pickImage`.
- **Model:**
  - `CreateMap(..., mode)` and `AddMap(id, imageId, mode)` write `mode` only when it is
    "pointcrawl".
  - Nothing ever changes it (A4).
  - `Model.IsPointCrawl(mapId)`.
- **Chips:** `chip.pointcrawl` on the Atlas card and in the side panel's map meta (A2).
- **Empty state:** on a point crawl map with fewer than 2 Locations, the Director sees
  `hint.pointcrawl.empty` (Q21).

**Acceptance.** Both entry points, Cancel and Back; old maps read free; the chip is shown.

### V21-07 Path records, model and cascades

- **Constants:** `pathTableName = "RegionMapPaths"`, `pathSchemaVersion = 1`,
  `pathBendLimit = 32`, `pathNameMax = 80`.
- **Records:** `RegionMapPathRecord`, `PathsTable()`, `IsValidPath`. The model index gains
  `pathsOf[locationId]` and `pathsOn[mapId]`, built in the same cached pass.
- **`RegionMapPaths`:**
  - **Reads:**
    - `Paths(mapId)` and `PathsOf(locationId)`, per viewer.
    - A player, or View as player (Q28), sees a path only when it is revealed and both
      ends are visible pins (H1).
    - `DisplayName(path)`: the name, else the type name, else "".
  - **Writes:**
    - `CreatePath(mapId, aId, bId, bends, fields)`, `UpdatePath(id, changes)`,
      `DeletePath(id)` and `SetVisibility(id, v)`. Each returns `ok, reason, undoEntry`.
    - All are Director-only (H3) and use the `WriteLocation` pattern.
    - New paths are revealed (W3).
  - **Cascades (B5):**
    - `DeleteLocation`, `RemoveMap` and `MoveToMap` (Model.lua:873, 902, 626) add
      path-hide steps to their batch and return the path count for the confirm.
    - `AnyPending` covers path rows.

**Acceptance.**
- The player and View-as-player filters match H1.
- Deleting a pin with 3 paths asks first, removes them, and Undo restores all 4 rows.
- Moving a pin to another map removes its paths.

### V21-08 Path types and time unit

- **Getters and setters on the state document:** `TimeUnit` / `SetTimeUnit`, `PathTypes`
  (the starter set while nil) / `SetPathTypes`.
- **Undo:** writes push `{state = key, before}` steps, and `Model.Revert` handles them.
- **Starter set (C4, N1, Q3)**, all styles editable:

  | Name | Pattern |
  |---|---|
  | Road | Solid |
  | Trail | Dashed |
  | River | Double |
  | Sea | Dash-dot |
  | Underground | Dotted |
  | Secret | Long dash |

- **Settings "Whole game":**
  - `Segments` for Days / Watches.
  - Type rows with a line sample and Edit.
  - The editor: name, pattern select, 6 swatches (24 px, with a tooltip naming the colour and
    a check on the selected one; Ink has a light ring), width segments, and the
    `set.pathType.sameLook` warning.
  - Delete type: with a confirm (`dlg.deleteType.*`) when paths use the type, otherwise at
    once with a toast. Both have Undo.
  - Add path type.
- **Colour tokens:** the swatch palette and the danger and Undo contrast use theme tokens and
  meet 4.5:1 for text and 3:1 for graphics (Q26).

**Acceptance.** Edit, add and delete with undo; switching the unit relabels every time
without changing the stored values.

### V21-09 Path layer: drawing and hit test

- **Layer:** a new path layer between the border layer and `overlay.route`, with an inline
  size. It slides on pan like the route layer and is re-laid out on zoom or after a pan of
  half a view.
- **Segments:**
  - Each segment from a to b through its bends has a casing panel (the opposite tone,
    1-2 px wider each side, Q1) and a colour panel.
  - Solid and Double are long panels; Double is two panels offset either side of the
    center line.
  - Dashed, Dotted, Dash-dot and Long dash are pooled short panels with constant
    screen-pixel sizes (Q2: dots at least 4 px; Double at least 6 px across with a 2 px gap).
  - Everything is clipped with `ClipSegment`. A cap of `C.pathSegmentLimit` pooled panels
    comes from V21-19.
- **States:**
  - Hidden paths (Director): faded colour, casing at full strength, and an eye-slash badge
    at each segment's middle (F2, Q12).
  - Selected path: a halo.
  - "No type" (N3): plain thin solid.
- **Labels:** `path.label` at the middle of the longest segment, on hover, when selected, or
  with Show names on (Q11). Decluttered by zoom like Normal pin names.
- **`PathLayer.PathAt(layout, x, y)`:**
  - The nearest visible path whose distance from the point to a segment is within
    `C.pinHitMin / 2` scaled (a 24 px band, Q4). Pins win over paths.
  - Canvas `click` and `rightClick` (tool "none") and the hover poll call it.

**Acceptance.**
- Every pattern is distinct at fit and at 20x on light and dark art.
- Casing contrast is at least 3:1 (measured).
- Hover and selection labels work.
- A click 10 px off a line selects it.

### V21-10 Path read panel

`panelMode = "path"` shows:
- the title (`path.title*`), a type chip with a line sample, and `path.ends`;
- the time each way (`path.time*`) and the description;
- for the Director: the eye toggle with `path.waits` when an end is hidden, and the note
  section (`path.note`, `path.note.sub`), Edit and "...".

Players see the name, type, time and description (H5).

**Acceptance.** The Director and player views match H5. Esc closes the panel.

### V21-11 Path tool

- **Toolbar:** `tools.path` joins the `SetTool` whitelist. The button shows only on point
  crawl maps and is disabled with `tb.path.disabled` below 2 Locations.
- **The draft** in session is `{startId, bends}`. Steps:
  - Pin clicks while the tool is on go through `PlaceAt`; a click within the pin snap radius
    picks the pin.
  - The first pin starts the draft (`hint.path.start`, then `hint.path.next`).
  - A click on empty map adds a bend; clicking the start pin is ignored.
  - A rubber-band line follows the cursor.
  - Right-click, or Backspace (`PollKeys`; the canvas takes focus when the tool starts),
    removes the last bend.
- **Esc:** the first Esc cancels the draft and the second ends the tool (Q7). The tool layer
  of `EscapeLayer` checks the draft first.
- **Finishing at a pin:**
  - `CreatePath` with the session's last type and time (Q8; the first path of a game is
    Road, 1 day).
  - When the two pins are already joined and there are no bends, it adds one bend offset to
    the side (Q9).
  - The new path opens in edit mode, and the tool stays on.

**Acceptance.** Draw with 0 and 3 bends; Backspace; Esc twice; a parallel path is offset;
the tool stays on.

### V21-12 Connect to... and the Location's Paths section

- **`menu.connect`** in the pin "..." menu and in the right-click menu (Director, point crawl
  maps). It opens `panelMode = "pickPathEnd"`: the other pins on the map, sorted by distance,
  filtered by a `gui.SearchInput`. A pick creates the path as in V21-11 and opens it in edit
  mode (Q10).
- **Paths section** in a Location's read mode on a point crawl map: rows with the far end,
  path name, type, time and hidden badge. A click selects the path. Connect to... is there
  too.

**Acceptance.** A path made by keyboard and clicks only, with no drag.

### V21-13 Path edit form and "..." menu

- **`panelMode = "pathEdit"`**, with autosave and Saving / Saved / Not saved, as for
  Locations. Fields:
  - name;
  - type (a dropdown with line samples);
  - time (a number plus the unit label and `edit.path.unit.hint`);
  - the other way (Same / Different time / Not possible, plus a time, W2);
  - description;
  - note;
  - visibility.

  Number ranges are checked (`edit.path.timeRange`).
- **"..." menu:**
  - `menu.redraw`;
  - Hide or Reveal (`menu.hide` / `menu.reveal`);
  - Delete (`menu.delete`, at once with `toast.pathDeleted` and Undo, E3).

**Acceptance.** Every field saves and syncs; the unit switches the label; Undo of a delete
restores the path.

### V21-14 Bend handles and Redraw line

- **Handles** show only while a path is selected and pins are unlocked (Q5):
  - Bend handles are 10 px discs with 24 px hit areas. A polled drag writes once on drop;
    right-click removes the bend.
  - "+" handles at segment middles: dragging one adds a bend.
- **`menu.redraw`** sets `tools.redraw` for the path. It is the Path tool's second step with
  the a end fixed and the b end as the only valid finish (`hint.redraw`). It replaces
  `bends` on finish and keeps every other field (Q6).

**Acceptance.** Drag, remove and add a bend with undo; no handles while pins are locked;
Redraw keeps the name and time.

### V21-15 Travel model

- **`RegionMapTravel.Options()`**, for the viewer:
  - **At a Location on a point crawl map:** each visible path of it whose direction is
    allowed (`back ~= "none"` when leaving from b), with the time for that direction.
  - **Partway:** continue to the far end (the rest of the time) or back to `pathFrom` (the
    time spent).
  - **Otherwise** nothing (G6).
  - **Players:** only with `PlayersCanMoveParty`, and only along paths they can see (G5).
- **`Travel(pathId, toId, revealFirst)`** writes the Party at `toId` (beside its pin, like
  "at") and a `leg` entry. Both go in one undo entry with `toast.traveled`.
  - With `revealFirst`, the path's reveal is part of the same undo entry.
  - A Director travel on a hidden path without revealing it sets `secret` (W1).
- **`StopPartway(pathId, fromId, spent)`** (Director):
  - Accepts 0 < spent < the time in that direction.
  - Writes the Party with `pathId`, `pathFrom`, `spent`, and u/v at that fraction of the
    polyline's length (Q13), plus a `stopped` entry storing `spent` (Q15).
  - If the newest log entry is a leg on this path that arrived where the Party now is, that
    entry is hidden in the same undo entry and the stop counts from its start (Q14).
- **The derived position:** the Party's drawn position on a path is recomputed from the
  path every refresh, so editing bends or time never strands it. If the path is deleted, the
  Party moves to the nearer end in the same batch (Q13).
- **Party status** gains `onPath` (`status.onPath`).
- **On point crawl maps:**
  - "Move Party here" is Director-only and logged as `placed` (Q16).
  - A Director placement within `partySnapRadius` of a visible pin counts as "at" it.
  - Players cannot drag the Party there.

**Acceptance.** Every option shape; the limits; replacing an arrival; deleting a path with
the Party on it.

### V21-16 Leg and stop log entries

- **Records:** `logKinds` gains `leg` and `stopped`, and the new optional fields are
  validated.
- **The route** of a leg is the path's polyline in travel order (I1).
- **`CanSeeEntry` for players:**
  - A leg or stop is shown when the map can be opened and both ends are visible pins.
    Otherwise V2's hidden-Location rule applies.
  - The path name and route show only when the path is visible to players and the entry is
    not `secret` (W1).
- **`EntryText`** uses `log.leg`, `log.leg.on`, `log.leg.back`, `log.stopped` and
  `log.stopped.noPath`, with `{by}` from `leg.by` (Q19).

**Acceptance.** Director and player texts for normal, secret, rest-of-path and stop entries;
the route is drawn along the path.

### V21-17 Travel UI

- **Party section** (`panelMode = "party"`), opened by clicking the banner or the status chip
  on a point crawl map:
  - the status line in body text;
  - `party.travelTo` rows: `{dest} by {path}` plus the time, at 14 px or more (Q18), with the
    eye-slash on hidden paths for the Director;
  - an off-path message (Director and player variants) and an empty message.
- **Party right-click menu:** the travel entries. Use a "Travel to" submenu if
  `gui.ContextMenu` supports one (check); otherwise flat `ctx.party.travel` entries.
- **Banner on point crawl maps:** `party.tooltip.travel`. A drag snaps back and shows
  `hint.dragTravel` (Q17).
- **Path right-click:** `ctx.path.place`, snapped by `PathAt` (Q4), opens the stop card:
  - the time field defaults to half (G7);
  - `dlg.stop.field` names the start end, which `dlg.stop.swap` flips;
  - the range check uses `dlg.stop.range`;
  - `dlg.stop.ok` places the Party.
- **Hidden path in Travel to (Director):** the `dlg.hiddenTravel.*` card with Reveal and
  travel, Travel without revealing, and Cancel (W1).
- **Motion:** no Party animation is added; if one ever is, it honours Reduce motion (Q27).

**Acceptance.**
- Director: travel by the list and by the menu; stop, swap, limits; hidden path both ways;
  drag snap-back.
- Player client (the user sets it up): switch off and on, hidden paths absent, secret legs
  anonymous, no Move Party here.

### V21-18 Accessibility and visual pass

Measure contrast live:
- casing on light and dark art;
- hidden paths;
- swatches;
- the Delete link and the toast Undo border.

Also check Font Size 80/100/140, Default and Warm Gold with no `THEME_ENGINE` lines, and that
every new action has a non-drag and non-hover way in.

### V21-19 Performance

With 250 pins and about 300 path segments on one map, measure:
- the pan frame time;
- the first draw;
- a refresh;
- a zoom re-layout.

Set `C.pathSegmentLimit` and record the numbers in README section 5.

### V21-20 Docs and acceptance

- **README:** behavior, architecture (with the five new files), data, acceptance.
- **This file:** the build notes.
- **IDEAS.md:** mark 9, 10, 11, 7.2 and the creation part of 7.3 as delivered.
- **The brief's status:** BUILT.
- The section 6 checks.

## 5. Out of scope

From the brief:
- hex overlay and hex mode (V2.2);
- converting a map between modes;
- paths that leave the map edge (workaround: an edge Location);
- a travel time total;
- path import;
- rest entries;
- route proposals by players;
- fog;
- planned multi-leg routes.

Any core change is also out of scope, including host gaps found while building; report those
separately.

## 6. Verification (every phase)

1. `..\dependencies\lua\bin\luac.exe -p` on each changed file, and an ASCII check.
2. `..\dependencies\check-mod.ps1 -Mod "Region Map"` must show 0 problems. Before a commit,
   also run `tools/lua-typing/check.ps1 -Changed`.
3. **Deploy:**
   - Copy the changed files (UTF-8 without BOM) to
     `C:\Users\ElderHex\codex-dev-mods\Overland Map\`, touch them, then `reload_lua`.
   - Register new files in the 3.1 order and confirm Firebase persistence.
4. **Live checks** on the Director client with `execute_lua` probes and screenshots; the
   task's acceptance is the list. Player-client checks are batched for a session the user
   sets up.
5. `git status` shows changes only under `Region Map/`.
6. Every new on-screen string traces to a V2_COPY.md id.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Inline gradients can't make the fade | Check first in V21-03. Fallback: a mask image (one uploaded asset); ask the user |
| Pattern panels cost frames on big maps | Pooling, clipping, re-layout only on zoom or a large pan, and a segment cap from V21-19 |
| `gui.ContextMenu` has no submenus | Flat travel entries |
| A partial import write fails | Stop; the Undo covers the rows written; `toast.saveFailed` |
| The mod isn't checked out | It's the prerequisite; no live check runs before it |

## 8. Build notes

**J1 measurement, 2026-10-08 (V21-00).**
- **Test images:** five generated JPEGs (grid plus texture, quality 85) in
  `C:\Users\ElderHex\overland-map-test-images\`, uploaded by the user through the Atlas New
  map card:

  | Size (px) | File | Megapixels |
  |---|---|---|
  | 1024 x 683 | 0.2 MB | 0.7 |
  | 2048 x 1365 | 0.6 MB | 2.8 |
  | 4096 x 2731 | 2.5 MB | 11 |
  | 8192 x 5461 | 9.9 MB | 45 |
  | 16384 x 10923 | 35.8 MB | 179 |

  The five test maps were deleted afterwards.
- **Upload:** the 16k image took about 60 s ("Uploading Image..." blocks the window) and
  the 8k one about 20 s. All five uploaded; nothing was rejected or downscaled, and the 16k
  image renders at full resolution.
- **Image size API:** the engine has `gui.TryGetImageDimensions(id)` and
  `gui.GetImageDimensionsCallback(id, f)`. Both return `{width, height, ppu}` with no panel,
  so V21-01 uses them instead of a probe panel. A detached panel with `bgimageStreamed` also
  fires `imageLoaded`.
- **Frame times:** sampled with a per-frame coroutine. `dmhub.BeginPerfWindow` counts only
  focused frames, and the app was unfocused, which also caps it at 30 fps (33 ms).
  - Panning at 20x zoom stayed at 33 ms for every size, including 16k.
  - Opening a map gave single 50-100 ms frames, with no size trend.
  - Pan smoothness does not limit image size.
- **Sharpness:** an image stays sharp while the zoom is under `image width / canvas width`.
  The canvas is about 1470 px in the default window and about 2400 px when Expanded on a
  2560 px screen. Screenshots at 20x matched the formula: 1024 and 2048 were visibly
  blurred, 8192 was soft, and 16384 was close to crisp.

  | Image width | Soft beyond (default / Expanded) |
  |---|---|
  | 1024 | 0.7x / 0.4x |
  | 2048 | 1.4x / 0.85x |
  | 4096 | 2.8x / 1.7x |
  | 8192 | 5.6x / 3.4x |
  | 16384 | 11x / 6.8x |
- **First load for players** (not measured: the uploads were already cached here). V2
  measured 6.3 s for an uncached 84 MP image, about 75 ms per megapixel on this machine. At
  that rate 45 MP is about 3.4 s and 179 MP about 13 s, past the 10 s Show to players
  window. GPU memory, uncompressed RGBA: 8k is about 180 MB and 16k about 716 MB.
- **Decision:**
  - Proposed: 2000 / 6000 / 10000.
  - The user picked 1500 / 4000 / 12000 (brief W5).
  - A 12000 x 8000 map is 96 MP: about 7 s for a first load here, so near the 10 s Show
    window on slower machines.
- **Seen while cleaning up:** deleting rows through `RegionMapModel.DeleteLocation` from
  `execute_lua` left the open Atlas showing the old cards until the next navigation. The
  window's `monitorAssets` did not refresh for this client's own writes made outside the
  window. The UI's own deletes refresh. Users can't reach this; it is noted for the
  V2.1 import, whose coroutine writes must call the shell refresh themselves.
- **P0 status:** done. The copy is signed off, the numbers are approved, the art spec is
  written, and the prerequisite is met.
