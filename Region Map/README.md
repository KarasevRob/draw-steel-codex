# Overland Map (Region Map)

An opt-in CodeMod for DMHub / Draw Steel Codex, named **Overland Map** in the in-app mod tools
(id `ec447c62-03db-4416-a5a2-0b013c0f3893`) and on screen. Until 2026-10-08 it was called
Region Map. The code still uses that name: this folder, the `RegionMap*` files and
namespaces, and the table and document names, which are stored and never renamed.

The Director builds a tree of image-based maps and Locations; the group reads them, adds
their own places and follows one shared Party across the maps. The mod owns its own window,
canvas and data. It does not touch
tactical maps, tokens, combat rules or character content.

This README describes current behavior and the runtime file order.
[IDEAS.md](IDEAS.md) contains only unfinished work.
[Tests](tests/README.md) lists runnable checks, recorded live evidence and remaining
verification gaps. Development deployment and Git commits do not by themselves
publish a new installable CodeMod package.

The original [V2](docs/V2_BRIEF.md) and [V2.1](docs/V2_1_BRIEF.md) decision ledgers
retain design decisions; the retired TECH_TASK task IDs have been removed from source
comments. Later feature contracts supersede
changed behavior. [V2_COPY.md](docs/V2_COPY.md) records agreed wording, while
[RegionMapCopy.lua](RegionMapCopy.lua) is the runtime source of text.
[Maintenance candidates](docs/CLEANUP_AUDIT.md) retain unresolved audit leads.

## 1. Behavior

### Fullscreen, in-app window, and popout

- One registered panel, `Overland Map` (game menu and icon rail), opens in the viewer's
  last in-app view; the initial view is fullscreen. Fullscreen covers the board behind
  other windows and the rails, hiding the action bar until the viewer leaves fullscreen.
- **Window view** switches to a movable window inside Codex; **Fullscreen** switches
  back. This keeps the same map, camera, selection, editors, and unfinished path alive.
  A themed border outlines the smaller window above its map content; fullscreen has none.
  The window starts centered at 900x600, minimum 720x480, and remembers its size and
  position per viewer/game. Drag the title or resize the edges/corners. Window options
  offers **Reset window size and position**. A viewport too small for the minimum uses
  fullscreen temporarily, preserving the preferred mode and window geometry.
- The board and action bar remain usable around the smaller window. Activating its
  rail/menu entry raises it if covered; activating it again while foremost closes it.
  The view toggle and Pop out remain separate toolbar controls. Tab from the focused
  map uses the engine's focus navigation; Enter/Space activates a focused control.
- Each client chooses its own view. Show to players keeps an already-open client's
  current host, or opens the remembered view when closed. The design and validation
  contract are in [docs/PANEL_VIEW_BRIEF.md](docs/PANEL_VIEW_BRIEF.md).
- **Pop out** (toolbar) moves the map into its own OS window (1000x720, minimum 720x480);
  **Return to app** in that window's toolbar restores the remembered in-app view. The popout's own
  "return to the app" button only closes it: the host cannot reopen an action panel. While
  popped out, the rail button raises that window.
- Native popout wheel zoom is currently blocked by engine event routing. Use the
  +/- camera buttons, or the in-app window view. Reproduction and the proposed engine
  change are in [the wheel handoff](docs/POPOUT_WHEEL_ENGINE_HANDOFF.md).
- **Close** (fullscreen toolbar or window title bar) and Esc at the Atlas close the
  in-app map through the existing edit/import guard. Foreground windows take Esc first.
- Layout: breadcrumb top-left, toolbar top-right, camera controls bottom-left (they fade
  after 2 s without pointer movement), Party status bottom-right, side panel over the
  map's right edge (full width below 720 px).
- Toolbar, in order: Search, Add, Import (Director, open maps only), Path (Director, point crawl maps only), Lock, Ruler, Show to
  players (Director), View as player (Director), Session log, Settings (Director), then
  Window/Fullscreen, Pop out, and Close (fullscreen only), or Return to app (native popout).
  Icons with tooltips.
