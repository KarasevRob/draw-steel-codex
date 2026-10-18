# Curved overland paths and rendering cost

Research date: 2026-10-16. Scope: Overland Map (`Overland Map/`). Status: research;
the curve feature and renderer changes are not implemented.

Curved paths are feasible within the mod. A live probe in Draw Steel Codex build 10
successfully displayed a smooth sampled curve through `panel.shapes:AddPath`.
The main cost is how the sampled geometry is represented and updated: the existing
renderer creates UI panels for individual segments, while the native shapes API
retains an entire polyline as one shape.

The recommended starting point is cached, adaptively sampled curves using the existing
renderer. Native paths are a promising optimization candidate, but their resource
cleanup, zoom quality, and performance in the actual overland layer need verification.

## Current renderer

[RegionMapPathLayer.lua](../OverlandMapPathLayer.lua) draws paths as thin rotated panels.
A solid segment uses two panels: a wider casing underneath and a coloured mark on top.
Double lines use three. Dashed and dotted patterns create separate marks and casings.

The implementation already reduces repeated work:

- Panels are pooled, with runs keyed by path and segment so pieces retain their styles.
- Geometry is placed within the viewport plus a margin of half a view around it.
- Ordinary panning moves the containing layer through `panel.x` and `panel.y`.
- During zoom animation, `RegionMapCanvasTools.Stretch` moves existing pieces while
  preserving their sizes; final placement happens after zoom settles.
- Style assignments are cached and rounded to avoid unnecessary engine style passes.

The current `pathPieceLimit` is 2,500. This is a **pattern simplification threshold**,
not a hard geometry or memory ceiling: a dashed segment falls back to a solid mark
when the estimated budget is exceeded. Solid segments still allocate pieces, and the
double-line branch does not use that budget check. Curves need their own sampling limit.

