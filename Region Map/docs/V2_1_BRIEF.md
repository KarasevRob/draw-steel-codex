# Overland Map V2.1 - Design Brief

Status: BUILT 2026-10-10, except Torn edge and Frame (K9: they wait for the user's art) and
the player-client checks (batched for a session the user sets up). What changed from this
brief while building is in the build notes, [TECH_TASK_V2_1.md](../TECH_TASK_V2_1.md)
section 8. All V2.1 copy is signed off, including the build-time choices V2_COPY.md 25.7
and 25.8 (2026-10-10).

LOCKED 2026-10-08 by the user. Build per the ledger (sections 2, 2.1, 2.2) in the M5
order; changes from here are new ledger rows agreed with the user. Mockups:
https://claude.ai/artifact/UieXXhuoYwRF4678XZp81U (private), accepted 2026-10-08 (N1); they
predate the critique round, so where they differ the ledger wins. Section 3 is the map of
decisions; section 4 lists what is left to the build. Build plan:
[TECH_TASK_V2_1.md](../TECH_TASK_V2_1.md); copy: [V2_COPY.md](V2_COPY.md) sections 18-25.

V2.1 covers point crawl mode and three quick ideas from [IDEAS.md](../IDEAS.md). The hex
overlay and hex mode move to V2.2. [V2_BRIEF.md](V2_BRIEF.md) stays the source of truth for
everything V2.1 does not change.

## 1. Frame (agreed 2026-10-08)

**Problem.** The Director cannot set up structured travel between places: the Party can be
dropped anywhere, and nothing records which places connect, what lies between them or how
long a leg takes. That is what point crawl play needs. Alongside it: no guidance on map
image size, a hard rectangular map edge, and no way to bring in many Locations at once.

**For whom.**
- Director (power user, prep): picks a map's mode at creation, draws paths between Locations
  with descriptions and attributes, moves the Party along them, imports Locations, gets image
  guidance.
- Players (set-and-forget): see the paths they may know, see where the Party can go next,
  read a path's description, follow travel in the session log. Nothing new to manage.

**Done when.**
1. A new map is created as a point crawl map or a free map.
2. On a point crawl map the Director creates and edits paths between pins (description and
   attributes); the Party moves only along paths, one leg at a time; each leg is logged with
   the travel time the Director entered on the path (C2); players see the paths they should.
3. Map images show size guidance when chosen and can have a softer border.
4. The Director can import Locations from a JSON file; pins land grouped near the center of
   their parent's map.

**Inherited constraints.** Zero core changes; opt-in mod; project standards (CLAUDE.md, UI
and theme guides); stored table and document names never change; players can write tables
(M0, 2026-10-06); every on-screen string comes from the copy manifest and is signed off; a
map's mode is fixed at creation (IDEAS 7.3).

**Out of scope.** Hex overlay (3), hex mode (7.1), converting a map between modes (7.3,
deferred), fog, planned multi-leg routes (3.1).

## 2. Decision ledger

| Date | # | Decision | Why |
|---|---|---|---|
| 2026-10-08 | L1 | V2.1 = point crawl mode (7.2 + 7.3) plus ideas 11, 10 and 9 | User: quick wins plus point crawl |
| 2026-10-08 | L2 | Hex overlay and hex mode become V2.2 | Out of this leg |
| 2026-10-08 | L3 | Maps that exist before V2.1 are free maps and behave exactly as today | No migration, no regression |
| 2026-10-08 | L4 | A map's mode is set when it is created; converting between modes is deferred | User (IDEAS 7.3) |
| 2026-10-08 | J1 | Size numbers are measured in the app (load time against the 10 s timeout, zoom smoothness, sharpness at max zoom), then proposed for approval | Engine-specific numbers beat convention |
| 2026-10-08 | J2 | Guidance is one always-visible hint line under the side panel image picker, and in the Atlas New map card's tooltip | Visible when choosing; the card has no room for text |
| 2026-10-08 | J3 | An image outside the range is used as normal and a toast warns, with the recommendation; nothing is blocked | Never stop the Director's prep |
| 2026-10-08 | J4 | Only new picks are checked; existing maps are left alone | Minimum workload |
| 2026-10-08 | K1 | Border looks: soft fade, worn/torn paper edge, decorative frame (plus None) | User pick; vignette dropped |
| 2026-10-08 | K2 | Border is per map, picked by the Director | Maps differ in art style |
| 2026-10-08 | K3 | The user supplies the torn-edge mask and frame art; soft fade needs none. The brief specifies the image format the art must follow | User |
| 2026-10-08 | K4 | Border shows only on the open map, not on Atlas cards | Consistent grid, less work |
| 2026-10-08 | K5 | A new map starts with the border the Director last picked; existing maps stay None | User |
| 2026-10-08 | K6 | The border is set in the toolbar's Settings popover, beside the open map's scale and pace | User |
| 2026-10-08 | K7 | A frame sits outside the image, adding a margin; fit and camera limits include it. Fade and torn edge act on the image itself | Nothing on the map is covered |
| 2026-10-08 | C1 | A path has: description, name (optional), type, travel time, danger/requirement note, hidden/revealed | User |
| 2026-10-08 | C2 | Travel time is always entered by the Director, as a number plus a unit (watches or days, see C9); nothing is computed from length | User: exact and simple; structured so the log can add times up |
| 2026-10-08 | C3 | Path types are Director-defined and game-wide: name, line pattern (from a fixed set), colour, line width | User; the pattern keeps types apart without colour |
| 2026-10-08 | C4 | A game starts with an editable, deletable starter set of types (Road, Trail, River, Sea, Underground, Secret) | Point crawl works with no setup |
| 2026-10-08 | C5 | The danger/requirement note is Director-only | Prep information; players learn it in play |
| 2026-10-08 | C6 | Path types are managed in the Settings popover, "Path types" section | Next to the other map settings |
| 2026-10-08 | B3 | Two places may be joined by several paths; every path is two-way (amended by W2: the other direction can take a different time or be impossible) | Point crawl practice; one-way trips go in the note |
| 2026-10-08 | B5 | Deleting an end Location, or moving it to another map, removes its paths too; the confirm says how many; undo restores them | A path always joins two pins on one map |
| 2026-10-08 | C9 | The time unit is one game-wide setting, watches or days (default days), in the Settings popover. Times are stored in one base unit (a watch = 4 hours, 6 watches = 1 day), so switching the unit converts the display, never the meaning | User; storage rule is the build's |
| 2026-10-08 | G1 | On a point crawl map the Party moves only through a "Travel to" list (no banner drag): in the Party's right-click menu and in a Party section of the side panel (opened by clicking the banner or the status chip). Each entry: destination, path name, time | User: list only; two places to reach it |
| 2026-10-08 | G3 | The Director can stop the Party partway: right-click a path line > "Place Party here" puts it on the path at that point. The Director then enters the time already spent; going on takes the rest of the path's time, turning back takes the time spent | User |
| 2026-10-08 | G4 | "Place Party here" stays for the Director on point crawl maps (any pin, any point); it is logged as placed, not as travel | Teleports and session starts |
| 2026-10-08 | G5 | Players use the Travel list when "Players can move the Party" is on, only along paths they can see | Same rule as today |
| 2026-10-08 | H2 | Hidden paths are revealed by the Director by hand | Full control, no surprises |
| 2026-10-08 | H3 | Only the Director creates and edits paths | World structure, like maps |
| 2026-10-08 | I1 | The log writes one entry per leg: path, from, to and time ("Traveled the King's Road from Ashford to Kell's Ferry - 2 days"); the drawn route follows the path line | Simple; no journey clock |
| 2026-10-08 | D1 | A path is a straight line with optional bend points, drawn as straight segments | Follows the art without curve costs |
| 2026-10-08 | E1 | Paths are created with a toolbar Path tool (click a pin, then another; no drag) or right-click a pin > "Connect to..." > pick a place; the new path opens in the side panel | Two ways in, neither needs a drag |
| 2026-10-08 | F2 | Hidden paths show to the Director faded, with an eye-slash badge at the middle | Same language as hidden pins; not colour-only |
| 2026-10-08 | F3 | A path's name and time label shows at its middle on hover or when selected | Keeps the art clean |
| 2026-10-08 | D2 | Bends: with the Path tool, clicks on empty map between the two pins add bends; a selected path shows handles (drag to move, right-click to remove, drag a segment's middle to add); Esc cancels drawing | Non-drag way in while drawing, direct edit after |
| 2026-10-08 | A1 | Creating a map (Atlas New map, Add map) first offers two buttons, "Free map" and "Point crawl map"; the choice opens the image picker | Explicit, one extra click |
| 2026-10-08 | A4 | The mode cannot change after creation, even on an empty map; Remove map and Add map again is the way back | User (strict L4) |
| 2026-10-08 | A2 | A point crawl map shows a "Point crawl" chip on its Atlas card and in its side panel; the Path tool only appears on point crawl maps | Visible without clutter |
| 2026-10-08 | IM1 | Import is Director-only and imports into the open map, one level (no nesting): "Import Locations..." | Nesting needs map images a JSON file cannot carry |
| 2026-10-08 | IM2 | An entry has a required name and optional description, Director note, pin look (icon key, pin style, importance), visibility and u/v (0-1); entries without u/v are grouped near the map's center | User |
| 2026-10-08 | IM3 | Import brings Locations only, never paths | User |
| 2026-10-08 | IM4 | Importing the same file twice creates new Locations each time; the preview warns about names already on the map | Simple and predictable |
| 2026-10-08 | IM5 | Choosing the file opens a preview (count, skipped entries with reasons, names already on the map), then Import / Cancel; one undo removes the whole import | Nothing surprising, cheap recovery |
| 2026-10-08 | IM6 | A file that would pass the map's 250-pin limit is refused whole; the preview says how many fit | Nothing half-imports |
| 2026-10-10 | IM6 (revised) | No size check: with the per-map cap gone (V2 D13f revised), every entry that passes its checks is imported | User decision |
| 2026-10-08 | M5 | Build order: 11 size guidance, 10 borders (soft fade first, the others when the art arrives), 9 import; then point crawl in slices (mode and paths, travel, log) | Early wins; point crawl gets the most review |
| 2026-10-08 | M6 | Before lock: a clickable mockup of the point crawl screens with their copy, then three critique reviews (UX, Director in session, accessibility) | User |
| 2026-10-08 | K8 | Until the Director first picks a border, new maps get Soft fade | Organic from the start |
| 2026-10-08 | H5 | Players see a revealed path's name, type, travel time and description (never the danger/requirement note) | Matches C5 |
| 2026-10-08 | G6 | A Party placed off pins and paths on a point crawl map has no travel options; the list says it is not on a path and the Director uses Place Party here | No guessing |
| 2026-10-08 | G7 | Stopping partway prompts for the time already spent, filled in with half the path's time | Confirm or edit in one step |
| 2026-10-08 | H1 | A path has its own Hidden/Revealed toggle and is never shown to players while either end is hidden | A path cannot reveal a secret place |
| 2026-10-08 | N1 | Mockups accepted with no comments, including their draft copy and the details they added: line patterns Solid, Dashed, Dotted, Double, Dash-dot; a 6-colour palette (Parchment, Blue, Ochre, Violet, Rust, Ink); the starter types' looks; the Party right-click holding only "Travel to"; widths Thin, Normal, Thick | User review |
| 2026-10-08 | N2 | A partway stop is logged as a placement: "Stopped on the King's Road, 1 day from Ashford" | User review (G4: placed, not travel) |
| 2026-10-08 | N3 | Deleting a path type that paths use turns those paths into "No type" with a plain line; the confirm says how many paths use it; undo restores | Proposed with the mockups, no objection |
| 2026-10-08 | IM7 | "Import locations..." sits in the Director's map right-click menu and in the open map's "..." menu in the side panel (settles open item IM1) | User, at the start of P3 |
| 2026-10-14 | IM7 (revised) | Import locations is a Director-only button beside Add in the top toolbar, available on an open map; it replaces both menu entries | User |
| 2026-10-14 | AT1 | Atlas cards expose map management through "..." and right-click: Open, Edit, Import, image, settings, journal, sharing, presentation and Delete with confirmation and Undo. Reuse the top-level Location's menu and existing handlers; import, settings and presentation open the selected map first. Add location, Path tool, Ruler and View as player remain only in the map toolbar. Keep the Import toolbar button. | User: actions available from the Atlas; explicitly exclude the four canvas/view controls |
| 2026-10-14 | IM8 | Replace prose import help with a terse OpenAPI-compatible JSON Schema and Copy contract, with Copied feedback. Display and clipboard use the same text; copying preserves the draft. | User: developer-oriented, copyable contract |
| 2026-10-14 | IM9 | Raise the shared name limit from 80 to 256 Unicode characters in validation and name editors, including imported Location names. Reflect it in the contract and validation messages. | User: increase name max characters to 256 |
| 2026-10-08 | K9 | Torn edge and Frame are deferred until the user provides the art; they ship as dimmed tiles meanwhile | User, after P2 |

### 2.1 Critique round (M6, 2026-10-08)

Three reviews ran against this brief and the mockups: UX (Hodent), a Director running
sessions, and accessibility. The fixes below do not reverse a user pick; they settle open
points or tighten a decision. Each is a decision unless the user objects. The three points
that changed or completed a user pick were put to the user; the answers are in 2.2.

| # | Decision | Source |
|---|---|---|
| Q1 | Every path line is drawn over a 1-2 px casing in the opposite tone (dark under light colours, light under Ink), like pin names on their halo. Lines on parchment art measured 1.2-2.1:1 without it | Accessibility |
| Q2 | Line patterns are sized in screen pixels, the same at every zoom (as pins are). Minimums: dots 4 px, Double 6 px across with a 2 px gap | Accessibility |
| Q3 | A seventh pattern, Long dash, joins the set (extends N1); Secret gets it, so no two starter types share a pattern. The type editor warns when a type's pattern and width match another type's | Accessibility: Underground and Secret differed by colour only |
| Q4 | Every path segment has a hit band of at least 24 px (`pinHitMin`). Right-click "Place Party here" snaps to the nearest path inside the band and names it ("Place Party on the King's Road"); a click outside every band does not offer it | UX, accessibility: a near miss stranded the Party off-path (G6) |
| Q5 | The selected path gets a halo. Bend handles are 10 px discs with 24 px hit areas; the point that adds a bend shows as a "+" handle. Handles show only while pins are unlocked, as pin dragging does today, so reading a path in session cannot move a bend (tightens D2) | UX, accessibility |
| Q6 | A path's menu has "Redraw line": it re-enters the Path tool's second step for that path and keeps the record. This is the non-drag way to change bends after drawing | Accessibility (follows V2 D7b "Move") |
| Q7 | Path tool states: disabled with a tooltip until the map has 2 Locations; after the first pin, the hint changes and a line follows the cursor; a click within the pin snap radius picks the pin; clicking the start pin again does nothing; right-click or Backspace removes the last bend; Esc cancels the path (the tool's Esc is handled before the panel's); the tool stays on after a path is made until Esc or the toolbar button | UX, accessibility |
| Q8 | A new path copies the type and travel time of the last path made, ready to edit; the first path of a game starts with Road and 1 day | Director: 30+ paths in prep |
| Q9 | A new path between two Locations already joined starts with one bend pushed to the side, so it never sits on top of the first | All three |
| Q10 | A Location's side panel lists its paths (name, type, time, hidden badge); a click selects the path. "Connect to..." is there too. Its list is sorted by distance and filters as you type | UX, Director, accessibility: keyboard and hub-town access |
| Q11 | The "Show names" setting (R9) also shows path labels, decluttered by zoom like pin names. Hover and selection still show them when it is off (F3 kept) | Director, accessibility: the table cannot hover |
| Q12 | A hidden path fades its colour but keeps its casing at full strength (at least 3:1), and long paths repeat the eye-slash badge on each segment | Accessibility: the faded line measured 1.7:1 |
| Q13 | A Party stopped partway is stored as the path id plus the time spent from one end; its banner position is worked out from that, so editing the path's bends or time never strands it. If the path is deleted, the Party moves to the nearer end | Director |
| Q14 | The stop-partway prompt names the end the Party's last leg started from, with a swap button; it only accepts a time above 0 and below the path's time. A stop made on the path the Party just arrived by replaces that arrival entry (one entry, one undo) | Director (blocker), UX |
| Q15 | The stop entry stores the time spent, so it counts toward travel time; the leg that follows logs only the rest of the path's time. N2 wording kept | Director |
| Q16 | On point crawl maps a pin's "Move Party here" is Director-only and logged as a placement (G4); players move only through Travel to (G5). A Director placement within the pin snap radius counts as "at" that Location | UX (blocker), Director |
| Q17 | On point crawl maps the banner's tooltip says to click to travel; a drag snaps back and a short hint points to Travel to | UX: V2 habit of dragging |
| Q18 | Travel list rows lead with "{destination} by {path}" in body text at 14 px or more, matching the right-click menu; the Party status line is body text too. Muted 12 px stays for field labels only | Accessibility |
| Q19 | One wording for a leg everywhere: "from {from} to {to} by {path} - {time}". With no path name it uses the type; with neither it drops "by". This avoids "the The Ferry Run" | UX |
| Q20 | Copy follows the V2 glossary (V2_COPY section 2): "location", never "place"; {party}, never "the Party"; "Players don't see this" instead of "(Director only)"; "Hidden" chip; US spelling ("Color"); ASCII only in the Lua strings | UX |
| Q21 | The mode choice says "You can't change this later." and has Cancel; the descriptions are distinct (Free: drag the Party anywhere; Point crawl: the Party travels along paths you draw). Empty states get copy: an empty point crawl map says to add locations then join them with the Path tool; a Travel list with no paths from here says so | UX |
| Q22 | Settings popover sections follow V2's grouping: "This map" (scale, pace, border), "Whole game" (travel time unit, path types), then the existing ones; one path type open for editing at a time | UX: scopes were mixed |
| Q23 | Pins, paths, labels and the Party always draw above a border's mask or fade; nothing on the map is masked. The fade band stays narrow | Accessibility |
| Q24 | Import: entries without u/v land on a grid in file order around the center, not in one pile; the placement copy says to unlock pins to place them; one error dialog covers bad JSON, an empty file, and a file where every entry is skipped | UX, Director, accessibility |
| Q25 | The size toast has "Replace image..." | UX |
| Q26 | Swatches are 24 px with a tooltip naming the colour, a check mark on the selected one, and a light ring on Ink. "Delete type" and the toast's Undo border meet 4.5:1 and 3:1, using theme tokens | Accessibility |
| Q27 | Any Party movement animation respects Reduce motion (R9) | Accessibility |
| Q28 | Decision map housekeeping: A3 closed by N1; E2 is the side panel read/edit pattern of V2 locations with its Saving/Saved state; E3 is the V2 delete pattern (confirm only when it removes something else, toast with Undo); H4 "View as player" covers paths with the same rules as players | UX |

**Deferred (with reasons).** Paths that leave the map edge: use an edge Location ("Road to
Northreach") with its own path, then place the Party on the next map. A total of travel time
in the log header, path import, rest/"time passes" entries, and players proposing a route for
the Director to confirm: none is needed for point crawl to work; revisit after a real 30-place
region is built.

### 2.2 Answered by the user (2026-10-08)

| # | Decision | Why |
|---|---|---|
| W1 | When the Director picks a hidden path in Travel to, a prompt asks "Reveal it to players?" with "Reveal and travel" and "Travel in secret" (and Cancel). In secret, players see the leg without the path's name or line ("{party} traveled from Ashford to Hollow Barrow - 1 day"; if the destination is hidden too, the V2 log rules for hidden Locations apply). The Director's Travel list marks hidden paths with the eye-slash | User; both reviews found the leak |
| W2 | A path has an optional "The other way" field: Same (default), Different time (a second time for the B-to-A direction), or Not possible. The Travel list, the stop-partway time and the log follow it. Amends B3 (paths are still one record, drawn once) | User; rivers and one-way passages |
| W3 | A new path starts Revealed; players still see it only while both ends are revealed (H1). Secret paths are hidden by hand | User; revealing places reveals the roads between them |
| W5 | Image size numbers (J1): minimum 1500 px wide, recommended 4000, maximum 12000. Measured 2026-10-08 (TECH_TASK_V2_1 section 8); the user picked the looser set, warning only on clearly tiny or huge images | User, after measurement |
| W4 | A game never has two Directors. Director-only actions (paths, types, import, borders) need no handling for two Directors editing at once; player edits still sync as in V2. Added after lock | User |

## 3. Decision map

Every decision this leg needs, grouped into the categories the design rounds take one at a
time. Status is open unless the ledger settles it.

**A. Map mode**
- A1. Where the mode is chosen: Atlas New map, and Add map on a Location (both create the
  map the moment an image is picked, so a choice must come before the pick or right after).
- A2. How a map shows its mode afterwards (breadcrumb, Atlas card, side panel).
- A3. Mode names: "Point crawl" and "Free"? (copy).
- A4. Can the mode change while the map has no paths yet? (L4 says fixed; confirm the edge
  case of a wrong pick on an empty map.)

**B. Path record**
- B1. Storage: a new table (proposed `RegionMapPaths`) with its own record type and schema.
- B2. Fields: two Location ids on the same map, name?, description, attributes (C),
  visibility, Director note?, audit fields.
- B3. Multiple paths between the same two Locations: allowed? (The Alexandrian: yes, when
  they differ by choice.)
- B4. Direction: always two-way, or one-way allowed?
- B5. What happens to paths when an end Location is deleted, moved to another map, or
  hidden.

**C. Path attributes**
- C1. Which: type (road, trail, river, ...), travel time (computed from scale and pace, or
  entered), danger or encounter note, requirement (a check, a vehicle), others.
- C2. Fixed list or Director-defined.
- C3. Which attributes players see.

**D. Path shape**
- D1. Straight line, bends (waypoints), or curves.
- D2. If bends: how they are added and moved.

**E. Path controls (Director)**
- E1. Create: a path tool (click one pin, then another), right-click "Connect to...",
  side panel action; the non-drag path.
- E2. Select, read and edit: side panel read/edit modes for a path.
- E3. Delete and undo.

**F. Path drawing**
- F1. Line style, and per-type styles.
- F2. Hidden vs revealed paths for the Director, not by colour alone.
- F3. Hover and selected states; labels (name, distance or time) and when they show.
- F4. Zoom and declutter; performance cap.

**G. Party on a point crawl map**
- G1. How a move is made: drag the banner to a connected pin, a "Travel to" list, or both.
- G2. Unreachable pins: how shown while dragging.
- G3. Is there a "on the path" state (part way along), or only at a Location?
- G4. Director override: does "Place Party here" stay free on point crawl maps?
- G5. Players moving the Party: same setting as today?

**H. Players**
- H1. Which paths a player sees (revealed only; both ends visible?).
- H2. Discovering a path (Director reveals it; reveal on arrival?).
- H3. Can players add paths? (Players can add Locations today.)
- H4. View as player for paths.

**I. Session log**
- I1. Leg entry: new kind or reuse "arrived"; names the path; distance and time.
- I2. The drawn route follows the path's shape.

**J. Quick idea 11: image size guidance**
- J1. The numbers (minimum, maximum, recommended), measured on the engine.
- J2. Where the guidance shows (Atlas New map card, side panel image picker).
- J3. The warning: when, where, and whether anything is blocked (proposed: warn only).

**K. Quick idea 10: map border**
- K1. Looks offered (none, soft fade, worn or torn edge, frame).
- K2. Per map or one setting for all.
- K3. Technique and art: a mask image, gradient edges, or a frame image; who makes the art.

**IM. Quick idea 9: JSON import** (decision ids IM1-IM6; L1-L4 are the scope rows)
- L1. Entry point and who may import (Director only?).
- L2. File format: nesting, ids, which fields, re-import of the same file.
- L3. Nesting limit: a Location can only hold children if it has a map image (see 5.4),
  so deep trees need images in the file or import only one level under an existing map.
- L4. Placement: grouped near the center of the parent's map (user), the grouping pattern.
- L5. Preview and confirm, errors, the 250-pin guard, one undo for the whole import.

**M. Cross-cutting**
- M1. Copy manifest for every new string.
- M2. Accessibility: non-drag paths for every drag, line styles not colour-only, keyboard.
- M3. States: late joiner, a path whose end is deleted mid-edit, hot reload. (A game has
  one Director, so there is no case of two Directors editing; see W4.)
- M4. Regression: free maps unchanged; on point crawl maps a free Party drop is replaced.
- M5. Phasing and build order inside V2.1.

## 4. Open questions

Left to the build; each answer goes back into this brief before the slice that needs it ships.

- K3. **Deferred until the user provides the art (2026-10-08).** Torn edge and Frame (V21-04)
  are not built. The art format is in [BORDER_ART.md](BORDER_ART.md). When the two images are
  in the journal library, put their ids in `RegionMapConstants.borderTornMask` and
  `borderFrameImage`, then build V21-04. Until then both tiles show dimmed with "Not
  available yet". Soft fade and None are built and live.
- B1, B2. The path table's exact name, record type and schema (including W2's other-way time
  and Q13's partway Party fields).
- F4. Zoom declutter and a performance cap for paths, measured with a full 250-pin map.
- M3. Late joiner, an end deleted while its path is being edited, hot reload: each tested on
  the slice that adds it.

## 5. Evidence

### 5.1 Current state (code, 2026-10-08)

- **Map creation.** Atlas New map is an image picker card; choosing an image creates the map
  at once and opens it with the name in edit (`RegionMapAtlas.lua:37`, `:117`). Add map on a
  Location works the same through the side panel picker (`RegionMapSidePanel.lua:655`). No
  step exists between the pick and the create.
- **Location record.** `RegionMapRecords.lua:57`: id, parentId, name, u/v on the parent's
  map, pin style, importance, icon, visibility, imageId, imageRevision, mapShared, optional
  `scale` and `pace`, owner fields, revision, hidden. Optional fields (`scale`, `pace`) are
  absent on older rows and read as nil, so an optional mode field can follow the same
  pattern without a schema bump. Validation rejects unknown enum values but ignores unknown
  fields (`IsValidLocationFields`, `:487`).
- **Tree rule.** A Location whose parent has no map image is rejected ("parent has no map",
  `RegionMapRecords.lua:550`).
- **Lines already drawn.** The ruler is a thin panel stretched to the segment's length and
  rotated to its angle (`RegionMapCanvasTools.lua:399-403`). The Party route is a pooled set
  of dots along each leg, only on screen, re-placed on zoom (`:304-366`). Either technique
  draws a straight path segment with no new engine feature.
- **Party.** Stored in the state document. `WriteParty` puts it at a Location (snapped to its
  pin) or traveling at a point (`RegionMapModel.lua:784`). A drag snaps to the nearest
  visible pin within `partySnapRadius` (`RegionMapCanvas.lua:564`); a drop elsewhere is a
  free "traveling" point (`:265-276`). The Director's "Place Party here" jumps anywhere
  (`RegionMapModel.lua:814`).
- **Session log.** Each Party move writes an entry: arrived, traveling, travelingOn or placed,
  with a route of u/v points; consecutive free drops merge (`RegionMapLog.lua:146`). The
  route layer draws those points as dots.
- **Measuring.** `MeasureText` turns two points into distance and travel time from the map's
  scale and pace (`RegionMapCanvasTools.lua:195`). A path's length and time can reuse it.

### 5.2 Engine capabilities

| Need | Finding | Anchor |
|---|---|---|
| Straight path lines | Rotated thin panel (ruler) or pooled dots (route) | `RegionMapCanvasTools.lua:399`, `:324` |
| Image size after a pick | `bgimageWidth` / `bgimageHeight` on the image panel once loaded; already read on load | `Definitions/Panel.lua:33`; `RegionMapCanvas.lua:677-687` |
| Image size before loading | Nothing found; the size is known only once the image has loaded | - |
| Soft or shaped image edge | Panels take `bgimageMask` (plus `bgimageMaskRect`, `bgimageMaskInvert`); used in core for item icon effects. A mask on the map image panel would zoom and pan with it. Needs a mask image and a live probe | `Definitions/Panel.lua:27-32`; `DMHub Game Rules/Equipment.lua:1138` |
| Frame art | `bgslice` nine-slice keeps a frame's edges at fixed width while stretching the middle | `Definitions/Style.lua:86` |
| Open a file | `dmhub.OpenFileDialog{ id, extensions, prompt, open, cancel }`; used by title screen and settings | `Definitions/dmhub.lua:412`; `DMHub Titlescreen/Titlescreen.lua:549` |
| Read JSON | `dmhub.ParseJsonFile(path, onError)`, or `ReadTextFile` + `FromJson` | `Definitions/dmhub.lua:422`, `:434`, `:1058` |

Not yet probed live: a mask on the map image (K3), and the largest image the canvas handles
smoothly (J1). Both are probed in their design rounds.

### 5.3 Precedent

- **The Alexandrian, "Pointcrawls" (parts 1 and 2).** Players at a point choose one of its
  connected paths. Paths differ by type (road, track, river, landmark chain, supernatural,
  stairs or shaft, maze), shown by colour, line style or labels. Two points may have several
  paths if they differ by choice (faster but needs a check), not just by numbers. A hidden
  route is a connection the players must find before they can use it.
  [Part 1](https://thealexandrian.net/wordpress/48666/roleplaying-games/pointcrawls),
  [Part 2](https://thealexandrian.net/wordpress/48668/roleplaying-games/pointcrawls-part-2-advanced-pointcrawl-procedures)
- **Cairn 2e, Warden's Guide.** Each connection records travel time (watches or days); time
  adds up from distance (short, medium, long), path type (road, trail, wilderness) and terrain
  (easy, tough, perilous).
  [Pointcrawls](https://cairnrpg.com/second-edition/wardens-guide/pointcrawls/)
- **VTTs.** No dedicated point crawl tool or Foundry module turned up. Foundry's World
  Explorer reveals a hex grid by hand (hexcrawl, not paths). Likely a gap worth filling;
  low confidence, from one search.
  [World Explorer](https://github.com/CarlosFdez/world-explorer)

### 5.4 Constraints found

- Import (L3): every Location that holds others must have a map image. A JSON tree deeper
  than one level under an existing map either carries image ids or cannot be imported as is.
- Map creation (A1): the pick creates the map immediately, so the mode choice changes that
  flow on both creation surfaces.

### 5.5 User evidence

No community request data gathered (no Discord access in this session). The ideas come from
the user (IDEAS.md 7, 7.3, 9, 10, 11).