- **Esc** closes one layer at a time: a tool or text field, then edit mode, then a popover
  or the side panel, then goes up one map, and at the Atlas closes the in-app map.
- Left-clicking elsewhere on the map or Atlas dismisses the mod's context menu. Menu
  actions still run normally; opening another menu replaces the previous one.
- While a side panel (Location, path, label, Party or log) is open, the map can pan left by the
  panel's width, so a pin under the panel can still be reached at Fit (V2.1).

### Map labels

- Add independent lettering with **+ > Add label** or **Add label here**. Labels have no
  Location pin, description, child map, or Party destination.
- The Director manages every label. **Players can manage their own labels** defaults
  off in Settings; turning it off freezes existing player labels. View as player is
  always read-only. Director labels start Hidden; player labels start Revealed.
- Only the Director changes visibility. Players can see/search a label only while it is
  Revealed and its map is accessible; ownership does not bypass those checks.
- The editor supports explicit line breaks, available fonts, bold/italic, alignment,
  color, size, rotation, spacing, outlines, and Auto contrast / Plate / None / Image backgrounds. Auto
  contrast is a snug black/white backing. Size is a percentage of map width (0.1-25%).
  Text grows with map zoom, without overlap hiding or Font Size changing its proportions.
- Text permits 256 Unicode characters and 1,024 bytes, with explicit newlines and no
  automatic wrapping. Successful formatting is remembered per viewer/game, excluding
  text, rotation and visibility. Missing fonts fall back without rewriting the stored font.
- **Positions locked/unlocked** controls movement of both location pins and labels.
  Unlock, select a label, then drag it. Selected labels have resize and rotation handles,
  with numeric size/angle fields in the editor. There are no separate Move label actions.
  Locked text passes ordinary gestures through; search/context actions still open its editor.
- **Show labels** defaults on and is a local preference, separate from Show names. Search
  temporarily shows its selected permitted label even when Show labels is off. Mixed
  search results distinguish Locations from labels and include their map breadcrumbs.
- Valid text saves after 1.5 seconds, field exit, or editor closure. Each confirmed batch,
  transform, creation, and deletion has one Undo. Blank unsent drafts are discarded.
  Failed saves retain Retry; pending work rechecks permissions and cannot retarget another
  label. Map deletion/removal includes its labels in the same Undo.

The agreed design is [docs/LABELS_BRIEF.md](docs/LABELS_BRIEF.md); measured results and
remaining validation limits are in [tests/LABELS.md](tests/LABELS.md).

### Locations and maps

- A **Location** may have a pin on its parent's map, its own
  map image, or both. Top-level Locations are the **Atlas** (a gallery of cards, with a
  New map card for the Director).
- Each Atlas thumbnail shows the Director **Hidden** or **Revealed**, based on whether
  that map is shared with players. New map and Add map display **New maps are hidden
  from players until you share them.** on both creation steps. Replacing an existing
  map image preserves its sharing state and does not show the creation notice.
- Atlas map names stay on one line and end with an ellipsis when they do not fit the
  card. Hovering the card shows the complete name; the saved name is unchanged.
- **Map actions from the Atlas** (Director): each card's "..." menu offers Open map, Edit
  (name, description and notes), Import locations, Replace map image, Map settings (scale,
  pace, border and pin text), journal actions, sharing, Show this map to players and Delete.
  Right-clicking a card opens the same menu, also used in the top-level map's side panel.
  Import, Settings and Show to players open that card's map first. Delete confirms the
  contained Locations, paths and labels; one Undo restores the map and its contents. Long menus
  scroll in short windows.
- The breadcrumb shows Atlas > ... > current map; every part is clickable and long names truncate with an ellipsis. "Open map" in
  the side panel zooms into the pin and crossfades to its map.
- **Reading a parent from the breadcrumb.** Hover a Location crumb to see the start of its
  description (300 characters). Right-click a parent's crumb to read all of it in the side
  panel while the current map stays open; its Open map button goes up to it.
