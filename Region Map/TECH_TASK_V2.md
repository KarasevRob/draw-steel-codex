# Region Map V2 - Technical Task

Status: READY FOR BUILD. Written 2026-10-05.
Source of truth: [docs/V2_BRIEF.md](docs/V2_BRIEF.md) (locked) and
[docs/V2_COPY.md](docs/V2_COPY.md) (signed off). Where this file and the brief disagree,
the brief wins; fix this file. Decision IDs (D.., R..) and copy IDs (`tb.search`, ...)
refer to those two documents. V1 file and line references are to the 2026-10-05 tree.

## 1. Scope and constraints

V2 replaces the V1 UI and data model of the Region Map mod: one Location object, a
canvas-first window, the Party as a draggable banner, Show to players, ruler and session
log. Fog, hex overlay and travel paths are V2.1 and out of scope.

| Constraint | Meaning |
|---|---|
| Zero core changes | Edit only files in `Region Map/`. No edits to `DocumentSystem/`, `DMHub Core UI/`, `DMHub Game Hud/`, `Definitions/`, `DefaultStyles.lua`, `main.lua`, `deploy.ps1`, `.gitignore`. |
| Opt-in mod | Feature-detect host APIs once in `RegionMap.lua` (V1 `MissingHostApis`); guard every undocumented host detail with `rawget`/`pcall`. |
| File registration | New files via `mcp__dmhub__register_lua_file` in the order of section 3, confirm Firebase persistence. Removing a file from the CodeMod is done by the user in the in-app mod tools. Never edit `main.lua`. |
| Project standards | `CLAUDE.md`, `UI_BEST_PRACTICES.md`, `ThemeEngine.md`, `DefaultStyles.md`, `STYLE_GUIDE.md`; ASCII-only Lua; `borderBox = true` with padding; style rules only in `RegionMapStyles.lua` through `ThemeEngine.MergeStyles`. |
| Typing | Every new or rewritten file checks clean (0 problems). |
| Copy | Every user-facing string comes from `RegionMapCopy.lua`, keyed by the manifest ID. No literal UI strings elsewhere. |
| V1 data | Dropped (decision 8.3, 2026-10-06). V2 neither reads nor migrates V1 maps, labels or tombstones; their rows stay in the game data, unused. There is no rollback to V1. |
| DMHub process | Never start, stop or restart DMHub without asking the user first. |
| Tests | Mod-local unit tests stay skipped (V1 RM-21 decision). Verification is live (section 6). |

## 2. Engine facts this task relies on

From the 2026-10-05 engine checks (brief section 11b) and the V1 build:

| Fact | Use |
|---|---|
| Rail window geometry is written with `selfStyle.width/height`, `x/y`, then the `resize` event on `dialog.data.resizePanel` (`RegionMap.lua` `FitHostWindow`) | Expand (V2-17) |
| Play area = documents layer size minus rails (40 wide, inset 12) and top inset 64; rail windows are zoomed by `PanelDocument.WindowUIScale()` | Expand target size, Font Size scaling |
| `transitionTime` + `easing` on style rules; `imageLoaded` with `bgimageWidth/Height`; V1 streams images with `bgimageStreamed` | Map transitions (V2-08) |
| `dmhub.SetAndUploadTableItem` writes are not on the engine undo stack | Mod-side undo (V2-05) |
| Panels rotate around their pivot (`rotate`); no image tiling | Route and ruler lines (V2-14, V2-15) |
| `hover`/`dehover`, `rightClick` + `gui.ContextMenu`, `doubleclick`, `captureEscape` + `escapePriority` | Toasts, menus, rename, Esc order |
| A left-drag on a panel the engine considers draggable moves it physically; V1 polls the mouse for panning (`RegionMapCanvas.lua` `PollLeftPan`) | Party and pin drags use the same polled approach |
| Table rows sync to every client; hiding is UI-only (V1 README section 4, accepted) | Hidden Locations and Director notes stay UI-hidden only |

## 3. Target architecture

### 3.1 Files (load order = CodeMod order)

| # | File | State | Responsibility |
|---|---|---|---|
| 1 | `RegionMapConstants.lua` | Update | Names, limits, metrics, timings (V2-01) |
| 2 | `RegionMapCopy.lua` | New | Every manifest string and `Copy.T(id, args)` (V2-02) |
| 3 | `RegionMapJournal.lua` | Keep | Journal access and opening |
| 4 | `RegionMapRecords.lua` | Update | Record types (V2 Location, log entry, details and notes), safe reads, validation, uploads (V2-03) |
| 5 | ~~`RegionMapMigration.lua`~~ | Removed | Cut with V2-04 (decision 8.3); removed from the CodeMod and the repo 2026-10-08 |
| 6 | `RegionMapModel.lua` | Rewrite | Location tree, permissions, visibility, writes, Party, settings, preferences (V2-03) |
| 7 | `RegionMapUndo.lua` | New | Undo entries and the toast queue (V2-05) |
| 8 | `RegionMapLog.lua` | New | Session log entries, merging, route points, cap (V2-15) |
| 9 | `RegionMapStyles.lua` | Rewrite | V2 rules (V2-20) |
| 10 | `RegionMapSession.lua` | Update | Context type, local view state, Esc layers, last-used pin style (V2-06) |
| 11 | `RegionMapCanvasTools.lua` | Rewrite | Add, Move, ruler, scale calibration tools (V2-12, V2-14) |
| 12 | `RegionMapCanvas.lua` | Rewrite | Image, pins, Party, route, camera, drags, transitions (V2-07, V2-08, V2-09) |
| 13 | `RegionMapSidePanel.lua` | New | Location panel read/edit and "..." menu (V2-10) |
| 14 | `RegionMapAtlas.lua` | New | Atlas gallery and New map (V2-11) |
| 15 | `RegionMapPopovers.lua` | New | Search and Settings popovers (V2-13, V2-16) |
| 16 | `RegionMapLogPanel.lua` | New | Session log panel (V2-15) |
| 17 | `RegionMapPresent.lua` | Rewrite | Show to players send/receive (V2-18) |
| 18 | `RegionMapPanel.lua` | Rewrite | Shell: breadcrumb, toolbar, camera controls, status, banners, toasts, layout (V2-06) |
| 19 | `RegionMap.lua` | Update | Capability check, registration, host adapter, Expand (V2-17) |

No file over about 800 lines. Components get a `RegionMapContext` and talk through events
on their root panel (V1 pattern, `RegionMapSession.lua`).

**User steps in the in-app mod tools** (the bridge cannot unregister): remove
`RegionMapLocationCard.lua`, `RegionMapLibrary.lua`, `RegionMapMigration.lua`, `Main.lua` and
`RegionMapViews.lua` from the CodeMod once the replacements are registered and loading; then
delete the files. Done 2026-10-08 (see section 7b, "Cloud cleanup").

### 3.2 Data

| Storage | V2 contents | Notes |
|---|---|---|
| `RegionMapLocations` (new table) | One row per Location (3.3) | V2 writes only here and in the tables below |
| `RegionMapLocationDetails` (V1 table, kept) | Description and journal link, keyed by Location id | Same row format as V1 (`labelId` = Location id) |
| `RegionMapLocationDirectorNotes` (V1 table, kept) | Director notes, keyed by Location id | Same, kept because it works |
| `RegionMapLogEntries` (new table) | Session log entries (3.4) | Capped (V2-15) |
| `regionMapState` document | `party` gains `locationId`; new `partyName`, `partyImageId`, `playersCanAddLocations` | `schemaVersion = 1`. A V1 `party` points at a V1 map id, so it reads as "not placed" |
| `regionmap:preferences` setting | Last map, cameras, Show names, Reduce motion | Per user and game |
| `RegionMapRecords`, `RegionMapLabelRecords`, `RegionMapTombstones` (V1) | Not read (decision 8.3) | Left in the game data, unused |

