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

> **Deferred (2026-10-08, brief K9).** Not built until the user provides the torn-edge mask
> and the frame image ([docs/BORDER_ART.md](docs/BORDER_ART.md)). To resume: put the two
> library ids in `RegionMapConstants.borderTornMask` and `borderFrameImage` (the Settings
> tiles enable themselves), then build the items below. Soft fade and None are done (P2).

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
- **Entry point (IM7, confirmed at the start of P3):** `menu.import` in the Director's map
  right-click menu and in the open map's "..." menu.

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

**P1 / V21-01 size guidance, 2026-10-08.**
- **Changed files:**
  - Constants: the three widths.
  - Copy: `image.hint`, `toast.image.small`, `toast.image.large`, `toast.replaceImage`.
  - CanvasTools: `ImageSize`.
  - Undo:
    - Toasts carry an optional action button (`RegionMapToastAction`).
    - `Notify` takes `action = {copyId, click}`.
  - Panel:
    - `ctx.ImageHint` and `ctx.CheckImageSize`.
    - The toast gets a fourth button.
  - Session: two context fields.
  - Atlas: the size check after a new map is created, and the hint as the second line of
    the New map tooltip.
  - SidePanel: the hint under the image picker, and the check after Add map or Replace
    image.
- **Checks:** `luac -p` and ASCII pass; `check-mod.ps1` shows 0 problems.
- **Verified live (Director),** using the J1 test images still in the journal library:
  - Add map on Old Mill: the picker shows the hint, and the 1024 image gave
    `toast.image.small` with "Replace image...".
  - The toast button opened the replace picker. 16384 gave `toast.image.large`, and 4096
    gave no toast.
  - The Atlas New map tooltip shows the hint.
  - Creating a map from the 1024 image gave the small-image toast over the new map in edit
    mode.
  - Opening existing maps shows no toast.
  - Cleanup: the test map was deleted and Old Mill's map removed, so Old Mill is back to no
    map.
- **Behaviour kept from V2:** Add map and Replace image push no undo entry, as before; the
  size toast replaces nothing that had an Undo.

**P2 / V21-02 and V21-03 Settings sections and Soft fade, 2026-10-08.**
- **Gradient check:** inline gradients work, so no mask asset is needed.
  - `gui.Gradient{point_a, point_b, stops}` on a `bgimage` panel, with `bgcolor` giving the
    hue and white stops giving only the alpha (precedent: `Codex Titlescreen/AdventurePage.lua`).
  - Points are in the panel's own 0..1 box with y = 0 at the bottom.
- **Changed files:**
  - Constants: `borders`, `defaultBorder`, the two art ids (both "" for now), `fadeShare`
    0.06 and `fadeMaxWidth` 72.
  - Records: `border` on the Location class; validated as an enum when present.
  - Model:
    - `Border`, `LastBorder`, `SetBorder`; `border` accepted by `UpdateLocation`.
    - `CreateMap` and `AddMap` copy `LastBorder` (K5, K8). Replace image keeps the border.
  - CanvasTools: `CreateFade`, `SetFadeBand`, `FadeBand`.
  - Canvas: the fade panel sits right after the image, under the route, pins and Party
    (Q23). It is laid out with the image and shown only on a "fade" map.
  - Styles: the four fade strips and the border tiles.
  - Popovers:
    - Sections now run This map, Whole game, Party, Only for you (Q22).
    - "Players can add locations" moved from Party to Whole game: it is a game-wide
      setting, and the section would otherwise be empty until Phase 4.
    - Border tiles preview the open map in each look; the pick shows as an accent frame
      plus a bold name.
  - Copy: `set.map.border`, `set.map.border.hint`, `set.border.*`, `set.game`.
- **Engine notes:**
  - A tile classed `disabled` drew as active: the theme styles that class. The tiles use
    `needsArt` instead.
  - `opacity` on a panel does not pass to its children, so the art-less tiles dim their
    preview and name through `parent:needsArt` rules.
- **Checks:** `luac -p` and ASCII pass; `check-mod.ps1` shows 0 problems; no Lua errors in
  the console.
