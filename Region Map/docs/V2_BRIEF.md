# Region Map V2 - Design Brief

Status: LOCKED, signed off by the user 2026-10-05 (critique round folded in, section 10b).
Copy is in [V2_COPY.md](V2_COPY.md), signed off 2026-10-05.
Build plan: [../TECH_TASK_V2.md](../TECH_TASK_V2.md).
Everything below is a settled decision unless it is listed under Open questions.
The decision ledger (section 10) is the record; the sections above it describe the result.

## 1. Frame

**Problem.** The V1 MVP is a toolbar, a canvas and a side pane, with every feature added
as another button or pane. Maps, labels and locations overlap as concepts, labels are hard
to read on map art, chrome takes about a quarter of the window, and most actions are tool
modes rather than direct manipulation.

**Designed for (in order).**
1. Director at the table: show places, move the Party, reveal locations, quickly.
2. Players: see what is shared, add their own places, know where the Party is.
3. Director in prep: build maps and locations, write notes.

**Done looks like.** A Director can run a travel scene from the map alone: find a place,
reveal it, move the Party there, show the map to the table, without touching a pane or a
tool mode. Every V1 capability is either kept, relocated, or listed as removed (section 8).

**Constraints.**
- Opt-in CodeMod, zero core changes (only files in `Region Map/`).
- ThemeEngine and STYLE_GUIDE vocabulary; ASCII-only Lua.
- ~~V1 content migrates automatically and losslessly (D4e).~~ Superseded by R17: V1 data
  is dropped.

## 2. Pillars

- **Canvas-first.** The map is the interface; chrome floats and recedes.
- **One object.** Everything is a Location; a Location may have its own map.
- **Direct, but safe.** Drag the Party; pins are locked during play; undo instead of dialogs.
- **Readable at a glance.** Pin styles, tiers and decluttering beat thin text on art.

## 3. Object model

- **Location** is the only object (D4a). A Location may have:
  - a pin on its parent's map (position, style, tier, icon), and/or
  - its own map image, which makes it openable.
- Top-level Locations with images form the **Atlas**.
- Containment is **drill-in only**: children are pinned on their parent's own map (D4b).
- **Party** is the only entity in V2 (D4c). It is either "at" a Location (snaps to its pin
  and follows it) or free on a map ("travelling") (D4d). It has a custom name (D11b).
- **Visibility**: a pin is Hidden (Director only) or Revealed (D9a). A Location's own map
  has a separate "Map shared" state (D9b).
- Content: short plain-text description, optional journal link for deep lore, separate
  Director notes (D6c).
- Per-map **scale** for the ruler (D14c). **Session log** entries (D14d).

## 4. Screen layout

```
+----------------------------------------------------------------+
| Atlas > Vasloria > Coast   [Q][+][Lock][Ruler][>][o][Log][Exp][*] |
|                                                                 |
|            [castle] Saltmarsh            +--------------------+ |
|                 (flag) The Iron Company  | side panel (right) | |
|      (+) Old Lighthouse                  | overlays the map   | |
|                                          +--------------------+ |
| [fit][-][+][names]                       Party: Saltmarsh       |
+----------------------------------------------------------------+
```

- **Host**: the resizable rail window (1000x800 default) plus **Expand**, which fills the
  screen's play area; Esc or the toggle returns (D13a).
- **Breadcrumb** top-left: Atlas > ... > current map; each part clickable; Esc/Back goes
  up one level (D8b).
- **Toolbar** top-right (D12a, R7): Search, Add, Lock, Ruler, Show to players (Director),
  View as player (Director), Session log (D14d), Expand (D13a), Settings gear (Director).
  Icons with tooltips. Expand's place in the toolbar follows from R2 (left only by its toggle).
- **Camera controls** bottom-left: fit, zoom out, zoom in, show names; they fade when the
  pointer is away (D12d).
- **Status** bottom-right: Party location ("Party: Saltmarsh" / "travelling").
- **Side panel** slides in at the right edge over the map; the map pans just enough to
  keep the selected pin visible; full width on narrow windows (D6a, D6e).