- Pins have three styles (Icon + name, Name plate, Icon only with the name on hover) and
  three tiers (Major, Normal, Minor). Pins keep a constant screen size and scale with Font
  Size; zoomed out, names hide by tier (Minor first). Icons come from a curated, theme-tinted
  set or any library image. A pin with its own map shows a map badge.
- **Settings > This map > Pin text** formats every direct pin name on that map, including
  player-owned pins. Font, separate Major/Normal/Minor sizes (6-72 pt, one decimal),
  bold/italic and left/center/right anchoring save immediately. Text appearance contains
  spacing, text color, outlines and Default/Auto contrast/Plate/None/Image backgrounds. Reset restores
  the existing theme appearance; confirmed changes support guarded Undo. Parent and child
  maps have independent settings. See [the design](docs/PIN_TEXT_BRIEF.md) and
  [verification](tests/PIN_TEXT.md).
- Labels and pin names support custom outline colour/thickness and uploaded still-image
  backgrounds, with Fit/Fill/Stretch, automatic padding or manual dimensions, offsets and
  opacity. Directors manage all image settings; player owners retain text/outline edits.
  Manual backgrounds stay fixed during text resizing. See [the decided design](docs/TEXT_APPEARANCE_BRIEF.md)
  and [verification](tests/TEXT_APPEARANCE.md).
- Pin hover shows the full name and the first two description sentences, capped at
  300 Unicode characters with `...` when shortened. Director notes and journal contents
  never enter the preview; existing pin visibility rules still apply.
- **Visibility.** A pin is Hidden (Director only, shown dimmed with an eye-slash badge) or
  Revealed. A Location's own map has a separate Map shared switch.
- **Side panel.** Click a pin to read it: description, journal link, Party here, Move Party
  here, Open map, Edit, "..." (Move, Move to map, Show/Hide, Add map, Replace image, Remove
  map, Link journal, Delete) and the Director note (Director only). Edit turns the panel into
  a form that autosaves after 1.5 s without typing or on leaving a field.
- **Create**: toolbar Add > Add location then click the map (sticky until Esc), or right-click > Add
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
- Limits: names 1-256 characters on one line; description 4000; Director note 8000; nesting
  16 levels. A map holds any number of Locations (the 250 cap was removed 2026-10-10;
  performance is measured only up to 250 pins a map, section 5). A game holds any number
  of path types (the 24 cap was removed 2026-10-11; the whole list is stored in
  `regionMapState` and rewritten on every type edit).

### Location and path images

- Each Location or path can have one still image from the Journal image library. Only
  the Director chooses, replaces or removes it, including on player-owned Locations.
- The preview sits before the description, after title/status and path travel details.
  Its 160-pixel frame fits the whole image. Click it or **Open image** to use the existing
  viewer in the same window; Enter also opens it in the active read section when no
  input, search, picker or modal has focus. Click/Escape dismisses the viewer.
  Enlarged images fit the originating window while retaining the viewer's 1024-pixel cap.
- Viewing is local. Opening or closing changes neither the map nor the Party and does
  not affect another viewer. An open image remains a snapshot if its source changes.
- Visibility follows the object. Players cannot see path images while either endpoint
  is hidden. Players editing their own Location see a read-only preview.
- Loading waits for the image event and valid dimensions. After 10 seconds it offers
  **Image unavailable.** and **Retry**; a late successful load still recovers. Missing,
  unreadable and video assets cannot open. Asset changes can recover the selected preview.
- Changes use normal save feedback and one Undo entry. A chooser captures its object and
  attachment value; navigation, closing and reload cancel it, and a newer attachment
  wins over a delayed upload. Removing a reference leaves the library asset intact.
- Optional `artworkImageId` fields keep the current schemas. Missing/malformed fields
  never invalidate the owning row. Map replacement/removal and object deletion Undo keep
  artwork. JSON import does not accept attachments.

The helper is registered before both detail panels.
[Artwork checks](tests/ARTWORK.md) record implementation evidence and validation limits.

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

