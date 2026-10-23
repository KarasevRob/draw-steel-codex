# Overland Map performance, 2026-10-19

The current development version was measured on one client. Normal-map panning had
a median per-run p95 of 37 ms; dense-map panning was about 103 ms. Cached full-content
opening took about 7.4 seconds for normal and 22-24 seconds for dense. Large settled
zoom changes produced multi-second stalls. These are performance problems worth
investigating, not a passing comparative acceptance result.

[Raw measurements and source hashes](PERFORMANCE_2026-10-19.json) accompany this record.
The older implementation was not run: its original untracked `RegionMapAids.lua`
remains unavailable. Historical observations below do not establish a rewrite regression.

## Environment and source identity

- Codex 0.0.857, bridge build 10, Director, one connected client.
- AMD Ryzen 9 5900HX, 8 cores / 16 threads, 32 GB RAM; NVIDIA RTX 3060 Laptop GPU,
  driver 32.0.16.1742. An integrated AMD GPU is also installed; GPU utilization was not profiled.
- 2560x1600 display at 60 Hz, VSync 1, targetFrameRate -1; Font Size 100%, MCDM theme.
- Fixed 1200x720 logical fixture viewport and 4000x2000 image geometry.
- Checkout HEAD `1c119e78815ee0a819e1706582191bc0b7a15e61`, plus the existing local
  runtime edits. This is the development checkout, not a claim about unchanged
  published release bits. All 49 loaded runtime files matched the normalized repository
  length/checksum before and after timing. SHA-256 identities are in the JSON.
- The original map was collapsed during measurement; the rest of the running game
  remained present. The empty benchmark stage measured 27.0-27.9 ms mean frame time
  and 34.4-35.4 ms p95 before the feature/main batches. That is already slower than
  the historical 16.6 ms display cap. Background app work was not isolated or subtracted.
- No LuaLS, offline suite, deployment, publication or other deliberate heavy job ran
  during the timing windows. The console also contained engine video-clock resync
  messages; no CPU/GPU attribution is inferred from them.

## Workload and timing definitions

`PerformanceFixture.lua` creates deterministic records entirely in a fake transport:
250 named pins, 150 paths cycling the five styles, 50 labels with None backgrounds,
a compass and a calibrated scale bar. Normal paths have two bends / three segments;
dense paths have the supported maximum 32 bends / 33 segments. Hidden records remain
visible to the Director. Names are enabled. No benchmark rows are uploaded to the game.

`LivePerformanceBenchmark.lua` uses the actual production layer modules and engine GUI.
Pin-only and path-only cases mask the other rendered components; path endpoints remain
in the isolated model. Interactions call the layer APIs, so they measure rendering and
preview layout, not physical pointer delivery or the complete gesture controller.

Each interaction case has one unreported warm-up and five measured runs. A fresh
renderer is constructed per run, followed by readiness and 30 settling frames. Every
phase ends one frame after its final action so deferred engine work is counted.

| Phase | Work per run |
|---|---|
| Idle | 120 frames, no layout action |
| Unchanged bind | 60 identical Bind/Layout calls |
| Short pan | 120 position updates, horizontal center oscillating by 0.03 |
| Long pan | 120 position updates, horizontal center 0.1 to 0.9 |
| Animated zoom | Fit to 20x and back over 120 updates, then 12 settling updates |
| Settled zoom stress | 12 jumps: 2x, 5x, 20x, Fit, repeated three times, ten frames apart |
| Bend preview | 120 updates to the first path's first bend, u=0.4 to 0.7, v=0.4 |

The settled-zoom phase is intentionally severe. It does not represent four ordinary
wheel notches. It was added after the feature-only cases, which have no settled-zoom
result. Camera motion must not be interpreted as a persistence benchmark.

Renderer construction is synchronous Lua construction plus the initial Bind/Layout.
It excludes deferred engine layout, map texture loading and shell controls.
Full-content opening instead constructs the real `OverlandMapPanel` inside an existing
host, including its toolbar/editors and cached artwork. Its wall stopwatch ends two
engine frames after artwork, canvas geometry and compass report ready. This includes
deferred work but excludes network download, application start and host/OS-window
creation. It is not a GPU first-visible-pixel measurement or fully cold cache test.

## Current results

Frame values are **medians of five per-run p95 values**, not a percentile pooled across
all runs. Lower is better. The p95 describes the slower end of the frame distribution.

| Whole-frame p95, ms | 250 pins only | 150 paths only | Normal full fixture | Dense full fixture |
|---|---:|---:|---:|---:|
| Idle | 35.9 | 36.6 | 36.4 | 107.5 |
| Unchanged bind | 36.1 | 41.4 | 37.6 | 102.5 |
| Short pan | 35.6 | 39.6 | 37.1 | 102.5 |
| Long pan | 36.1 | 41.1 | 37.4 | 102.5 |
| Animated zoom | 39.1 | 36.6 | 95.1 | 192.5 |
| Settled zoom stress | Not measured | Not measured | 1,397.5 | **At least 2,000** |
| Bend preview | Not applicable | 42.1 | 44.6 | 122.5 |

