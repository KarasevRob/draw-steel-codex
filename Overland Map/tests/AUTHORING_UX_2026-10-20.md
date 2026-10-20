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

## Live verification and prerequisites

- The user opened the game after the initial bridge/lobby checks. No app start or stop
  was performed by the agent.
- Registered `OverlandMapQuickAdd.lua` after `OverlandMapPopovers.lua` in the live mod
  (`ec447c62-03db-4416-a5a2-0b013c0f3893`, index 45). Player.log confirmed
  `Verified OverlandMapQuickAdd in cloud` and a successful CodeMod write.
- Broadhurst map: `e7011483-eb13-4d30-a98b-0c76232dd459`.
- Remaining: full authoring smoke checks, theme/font checks and the blind usability rerun.
  The referenced `scratchpad/broadhurst-usertest-log.md` is absent from this checkout.
