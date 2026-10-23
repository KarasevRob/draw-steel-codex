# Authoring UX verification - 2026-10-20

Plan: [AUTHORING_UX_PLAN.md](../docs/AUTHORING_UX_PLAN.md).

## Baseline

- The two inherited step 1.1 edits passed Lua 5.4 syntax checks.
- All 248 checks across 13 offline suites passed before further edits.
- `../dependencies/check-mod.ps1 -Mod "Overland Map"` completed with 62 existing
  unused-local, unused-function and redefined-local diagnostics.
- The required `../tools/lua-typing/check.ps1` and parent typing reference are absent
  from this checkout. That check has not run; the available mod check is recorded separately.

## Phase 1

- Kept selection stationary, eased the camera allowance when a panel opens or closes,
  applied Reduce Motion immediately, and required a matching canvas press for clicks.
- Syntax and ASCII checks passed on all changed Lua files.
- All 252 checks across 14 offline suites passed, including four new authoring checks.
- The mod type check completed with 60 existing diagnostics and no new ones; removing
  unused canvas helpers eliminated two baseline diagnostics.
- All four changed runtime files were copied with `deploy.ps1` to the configured
  `C:\Users\ElderHex\codex-dev-mods\Overland Map` folder. App reload is pending.

## Phase 2

- Editable pins open their editor; locked labels and aids can still be selected.
- Location, label and path editors have pinned status/Retry/Delete/Done footers. Done
  and editor Esc deselect; picker Esc returns. New selections reset the scroll position.
- Labels drag before selection when unlocked. Blocked pin, label and aid drags show one
  toast with Unlock. The lock highlight means locked; opening a map still re-locks it.
- Add label remains active after placement.
- All 262 checks across 14 offline suites passed. Syntax/ASCII checks passed; the mod
  type check retained the same 60 baseline diagnostics, with no new diagnostics.
- Deployed all eight changed runtime files and reloaded the app. Live Broadhurst pin
  selection opens edit without moving the map. The header, shared actions and pinned
  footer were inspected visually.
- Live testing caught destruction of controls moved between read/edit slots. Explicit
  `Unparent()` before reassignment fixes it; a subsequent live inspection found all shared
  controls valid and zero invalid descendants. The offline fixture now supports Unparent.
- The file watcher must finish reading changed files before reload. A reload issued
  during detection used cached source; touching the files, observing the read log and
  checking the loaded function's ending line confirmed the corrected source was active.

## Phase 3

- Removed hidden pin/label fades. Visibility badges and the hidden path fade now follow
  the per-viewer Show player visibility preference, initially off. Label eyes use the
  round pin badge at the label's top-left corner.
- Added the Director's map-wide hidden count and toggle chip. Broadhurst reports 25.
- All 264 checks across 14 suites passed, with syntax and ASCII checks. The mod type
  check still reports only the 60 existing baseline diagnostics.
- Deployed and visually checked Broadhurst with the overlay off and on: names stay
  readable, pin and label eyes appear on request, and the chip reflects the preference.
  Live inspection caught a fixed button-size class overriding the chip width; explicit
  auto layout sizes corrected the overflow (228 px measured, full text visible).

## Phase 4

- Added the lazily constructed Quick Add component. New locations and labels open a
  single-line field beside their anchor, with All options for the full editor. Enter
  saves and returns focus to the canvas without stopping placement or opening an editor.
- Quick Add follows canvas layout, flips left near the right edge, clamps below the
  toolbar and hides off-screen. It participates in session flush/cancel transitions;
  empty label drafts disappear on leaving. Escape closes it before stopping the tool.
- Added eight authoring checks for saves, placement, All options, Escape, blank labels,
  navigation, permission/undo handling and off-screen layout. All 272 checks across
  fourteen offline suites pass. Changed Lua files pass syntax and ASCII checks.
- The final available mod type check completed with the same 60 existing diagnostics
  and no new diagnostics. Its exit status remains 1 because those baseline hints exist.
- Final review reproduced a permission-reconciliation reset of an allowed location's
  unfinished input. The regression isolated the cancel callback (without a bind or
  navigation); it now resets text only when work was actually cancelled. Undo still
  removes unsent typing. The regression fails before the fix and passes after it.

## Live authoring checks

- Created five pins down Broadhurst's right edge using click, type, Enter. Each saved
  with `u = 0.9695783`; the Delian Tomb landmark stayed at screen `(1301, 545)` throughout.
  The side editor did not exist after the sequence. Quick Add opened to the anchor's left.
- Escape committed a sixth test name and closed Quick Add; the placement hint remained
  until the second Escape. Labels use the same flow and keep their placement tool active.
- A locked label drag displayed Positions are locked with Unlock. Clicking Unlock
  removed the lock highlight. An unselected test label then moved from `(1820, 1140)`
  to `(1880, 1180)` without moving the map.
- Clicking Delian Tomb opened edit with Move Party here and the shared header/actions.
  Done closed it. After panning into the extra panel allowance, live layout samples on
  Done showed inset `320, 252.85, 193.61, 142.26, 98.80, 63.25, 35.59, 15.83, 3.97, 0`
  over 0.300 seconds. Camera center eased from `0.71070` to `0.5`.
