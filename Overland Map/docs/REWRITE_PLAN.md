# Overland Map architecture rewrite

Implementation and verification record, 2026-10-18. The approved plan supplied with
the task is the acceptance contract. Remaining acceptance gaps below are explicit;
they are not successful checks. Publication is separate.

## Boundaries

Preserve the existing features, toolbar order, one active map, and all three hosts.
Require the current Codex runtime. Use fresh Overland identifiers without migration,
aliases, or dual storage access. Old development data stays untouched. Overland state
does not participate in tactical Revert Turn. Guarded Overland Undo remains available.
Two-client live tests are excluded; offline concurrency simulations are required.

No Tabletop drag-to-open, cards, minimizing, switcher integration, file drop/paste,
pings/following, richer previews, new sharing rules, curves, hexes, multi-leg routes,
or engine development is included.

## Baseline and prerequisites

- Original CodeMod: `ec447c62-03db-4416-a5a2-0b013c0f3893`, displayed as Overland Map.
- Original 32 file IDs, revision counts, dependency IDs, and order are captured in
  `output/overland-rewrite/cloud-baseline.json`. Renames use `file.name` and
  `mod:Upload()`; existing file records are not deleted or recreated.
- The initial working tree already contained Map aids and other changes. Its status,
  tracked patch, and module hashes are retained in the same evidence directory.
- Baseline: 146 checks passed across eight offline suites. Lua 5.4.7 is installed
  under `../dependencies/lua/bin`.
- Full-repository LuaLS ran with the documented command and four workers. It reported
  nine pre-existing diagnostics: eight in `output/segmented-stamina` and one in
  `tests/ai_minion_critical_test.lua`. Report: `baseline-luals.json`. Sources were
  renamed during this run; the final check must run against a settled tree.
- The user confirmed that `tools/lua-typing/check.ps1` and `gen_table_overloads.py`
  exist only in the maintainers' private parent repository. They cannot be restored
  from this checkout or machine. Use the direct whole-repository command in `TYPING.md`.
  LuaLS 3.19.2 was downloaded from the official release; its Windows archive digest is
  `4a3dc851b3b31e7b75a23f645d1ba4a2137579a55f5fa4edbb17a3e2a6254044`.
  The workflow pins the Linux archive separately. Both local 3.19.1 and CI-matching
  3.19.2 reported the same nine baseline diagnostics, with none in Overland Map.
  No literal `X.tableName = "..."` declarations were added/renamed, and the generated
  overload blocks contain no Region references; no manual generated-block change was needed.
- Connected runtime: build 10, version `0.0.857`. `dragMove = false` assignment works.
  Registered cursor IDs include `horizontal-expand`, `vertical-expand`,
  `diagonal-expand`, and `diagonal-expand-mirror`.
- `groupOpacity` and `boxShadow` are rejected by this runtime as unknown style
  properties. The engine logs the rejection without throwing, so a successful
  `pcall` is not evidence that a style exists. No production fallback was added.
- `panel.shapes.AddPath`, `Remove`, focused-frame performance windows, and
  `DumpRenderTextures` exist. A global `Shapes` namespace is not required.

## Capability preservation matrix

The destinations below describe the target architecture. Each row needs final live
or offline evidence before the rewrite can be marked complete.

| Existing capability | Owning destination | Required evidence |
|---|---|---|
| Fullscreen/window toggle, geometry, fallback, raise-before-close | Host and view session | Same content/focus/drafts; minimum geometry; live resize |
| Native popout/return, presentation respects host | Host and transitions | Transfer guards, one map, clean restart |
| Toolbar order, context menus, Escape layers, keyboard | Shell and gesture controller | Input matrix, Tab/Enter/Space/Escape |
| Atlas cards, map creation, sharing badges, menus | Viewer read models and Atlas | Permissions, truncation/hover, CRUD/Undo |
| Location tree, nested maps, ancestor access | Records and model | Fresh schemas, limits, malformed rows, permission loss |
| Location name, description, Director notes | Three editor/save lanes | Busy, close, partial failure, exact Retry, guarded Undo |
| Pin styles, tiers, badges, lock/ownership | Pin layer and gesture adapter | Overlap, direct movement, screen size/font scaling |
| Pin typography and hover descriptions | Pin text services/editor/layer | Existing 17 checks and live font/theme sweep |
| Map replacement and borders | Images, artwork layer, model | Retained references, fade, no geometry drift |
| Attachments, local viewer, image pickers | Images and reader/editor adapters | Lazy requests, stale callbacks, missing/video/private assets |
| Independent labels, formatting, visibility and search | Labels, queue, layer, editor | Existing 26 label + 14 appearance checks; transforms |
| Compass artwork/north text, None background | Aid model/layer/editor and geometry | Independent text size, rotation, resize, direct closed-editor drag |
| Scale bar, units, calibration, collision handling | Aid model/layer/editor and geometry | Distance fixes endpoints under all style changes |
| Placement, ruler and calibration click/drag | Geometry and tool adapters | Both workflows; numeric alternatives; cancellation |
| Paths, types, bends, endpoint rules, redraw | Paths, geometry, layer, gestures | Patterns, clipping, hidden ends, one commit/Undo |
| Party drag/snapping and free placement | Party service/layer/gesture adapter | Snap threshold, ownership/switches, placement logging |
| Point crawl travel and stop partway | Travel domain and Party editor | Direction/time rules, hidden routes, rescue/Undo |
| Session log, notes, route, cap, merged drops | Log domain/editor and guides | Save-on-close, secret text/route filtering, batching |
| Search, breadcrumbs, parent readers | Viewer read models/readers | Limits/hover, ancestor changes, keyboard navigation |
| Journal resolution/linking | Journal domain and editors | Permissions and delayed chooser identity |
| JSON/file import, preview, batching and discard | Import plus transition registration | Existing parser checks, exact partial results, explicit discard |
| Show to players and View as player | Present service and transitions | Flush original IDs; immediate visibility reconciliation |
| Camera, per-viewer preferences, Reduce motion | Preferences, camera/view session | Direct pan, fit/20x, settled zoom, no editor/Atlas rebuild |
| Undo, retry and concurrent changes | Receipts, queues and Undo | No timeout confirmation; row/state/Party revision guards |
| Themes, Font Size, contrasting artwork | Shared controls and retained layers | 80/100/140%, minimum window, bright/dark/dense maps |

