# Region Map

An opt-in CodeMod for DMHub / Draw Steel Codex, listed as **Overland Map** in the in-app mod
tools (id `ec447c62-03db-4416-a5a2-0b013c0f3893`). In the app and in this repo the feature
and its window are still called Region Map. The Director builds a tree of image-based
maps and Locations; the group reads them, adds their own places and follows one shared
Party across the maps. Region Map owns its own window, canvas and data. It does not touch
tactical maps, tokens, combat rules or character content.

This is V2. The design is [docs/V2_BRIEF.md](docs/V2_BRIEF.md) (locked), the on-screen text
is [docs/V2_COPY.md](docs/V2_COPY.md) (signed off), and the build plan and build notes are
[TECH_TASK_V2.md](TECH_TASK_V2.md). [TECH_TASK.md](TECH_TASK.md) is the superseded V1 plan;
the images `docs/01`-`04` are V1 schematics, kept for history. Ideas not yet scheduled are
in [IDEAS.md](IDEAS.md).

## 1. Behavior

### Window

- One registered panel, `Region Map` (game menu and icon rail). Default window 1000x800,
  minimum 720x480. In icon-rail mode the rail hosts the window; with the rail off, the mod
  hosts its own floating window.
- **Expand** (toolbar) fills the play area between the icon rails; the toggle or Esc
  restores the previous size and place.
- Layout: breadcrumb top-left, toolbar top-right, camera controls bottom-left (they fade
  after 2 s without pointer movement), Party status bottom-right, side panel over the
  map's right edge (full width below 720 px).
- Toolbar, in order: Search, Add, Lock, Ruler, Show to players (Director), View as player
  (Director), Session log, Expand, Settings (Director). Icons with tooltips.
- **Esc** closes one layer at a time: a tool or text field, then edit mode, then a popover
  or the side panel, then goes up one map.

### Locations and maps

- **Location** is the only object. A Location may have a pin on its parent's map, its own
  map image, or both. Top-level Locations are the **Atlas** (a gallery of cards, with a
  New map card for the Director).
- The breadcrumb shows Atlas > ... > current map; every part is clickable. "Open map" in
  the side panel zooms into the pin and crossfades to its map.
- **Reading a parent from the breadcrumb.** Hover a Location crumb to see the start of its
  description (300 characters). Right-click a parent's crumb to read all of it in the side
  panel while the current map stays open; its Open map button goes up to it.
- Pins have three styles (Icon + name, Name plate, Icon only with the name on hover) and
  three tiers (Major, Normal, Minor). Pins keep a constant screen size and scale with Font
  Size; zoomed out, names hide by tier (Minor first). Icons come from a curated, theme-tinted
  set or any library image. A pin with its own map shows a map badge.
- **Visibility.** A pin is Hidden (Director only, shown dimmed with an eye-slash badge) or
  Revealed. A Location's own map has a separate Map shared switch.
- **Side panel.** Click a pin to read it: description, journal link, Party here, Move Party
  here, Open map, Edit, "..." (Move, Move to map, Show/Hide, Add map, Replace image, Remove
  map, Link journal, Delete) and the Director note (Director only). Edit turns the panel into
  a form that autosaves after 1.5 s without typing or on leaving a field.
- **Create**: toolbar Add then click the map (sticky until Esc), or right-click > Add
  location here. The new Location is Hidden, opens in edit mode with the name focused and
  copies the last pin style used.
- **Move a pin**: unlock with Lock and drag, or "..." > Move then click. Pins are locked by
  default so nothing moves by accident during play.
- **Delete**: an empty Location goes at once with an undo toast; one with children or a map
  asks first and removes the subtree. A Party inside moves to the parent map. A delete made
  while a save of the same Location is still going (a rename just typed) waits for it.
- **Players never delete Director content**: a player deletes only their own Locations, and
  only while they have no map. Only the Director adds maps, so a map and everything on it is
  Director content; a player's Location that has one loses its Delete entry.
- Limits: names 1-80 characters on one line; description 4000; Director note 8000; nesting
  16 levels; 250 Locations per map (soft guard, counted per viewer).

### Party

- One Party across all maps, drawn above pins only on the map it is on. It is either "at"
  a Location (sits beside its pin and follows it) or traveling (free on a map).
- Drag the Party; dropping it within 32 px of a pin makes it "at" that Location. Also
  "Move Party here" in the side panel, and for the Director right-click > Place Party here
  (anywhere on any map).
- Settings (Director): Party name, Party image (or the default banner), "Players can move
  the Party", "Players can add locations".

### Table tools