- **Verified live (Director),** on M2 test map:
  - Soft fade on all four edges at fit, zoomed in and Expanded; the band stays at 72 px when
    Expanded. Pins, labels, the route and the Party draw above it.
  - Default (mcdm) and Warm Gold: the fade follows each theme's canvas color. The theme was
    switched back afterwards.
  - Picking None gives a hard edge and stores `lastBorder = "none"`; picking Soft fade again
    stores "fade".
  - Add map on Old Mill created the map with `border = "fade"`; the map was removed again.
  - Existing maps read None until a border is picked (M2 test map is now Soft fade).
  - Torn edge and Frame show dimmed with the `set.border.needsArt` tooltip.
- **Not checked:** the 720x480 window size; the band shrinks with the image there
  (6% of its shorter side).
- **V21-04 waits for the art:** the tile check and `FadeBand` are in place; Torn edge and
  Frame drawing is not written yet.

**P3 / V21-05 JSON import, 2026-10-09.**
- **Entry point (IM7):** the user confirmed both places at the start of the phase: the
  Director's map right-click menu and the open map's "..." menu.
- **New file:** `RegionMapImport.lua`, registered after `RegionMapPopovers.lua`.
  - `CheckEntry`, `Check`, `ReadFile`: pure checks, so they can be tested without the UI.
  - `GridPositions(count, aspect)`: the grid for entries with no u/v.
  - `Create(ctx)` builds the card layer. Its data holds `start()` (the file dialog),
    `openFile(path, mapId)` (what the dialog calls) and `close()`. The plan named this
    `Start(ctx)`; the layer shape follows `ctx.Confirm`.
- **Changed files:**
  - Constants: `importSpacing` 0.11, `importRowShare` 0.45, `importBatch` 10,
    `importWait` 20 s.
  - Copy: manifest section 20, plus the `.one` forms and `dlg.close`.
  - Model: `CreateLocation` takes an optional name, so an import does not follow the create
    with a rename (a second revision the undo step would not match).
  - CanvasTools (`MapMenu`) and SidePanel (`MenuEntries`): `menu.import`.
  - Panel: the layer sits under the confirm layer; Esc closes it. Session: `ImportLocations`.
  - Styles: the card (480 wide) and its scrolling list.
  - Docs: [docs/IMPORT_FORMAT.md](docs/IMPORT_FORMAT.md) and
    [docs/import-example.json](docs/import-example.json).
- **Engine notes:**
  - `dmhub.ParseJsonFile` returns 1-based arrays and drops nulls. Invalid JSON and an empty
    file both return nil without calling the error callback, so `ReadFile` reads the text
    first to tell them apart.
  - With several creates to one table in flight, a create's success callback can fire
    before its row is in the local table. Writes that need the row (`SaveDetails`,
    `SaveDirectorNote`) then fail with "permission". The first build stopped after 10 rows
    this way. Commit now creates a batch, waits for the answers, waits until
    `Model.GetLocation` reads every new row, and only then writes descriptions and notes,
    all from the coroutine.
  - A list taller than its vscroll box is centered in it unless it has `valign = "top"`;
    the card opened with its summary line scrolled out of view until that was set.
- **Grid:** names collided at Fit with square spacing, since a pin with its name is wider
  than tall. 0.11 of the width between columns and 0.45 of that between rows (on screen)
  keeps "Import Test 14"-length names apart at Fit. Imported pins can still land on
  existing ones; the preview says to unlock pins to move them.
- **Checks:** `luac -p` and ASCII pass; `check-mod.ps1` shows 0 problems; no Lua errors in
  the console.