## 5. Pins on the map

- Styles per Location: Icon + name (default), Name plate, Icon only (name on hover) (D5a).
- Tiers: Major, Normal, Minor set icon and text size (D5b).
- Zoomed out, names declutter by tier, Minor first; icons stay; pins keep a constant
  screen size (D5c).
- Icons: curated, theme-tinted map set plus any library image (D5d).
- Hover: name + first line of the description (D6d).
- Pins with their own map show a small map badge (D8a).
- Director sees Hidden pins dimmed with an eye-slash badge (D9c).
- **Party marker**: compact theme-coloured banner with a group icon, optional custom image,
  name chip underneath, drawn above pins (D11a, D11b). Shown only on the map it is on (D8d).

## 6. Interactions

| Action | How |
|---|---|
| Select a Location | Click the pin -> side panel (read mode) |
| Rename | Double-click the pin name, or Edit in the panel |
| Edit | "Edit" switches the panel to a form; autosave (~1.5 s pause or leaving the field); "Done" exits (D6b, D13b) |
| Create a Location | Toolbar "+" then click the map, or right-click the map > "Add location here"; opens in edit mode with the name focused (D7a) |
| Move the Party | Drag it (whoever may move it); drop on a pin = "at" that Location; elsewhere = travelling (D7b, D4d) |
| Move a pin | Unlock with the toolbar Lock, then drag; or "Move" in the pin's "..." menu (D7b) |
| Open a Location's map | "Open map" in its panel only (D8a); short zoom + crossfade (D8c) |
| Go up / switch top-level map | Breadcrumb, Esc/Back, Atlas gallery (D8b) |
| Find a place | Toolbar search across every map the viewer can see; a result opens its map, centres and selects the pin (D12b) |
| Show players | Director: "Show to players" presents the whole current map, one-shot; everyone auto-jumps; the Director gets a toast (D10a-d) |
| Check the player view | Director: "View as player" toggle, local (D9c) |
| Undo | Moves, deletes and visibility changes show an undo toast (D7c) |
| Delete | From "..."; a Location with children or a map asks first, deletes the subtree; a Party inside moves to the parent map (D7d) |
| Measure | Ruler from the toolbar: distance and travel time on calibrated maps (D14c) |
| Review travel | Session log: automatic Party entries plus the past route drawn on the map (D14d) |

Panning and zoom: wheel zoom at the cursor, left-drag on empty map, right/middle-drag;
arrow keys pan. No other keyboard shortcuts (D13d).

## 7. Side panel (read mode)

```
+------------------------------+
| [castle] Saltmarsh       x   |
| Major - Revealed [eye] [map] |
|------------------------------|
| A fishing village on stilts. |
| > Read in journal            |
|------------------------------|
| Party is here                |
| [Move Party here] [Open map] |
| [Edit]                 [...] |
|------------------------------|
| v Director notes (hidden)    |
+------------------------------+
... = Move, Move to map..., Show/Hide, Add map, Replace image, Remove map, Link journal, Delete
[eye] = Revealed/Hidden, [map] = Map shared (R4), shown when the Location has a map
```

Signed off as drawn (D6f). Edit mode shows: name, icon, style, tier, visibility,
description, journal link; Director notes stay Director-only.

## 8. Regression surface (every V1 capability)

| V1 capability | V2 |
|---|---|
| Map selector dropdown | Breadcrumb + Atlas gallery |
| Manage maps pane (create, rename, replace image, publish, delete) | Atlas "New map"; Location panel Edit, "...", "Map shared" |
| Labels pane and label search | Global search (D12b) |
| Add Label tool + inline editor | "+" or right-click; panel in edit mode |
| Label rename, audience, move, delete | Panel Edit, "...", Lock + drag, undo |
| Location card (description, journal link, Director note) | Side panel |
| Move Party tool / Move Party here | Drag the Party; "Move Party here" in the panel |
| Players can move Party (footer) | Settings popover (D11c) |
| Present map | "Show to players" (one-shot, auto-jump) |
| Present location (zoom + ring) | **Removed** (D10e) |
| Busy-viewer offer | **Removed**: recipients always auto-jump; pending edits keep saving (D10b) |
| Unsaved changes list and drafts | **Removed**: autosave (D13b) |
| Show Labels toggle | "Show names" in camera controls |
| Keyboard nudges for selected markers | **Removed** with pin locking; arrow keys pan only (D13d) |
| Last viewed map per player | Kept (D13c) |
| Label limit (250 per map) | Kept as a soft creation guard per map |