- Director: the **Import locations** button beside Add in the top toolbar
  opens a card for pasted JSON or a JSON file ([docs/IMPORT_FORMAT.md](docs/IMPORT_FORMAT.md))
  into the open map. The editor has a Swagger-style field reference with **Copy contract**
  and a hidden two-Location example.
- Paste accepts up to 100,000 Unicode characters; files keep their uncapped import path.
  Back preserves pasted text. Replacing or discarding a nonempty draft asks first; drafts
  are not saved across closing the card, app exit or Lua reload. Native OS close cannot prompt.
- A preview lists the count, skipped entries with the reason for each, and names already on
  the map. Entries without u/v go on a grid near the center. One Undo removes confirmed
  imported pins whose row, description and note have not changed since. Preview shows
  at most 100 reasons and 100 duplicate names, with exact totals. Import is disabled
  while a batch is running. See the [import contract](docs/IMPORT_FORMAT.md) for failure
  handling and the retained description/note rows after Undo.

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
  the Party", "Players can add locations", "Players can manage their own labels".
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
- **Search**: visible Locations and labels across accessible maps, with kind and map
  breadcrumbs. Arrow keys select, Enter opens, and Ctrl+Enter edits a permitted label.
- **Ruler**: click-click or drag. On a calibrated map it shows distance and, with a pace,
  travel days; otherwise a share of the map width. The Director sets the scale (two points
  plus a distance, miles or km) and pace per map in Settings.
- **Session log**: automatic Party entries (arrived, traveling, placed; consecutive free
  drops merge), a Director note per entry, and the past route drawn as dots on the map
  (Show route switch, off by default). Add note, Undo last change and Show route sit below
  the title, above the entries. Clicking an entry opens its map. The newest 500 entries are kept per game.
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

Load order (31 runtime files; the CodeMod file list must match):