### 3.3 Location record

```lua
--- One place in the Region Map tree. A Location may have a pin on its parent's map
--- and/or its own map image. Top-level Locations (parentId == "") are the Atlas and
--- always have an image.
--- @class RegionMapLocationRecord: GameType, RegionMapAudit
--- @field new fun(o?: table): RegionMapLocationRecord
--- @field id string V1 map or label id when migrated, else a new GUID
--- @field schemaVersion integer 1
--- @field parentId string "" for top-level
--- @field name string 1..80 characters, one line
--- @field u number 0..1 on the parent's map; ignored for top-level
--- @field v number
--- @field pinStyle "iconName"|"plate"|"iconOnly"
--- @field importance "major"|"normal"|"minor"
--- @field icon string curated icon key, library image id, or ""
--- @field visibility "hidden"|"revealed" pin visibility to players
--- @field imageId string "" when the Location has no map
--- @field imageRevision integer bumps on Replace map image; camera keys include it
--- @field mapShared boolean players may open this Location's map
--- @field scale nil|{u1: number, v1: number, u2: number, v2: number, distance: number, unit: "mi"|"km"}
--- @field pace nil|number travel distance per day in the scale's unit
--- @field ownerId string
--- @field ownerName string
--- @field createdByDirector boolean
--- @field revision integer
--- @field hidden boolean soft delete
RegionMapLocationRecord = RegisterGameType("RegionMapLocationRecord")
RegionMapLocationRecord.tableName = C.locationTableName
```

Validation (`IsValidLocation`, same style as V1 `IsValidLabel`): schema, id, name, enums,
`u`/`v` in 0..1 for children, `imageId` non-empty for top-level, `imageRevision` positive
integer when `imageId ~= ""`, `parentId` resolves to a valid Location with an image, no
cycles (walk up at most `C.maxDepth` levels).

### 3.4 Log entry record

```lua
--- One automatic Party entry in the session log (D14d, R8).
--- @class RegionMapLogEntryRecord: GameType, RegionMapAudit
--- @field new fun(o?: table): RegionMapLogEntryRecord
--- @field id string
--- @field schemaVersion integer 1
--- @field kind "arrived"|"traveling"|"travelingOn"|"placed"
--- @field mapId string the map the Party is on
--- @field locationId string arrived: the Location; traveling: the one it left; else ""
--- @field route {u: number, v: number}[] Party positions on mapId, oldest first, merged legs appended
--- @field mergedCount integer number of traveling drops merged into this entry
--- @field at any ServerTimestamp of the last change
--- @field byId string
--- @field byName string "the Director" is rendered for Director writes
--- @field note string Director annotation, may be ""
--- @field revision integer
--- @field hidden boolean
RegionMapLogEntryRecord = RegisterGameType("RegionMapLogEntryRecord")
RegionMapLogEntryRecord.tableName = C.logTableName
```

## 4. Task list

Priority: **P1** = needed for a usable V2, **P2** = needed before release, **P3** = polish.

| ID | Pri | Title | Brief |
|---|---|---|---|
| V2-00 | P1 | Verify player table writes first | V1 open decision |
| V2-01 | P1 | Constants | - |
| V2-02 | P1 | Copy module | V2_COPY |
| V2-03 | P1 | Location records and model | D4, D9, R1, R4, R11 |
| ~~V2-04~~ | - | ~~V1 migration~~ - CUT (decision 8.3) | ~~D4e~~ |
| V2-05 | P1 | Undo and toasts | D7c, R3, R9, 11b |
| V2-06 | P1 | Shell: layout, breadcrumb, toolbar, Esc, banners | D8b, D12, R2, R6 |
| V2-07 | P1 | Pins on the canvas | D5, D6d, D9c, R9 |
| V2-08 | P1 | Map navigation and transitions | D8, 11b |
| V2-09 | P1 | Party marker and moves | D4d, D7b, D11, R3, R12 |
| V2-10 | P1 | Side panel | D6, D7d, R1, R4, R10, R11, R12 |
| V2-11 | P1 | Atlas | D8b, D12c |
| V2-12 | P1 | Create and move Locations | D7a, D7b, R6, R10, R12 |
| V2-13 | P2 | Search | D12b, R9 |
| V2-14 | P2 | Ruler and map scale | D14c, R7 |
| V2-15 | P2 | Session log and route | D14d, R8, R9 |
| V2-16 | P2 | Settings popover | D11c |
| V2-17 | P2 | Expand | D13a, 11b |
| V2-18 | P1 | Show to players | D10, R4, R5 |
| V2-19 | P2 | View as player | D9c, R9 |
| V2-20 | P2 | Styles and accessibility pass | R9, STYLE_GUIDE |
| V2-21 | P3 | Performance | V1 RM-17..19 |
| V2-22 | P2 | Remove V1 surfaces and update docs | Brief section 8 |

**Milestones.** Since decision 8.3 the build deploys to the user's game as it goes; there is
no separate test game and no V1 window to protect.

| Milestone | Tasks | Result |
|---|---|---|
| M0 | V2-00 | Go/no-go on player writes |
| M1 Foundation | V2-01..03, V2-05 | V2 data readable and writable; no UI change yet |
| M2 Map | V2-06..12, V2-18, V2-22 (UI part) | V2 UI replaces V1: a Director can run a travel scene (brief "Done looks like") |
| M3 Tools | V2-13..17, V2-19 | Search, ruler, log, settings, Expand, View as player |
| M4 Finish | V2-20, V2-21, V2-22 (docs), section 6 | Release |

---

### V2-00 (P1) Verify player table writes first

**Why.** V1 never confirmed that a player client can write a data table (README section 4).
V2 depends on it: players create Locations (D9d), and anyone who moves the Party writes a
log entry.

**Do.** With one Director and one player client in a game (ask the user to set this up):
from the player client, `dmhub.SetAndUploadTableItem("RegionMapLocations", {...})` through
`execute_lua` with a throwaway row, then confirm the row arrives on the Director client and
`success` fires. Remove the row with `dmhub.ObliterateTableItem` from the Director.

**If blocked.** Use the approved fallback (decision 8.2): player-created Locations and log
entries go into a shared document (`mod:GetDocumentSnapshot`) instead of tables; V2-03 and
V2-15 read both sources. Report the result to the user before continuing.

### V2-01 (P1) Constants

Update `RegionMapConstants.lua`:

- **Add:** `locationTableName = "RegionMapLocations"`, `logTableName =
  "RegionMapLogEntries"`, `locationSchemaVersion = 1`, `logSchemaVersion = 1`,
  `maxDepth = 16`, `autosaveDelay = 1.5`, `toastSeconds = 10`, `undoDepth = 20`,
  `transitionSeconds = 0.3`, `pinDisc = { major = 36, normal = 28, minor = 24 }`,
  `pinNameSize = { major = 18, normal = 15, minor = 13 }`, `pinHitMin = 24`,
  `partySnapRadius = 32` (screen px), `declutterZoom = { minor = 1.5, normal = 1.0 }` (zoom
  below which names of that importance hide), `sidePanelWidth = 320`, `logCap = 500`,
  `routeDotSpacing = 14`, `windowMaxWidth = 4096`, `windowMaxHeight = 2160`, the curated
  icon list `pinIcons` (keys -> Phosphor paths, verified live in V2-07).
- **Remove** (no V2 user): nudges, inline editor metrics, workspace breakpoints and
  bottom-pane metrics, `draftLimit`, `previewChars`, `focusZoom`, `focusHaloSeconds`,
  `retainedSeconds` (if V2-08 drops the retained highlight), `iconLabels`,
  `iconShowLabels`, `iconHideLabels`.