## 9. Phasing

- **V2**: everything in sections 3-7, plus the ruler (D14c) and the session log with the
  drawn past route (D14d).
- **V2.1**: hex overlay with distances (idea 3), planned Party travel paths (idea 3.1),
  fog by grid cells (D14b).
- **Later / not now**: more entities than the Party, area Locations, Lead/follow
  presenting.

### Rejected or removed, with reasons

- Anchored card at the pin: user preferred the side panel's room (D6a).
- Lead/follow presenting: one-shot is the table model (D10a).
- Presenting a single Location: removed after review (D10e).
- Ancestor Party badges: Party shows only where it is (D8d).
- Keyboard shortcuts: not wanted (D13d).
- Player landing on the Party: players keep their last map (D13c).

## 10. Decision ledger

| Date | ID | Decision | Rationale |
|---|---|---|---|
| 2026-10-05 | D1 | Design for play at the table first; prep tools exist but stay out of the way | V1 hurts most during play |
| 2026-10-05 | D2 | V2 = UX redesign + Locations model, pin styles and icons, drag Party; hex and travel paths are V2.1 | Locations change the data model first |
| 2026-10-05 | D3 | Concept A, canvas-first (inspector form superseded by D6a: side panel) | Fits the play-first goal |
| 2026-10-05 | C | Opt-in mod, zero core changes; V1 content migrates automatically | Existing games keep their content |
| 2026-10-05 | D4a | One object, Location; may have its own map and/or a pin on its parent's map; top-level Locations form the Atlas | One mental model |
| 2026-10-05 | D4b | Containment is drill-in only | Flat, readable maps |
| 2026-10-05 | D4c | V2 entities: the Party only | Scope |
| 2026-10-05 | D4d | Party is "at" a Location (snaps, follows) or free ("travelling") | Clear status, still flexible |
| 2026-10-05 | D4e | V1 migration: maps -> top-level Locations ("published" -> "Map shared"); labels -> child Locations, Normal tier, Name plate; shared/Director-only -> Revealed/Hidden; content and author carry over; Party keeps map and position (free) | Lossless, closest look to V1 |
| 2026-10-05 | D5a | Pin styles per Location: Icon + name (default), Name plate, Icon only | Ideas 1, 5, 6 |
| 2026-10-05 | D5b | Tiers: Major, Normal, Minor | Visual hierarchy |
| 2026-10-05 | D5c | Declutter names by tier when zoomed out; constant screen size; hover shows names | No overlap |
| 2026-10-05 | D5d | Curated theme-tinted icon set + any library image | Consistency with an escape hatch |
| 2026-10-05 | D6a | Selection opens a slide-in side panel at the right edge | User choice, more room |
| 2026-10-05 | D6b | Panel reads first; "Edit" switches it to a form | No accidental edits |
| 2026-10-05 | D6c | Short description + journal link; separate Director notes | Rich lore without one journal page per pin |
| 2026-10-05 | D6d | Hover: name + first description line | Scanning |
| 2026-10-05 | D6e | Panel overlays the map; map pans to keep the pin visible; full width on narrow windows | No view jumps |
| 2026-10-05 | D6f | Side panel read layout as in section 7 | Signed off from the mockup |
| 2026-10-05 | D7a | Create via "+" then click, or right-click > "Add location here"; opens in edit mode | Two paths |
| 2026-10-05 | D7b | Party always draggable; pins locked during play (Lock toggle; "Move" in menu) | Safety at the table |
| 2026-10-05 | D7c | Undo toast for moves, deletes, visibility changes | Cheap recovery |
| 2026-10-05 | D7d | Delete removes the subtree after a confirm listing what goes; Party moves to the parent map | No orphans |
| 2026-10-05 | D8a | Child maps open only via "Open map"; map badge on such pins; double-click = rename | One meaning per gesture |
| 2026-10-05 | D8b | Breadcrumb + Atlas thumbnail gallery; Esc/Back goes up | Replaces dropdown and library pane |
| 2026-10-05 | D8c | Zoom + crossfade transition, about 0.3 s | Sense of place |
| 2026-10-05 | D8d | Party shown only on its own map; status names where | User choice |
| 2026-10-05 | D9a | Visibility: Hidden / Revealed | Simple at the table |
| 2026-10-05 | D9b | Separate "Map shared" for a Location's own map | Know it exists before opening it |
| 2026-10-05 | D9c | Hidden content dimmed + eye-slash for the Director; local "View as player" | Checkable player view |
| 2026-10-05 | D9d | Players add shared Locations and edit their own; Director switch turns it off | V1 parity |
| 2026-10-05 | D10a | Presenting is one-shot | User choice |
| 2026-10-05 | D10b | Recipients always auto-jump; pending edits keep saving (autosave, D13b) | User choice |
| 2026-10-05 | D10c | Present a whole map only | User choice |
| 2026-10-05 | D10d | Director gets a toast; no persistent indicator | One-shot model |
| 2026-10-05 | D10e | Presenting a single Location removed | User decision after the flag |
| 2026-10-05 | D11a | Party: compact theme-coloured banner, group icon, optional custom image, above pins | Map-like, smaller |
| 2026-10-05 | D11b | Party custom name (default "Party") in a chip and status | Flavour |
| 2026-10-05 | D11c | Game-wide switches in a Director settings popover (toolbar gear) | One home for rules |
| 2026-10-05 | D12a | Top-right toolbar: Search, Add, Lock, Show to players, View as player, Session log, Settings | Compact play actions |
| 2026-10-05 | D12b | Global search across visible maps | Replaces the Labels pane |
| 2026-10-05 | D12c | Atlas "New map"; "Add map" on any Location; Replace/Remove in "..." | Maps are Locations |
| 2026-10-05 | D12d | Camera controls bottom-left, fading when idle | Less chrome |
| 2026-10-05 | D13a | Rail window + Expand to fill the play area | Table moments |
| 2026-10-05 | D13b | Autosave with "Saving... / Saved"; no Save buttons or unsaved list | Simpler editing |
| 2026-10-05 | D13c | Players open on their last viewed map | User choice |
| 2026-10-05 | D13d | No shortcuts beyond Esc and arrow panning | User choice |
| 2026-10-05 | D14a | Ruler and session log in V2; fog in V2.1 | Small vs grid-dependent |
| 2026-10-05 | D14b | Fog by grid cells (squares, hexes once V2.1 hex lands); Director paints reveal/hide | Simple, syncs well |
| 2026-10-05 | D14c | Ruler uses a per-map scale (calibrate a known distance once); shows distance and travel time at a chosen pace; uncalibrated maps show % of width | Meaningful distances |
| 2026-10-05 | D13e | Keyboard nudges for a selected pin are removed; arrow keys only pan | Follows from locked pins and D13d; confirmed by user |
| 2026-10-05 | D13f | The 250-per-map soft creation guard stays for Locations | V1 performance guard; confirmed by user |
| 2026-10-10 | D13f (revised) | The per-map Location cap is removed: a map holds any number of Locations | User decision. Performance was measured up to 250 pins a map (README section 5); above that it is not measured |
| 2026-10-05 | D12e | The session log has its own toolbar button | Confirmed by user |
| 2026-10-05 | D14d | Session log: automatic entries when the Party arrives or is placed (where, when, by whom), Director can edit/delete/annotate; players see entries for revealed places; past route drawn on the map | Recap and continuity |

