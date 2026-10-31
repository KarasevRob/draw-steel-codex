# Lazy editors and the bordered-path experiment

The shell now builds Location, Path, Label, Party, Log and Import components on first
eligible use. A component stays attached to its original shell slot until that view
is destroyed. The bordered-path experiment was rejected at its first visual gate;
the production path renderer is unchanged by this work.

**Performance is accepted for this phase by the user (2026-10-19).** No further timing
runs are required for this phase. This acceptance leaves the recorded measurements
unchanged: several normal interaction/reopen results exceeded the original 5% threshold,
and the dense comparison was incomplete. The implementation is retained and deployed;
no release or publication was made. Native appearance and physical keyboard checks
remain separate human checks.

## Source and scope

The baseline is checkout `06b3888f06c339b227218e84b71b863cb14b14e3` plus the existing
dirty tree. All 49 runtime files were copied before editing to test-only `.source`
snapshots under `output/overland-lazy-2026-10-19/baseline`. The same directory retains
the tracked dirty-tree patch, status, normalized SHA-256/length/checksum manifests,
screenshots and raw measurements. Only `OverlandMapPanel.lua` and
`OverlandMapLabelPanel.lua` differ from those runtime snapshots.

No registered file, storage field, renderer selector, engine change or publication
was added. Existing path, host, editor and persistence implementations are retained.

## Ownership and binding

Six transparent, noninteractive slots preserve sibling order and inherit the shell's
theme. Import remains below the stop card and confirmation layer. The private registry
retains the factory and constructed panel; `Existing` never constructs, while `Ensure`
checks the view owner, prevents re-entry/retry after failure, and attaches synchronously.

Selection and permission reconciliation precede construction. Location requires a
valid selected Location in its read/edit/picker modes; Path requires a valid path or
permitted endpoint picker; Label requires an editable selected label; Party retains
its availability check. Log starts on its first opening. Import requires an explicit
action, current map, Director/add permission and no running import.

Existing components retain their change-domain binds, including outgoing closing
binds. These release record observers and artwork requests and save open Log notes.
Toolbar, Escape and close/transfer inspection use nullable existing components.
Destruction blocks new construction before flushing existing participants. The Label
format listener is installed during eager view setup and captures no panel.

Location's three save lanes, debounce, Retry and Undo baselines remain in their
existing services. Accepted saves belong to the game and can finish after view
destruction. Fullscreen/window mode changes retain slots; teardown/replacement creates
a new registry.

## Bordered primitive: rejected

The temporary `PathBorderProbe.lua` compared the existing two rounded surfaces with one bordered
surface, using the same rounded outer dimensions, center, angle, casing thickness,
stroke color and opacity. The matrix includes all three stroke widths, dots, lengths
0.5/2/10/90, effective scales 0.8/1/1.4, angles 0/30/75 and dark/light backgrounds.
The probe clips its canvas, as the production canvas does.

After the experiment closed, the unused probe was removed from the mod's test directory.
Its source remains in the local evidence archive as `PathBorderProbe.lua.source` alongside
the captures. Superseded type-check logs were removed; final diagnostics, baseline
snapshots, raw measurements and reusable regression/benchmark helpers were retained.

Twenty-seven captures provide a baseline, repeat baseline and candidate for each
scale/angle pair. Repeated baseline noise has a maximum channel delta of 2-3. The
bordered version reaches 95-140, with 1,152-2,601 pixels beyond the corresponding
noise ceiling. Differences affect the marks. The engine accepts fractional border
widths at its style setter; the cause of the raster difference was not established.

This fails the required appearance gate. Per the plan, descriptor generation,
collision indexing, pool conversion and path performance adoption were not attempted.
There is no claimed path-panel reduction or path speedup. Geometry, simplification,
hit testing, layer composition, draft lines and bend previews remain unchanged.

## Verification method

The initial 189 offline checks passed. `LazyPanelChecks.lua` adds 23 production-shell
checks with real record/session services and recording GUI/factory doubles. The full
runner now has 212 checks across ten suites. `LazyPanelLiveChecks.lua` adds eight
checks with real engine controls and isolated storage: three-lane accepted saves after
teardown, original targets, retained identity, Log save-on-close, Import discard/cancel,
blank label drafts, permission loss, Escape and host-mode retention.

The live helper fixes its Journal adapter: the model captured the original fixture
table before the live Journal module loaded. The adapter is now populated with the
live implementation. Pilot results with this fixture error are excluded. Live tests
find controls within their own subtree: engine `Panel:Get(id)` can resolve another
view's duplicate id and is unsuitable for these isolated tests.