- Keep table and document names that are persisted; never rename them.

### V2-02 (P1) Copy module

New `RegionMapCopy.lua`:

```lua
--- Every user-facing Region Map string, keyed by the copy manifest ID
--- (docs/V2_COPY.md). Change wording here and in the manifest together.
--- @class RegionMapCopy: GameType
--- @field new fun(o?: table): RegionMapCopy
RegionMapCopy = RegisterGameType("RegionMapCopy")

RegionMapCopy.strings = {
    ["tb.search"] = "Search locations",
    ["status.at"] = "{party} at {name}",
    -- ... every manifest row
}

--- The string for a manifest ID with {placeholders} filled in. Values are
--- escaped for markup (V1 LiteralText) so user text never renders as markup.
--- @param id string
--- @param args nil|table<string, any>
--- @return string
function RegionMapCopy.T(id, args) ... end

--- Singular/plural for counts: "1 location", "2 locations".
--- @param count integer
--- @param singular string
--- @param plural string
--- @return string
function RegionMapCopy.Count(count, singular, plural) ... end
```

**Acceptance.** Every row of V2_COPY.md sections 3-16 has an entry with the same ID and
text; a missing ID prints `REGION_MAP: missing copy <id>` once and returns the ID (visible
in testing, never a crash). `grep` finds no quoted UI strings in other V2 files except
style class names, icon paths and log prints.

### V2-03 (P1) Location records and model

**Records** (`RegionMapRecords.lua`): add `RegionMapLocationRecord`,
`RegionMapLogEntryRecord`, `LocationsTable()`, `LogTable()`, `IsValidLocation`,
`IsValidLogEntry`. Keep V1 record classes and accessors for the migration source only.

**Model** (`RegionMapModel.lua`, rewrite). One validated index per refresh (V1 RM-19
pattern): `byId`, `childrenOf[parentId]`, `topLevel`, built from V2 rows plus V1 rows
through the migration adapter (V2-04). Public API (everything else local):

| Function | Rule |
|---|---|
| `GetLocation(id)` | Valid, not hidden |
| `Children(mapId)`, `TopLevel()` | Visible to the viewer, sorted by name key (V1 `MapNameKey`) |
| `Ancestors(id)` | Root first; for the breadcrumb (players: only levels they can see, R4) |
| `CanSeePin(loc)` | Director: always. Player: `visibility == "revealed"` and `CanOpenMap(parent)` |
| `CanOpenMap(loc)` | Has an image. Director: always. Player: `mapShared` and (top-level or `CanSeePin(loc)`) |
| `CanEdit(loc)` | Director: always. Player: `ownerId == dmhub.loginUserid` |
| `CanAdd(mapId)` | `CanOpenMap(map)`, visible pin count below `C.labelLimit` (counted per viewer, V1 RM-02), and for players `playersCanAddLocations` |
| `CreateLocation(mapId, u, v, style)` | Director-created: `visibility = "hidden"` (R1); player-created: `"revealed"`; name "" until named (`edit.name.fallback` shown); copies the last-used icon, importance, style and visibility (R10, passed in) |
| `UpdateLocation(id, changes)` | Apply only changed fields to the freshest row (V1 README section 4 rule); bump revision; returns the undo entry |
| `MoveLocation(id, u, v)`, `MoveToMap(id, mapId)` | MoveToMap places at 0.5/0.5; refuses a target inside the Location's own subtree |
| `SetVisibility(id, v)`, `SetMapShared(id, b)` | Director only |
| `AddMap(id, imageId)`, `ReplaceImage(id, imageId)`, `RemoveMap(id)` | New maps start `mapShared = false` (R1). RemoveMap deletes the children subtree (copy 17.5) |
| `DeleteLocation(id)` | Hides the row and its whole subtree in one batch; if the Party is inside, moves it to the deleted Location's parent map at the pin's position (D7d) |
| `Party()`, `WriteParty{mapId, u, v, locationId}`, `PlaceParty(mapId, u, v)` | `locationId` set when snapped; V1 `WriteParty` reasons kept |
| `PartyStatusFor(viewer)` | `at` / `traveling` / `elsewhere` / `none`; a player sees `traveling` when the Party is at a Location whose pin they cannot see (R3) |
| Settings getters/setters | `partyName` (default copy "Party"), `partyImageId`, `playerCanMoveParty`, `playersCanAddLocations` (default true, V1 behavior) |

Every write rechecks permission at commit time (V1 `CanCommit(guard)` pattern) and returns
`ok, reason, undoEntry`.

**Acceptance.** Director and player views of one tree match the visibility table above;
players never receive a Hidden Location or an unshared map from any public function.

### ~~V2-04 (P1) V1 migration~~ - CUT 2026-10-06 (decision 8.3)

V1 data is dropped, so nothing below is built. The M1 adapter and bulk migration were
removed; `RegionMapMigration.lua` is a no-op until the user unregisters it. Kept for the
record only:

New `RegionMapMigration.lua`. Two parts, so no client ever waits for a migration:

1. **Read adapter.** When the model builds its index, every valid V1 map
   (`RegionMapRecords.IsValidMap`) and label (`IsValidLabel`) whose id has no V2 row is
   converted in memory:

   | V1 | V2 |
   |---|---|
   | map | top-level Location: same id, name, imageId, imageRevision; `mapShared = published`; `visibility = "revealed"`; pinStyle/importance defaults |
   | label | child Location: same id; `parentId = mapId`; `name = text`; u, v; `importance = "normal"`; `pinStyle = "plate"`; `visibility = shared -> "revealed", director -> "hidden"`; owner, createdByDirector, audit carried over |
   | tombstoned map | skipped with its labels |
   | Party `{mapId, u, v}` | unchanged; `locationId` absent = traveling (D4e) |

   Details and Director notes need no conversion (keyed by the same ids).
