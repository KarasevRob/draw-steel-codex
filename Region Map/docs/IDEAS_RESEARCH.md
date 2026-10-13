# Overland Map - Implementation research on the open ideas

2026-10-13. Research only: nothing here is designed, approved or scheduled. It covers the
open ideas in [../IDEAS.md](../IDEAS.md) except the hex ideas (3, 3.1, 7.1, 7.3), which the
user deferred to TBA. Every idea is costed in its **full version**, within the mod only (no
engine change, no edits outside `Region Map/`). Line numbers are from the branch at commit
`2ec6b20` and will drift.

## How the score works

Each idea gets three grades, S = 1, M = 2, L = 3, XL = 4:

- **Build**: S = under ~250 new or changed lines in 1-3 files, no new table or interaction
  mode; M = ~250-700 lines, or a new optional field with a Settings control, or a small new
  interaction; L = ~700-1500 lines, or a new table, or a new tool or interaction mode;
  XL = over ~1500 lines.
- **Design**: S = 0-1 open decisions with obvious defaults; M = 2-4; L = 5 or more, or one
  that changes the data model or reopens a decided design; XL = a full brief round.
- **Risk**: S = only patterns already proven in this mod, used the same way; M = proven
  APIs used in a new way, or a cost that needs measuring; L = an API in the stubs but
  unproven in the codex, or a cost likely near the frame budget; XL = needs an engine change.

**Score = Build x 2 + Design + Risk** (4 to 16; lower is simpler). Art the user has to
make (border art, a decorated compass rose) is listed as a dependency, not scored.

## Ranking

| Rank | Idea | Build | Design | Risk | Score | Size (lines) | Depends on |
|---|---|---|---|---|---|---|---|
| 1 | 10. Torn edge and Frame borders | S | S | M | **5** | ~110-170 | The user's art |
| 2 | 13. Change a path's ends | M | M | S | **7** | ~350-450 | - |
| 3= | 16. Compass | M | M | M | **8** | ~290 | Rose art (optional) |
| 3= | 17. Scale bar | M | M | M | **8** | ~350 | - |
| 5 | 14. Curved paths | M | L | L | **10** | ~400-550 | Reopening V2.1 D1 |
| 6 | 12. Route planning (*Later*) | L | L | M | **11** | ~800-1100 | Agreeing the draft frame |
| 7 | 15. Map labels | XL | L | M | **13** | ~1350-1850 | A frame that reopens V2 D4a |

16 and 17 tie. Built together as one "map furniture" corner they come to about 570 lines
instead of about 640, with one corner decision and one test pass.

Every idea fits the existing files except labels, which would add three files (data,
drawing, side panel), each registered through the DMHub MCP workflow. None needs an engine
change. None needs a schema version bump: the record checks match versions exactly
(`RegionMapRecords.lua:694`, `:739`), so a bump would make old and new clients reject each
other's rows; new fields stay optional instead.

## 10. Torn edge and Frame borders - score 5

**Full version.** Torn edge masks the map image with the user's 4096 px mask, stretched to
any map. Frame draws the 1024 px 9-slice art outside the image, and Fit and the camera
limits include it. Both tiles get real previews in Settings.

**What is built.** The `border` field and its checks (`RegionMapRecords.lua:78`, `:519`,
`:590`), `Border` / `LastBorder` / `SetBorder` (`RegionMapModel.lua:645`, `:719-763`), the
tiles that enable once an art id is set (`RegionMapPopovers.lua:248`), the copy, and the two
empty art ids (`RegionMapConstants.lua:61-62`).

**What is not.** The drawing. `Canvas.Layout` draws only Soft fade
(`RegionMapCanvas.lua:827-842`), and `TECH_TASK_V2_1.md:757-758` says "Torn edge and Frame
drawing is not written yet". So this is more than pasting in two ids.