### Critique decisions (ledger continued)

| Date | ID | Decision | Rationale |
|---|---|---|---|
| 2026-10-05 | R1 | (P1) Director-created Locations start Hidden; player-created start Revealed; new maps start not shared; visibility shows in the edit form's first row | No accidental reveal while typing (autosave) |
| 2026-10-05 | R2 | (P2) Esc order: cancel in-progress action (placement, ruler, text field) -> leave edit mode -> close panel -> go up a level. Expand is left only with its toggle | One Esc never throws the table out of a shown view |
| 2026-10-05 | R3 | (P3, P4) Party "at" a Location is drawn beside the pin; drag threshold, snap radius and target highlight; undo covers Party moves and removes the log entry; at a Hidden Location players see "travelling"; a player-dragged Party never snaps to a pin they cannot see | No pin/Party click conflicts; no spoilers via status |
| 2026-10-05 | R4 | (P5) "Map shared" toggle next to the eye in the panel header; "Show to players" on an unshared map asks "Share this map?"; players see the map badge and "Open map" only once shared; players' breadcrumb lists only levels they can see | Closes the undefined present/share cases |
| 2026-10-05 | R5 | (P6) Recipients of "Show to players" get a toast "The Director showed you {map}" (no Back button); landing stays D13c; reveals are sent immediately (P8 rejected) | User choice |
| 2026-10-05 | R6 | (P9) Lock is per viewer, re-locks whenever the map opens, and shows a "Pins unlocked" chip while off; players only ever move their own Locations | Nobody unlocks pins for others |
| 2026-10-05 | R7 | (P10) Ruler has a toolbar button; measurements are local; click start then click end works as well as dragging | Discoverable, motor-friendly |
| 2026-10-05 | R8 | (P11) Session log merges consecutive travelling drops into one leg; real time only, no in-game day counter | User choice |
| 2026-10-05 | R9 | (P12) Accessibility package: 10 s undo toast that pauses on hover plus "Undo last change" in the log; pins and Party scale with Font Size, 24x24 minimum hit area; camera controls fade only to 3:1 and return on pointer movement; names always on a halo or backing; "Show names" forces every name visible; "Reduce motion" option; "Viewing as player" banner; side panel scales with Font Size and its button rows wrap; Tab order in forms; Enter opens the top search result | Removes barriers without changing the model |
| 2026-10-05 | R10 | (P13) "+" stays active until Esc; new pins copy the last-used icon, tier, style and visibility; "Move to map..." in the "..." menu | Fast prep of many pins |
| 2026-10-05 | R11 | (P14, P15) Player-made Locations name their author in the panel (no map badge); failed autosaves show "Not saved - Retry" (no Revert) | User choice |
| 2026-10-05 | R12 | (P16, P17, P18) Double-click renames only when unlocked and allowed, else acts as a click; right-click on a pin opens its "..." menu; Director right-click on any map: "Place Party here"; one name per concept in the copy manifest; the "..." menu gains "Remove map" | Consistency, closes gesture gaps |
| 2026-10-05 | R13 | Brief signed off and locked | User sign-off |
| 2026-10-05 | R14 | Undo is refused when someone else changed the same item since: the toast's Undo button disappears | Never overwrite another person's edit; confirmed by user after the engine checks |
| 2026-10-05 | R15 | Session log keeps the newest 500 entries per game; the Director's client deletes older ones on open | Bounded storage over a long campaign |
| 2026-10-05 | R16 | If players cannot write data tables, their Locations and log entries go in a shared document; Director content stays in tables | Fallback for the first build check (TECH_TASK_V2 V2-00) |
| 2026-10-06 | R17 | V1 may break and is replaced wholly by V2; V1 data is dropped (no migration). Supersedes C (migration part) and D4e; `migrate.done` is dropped from the copy | User decision; the only V1 content was test data |