2. **Bulk write.** On the first Director open where V1 rows exist and
   `state.migration ~= "done"`: write a V2 row for each adapted Location in a coroutine
   (`dmhub.Coroutine`, yield every 10 writes), maps before labels. On all confirmed, set
   `state.migration = "done"` and show `migrate.done` once (chat notice to the Director, as
   V1's load message). Failed writes are retried on the next Director open; the adapter
   keeps the content visible meanwhile.
3. A write to an adapted Location (any edit) writes its V2 row first; that is the
   migration of that one item.

**Acceptance.** A game with V1 content shows the same maps, labels, descriptions, notes and
Party position in V2 before and after the bulk write; V1 tables are byte-identical after
migration (rollback safe); running migration twice writes nothing the second time.

### V2-05 (P1) Undo and toasts

New `RegionMapUndo.lua`, session-local:

- **Entry**: `{ description, steps = { {tableName, id, before, afterRevision} | {party = before, afterRevision} } }`.
  Model writes return one; `Undo.Push(entry, toastCopyId, args)` stores it (depth
  `C.undoDepth`) and queues a toast.
- **Undo**: rewrite each `before` with `NextRevision(current)`. Before writing, every step's
  current revision must still equal `afterRevision`; if any moved (someone else edited),
  the entry is discarded and its toast loses the Undo button (accepted 2026-10-05). Undo of
  a Party move also hides the log entry it created or restores the merged entry (R3).
- **Toasts**: one at a time, newest replaces older; `C.toastSeconds`, timer pauses on
  `hover` and resumes on `dehover` (R9); Undo closes it with no second toast. Copy:
  manifest section 10.
- **"Undo last change"** (log panel) undoes the newest still-valid entry of this user.
- Engine undo (`dmhub.Undo`, Ctrl+Z) does not cover Region Map table writes; Party
  document writes pass `{undoable = false}` so Ctrl+Z cannot desync the log.

**Acceptance.** Hide, reveal, share, move (pin, Party, to map), delete (with subtree) and
remove map each undo exactly; an undo after a remote edit to the same row shows no Undo
button and changes nothing.

### V2-06 (P1) Shell: layout, breadcrumb, toolbar, Esc, banners

Rewrite `RegionMapPanel.lua` around the canvas (brief section 4):

- **Layout.** The canvas fills the window. Floating overlays (all `floating = true`, not in
  the flow, so nothing reflows the canvas, V1 RM-07): breadcrumb top-left, toolbar
  top-right, camera controls bottom-left, status chip bottom-right (moves left of the side
  panel when it is open), banners stacked under the breadcrumb, toasts bottom-center. Side
  panel and log panel overlay the right edge, `C.sidePanelWidth`; full width below 720
  px (D6e).
- **Breadcrumb.** `Model.Ancestors`; each part clickable; the current map bold.
- **Toolbar.** Buttons and tooltips per manifest section 3, in brief order; Director-only
  buttons absent for players; Add absent for players when `playersCanAddLocations` is off.
  Toggle buttons show an on state.
- **Camera controls.** Fit, zoom out, zoom in, Show names. Fade to a 3:1-contrast state
  after 2 s without pointer movement over the canvas; back on movement (R9); no fade under
  Reduce motion (stays visible).
- **Esc order (R2).** One `captureEscape` handler per layer with rising `escapePriority`:
  map level (go up one level) < side panel (close) < edit mode (leave) < in-progress action
  (placement, ruler, Move, text field). Expand ignores Esc.
- **Lock (R6).** Local per viewer, `true` whenever a map opens; chip `chip.unlocked` while
  off.
- **Banners.** `banner.viewAs`, `chip.unlocked`, `hint.add`, `hint.move`, `hint.ruler`.
- **Session state** (`RegionMapSession.lua`): current map, selection, panel mode
  (read/edit/log/none), lock, active tool, View as player, last-used pin style (R10).
  V1 session drafts and the unsaved-changes list are removed (autosave, D13b).

**Acceptance.** At 720x480, 1000x800 and expanded, no overlay overlaps another; Esc follows
R2 from every state; a player sees no Director button.

### V2-07 (P1) Pins on the canvas

Rewrite the marker part of `RegionMapCanvas.lua`:

- One pin panel per visible child (`Model.Children`), positioned from u/v like V1 markers.
  Disc size and name size from `C.pinDisc` / `C.pinNameSize` by importance; constant on
  screen at every zoom (D5c). Hit area at least `C.pinHitMin` square.
- Styles (D5a): Icon + name; Name plate (backed text); Icon only (name in hover). Names are
  always on a halo or backing (R9).
- Badges: map badge when the viewer can open the Location's map (D8a, R4); Director sees
  Hidden pins at 0.55 opacity with an eye-slash badge (D9c).
- **Declutter** (D5c): below `C.declutterZoom.minor` minor names hide, below `.normal`
  normal names hide; icons stay; Show names forces every name, icon-only too (R9).
- **Hover** (D6d): name plus the first line of the description (`pin.hover`), as a tooltip
  panel; the selected pin's panel shows the same content for non-hover users.
- **Icons** (D5d): curated keys from `C.pinIcons` (theme-tinted masks) or a library image
  id. Verify every curated Phosphor path live once (`execute_lua` building a panel per path
  and checking `imageLoaded`); drop any that fail.
- **Font Size outside rail mode:** multiply disc, name and hit sizes by
  `dmhub.GetSettingValue("fontsize") / 100` when `WindowUIScale()` is 1 and the rail is off
  (11b).
- Click selects and opens the side panel; double-click renames only when unlocked and
  `CanEdit` (else it is a click, R12); right-click opens the "..." menu (R12).

**Acceptance.** 250 pins on one map pan and zoom without visible stutter (measure in
V2-21); names never overlap at fit zoom on the test map; colors are never the only signal
(Hidden = dim + badge).

### V2-08 (P1) Map navigation and transitions

- **Open map** (panel button only, D8a): zoom the camera toward the pin over
  `C.transitionSeconds` in the canvas `think`, then crossfade to the child map. The child
  image is a second streamed image panel; it fades in only after its `imageLoaded` (slow
  loads show the old map meanwhile, 11b). Going up reverses (zoom out of the pin's spot).
- **Reduce motion**: instant switch, no zoom, no fade.
- Each map keeps its own camera (V1 preference keys, `mapId:imageRevision`); opening a
  map with no saved camera fits it.
- **Replace map image** keeps children's u/v (V1 behavior); drop V1's 2 s "retained"
  highlight unless it proves needed.
- Measure first-open time of a large image (4k-8k) once and record it in the README
  (11b open item).

**Acceptance.** Breadcrumb, Esc, Atlas and Open map all land on the right map with its own
camera; no blank frame during a transition on a cached image.

### V2-09 (P1) Party marker and moves

- **Marker** (D11a): theme-colored banner, group icon or `partyImageId`, name chip with
  `partyName`, drawn above pins; only on the map it is on (D8d). At a Location it is drawn
  beside the pin (R3), following the pin when the pin moves.
- **Drag** (D7b, R3): polled drag like V1 `PollLeftPan` (the engine moves draggable panels
  physically). Start after `C.canvasDragThreshold`; while dragging, the nearest pin within
  `C.partySnapRadius` the dragger can see is highlighted; drop on it = `WriteParty` with
  `locationId`, else free (`traveling`). A player-dragged Party never snaps to a pin the
  player cannot see (R3). Drags are allowed whatever the Lock state (Lock covers pins only).
- **Non-drag paths:** "Move Party here" in the panel; Director right-click "Place Party
  here" on any map (R12).
- Every move writes a log entry (V2-15) and pushes one undo entry covering both.
- **Status chip** (`status.*`): `Model.PartyStatusFor`; `status.elsewhere` is clickable and
  opens the Party's map.

**Acceptance.** Director and player (with permission) can drag, snap and undo; a player
without permission cannot start a drag (no ghost); a player never learns a Hidden
Location's position from the Party or status.

### V2-10 (P1) Side panel

New `RegionMapSidePanel.lua`, replacing `RegionMapLocationCard.lua`:

- **Read mode** (brief section 7, signed off D6f): header with icon, name, close; Director
  meta `panel.meta` with the eye toggle and, when the Location has a map, the map-shared
  toggle (R4); description (Director sees `panel.desc.empty` when empty); journal link;
  `panel.author` for player-made Locations only (R11); `panel.partyHere`; "Move Party here",
  "Open map" (players only once shared); "Edit"; "..."; collapsible Director notes.
- **Edit mode** (D6b): Visibility first (Director only, R1), Name, Icon, Pin style,
  Importance, Description, Journal entry, Director notes; "Done". **Autosave** after
  `C.autosaveDelay` without typing or on leaving a field (D13b), state line
  `edit.saving` / `edit.saved` / `edit.notSaved` + Retry (R11). Flush pending saves before
  any navigation (including a Show to players jump, D10b).
- **"..." menu** (manifest section 8): items filtered by role and state; same menu on pin
  right-click. Delete confirms only when the Location has a map or children (D7d,
  `dlg.delete.*`); otherwise it deletes at once with an undo toast.
- New Locations open here in edit mode with the name focused (D7a).
- Panel width scales with Font Size outside rail mode; button rows wrap (R9); Tab order
  follows the visual order of the form.

**Acceptance.** Every action in the menu works for each role; autosave survives closing the
panel mid-typing; the panel never covers the selected pin (map pans just enough, D6e).

### V2-11 (P1) Atlas

New `RegionMapAtlas.lua`, replacing `RegionMapLibrary.lua`:

- Grid of top-level Locations the viewer can open (`Model.TopLevel`), thumbnail (streamed
  image), name, chips `atlas.card.party` and, for the Director, `atlas.card.notShared`
  (dimmed card), count `atlas.card.count` (visible children).
- "New map" card (Director): image picker (`gui.IconEditor`, as V1 Library), creates a
  top-level Location named `atlas.new.defaultName`, not shared (R1), opens it with the name
  selected in the side panel.
- Empty states per manifest (`atlas.empty.*`).
- Reached from the breadcrumb root; the window opens here only when the viewer has no
  last map and no map is visible.

### V2-12 (P1) Create and move Locations

`RegionMapCanvasTools.lua`, rewrite:

- **Add** (D7a, R10): toolbar "+" enters a sticky placement mode (`hint.add`) until Esc;
  each click creates a Location at the point, copying the last-used style; right-click on
  the map "Add location here" does the same once. Letterbox clicks are ignored (V1 rule).
  `limit.locations` when `CanAdd` fails on the limit.
- **Move pin**: unlocked drag (polled, one write on drop, undo toast) or "Move" from the
  menu (`hint.move`, click to place, Esc cancels).
- **Move to map...**: picker of maps the viewer can open (`picker.moveToMap.*`).
- V1 keyboard nudges and the inline label editor are removed (D13d, D13e).

### V2-13 (P2) Search

In `RegionMapPopovers.lua`: toolbar Search opens a popover with `gui.SearchInput`
(`editlag = 0.15`, V1 RM-03) over every Location the viewer can see on any map. Results:
name and path (`search.result.path`); click or Enter on the top result (R9) opens the map,
centers and selects the pin. `search.none`, `search.hint`.

### V2-14 (P2) Ruler and map scale

- **Ruler** (R7): toolbar toggle; click start then click end, or drag; local only (no
  writes). Line drawn as a rotated thin panel (11b) with end dots and a label
  (`ruler.*`). Distance from the map's `scale`; time from `pace`, rounded to half days,
  `ruler.time.under` below 0.5. Without a scale: percent of map width plus the Director
  hint.
- **Set scale...** (Settings, V2-16): calibration tool, click two points on the map, then
  enter distance and unit; stored on the Location (`scale`). Travel pace per day is an
  optional number on the Location (`pace`); empty hides travel time.

### V2-15 (P2) Session log and route

- **Model** (`RegionMapLog.lua`): on every Party write, append or merge (R8): if the newest
  entry is `traveling` or `travelingOn` on the same map and this move is also free, append
  the point to `route`, increment `mergedCount`, update `at`; else create an entry (`kind`
  from section 3.4). Director may annotate (`note`), edit the note, or delete an entry.
  Players see entries whose map they can open and whose Location (if any) they can see.
- **Cap** (decision 8.1): when the table holds more than `C.logCap` entries, the Director
  client obliterates the oldest (`dmhub.ObliterateTableItem`) on open.
- **Panel** (`RegionMapLogPanel.lua`): right-edge panel like the side panel; date headings
  (`log.day.*`), entry lines (`log.*`), footer Add note, Undo last change, Show route.
  `log.empty` when empty.
- **Route**: for the current map, the route points of its entries drawn as dot panels every
  `C.routeDotSpacing` px along each leg, in a layer below pins and the Party (11b); toggled
  by Show route (local preference).

### V2-16 (P2) Settings popover

In `RegionMapPopovers.lua` (Director only, toolbar gear): sections and controls per manifest
section 13. Party name and image write the state document; the two switches write the state
document; Map scale and pace write the current Location; Reduce motion writes the local
preference.

### V2-17 (P2) Expand

In `RegionMap.lua` host adapter, next to `FitHostWindow`:

- Toggle stores the current window geometry in session state (not `_tmp_location`), then
  sets size = (documents layer size - left/right rail insets - top inset - bottom gap) /
  `WindowUIScale()`, position = top-left of the play area, and fires the `resize` delta
  (11b). Toggle again restores the stored geometry.
- Raise the registration's `maxWidth` / `maxHeight` to `C.windowMaxWidth` /
  `C.windowMaxHeight`.
- Rail mode only; with the rail off, Expand sizes the mod's own floating window the same
  way. Native popouts: hide the button.
- Esc never leaves Expand (R2); a host window resize by the user while expanded clears the
  expanded state.

**Acceptance.** Expanded window covers the play area exactly at Font Size 80/100/140 and on
a 16:9 and a 21:9 screen; restoring returns the previous size and place.

### V2-18 (P1) Show to players

Rewrite `RegionMapPresent.lua`:

- Director "Show to players": if the map is not shared, `dlg.share.*` first (R4); then send
  through GameHud's present slot as V1 (`PresentWithConfirm` with the foreign-presentation
  guard, nonce, TTL) with `{ locationId, imageRevision }`; Director toast `toast.showing`.
- Recipients always jump (D10b): flush autosave, open the map (fit), toast `toast.shown`
  (R5). No busy-viewer offer, no Back, no location focus (D10e).
- Players open on their last viewed map (D13c); presenting does not change that rule.
- Remove V1 pending focus, offer and focus halo code.

### V2-19 (P2) View as player

Director toggle, local only: the model answers visibility questions as a player who owns
nothing (no Hidden pins, no unshared maps, players' breadcrumb, no Director buttons or
notes); `banner.viewAs` shows while on; editing is disabled while on.

### V2-20 (P2) Styles and accessibility pass

`RegionMapStyles.lua` rewritten for V2 surfaces using STYLE_GUIDE grammar and DefaultStyles
tokens (MCDM scheme and Warm Gold). Checklist (R9):

- Hidden state: dim + badge, never color alone.
- Every hover-only content has a click path (selection shows it).
- Camera controls at 3:1 contrast when faded; names on a halo or backing.
- Pins, Party and hit areas scale with Font Size (V2-07).
- Reduce motion turns off transitions, fades and the camera control fade.
- No drag-only action: Move from menu, Move Party here, Place Party here, ruler
  click-click.

**Acceptance.** ui screenshots at 720x480, 1000x800, expanded; Font Size 80/100/140; Default
and Warm Gold with no `THEME_ENGINE:: unresolved` log lines.

### V2-21 (P3) Performance

Keep V1's measures (think 0.02 s only while hovered, focused, dragging or transitioning;
coalesced refresh 0.05 s; camera saves debounced 0.5 s). Add: pin panels reused across
refreshes keyed by Location id; route dots rebuilt only when the log changes. Measure and
record in the README: refresh with 250 pins on one map and 3 x 250 across maps; pan/zoom
frame time with 250 pins; first open of a large image.

