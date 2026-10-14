# Map label verification

Results collected on 2026-10-14, engine 0.0.857, bridge build 10. The feature is
implemented and deployed to the local development checkout. **The complete labels
update has not been published.** The user paused runtime work and then requested
documentation only; no further app inspection, cleanup, reload, deployment or publication
was performed for this documentation pass.

The behavior contract is [LABELS_BRIEF.md](../docs/LABELS_BRIEF.md). The three helpers are
registered persistently in the existing Overland Map CodeMod, bringing it to 29 runtime
files. Registration is distinct from publishing the completed sources.

## Local validation already completed

| Check | Recorded result |
|---|---|
| Shipped Lua 5.4.7 syntax checker | Passed for 33 runtime/test Lua files |
| Lua source ASCII sweep | Passed |
| Isolated label checks | 18 passed |
| Artwork regression checks | 27 passed |
| Available `../dependencies/check-mod.ps1 -Mod 'Region Map'` | 0 problems; final recorded run 38 seconds |
| Required baseline-aware checker | Unavailable; no pass claimed |

`../tools/lua-typing/check.ps1`, `tools/lua-typing/baseline.json`, and the table-overload
generator were not found. Searches included hidden files in the accessible project and
development-mod directories and repository history. The installed app and its compiled
engine were available; the expected source-checkout tooling was not. The available
module checker loads the other modules as libraries, but does not replace the missing
historical-baseline comparison. No baseline or successful standard check was fabricated.

These are recorded results, not new test runs during the documentation-only pass.

## Isolated coverage

[LabelChecks.lua](LabelChecks.lua) loads the production model, queue and selected UI
logic into a separate Lua environment. It uses in-memory rows, controlled timers,
upload receipts and simulated panels/input. It does not write live game data.

For a future local rerun from the repository root:

```powershell
& ../dependencies/lua/bin/lua.exe 'Region Map/tests/LabelChecks.lua' run
& ../dependencies/lua/bin/lua.exe 'Region Map/tests/ArtworkChecks.lua' run
```

The 18 passing cases cover:

1. Multiline creation, formatting, same-value no-op, deletion and Undo.
2. Player permission default off, own-label editing only, Director-only visibility,
   View as player restrictions, and Undo after permission revocation.
3. Hidden labels and inaccessible maps excluded from search.
4. Invalid writes preserving the row and unavailable stored fonts falling back.
5. Map-image replacement preserving labels; subtree deletion and Undo.
6. Autosave coalescing fields into one creation and editor closure flushing valid text.
7. A queued move following pending text, with separate Undo entries in order.
8. Failed creation retrying with the same ID and correct creation Undo.
9. Permission revocation canceling unsent work while retaining an accepted creation.
10. Blank unsent drafts and stale Undo producing no write.
11. Invalid preview/transform values never reaching the renderer.
12. Duplicate receipts and mod unload producing no additional writes.
13. Canceling a failed batch allowing subsequent editing to recover.
14. Player deletion Undo and direct permission-setting bypass guards.
15. The separate 256-Unicode-character and 1,024-byte limits, newline normalization,
    and control-character rejection.
16. Removing a nested map including its own labels and restoring them in the same Undo.
17. Search keyboard scope, selection, and unchanged field exit retaining the clicked row.
18. Automatic backing polarity for dark, light and mid-gray text.

These checks simulate role changes, network timing and keyboard state. They are not
evidence of a separate player's client or an actual delayed network upload.

## Live observations

One disposable addon map and four labels were used in the existing game. The test map
reused an existing map image; no asset was uploaded. The game was never switched and the
Party was not moved.

| Area | Observed result | Remaining limit |
|---|---|---|
| Create/save/Undo | UI placement and multiline text produced a confirmed save; a size edit saved and Undo restored it | Full real-player flow remains untested |
| Transforms | Selected-body drag, resize and rotation saved; resize retained the center; inverse-rotation hit tests passed | Shift snapping and Escape during an active drag need physical input verification |
| Locked interaction | Dragging locked lettering panned without changing its row revision | Unselected unlocked drag is implemented but lacks a separate final live check |
| Visibility and permission | View as player hid the editor, refused a model write, excluded the Hidden label, and found the three Revealed labels while their map was shared | Separate player ownership/revocation session remains untested |
| Local display | Show labels off removed all four; search selection temporarily showed one; deselection hid it again without changing the preference | No independent second-client display check |
| Search | Enter opened a result; one click on Edit label opened its editor after the unchanged-query rebuild fix | Physical arrows and Ctrl+Enter remain unverified |
| Backgrounds | Auto contrast, Plate and None inspected; light text had black backing and dark text white backing | No map-pixel sampling or glyph halo is intended |
| Color picker | Opened in the app and native popout; controls remained visible; main-window Escape closed only the picker, preserving the editor/map | Native physical Escape remains unverified |
| Large zoom | At 20x, text/box scale increased by 20x and all four labels remained drawn | No full-frame performance claim |
| Errors | Targeted RegionMap error query after the final contrast/layout fixes returned no entries | Probe errors and a core reload cleanup error occurred earlier; no claim of an entirely error-free session |

