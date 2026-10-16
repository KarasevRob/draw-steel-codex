# Map label verification

Evidence collected 2026-10-14/15, with placement and text-appearance follow-ups on
2026-10-16. Labels are implemented in the development checkout. This record does not
assert the current version of an installable cloud package.

Positions locked/unlocked now controls both Location and label movement; separate
Move label actions are removed. Live checks confirmed locked/unlocked/relocked behavior.
The temporary map, Location and label from that follow-up were removed.

The [label contract](../docs/LABELS_BRIEF.md), [appearance contract](../docs/TEXT_APPEARANCE_BRIEF.md)
and [combined test index](README.md) describe current behavior and validation.

## Automated validation

- 18 label checks and 27 artwork checks passed; the latest combined run is recorded
  in [README.md](README.md).
- Runtime/test Lua passed syntax and ASCII checks.
- The available module type checker reported zero problems. The prescribed
  whole-repository checker is absent; no whole-repository pass is claimed.

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

## Registration and retained fixture

RegionMapLabels, RegionMapLabelLayer and RegionMapLabelPanel were registered
persistently. Current order is in the [runtime file table](../README.md#2-architecture);
the original 29-file order has been superseded by later features.

The map originally named **Labels verification (temporary)**,
`bd2a3594-9362-4132-b4ca-0186eaa91850`, was preserved and subsequently used by the
user. It is not a pending automatic-cleanup target. The old pre-test preference
snapshot must not be restored over later user changes.

Git pushes and local development deployment are separate from publishing an
installable CodeMod package. Check the live module/package before reporting its status.