| # | File | Responsibility |
|---|---|---|
| 1 | `RegionMapConstants.lua` | Names, limits, metrics, timings |
| 2 | `RegionMapCopy.lua` | Every on-screen string, keyed by its V2_COPY id; `Copy.T(id, args)` |
| 3 | `RegionMapJournal.lua` | Journal access and opening |
| 4 | `RegionMapRecords.lua` | Record types, safe reads, validation, uploads |
| 5 | `RegionMapModel.lua` | Location tree, permissions, visibility, writes, Party, settings, search, map kind and border, cascades |
| 6 | `RegionMapUndo.lua` | Undo entries and the toast queue |
| 7 | `RegionMapTextAppearance.lua` | Appearance validation, font fallback, contrast, image loading and geometry; no GUI constructors |
| 8 | `RegionMapLabels.lua` | Label records, permissions, mixed search, immutable save queues and Undo |
| 9 | `RegionMapLog.lua` | Session log entries, merging, route points, cap; legs and stops and their one wording (`LegCopy`) |
| 10 | `RegionMapPaths.lua` | *V2.1.* Path index and viewer filter, path writes, types and time unit, time wording and time fields, path names, the other end |
| 11 | `RegionMapTravel.lua` | *V2.1.* Travel options, travel, stop partway, the Party's spot on a path |
| 12 | `RegionMapStyles.lua` | Shared control rules, component-style assembly and theme subscriptions |
| 13 | `RegionMapSession.lua` | Context, view preferences, shared controls, appearance editor and image panels, host controls |
| 14 | `RegionMapPinText.lua` | Map-wide pin typography, image/name composition, hover previews and save queue |
| 15 | `RegionMapCanvasTools.lua` | Layout math, segment clipping, the panel pool, Add, Move, ruler and scale tools, route and ruler overlay, Soft fade |
| 16 | `RegionMapPathLayer.lua` | *V2.1.* Path drawing (pooled pieces), labels, badges, hit test, draft line and bend handles |
| 17 | `RegionMapLabelLayer.lua` | Map lettering, contrast backings, transformed hits and selection handles |
| 18 | `RegionMapPathTool.lua` | *V2.1.* Path tool steps, Connect, Redraw line, bend edits |
| 19 | `RegionMapCanvas.lua` | Image, pins, Party, camera, drags, transitions |
| 20 | `RegionMapArtwork.lua` | Selected-object preview, Director picker, loading, guarded local viewer and writes |
| 21 | `RegionMapSidePanel.lua` | Location panel read and edit modes, "..." menu |
| 22 | `RegionMapPathPanel.lua` | *V2.1.* Path read and edit, Connect to... picker, a Location's Paths section |
| 23 | `RegionMapLabelPanel.lua` | Label formatting editor, guarded color picker and save feedback |
| 24 | `RegionMapPartyPanel.lua` | *V2.1.* Party section, Travel to menu, hidden-path question, stop card |
| 25 | `RegionMapAtlas.lua` | Atlas gallery and New map |
| 26 | `RegionMapPopovers.lua` | Breadcrumb, Search and Settings popovers |
| 27 | `RegionMapImport.lua` | *V2.1.* JSON import: read, check, preview, create |
| 28 | `RegionMapLogPanel.lua` | Session log panel |
| 29 | `RegionMapPresent.lua` | Show to players send and receive |
| 30 | `RegionMapPanel.lua` | Shell: toolbar, camera controls, status, banners, toasts, Esc layers, layout, refresh |
| 31 | `RegionMap.lua` | Capability check, registration, fullscreen host, popout |

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
| `RegionMapMapLabels` | Schema-1 independent lettering: map, text, u/v, font, size, angle, spacing, alignment, bold/italic, colors/background, visibility, owner, audit/revision and soft delete |
| `RegionMapLogEntries` | Session log entries: kind, map, Location, route points, merged count, time, author, note. V2.1 adds the kinds `leg` and `stopped` with path id and name, from/to, time, spent, rest ("on"/"back") and secret |
| `regionMapState` document | Party (map, Location, u/v, revision; V2.1 adds `pathId`, `pathFrom`, `spent`), Party name and image, Players can move the Party, Players can add locations; V2.1 adds `timeUnit`, `pathTypes` (absent means the starter set), `lastBorder` and `stateMeta` (a revision per key, for undo); checkpoint-backed |
| `regionmap:preferences` setting | Per user and game: last map, cameras (keyed by image revision), Show names, Reduce motion; V2.1 adds the last path type and time (`lastPathStyle`) |

- Every write rechecks role, ownership, map access and the Party switch. These are checks
  between trusted clients, not server enforcement.
- Labels add `playersCanManageLabels` to `regionMapState` (absent means false), and
  `showLabels` (absent means true) plus `lastLabelFormat` to viewer preferences. Their
  new table is independent of the unused V1 label table; no migration is required.
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
| Torn edge and Frame borders (V2.1, K9). | Await the user's art and rendering integration; supplying the Constants art IDs alone is not sufficient. |
| `@danger` as text (host). | In Default, MCDM and Warm Gold it reads 3.4-4.0:1 on `@bg`, under 4.5:1. The mod puts warning text in `@fgStrong` with a `@danger` bar instead. A host fix would be a darker or lighter text variant of the token; not a mod change. |

## 5. Performance

Recorded measurements are fixture-specific, not guarantees for larger maps or other
clients. They are kept here because future rendering work needs a comparison point.
All timings below precede the review fixes and the current pin-name composition. In
particular, the 221 ms first draw has not been remeasured. Lazy image panels, targeted
label updates and batched imports have offline regression coverage, not new app timings.

| Fixture and date | Observed cost |
|---|---|
| 250 pins held in memory, 2026-10-07 | Pan 16.6 ms/frame at the 60 Hz display cap; first draw 221 ms; pin refresh 2.6 ms |
| 150 paths on the active map, 2026-10-10 | First draw at Fit: 1,401 pieces, 123 ms; zoom layout: 23-34 ms, with extra pool-growth cost |
| Large session log, 2026-10-11 | First batch 54 ms, then 40 rows/frame; unchanged open-log refresh about 1 ms |
| Focused PC test map, 2026-10-13: about 760 path pieces, 600 route dots and 33 pins | Pan improved from over 100 ms/frame to 16.7 ms after position writes stopped using selfStyle; animated Fit measured 16.7 ms/frame |
| Same zoom work with stable per-segment pooling, unfocused app at 30 Hz | Four wheel notches dropped from five frames over 33 ms to one; this is not a focused FPS benchmark |