## Implemented boundaries

- Directory/files, namespaces/types, panel IDs, selectors, diagnostics, preferences,
  state document and tables now use Overland names. Labels use `OverlandMapLabels`.
  Sidecars use `locationId`, schema 1. Combat checkpoint registration was removed.
- `OverlandMapLifetime` owns game generations, cancellable timers and binding owners.
  Table receipts and all mod schedules carry game guards.
- `OverlandMapSaveQueue` owns immutable batches, exact retries and independent
  removable observers. Closing an editor detaches observers while accepted writes finish.
- `OverlandMapEditors` provides Location's three independent save lanes plus path and
  log lanes. Location/path panels retain the 1.5-second text debounce and confirmation
  behavior. Log notes retain save-on-close; imports retain explicit discard.
- `OverlandMapPreferences`, `OverlandMapControls`, and `OverlandMapSession` separate
  persistent preferences, shared GUI construction, and view transition contracts.
- `OverlandMapImages` separates dimensions from texture readiness and owns timeout,
  cancellation and late-success rules. Map artwork, attachments, Atlas thumbnails,
  decorative backgrounds and compass imagery use it. Index construction requests no images.
- `OverlandMapGeometry` holds coordinate/calibration/clipping and aid measurement math.
  `OverlandMapDrawing` holds retained panel pools and cached layout helpers.
- Aids domain, layer and editor are separate runtime files. Canvas composition delegates
  pins, Party, camera, guides and artwork to retained owners. Artwork owns its image
  panels, borders and crossfade lifetime. Selection handles remain application-scaled;
  artwork/lettering/aids use image-scaled geometry and authored positions stay normalized.
- `OverlandMapGestures` owns Begin/Update/Commit/Cancel, release consumption and feature
  adapters. It rechecks access before completion and cancels on host defocus, resize,
  navigation, permission loss and destruction. A drag produces at most one operation.
- `OverlandMapCommands` represents acceptance separately from receipt settlement.
  UI writes consume named command results; the retained domain algorithms remain
  internal implementation functions. Import results preserve input order and individual
  receipts. Settings without Undo report document submission without a server receipt.
  Deletion and map removal use model-owned consequence plans in both confirmation and
  execution. Changed consequences require fresh confirmation. Mixed Party/log and
  deletion results retain failed suboperations; dependent failed batches do not offer
  successful-operation Undo. No timeout turns a pending receipt into confirmation.
  Moving a Location between maps and deleting a path also retain refused path,
  Location and Party submissions. Independent import rows retain partial Undo.
- Record reconciliation cancels unauthorized game-scoped work without discarding
  permitted drafts. UI continuations carry transition generations and permission
  guards: completed saves cannot reclaim focus after navigation or selection changes.
  Creation callbacks use receipt identities, including synchronous callbacks.
  Repeated field confirmation returns unchanged without another row revision; explicit
  Retry still resubmits failed optimistic values with their original Undo before-image.
- Viewer-filtered read models feed readers, Atlas, breadcrumbs and search. Permission
  reconciliation precedes cached signatures. Record, permission, camera, selection,
  asset, preference, queue, Party/log and layout work has scoped ownership; camera
  layout does not rebuild editors or Atlas. Full reconciliation remains available.
- Local row submission/receipt notifications have independently removable observers.
  Engine notifications without row identity reconcile the relevant record domain.
