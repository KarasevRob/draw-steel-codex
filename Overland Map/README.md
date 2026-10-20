# Overland Map

An opt-in CodeMod for Draw Steel Codex, with unchanged module ID
`ec447c62-03db-4416-a5a2-0b013c0f3893`. The 2026-10-18 rewrite uses Overland names
throughout its runtime and fresh storage. Old development maps, Party state, logs
and preferences are intentionally not loaded or migrated.

The Director builds a tree of image-based maps and Locations; the group reads them, adds
their own places and follows one shared Party across the maps. The mod owns its own window,
canvas and data. It does not touch
tactical maps, tokens, combat rules or character content.

This README describes current behavior and the runtime file order.
[IDEAS.md](IDEAS.md) contains only unfinished work.
[Tests](tests/README.md) lists runnable checks, recorded live evidence and remaining
verification gaps. Development deployment and Git commits do not by themselves
publish a new installable CodeMod package.
The rewrite was published on 2026-10-18; see the
[publication record](tests/LIVE_REWRITE_2026-10-18.md#publication).

The original [V2](docs/V2_BRIEF.md) and [V2.1](docs/V2_1_BRIEF.md) decision ledgers
retain design decisions; the retired TECH_TASK task IDs have been removed from source
comments. Later feature contracts supersede
changed behavior. [V2_COPY.md](docs/V2_COPY.md) records agreed wording, while
[OverlandMapCopy.lua](OverlandMapCopy.lua) is the runtime source of text.
[Maintenance candidates](docs/CLEANUP_AUDIT.md) retain unresolved audit leads.
[Tabletop adaptation report](docs/TABLETOP_ADAPTATION_REPORT.md) examines reusable
UI patterns across the mod, with source links and code examples. Its recommendations
are research, not approved feature designs.

## 1. Behavior

### Fullscreen, in-app window, and popout

- On a Tabletop-capable build, drag a card out of the windowed Atlas onto bare table
  space, or use its focusable **Open on tabletop** control from either in-app view.
  This opens the map in the existing window and keeps placement personal.
  **Minimize** retains the content and drafts in a movable table button; the button can
  dock to either rail. Restore from that button, the launcher, Ctrl+Tab, the Windows menu,
  or a presentation. See [Tabletop placement](docs/TABLETOP_PLACEMENT.md) for the contract
  and current verification limits.
- Open and minimized in-app layouts restore on rejoin and Lua reload without taking
  focus. Explicitly closed windows stay closed. Atlas selection, window geometry and
  minimized-button position are remembered per viewer/game. Native windows retain the
  existing same-session restoration policy; a full app restart does not recreate them.
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
  players (Director), View as player (Director), Session log, Map aids (Director), Settings (everyone), then
  Window/Fullscreen, Pop out, and Close (fullscreen only), or Return to app (native popout).
  Icons with tooltips.
- The Lock button is highlighted while positions are locked. Maps open locked;
  a blocked pin drag shows **Positions are locked** with an **Unlock** action.
  Dragging over locked labels or map aids quietly pans the map without moving the object.
- **Esc** commits and closes Quick Add before stopping its placement tool. Other layers close
  one at a time: a tool or text field, then edit mode, then a popover
  or the side panel, then goes up one map, and at the Atlas closes the in-app map.
- Left-clicking elsewhere on the map or Atlas dismisses the mod's context menu. Menu
  actions still run normally; opening another menu replaces the previous one.
- While a side panel (Location, path, label, Party or log) is open, the map can pan left by the
  panel's width, so a pin under the panel can still be reached at Fit (V2.1).
  Selecting a location never pans the camera. Closing a panel eases the camera back
  into its normal bounds; Reduce Motion applies that adjustment immediately.

### Compass, scale bar and hover text

- **Settings > Only for you** includes Show compass, Show scale bar and Show hover
  text, all initially on. These choices affect only your view across maps in this
  game. Show names and Show labels retain their camera shortcuts and are also in
  Settings. Players and View as player see only this personal section.
- The **Map aids** compass button in the top toolbar opens a separate Director editor
  to add, edit or remove each aid independently.
  Maps start without aids. Both follow the artwork when panning, zooming or resizing.
- The compass uses the uploaded compass icon or a custom still image. Set image width,
  clockwise rotation and opacity; optionally show and format its north label. North
  follows the image's original top edge while the text stays upright.
- Set the map scale before adding a scale bar. **Distance** determines its measured
  length in the map's units. The four alternating segments show 0, midpoint and total;
  recalibration preserves distance. Text and background changes never change the
  measured endpoints. Overlapping labels stagger into additional rows.
- **Place on map** takes one click; Enter uses the visible centre and Escape cancels.
  **Find on map** moves the camera. X/Y fields place the anchor by percentage. Unlock
  positions to click-drag an aid directly. A click opens its editor, including while locked.
  Drag the compass corner to resize, or **R** to rotate. The camera brings hidden
  handles into view after selection or release without moving the saved anchor.
  Escape clears the selection. The editor also offers **Unlock positions**. Editing
  temporarily reveals the aid even if your personal visibility is off. Closing the
  editor clears its handles.
- Both support the existing font, emphasis, alignment, spacing, colour, outline and
  Auto contrast / Plate / None / Image background controls, defaulting to **None**.
  Existing saved background choices stay unchanged. Saves use Retry and guarded
  Undo. Missing compass artwork is hidden without erasing its reference; missing
  decorative artwork uses automatic contrast. Invalid calibration or an oversized
  scale bar is explained in Map aids. Replacing a map image retains its aids and
  reminds the Director to check alignment and scale.
- **Show hover text** off immediately dismisses pin, breadcrumb and Atlas popups and
  suppresses hover-only path names. Button help, Party hints, highlighting, selection
  and Show names continue to work.

See [the approved design](docs/MAP_AIDS_BRIEF.md) and [verification](tests/MAP_AIDS.md).

### Map labels

- Add independent lettering with **+ > Add label** or **Add label here**. Labels have no
  Location pin, description, child map, or Party destination.
  Add label stays on until Esc or a toolbar toggle, like Add location.
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
- **Positions locked/unlocked** controls movement of location pins, labels and map aids.
  Unlock and drag any label. Selected labels have resize and rotation handles,
  with numeric size/angle fields in the editor. There are no separate Move label actions.
  Locked labels still open their editor on click; attempted drags offer Unlock.
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
- **Visibility.** A pin is Hidden (Director only) or Revealed. Names and labels remain
  fully readable in preparation view. **Show player visibility**, initially off in
  the Director's personal Settings, adds hidden-item badges; label badges attach to the top-left corner.
  A Location's own map has a separate Map shared switch.
- **Side panel.** Clicking an editable pin opens its editor with a shared title, close
  button, Open map, Move Party here and "..." actions where available. The Director also
  sees its Paths section. Other viewers, Search and breadcrumbs open the read view,
  including description, journal link and the permitted actions. Forms autosave after
  1.5 s without typing or on leaving a field. Location, label and path editors keep save
  status, Retry, Delete and Done below the scroll area. Done closes the selection;
  Esc closes an editor once its tool is off, while pickers still return to the read view.
- **Journal link.** A Location links one journal entry of any kind: document, negotiation,
  PDF, image or PDF bookmark. The picker shows each entry's kind icon. Open in journal opens
  it the way the journal does; a viewer who cannot browse the entry in the journal sees no link.
- **Create**: toolbar Add > Add location then click the map (sticky until Esc), or right-click > Add
  location here. The new Location is Hidden and copies the last pin style used. A compact
  **Quick Add** name field opens beside it; type and press Enter, then click the next spot.
  Finishing Quick Add clears the selection. Clicking empty map space also deselects.
  Add label uses the same flow and remembers the last label format. Neither opens a side
  panel or changes the camera. **All options** opens the full editor. Leaving saves typed
  text; an empty label draft is discarded. The field follows its anchor and hides off-screen.
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
  `overlandMapState` and rewritten on every type edit).

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
  the border picked last. Torn edge and Frame are removed until they have proper art and a
  rendering method ([docs/BORDER_ART.md](docs/BORDER_ART.md)).

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
  Show player visibility adds a fade and eye-slash on each hidden path segment. Path text
  stays opaque. Labels ("name - time") show on
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
- The Director's top banner chip counts hidden pins, labels and paths on the open map.
  Clicking **N hidden from players** toggles Show player visibility; the chip is highlighted
  while the overlay is on and disappears when nothing is hidden.
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