**Approach.** Torn edge: set `bgimageMask` on the map image panel when the border changes
or the image loads (`RegionMapCanvas.lua:971-973`); if masking a streamed image fails, fall
back to an overlay panel like the fade with `bgimageMaskInvert`. Frame: one panel after the
image, sized on zoom only, using `bgslice` (9-slice); `CalculateImageLayout`
(`RegionMapCanvasTools.lua:100`) gains a margin for Fit. Fallback if `bgslice` cannot set
the edge thickness: 8 panels with `imageRect`.

**Engine.** `bgimageMask` (stub `Panel.lua:27`) is used in the codex but never on a
streamed map image. `bgslice` (stub `Style.lua:86`) is used only on small bundled images,
and its units are unclear: the stub says normalized, codex values (14, 20, 100) look like
pixels.

**Open decisions (2).** Frame thickness scales with the map or stays fixed on screen; the
art ships as a library id or a mod image (a live check decides).

**Grades.** Build S (about 110-170 lines over 4-5 files), Design S, Risk M (proven APIs in
a new use: a mask on a streamed image, 9-slice at map scale).

## 13. Change a path's ends - score 7

**Full version.** The Director replaces one end of a path, by "..." > Change ends (a
keyboard-usable picker) or by dragging an end handle onto another pin. The path keeps its
id, name, type, times, notes, visibility and bends. One undo step, refused after a remote
edit. A Party stopped on the path moves with it.

**Approach.**
- A new `RegionMapPaths.ChangeEnd(id, slot, pinId)` beside `UpdatePath`
  (`RegionMapPaths.lua:582-593`). It has to bypass `NormalizeFields`, which refuses end
  changes on purpose (`:523`, "the ends change only by making a new path").
- The kept pin stays in its slot, so `time`, `back` and `backTime` keep their direction.
- If the new pair already has a path and this one has no bends, add the bow bend (move
  `OffsetBend` from `RegionMapPathTool.lua:47-57` into the Paths file).
- Party: if it counts from the replaced end, rewrite `pathFrom` to the new pin in the same
  undo step (`Model.MovePartyOff`, `RegionMapModel.lua:998-1001`). Without that,
  `RegionMapModel.lua:810` would silently drop it off the path.
- Picker: reuse the Connect to picker (`RegionMapPathPanel.lua:570-666`) as a new panel
  mode. Drag: two end handles beside the bend handles (`RegionMapPathLayer.lua:576-645`),
  a new drag kind, and the Party drag's snap highlight (`RegionMapCanvas.lua:1097-1113`).
- Log: no change. Entries copy their route, path name and ends when written
  (`RegionMapLog.lua:272-285`), so past legs read as they were.

**Engine.** Nothing new; only patterns this mod already uses.

**Data.** None; `aId` and `bId` exist.

**Risks.** The end handle must stay clear of pin hit boxes, which take presses first when
pins are unlocked. For a moment after a change, other clients may get the path row before
the Party write. Moving an end to a hidden pin hides the path, and its past legs, from
players.

**Open decisions (4).** Party on the replaced end (move with the line, recommended);
keep or clear bends; the handle's look; one end per action or both.

**Grades.** Build M (about 350-450 lines over about 11 files; a picker mode and a drag
kind), Design M, Risk S.

## 16. Compass - score 8

**Full version.** A per-map compass set by the Director: off, in a screen corner, or on the
map (pans with it, draggable when pins are unlocked); a north angle; drawn from
`phosphor/compass.png` (proven in the codex at `DocumentSystem/DocumentSystem.lua:74`) with
a slot for rose art later.

**Approach.**
- Data: one optional field on the map row,
  `compass = {place = "off"|"corner"|"map", angle, u, v}`. A bad value must read as off,
  not reject the row as a bad `border` does (`RegionMapRecords.lua:590-591`), which would
  hide the map from everyone.
- Drawing: a disc in the pin look with a tinted glyph, rotated by `rotate` (written only
  when it changes), and an "N" placed at the needle tip.