### V2-22 (P2) Remove V1 surfaces and update docs

- Removed V1 surfaces (brief section 8): map dropdown, Manage maps pane, Labels pane, inline
  editor, nudges, busy-viewer offer, unsaved-changes list, location presenting, footer
  Party toggle. Each relocated capability is checked against the brief's regression table.
- `README.md` rewritten for V2 (behavior, architecture table = section 3.1, data = 3.2,
  open decisions, acceptance). `TECH_TASK.md` (V1) gets a header line "Superseded by
  TECH_TASK_V2.md"; `IDEAS.md` marks ideas 1, 2, 4, 5, 6 as delivered in V2 and 3, 3.1 as
  V2.1.
- The mockup and brief are not edited by the build; deviations go back through the user.

## 5. Out of scope

- Fog, hex overlay with distances, planned travel paths (V2.1).
- More entities than the Party, area Locations, lead/follow presenting (later).
- Keyboard shortcuts beyond Esc and arrow panning (D13d).
- Any core change, including host-level gaps found during the build (report them
  separately).

## 6. Verification (definition of done)

1. `..\dependencies\lua\bin\luac.exe -p` passes for every `Region Map/*.lua`; ASCII-only.
2. LuaLS 0 problems in `Region Map/`; upstream `tools/lua-typing/check.ps1` passes before
   merge.