## 10b. Critique round (2026-10-05) - decided

Outcome: accepted P1-P5, P9, P10, P12, P13, P16, P17, P18. P6 accepted as a toast without
"Back". P11 accepted as merged legs only (no in-game day counter). P14 accepted as author in
the panel only (no map badge). P15 accepted as "Not saved - Retry" only (no Revert).
Rejected: P7 (players keep D13c landing), P8 (reveals are sent immediately).
See ledger entries R1-R12.

Three independent reviews: UX (Hodent lens), a Director running live sessions, and
accessibility. Findings that two or three reviewers raised are marked (x2) / (x3).

| ID | Proposal | Source |
|---|---|---|
| P1 | New Locations the Director creates start Hidden; player-created start Revealed; new maps start not shared. Visibility shows in the edit form's first row | UX, Director (x2) |
| P2 | Fixed Esc order: cancel what is in progress (placement, ruler, text field) -> leave edit mode -> close the panel -> go up a level. Expand is left only with its toggle | UX, Director, A11y (x3) |
| P3 | Party "at" a Location is drawn beside the pin, not on it; drag threshold; generous snap radius and target highlight while dragging; undo covers Party moves and removes the log entry | UX, Director, A11y (x3) |
| P4 | Party at a Hidden Location reads "travelling" for players; a player-dragged Party never snaps to a pin they cannot see | Director |
| P5 | "Map shared" toggle next to the eye in the panel header; "Show to players" on an unshared map asks "Share this map?"; players see the map badge and "Open map" only once shared; players' breadcrumb lists only levels they can see | UX, Director (x2) |
| P6 | Recipients of "Show to players" get a toast "The Director showed you {map} - Back"; Back returns to their previous view; an open edit form stays open | UX, Director, A11y (x3) |
| P7 | A player with no valid last map lands on the most recently presented map | Director |
| P8 | Visibility changes are held locally until the undo toast expires (~3 s), then sent, so a mis-click reveal can be taken back before players see it | Director |
| P9 | Lock is local to each viewer, re-locks every time the map opens, and shows a "Pins unlocked" chip while off; players can only ever move their own Locations | UX, Director, A11y (x3) |
| P10 | Ruler gets a toolbar button; measurements are local (others see nothing); click start then click end works as well as dragging | UX, Director, A11y (x3) |
| P11 | Session log: a Director-set "Day N" stamped on entries; consecutive travelling drops merge into one leg; annotations Director-only by default | Director |
| P12 | Accessibility package: undo toast at least 10 s and pauses on hover, plus "Undo last change" kept in the log; pins and the Party scale with Font Size, with a minimum hit area of 24x24; camera controls fade only to 3:1 contrast and return on pointer movement; names always drawn with a halo or backing; "Show names" forces every name visible, icon-only too; a "Reduce motion" option; a "Viewing as player" banner; side panel width scales with Font Size and its button rows wrap; Tab order in forms, Enter opens the top search result | A11y |
| P13 | Prep speed: "+" stays active until Esc; new pins copy the last-used icon, tier, style and visibility; "Move to map..." in the "..." menu | Director |
| P14 | Player-made Locations show their author in the panel and a small badge on the map; the Director can Hide them | Director |
| P15 | Autosave: a "Not saved - Retry" state and "Revert" in edit mode (back to the values from when editing started) | UX |
| P16 | Double-click renames only when pins are unlocked and the viewer may edit that pin; otherwise it acts as a single click. Right-click on a pin opens its "..." menu | UX |
| P17 | Director right-click on any map: "Place Party here" (puts the Party onto a map it is not on) | Director |
| P18 | Glossary in the copy manifest: one name per concept ("Show to players", "Map shared", "Show names", "travelling"); the section 7 menu gains "Remove map" (D12c) | UX |