Load order (49 runtime files; persisted in the CodeMod file list):

| # | File | Responsibility |
|---|---|---|
| 1 | `OverlandMapConstants.lua` | Storage identities, limits and metrics |
| 2 | `OverlandMapCopy.lua` | Interface wording |
| 3 | `OverlandMapJournal.lua` | Viewer-aware journal access for every entry kind |
| 4 | `OverlandMapLifetime.lua` | Game generations, owners and guarded timers |
| 5 | `OverlandMapImages.lua` | Scoped requests, dimensions, readiness and Retry |
| 6 | `OverlandMapRecords.lua` | Fresh schemas, validation, row uploads and receipts |
| 7 | `OverlandMapModel.lua` | Location tree, permissions, Party and deletion plans |
| 8 | `OverlandMapCommands.lua` | Typed outcomes and individual operation settlement |
| 9 | `OverlandMapUndo.lua` | Guarded reversals and receipt-aware toasts |
| 10 | `OverlandMapSaveQueue.lua` | Immutable batches, retries and removable observers |
| 11 | `OverlandMapTextAppearance.lua` | Typography, contrast and text geometry |
| 12 | `OverlandMapLabels.lua` | Independent lettering records and save adapter |
| 13 | `OverlandMapLog.lua` | Travel history, notes, merging and retention |
| 14 | `OverlandMapPaths.lua` | Paths, endpoint rules, types and time values |
| 15 | `OverlandMapReaders.lua` | Viewer-filtered read models |
| 16 | `OverlandMapEditors.lua` | Location, path and log editor save lanes |
| 17 | `OverlandMapTravel.lua` | Point crawl travel and stopping partway |
| 18 | `OverlandMapStyles.lua` | Theme rules and subscriptions |
| 19 | `OverlandMapPreferences.lua` | Per-viewer preferences and camera storage |
| 20 | `OverlandMapControls.lua` | Shared controls, appearance editors and image decoration |
| 21 | `OverlandMapSession.lua` | View state and transition participants |
| 22 | `OverlandMapPinText.lua` | Pin typography, hover previews and save adapter |
| 23 | `OverlandMapGeometry.lua` | Coordinate, clipping, calibration and aid mathematics |
| 24 | `OverlandMapDrawing.lua` | Retained panel pools and cached layout helpers |
| 25 | `OverlandMapCanvasTools.lua` | Placement, ruler and calibration tools |
| 26 | `OverlandMapPathLayer.lua` | Pooled strokes, labels, badges and editing handles |
| 27 | `OverlandMapLabelLayer.lua` | Lettering, transforms and handles |
| 28 | `OverlandMapPathTool.lua` | Connect, redraw and bend-edit commands |
| 29 | `OverlandMapAids.lua` | Aid domain operations and save adapter |
| 30 | `OverlandMapAidLayer.lua` | Compass and scale bar rendering and handles |
| 31 | `OverlandMapAidEditor.lua` | Map aids toolbar editor |
| 32 | `OverlandMapGestures.lua` | Shared gesture lifecycle and canvas interaction adapters |
| 33 | `OverlandMapPinLayer.lua` | Retained pins, hits and snapping |
| 34 | `OverlandMapPartyLayer.lua` | Party banner, hit target and travel animation |
| 35 | `OverlandMapCamera.lua` | Camera movement, zoom and settled layout |
| 36 | `OverlandMapGuideLayer.lua` | Ruler and historical route overlays |
| 37 | `OverlandMapCanvas.lua` | Layer composition and layout coordination |
| 38 | `OverlandMapArtwork.lua` | Retained map artwork and selected-object attachments |
| 39 | `OverlandMapSidePanel.lua` | Location readers, editors and menus |
| 40 | `OverlandMapPathPanel.lua` | Path readers and editors |
| 41 | `OverlandMapLabelPanel.lua` | Lettering editor |
| 42 | `OverlandMapPartyPanel.lua` | Party controls and travel choices |
| 43 | `OverlandMapAtlas.lua` | Map gallery and map creation |
| 44 | `OverlandMapPopovers.lua` | Search, settings and aid composition |
| 45 | `OverlandMapQuickAdd.lua` | Lazy anchor-following name/text editor for new items |
| 46 | `OverlandMapImport.lua` | Explicit JSON draft, preview and batched import |
| 47 | `OverlandMapLogPanel.lua` | Session log and save-on-close notes |
| 48 | `OverlandMapPresent.lua` | Map presentation |
| 49 | `OverlandMapPanel.lua` | Toolbar, navigation, selection, focus and scoped refresh |
| 50 | `OverlandMapHost.lua` | In-app window chrome, geometry and the window state machine |
| 51 | `OverlandMapTabletop.lua` | Every Tabletop call, per-feature availability, minimized button, window lists, Atlas placement |
| 52 | `OverlandMap.lua` | Bootstrap, native popout and lifecycle reconciliation |