- Corner: the free slot is bottom-left, one row above the camera controls (every other
  corner is taken). On the map: a canvas child after the fade, placed with `panel.x/y`
  like pins, with a drag kind that saves through undo.
- Settings: Off / Corner / On the map, and a degrees field.

**Engine.** `rotate` on image panels is used elsewhere in the codex
(`DMHub Core UI/Dropdown.lua:335-337`), but in this mod only on plain bars.

**Risks.** The Phosphor needle may be diagonal, with ends that look alike, so an "N" marker
is probably needed and the base angle set by eye. A rotated small mask's sharpness. The
corner row's height in a 720x480 popout at Font Size 140 (about 514x343 px of map).

**Open decisions (4 for the user).** Which corner; on the map, a constant screen size or
growing with zoom; how north is set (degrees, 8 directions, a two-click tool, a handle);
one global art slot or per-map Plain/Rose tiles. A two-click "Set north" tool adds about 60
lines and would make Build L.

**Grades.** Build M (about 290 lines over 7 files, a new field with Settings and a small
drag), Design M, Risk M.

## 17. Scale bar - score 8

**Full version.** A checkered bar in the bottom-left corner on calibrated maps, with ticks
and labels ("0 5 10 mi"). Its length is the largest 1-2-3-5 x 10^n distance that fits about
160 px times Font Size, picked again as the camera zooms. Units follow the map's scale; a
time line shows when the map has a pace. Players see it; the Director turns it off per map
and gets a hint on an uncalibrated map.

**Approach.**
- Data: one optional `scaleBar` boolean on the map row, absent meaning shown.
- Maths in `RegionMapCanvasTools.lua`: export `ImageDistance` (`:251`), add
  `PixelsPerUnit` and `NiceLength`. Add a formatter: today's `FormatNumber` (`:243`) turns
  0.05 into "0.1" and 0.01 into "0". Move the travel-time wording out of the ruler's
  `MeasureText` (`:276-282`) so both share it.
- Component: a plate holding up to 5 blocks at percent widths, tick labels placed with
  `panel.x`, a unit label and a time label. Updates only when the map, zoom, Font Size,
  unit or pace changes: one width write and a few `x` writes.
- Settings: one control in the "This map" section (`RegionMapPopovers.lua:279-291`).

**Engine.** Nothing unverified: every API is already used in this mod.

**Risks.** Label width estimates at Font Size 140; a long toast overlapping the corner row
in a small popout; block contrast on light, dark and sea art; the cost of the per-zoom
write (expected under 1 ms; fallback is to update when the zoom settles).

**Open decisions (4 for the user).** On by default for existing calibrated maps; a chrome
plate or map-ink blocks with a casing like paths; what the time line says; the hint as a
chip or in Settings only.

**Grades.** Build M (about 350 lines over 8 files, a new field with Settings), Design M,
Risk M.

## 14. Curved paths - score 10

**Full version.** A per-path "Curved" option (old paths stay straight), drawn as a
centripetal Catmull-Rom curve through the existing bends so they stay on the line. Hit
testing, labels, eye-slash marks, the stopped Party, the walk animation, new log routes and
the route dots follow the curve, and dash patterns run on without seams.

**Approach.**
- Curve maths in Lua in `RegionMapPaths.lua` (`Curve`, `LinePoints`, cached by revision),
  computed in u/v so every client gets the same shape.
- `Travel.Slice` (`RegionMapTravel.lua:73-102`) reads the curve, which carries the stop
  spot, routes, log and walk animation with it.
- Path layer: place the samples as pooled pieces keyed per sample, which keeps the gain
  from commit `2ec6b20`.
- **Seams are real today:** marks are placed "at whole periods from the segment's start"
  (`RegionMapPathLayer.lua:268-269`). Curve pieces of 6-25 px are shorter than the dash
  period (16-27 px), so dashed lines would turn solid. The fix carries the walked length
  from piece to piece; the route dots need the same.