Current rendering constraints:

- Each selfStyle write can rematch a panel and its subtree against the theme rules.
  Map positions use panel.x/y instead; avoid style writes during ordinary pan.
- Revision/signature caches skip unchanged pins, paths and log rows. Unrelated game
  updates should not rebuild the mod's indexes.
- Pins and Party move as a layer while panning. Paths and route marks use pooled pieces
  inside the view plus a margin; crossing the margin triggers layout.
- During zoom, Stretch repositions existing pieces; final dimensions/styles update
  when zoom settles. Pools retain pieces per segment so most styles stay unchanged.
- The 2,500 path-piece threshold simplifies patterned segments to solid lines.
  It is not a hard memory or geometry cap.
- The log builds rows in batches. Canvas think runs at the active rate while hovered,
  dragging or animating; camera saves and model refreshes are debounced.
- Images load asynchronously; artwork previews load only for the selected object.

[Curved-path research](docs/CURVED_PATHS_RESEARCH.md) records later construction
measurements and native-shape lifecycle questions. [Label checks](tests/LABELS.md)
and [text appearance checks](tests/TEXT_APPEARANCE.md) retain their rendering evidence.

## 6. Acceptance status

See the [test index](tests/README.md) for commands and feature-specific evidence.
The review follow-up adds offline import/failure checks, window input ownership checks,
pin-format preservation and Undo checks, and CI for the offline suites. See the
[review follow-up](docs/REVIEW_FIXES_2026-10-17.md) for current validation and merge notes.
The [2026-10-17 live validation](tests/LIVE_REVIEW_2026-10-17.md) records the connected-app
pass, three further interaction fixes, cleanup and publication. Concurrent-edit tests
were skipped at the user's request.

Earlier live checks cover the creation tools, breadcrumb truncation, tooltip cleanup,
window sizing, label/pin formatting, image backgrounds, import preview, paths and
travel on the Director client. Model fixtures cover permissions, failure/Retry,
remote rebasing and guarded Undo. These do not replace separate player-client tests.

Still requiring targeted verification:

- Real player-client editing, visibility, presentation, Party movement, secret legs,
  asset access and late joins; simultaneous edits and remote Undo refusal.
- The complete keyboard/focus/Escape matrix, including Tab and the intermittent
  Space/freeze interaction recorded in the [window brief](docs/PANEL_VIEW_BRIEF.md).
- Native file-picker cancellation, physical clipboard paste and fresh image uploads.
- Native popout wheel routing remains an [engine issue](docs/POPOUT_WHEEL_ENGINE_HANDOFF.md).

## 7. Development

- Follow the repository `CLAUDE.md`, `UI_BEST_PRACTICES.md`, `ThemeEngine.md`,
  `DefaultStyles.md` and `STYLE_GUIDE.md`. ASCII-only Lua. Every on-screen string comes
  from `RegionMapCopy.lua`.
- Change only files in `Region Map/`. Register new files with
  `mcp__dmhub__register_lua_file` in the order above; never edit `main.lua`.
- Check syntax with `..\dependencies\lua\bin\luac.exe -p`. The required type checker is
  `../tools/lua-typing/check.ps1`; it is absent in this checkout. The available
  `../dependencies/check-mod.ps1 -Mod 'Region Map'` loads other mods as libraries and
  checks this mod. It is not the prescribed whole-repository check.
- Deploy with explicit paths so nothing outside the runtime files is copied:
  `.\deploy.ps1 "Region Map/RegionMapConstants.lua" ...`, then reload Lua. The app reads
  dev mods from a dev-mod folder named after the CodeMod, so these files go to
  `<git folder>\Overland Map\`, not `Region Map\`. Use the repository deployment workflow.
