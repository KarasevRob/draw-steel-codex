# Implementation notes for open ideas

Research began 2026-10-13; pruned against the current mod on 2026-10-16.
These are possible approaches, not approved designs. Current scope and deferrals
live in [IDEAS.md](../IDEAS.md). Old line-count estimates and completed label/import
proposals have been removed.

## 10. Torn edge and Frame borders

The map record, validation, settings tiles, copy and empty artwork IDs already
exist. Rendering currently handles None and Soft fade only; supplying artwork IDs
alone does not implement the other borders.

- Torn edge: investigate a mask on the streamed map image. An overlay using an
  inverted mask is a possible fallback.
- Frame: a nine-slice image outside the map. Fit and camera bounds must include its
  margin. Eight cropped panels are a fallback if the native slicing cannot express
  the required thickness.
- Verify streamed-image masking, slice units and asset access across games.
- Decide whether frame thickness scales with the map or stays fixed on screen.

The user's [border artwork specification](BORDER_ART.md) remains the dependency.
Relevant code: RegionMapConstants, RegionMapPopovers, RegionMapCanvas and
RegionMapCanvasTools.

## 13. Change a path's endpoints

Bend handles and Redraw line already reshape a path. Endpoint reassignment would
preserve its ID, name, type, times, description, note and visibility instead of
requiring deletion and recreation. Confirm that this is the requested scope first.

A possible implementation adds a guarded write in RegionMapPaths and a picker
reusing the Connect to list. Existing field validation deliberately rejects endpoint
changes. Keep the unchanged endpoint in its slot so forward/backward time retains
its direction.

Decisions and risks:

- Keep or clear existing bends; choose one endpoint per action or both.
- Decide what happens to a Party stopped on the path. Its pathFrom reference must
  remain valid; path and Party updates need one Undo operation.
- Keep the same-map, distinct-endpoint and viewer-access checks.
- Consider the bow used when multiple paths join the same pair of pins.
- Preserve historical log route/name snapshots. Access follows the path and its
  endpoints, so choosing a hidden endpoint changes what players can see.
- If drag handles are added, keep them distinguishable from pin hit areas.

## 16. Compass

A per-map optional record could hold placement, north angle and map coordinates.
Malformed optional data should fall back safely instead of hiding the owning map.

A plain version can use the bundled compass icon; a decorated rose needs artwork.
The glyph's baseline direction and north marker need visual verification.

Decide screen-corner versus map placement, fixed versus zoom-relative size,
how north is set, whether players see it, and whether artwork is shared or per map.
Check small-window layouts at the largest Font Size before choosing a corner.

## 17. Scale bar

Reuse the existing map calibration and units. A checkered bar needs no new scale
model, but may need a visibility preference.

A screen-fixed bar can choose a readable round distance from the current zoom;
a map-placed bar would represent one fixed distance. Decide this before choosing
the drawing and update path. The existing ruler formatter rounds tiny distances too
aggressively for every possible scale-bar length.

Other decisions: behavior on uncalibrated maps, defaults for existing maps,
player visibility, backing/contrast, and an optional travel-time line when pace is set.
Update on map, zoom, Font Size, units or pace changes instead of rebuilding every frame.

## 14. Curved paths

Use [CURVED_PATHS_RESEARCH.md](CURVED_PATHS_RESEARCH.md), which supersedes the initial
renderer assumptions and timing extrapolations. It includes native AddPath evidence,
resource-lifecycle questions, sampling limits, and integration with travel and hit tests.

## 12. Route planning

Saved for later by the user. The interaction has not been agreed.

One possible design searches visible paths on the current map using travel time as
edge weight, offers a few alternatives, and optionally stores a plan followed one leg
at a time. Reuse Travel.Options, Travel.Duration and the existing travel/Undo/log flow.
Dijkstra or a bounded alternative-route search are candidates, not chosen algorithms.

Before implementation, decide:

- Preview only, a persistent plan, or whole-route travel.
- Who sees and may cancel a plan; how hidden legs are represented.
- What happens after a path changes, a plan breaks, or the Party leaves the plan.
- How concurrent travel actions avoid duplicated legs or stale Party writes.
- How many alternatives are useful and how their cost is bounded on uncapped maps.

The original timing estimates were not benchmarks and are not acceptance criteria.