Existing performance records identify style updates as a major cost. The
[README performance section](../README.md#5-performance) reports 23-34 ms path
re-layouts in an earlier test with 150 paths on the active map, and later improvements
from direct position writes and stable pooling. Those historical results used different
fixtures and optimization stages; they are context, not curved-path benchmarks.

## Live construction measurements

A temporary dialog was mounted inside the running game without restarting the app.
The first visual probe drew a cubic Bezier curve sampled at 65 points, alongside its
control polygon. This established that `AddPath` accepts a general sequence of 2D
points; it does not require a function whose x coordinate always increases.

The construction comparison used an 800 by 400 drawing surface and synthetic paths
sampled at either 3 or 24 segments. Each path had a dark casing and a lighter stroke.
The panel comparison attached its children in one batch, matching the production
pool's approach to attachment. Timings used `os.clock()` around construction calls.

| Renderer | Paths | Segments per path | Drawing objects | Construction call time |
|---|---:|---:|---|---:|
| Rotated UI panels | 50 | 3 | 300 panels | About 39 ms |
| Rotated UI panels | 50 | 24 | 2,400 panels | About 369 ms |
| Native paths on one surface | 50 | 24 | 100 shapes | About 6 ms |
| Native paths on one surface | 150 | 24 | 300 shapes | About 18 ms |

These are synthetic, single-pass construction observations, not measurements of the
production path layer. Panel times include surface creation and point generation;
those preparatory operations accounted for approximately 1-2 ms. Native times cover
the shape creation calls after preparing the points and surface. Neither timing
includes all deferred layout, mesh generation, camera rendering, or GPU work.

A preliminary panel test attached children individually and took substantially longer.
That result is excluded from the comparison because production pooling attaches in
batches.

Frame intervals were also sampled over 120 updates per case, but the app's dedicated
performance windows recorded zero focused frames during the earlier sampling pass.
Intervals clustered around display-paced values such as 16.7 and 33.3 ms. These short
samples do not establish GPU cost, available frame-time headroom, or a production FPS
target. No GPU-memory measurements were taken.

The temporary dialog and its global probe state were removed. No source files, map
records, preferences, or uploaded assets were changed during the live research.

## Native shapes capability and limitations

The exposed [Shapes API](../../Definitions/Shapes.lua) provides `AddPath`, `AddLine`,
`AddDisc`, colour and thickness settings, `SetColor`, and `Remove`.
The shipping `gui.Curve` editor in [Gui.lua](../../DMHub%20Core%20UI/Gui.lua) already
uses `AddPath` for sampled curves.

`GetCurvePoints` is a different capability: it returns scalar samples of a
one-dimensional curve. It is not a general two-dimensional route-spline helper.
The mod would calculate its own 2D samples and pass those to `AddPath`.

Read-only inspection of the installed engine assemblies established the rendering
mechanism:

- `LuaSheetShapes.AddPath` constructs a `Shapes.PolylinePath` and stores its colour and
  thickness in a `SheetShapes.DrawPath`.
- `ShapesRenderer.Init` creates a `SheetShapes` camera surface and displays its render
  texture through a Unity `RawImage`.
- `SheetShapes.Init` allocates a render texture from the camera's template texture.
- `SheetShapes.LateUpdate` submits the retained shapes every frame, with a separate
  command scope for each shape.
- `ShapesRenderer.Update` does not implement a surface-resolution adjustment.

Consequently, one native drawing surface can avoid thousands of styled UI objects,
but it adds a camera, render texture, and recurring drawing work. A surface per path
would multiply those resources; a shared surface is the candidate worth testing.
The exact texture resolution, format, memory footprint, and behavior at large zoom
were not established. Vector input alone does not guarantee sharpness when its raster
output is enlarged.

The public wrapper exposes no in-place path-point update or dash-pattern setting.
Repeated geometry changes would currently require removal and recreation. Dashes,
dots, double strokes, and outlines therefore need deliberate handling; splitting every
dash into another native shape reduces the object-count advantage.

### Mesh cleanup concern

In the inspected build, `SheetShapes.RemoveDrawShape` only removes the dictionary entry.
`SheetShapes.OnDestroy` releases the render texture, but neither inspected method calls
`Dispose` on the retained path meshes. The underlying `Shapes.DisposableMesh.Dispose`
is the method that releases its mesh; no finalizer was found in that class hierarchy.

This is a concrete cleanup gap to investigate before repeated native-path rebuilding
is used in production. It is not a measured memory-leak rate or proof that no other
engine cleanup mechanism exists. The library's documentation explicitly requires
disposing persistent polyline paths and notes that modifying them rebuilds mesh data.
[Shapes documentation](https://www.acegikmo.com/shapes/docs/).

Inspection used `Assembly-CSharp.dll` and `ShapesRuntime.dll` under the installed
`D:\SteamLibrary\steamapps\common\Draw Steel Codex\Codex_Data\Managed` directory.
An engine source checkout was unavailable at the checked locations.

## Resource implications

| Resource or operation | Implication for curves |
|---|---|
| Curve calculations | Cacheable work proportional to the number of samples. The synthetic point-generation work was small relative to panel creation, but a production spline implementation still needs measurement. |
| UI construction and memory | Panel count grows with sampled segments. Fifty solid paths at 24 segments already require 2,400 panels before labels, selection halos, and editing handles. |
| Zoom and bend editing | More pieces can require more position and style updates. Rebuilding every frame would lose the current renderer's main optimization. |
| Ordinary panning | Cached geometry can continue moving as a layer until the view crosses the placement margin. |
| GPU rendering | More samples mean more geometry; casing and overlapping marks add work. Native shapes trade UI-object overhead for camera, texture, and shape-submission costs. |
| Hit testing | Scanning every sampled segment increases pointer-query work. Cached bounds can reject distant paths before segment-distance tests. |
| Network and persistence | Store bend/control points and curve settings, rather than viewport-specific samples. Sampling can remain local. Historical route snapshots need a separate geometry policy. |

The construction measurements show that geometry cost depends on sampling density
and representation; there is no universal twofold cost for curved paths.

## Curve shape and integration

A centripetal Catmull-Rom spline is a suitable candidate when existing bend points
should remain on the visible path. Compared with uniform parameterization, it avoids
cusps and self-intersections within individual nondegenerate cubic spans. It does not
guarantee that an entire route cannot cross itself or that it stays on the original
straight segments. Duplicate points and endpoints need explicit treatment.
[Yuksel, Schaefer and Keyser](https://www.cemyuksel.com/research/catmullrom_param/catmullrom.pdf).

Sampling should adapt to screen-space error: use fewer segments on gentle stretches
and more around tight bends. A tolerance around 0.5-1 screen pixel is a proposed
starting point for visual testing, not an established acceptance threshold. Curve
parameterization and length calculations should account for the map image's aspect
ratio so narrow or wide maps do not introduce unintended distortions.

Rendering alone is insufficient. The following must agree on the same curve geometry:

- **Dashes and route dots:** carry cumulative distance across sample boundaries.
  The current code restarts spacing on each segment, which can destroy the pattern
  when samples are shorter than a dash period.
- **Labels and hidden-path badges:** place them by meaningful route spans or arc
  length, rather than treating every short sample as a separately annotated segment.
- **Selection and hit testing:** follow the visible curve and retain the current hit
  tolerance.
- **Party position and travel:** update `RegionMapTravel.Slice` and its callers so
  stopped positions, movement, and new route logs follow the curve.
- **Editing:** keep authored bend handles distinct from generated sample points;
  draft previews and insertion handles must follow the selected curve behavior.
- **Existing paths and history:** define an explicit migration policy. A per-path curve
  option can preserve current shapes until changed; historical logged routes should
  not silently acquire a different shape.

Primary integration points are [RegionMapPaths.lua](../OverlandMapPaths.lua),
[RegionMapPathLayer.lua](../OverlandMapPathLayer.lua),
[RegionMapCanvasTools.lua](../OverlandMapCanvasTools.lua), and
[RegionMapTravel.lua](../OverlandMapTravel.lua).

## Recommended implementation direction

Start with optional curves, a shared geometry representation, adaptive sampling, and
cache invalidation on actual path or relevant view changes. Preserve the existing
pooling, culling, direct position updates, and delayed zoom placement. Enforce an
explicit sampling budget rather than relying on the dash simplification threshold.

Evaluate the native renderer separately after resolving its mesh lifetime. Compare both
approaches in the actual overland canvas with the same paths, styles, and viewport:
first open, warm redraw, ordinary and long pans, wheel zoom, bend dragging, and repeated
open/close cycles. Include solid, dashed, dotted, and double paths, visibility states,
selection, party movement, and non-square maps. Measure focused whole-frame times and
memory alongside Lua call time before choosing a production renderer.