- Labels use the longest span by arc length; eye-slash marks one per span, not per piece.

**Engine.** `panel.shapes` exists in the stubs (`Definitions/Shapes.lua`) but is used only
by the small `gui.Curve` editor (`DMHub Core UI/Gui.lua:4887`). Its `GetCurvePoints`
returns a 1D curve, not a 2D spline, and the stubs show no dashes, casing or transform. It
is not a way out without a live spike.

**Performance (estimates from README section 5, not measured).** Curving every bent path on
the test map roughly doubles the pieces (1401 to about 2800 at Fit, over the 2500
`pathPieceLimit`). First draw goes from 123 ms to about 250-350 ms, a zoom re-place from
23-34 ms to about 45-70 ms. A zoom settle adds about 600-1200 style writes, so expect 1-2
slow frames per zoom on curve-heavy maps.

**Open decisions (7+).** Reopening V2.1 D1 ("follows the art without curve costs") needs
sign-off; per path, per type or both; new paths straight or remembering; old logged legs
keep their stored route; draft previews curved or straight; sampling quality against cost;
whether to spike `panel.shapes`.

**Grades.** Build M (about 400-550 lines over 11 files, a new field with a control), Design
L (reopens D1), Risk L (cost likely near the frame budget).

## 12. Route planning - score 11 (*Later*)

**Full version.** Pick a destination pin on the same point crawl map and see 3-4 routes
(fastest, fewest legs, another way, optionally avoiding a path type) with total times,
previewed on the map. "Follow" stores the route as a plan; "Next leg" travels one leg
exactly as Travel to does (one log entry, one undo). The Director can stop partway or
cancel. Players plan only over paths they see, and only with "Players can move the Party".

**Approach.**
- Search in `RegionMapTravel.lua`: first hops from `Travel.Options()` (`:130`), later arcs
  from `Paths.PathsOf` (`RegionMapPaths.lua:125`) filtered by `RegionMapPaths.CanSee`
  (`:87-94`), weighted by `Travel.Duration`. Dijkstra, with Yen's k-shortest paths (K = 3)
  for alternatives, or a cheaper penalty method.
- Plan stored inside `party` in the `regionMapState` document. Because `WriteParty`
  (`RegionMapModel.lua:903`) rebuilds the Party, every other move drops the plan for free.
  Players see a plan cut short at the first leg they cannot see.
- Next leg goes through the existing Travel path, keeping the reveal-or-secret question.
- Preview: route halos and numbered badges in the path layer, only on paths the viewer
  already draws, so hidden paths cannot leak.

**Performance (estimate).** One Dijkstra on about 250 pins and 600 directed arcs is about
0.5-1 ms. Yen K = 3 on an 8-leg route is about 16 searches, 10-20 ms, near the frame budget
on uncapped maps, so alternatives run in a `dmhub.Coroutine` (used in this mod at
`RegionMapImport.lua:225`).

**Risks.** The plan write replaces the whole Party; written from a stale copy it could move
the Party back (whether the engine merges document writes per field is unverified). Two
clients pressing Next leg at once log a leg twice, as two Travel to presses can today.

**Open decisions (9).** Where the plan lives; what "stop" means; which alternatives and how
many; what players see of a Director plan with hidden legs; who may cancel; a broken plan
(replan or cancel); Travel to off the plan; whether the plan shows to everyone; picking the
destination by list or by clicking the map.