3. Live, one Director and two players (the user starts the clients; ask before any
   DMHub start or stop):
   - Player creates, edits, moves and deletes their own Location; cannot touch others'.
   - Hidden Location: invisible to players everywhere (pin, search, breadcrumb, route,
     log, Party status).
   - Map shared on/off; Show to players on an unshared map asks first; recipients jump and
     get the toast; an open edit form on a recipient is saved, not lost.
   - Party drag, snap, undo; player permission off/on; log entries and merging.
   - Undo after a remote edit to the same row shows no Undo button.
   - Expand on rail mode at Font Size 80/100/140.
4. Visual pass of V2-20.
5. Every string on screen traceable to a manifest ID (spot-check each surface).
6. `git status` shows changes only under `Region Map/`; the CodeMod file list matches
   section 3.1; the user has removed the four retired files in the mod tools.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Players cannot write tables | V2-00 first; approved fallback to a shared document (8.2) |
| Hidden content is in every client's tables | Accepted in V1; unchanged. Director notes stay labeled as hidden from players' screens only |
| Large images load slowly | Fade only after `imageLoaded`; measure in V2-08 |
| Concurrent edits | Changed-fields-only writes; undo refuses after a remote edit |

## 7b. Build notes

**M1 (V2-01..05), 2026-10-05.** Built, registered, deployed to the dev-mod folder and
probed read-only in a live game (V1 content visible through the adapter, player filter,
Party, copy). LuaLS: 0 problems in `Region Map/`. Choices made while building:

- **V1 code stays until M2.** M1 must leave the V1 UI working, so `RegionMapModel.lua` holds
  the V2 API first and the V1 API below it (about 1,400 lines until M2 deletes the V1 part).
  Two V1 names clashed and were renamed with their callers: `CreateMap` -> `CreateMapV1`
  (Library), `WriteParty` -> `WritePartyV1` (Canvas). V1-only constants are also kept until M2.
  `PlayersCanMoveParty` / `SetPlayersCanMoveParty` are shared and stay.
- **Bulk migration is not triggered in M1.** While the V1 UI still writes V1 tables, an
  early V2 copy would hide later V1 edits. `RegionMapMigration.Run` is wired to the V2 open
  in V2-06. Migration writes are not "creates", so a migrating row never blinks out.
- **Index cache** keys on `dmhub.ngameupdate` + `dmhub.tablesUpdateId`; the model's own
  writes invalidate it.
- **Deleting keeps details and notes rows** (nothing shows them, and undo restores the
  Location with its text intact). V1 hid them.
- **Undo** compares revision and `mutationId` per step, and waits (up to 5 s) for the
  entry's writes to be confirmed before reverting. Party writes keep `partyRevision` /
  `partyMutationId` in the state document so an unplace is undoable too. A refused undo is
  silent (the button goes); a failed revert shows `toast.saveFailed`.
- **Copy additions** (derived from manifest notes, same wording rules): singular `.one`
  variants picked by `args.count`, `dlg.removeMap.body.empty`, `pin.hover.nameOnly`,
  `party.defaultName`, `log.by.director`, `ruler.unitShort.*`, month names.