Visual inspection covered 1200x720 and 720x480 viewports, Font Size 80/100/140, MCDM
and High Contrast, Location/Path/Label/Import and the status chip. Settings were restored.
Native mounting and guarded teardown were exercised; native-window appearance and
physical Tab/keyboard routing still require human verification. Bridge event dispatch
does not establish OS input delivery. No two-client tests were run.

ASCII and Lua 5.4.7 syntax checks passed for all 67 retained Overland runtime/test Lua
files after cleanup; the retired probe also passed before its removal. The 212 offline
checks passed again after cleanup.
The whole-repository LuaLS 3.19.2 check completed with nine diagnostics, all in the
existing `output/segmented-stamina` files and identical to the previous recorded
diagnostics. There were no Overland diagnostics. This is not a clean repository pass.
The unavailable private parent-checkout wrapper was not used. The direct command was:

```powershell
& "$env:TEMP/overland-luals-3.19.2/bin/lua-language-server.exe" --check . --configpath .luarc.json --checklevel=Warning --num_threads=4 --logpath 'output/overland-lazy-2026-10-19/luals-final-log' --check_format=json --check_out_path 'output/overland-lazy-2026-10-19/luals-final.json'
```

The supported CodeMod API does not expose the exact text currently executed by Lua.
`localContents` is a local-change cache (nil for unchanged files); revision hashes
identify stored revisions. Neither is a loaded-runtime hash. The benchmark loads the
captured source variants directly in isolated environments; deployment verification
must distinguish disk/source hashes and reload status from an unavailable runtime-text
hash. Earlier reports' CodeMod-cache comparisons should not be read as that proof.

## Measured results and decision

The completed comparison used one warm-up and five measured runs per variant, in
baseline-then-lazy order, with 1200x720 viewport, Font Size 100 and MCDM. LuaLS was
finished before timing began. Both normal batches completed all engine interaction
coverage checks. The external monitor recorded Codex and its Windows Ghost window
during rendering stalls; the first other application appeared at 23:33:09 UTC, after
both normal batches had finished at 23:31:50 UTC. The dense warm-up subsequently lost
focus and was cancelled; it supplies no accepted timing result.

| Normal fixture | Baseline | Lazy |
| --- | ---: | ---: |
| Median production shell construction | 314 ms | 53 ms |
| Median harness image/layout readiness | 10,125 ms | 11,438 ms |
| Panels at opening | 4,779 | 4,232 |
| Heavy component factory calls at opening | 6 | 0 |
| Allocated path panels at Fit | 2,457 | 2,457 |
| Active path panels at Fit | 2,453 | 2,453 |
| Peak allocated path panels through interactions | 4,590 | 4,590 |
| Engine live panels after each view's destruction, including the test stage | 6,462 | 6,462 |

The constructor median decreased by 83.1%. The 547-panel opening reduction is exactly
553 deferred component panels minus six host slots. All six factories ran exactly once
when eventually used, and reopening retained the panel identities. The process returned
to 6,461 live panels after the final stage was removed. Rendering and editor opening
produced no fixture persistence writes.

These are uncapped whole-frame p95 values pooled across the five runs. Lua values are
the median of each run's mean synchronous work. Engine summaries and every individual
wall-clock interval remain in the raw files; capped engine percentiles are not used
to quantify long stalls.

| Normal interaction | Baseline p95 | Lazy p95 | Baseline / lazy Lua work |
| --- | ---: | ---: | ---: |
| Idle | 42 ms | 37 ms | 0 / 0 ms |
| Records refresh | 43 ms | 44 ms | 1 / 1 ms |
| Short pan | 44 ms | 43 ms | 0 / 0 ms |
| Long pan | 43 ms | 36 ms | 0 / 0 ms |
| Moving zoom | 152 ms | 160 ms | 4.99 / 5.28 ms |
| Settled zoom | 5,818 ms | 7,035 ms | 26.79 / 26.17 ms |
| Bend preview | 64 ms | 51 ms | 0.083 / 0.067 ms |

Deferred work remains visible on first use. Times below are medians; readiness is the
five-frame observation interval after opening, not a promise of latency on other maps.
Factory subtree counts are taken immediately after construction, before populated
rows are added by binding.