**Grades.** Build L (about 900 lines over 11 files), Design L (nine decisions; reopens
V2.1's deferred multi-leg routes; the draft frame is not agreed), Risk M.

## 15. Map labels - score 13

**Full version.** Straight one-line text on one map at any angle (no text bent along a
curve), sized in map units so it grows with zoom, with a size choice, letter spacing and
Hidden/Revealed. Created by a tool or right-click; edited, dragged, rotated with a handle,
deleted with undo; removed with its map; hidden by zoom; in search and JSON import; pins
draw above it.

**Approach.** Copy the V2.1 paths pattern: a new table and data file modelled on
`RegionMapPaths.lua`, a drawing layer modelled on the path layer, a side panel form
modelled on `RegionMapPathPanel.lua`. Cascades in `DeleteLocation` / `RemoveMap`
(`RegionMapModel.lua:1057-1126`). Undo needs no change (steps are keyed by table name). V1
label code is not reusable: V1 labels had no size or angle, and wrote `fontSize` at every
layout, the costly pattern the mod has since removed.

**Engine.**
- `rotate` on a text label is proven in the codex
  (`Draw Steel Character Builder/CharacterPanel.lua:652`).
- There is no letter-spacing style, but the `<cspace=0.25em>` text tag works
  (`Codex Titlescreen/EncounterOfTheWeek.lua:3827`).
- Large `scale` factors on text (over about 5x) and rotated hit testing by the engine are
  unverified; hit testing would be done in Lua instead.

**Performance (estimate).** With 50 labels, pan is free (the layer slides). A zoom writes up
to 50 `scale` values a frame, about 1.5-3.5 ms, which must be measured; the fallback is to
resize when the zoom settles, which makes labels jump in size.

**Open decisions (14).** First the frame: what a label is for that a Location is not, which
reopens V2's "one object" decision (D4a). Then who may add labels, the size model, zoom
hiding, angle snapping, spacing and type conventions, look, overlap with pins and path
names, clicks during play, search, import, a Show labels switch, default visibility, and
delete confirms.

**Grades.** Build XL (about 1650 lines, 3 new files, a new table, a tool and two drag kinds;
L if search and import are cut), Design L (near XL), Risk M.

## Outside references

- Rounding a scale bar's length: MapLibre's scale control snaps to 1, 2, 3, 5 or 10 times a
  power of ten ([scale_control.ts](https://devlop.bogorkab.go.id/kunker/node_modules/maplibre-gl/src/ui/control/scale_control.ts));
  OpenLayers' ScaleLine uses 1, 2 and 5
  ([ScaleLine docs](https://wichita.ogs.ou.edu/OpenLayers-2.12/doc/devdocs/files/OpenLayers/Control/ScaleLine-js.html)).
  Alternating-segment bars are a standard style
  ([QGIS: The Scale Bar Item](https://docs.qgis.org/4.2/en/docs/user_manual/print_layout/layout_items/layout_scale_bar.html)).
- Compass rose and north arrow:
  [Dictionary.com](https://dictionary.com/browse/compass-rose);
  [Rand McNally, Ask a Cartographer](https://randpublishing.com/blog/ask-a-cartographer-is-a-north-arrow-or-compass-rose-really-needed-on-a-map/).
- Curves: centripetal Catmull-Rom is the only parameterization that guarantees no cusps or
  self-intersections within a segment, and it passes through its control points
  ([Yuksel et al.](https://cemyuksel.com/research/catmullrom_param/)).
- Alternative routes: Yen's k-shortest loopless paths, O(kn(m + n log n)) with Dijkstra
  ([JGraphT YenKShortestPath](https://jgrapht.org/javadoc/org.jgrapht.core/org/jgrapht/alg/shortestpath/YenKShortestPath.html)).
- Area labels: Imhof's rules (horizontal or a gentle arc, spaced across the area) as
  summarized in [Krumpe and Mendel, Computing Curved Area Labels](https://arxiv.org/pdf/2001.02938)
  and [Red Blob Games, SDF curved text](https://www.redblobgames.com/blog/2024-10-09-sdf-curved-text/).
  Map text in another VTT: [Foundry VTT Drawings](https://foundryvtt.com/article/drawings/).
- 9-slice borders: [Unity manual, 9-slicing](https://docs.unity3d.com/2020.1/Documentation/Manual/9SliceSprites.html).