## 11. Open questions

1. ~~Copy~~: resolved, [V2_COPY.md](V2_COPY.md) signed off 2026-10-05.
2. Accessibility pass: colour never the only signifier (Hidden uses dim + badge), hover-only
   content (icon-only names, hover summaries) needs a non-hover path (selection shows it).
3. ~~Engine checks~~: done 2026-10-05, see section 11b. One item stays open there
   (cold-load time of very large map images).
4. ~~Session log storage size~~: resolved, R15.

## 11b. Engine checks (2026-10-05)

Checked against the codex source and live in a running game (rail mode, 2560x1600
screen, Font Size 100). Nothing found needs a core change.

| Check | Verdict | Evidence | What the build must do |
|---|---|---|---|
| Expand fills the play area | Works | Live: the Region Map window set to 1600x972 at (64, 64) filled the space between the rails; the map reflowed with no errors; window restored afterwards. Rails are 40 wide, inset 12 (`iconRail` panels, `PanelDocument.RAIL_STOP_GAP`); play-area height starts at `IconRailTop` (64). Same write path as `FitHostWindow` (`RegionMap.lua:84`): `selfStyle` size, `x`/`y`, then the `resize` event to `dialog.data.resizePanel` | Size = (documents layer size - rail insets) / `PanelDocument.WindowUIScale()`. Raise the registration's `maxWidth`/`maxHeight` (now 1600x1000, `RegionMapConstants`), or a wide screen cannot expand fully. Remember the pre-expand geometry locally, not in `_tmp_location`. |
| Zoom + crossfade | Works; cost depends on the image | Styles have `transitionTime` and `easing` (`Definitions/Style.lua:15`); V1 already streams the map (`bgimageStreamed`, `RegionMapCanvas.lua:412`) and reports `imageLoaded` with `bgimageWidth/Height` (`:567`); the camera is applied per frame in `think` | Animate the camera in `think` (about 0.3 s); stack the new map as a second image panel and fade it in only after its `imageLoaded`, so a slow load shows the old map zoomed instead of a blank. Two map textures are alive for the fade only. Skip both under "Reduce motion". |
| Undo | Works, mod-side only | Rows are written with `dmhub.SetAndUploadTableItem` (`RegionMapRecords.lua:365`), which never enters the engine undo stack (`dmhub.Undo` covers token and document edits only). Every row already carries `revision` (`RegionMapModel.lua`) | Undo = rewrite the saved previous row with the next revision. If the row's revision has moved since our write (someone else edited it), the toast's Undo button disappears instead of overwriting their change. No new copy needed. |
| Drawing the past route | Works | Live: three rotated thin panels (`rotate`, `Definitions/Style.lua:72`) drew straight segments at the right angles and positions inside the canvas, clipped at its edge; removed afterwards. No tiling option exists (`imageRect` is 0-1 only) | Route layer goes BELOW pins and the Party (the probe drew over the Party because it was added last). Solid segments are one panel per leg; a dashed look needs one small panel per dash or a dash texture. Merged legs (R8) keep the count low. |
| 10 s undo toast that pauses on hover | Works | `hover` / `dehover` events (`Definitions/gui-definitions.lua:39`), `dmhub.Schedule` / `think` timers | Nothing special |
| Players' breadcrumb lists only visible levels | Mod logic only | Built from the mod's own visibility fields | Nothing special |
| Pins and side panel scale with Font Size | Works in rail mode; mod work outside it | In rail mode Font Size zooms the whole window (`WindowUIScale`, `DocumentSystem.lua:4214`). Outside rail mode only fonts grow | Outside rail mode multiply pin, Party and hit-area sizes by `fontsize / 100` |
| Right-click menus, double-click rename, Esc order | Works | `rightClick` event + `gui.ContextMenu` / `element.popup` (CommandBuilder.lua:1371); `doubleclick` (already used in V1, `RegionMapLocationCard.lua:231`); `captureEscape` + `escapePriority` (`Definitions/Panel.lua:60`) | Give each Esc layer (placement, edit, panel, map level) its own `escapePriority` so R2's order holds |

**Still open:** cold-load time of very large map images (4k-8k). The test game's map is
1293x680 and already cached, so the load time could not be measured. Measure with a large
image during the build; the fade-after-`imageLoaded` rule above keeps the worst case
readable either way.

## 12. Evidence

- Current-state audit: UX/UI review of 2026-10-05 (V1 MVP running in a live game).
- User ideas: [../IDEAS.md](../IDEAS.md).
- Icons: the full Phosphor set ships with the app (the codex uses `phosphor/mountains`,
  `campfire-bold`, `compass`, `path`, `skull-fill`, `sword`, `fish-*`,
  `map-pin-simple`); curated names are verified live before build.
- V1 lessons carried forward: engine-dragged panels can move unexpectedly (left-drag pan is
  polled); labels with `"100% available"` widths on wrapping text measure too tall; children
  of full-height vertical panels centre unless top-aligned.