- **Verified live (Director),** on M2 test map, with the test files in
  `C:\Users\ElderHex\overland-map-test-imports\`, opened through `openFile`:
  - Duplicates and skips: the preview lists the reasons per entry and the names already on
    the map. Esc closes the card.
  - 24 entries: all 24 created, with 8 descriptions and 6 Director notes, as one undo entry.
    The toast's Undo and "Undo last change" each removed all 24.
  - Over the limit (260 against room for 247), invalid JSON, empty, and all skipped: each
    shows its card with Close only.
  - 40 skipped entries: the list scrolls inside the card, opens at the top, and reopens at
    the top after being scrolled.
  - `docs/import-example.json` passes the checks: 4 entries, none skipped.
  - "Import locations..." shows in the map right-click menu and the open map's "..." menu.
  - The map was left with its 3 original Locations.
- **Not checked:** the Windows file dialog itself. It is native and can't be driven over
  the bridge; `start()` passes the picked path to the same `openFile` the tests used.

**P4 / V21-06 to V21-10 point crawl foundations, 2026-10-09.**
- **New files**, registered in this order:
  - `RegionMapPaths.lua` after `RegionMapLog.lua`: the path index, the viewer filter (H1),
    reads, the types and time unit, the wording, writes and the cascade helpers.
  - `RegionMapPathLayer.lua` after `RegionMapCanvasTools.lua`: drawing, labels, badges and
    the hit test. `Create()` takes no arguments; `Sample(width)` draws the line samples.
  - `RegionMapPathPanel.lua` after `RegionMapSidePanel.lua`: the read panel and the
    Director's path menu (`MenuEntries`).
- **Registration:** the first tries failed with HTTP 502 ("Could not read the CodeMod
  configuration") and then 409 ("Permission denied"). The app had started without reaching
  Firebase authentication. A restart while the files were unregistered broke the window
  (`RegionMapPathLayer` uninitialized in `RegionMapCanvas`). After the restart the login had
  recovered, and all three registered on the first try.
- **Changed files:**
  - Constants: `modes`; path, type and time limits; `watchesPerDay` 6; the patterns,
    widths and colours; casing, halo and badge sizes; `starterPathTypes`; `pathPieceLimit`
    2500 (a placeholder until V21-19 measures it).
  - Records: `mode` on the Location (an enum when present), `RegionMapPathRecord`,
    `PathsTable()`, `IsValidPathFields`.
  - Model:
    - `CreateMap` and `AddMap` take `mode`; only "pointcrawl" is stored. `IsPointCrawl`.
    - `WriteStateKey(key, value)` writes one key of the state document with a per-key
      revision in `stateMeta`; its undo steps carry `state` and `stateBefore`, and
      `Revert` and `StepCurrent` handle them.
    - `MoveToMap`, `DeleteLocation` and `RemoveMap` add path-hide steps to their batch;
      `RemoveMap` also clears `mode`, so Add map can choose again.
  - Undo: rebinds also match on `state`.
  - Session: `ModeChoice`, `selectedPathId`, `newMapMode`, the `pickMode` and `path` panel
    modes.
  - Atlas: the two-step New map card; the "Point crawl" chip.
  - SidePanel: the `pickMode` step for Add map; path counts in the Delete, Remove map and
    Move to map confirms; the chip in the map meta.
  - Canvas: the path layer after the fade; path hover, click and right-click when no tool is
    active.
  - Panel: the path panel; Esc closes it; the `hint.pointcrawl.empty` banner.
  - Popovers: Whole game gains the time unit and the path types.
  - Styles: `PathStyles()`. Copy: sections 18, 21 and 22.
- **Changed from the task text:**
  - The Atlas card's step 1 has no Cancel: it is the card's resting face, so there is
    nothing to cancel. The side panel's `pickMode` step has Cancel, and both image steps have
    Back.
  - The "Point crawl" chip sits on the Atlas card's thumbnail corner, not in the meta row.
    The meta row was already full: count, "Party here" and "Not shared" would overflow the
    card.
  - `path.waits` replaces the "Revealed" meta text when an end is hidden, instead of a
    second line under it that repeated "Revealed".
- **Fixes found while verifying:**
  - The New map card was centred in its box and 16 px taller than the map cards: `minHeight`
    does not include padding and border even with `borderBox`. Both steps now fit the
    standard card height, with `valign = "top"`.
  - The type editor in Settings was built before it had a parent, and the engine warned. It
    now lives in the types list from the start, collapsed until a type is edited.
  - "Delete type" sat tight under the width segments: 8 px gap.
- **Checks:** `luac -p` and ASCII pass; `check-mod.ps1` shows 0 problems; no Lua errors in
  the console.
- **Verified live (Director),** on a new "PC test" map (6 pins, 7 paths seeded with
  `CreatePath`, one per starter type plus a hidden road with a bend):
  - **Map kind:** both entry points, Back and Cancel. M2 test map still reads as free. The
    Atlas chip and the side panel chip show. The empty-map hint shows on a point crawl map
    with no Locations.
  - **Drawing:** every pattern at fit and at the deepest zoom, where dashes keep their
    on-screen size. Casing under each mark. A hidden path draws faded with an eye-slash per
    segment. The selected path has a halo.
  - **Labels:** on hover and selection; Show names shows all of them. The label sits at the
    middle of the longest leg on screen.
  - **Wording:** "1 day and 2 watches"; "3 watches from Stonehold, 5 watches from
    Ashwater"; "1 day, from Ashwater to Mirefen only"; "Underground: Old Quarry - Mirefen"
    for an unnamed path; "No type" after its type is deleted.
  - **Hit test:** a click 10 px off a line selects it. Right-click gives Hide from players
    and Delete. A pin under the cursor wins over a path.
  - **Visibility:** hiding gives the toast, and undo reverts it. View as player drops the
    hidden path and the path to a hidden pin. The player's path panel has no visibility
    line, menu or note.
  - **Path panel:** title, type chip with its line, ends, time, description, the note
    section, and the waits line on the path to Hidden Grove. Esc closes it.
  - **Cascades:**
    - Deleting Mirefen asked "This also deletes 3 paths."; the toast's Undo brought back the
      pin and all 3 paths, the hidden one still hidden.
    - Remove map on Stonehold's point crawl sub-map ("This also deletes 1 path.") cleared
      the image, the kind, both pins and the path; undo restored all of them.
    - Move to map took Hidden Grove's path off the map; undo brought it back.
  - **Settings:** Days and Watches relabel every path. A colour change redraws at once,
    with a tooltip and the check mark. Undo restores it. Adding a type opens its editor. The
    same-look warning shows. Deleting an unused type gives a toast and no confirm. Deleting
    Trail asked "2 paths use it" and its path drew as "No type"; undo restored Trail in its
    place.
- **Not done yet:**
  - Labels are not decluttered by zoom; Show names shows every path's label.
  - Casing contrast was not measured (V21-18), and the 250-pin performance run (V21-19)
    has not been done.
  - The player client itself was not checked; View as player was.
- **Test data left in the game:** the "PC test" map (shared) with its pins and paths, and
  Stonehold's sub-map with 2 pins and 1 path.

**P5 / V21-11 to V21-14 path editing, 2026-10-10.**
- **New file:** `RegionMapPathTool.lua`, registered after `RegionMapPathLayer.lua`. It holds
  the Path tool's steps, Connect (shared by the tool and Connect to...), Redraw line and the
  bend handle edits. Registration first failed with HTTP 409 "Permission denied" (the same
  Firebase login failure as in P4); after the user restarted the app it went through.
- **Changed files:**
  - Constants: `firstPathType`, `firstPathTime`, `pathParallelOffset`, the handle sizes.
  - Session: the `pathEdit` and `pickPathEnd` panel modes, the `path` and `redraw` tools,
    `pathDraft`, and `LastPathStyle` / `RememberPathStyle` (Q8, stored per Director).
  - Paths: `CountJoining` (Q9), `SaveStatus`.
  - PathLayer: a non-sliding top layer with the draft line, the bend discs and the "+"
    handles; `HandleAt`, `HandlePoints`. A path's label hides while its handles show,
    because the middle "+" sits where the label would.
  - Panel: the toolbar button, tool and Esc wiring, `SelectPath(id, "pathEdit")`, and the
    check that drops `pickPathEnd` when the pin can no longer be connected.
  - Canvas: clicks, right-clicks and Backspace go to the tool; handle drag with one write on
    drop.
  - PathPanel: the edit form with autosave, the Connect to... picker, the Location's
    Paths section (`PathsSection`) and `CanConnect`.
  - SidePanel: `menu.connect`, the Paths section in read mode, and it stays closed while
    `pickPathEnd` shows the picker.
  - Styles: handles, path rows, the time field, the danger hint, the chosen type row.
- **Changed from the task text:**
  - Bend and Redraw edits reuse the `toast.moved` string ("{name} moved"). A new path gives
    no toast: its edit form opening is the sign, and the undo stack still holds it.
  - A typed time keeps a tenth of a watch, the finest the time wording shows. In days
    mode "0.17" stores 1 watch, not 1.02.
  - Connect to... closes the side panel at once; the new path's form opens when its row is
    readable.
- **Fixes found while verifying:**
  - The first right-click after any drag was lost. The engine sends no click event after a
    drag release, so the drag stayed in `state.lastDrag` and the right-click took it for its
    own. Right-clicks now ignore a left-button drag. This was in V2 too: a right-click on a
    pin just after dragging another one did nothing.
  - The time field and its unit spread across the row; both now sit left.
  - The chosen type row looked like a hovered one; its name is now bold.
  - The search fields (the picker's and the toolbar Search's, the latter since V2) and the
    text areas ran past the panel padding. The theme's `input` rule adds `hpad = 10` outside
    the width, and on `gui.SearchInput` and `gui.TextEditor` `borderBox` does not take it
    back. Neither inline `borderBox` nor an unpadded wrapper helped. The widths are now
    `100%-28` (search) and `100%-20` (text areas), measured live, which also fixes the
    Location form.
  - The hidden path's row text sat left of the others; its label is now `halign = "left"`.
- **Panel pan (user decision, 2026-10-10):** with a side, path or log panel open, the
  camera may pan the map left by the panel's width, so a pin under the panel can be
  reached even at fit. `CalculateImageLayout` takes `rightInset`; the shell keeps it in
  `ctx.data.panelInset` (0 when no panel is open, or when a narrow window's panel covers
  everything) and relays out when it changes. Selecting a pin under the panel now pans it
  clear through `keepVisible`, which could not move the camera at fit before. When the
  panel closes, the camera clamps back.
- **Deploy:** the app's file watcher can miss a copy, and a reload then runs the old code.
  `Player.log` shows a "Local file changed" line for each file it saw. Touching the
  deployed files triggers it again; `debug.getinfo` on a changed function confirms what is
  live.
- **Checks:** `luac -p` and ASCII pass; `check-mod.ps1` shows 0 problems; no Lua errors in
  the console after the reload.
- **Verified live (Director), on the PC test map:**
  - **Path tool:** Kell's Ferry, a map click, Hidden Grove made a Road with 1 bend at 1 day.
    The form opened and the tool stayed on. The draft line follows the pointer.
  - **Right-click** drops the last bend. **Esc** once drops the draft and keeps the tool, and
    a second Esc turns it off.
  - **Bend handles:** hidden while pins are locked. Once unlocked, a bend drag moved the bend
    with one write and the toast; dragging a "+" added a bend; right-clicking a bend removed
    it.
  - **Paths section:** Hidden Grove lists "Kell's Ferry by Road - 1 day" and "Stonehold by
    Druid way - 2 watches", with Connect to....
  - **Connect to... using only the keyboard:** the search had focus, typing "mire" left
    Mirefen, and Enter made "Road: Hidden Grove - Mirefen" and opened its form.
  - **Edit form:**
    - The name autosaved and the write was confirmed; the title changed.
    - Trail saved at once, and the next path's style became Trail.
    - "abc" showed the range line and was not sent; "1.5" days saved as 9 watches ("1 day
      and 3 watches").
    - Different time showed "Time from Mirefen".
    - Esc returned to the read view, which showed all of it.
  - **Redraw line:** from the "..." menu. The banner names the end pin; the new bend saved
    with "Fen Causeway moved", and the toast's Undo put the old line back.
- **Verified after the fixes (second reload):**
  - **Panel pan:** at fit, selecting Mirefen (under the panel) panned it clear. With a path
    panel open, a drag slid the map left until its right edge met the panel; closing the
    panel brought it back to centre.
  - A path's label hides while its handles show.
  - A right-click on a new bend, straight after the drag that made it, removed it.
  - The chosen type row is bold; the time rows sit left; the search fields and text areas
    line up with the other fields; the hidden path row lines up.
  - **Delete and undo:** "Fen Causeway deleted" with Undo; undo restored every field.
  - **Q9:** a second path from Hidden Grove to Mirefen bowed out beside Fen Causeway. It
    copied the last style (Trail, 1.5 days).
- **Not verified:** Backspace while drawing. The bridge's virtual keys do not reach
  `dmhub.KeyPressed` (arrow keys read false too). It calls the same function as
  right-click, which works.
- **Test data added:**
  - "Fen Causeway" (Trail, Hidden Grove - Mirefen, 1.5 days, different way back).
  - An unnamed Trail from Hidden Grove to Mirefen (the Q9 offset test).
  - A Road from Kell's Ferry to Hidden Grove with one bend.

**P6 / V21-15 to V21-17 travel and the leg log, 2026-10-10.**
- **New files**, registered in this order (the first tries failed with HTTP 502, the same
  Firebase login failure as before; after the user restarted the app both went through):
  - `RegionMapTravel.lua` after `RegionMapPaths.lua`: the travel model.
  - `RegionMapPartyPanel.lua` after `RegionMapPathPanel.lua`: the Party section, the
    Party's "Travel to" menu, the hidden-path question and the stop card. The plan put
    these in the path panel; they got their own file so it stays under 800 lines.
- **Changed files:**
  - Copy: manifest sections 23 and 24. `leg.by` holds its leading space (" by {path}").
  - Records: log kinds `leg` and `stopped`; the new log fields have type defaults (a
    game type raises on a field a row never had) and are checked when the kind uses them.
  - Model:
    - The Party gains `pathId`, `pathFrom`, `spent`. A stopped Party's u/v are worked out
      from the path every read (Q13); a player who can't see the path sees a plain
      position. `PartyStatus` adds "onPath".
    - `WriteParty` takes the path fields, `travel` and `noLog`. On a point crawl map players
      move only with `travel` (Q16).
    - `PlaceParty` takes a pin id (Q16).
    - `PartyOffPaths` + `MovePartyOff`: the cascades (`DeletePath`, `DeleteLocation`,
      `MoveToMap`) move a Party stopped on a removed path to its nearer end. The target is
      read before the batch hides rows, since hidden rows leave the index.
  - Paths: `Points(path)`; `DeletePath` moves the Party off.
  - Log: `RecordLeg`, `RecordStop`, `HideStep`, `Newest`, `ShowsPath`. Players see a
    leg or stop only when both ends are visible; its path name and line only when it was
    not secret and the path is visible to them now (a deleted path keeps its name).
    Entries store `pathName`, so renaming or deleting a path keeps the history.
  - LogPanel: `LegText` (one wording, Q19) and the leg and stop lines.
  - Panel: `ctx.ShowParty`, `ctx.StopOnPath`; the "party" panel mode (Esc closes it, it
    closes when the Party leaves the open point crawl map); the status chip opens it;
    `ctx.Confirm` takes an `alternate` button (W1); the stop card layer.
  - Canvas: on a point crawl map a banner click opens the Party section, a drag snaps back
    with `hint.dragTravel` (Q17), right-click shows the Travel to menu; the map menu gets the
    pin near the click.
  - CanvasTools: `MapMenu` places the Party "at" a pin within the snap radius on point
    crawl maps (Q16).
  - PathPanel: `ctx.path.place` first in the path menu; `ParseTime` and `TimeInputText`
    shared with the stop card.
  - SidePanel: "Move Party here" on a point crawl map is the Director's and logs `placed`.
  - Session and Styles: the new mode, context fields and the travel row rules.
- **Changed from the task text:**
  - `gui.ContextMenu` has submenus, so the Party menu is one "Travel to" submenu. The
    entries are "{dest} by {path} ({time})"; the core shortcut slot hugged the text in the
    same colour, so the time is in brackets (manifest 25.7, signed off 2026-10-10).
  - Leaving from partway the toast is the log line, "Traveled on to ..." or "Turned back to
    ..." (manifest 25.8, signed off 2026-10-10).
  - Turning back on a path whose other way is "Not possible" is not offered (W2).
  - A stop replaces the arrival only for a whole-path leg from the same end (Q14). After a
    leg from partway, the stop is a new entry.
  - Lengths along a path are measured in image units, so on a long, narrow image the
    stopped Party's spot is slightly off the true half; it is always on the line.
  - A reveal that fails while travelling leaves the leg secret instead of failing the travel.
- **Fix found while verifying (V2 bug):** "Place Party here" toasted "{party} placed on
  PC test": `toast.partyPlaced` was never given the Party's name.
- **Checks:** `luac -p` and ASCII pass; `check-mod.ps1` shows 0 problems; no Lua errors in
  the console.
- **Verified live (Director), on the PC test map:**
  - **Q16:** "Place Party here" just above Kell's Ferry put the Party at the pin, logged as
    placed.
  - **Party section:** the banner click opens it, showing "Party is at Kell's Ferry" and
    three rows (dest by path, time underneath).
  - **Travel and undo:** Stonehold by King's Road gave the toast and a route along the
    road. Undo put the Party back and removed the leg.
  - **Menu:** the Travel to submenu travelled to Hidden Grove and closed.
  - **Stop card:** right-click on the Road, "Place Party on Road". It counted from Kell's
    Ferry (where the leg began) at 0.5 of 1 day. "10.5" showed the range line, and the swap
    button counted from Hidden Grove.
  - **Q14:** placing at 0.5 day replaced the arrival with "Stopped on Road, 3 watches from
    Kell's Ferry". The banner sat on the road at half its length; the chip read "Party on
    Road".
  - **Going on:** "Traveled on to Hidden Grove by Road - 3 watches", with the route starting
    at the stop.
  - **Turning back:** from 3 watches out on Underground, "Turned back to Mirefen by
    Underground - 3 watches".
  - **W1:** Smugglers' cut showed the eye-slash; the card offered all three buttons.
    - Travel without revealing: the path stayed hidden. View as player showed "Traveled
      from Stonehold to Mirefen - 1 day and 4 watches" with no line, and dropped the legs
      through hidden Hidden Grove.
    - Reveal and travel: one undo entry (Party, reveal, log); undo hid the path again.
  - **Q13:** deleting Underground with the Party 7 of 9 watches from Mirefen moved it to
    Old Quarry; undo restored the path and the Party on it.
  - **Q17:** a banner drag snapped back with the hint and wrote nothing.
  - **Options:** View as player with the switch off says "Only the Director can move
    Party.". With it on, Mirefen offers only Old Quarry by Underground. The one-way Sea lane
    shows from Ashwater only.
- **Not verified:**
  - A real player client (batched for a session the user sets up).
  - The side panel "Move Party here" button on a point crawl map (code path shared with the
    tested `placed` write).
  - Enter in the stop card's field does nothing; Place Party is a click.
- **Seen, not changed (V2):** in a player's log, entry lines without the Director's "..."
  button sit a little right of their meta line.
- **Test state:** the Party is at Ashwater on PC test; the log holds the test legs.

**P7 / V21-18 to V21-20 finish, 2026-10-10.**
- **Changed files:**
  - PathLayer: the label declutter (Q11, left open in P4). With Show names on, labels are
    placed longest line first, and one shows only when its line on screen is at least 0.8 of
    its width and it clears the pins, their names and the labels already placed. Hover and
    selection always show. Widths are estimated (0.52 em a character), so nothing waits a
    frame to measure. Drawn paths keep their end pins' names for this.
  - Constants: `pathLabelSize`, `pathLabelCharWidth`, `pathLabelPad`, `pathLabelFit`,
    `pathLabelGap`; `pathHiddenOpacity` 0.6 (was an inline 0.45); the `pathPieceLimit`
    comment now holds the F4 numbers (the value stays 2500).
  - Styles:
    - Warning text (`regionMapHint danger`, `regionMapStateLine danger`,
      `regionMapLink danger`) is `@fgStrong` with a 3 px `@danger` bar at its left. This was
      `@danger` text.
    - The route dots get a 1.5 px `@bg` ring.
  - PartyPanel: Enter in the stop card's field places the Party, like the button (P6
    left this open).
- **V21-18, measured (WCAG ratios; art samples light #E8DCC0, mid #7A9A50, dark #2A2A2E,
  sea #5C88A8):**
  - Line against its casing: 6.5:1 (rust) to 15.8:1 (parchment). Line or casing against
    the art: 4.6:1 or more on all four samples.
  - Hidden paths: at 0.45 opacity the faded line read 2.3-2.5:1 against its casing for
    blue, ochre, violet and rust. At 0.6 every colour reads 3.1:1 or more and still reads as
    faded (2.1:1 or more against the full colour). The eye-slash badge still carries
    "hidden".
  - Swatches against `@bg`: 6.2:1 or more, except Ink at 1.0-1.1:1, which has the
    `@fgStrong` ring (Q26).
  - `@danger` text on `@bg` is 4.0:1 (Default), 3.7:1 (MCDM) and 3.4:1 (Warm Gold), so
    "Delete type" and the range lines could not meet 4.5:1 in that colour. No stronger theme
    token exists. They now follow the DefaultStyles.md `multiselectChipRemove` pattern:
    readable text, with the red on a non-text mark that needs only 3:1 (and gets 3.4:1 or
    more).
  - The toast's Undo (`@accent` on `@bg`): 14.7:1, 6.0:1 and 5.8:1. Its box border is
    `@border`: 6.8:1 or more.
  - Font Size 140 (the host zooms the whole window) and 80: labels and lines scale, and the
    declutter holds. The Party section and the stop card fit at 80. Font Size was restored
    to 100.
  - Default, Warm Gold and MCDM: no `THEME_ENGINE` lines and no Lua errors. In Default the
    route dots (`@accent`, parchment) vanished on a Road, hence the ring.
  - Non-drag and non-hover routes: bends have Redraw line; travel has the list and the menu;
    labels have Show names; paths are listed in a Location's panel; hidden is a badge, not a
    colour.
- **V21-19:** numbers in README section 5.
  - **Method:** 244 test pins and 150 test paths (one bend each) were joined to the real
    rows in memory. This was done by swapping `Model.Index`'s `Locations` upvalue and
    `RegionMapRecords.PathsTable`, as V2 did for pins. The path layer's API was wrapped with
    timers by reopening the window. Everything was restored and Lua reloaded; nothing
    reached the cloud.
  - **Cap:** creating a piece is engine work (0.14 ms a panel in an isolated test, the same
    with or without a class), so the first draw is bounded by the cap, not by our Lua. The
    cap stays at 2500: the dense test map reaches it only at the deepest zoom.
  - **Frame sampling:** the unfocused app caps at 30 fps, and pans through the bridge showed
    the same 50-100 ms bursts with or without the test paths. Those bursts are not the path
    layer.
- **V21-20:** README (behavior, architecture with all 25 files, data, performance,
  acceptance, open decisions), IDEAS.md (9, 11, 7.2 and the creation part of 7.3 delivered;
  10 partly), the brief's status (BUILT, with the exceptions).
- **Checks:** `luac -p` and ASCII pass; `check-mod.ps1` shows 0 problems; no Lua errors in
  the console; `git status` shows changes only under `Region Map/` (plus the untracked
  `.codex/`, `.mcp/` and `output/` that were there before).
- **Verified live (Director):**
  - Show names at Fit: 7 of 10 labels, none overlapping. One zoom step brought back
    "Trail - 1 day and 3 watches".
  - "Delete type" and the stop card's range line show the new look.
  - Enter with "40" in the stop card shows the range line and writes nothing.
  - Route dots in Default ring on the Road.
- **Not verified:** the player-client list in README section 6.
- **Seen, not changed:** while these checks ran, the app was also in use. The Party traveled
  Ashwater to Mirefen by Sea lane and on to Old Quarry by Underground (20:31-20:32). The
  checks wrote no game data. The performance run closed and reopened the Overland Map window
  twice; after the final reload it was closed, with the map editor panels open, and it was
  left that way.
