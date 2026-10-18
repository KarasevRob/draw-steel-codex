# Overland rewrite verification, 2026-10-18

Target: Draw Steel Codex build 10, version 0.0.857, one Director client.
CodeMod `ec447c62-03db-4416-a5a2-0b013c0f3893`; checks used the local developer deployment.
Publication was subsequently authorized and is recorded below. Two-client tests were
excluded by request. This record does not claim server-side transactions or
player-client behavior.

## Automated checks

- The original 146 checks remain in eight suites. `LifetimeChecks.lua` adds 38,
  and CanvasTools adds one continuation regression, for 185 passing checks across nine suites.
- New cases cover fresh identities/sidecars; detachable observers; the three Location
  lanes finishing after closure; immutable Retry and original Undo baselines; busy,
  failed and uncertain receipts; duplicate callbacks; game and owner replacement;
  image timeout/late success/cancellation; gesture release consumption; revoked
  gestures; changed deletion consequences; resize transitions; invalid draft withdrawal;
  note permissions; partial deletion and mixed Party/log results; map-move and path-delete
  partial failures; synchronous creation identities; ordered import results; UI continuation
  invalidation; record reconciliation; and no-op outcomes.
- All 38 lifetime and six canvas checks also passed inside the connected app's Lua
  runtime, using fake storage and panel fixtures. `acceptance-live-isolated.json`
  records the follow-up run; it does not exercise physical pointer delivery.
- ASCII and Lua syntax checks passed for all 63 runtime/test Lua files.
- Full-repository LuaLS 3.19.1 and the CI-matching 3.19.2 both reported nine
  pre-existing diagnostics and none in Overland Map.
  The existing diagnostics concern `output/segmented-stamina` (eight) and
  `tests/ai_minion_critical_test.lua` (one).
- The private parent checker and overload generator are unavailable. The user confirmed
  they are not recoverable from this checkout or machine. Use the documented direct
  whole-repository LuaLS command. The overload blocks contain no old module references;
  no literal `X.tableName = "..."` registration was added or renamed by this rewrite.

## Connected-app results

| Check | Result |
|---|---|
| Fresh application process | New namespaces loaded; `RegionMapModel` absent; 49 files registered, bootstrap last |
| Map image, paths, pins, label and aids | Rendered together after restart and reload |
| Location rename on editor closure | Queued name saved with a confirmed table receipt |
| Fullscreen/window switch during text editing | Same content object, focus object and draft text retained |
| Native popout and return | Eligible edit flushed; old host released; one active host; same map restored |
| Minimum in-app window at Font Size 140% | Toolbar, breadcrumbs, controls and map remained visible in 720x480 logical host |
| Font Size 80/100/140% | In-app map inspected; original 100% setting restored |
| Scale bar direct drag, editor closed | One map revision; distance unchanged; Undo restored its anchor |
| Compass direct drag, editor closed | One map revision; persisted normalized position |
| Compass resize and rotation handles | One revision each; width changed from 0.06 to 0.110260; rotation to 49.793869 degrees |
| Missing default compass image | Hidden with its reference retained; custom readable image loaded |
| Map aids None backgrounds | Existing artwork/text remained legible and geometry retained |
| Party placement and travel | Party snapped to start pin, travelled the path and recorded a log row |
| Mixed travel status | Party step reported submitted while log table receipt was pending |
| Travel Undo | After the log receipt settled, Party returned to the original pin and the travel log row was hidden |
| Log note on editor closure | Typed note saved with a confirmed table receipt after closing the log panel |
| View as player toolbar | Unshared map, breadcrumb and label disappeared; viewer Atlas was empty |
| Import parser/editor | Real parser and GUI checks passed, including ASCII/Cyrillic/emoji limits and explicit discard |
| Large import draft | 100,000-character replacement confirmation and oversized-input rejection passed |
| Import test writes | None; editor suite ended with an empty, closed draft |
| Final command/continuation check | Atlas image choice opened the created map; pin creation opened its editor using the confirmed receipt identity |
| Ordinary asset notification | Reconciles permissions without invalidating an authorized continuation |
| High contrast and My Little Pony schemes | Map, toolbar and Location editor inspected; MCDM restored |
| Keyboard typing and Escape | Typed Location name persisted; Escape cancelled Ruler before leaving edit mode on the next Escape |
| Tab probe | Follow-up confirmed Name -> Description -> Director notes through bridge virtual input; physical traversal remains manual |