The bridge's virtual key tool dispatched Enter/Escape, but did not make
`dmhub.KeyPressed("DownArrow")` report a held key. Arrow/Ctrl logic passed isolated
checks; physical keyboard and native-window dispatch must be verified separately.

### Layout and Font Size

The in-app window was requested at 720x480 and 1000x800 logical units at Font Size
80, 100 and 140. Default and Warm Gold were inspected during that sweep; MCDM was
restored afterward. This was not a complete size/font/theme cross-product.

- At 720x480, the content was 720x444. The sampled lettering box stayed approximately
  91.91x18.22 logical units at all three Font Size values; the host scaled controls and
  map together. Numeric fields measured 292 pixels inside 292-pixel parents.
- At 1000x800, Font Size 80/100 produced 1000x764 content. At 140, the host clamped the
  available height to approximately 629.14 logical units; this was not an unclamped
  1000x800 test. The editor retained its scroll region and field widths.
- Fullscreen lettering/search and native popout lettering/editor were inspected. The
  native content measured approximately 999.68x718.97 with four labels and 292-pixel
  fields inside 292-pixel parents. The color picker stayed inside the native window.
  Return to app succeeded. A full native size/font matrix was not run.
- The successful native desktop capture is the temporary file
  `C:/Users/ElderHex/AppData/Local/Temp/codex-shot-2026-10-14_23-52-40.png`.
  It is supporting local evidence, not a durable repository artifact.

### Rendering and performance

The rendering probe measured natural text dimensions independently of scale at 1x,
2x and 20x and at 45-degree rotation. Explicit newlines increased natural height.
The implementation caches those dimensions and applies inverse rotation for hit tests.

The [benchmark fixture](../../output/labels-live-benchmark.lua) temporarily supplied
250 pins, 150 paths and 0/50/200 labels through in-memory model overrides. Those overrides
were restored. Recorded mean synchronous Lua layout times were:

| Labels | Pan layout | Zoom layout | Label style writes during pan |
|---|---|---|---|
| 0 | 0.033 ms | 1.600 ms | 0 |
| 50 | 0.017 ms | 2.050 ms | 0 |
| 200 | 0.033 ms | 2.875 ms | 0 |

All 50/200 labels remained represented. These measurements exclude deferred engine
rendering/GPU work and are not frame rates. They preceded the final backing-image/contrast
adjustment; whole-frame timing of the final renderer remains unverified. Pan moves the
existing layer and does not write per-label styles.

## Registration, publication and paused cleanup

CodeMod: `ec447c62-03db-4416-a5a2-0b013c0f3893`, Overland Map.
Development directory: `C:/Users/ElderHex/codex-dev-mods/Overland Map`.

| Helper | Registered position | File ID |
|---|---|---|
| RegionMapLabels | After RegionMapUndo, index 7 | `26fd4f77-afd3-4aef-9bcf-862b2d3a1e21` |
| RegionMapLabelLayer | After RegionMapPathLayer, index 15 | `1c1b50af-c6c3-46ac-b09f-6f5a20c3069e` |
| RegionMapLabelPanel | After RegionMapPathPanel, index 21 | `91268f42-666a-4d90-88b1-86c14891b1e5` |

All three registrations were read back successfully. The complete 29-file module was
deployed locally, preserving concurrent source edits. The checked-out source cache was
refreshed and the final contrast/search changes were exercised. The development checkout
and its original automatic-reload setting were retained. No C# engine source was changed.

The last verified installable package, `elderhex-elderhex_mapregion`, was version **2**,
with data ID `3da61d59-e334-4c69-a4cf-ccad8f714117`. It predates labels. No completed-label
CodeMod commit or new package version was published before the pause.

Cleanup remains outstanding at the user's request to leave the app untouched:

- Game: `ab736f85-7b96-4216-bee8-6ea3d2d8cc59`.
- Disposable map: **Labels verification (temporary)**,
  `bd2a3594-9362-4132-b4ca-0186eaa91850`, last observed unshared, with four labels.
- Original map: **Broadhurst**, `8f5ad0d2-5ef0-4d33-a59d-0925184a3346`.
- Font Size 100 and the MCDM theme were restored before the pause; the native popout was
  returned to the app. The original map view, window geometry and label-format/display
  preferences were not fully restored. Do not overwrite preferences changed since testing.
- The [fixture inventory and pre-test preferences](../../output/labels-live-fixture-2026-10-14.json)
  identify the four label IDs and original values. The existing image asset must remain.
  Temporary probe globals may remain until a later reload or explicit cleanup.

If runtime work is authorized again, first inspect the current state and remove only the
identified disposable fixtures through normal model deletion. Restore only preferences
still attributable to testing. Then, when publication is requested, compare and publish
the complete source set, audit a new code-only snapshot for unrelated data/modules, and
update the same game without switching games. None of those steps is part of this
documentation-only completion.
