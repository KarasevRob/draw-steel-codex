# Overland Map (Region Map)

An opt-in CodeMod for DMHub / Draw Steel Codex, named **Overland Map** in the in-app mod tools
(id `ec447c62-03db-4416-a5a2-0b013c0f3893`) and on screen. Until 2026-10-08 it was called
Region Map. The code still uses that name: this folder, the `RegionMap*` files and
namespaces, and the table and document names, which are stored and never renamed.

The Director builds a tree of image-based maps and Locations; the group reads them, adds
their own places and follows one shared Party across the maps. The mod owns its own window,
canvas and data. It does not touch
tactical maps, tokens, combat rules or character content.

This is V2.1: V2 plus point crawl maps, map image guidance and borders, and JSON import.
The designs are [docs/V2_BRIEF.md](docs/V2_BRIEF.md) and
[docs/V2_1_BRIEF.md](docs/V2_1_BRIEF.md) (both locked; V2.1 changes only what it names), the
on-screen text is [docs/V2_COPY.md](docs/V2_COPY.md) (sections 1-17 V2, 18-25 V2.1), and
the build plans and build notes are [TECH_TASK_V2.md](TECH_TASK_V2.md) and
[TECH_TASK_V2_1.md](TECH_TASK_V2_1.md). [TECH_TASK.md](TECH_TASK.md) is the superseded V1
plan; the images `docs/01`-`04` are V1 schematics, kept for history. Ideas not yet scheduled
are in [IDEAS.md](IDEAS.md). The cleanup audit of the Lua (duplication, dead code, bugs found
along the way) and its tiers are in [docs/CLEANUP_AUDIT.md](docs/CLEANUP_AUDIT.md).

## 1. Behavior

### Window

- One registered panel, `Overland Map` (game menu and icon rail). Default window 1000x800,
  minimum 720x480. In icon-rail mode the rail hosts the window; with the rail off, the mod
  hosts its own floating window.
- **Expand** (toolbar) fills the play area between the icon rails; the toggle or Esc
  restores the previous size and place.
- Layout: breadcrumb top-left, toolbar top-right, camera controls bottom-left (they fade
  after 2 s without pointer movement), Party status bottom-right, side panel over the
  map's right edge (full width below 720 px).
- Toolbar, in order: Search, Add, Path (Director, point crawl maps only), Lock, Ruler, Show to
  players (Director), View as player (Director), Session log, Expand, Settings (Director).
  Icons with tooltips.
- **Esc** closes one layer at a time: a tool or text field, then edit mode, then a popover
  or the side panel, then goes up one map.
- While a side panel (Location, path, Party or log) is open, the map can pan left by the
  panel's width, so a pin under the panel can still be reached at Fit (V2.1).

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

### Map images (V2.1)

- **Size guidance.** The image pickers and the Atlas New map tooltip say "Best at 4000 px
  wide. Under 1500 px it blurs when zoomed in; over 12000 px it loads slowly." After a new
  pick, an image outside 1500-12000 px wide gives a toast with "Replace image..."; nothing
  is blocked. Existing maps are never checked.