Original cloud file IDs and revision histories are preserved. New files were registered
through the live bridge, with the bootstrap last. `main.lua` is informational only.
The current Codex runtime is required; old-build support branches have been removed.

Components coordinate through the view context and transition participants. Game-scoped
save queues outlive editors; editor subscriptions and image requests carry owner and game
guards. Fullscreen/window changes retain the content tree. Native transfer flushes valid
edits and releases the old view. Ordinary pans move retained layers directly.

The production renderer uses pooled panels and the input controller uses centralized
polling. See [the rewrite record](docs/REWRITE_PLAN.md) for adoption-gate evidence and
the architecture contracts.

The shell constructs Location, Path, Label, Party, Log and Import on first eligible use,
then retains each component in its original layer slot. Closing binds and game-scoped
saves keep their existing lifetimes. The user accepted performance for this phase on
2026-10-19; the measured limitations remain recorded. The [lazy-editor record](tests/LAZY_EDITORS_2026-10-19.md)
also documents the rejected bordered-path primitive; the production path renderer remains unchanged.

## 3. Data

| Storage | Contents |
|---|---|
| `OverlandMapLocations` | Location tree, normalized positions, pin appearance, map image, sharing, calibration, pace, aids and revisions |
| `OverlandMapLocationDetails` | Description and journal link; independent revision lane, keyed by `locationId` |
| `OverlandMapLocationDirectorNotes` | Director note; independent revision lane, keyed by `locationId` |
| `OverlandMapPaths` | Endpoints, bends, type, time, description, note, visibility and revisions |
| `OverlandMapLabels` | Independent map lettering, appearance, placement, visibility and revisions |
| `OverlandMapLogEntries` | Party travel, historical routes, merged moves, notes and revisions |
| `overlandMapState` document | Party, permissions, path types, time units and separately guarded state keys |
| `overlandmap:preferences` setting | Per-user/game camera, host geometry, names, labels, Reduce motion and remembered formatting |