- The original 32 cloud file IDs and revision counts are unchanged; 17 new runtime
  files were registered and their order persisted. The bootstrap remains last.
- A clean restart verified all 49 deployed source checksums and an empty fresh Atlas
  after fixture cleanup. Old service globals are absent. Four bare historical record
  types remain exposed by the engine for retained data; the rewritten source neither
  registers nor uses them. Their GameType boilerplate is not a compatibility alias.

The complete file responsibility/order table is in the [README](../README.md).
The [live record](../tests/LIVE_REWRITE_2026-10-18.md) lists actual UI checks and limits.
The offline runner passes 185 checks across nine suites, preserving all 146 baseline checks.
The 38 lifetime and six canvas checks also passed inside the target Lua runtime with
isolated fake storage. Multi-client tests remain excluded. Physical input is assigned
to human testing; the [manual checklist](../tests/MANUAL_REWRITE_ACCEPTANCE.md) records it.

## Measurement procedure and adoption gates

`tests/PerformanceFixture.lua` builds deterministic data in an isolated transport:
250 pins, 150 paths, 50 labels, both aids, rectangular 4000x2000 artwork and a
1200x720 viewport. Normal paths have two bends/three segments; dense paths use all
32 supported bends. Fixture construction checks passed (about 0.9 s each offline).
These are fixture-construction costs, not rendering or frame-time results.

Rendering comparisons require a focused app, fixed viewport/settings, one warm-up and
five runs: cold open, warm redraw, short/long pan, fit-to-20x zoom, bend drag. Record
whole-frame p95 and median cold-open cost plus Lua work, panel/bind/style counts and
native resources. Display-capped measurements are inconclusive.

Native input was rejected: a left-button drag with `dragMove = false` had exactly one
release and no click; a right-button drag produced no native drag events. Central
polling is the fixed production adapter, without an old-runtime compatibility branch.

Shapes gates run in order: cleanup, visual, performance. Cleanup requires 1,000 geometry
replacements and 100 open/close cycles with native meshes/cameras/textures returning to
baseline and no progressive retained-memory growth. Missing mesh instrumentation or
unresolved disposal fails the gate. Historical assembly inspection found unresolved
path-mesh disposal; it is not proof of cleanup. No adoption claim has been made.
The scoped stroke/casing probe used one drawing surface. Cleanup is unverifiable with
available instrumentation, so the experiment stops at its first gate and production
retains the pooled renderer. Visual/performance gates were not used to justify adoption.
There is no renderer selector. A future experiment would still need dense median
p95 improvement >=15%, normal p95 regression <=5%, and cold-open regression <=10%.

## Remaining acceptance work

A pre-rewrite rendering baseline was not captured before extraction. Historical
measurements use different fixtures and cannot establish a before/after comparison.
The follow-up recovered and hash-verified all 40 tracked baseline Lua files from
HEAD and the saved working-tree patch. The original untracked `RegionMapAids.lua`
and `tests/MapAidsChecks.lua` remain unavailable. The user confirmed that no backup
is available and deferred resolving the comparative benchmark. Recovered files are
stored as `.lua.txt` under `output/overland-rewrite/recovered-baseline` so they do not
introduce old globals into repository type checking or runtime registration.
The isolated live renderer fixture excludes texture download and shell construction;
its construction timing is not end-to-end cold opening. Native mesh/camera disposal
counts are unavailable. These limits prevent a complete comparative performance claim.

The follow-up fixed Escape leaving the map during a pin drag, selected path handles
losing to overlapping pins/Party, the second double-click release reopening the
reader, and confirmation dialogs leaving a pointer preview active. All four fixes
were deployed and retested in the connected client. Added offline cases cover handle
priority, insertion, right-click removal and double-click release suppression.

Bridge-driven checks now cover locked movement, focus loss, navigation, tool changes,
View as player, target deletion, import/host guards, numeric label edits and a locally
injected presentation. The presentation flushed its original Location identity and
received its table receipt after navigation. Minimum-window layout was inspected at
80%/Void and 140%/High Contrast; reset placement retained the content and selection;
Reduce motion made Fit immediate and prevented idle control fading.

The user assigned the remaining physical keyboard/overlap/host matrix to manual human
testing. Virtual input cannot establish OS click thresholds, pointer capture beyond
the app window or native Submit behavior. Every theme/artwork combination and all
permission-change timing combinations have not been exercised live. Retained suites
cover their specified simulated cases; they do not substitute for unperformed cases.
Native-popout wheel routing remains the recorded engine limitation. Comparative
performance and manual acceptance remain open; this follow-up does not mark the
rewrite fully accepted. Two-client tests are excluded.

All development clients must use the rewritten version; mixed old/new sessions are
unsupported. Old development maps, Party state, logs and preferences remain untouched
and are not loaded. This task does not publish an installable package.
