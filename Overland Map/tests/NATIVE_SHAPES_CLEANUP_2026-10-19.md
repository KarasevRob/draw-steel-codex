# Native Shapes cleanup follow-up

2026-10-19. Single-client, read-only engine inspection and diagnostic queries.
No renderer, game records, preferences or installed engine files were changed.

Cleanup remains a failed adoption prerequisite. The installed wrapper omits the
path disposal request that the underlying library requires. Native resource
counters already exist in Shapes, but the current Lua bridge does not expose them.
No replacement stress test or new native-renderer performance run was performed.

## What the installed code establishes

The investigation considered two possibilities: draw-command cleanup implicitly
releases removed paths, or paths require an explicit disposal request. Following
the ownership methods supports the second:

1. `LuaSheetShapes.AddPath` creates a `Shapes.PolylinePath`, retained by
   `SheetShapes.DrawPath`. Drawing it lazily obtains a mesh.
2. `LuaSheetShapes.Remove` calls `SheetShapes.RemoveDrawShape`, which only removes
   its dictionary entry. It does not dispose the path.
3. `ShapesRenderer.OnDestroy` destroys the shapes camera GameObject.
   `SheetShapes.OnDestroy` destroys the allocated render texture. Neither method
   disposes retained paths.
4. `DrawCommand.CleanupCachedAssetsAndMeshes` calls
   `DisposableMesh.ReleaseFromCommand`. That releases a mesh only when all drawing
   commands have released it **and** `disposeWhenFullyReleased` is true.
5. `DisposableMesh.Dispose` sets that flag and returns an eligible mesh to
   `ShapesMeshPool`. Its constructor leaves the flag false. No finalizer is declared
   by `PolylinePath`, its `PointPath<T>` parent, or `DisposableMesh`.

This establishes a missing disposal request on the inspected ownership paths. It
does not measure a leak rate or prove that no unrelated engine-wide cleanup exists.
The [Shapes documentation](https://www.acegikmo.com/shapes/docs/) independently
requires explicit disposal of persistent polyline paths.

The engine also opens a separate draw-command scope for each retained shape every
frame. Fewer GUI panels alone therefore cannot establish a whole-frame speedup.

## Instrumentation available and missing

The installed Shapes assembly has these public static properties:

- `Shapes.DisposableMesh.ActiveMeshCount`
- `Shapes.ShapesMeshPool.MeshCountInUse`
- `Shapes.ShapesMeshPool.MeshCountInPool`
- `Shapes.ShapesMeshPool.MeshesAllocatedCount`

They distinguish unreleased paths from intentionally retained reusable meshes.
A warmed pool may retain meshes after cleanup; in-use counts must return to their
baseline, and total allocations/native memory must stabilize under repeated equal
workloads. Growing allocation counts cannot be dismissed as harmless pooling.

The connected app exposes `dmhub.DumpRenderTextures()`, which successfully emitted
a texture inventory with dimensions and estimated memory, plus Lua/panel counters
through `dmhub.debugPropertyOutput`. These are not mesh or complete camera counters.
No callable mesh-count bridge was found in the inspected Lua interface. The live
globals `Shapes`, `CS`, `luanet` and `UnityEngine` are absent. Reading assembly
metadata in a separate PowerShell process cannot read the game's live counters.

## Concrete engine handoff

This work needs the engine maintainers or an instrumented engine build; engine
implementation remains outside the Overland rewrite's approved scope.

1. Review and add path disposal to record removal and surface teardown, covering
   every retained path exactly once. Use the library's disposal mechanism so
   outstanding render commands can finish before meshes return to the pool.
2. Expose the four existing counters in a diagnostic snapshot, alongside live
   Shapes surfaces/cameras/render textures and native mesh/texture memory. A Unity
   profiler capture is also suitable if it provides the same ownership evidence.
3. Record a warm baseline, then run 1,000 rendered geometry replacements and 100
   open/close cycles. Allow deferred command cleanup between checkpoints. Each
   replacement must actually render: allocating and removing before the next frame
   can miss lazy mesh allocation entirely. Check teardown with paths still present
   as well as explicit Remove, and repeat equal batches to detect progressive growth.
4. Only after cleanup passes, compare the shared-surface stroke/casing prototype
   visually with all current patterns, visibility states, clipping and Fit-to-20x
   zoom on rectangular artwork. Labels and handles stay on their established layers.
5. Run both backends in the same client/session against the current normal/dense
   fixtures: warm-up plus five measured runs, separate opening, redraw, pans, zoom
   and bend editing. Capture complete frame timing and resources, not just Lua
   construction. Reject incomplete focus coverage and capped timing conclusions.

The existing adoption gates remain: dense median p95 improves at least 15%; normal
p95 regresses no more than 5%; normal cold-open median regresses no more than 10%.
The old single-pass construction observations (50 paths/24 segments: about 369 ms
for panels and 6 ms for native shape calls) suggest potential but exclude deferred
rendering and cannot pass those gates. See the
[historical probe](../docs/CURVED_PATHS_RESEARCH.md#live-construction-measurements)
and [current pooled benchmark](PERFORMANCE_2026-10-19.md).

## Reproduction and limits

Run the metadata inspection using Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File "Overland Map/tests/InspectShapesCleanup.ps1" `
  -OutputPath "output/overland-rewrite/shapes-cleanup-2026-10-19/inspection.json"
```

Create the output directory first. `-ManagedDirectory` can select another installed
build. The script uses reflection-only assembly loading; it never invokes engine
methods or attaches to the game process. It records selected ownership methods,
not an exhaustive assembly call graph. The script completed and its PowerShell
syntax parsed successfully. No Lua was edited, so Lua syntax/type/offline checks
were not rerun for this inspection.

Installed assemblies under
`D:\SteamLibrary\steamapps\common\Draw Steel Codex\Codex_Data\Managed`:

| Assembly | SHA-256 |
|---|---|
| Assembly-CSharp.dll | `DF5BA6D9A4055085389A17E8ADA2105AC4F3C15C7CBBDB18E7135D5D89834E34` |
| ShapesRuntime.dll | `E9F1CE51A6AEC1192C73B17205FA09EC53BC56DF3BA25E644A314FE52DB48AD2` |

Some unrelated diagnostics and generic Stack references cannot resolve through
Windows .NET's reflection-only loader against the app's Mono assemblies; the JSON
records every unresolved entry. The relevant path removal, teardown,
ReleaseFromCommand, Dispose and command mesh-cleanup instructions resolved.
The mesh-pool property's existence/accessibility is verified, but some underlying
Stack instructions are unresolved. No native lifetime test is claimed from this
static evidence.