| Construction/readiness, ms | 250 pins only | 150 paths only | Normal | Dense |
|---|---:|---:|---:|---:|
| Median synchronous renderer construction | 265 | 400 | 709 | 2,369 |
| Median renderer readiness, including deferred work | 1,061 | 2,137 | 4,525 | 22,056 |
| Median full-content opening | Not measured | Not measured | 7,409 | 22,315 (qualified below) |

Normal opening samples: **7,774 / 7,276 / 7,473 / 7,409 / 7,401 ms**.
Dense retained opening samples: **21,936 / 22,109 / 22,596 / 22,315 / 23,785 ms**.
Dense opening spans three batches (2+2+1 retained samples), each with a warm-up.
Two additional attempts lost their record because the initial coverage guard aborted
them. That guard was corrected after discovering the timer limits below. The dense
opening summary is therefore observational; it is not an unbiased five-consecutive-run
acceptance gate. A separate diagnostic opening took 23,370 ms and is excluded from
the five-sample summary.

Normal and dense renderer readiness increased through their sequential runs:
3,717 to 5,282 ms and 20,315 to 24,023 ms respectively. Live panel counts returned to
baseline each time. This trend warrants investigation; it does not, by itself, prove
a memory leak or identify its cause.

Lua stopwatch p95 was below its 1 ms resolution for normal/dense pan, 8/27 ms for
animated zoom, and below 1 / 1 ms for bend preview. For the 12 settled-zoom calls,
median per-run Lua p50 was 31/89 ms and p95 was 208/308 ms. Whole-frame costs are much
larger: the worst observed settled-zoom frames were **2,555 ms normal and 9,296 ms
dense**. These gaps include deferred engine work and the rest of the game; this test
does not distinguish native CPU work, GPU work, scheduling or other causes.

## Engine timer limits and foreground evidence

Read-only inspection of the installed `Assembly-CSharp.dll` established that:

- `PerfManager.RecordPerfWindowFrame` ignores durations of 10,000 ms or more.
- `PerfWindowBucketMidMs` caps the histogram at 2,000 ms. Saturated p95/p99 values
  must be reported as lower bounds; `maxMs` is uncapped for frames under 10 seconds.
- Recording also depends on current/previous application focus. `focusedSeconds`
  excludes discarded long frames, so it is not an independent focus-duration measure.

All recorded feature, normal and dense **interaction** phases counted every engine
frame between their boundaries. None has an omitted >=10-second frame. Dense settled
zoom reached the percentile cap in all five runs, so its exact p95 is unknown.

Opening commonly crossed three engine frames, of which only one or two appeared in
the histogram. The original helper incorrectly called that missing coverage "focus
loss" and triggered unnecessary foreground requests. Opening now retains its wall
time and missing-frame count; interrupted records are also retained on failure.
Opening histogram means and percentiles are not valid opening-cost estimates.

An independent Windows monitor polled the foreground window every 200 ms during the
last warm-up/sample pair. It saw Codex and `dwm`, without another application. A bounded
follow-up confirmed the `dwm` window had class **Ghost** and title **Codex (Not responding)**,
then returned to Codex. The follow-up saw that window for about 18 seconds. This
supports an actual unresponsive opening, not a user switching away. It does not
recover the discarded native frame durations or prove uninterrupted Unity focus.

## Historical comparison

| Earlier observation | Current observation | What can be concluded |
|---|---|---|
| Oct 7: 250 pins, first draw 221 ms | Pin-only synchronous construction 265 ms | Numerically higher; pin composition and timing boundaries differ |
| Oct 7: 250 pins, pan 16.6 ms/frame at 60 Hz cap | Pin-only short/long-pan mean 29.77/29.76 ms; p95 35.6/36.1 ms | Current game is slower, including its empty-stage baseline; not attributable to the rewrite from these runs |
| Oct 10: 150 paths, first draw 123 ms, 1,401 pieces | Path-only construction 400 ms; current normal geometry has 2,453 visible pieces | More geometry and different rendering composition; not an equal-workload ratio |
| Oct 10: zoom layout 23-34 ms plus pool growth | Path-only animated-zoom Lua p95 3 ms, whole-frame p95 36.6 ms | Different moving/settled work and statistics; no improvement percentage is valid |
| Oct 13: 33 pins, about 760 path pieces and 600 route dots, pan 16.7 ms/frame | Normal full-fixture pan mean about 33.6 ms | Current fixture has 250 pins, 2,453 path pieces, 50 labels and aids, without route dots; incomparable workload |
| Oct 18: normal/dense construction 725/2,073 ms | 709/2,369 ms | Similar fixture construction: -2.2% normal, +14.3% dense observed, with different session/source context |
| Oct 18: normal/dense mixed-window frame p95 102.5/177.5 ms | Separate phases shown above | Old window mixed opening and interaction work; it cannot be directly compared to any new phase p95 |