The initial extracted canvas omitted path/guide panels from its first child tree; the
engine destroyed those unattached panels before artwork loaded. Retaining every layer
from construction fixed this. The first owner in a newly entered game also captured its
generation too early; creation now captures the current generation first, with an
offline regression. Local table writes now notify removable view observers directly,
because engine asset notifications did not reliably refresh the writing client.

## Native adoption decisions

Native dragging with `dragMove = false` produced one begin, 25 drag updates, one release
and zero clicks for a left-button drag; the panel position stayed fixed. The same
right-button gesture produced no drag events. This fails the supported-button gate.
Production uses one centralized polling controller. The remaining native-input matrix
was not run after that essential failure.

`groupOpacity` and `boxShadow` are rejected by this runtime as unknown style properties.
The engine logs these rejections without throwing. Existing opacity/shadow composition
is retained; there is no old-runtime support branch.

`NativePathExperiment.lua` submitted stroke and casing to one shared Shapes surface,
removed both shapes and destroyed the surface. This establishes API submission only.
Available diagnostics expose panel/Lua counts and render textures, not the required
native mesh/camera lifecycle counts. Historical assembly inspection also leaves path
mesh disposal unresolved. The cleanup gate therefore fails as unverifiable. The
1,000-replacement/100-cycle, visual and comparative performance gates were not claimed
or used to justify adoption. Production keeps the pooled backend, with no selector.

## Performance scope

`PerformanceFixture.lua` builds 250 pins, 150 paths, 50 labels and both aids in a fake
transport. Normal paths have three segments; dense paths have the supported maximum
32 bends. `LiveRendererFixture.lua` renders that data through the actual engine GUI
at a logical 1200x720 viewport and 4000x2000 image geometry, without game-table writes.

Its runner performs a warm-up and five runs covering unchanged binds, short/long pans,
Fit-to-20x zoom and bend previews. It records focused whole-frame timing, Lua stopwatch
cost, renderer construction cost and live panel counts. Construction excludes texture
download and shell creation, so it is not the plan's end-to-end cold-open metric.

A pre-rewrite rendering baseline was not captured. The older README timings are
historical and use different fixtures. Current observations cannot establish a
before/after improvement or satisfy the comparative renderer performance gate.

Five focused runs after one warm-up, Font Size 100%, MCDM theme, 60 Hz/VSync 1:

| Fixture | Median whole-frame p95 | Median Lua p95 | Median renderer construction | Live panels at end of each run |
|---|---:|---:|---:|---:|
| Normal | 102.5 ms | 7 ms | 725 ms | 9,524 in all five runs |
| Dense | 177.5 ms | 20 ms | 2,073 ms | 18,702 in all five runs |

These high frame costs are observations, not a passing performance result. The frame
window includes construction-frame effects and the rest of the active game. Native
mesh/resource stability is not established by stable panel counts. The first focus
probe collected zero focused frames and was discarded; measurements began only after
activating the game window. Raw runs are in `output/overland-rewrite/renderer-observations.json`.

## Limits and cleanup

The supplied baseline suites retain coverage for geometry, typography, visibility,
attachments, search, import batches and host behavior. They are not evidence that every
physical keyboard/overlap/window interaction was exercised on the rewritten UI.
Native-popout wheel routing remains an engine limitation. No engine changes were made.

The test map and its pins/path/label/logs were created only in the new Overland stores.
Cleanup is restricted to those exact fixture identities. Historical storage metadata is
compared with the captured baseline; no legacy data is migrated or changed. Cloud
file names and ordering are persisted, with original file IDs/history retained.
The publication step is separate from this developer-checkout verification.

Cleanup removed exactly seven temporary rows (three Locations, one path, one label and
two log rows), the test Party and the new test camera/host preferences. All six new
tables then contained zero rows. Font Size was restored to 100%. All six old-store
ID/revision/mutation/hidden snapshots matched the initial baseline exactly.

After the final application restart, all 49 registered files matched the repository's
normalized source checksums and their persisted order ended in `OverlandMap`.
`RegionMapModel` and the old service implementation were absent. The engine still
exposes four bare historical record types (`RegionMapLocationRecord`, its two sidecar
types, and `RegionMapMapLabelRecord`), containing only GameType boilerplate. These
correspond to retained old data, not compatibility aliases installed by the rewrite;
none of the 49 current source files references them. They were left untouched.
All new-store fixture rows remained absent, Party was
unset, and the fresh Atlas opened. No Overland errors were present in that process's
console. The original CodeMod ID and original file revision histories remain intact.

