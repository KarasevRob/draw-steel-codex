# Live review validation and publication, 2026-10-17

Tested the reviewed `2b1341dd` sources in a connected Director game on engine 0.0.857.
All 31 CodeMod files were compared with repository sources after deployment. The mod
monitor was enabled before touching files and reloading, because reloading alone can
reuse cached source while monitoring is disabled. The three
additional live findings below were fixed and retested before publication.

## Live findings fixed

- **Window hover:** child controls receive hover events themselves. The host's boolean
  stayed false even with the pointer inside. Esc ownership and polling now use the host's
  normalized pointer coordinates, including bounds and the engine's zero sentinel.
  Actual hover events remain separate from those coordinates so clicking a covering
  window cannot raise the map through it; that overlap case also passed in the app.
- **Off-layer title drag:** the engine returned `(0, 1.030534)` above the document layer,
  not just `(0, 0)`. Accepting it snapped the window to its corner. Out-of-range readings
  now keep the last valid drag position. The same bridge mouse sequence passed afterwards.
- **Outline slider:** `Get("slider-handle")` resolved another editor's repeated core ID.
  Controls now capture their own descendants. The first drag change can also arrive before
  the dragging flag, so only `confirm` persists a slider value. Bind preserves the live
  drag preview. Actual drag steps left the map revision unchanged; release advanced it once.

## Passed in the connected app

- Real JSON parser: 15 inputs, BOM, malformed JSON, URLs, and ASCII/Cyrillic/emoji limits.
  Editor preview, Back, replacement/discard cancellation, invalid-input recovery,
  oversized buffers in three character sets, and replacing a 100,000-character draft.
- Real file reads: a 110 KB file bypassed the paste cap. A file containing 50,000 invalid
  entries created bounded preview content and displayed `...and 49900 more.` Synchronous
  read/check/preview work took about 0.26 seconds in this session.
- A 12-pin import crossed two batches, disabled Import while running, rejected a second
  activation, and saved all descriptions and Director notes. All pins were hidden.
  Editing one description then using Undo preserved that pin and removed the other 11.
- A label created through the UI with a missing remembered font and deleted background
  fell back to `berling` / `auto`. Typed text survived View as player. Undo with unsent
  edits removed the new label and autosave did not recreate it.
- Esc reached a lower-priority probe while the map remained foremost but both focus and
  pointer were outside. Map focus with the pointer outside, and pointer-only engagement
  over a child control, dispatched Esc to the map. A covered map was raised by its rail action.
- Title dragging out of the document layer retained position after the bounds fix.
  Fullscreen/window changes preserved the import draft. Canceling the popout discard
  confirmation preserved the in-app window and draft.
- The import card was visually inspected at 720x480 logical window size with Font Size
  80 and Warm Gold, and 140 and High Contrast; 100/Default was also exercised. Source and
  reference remain scrollable and footer actions accessible. Theme changes retained text.
- A real slider drag with 250 pins made no intermediate writes and one release write.
  An unknown nested pin-format field survived. One Undo restored the earlier outline.
- Fifty image labels reached ready state without image callbacks calling the full-window
  refresh. All 250 pin names were represented; none allocated an image background panel.
  The instrumented initial `showMap` callback took 463 ms for 250 pins plus 50 image labels
  with a warm image cache. This is synchronous Lua work, not total frame/GPU timing, and
  is not directly comparable with the old 250-pin-only 221 ms figure.
- A Location artwork attachment loaded, opened in the image viewer, and closed with Esc.
  Switching from a selected label to the Path tool hid both resize/rotate handles.
- The native popout opened with about 1000x719 logical content and returned to the in-app
  host. Native rendering was not captured: the desktop capture showed the IDE instead.
- Deleting the disposable map produced 301 Undo steps. After uploads settled, one Undo
  restored the map, all 250 pins and all 50 labels. The fixture was then deleted again.

## Scope and cleanup

The user explicitly requested skipping concurrent-edit tests. No second-client results
are claimed. Network refusal/timeout/Retry races retain offline coverage; this run did not
disconnect the real transport. Native wheel routing remains the existing engine issue.
Physical clipboard input and native file-picker cancellation were not exercised.

Only a newly created disposable map was mutated. The two existing maps, including the
older map named `Labels verification (temporary)`, were preserved. Final deletion uploads
settled, the disposable map became inaccessible, and exactly the two original maps
remained. The Party stayed unplaced. Changed view preferences, font size, theme and mod
monitor were restored; the temporary JSON files were removed. Deleted Locations retain
their inaccessible sidecar rows under the normal model deletion policy.

## Final verification and publication

Offline suites: **118 checks passed** (26 labels, 14 appearance, 17 pin text, 27 artwork,
5 canvas tools, 17 window host, 12 import/maintenance). All 40 Lua files pass syntax and
ASCII checks. Whole-repository LuaLS **3.19.2 reports zero problems**, with all four worker
results verified by the CI reporter. Every tracked Lua file matched the checked source
export. Local Markdown links and diff whitespace checks passed.

Published CodeMod `ec447c62-03db-4416-a5a2-0b013c0f3893` through `CommitChanges`:

- Changelist: **`ce9e32cb-dcbf-4202-bd67-5e1c335d96d5`**.
- Engine version: **0.0.857**.
- Server timestamp: `1792237732716` milliseconds since epoch.
- 28 updated files; the registered file list remains 31 files in the same order.
- Completion callback succeeded. Afterwards `hasLocalChanges` was false, and the latest
  published revision body of every file, fetched by its MD5, matched the repository source.
- The development checkout remains open. The original mod-monitor selection was restored.