- **Player status** when the Party is on a map the player cannot open: `none`.
- `deploy.ps1` cannot run here (empty `gitfolder` setting); files were copied to
  `C:\Users\ElderHex\codex-dev-mods\Region Map\` directly.
- **Player side verified live 2026-10-06** (`docs/M1_TEST_STEPS.md`, one Director and one
  player client): player create/rename/delete/undo of their own Location; refusals
  (`permission`) for editing a map, hiding, creating a map, moving the Director's Location,
  moving the Party with the switch off, adding with "Players can add locations" off; a
  Director reveal reaching the player; player Party move and its undo. Test rows removed and
  both switches restored afterwards.
- **Still not verified live:** the Director-side delete with a subtree and the Party inside,
  RemoveMap, an undo refused after a remote edit, the toast timer, and the bulk migration
  (needs a throwaway game; never in a game still using the V1 window).

**M2 (V2-06..12, V2-18, V2-22 UI part), first build 2026-10-06.** All files written and
deployed to the user's game (decision 8.3). New: `RegionMapSidePanel.lua`, `RegionMapAtlas.lua`
(registered after `RegionMapCanvas.lua`). Rewritten: Session, Styles, CanvasTools, Canvas,
Present, Panel. Retired no-ops: Migration, Library, LocationCard. The V1 model API, the V1
record types and the migration are deleted. Model additions: `OpenableMaps`, `Details`,
`DirectorNote`, `SaveDetails`, `SaveDirectorNote`, `SaveStatus`, `DisplayName`,
`Players(Can|Set)MoveParty` on `WriteState`; `CreateLocation`/`CreateMap` take confirmation
callbacks (a new row is readable only once confirmed).

- **Verified live (Director):** Atlas with empty state and New map card; a map opens with
  breadcrumb, toolbar, camera controls and status chip; pins (Icon + name with halo, Name
  plate, Hidden dim + eye-slash badge); Party banner; click a pin -> side panel read mode;
  Edit -> form; typing autosaves (Saving... -> Saved, pin renames live); Esc leaves edit mode
  (R2); Move Party here -> Party beside the pin (R3), status "at", undo toast; Undo restores
  the Party; "..." menu entries for a Director pin.
- **Verified live, second pass (Director):** right-click map menu (now has its background) ->
  Add location here (hidden, edit mode, name focused, autosave); side panel scrolls to Done;
  pins locked by default (drag ignored) and unlocked (drag moves, "moved" toast + chip); Party
  drag (traveling) and snap onto a pin ("Party moved to ..."); Open map (zoom in + crossfade,
  breadcrumb grows); going up by Esc and by breadcrumb (eases back out); pin menu (with and
  without a map); Move to map picker + Undo; Remove map dialog + toast; Delete without a
  dialog for an empty Location (D7d) + undo; View as player (player Atlas empty state);
  Director Atlas cards and the New map picker opening; Show to players asks "Share this map?"
  (cancelled, nothing sent).
- **Fixed in the second pass:** (1) pins and the Party were drawn with their top-left corner on
  their point (the engine's `pivot` does not move a panel), so they sat half a size down-right
  and a Party drop on a pin's icon could miss the snap radius; they are now center-aligned and
  offset from the canvas center (`PlaceCentered`). (2) A Party drag starting beside a pin
  jumped by that offset; it now starts from where the banner is drawn. (3) The zoom into a pin
  before Open map saved itself as the parent's camera, so going up stayed zoomed in; that
  animation no longer saves (`StartAnimation(..., noSave)`). (4) A hover tooltip stayed behind
  at a drag's start; pressing a pin or the Party clears it. (5) The View-as-player banner
  overlapped the Atlas content; the Atlas body moves below the breadcrumb and banners
  (`bannerRows` event). (6) The New map picker drew a solid white box; it is a faint drop slot
  with a plus (the editor's own style rules lose to the theme, so the tint is a `selfStyle`).
- **Verified live, fourth pass (Director, 2026-10-07):** the Add tool (sticky until Esc, letterbox
  clicks ignored, each click opens a hidden Location in edit mode with the name focused, the last
  pin style is copied); Esc order Add/text field -> edit mode -> panel; Move from the menu (hint,
  Esc cancels, click places, undo); Replace map image (fits the new image, pins keep u/v,
  revision bumps, sharing kept). **Fixed:** (1) Move redrew the canvas before writing, so the pin
  stayed put until the next refresh; (2) the side panel header showed the map glyph for a pin with
  no icon instead of the pin's default glyph; (3) the image picker in the side panel drew a white
  box (same fix as the Atlas card); (4) the "..." tooltip stayed drawn under the open menu.
- **Show to players, verified live 2026-10-07 (Director + player client on this PC):** on an
  unshared map the compact "Share this map?" card -> Share and show shares the map, fills the
  present slot (`Region Map`, the map id, ttl 10) and toasts `toast.showing` on the Director; the
  player's window jumped to the map with the players' view: Hidden pins absent, the travelling
  Party at its point, `Party - traveling` chip, breadcrumb Atlas > map, toolbar Add + Lock only.
  Not seen: the player's `toast.shown` (the screenshot was taken later than its 10 s) and the
  recipient's open edit form being flushed by the jump.
- **Copy gaps approved by the user 2026-10-07 as built:** the foreign-presentation confirm
  (`tb.show` + the other feature's name) and no message for a failed or slow image (the old map
  stays until the new one loads).
- **Visual fixes (third pass, verified live):** beside a pin the Party's name label sits above
  the Party, clear of the pin's name; the hidden and map badges are centered on the corners of
  the disc's bounding box (plate corners for a Name plate), scaled with the UI, so the icon
  stays visible (`C.pinBadgeSize`); confirm dialogs (delete, remove map, share, foreign
  presentation) are a compact card over a dimmed layer inside this window (`ctx.Confirm`)
  instead of the engine's 60%-of-screen `gui.ModalMessage`; Esc closes the card first. The
  "clipped toolbar tooltip" was a screenshot crop: the tooltip shows in full past the edge.
- **Engine lessons:** (1) a panel with no bgimage gets no pointer events, so pins and the Party
  carry a clear background; (2) pins inside an `interactable = false` layer got no clicks, so
  they are direct canvas children; (3) `gui.IconEditor` given a Region Map style class broke
  its parent card's styling, so it takes inline sizes; (4) reading an unset `selfStyle` field
  raises, so last values are kept in `data`; (5) text outline width is a 0..1 fraction;
  (6) the dev-mod reload can miss a copied file, so deploys `touch` the files; (7) `pivot`
  does not move a panel, so a floating marker is centered with halign/valign "center" and an
  x/y offset from its parent's center; (8) `gui.IconEditor` ignores a `bgcolor` arg when
  shown in this window (set `selfStyle.bgcolor`), and `noneImage` hides its "(none)" label.

**M3 (V2-13..17, V2-19), first build 2026-10-07.** New and registered: `RegionMapLog.lua`
(after Undo), `RegionMapPopovers.lua` (after Atlas), `RegionMapLogPanel.lua` (after Popovers).
Updated: Constants, Session, Model (`Search`, WriteParty logs the move), Records
(`byDirector` on log entries), Undo (`Remember`, rebinds), CanvasTools (ruler, scale tool,
`MeasureText`, route/ruler overlay), Canvas, Panel (toolbar in brief order, popovers, log
mode, Esc layers), RegionMap.lua (Expand), Styles. LuaLS 0 problems.

- **Verified live (Director, 2026-10-07):** Search (popover, results with path, Enter opens
  the top result and selects it); ruler by click-click and by drag, rotated line, "48% of map
  width" uncalibrated, "39 mi - 1.5 days" with scale + pace; Set scale (Settings -> tool hint
  -> two clicks -> Settings reopens with Distance focused -> 30 mi saved on the Location); pace
  saved; Settings sections and switches; session log entries (free drops merge, R8; arrival;
  "Moved by the Director - time - N moves merged"; Today heading); route dots under pins; undo
  of a Party move hides its log entry; "Undo last change" twice in a row; note editor via the
  entry menu, Esc saves the note and closes only the editor; Expand to the play area between
  both rails and back to the previous size and place; View as player hides Hidden Locations
  from Search.
- **Choices made while building:** the popovers are in-window panels under the toolbar (like
  the confirm card), closed by Esc, their button or a press on the map; a scale draft waits
  for its distance in Settings and is dropped when Settings closes; pace shows only once a
  scale exists (it is in the scale's unit); the log panel takes the side panel's place
  (`panelMode = "log"`) and stays open across map changes; clicking a log entry opens its map;
  log note edits and deletions have no toast copy, so they go on the undo stack without one
  (`Undo.Remember`, reached by "Undo last change"); players do not see entries whose Location
  is Hidden (spec), so those route legs are not drawn for them; the Party's own "Moved by"
  line shows the local clock time after " - ".
- **Fixed while testing:** (1) undo of the newest move rewrote rows with new revisions, so the
  next older entry read as "changed by someone else" and "Undo last change" stopped after one
  step; a successful undo now moves older entries onto the new revisions (`RegionMapRebind`).
  (2) Expand first used the 1080-tall placement space; the window layer is the screen below
  the title bar (1728 x 1048 here), so the window ran past the bottom and over the right rail.
  It now measures the layer. (3) Inputs in the popovers overflowed their left edge
  (`borderBox`). (4) Esc closed the log with a note being typed and lost it.
- **Not verified yet:** anything on a player client (Search, log and route filtering, ruler);
  Expand at Font Size 80/140 and with the rail off; the 500-entry cap; the Party image picker
  in Settings. **Known gaps:** the note editor puts the caret at the start of the existing
  note; the ruler's end dot draws under the Party banner; the Search popover is full height
  even with few results.

**M4 (V2-20, V2-21, V2-22 docs), 2026-10-07.** Updated: Session, Canvas, CanvasTools,
Popovers, LogPanel, Styles, Model. Docs: README rewritten for V2, `TECH_TASK.md` marked
superseded, `IDEAS.md` marked (1, 2, 4, 5, 6 delivered; 3, 3.1 V2.1). LuaLS 0 problems.

- **V2-21 performance** (measured live with 250 in-memory test pins, nothing written; numbers
  in the README): pins and the Party sit on one layer that slides as a whole on pan (52 ->
  16.6 ms per frame); name plates and badges are created only when shown (first draw 570 ->
  221 ms); a pin is restyled only when it changed (refresh 13 -> 2.6 ms); route dots are
  rebuilt only when the route changes, after a zoom or after a pan of more than half the
  view; the model validates each row once (753 Locations: 30 -> 17 ms). First open of a
  6000x13985 image not loaded before: 6.3 s, frames stayed at 16-18 ms; cached images open in
  the same frame.
- **V2-20 pass, verified live (Director):** 720x480 with the side panel, 1000x800, Expanded;
  Font Size 80/100/140 (rail mode zooms the whole window); Default and Warm Gold with no
  `THEME_ENGINE` lines; Hidden = dim + eye-slash badge and "Hidden" text; faded camera
  controls 4.6:1 typical and 3.0:1 worst over map art, 9.9:1 over the letterbox; Reduce motion
  keeps the controls visible and skips the zoom and crossfade (the only other transitions are
  0.1 s hover tints).
- **M3 gaps closed:** the note editor puts the caret after the existing text; the Search and
  Settings popovers size to their content and scroll once they reach the bottom controls; the
  ruler's line and end dot draw over the Party and the ruler measures to the Party.
- **Fixed while testing:** (1) a toggle button's tooltip kept its old text after a click (the
  Lock button); it now updates while hovered. (2) A click on the Party with the ruler or scale
  tool on was swallowed, and a press dragged the Party; it now places the tool point at the
  Party. (3) After the V2-21 layer change the route dots drew about half a view up-left on
  every open: the route layer stayed at the engine's default 100x100 (see lesson 1). (4) The
  "needs a newer Codex" message was a literal in `RegionMap.lua`; it now reads `load.missing`.
- **Section 6 (checks without player clients):** `luac -p` and ASCII pass for all 23 files;
  LuaLS 0 problems; Lua grepped for literal UI strings (only the
  engine undo-stack descriptions and `REGION_MAP:` log lines remain, neither shown in the
  window); `git status` outside `Region Map/` shows only the earlier moves out of `output/`
  and `REGION_MAP.md`, plus untracked tool folders (`.codex/`, `.mcp/`,
  `output/segmented-stamina/`) that are not this work. The loaded file order matches 3.1 plus
  four retired no-ops still registered (`Main`, `RegionMapMigration`, `RegionMapLibrary`,
  `RegionMapLocationCard`); `RegionMapViews.lua` is no longer loaded.
- **Regression table (brief section 8):** every V1 row checked against the build: kept or
  relocated rows exist (breadcrumb and Atlas, Atlas New map and the "..." menu, global Search,
  Add and right-click, side panel, Party drag and Move Party here, the Settings switch, Show to
  players, Show names, last map per viewer, the 250 guard); the four removed rows (present a
  Location, busy-viewer offer, unsaved-changes list, nudges) have no code left, and arrow keys
  only pan.
- **Engine lessons:** (1) a panel built detached and attached later, whose classes never
  change, never gets its class styles applied, so a class-only size leaves it at 100x100; give
  such layers an inline width/height. (2) A live theme switch leaves `gui.Check` boxes, and the
  host window's own title bar, in the old colors until the window is rebuilt; a class change on
  the panel or the root does not help. Host limitation, not worked around.
- **Known, not fixed:** while the window is resized the pins run up to two frames ahead of the
  map image; players cannot set Reduce motion (it is in the Director-only Settings popover).
- **Not verified yet:** Font Size with the rail off (the mod scales pins itself there); every
  player-client item of section 6.3.

**V2.x: parent description from the breadcrumb (IDEAS.md idea 8), 2026-10-07.** Built after
M4, with the user's choice of hover preview plus right-click.
- **Behavior.** A Location crumb's tooltip shows its name, its description cut at
  `C.crumbPreviewLimit` (300) characters at a word, and a hint: `crumb.hint.up` on a parent
  ("Click to go to this map. Right-click to read about it."), `crumb.hint.current` on the open
  map. Right-clicking a crumb selects that Location in read mode, so the side panel shows it
  while the open map stays put. The tooltip is skipped while the panel already shows that
  Location. Click is unchanged (a parent opens going up).
- **Side panel.** Open map on a Location above the open map now opens it going up, not down.
  The "..." menu offers Move only for pins on the open map. Before this, the current map's own
  crumb could already open it in the panel and offer Move, which would have placed its pin by a
  click on the wrong map.
- **Copy.** Four new IDs (`crumb.hover`, `crumb.hover.nameOnly`, `crumb.hint.up`,
  `crumb.hint.current`), added to `docs/V2_COPY.md` section 4.
- **Checked:** `luac -p`, ASCII and LuaLS (0 problems). Live on the Director client, with a
  temporary Location and map under "M2 test map" (removed afterwards): the hover preview with
  its cut, right-click reading, no repeated tooltip, the current-crumb hint, Open map going up,
  and the Move entry filtered. Not checked on a player client.

**Review fixes, 2026-10-07.** From a read-through of every file but the styles.
- **Stuck navigation (fixed).** Open map waits for the zoom into the pin, and every map
  change was refused meanwhile. A wheel notch, a zoom button, a press on the map, Fit or a
  remote image change during those 0.3 s dropped the zoom's callback, so the window refused
  all map changes until it was reopened (reproduced). The canvas now always runs a cut-short
  animation's callback (`StopAnimation`; `LoadImage` and `ClearMap` run it after the switch),
  so the map still opens. The shell holds a transition token that the Atlas clears, so going
  to the Atlas mid-zoom stays on the Atlas. Checked live: Open map plus Zoom in at once opens
  the map; Open map plus Atlas at once stays on the Atlas; plain Open map unchanged.
- **Session log note lost while typing (fixed).** The log list rebuilds on any Region Map
  row change (another client moving the Party), and the rebuilt note editor started from the
  saved note, dropping the typed text (reproduced). It now starts from the draft. Checked live.
- **Delete during a save (fixed).** `DeleteLocation` did not check for a write still in
  flight on its rows, so a delete right after a rename could hide the children but not the
  Location itself. Both it and `RemoveMap` now refuse with "busy" before writing anything, and
  the side panel retries every `C.busyRetryDelay` up to `C.busyRetries` times, then shows Not
  saved. The Party now moves only after the rows are written (its target is worked out first,
  since hidden rows leave the tree), so a failed delete leaves the Party alone. Checked live:
  a rename in flight at the moment of Confirm, then the delete went through with the new name.
- **Players never delete Director content (decided by the user).** New `Model.CanDelete`: a
  player deletes only their own Location and only while it has no map. Only the Director
  adds maps, so a map and everything pinned below it is Director content. `DeleteLocation`
  and the "..." menu use it. Not checked on a player client (this client is the Director).
- **Found, not fixed:** View as player still shows journal links that players cannot see
  (`RegionMapJournal.ResolveForViewer` uses `dmhub.isDM`); Show to players over another
  feature's presentation shows that feature's internal dialog name and has no manifest copy;
  a Party move that writes no log entry (delete rescue, Move to map carrying the Party, undo)
  leaves the next merged route leg starting at the old point; `search.result.path` is
  unused (`window.title` is used since 2026-10-08). Players may still Move to map a Location of theirs that
  carries Director content (a move, not a delete).

**Cloud cleanup, 2026-10-08.**
- **Retired files removed.** The user removed `Main`, `RegionMapMigration`, `RegionMapLibrary`,
  `RegionMapLocationCard` and `RegionMapViews` from the CodeMod in the mod tools. Then the
  five files were deleted from the repo. `RegionMapViews` had stayed in the cloud list, as an
  empty file, after it stopped loading.
- **CodeMod renamed.** The user renamed the CodeMod to "Overland Map" (id
  `ec447c62-03db-4416-a5a2-0b013c0f3893`). The app now reads it from the dev-mod folder
  `Overland Map\`. The rename filled that folder with one-line placeholder files, and they
  were replaced with the real files.
- **On-screen name renamed too** (asked by the user). `C.panelName` and the copy strings
  `window.title`, `tb.settings`, `set.title` and `load.missing` say Overland Map. The
  load.missing chat title now reads `window.title` instead of a literal, so `window.title`
  is no longer unused. The panel's name is also its window title and the key for saved
  window placement, so a window placed under the old name opens at its default. The repo
  folder, the `RegionMap*` code names and the stored table and document names are
  unchanged.
- **Checked:**
  - Read through `code.GetMod(id).files`, the cloud list is the 18 files of section 3.1 in
    order.
  - Each cloud file's md5 equals the committed repo file.
  - The mod reports no local changes.

**M0 / V2-00: PASSED 2026-10-06.** A player client wrote a `RegionMapLocations` row through
the model and it reached the Director client with the player as owner. Players can write
tables, so the shared-document fallback (8.2) is not needed.

## 8. Decisions (approved by the user 2026-10-05)

| # | Topic | Decision |
|---|---|---|
| 8.1 | Session log size (brief open question 4) | Keep the newest 500 entries per game; the Director client deletes older ones on open. About 1 KB per entry worst case. |
| 8.2 | Fallback if V2-00 fails | Player Locations and log entries go in a shared document; Director-made content stays in tables. Applies only if V2-00 shows players cannot write tables; V2-03 and V2-15 then read both sources. |
| 8.3 | V1 compatibility (approved 2026-10-06) | V1 may break and is replaced wholly by V2. V1 data is dropped: no migration (V2-04 cut), no read adapter, no rollback; the V1 API and record types are deleted. The build deploys to the user's game as it goes. Brief D4e and the `migrate.done` string no longer apply. |