- **Border** (Settings > This map): None or Soft fade, which fades the image's edges into
  the canvas colour. Pins, paths, the route and the Party draw above it. New maps start with
  the border picked last. Torn edge and Frame show as dimmed tiles ("this border needs its
  art") until the art exists ([docs/BORDER_ART.md](docs/BORDER_ART.md)).

### Import (V2.1)

- Director: "Import locations..." in the map right-click menu and the open map's "..." menu
  reads a JSON file ([docs/IMPORT_FORMAT.md](docs/IMPORT_FORMAT.md)) into the open map.
- A preview lists the count, skipped entries with the reason for each, and names already on
  the map. An import that would pass the 250-pin guard is refused whole. Entries without
  u/v go on a grid near the center. One Undo removes the whole import.

### Point crawl maps (V2.1)

- **Kind.** A new map is Free (as V2) or Point crawl, chosen at creation (Atlas New map, or
  Add map in the side panel) and never changed. A point crawl map shows a "Point crawl"
  chip. Remove map clears the kind, so Add map can choose again.
- **Paths** join two pins on the same map, with up to 32 bends. Each has a name, a type, a
  travel time (watches: 4 hours, 6 to a day), the other way back (same time, a different
  time or not possible), a description, a Director note and Hidden/Revealed. A player sees a
  path only when it is revealed and both ends are visible.
- **Path types** (Settings > Whole game): six starters (Road, Trail, River, Sea, Underground,
  Secret), each a pattern, colour and width; every starter has a different pattern, so none
  depends on colour. Days or Watches sets how times read. Deleting a used type draws its
  paths as "No type"; Undo restores it.
- **Drawing.** Lines keep their screen size at every zoom, on a casing of the opposite tone.
  Hidden paths draw faded with an eye-slash on each segment. Labels ("name - time") show on
  hover, on the selected path, and for all paths with Show names, where they fit without
  covering pins or each other (more appear as you zoom in).
- **Making paths** (Director): the Path tool (click a pin, click the map for bends,
  click the end pin; right-click or Backspace drops a bend; Esc drops the draft, a second
  Esc ends the tool), or "Connect to..." on a pin, which lists the map's other pins by
  distance with a search (Enter takes the top one). A new path copies the last type and
  time used. Two paths between the same pins bow apart.
- **Editing.** Click a path to read it; Edit autosaves like the Location form. "..." has
  Place Party on it, Redraw line, Hide/Reveal and Delete (with Undo). With pins unlocked,
  the selected path shows bend handles: drag a bend, drag a "+" to add one, right-click a
  bend to remove it. A Location's side panel lists its paths.
- **Cascades.** Deleting a pin, moving it to another map or removing a map also removes
  its paths, in the same Undo; the confirm counts them.

### Travel (V2.1, point crawl maps)

- The Party sits at a pin or partway along a path. Click the Party (or its status chip) for
  the Party section: where it is and "Travel to" rows ("{place} by {path}", with the time).
  The Party's right-click menu has the same list as a "Travel to" submenu.
- Players get the list only with "Players can move the Party" on, and only along paths they
  see. A drag of the Party snaps back with a hint; on these maps travel is by the list.
- Traveling to a hidden path's far end asks the Director to reveal it and travel, or travel
  without revealing (the leg shows players no path name and no line).
- **Stop partway:** right-click a path > Place Party on it. The card counts time from one end
  (the swap button counts from the other), defaults to half the way and accepts more than 0
  and less than the whole. From partway the list offers going on (the rest of the time) and
  turning back (the time spent).
- Director only: "Place Party here" and "Move Party here" put the Party at a pin (within the
  snap radius) and log it as placed.
- If the path the Party is on is deleted, the Party moves to its nearer end; Undo puts both
  back.
- **Movement:** after a leg or a stop, the Party banner walks the leg's line on every client
  that has the map open (0.6-2 s, by on-screen length, eased; it steps off and onto the
  pins' sides). It plays only for a leg logged in the last 5 s that the viewer may see the
  line of, so a secret leg is still a jump for players. Undo, a placement or a drag jump as
  before; grabbing the Party mid-walk ends the walk. Reduce motion turns it off.

### Party

- One Party across all maps, drawn above pins only on the map it is on. It is either "at"
  a Location (sits beside its pin and follows it) or traveling (free on a map).
- Drag the Party; dropping it within 32 px of a pin makes it "at" that Location. Also
  "Move Party here" in the side panel, and for the Director right-click > Place Party here
  (anywhere on any map).
- Settings (Director): Party name, Party image (or the default banner), "Players can move
  the Party", "Players can add locations".
- The status chip (bottom right, "Party at Old Quarry") goes to the Party: it opens the
  Party's map when it is on another one, then eases the camera onto the Party, zoomed in to
  at least 2x and centered in the part of the map an open side panel leaves visible. On a
  point crawl map it also opens the Party section, as before. Reduce motion makes the move
  instant.

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
  On point crawl maps each leg is one entry ("Traveled from Kell's Ferry to Stonehold by
  King's Road - 2 days"; "Traveled on to" and "Turned back to" from partway) whose route
  follows the path, and a stop is "Stopped on Road, 3 watches from Kell's Ferry". A stop
  right after arriving replaces the arrival. Entries keep the path's name, so a rename or
  delete leaves the history as it was.
- **Undo**: moves, deletes and visibility changes show a toast with Undo (10 s, paused while
  hovered); "Undo last change" in the session log walks back up to 20 steps. An undo is refused if
  someone else changed the same row since.
- Camera: wheel zoom at the cursor (1x fit to 20x), left-drag on empty map, right or middle
  drag, arrow keys pan (Shift for coarse). Each viewer's camera, last map and Show names are
  kept per user and game. Reduce motion (Settings) turns off the zoom, crossfade, the
  camera control fade and the Party's walk along a leg.

## 2. Architecture

Load order (the CodeMod file list must match):

| # | File | Responsibility |
|---|---|---|
| 1 | `RegionMapConstants.lua` | Names, limits, metrics, timings |
| 2 | `RegionMapCopy.lua` | Every on-screen string, keyed by its V2_COPY id; `Copy.T(id, args)` |
| 3 | `RegionMapJournal.lua` | Journal access and opening |
| 4 | `RegionMapRecords.lua` | Record types, safe reads, validation, uploads |
| 5 | `RegionMapModel.lua` | Location tree, permissions, visibility, writes, Party, settings, search, map kind and border, cascades |
| 6 | `RegionMapUndo.lua` | Undo entries and the toast queue |
| 7 | `RegionMapLog.lua` | Session log entries, merging, route points, cap; legs and stops and their one wording (`LegCopy`) |
| 8 | `RegionMapPaths.lua` | *V2.1.* Path index and viewer filter, path writes, types and time unit, time wording and time fields, path names, the other end |
| 9 | `RegionMapTravel.lua` | *V2.1.* Travel options, travel, stop partway, the Party's spot on a path |
| 10 | `RegionMapStyles.lua` | Style rules (ThemeEngine.MergeStyles) |
| 11 | `RegionMapSession.lua` | Context type, local view state and preferences, the small controls every panel builds (label, button, segments, text area, icon button, focus) |
| 12 | `RegionMapCanvasTools.lua` | Layout math, segment clipping, the panel pool, Add, Move, ruler and scale tools, route and ruler overlay, Soft fade |
| 13 | `RegionMapPathLayer.lua` | *V2.1.* Path drawing (pooled pieces), labels, badges, hit test, draft line and bend handles |
| 14 | `RegionMapPathTool.lua` | *V2.1.* Path tool steps, Connect, Redraw line, bend edits |
| 15 | `RegionMapCanvas.lua` | Image, pins, Party, camera, drags, transitions |
| 16 | `RegionMapSidePanel.lua` | Location panel read and edit modes, "..." menu |
| 17 | `RegionMapPathPanel.lua` | *V2.1.* Path read and edit, Connect to... picker, a Location's Paths section |
| 18 | `RegionMapPartyPanel.lua` | *V2.1.* Party section, Travel to menu, hidden-path question, stop card |
| 19 | `RegionMapAtlas.lua` | Atlas gallery and New map |
| 20 | `RegionMapPopovers.lua` | Breadcrumb, Search and Settings popovers |
| 21 | `RegionMapImport.lua` | *V2.1.* JSON import: read, check, preview, create |
| 22 | `RegionMapLogPanel.lua` | Session log panel |
| 23 | `RegionMapPresent.lua` | Show to players send and receive |
| 24 | `RegionMapPanel.lua` | Shell: toolbar, camera controls, status, banners, toasts, Esc layers, layout, refresh |
| 25 | `RegionMap.lua` | Capability check, registration, host window adapter, Expand |

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
| `RegionMapLocations` | One row per Location: parent, name, u/v on the parent's map, pin style, tier, icon, visibility, image and its revision, map shared, scale, pace, owner, revision, soft delete. V2.1 adds optional `mode` ("pointcrawl"; absent means free) and `border` (absent means none) |
| `RegionMapLocationDetails` | Description and journal link, keyed by Location id (V1 row format) |
| `RegionMapLocationDirectorNotes` | Director note, keyed by Location id (V1 row format) |
| `RegionMapPaths` | *V2.1.* One row per path: map, ends `aId`/`bId`, bends (u/v), name, type id, time and back/backTime (watches), description, note, visibility, audit fields, revision, soft delete |
| `RegionMapLogEntries` | Session log entries: kind, map, Location, route points, merged count, time, author, note. V2.1 adds the kinds `leg` and `stopped` with path id and name, from/to, time, spent, rest ("on"/"back") and secret |
| `regionMapState` document | Party (map, Location, u/v, revision; V2.1 adds `pathId`, `pathFrom`, `spent`), Party name and image, Players can move the Party, Players can add locations; V2.1 adds `timeUnit`, `pathTypes` (absent means the starter set), `lastBorder` and `stateMeta` (a revision per key, for undo); checkpoint-backed |
| `regionmap:preferences` setting | Per user and game: last map, cameras (keyed by image revision), Show names, Reduce motion; V2.1 adds the last path type and time (`lastPathStyle`) |

- Every write rechecks role, ownership, map access and the Party switch. These are checks
  between trusted clients, not server enforcement.
- Writes send only the changed fields onto the freshest local row; the side panel shows
  Saving... / Saved for confirmed table writes.
- V1 tables (`RegionMapRecords`, `RegionMapLabelRecords`, `RegionMapTombstones`) are no
  longer read and stay in the game data unused (decision 8.3: no migration, no rollback).
- V2.1 changes are additive: rows and documents written by V2 read as before (free maps, no
  border, no paths).

## 4. Open decisions

| Topic | Current state |
|---|---|
| Hidden Locations and Director notes sync to every client; hiding is UI-only. | Accepted (as in V1); notes are labeled "Hidden from players' screens". |
| Two clients editing one row at once. | Last write wins per field; undo refuses after a remote edit. True merges need a host patch API. |
| Players cannot set Reduce motion. | It lives in Settings, which is Director-only (D11c). Needs a decision: a player-visible "Only for you" section, or follow a host setting. |
| Live theme switch. | Checkboxes (and the host's own window title bar) keep the old colors until the window is reopened. Host limitation; not worked around. |
| Torn edge and Frame borders (V2.1, K9). | Wait for the user's art; the art ids in Constants are empty until then. |
| `@danger` as text (host). | In Default, MCDM and Warm Gold it reads 3.4-4.0:1 on `@bg`, under 4.5:1. The mod puts warning text in `@fgStrong` with a `@danger` bar instead. A host fix would be a darker or lighter text variant of the token; not a mod change. |

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

V2.1 paths, measured 2026-10-10 the same way: the PC test map with 244 test pins (250 in
all) and 150 test paths (160 in all, 315 segments, every pattern), kept only in memory,
timed inside the path layer. The app was unfocused, which caps it at 30 fps, so whole-frame
samples only show costs over 33 ms; with and without the test paths they matched.

| Measure | Result |
|---|---|
| Location and path index rebuild | 8 ms |
| Path layer refresh with no change (Bind) | 6-8 ms |
| First draw at Fit, 1401 line pieces | 123 ms, then one re-place of ~115 ms as the window settles its size |
| First draw three zoom steps in, 1963 pieces | 554 ms (panel creation, ~0.14-0.28 ms a piece; once per window) |
| Zoom re-layout (re-places every piece) | 23-34 ms; 77-125 ms the first time a deeper zoom grows the pool |
| Pan | ~0.02 ms a frame in the path layer (the layer slides); a long pan re-places, as a zoom |
| Hover hit test / label pass with Show names | 0.2 ms / ~1 ms |
| Pieces by zoom, Fit to four steps in | 1401, 1639, 1963, 2329, then the 2500 cap (`C.pathPieceLimit`): past it a segment draws solid |

Optimization pass, measured 2026-10-11 the same way (250 pins, 160 paths, 513 log entries in
memory), before and after:

| Measure | Before | After |
|---|---|---|
| Refresh with nothing changed | ~20 ms | 0.8 ms |
| Refresh after a data change | ~43 ms | ~28 ms |
| All three caches rebuilt (Locations, paths, log) | 21 ms | 11 ms |
| A token move, chat line or other game update | rebuilt all three caches | no rebuild |
| Open the log | 700-830 ms in one frame (3168 panels) | 54 ms, then 40 rows a frame |
| Refresh with the log open | rebuilt every row on any game update | 1 ms; a new entry builds one row |
| Animated zoom (Fit, Go to Party) | every line piece placed each frame | placed once, when it lands |
| Zoom step under Reduce motion | 24-38 ms | 22-30 ms |
| Window build | 160-175 ms | 145-160 ms (Settings is built on first open) |

How it stays cheap: one data revision (`RegionMapModel.Revision`) moves only when an Overland
Map table changes (the engine's `tablesUpdateId`, this client's writes, or another client's
change seen by the window), and the caches and the canvas, path and log signatures key on it;
a refresh that finds the same inputs skips the pins, the lines, the route and the log rows;
mid-zoom the line and route layers stretch as a whole and are placed for real once the zoom
settles (`C.zoomSettleSeconds` after the last wheel notch); line pieces write only the style
values that changed; pins and the Party sit on one layer that slides as a whole on pan;
pin panels are reused across refreshes, keyed by Location id, and restyled only when they
changed; name plates and badges are created only when shown; route dots are rebuilt only
when the log changes, after a zoom or after a pan of more than half the view; the canvas
thinks every 0.02 s only while hovered, dragging or animating (0.25 s otherwise); refreshes
coalesce over 0.05 s; camera saves are debounced 0.5 s. Pins appear only once the image size
is known, and the new image fades in only after it has loaded. Paths follow the same plan:
their pieces are pooled (collapsed, never destroyed), placed only on screen plus half a view
around it, and placed again only after a zoom, a resize, a change or a pan of half a view.

## 6. Acceptance status

Verified live on the Director client: every M2-M4 surface (see the build notes in
TECH_TASK_V2.md section 7b), the styles and accessibility pass (720x480, 1000x800,
Expanded; Font Size 80/100/140; Default and Warm Gold with no `THEME_ENGINE` log lines;
faded camera controls at 3:1 or better), and on one player client the M1 permissions and
Show to players.

**V2.1**, verified live on the Director client (build notes in TECH_TASK_V2_1.md section
8): size guidance; Soft fade; import (24 entries with one Undo, duplicates, skips, over the
limit, bad and empty files); both map kinds; every path pattern, label, hidden path and
cascade with its Undo; the Path tool, Connect to... by keyboard, Redraw line and bend
handles; travel by list and menu, stop partway, going on and turning back, Q14 replacement,
hidden-path travel both ways, the Party moved off a deleted path; View as player for paths,
travel options and the log. Accessibility pass (V21-18): line and casing contrast 6.5:1 or
more, each line or its casing 4.5:1 or more on light, mid, dark and sea art, hidden lines
3:1 or more against their casing, the toast Undo 5.8:1 or more, warning text in
`@fgStrong`; Font Size 80/100/140; Default and Warm Gold with no `THEME_ENGINE` lines; every
new action reachable without drag or hover.

Still open for V2.1 (needs a player client): the Travel list with "Players can move the
Party" off and on, hidden paths absent, secret legs anonymous, no Move Party here on point
crawl maps; Backspace in the Path tool (the bridge's keys do not reach `dmhub.KeyPressed`);
the native file dialog for import.

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