- **Show to players** (Director) presents the whole current map, one-shot (10 s). Asks to
  share an unshared map first and asks before replacing another feature's presentation.
  Every recipient jumps to the map and gets a toast; open edits keep saving.
- **View as player** (Director): a local toggle that shows the map as players see it.
- **Search**: every Location the viewer can see across all maps, with its path; a result
  opens its map, centers and selects the pin; Enter takes the top result.
- **Ruler**: click-click or drag. On a calibrated map it shows distance and, with a pace,
  travel days; otherwise a share of the map width. The Director sets the scale (two points
  plus a distance, miles or km) and pace per map in Settings.
- **Session log**: automatic Party entries (arrived, traveling, placed; consecutive free
  drops merge), a Director note per entry, and the past route drawn as dots on the map
  (Show route switch). Clicking an entry opens its map. The newest 500 entries are kept per game.
- **Undo**: moves, deletes and visibility changes show a toast with Undo (10 s, paused while
  hovered); "Undo last change" in the session log walks back up to 20 steps. An undo is refused if
  someone else changed the same row since.
- Camera: wheel zoom at the cursor (1x fit to 20x), left-drag on empty map, right or middle
  drag, arrow keys pan (Shift for coarse). Each viewer's camera, last map and Show names are
  kept per user and game. Reduce motion (Settings) turns off the zoom, crossfade and the
  camera control fade.

## 2. Architecture

Load order (the CodeMod file list must match):

| # | File | Responsibility |
|---|---|---|
| 1 | `RegionMapConstants.lua` | Names, limits, metrics, timings |
| 2 | `RegionMapCopy.lua` | Every on-screen string, keyed by its V2_COPY id; `Copy.T(id, args)` |
| 3 | `RegionMapJournal.lua` | Journal access and opening |
| 4 | `RegionMapRecords.lua` | Record types, safe reads, validation, uploads |
| 5 | `RegionMapModel.lua` | Location tree, permissions, visibility, writes, Party, settings, search |
| 6 | `RegionMapUndo.lua` | Undo entries and the toast queue |
| 7 | `RegionMapLog.lua` | Session log entries, merging, route points, cap |
| 8 | `RegionMapStyles.lua` | Style rules (ThemeEngine.MergeStyles) |
| 9 | `RegionMapSession.lua` | Context type, local view state and preferences, Esc layers, icon buttons |
| 10 | `RegionMapCanvasTools.lua` | Layout math, Add, Move, ruler and scale tools, route and ruler overlay |
| 11 | `RegionMapCanvas.lua` | Image, pins, Party, camera, drags, transitions |
| 12 | `RegionMapSidePanel.lua` | Location panel read and edit modes, "..." menu |
| 13 | `RegionMapAtlas.lua` | Atlas gallery and New map |
| 14 | `RegionMapPopovers.lua` | Breadcrumb, Search and Settings popovers |
| 15 | `RegionMapLogPanel.lua` | Session log panel |
| 16 | `RegionMapPresent.lua` | Show to players send and receive |
| 17 | `RegionMapPanel.lua` | Shell: toolbar, camera controls, status, banners, toasts, layout, refresh |
| 18 | `RegionMap.lua` | Capability check, registration, host window adapter, Expand |

The V1 files (`Main.lua`, `RegionMapViews.lua`, `RegionMapMigration.lua`,
`RegionMapLibrary.lua`, `RegionMapLocationCard.lua`) were removed from the CodeMod and the
repo on 2026-10-08. A file is removed from the CodeMod in the in-app mod tools; the MCP
bridge can only add files.

Each file defines one typed namespace (`RegisterGameType`, `@class X: GameType`).
Components receive a `RegionMapContext` (see `RegionMapSession.lua`), report upward through
its functions and are driven by events on their root panel.

Host APIs an older core may lack are checked once in `RegionMap.lua`; on failure the mod
prints one message, tells the local user in chat and stops. The window adapter relies on
host details that are not a formal API (`PanelDocument._tmp_location`, the `journalViewer`
window class, `dialog.data.resizePanel`, `RailModeActive`, `PanelDocument.WindowUIScale`);
each use is guarded.

## 3. Data

| Storage | Contents |
|---|---|
| `RegionMapLocations` | One row per Location: parent, name, u/v on the parent's map, pin style, tier, icon, visibility, image and its revision, map shared, scale, pace, owner, revision, soft delete |
| `RegionMapLocationDetails` | Description and journal link, keyed by Location id (V1 row format) |
| `RegionMapLocationDirectorNotes` | Director note, keyed by Location id (V1 row format) |
| `RegionMapLogEntries` | Session log entries: kind, map, Location, route points, merged count, time, author, note |
| `regionMapState` document | Party (map, Location, u/v, revision), Party name and image, Players can move the Party, Players can add locations; checkpoint-backed |
| `regionmap:preferences` setting | Per user and game: last map, cameras (keyed by image revision), Show names, Reduce motion |