- Inspected Quick Add at normal MCDM/100%, Default/140% in a 740 x 570 logical window,
  and Forest/80% in a 640 x 500 window. Input and All options stayed inside the card.
  All options preserved an empty label draft and opened its full editor; the 140%
  scroll area and pinned Delete/Done footer fit. Original theme, font and geometry
  were restored. This used the running game, without a harness restart.
- Removed the six smoke-test locations and test label. Original Broadhurst again has
  its 25 hidden items. Empty font-test label drafts were discarded.
- Deployed the final Quick Add cancellation guard, observed the watcher read, and
  reloaded. A live name stayed unchanged across `overlandMapReconcile` and saved on
  Enter. The subsequent console window contained no errors other than the app's
  existing video-clock resync messages.

## Usability rerun

- [Blind UI-only report](BROADHURST_USABILITY_2026-10-20.md): completed 19 named pins
  and 6 labels on a fresh Broadhurst image copy, including edge placements, then
  successfully renamed a location. A read-only follow-up confirmed all 25 items.
- Recorded distinct criticisms about icon discoverability, repeated entry steps,
  large labels overlapping nearby names, discovering label movement while locked,
  and finding a player preview. The blind tester's label-move and player-view checks
  remained incomplete; the separate developer smoke checks cover those behaviors.
- The new-item sequence used Quick Add without the full side editor. The measured
  edge-placement check establishes the stable camera; the blind report supplies
  the remaining usability observations. An exact comparison is unavailable because
  the earlier prompt and log are missing.
- A subsequent local player preview returned no trial pins or labels and excluded
  the unshared map from the visible UI. Restored Director view and the visibility
  preference, removed the test copy, and reopened the original Broadhurst with
  19 pins, 6 labels and its original window/font/theme settings. No CodeMod publication
  or presentation to players was performed.

## Reviewer follow-up

- Reproduced a selected pin surviving Quick Add, tool cancellation and a blank-map
  click, followed by Escape returning to the Atlas. Quick Add now deselects on
  completion, and blank-map clicks clear either pin or label selection. Escape still
  stops the sticky placement tool before navigating.
- Confirmed that a locked drag over Silver Wood left the camera stationary while a
  background drag panned it. This matched the original plan's dead-gesture rule, but
  obstructed navigation across large labels. Locked label/aid body drags now pan
  without a toast, since lettering covers too much of the map to notify on every pan;
  only a locked pin drag shows the Unlock toast. They never write object positions;
  clicks still select, and unlocked object drags still move the object. (Offline
  checks only; not yet re-checked live.)
- Reproduced fractional inset nontermination: retargeting from `0.9850579200000027`
  to `265.59999999999997` produced `265.60000000000002` even at `t = 1`. Completed
  easing now assigns the target exactly. The regression checks camera-save release
  and return to the idle think rate after retargeting.
- Hidden counts now cache by map ID and `Model.Revision()`, after the Director gate.
  Before the fix, three live refreshes at the same revision each recounted the lists.
  Afterwards, three warm-cache refreshes caused zero hidden-list scans; three refreshes
  following invalidation caused one. Offline checks also cover local writes, remote
  table updates, map switches and player preview.
- Quick Add uses `SetClassIf` for visibility and receives no canvas-layout events while
  closed. The regression fails before the fix and checks repeated visible/off-screen
  layouts, closing and subsequent canvas frames.
- `OverlandMapReaders.QuickAddItem` owns the current-map and editing-permission checks
  used by opening, refresh reconciliation and the input's edit/submit guard.
- Show player visibility remains a personal preference, constructed in a Director-only
  slot. Live Settings inspection showed it in Director view, absent in player preview
  while the other personal settings remained, and restored on returning to Director.
- Live Quick Add saved the name, collapsed and left no selected pin; Escape stopped
  placement while Broadhurst remained open. A locked Silver Wood drag moved a landmark
  100 screen pixels while the label's stored coordinates stayed unchanged. Review test
  pins were removed; Broadhurst again has its original 19 pins, 6 labels and 25 hidden items.
- All 276 checks across fourteen offline suites pass, including four new regressions
  and strengthened Quick Add deselection and zoomed locked-drag checks. Syntax/ASCII
  checks passed. All six changed runtime files were deployed, the watcher read them,
  and Lua reloaded successfully; deployed hashes match the repository.
- The available mod type checker completed with the same 60 baseline diagnostics;
  comparison by file, code and message found no changes. The required parent typing
  checker remains absent. Live console checks found only existing video-clock messages.

## Live verification and prerequisites

- The user opened the game after the initial bridge/lobby checks. No app start or stop
  was performed by the agent.
- Registered `OverlandMapQuickAdd.lua` after `OverlandMapPopovers.lua` in the live mod
  (`ec447c62-03db-4416-a5a2-0b013c0f3893`, index 45). Player.log confirmed
  `Verified OverlandMapQuickAdd in cloud` and a successful CodeMod write.
- Broadhurst map: `e7011483-eb13-4d30-a98b-0c76232dd459`.
- The referenced `scratchpad/broadhurst-usertest-log.md` and exact original blind-agent
  prompt are absent. The usability rerun uses an equivalent 25-item task on a fresh copy;
  it cannot provide an exact before/after comparison to the missing log.