Fresh schemas start at version 1. Missing optional values use documented defaults;
malformed records are rejected. There are no old-store readers, compatibility aliases,
migrations or dual writes. All participating development clients must use this rewrite.

Every domain operation rechecks permissions against current local records. Table writes
remain pending until their callback confirms or fails them. Document `CompleteChange`
records submission only; it supplies no separate server acknowledgement. Multi-store
operations expose individual results, including partial failure. No timeout grants Undo.
Independent row, state-key and Party revision guards remain client-side guarantees,
not server compare-and-swap or atomic transactions.

Overland state is independent of tactical **Revert Turn**. Use Overland's guarded Undo.
Dependent deletion batches with failed rows cannot be reversed as a successful operation;
independent import rows retain their existing partial Undo behavior.

## 4. Open decisions

| Topic | Current state |
|---|---|
| Hidden Locations and Director notes sync to every client; hiding is UI-only. | Accepted (as in V1); notes are labeled "Hidden from players' screens". |
| Two clients editing one row at once. | Last write wins per field; undo refuses after a remote edit. True merges need a host patch API. |
| Live theme switch. | Checkboxes (and the host's own window title bar) keep the old colors until the window is reopened. Host limitation; not worked around. |
| Torn edge and Frame borders (V2.1, K9). | Await the user's art and rendering integration; supplying the Constants art IDs alone is not sufficient. |
| `@danger` as text (host). | In Default, MCDM and Warm Gold it reads 3.4-4.0:1 on `@bg`, under 4.5:1. The mod puts warning text in `@fgStrong` with a `@danger` bar instead. A host fix would be a darker or lighter text variant of the token; not a mod change. |

## 5. Performance

Recorded measurements are fixture-specific, not guarantees for larger maps or other
clients. They are kept here because future rendering work needs a comparison point.
The historical table below precedes the review fixes and current pin-name composition.
The [2026-10-19 benchmark](tests/PERFORMANCE_2026-10-19.md) measures the current development
version separately, including cached full-content opening and distinct interaction phases.

| Fixture and date | Observed cost |
|---|---|
| 250 pins held in memory, 2026-10-07 | Pan 16.6 ms/frame at the 60 Hz display cap; first draw 221 ms; pin refresh 2.6 ms |
| 150 paths on the active map, 2026-10-10 | First draw at Fit: 1,401 pieces, 123 ms; zoom layout: 23-34 ms, with extra pool-growth cost |
| Large session log, 2026-10-11 | First batch 54 ms, then 40 rows/frame; unchanged open-log refresh about 1 ms |
| Focused PC test map, 2026-10-13: about 760 path pieces, 600 route dots and 33 pins | Pan improved from over 100 ms/frame to 16.7 ms after position writes stopped using selfStyle; animated Fit measured 16.7 ms/frame |
| Same zoom work with stable per-segment pooling, unfocused app at 30 Hz | Four wheel notches dropped from five frames over 33 ms to one; this is not a focused FPS benchmark |

On 2026-10-19, five normal/dense interaction runs measured median pan p95 of about
37/103 ms and animated-zoom p95 of 95/193 ms. Synchronous renderer construction was
709/2,369 ms, compared with 725/2,073 ms in the October 18 observations. Cached
full-content opening was about 7.4 seconds normal and 22-24 seconds dense; the dense
opening sample and foreground limitations are explicit in the report. Large settled
zoom jumps caused multi-second stalls. The engine caps frame percentiles at 2 seconds
and omits frames lasting 10 seconds or more, so those limits must accompany the results.
Historical workloads/session context differ; these results do not establish a rewrite
regression or a passing comparative acceptance result.

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

The [rewrite record](docs/REWRITE_PLAN.md) and [2026-10-18 live record](tests/LIVE_REWRITE_2026-10-18.md)
distinguish current evidence from remaining checks. The full offline runner passes
212 checks across ten suites. [Earlier live evidence](tests/LIVE_REVIEW_2026-10-17.md)
remains historical and does not establish a result for the rewritten rendering code.

Two-client live tests remain excluded by request. Offline fixtures simulate busy rows,
remote changes, failed uploads and stale Undo; they do not establish server atomicity.
The user reported that the [single-client manual tests](tests/MANUAL_REWRITE_ACCEPTANCE.md)
passed on 2026-10-19. The [current-version benchmark](tests/PERFORMANCE_2026-10-19.md)
is complete with recorded limits and substantial opening/zoom stalls. A matched
pre-rewrite comparison remains unavailable, so full comparative acceptance is still open.
The native-popout wheel limitation remains documented in the
[engine handoff](docs/POPOUT_WHEEL_ENGINE_HANDOFF.md).

## 7. Development

- Follow the repository `CLAUDE.md`, `UI_BEST_PRACTICES.md`, `ThemeEngine.md`,
  `DefaultStyles.md` and `STYLE_GUIDE.md`. ASCII-only Lua. Every on-screen string comes
  from `OverlandMapCopy.lua`.
- Change only files in `Overland Map/`. Register new files with
  `mcp__dmhub__register_lua_file` in the order above; never edit `main.lua`.
- Check syntax with `..\dependencies\lua\bin\luac.exe -p`. The required type checker is
  `../tools/lua-typing/check.ps1`; it is absent in this checkout. The available
  `../dependencies/check-mod.ps1 -Mod 'Overland Map'` loads other mods as libraries and
  checks this mod. It is not the prescribed whole-repository check.
- Deploy with explicit paths so nothing outside the runtime files is copied:
  `.\deploy.ps1 "Overland Map/OverlandMapConstants.lua" ...`, then reload Lua. The app reads
  dev mods from a dev-mod folder named after the CodeMod, so these files go to
  `<git folder>\Overland Map\`, not `Overland Map\`. Use the repository deployment workflow.