- Every write rechecks role, ownership, map access and the Party switch. These are checks
  between trusted clients, not server enforcement.
- Writes send only the changed fields onto the freshest local row; the side panel shows
  Saving... / Saved for confirmed table writes.
- V1 tables (`RegionMapRecords`, `RegionMapLabelRecords`, `RegionMapTombstones`) are no
  longer read and stay in the game data unused (decision 8.3: no migration, no rollback).

## 4. Open decisions

| Topic | Current state |
|---|---|
| Hidden Locations and Director notes sync to every client; hiding is UI-only. | Accepted (as in V1); notes are labeled "Hidden from players' screens". |
| Two clients editing one row at once. | Last write wins per field; undo refuses after a remote edit. True merges need a host patch API. |
| Players cannot set Reduce motion. | It lives in Settings, which is Director-only (D11c). Needs a decision: a player-visible "Only for you" section, or follow a host setting. |
| Live theme switch. | Checkboxes (and the host's own window title bar) keep the old colors until the window is reopened. Host limitation; not worked around. |

## 5. Performance

Measured 2026-10-07 on the Director client (2560x1600 screen) with 250 test pins kept only
in memory.

| Measure | Result |
|---|---|
| Pan with 250 pins on one map | 16.6 ms per frame (the display's 60 fps cap) |
| First draw of a map with 250 pins | 221 ms |
| Refresh with 250 pins on one map | 2.6 ms |
| Location list rebuild, 3 x 250 across maps (753 Locations) | 17 ms; a full refresh after a remote change about 21 ms |
| First open of a large image not loaded before (6000x13985) | 6.3 s until the engine reports it loaded; frames stayed at 16-18 ms meanwhile |
| Open of a large image already in the local cache (4500x6407 to 8400x6300) | Same frame; no frame over 18 ms afterwards |

How it stays cheap: pins and the Party sit on one layer that slides as a whole on pan;
pin panels are reused across refreshes, keyed by Location id, and restyled only when they
changed; name plates and badges are created only when shown; route dots are rebuilt only
when the log changes, after a zoom or after a pan of more than half the view; the canvas
thinks every 0.02 s only while hovered, dragging or animating (0.25 s otherwise); refreshes
coalesce over 0.05 s; camera saves are debounced 0.5 s. Pins appear only once the image size
is known, and the new image fades in only after it has loaded.

## 6. Acceptance status

Verified live on the Director client: every M2-M4 surface (see the build notes in
TECH_TASK_V2.md section 7b), the styles and accessibility pass (720x480, 1000x800,
Expanded; Font Size 80/100/140; Default and Warm Gold with no `THEME_ENGINE` log lines;
faded camera controls at 3:1 or better), and on one player client the M1 permissions and
Show to players.

Still open (TECH_TASK_V2.md section 6.3, needs one Director and two player clients):
player create, edit, move and delete of their own Locations; Hidden Locations absent
everywhere for players (pin, search, breadcrumb, route, log, status); shared on/off and an
open edit form surviving Show to players; Party drag, snap and undo with the player switch
off and on; log entries and merging on a player; an undo refused after a remote edit; Expand
in rail mode at Font Size 80 and 140, and Font Size with the rail off.

## 7. Development

- Follow the repository `CLAUDE.md`, `UI_BEST_PRACTICES.md`, `ThemeEngine.md`,
  `DefaultStyles.md` and `STYLE_GUIDE.md`. ASCII-only Lua. Every on-screen string comes
  from `RegionMapCopy.lua`.
- Change only files in `Region Map/`. Register new files with
  `mcp__dmhub__register_lua_file` in the order above; never edit `main.lua`.
- Check syntax with `..\dependencies\lua\bin\luac.exe -p` and types with the upstream
  `tools/lua-typing/check.ps1` (every file in this mod checks clean).
- Deploy with explicit paths so nothing outside the runtime files is copied:
  `.\deploy.ps1 "Region Map/RegionMapConstants.lua" ...`, then reload Lua. The app reads
  dev mods from a dev-mod folder named after the CodeMod, so these files go to
  `<git folder>\Overland Map\`, not `Region Map\`. Where `deploy.ps1` cannot run, or does not
  know the rename, copy the files there directly.