| Editor | Lazy factory cost | Factory panels | First open synchronous, baseline / lazy | First open readiness, baseline / lazy |
| --- | ---: | ---: | ---: | ---: |
| Location | 45 ms | 174 | 4 / 59 ms | 294 / 558 ms |
| Path | 35 ms | 107 | 17 / 59 ms | 465 / 663 ms |
| Label | 104 ms | 157 | 8 / 135 ms | 401 / 650 ms |
| Party | 4 ms | 14 | 5 / 15 ms | 269 / 295 ms |
| Log | 3 ms | 14 | 10 / 23 ms | 267 / 332 ms |
| Import | 25 ms | 87 | 2 / 46 ms | 502 / 513 ms |

| Reopening editor | Readiness median, baseline / lazy | Whole-frame p95, baseline / lazy |
| --- | ---: | ---: |
| Location | 314 / 283 ms | 82 / 91 ms |
| Path | 321 / 367 ms | 96 / 124 ms |
| Label | 349 / 367 ms | 92 / 101 ms |
| Party | 268 / 238 ms | 84 / 82 ms |
| Log | 283 / 221 ms | 78 / 69 ms |
| Import | 304 / 318 ms | 95 / 88 ms |

Moving zoom p95 increased 5.3%, settled zoom 20.9%, and three editor reopen p95 values
also exceeded the allowed regression. Readiness and settled-zoom costs increased over
successive runs, while their Lua work and path counts remained similar. This raises a
time-order/environment hypothesis, but it does not establish that cause or excuse the
observed regression. A balanced or reversed comparison would be needed to establish the
cause in a later investigation; it is outside the accepted phase. No speculative
production change was made to explain these measurements.

The dense lazy warm-up reached 10,581 active/allocated path panels and 13,316 total
panels, but it was interrupted during settled zoom before any measured run completed.
There is no baseline-dense comparison, and the original numerical gates were not
demonstrated. The user's subsequent acceptance closes performance work for this phase.
Physical keyboard/Tab routing and native appearance remain named human checks. The
path-only and combined timing variants were not run because the primitive had already
failed the plan's stop gate.

[Machine-readable results](LAZY_EDITORS_2026-10-19.json) contain the per-run summaries,
source manifests, resource counts and acceptance status. Raw normal batches, the
rejected dense partial run, external focus trace and screenshot comparisons are retained
under `output/overland-lazy-2026-10-19`.

## Deployment verification

All 49 Overland runtime files were passed together to `deploy.ps1`: 44 were copied and
five were already current. All 49 deployed normalized SHA-256 hashes match the candidate
manifest. The latest 49 Overland `MOD:: READ CONTENTS FOR MOD` lines name those dev-folder
files, and the bridge reports `allModsLoaded=true`, `filesChanged=false` after reload.
A probe of the deployed `OverlandMapPanel.Create` invoked none of the six heavy factories
and destroyed its temporary panel immediately. No Overland exception was observed;
unrelated `VIDEO CLOCK RESYNC` messages remained in the console.

These checks establish deployed source equality, read paths, reload completion and the
new constructor behavior. They do not supply the unavailable exact loaded-source text
hash. The benchmark helper and stages were released, the earlier settings restored,
and no timing session remains running.

## Reproduction

`LazyPanelBenchmark.lua` uses the existing normal/dense `PerformanceFixture` records
and the full production shell. Pass `baseline` as the absolute snapshot directory for
the eager variant; omit it for the lazy variant. The two changed runtime files are
reloaded from the snapshot for baseline runs; all other runtime files match the captured
baseline. Always verify both manifests before comparing.

The benchmark records construction, image/layout readiness, engine summaries, uncapped
wall-clock frame intervals, Lua work, factory calls/subtree sizes, path counts and
post-destruction panel counts. Its interaction sequence is idle (60 frames), refresh
(30), short/long pan (60 each), moving zoom Fit-20x-Fit (60 plus 12 settling frames),
four settled zoom jumps (2x/5x/20x/Fit, six frames apart) and bend preview (60). These
are matched within this comparison, not identical to the longer October 19 historical
benchmark. First-use and repeat-open editor timings follow the interactions when enabled.

The readiness interval includes isolated fixture/module preparation as well as image
and layout completion. It is a matched harness measurement, not a direct estimate of
the user's map-opening time. The separate construction timer covers the production
shell constructor and attachment only. Editor readiness covers five frames after the
open action; synchronous and factory costs are also reported separately.

Use one warm-up and five measured runs, fixed 1200x720 viewport, Font Size 100 and MCDM.
Run `MonitorPerformanceFocus.ps1` for the entire batch. Reject incomplete focused-frame
coverage, retain failed runs, and keep LuaLS outside all measured sessions. Engine
percentiles cap at 2,000 ms and omit frames at least 10 seconds long; use the uncapped
intervals for those stalls. The remaining game is present and its cost is not subtracted.