The final persistence review added explicit partial-result accounting for map moves
and path deletion. A refused dependent write cannot enable successful-operation Undo;
independent imported rows can still undo their confirmed subset. Ordinary asset
notifications previously invalidated every UI continuation and could cancel permitted
label drafts. Permission reconciliation now preserves authorized work and permanently
invalidates a continuation after its permission check fails.

After the final command and reconciliation changes, the module was hot-reloaded and
the creation/asset-notification checks above were repeated. Four additional temporary
Locations (one map and three pins) and any associated sidecars were removed by exact
identity. All six new tables were empty again, Party remained unset, the new last-map
preference was cleared, and the MCDM scheme was restored. The earlier clean restart
establishes registration persistence; the final reload verifies the later source edits.

Field confirmation had also repeated unchanged Location/path uploads. Those domain
updates now discard unchanged normalized fields while preserving explicit Retry.
The regression verifies no extra revision, successful Retry and restoration of the
original Undo before-image. The full offline runner remains green after this fix.

Final whole-repository LuaLS 3.19.2 (`output/overland-rewrite/final-acceptance-luals.json`)
reported exactly the same nine diagnostics as the initial baseline, with none in
Overland Map. All 49 deployed file checksums, IDs and order matched the final sources
after reload (`final-reload-verified.json`). The original 32 file revision counts
were unchanged. All six old-store metadata snapshots still matched, and the final
isolated runtime checks left the fresh stores empty.

## Single-client acceptance follow-up

The user excluded multi-client tests, assigned physical input to manual human testing,
and deferred resolving the missing performance baseline. These are explicit open items,
not passing acceptance results. The [manual checklist](MANUAL_REWRITE_ACCEPTANCE.md)
contains the physical-input handoff.

Four reproduced interaction failures were fixed and deployed:

| Failure | Change and retest |
|---|---|
| Escape during a pin drag also navigated to Atlas | Escape now recognizes every active gesture; the preview cancels with the same map and unchanged revision |
| A selected bend beneath a pin moved the pin | Central handle arbitration runs before pin/Party gestures; bend drag and right-click removal each changed the path once, leaving the pin unchanged; Undo restored the bend |
| Double-click opened the editor, then its second release reopened the reader | The handled double-click consumes that release; the next independent single click still opens the reader |
| A confirmation opened during a drag but release still moved the pin behind it | Confirmation enters the dialog transition, flushing valid fields and cancelling the pointer preview; release left the revision unchanged |

The gesture regressions also cover an insertion handle beneath Party and right-click
bend removal beneath a pin. There are now 38 lifetime checks and 185 total offline
checks. Escape and modal cancellation were exercised in the real connected UI.

Additional production UI checks passed using the bridge's virtual input or explicit
single-client lifecycle transitions:

- Locked pin movement made no write. Focus loss, map navigation, tool changes and
  View as player cancelled active previews without writing or retargeting them.
- Deleting a dragged target kept it deleted; release did not resurrect or move it.
- Fullscreen/window switching retained the content tree and unfinished path. Import
  text survived resizing; attempting native transfer opened the discard guard;
  Escape retained the draft, and explicit Discard closed it without importing rows.
- A locally injected presentation used the production receiver with the real view
  context. It flushed a Location name against its original ID, navigated while the
  table receipt was pending, then received confirmation. The fullscreen host and
  content object were retained. No shared presentation was broadcast.
- Numeric label rotation saved 45 degrees. A non-finite size was rejected without
  a new revision; restoring its unchanged valid value made no extra write.
- The minimum 720x480 logical window was inspected with 80%/Void and 140%/High Contrast.
  Reset placement retained content and selection. Reduce motion made Fit immediate
  and kept idle camera controls from fading. Font 100%, MCDM and the original window
  geometry were restored afterward.

`gui.GetFocus()` can retain an old Lua-side focus reference after engine Tab navigation;
the successful follow-up checked each panel's `hasFocus`. The bridge defaults to
virtual input. Virtual down/up does not itself emit a click, and virtual Enter/Space
does not establish the main-window Unity Submit path. An OS-input attempt was refused
because `SetForegroundWindow` did not activate the game. The user subsequently
assigned these checks to manual testing. No workaround was added to production.
Installed-assembly inspection also shows native-window focus handling returns before
the main-window Tab/Submit logic; this is evidence for a manual check, not a verified
native keyboard pass. Native-popout wheel delivery remains the existing engine issue.

