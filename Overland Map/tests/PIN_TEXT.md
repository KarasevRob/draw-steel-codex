# Pin text verification

Implemented and verified in the development checkout on 2026-10-15. The signed-off
contract is [PIN_TEXT_BRIEF.md](../docs/PIN_TEXT_BRIEF.md). No cloud publication was run.

## Isolated production-code checks

```powershell
& '..\dependencies\lua\bin\lua.exe' 'Overland Map/tests/PinTextChecks.lua' run
```

15 checks passed: sparse defaults and independent tier sizes; strict write validation
and safe malformed optional data; parent/child isolation and moving a nested map;
Director-only editing and Undo; one in-flight write, latest-value merging and remote-field
rebasing; unrelated busy writes; failure/Retry with the original Undo snapshot; reset
ordering; permission loss and unload; image replacement/removal and deletion Undo;
stale Undo refusal; effective default restoration and theme changes; sentence/abbreviation
handling; UTF-8 length limits; and description access without Director notes.

The existing 18 label checks and 27 artwork checks also passed after the model changes.
The tests use the existing isolated LabelChecks fixture, not the live game's records.

## Live checks

Used a private disposable map, three direct pins (Major Icon + name, Normal Name plate,
Minor Icon only), and a pin on the nested map. Other developers' fixtures were preserved.

- Settings controls, immediate saves, one-decimal size entry, invalid numeric text,
  font selection, theme color, backgrounds, reset and save feedback.
- Left and right anchors: measured the rendered text edge against the unchanged Location
  point for normal names and Name plates. Clicked the visible Name plate with None backing
  and confirmed selection; ordinary icon hit discs retain their original sizes.
- Fixed text dimensions across zoom; existing Show names and Icon only behavior retained.
- Minimum 720x480 window at Font Size 80/100/140, including the appearance disclosure and
  the color picker at 140. The picker opens leftward and fits on screen.
- Theme change to High Contrast and back; default name colors update while explicit
  custom colors remain independent. Hover uses the app tooltip typography.
- The two-sentence hover preview folds paragraphs and keeps `Dr.` and `1.5` intact.
- Late picker callbacks after closing Settings are ignored. Queued receipts still
  refresh the map after Settings closes.
- Native text material caching required replacing only the text leaves when switching
  fonts or removing a halo. Reproduced the stale glyph/outline behavior, compared a fresh
  leaf with identical formatting, then verified both transitions after the fix.

All five fixture Location rows were soft-deleted with confirmed receipts. The original
Font Size, color scheme, map selection, camera preferences, Show names, and window
geometry were restored. No second player client or OS keyboard automation was used;
access and synchronization races were exercised through the isolated model checks.

## Loading and validation

`RegionMapPinText.lua` is registered in the Overland Map CodeMod immediately after
`RegionMapSession.lua`. The repository folder remains `Region Map`. All changed runtime
files were deployed together initially, with subsequent fixes deployed and reloaded.
The app's loaded file contents were compared with the repository sources.

Runtime Lua passed `luac -p` and the ASCII scan. The prescribed
`../tools/lua-typing/check.ps1` and baseline are absent in this checkout; the available
`../dependencies/check-mod.ps1 -Mod 'Region Map'` was used for module type checking.
Final result: 0 problems. All 30 registered runtime files passed syntax and ASCII checks.