Historical sources: [README performance record](../README.md#5-performance) and
[October 18 live record](LIVE_REWRITE_2026-10-18.md#performance-scope).
No matching pre-rewrite benchmark exists. The historical construction differences
do not establish a causal regression or satisfy the native renderer adoption gates.
The pooled renderer remains selected; the Shapes experiment stays closed at its
unverifiable cleanup gate.

## Cleanup and validation

At Fit, the renderer trees contained 4,094/13,182 panels and 2,453/10,581 path pieces
for normal/dense. Panning and unchanged binds retained their panel counts. Settled
zoom grew the reusable pools. After every retained run, total live panels returned
to 6,462, including the benchmark stage; after removing that stage and restoring the
original map they returned to **6,461 live / 1,383 active**, the original values.
This is panel cleanup evidence, not native mesh/texture disposal or memory stability.

The original view, focus, Font Size 100% and MCDM theme were restored. Captured
preferences and ID/revision/hidden metadata in six Overland and six historical
Region tables were unchanged. The snapshot did not include a complete shared-state
document or every row field. Fixtures used only fake storage; measured full-fixture
runs made no additional fake-transport writes. Temporary benchmark globals were
released, and no benchmark content required deletion from live game tables.

All **189 checks** across nine offline suites passed. ASCII and Lua syntax passed
for all **64** Overland runtime/test Lua files. The image preparation helper reproduced
the same PNG SHA-256, and the foreground monitor passed PowerShell parsing.
Whole-repository LuaLS **3.19.2** completed with **zero Overland diagnostics** and
**nine existing diagnostics** in `output/segmented-stamina`. Its final JSON matches
`acceptance-final-luals.json` exactly after sorting diagnostic arrays. The command
exited 1 because those baseline diagnostics remain; this is not a clean repository
type-check pass. Final output is `luals-verified.json` in the local evidence directory.
The private parent checker remains unavailable; the direct whole-repository command
from `TYPING.md` was used, with four workers and `--checklevel=Warning`.

No production Lua changes, deployment, publication or multi-client tests were part of
this measurement task. Full comparative acceptance remains open. The next performance
investigation should focus on deferred opening work and settled zoom, while controlling
the rest of the game's frame cost and the increasing readiness time across repeats.

## Reproducing the measurements

These helpers are test files, not registered CodeMod files. Run from the repository:

```powershell
python 'Overland Map/tests/PreparePerformanceBenchmark.py' 'output/overland-performance'
```

It captures source hashes and the current runtime patch, and creates the local fixture
PNG without uploading it. The PNG SHA-256 for this run is
`f493e81c502fedb3d041c1ae1ad30ab9fa06646689d692e60e5e734f39b2a7e9`.
Verify the loaded CodeMod sources against the captured length/checksum before timing.
Close unfinished editors/imports, open an existing map, fix theme/font/viewport, and
keep Codex forward. Do not run type checks or other heavy jobs concurrently.

Through the connected bridge, substitute the actual repository path:

```lua
local directory = "C:/path/to/draw-steel-codex"
g_OverlandPerformance = {}
local b = g_OverlandPerformance
b.original = assert(gui.GetSheetById("overland-map-panel"))
b.collapsed, b.focus = b.original:HasClass("collapsed"), gui.GetFocus()
b.parent = b.original
while b.parent.parent do b.parent = b.parent.parent end
b.image = assert(assets:LoadImageOrVideoFileLocally(
    directory .. "/output/overland-performance/fixture-4000x2000.png")).image
b.compass = "md5:https://codexback.com/ox5FcFk_LEDg0Z84AANc9Q"
b.helper = assert(loadfile(directory .. "/Overland Map/tests/LivePerformanceBenchmark.lua"))()
b.original:SetClass("collapsed", true)
b.result = b.helper.Start {
    parent = b.parent, image = b.image, compass = b.compass, runs = 5,
    cases = { { name = "normal" }, { name = "dense", dense = true },
        { name = "openNormal", opening = true },
        { name = "openDense", opening = true, dense = true } },
}
```

Run `MonitorPerformanceFocus.ps1 -ExpectedProcessId <Codex PID> -DurationSeconds <budget>`
in a separate process for opening measurements. It reads foreground identity/title/class;
it does not send input or force focus. A Ghost window is an unresponsive-app observation,
not interchangeable with switching to a different application. The engine frame counter
alone cannot validate foreground during a long opening.

Poll `b.result.progress` between phases and save `dmhub.ToJson(b.result)` after completion.
For feature-only runs, use the `pins250`/`paths150` component masks in the helper and
explicit phases excluding `settledZoom`, matching the recorded protocol. Keep failures
and all warm-ups in raw evidence; do not silently drop slow samples.

Always restore the original view after saving results, including after cancellation:

```lua
local b = g_OverlandPerformance
if not b.result.done then b.result.Cancel() end
if b.original.valid then b.original:SetClass("collapsed", b.collapsed) end
if b.focus and b.focus.valid then gui.SetFocus(b.focus) end
g_OverlandPerformance = nil
```

Local diagnostic evidence, including installed-engine IL excerpts, foreground traces,
source patch, console/check output and unprocessed batch JSON, is under
`output/overland-rewrite/performance-2026-10-19`.