The panel file briefly remained cached after deployment followed immediately by a
bridge reload. Its deployed contents were correct but its loaded callback was old.
Allowing the local file watcher to process the change loaded the new callback; the
modal test then passed. Verification compared all 49 loaded normalized checksums,
IDs, revision counts and ordering with the repository and baseline. The original
32 file IDs/history are intact and the bootstrap is last.

Baseline recovery reconstructed and SHA-256-verified 40 tracked Lua files (31 runtime
files and nine test/helpers) from HEAD plus the captured patch. The original untracked
`RegionMapAids.lua` and `tests/MapAidsChecks.lua` were not recoverable. The user confirmed
no backup is available and deferred a solution. The recovered copies use `.lua.txt`
extensions to avoid loading old globals. No comparative performance pass is claimed;
end-to-end cold opening and the required resource measurements remain open with it.
The rejected Shapes experiment remains closed at its cleanup gate.

Final follow-up validation:

- ASCII and Lua syntax passed for all 63 runtime/test Lua files.
- All 185 offline checks passed; 38 lifetime and six canvas checks passed again in
  the target app with isolated storage.
- Whole-repository LuaLS 3.19.2 reported the same nine baseline diagnostics, zero
  Overland diagnostics (`acceptance-final-luals.json`).
- All ten follow-up fixture rows were removed by exact identity (eight Locations,
  one path, one label). No sidecars or log rows required removal. All six fresh
  tables were empty after reload; Party remained unset and fixture Undo was cleared.
- Old-store ID/revision/mutation/hidden snapshots still matched the baseline across
  all six tables. Original artwork was untouched. The app was left at the fresh Atlas.

Raw follow-up evidence is under `output/overland-rewrite`: `acceptance-single-client.json`,
`acceptance-live-isolated.json`, `acceptance-reload-verified.json`,
`acceptance-old-storage.json`, `acceptance-cleanup.json`, `acceptance-final-offline.txt`
and `recovered-baseline.json`. Nothing had been published at the end of that follow-up.
Full acceptance remains open for the deferred benchmark and manual checks.

## Publication

The user explicitly authorized commit, push and publication after the acceptance
follow-up. On 2026-10-18:

- Implementation commit `6fea99a43dbe6efb381eefb22a98930571ed2cd8` was pushed to
  `origin/region-map-v2` in `KarasevRob/draw-steel-codex`.
- CodeMod `ec447c62-03db-4416-a5a2-0b013c0f3893` was published through the supported
  `CodeModLua:CommitChanges` workflow.
- Changelist: `62412c6a-1e8f-4726-855a-a39929537786`; required engine version: `0.0.857`.
- The completion callback reported success. All 49 registered files received a new
  revision, preserving their file IDs, previous history and dependency order.
  Every published revision body fetched through `code.GetCodeFromMD5` matched the
  repository's normalized source checksum. `hasLocalChanges` was false afterward.
- The wrapper still exposed an unresolved timestamp sentinel, so this record does
  not assert an exact server timestamp. The successful completion callback and all
  published source bodies are recorded in `output/overland-rewrite/publication-verified.json`.
- Seven extra blank lines at EOF were removed before committing; there was no logic
  change. Syntax and staged whitespace checks passed and all 185 offline checks passed
  again. The existing whole-repository LuaLS result remains nine baseline diagnostics,
  none in Overland Map. GitHub Actions status could not be retrieved because the
  GitHub API returned its rate-limit response; no CI pass is claimed.

The release note states the fresh-storage cutover with no migration, retained-layer
architecture, interaction fixes, 185 offline checks and the deferred physical-input
and comparative-performance work. Publication does not mark those acceptance items
complete. The development checkout remains open. Unrelated working-tree changes and
raw local scratch/evidence files were not included in the Git commit.

## User manual acceptance, 2026-10-19

After publication and the simple nine-step single-client checklist, the user reported:
"All tests good." This is recorded as a user-reported manual pass. The supplied steps
covered a temporary point-crawl map, pin drag/Undo, Escape cancellation, double-click
editing, an overlapping path bend, saving a name during navigation, host switching,
keyboard controls and Font Size 80/100/140%.

No per-item trace for the extended checklist or new automated run was supplied.
The confirmation does not establish a fix for previously documented engine limitations.
Multi-client tests remain excluded and comparative performance remains deferred.
This update changes documentation only; the published runtime is unchanged.
