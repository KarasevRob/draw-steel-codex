# Overland Map checks

For canvas placement, run
`& '..\dependencies\lua\bin\lua.exe' 'Region Map/tests/CanvasToolsChecks.lua' run`.
The five isolated checks load the complete production module and cover Location/label
creation, ruler/scale points, ignored clicks, and independent panel positioning.

Verified live on 2026-10-16: Add location and Add label followed by map clicks create
editable entries. A duplicate `PlaceAt` definition had replaced tool dispatch with
panel positioning; the positioning helper now has its own name. Breadcrumb names use
the same native ellipsis setting as Atlas cards. The reported long name was inspected
in the in-app window, and temporary test entries were removed afterwards.

For map-wide pin formatting and hover descriptions, run
`& '..\dependencies\lua\bin\lua.exe' 'Region Map/tests/PinTextChecks.lua' run`.
The [pin-text verification record](PIN_TEXT.md) covers its isolated checks and live UI pass.

For the in-app window host, run the isolated offline checks from the repository root:

```powershell
& '..\dependencies\lua\bin\lua.exe' -e "local c = dofile('Region Map/tests/WindowHostChecks.lua'); if not c.Run() then os.exit(1) end"
```

They exercise the production host/preferences/buttons and core resize helper with an
in-memory GUI. They do not use the running engine or verify physical input and rendering.
See [the window design](../docs/PANEL_VIEW_BRIEF.md) for completed live checks and
the remaining keyboard retest, and [the engine handoff](../docs/POPOUT_WHEEL_ENGINE_HANDOFF.md)
for the unresolved native-popout wheel delivery issue.

For Location/path image attachments, see [artwork checks](ARTWORK.md). Their isolated
fixtures can run without changing this live import fixture or reloading the app.

These checks run against the deployed Overland Map mod in a connected Director session.
They are test helpers, not registered CodeMod files.

Open a map and leave the import editor empty. Through `execute_lua`, load the helper using
the absolute repository path, then call `Parse()` and `Editor()`:

```lua
local checks = assert(loadfile("C:/path/to/draw-steel-codex/Region Map/tests/ImportChecks.lua"))()
checks.Parse()
checks.Editor()
```

Run `checks.Oversized("x")`, `checks.Oversized(utf8.char(0x416))`, and
`checks.Oversized(utf8.char(0x1f30d))` in separate bridge calls. Each starts and ends with
an empty editor; unrelated large documents are not diffed against one another in the
native undo history. Progress markers identify a stalled step.
`checks.ReplaceLargeDraft()` verifies that confirming example replacement handles a
100,000-character draft without asking the native editor to diff the old and new documents.

`Parse` exercises the actual engine parser, BOM and malformed input, hidden examples,
URLs, field validation, and the 100,000-character ASCII/Cyrillic/emoji boundaries.
It also accepts 256-character names intact and rejects 257-character names for all three
character sets, checking that model validation and the import error agree.
`Editor` drives real GUI events for preview, Back, example replacement, discard, recovery,
and oversized input. It asserts that no Locations were written and finishes with an empty,
closed import card. It refuses to overwrite a nonempty draft.

Additional live acceptance checks:

- Choose a valid file while a draft exists: cancel switching, then confirm it; Back after
  confirmation returns to an empty editor. Invalid files and picker cancellation retain
  the draft. Files larger than the text limit still preview.
- Close/toggle the fullscreen map with a draft: cancel keeps the host, confirm closes it.
  Native OS close, app exit and Lua reload cannot prompt and discard drafts.
- Change permissions or make the target unavailable before Import: no writes begin.
  A changed duplicate list or map image/name refreshes the preview before confirmation.
- Import a small hidden batch with descriptions and notes on a disposable map; verify
  positions and sidecars, then Undo. Remove the disposable map afterwards.
- Inspect fullscreen and 720x480 popout geometry, Font Size 80/100/140, themes, long
  errors, scrolling, keyboard focus, and the native clipboard paste path at the size cap.

## Verification on 2026-10-14

- The JSON helper uses Swagger-style field rows with types, a required marker, enums,
  defaults and concise constraints. Copy contract copied all nine fields and rules as
  plain text, exactly matching the displayed reference, without changing the draft.
  The helper opened at the first field, and its narrow layout and High Contrast rendering
  were inspected at Font Size 140. Original theme, size and font settings were restored.
  Live 256/257-character name checks passed for ASCII, Cyrillic and emoji. No raw OpenAPI
  document remains in the helper or clipboard output.
- Contract layout correction: padding and border-box sizing now share the dimension rule,
  so the reference fits its column. Both headers measure 36 px; editor and reference each
  measure 320 px tall when wide and 240 px when narrow. Live checks covered normal width,
  a 600 px card, Font Size 140 and High Contrast. Field names use regular monospace text,
  types sit beside names, and the frame/separators use the quiet border token. Copy kept
  the draft intact. Theme, font size and card width were restored afterwards.
- Live parser and editor checks passed, including Unicode boundaries, invalid-input
  recovery, replacement/discard cancellation, and zero writes before Import.
- A 110 KB file previewed through the uncapped file path. Invalid files retained the
  draft; valid file switching required confirmation.
- A disposable map received exactly 12 hidden Locations across two batches, including
  descriptions, Director notes and explicit/default positions. A double Import press
  did not duplicate them. One Undo removed the batch; the disposable map was removed.
- Director permission loss and target deletion retained text and prevented importing.
  Adding a duplicate after preview refreshed the warnings without starting an import.
- The Import toolbar button sits directly after Add, opens the editor, and is hidden at
  the Atlas. Import is also available in the Atlas card and top-level map menus; the map
  surface right-click and pin menus omit it.
- Atlas map cards expose a Director-only "..." menu. A virtual mouse click on the button
  opened the menu without opening the map. Cancel preserved the map and its child; Delete
  removed both; one Undo restored both and the card. Player view hid these controls. The
  disposable test map was removed after verification.
- The expanded Atlas menu targets its selected map for Edit, Import, image replacement,
  journal linking, settings and presentation. Sharing produced an Undo entry and Undo
  restored the unshared state. Show to players retained the share confirmation; Cancel
  made no share or presentation. A disposable map passed Delete, Cancel and Undo again.
  The final menu excludes Add location, Path tool, Ruler and View as player as requested.
  Its layout was inspected at 720x480 with Font Size 140 and High Contrast, then restored
  to fullscreen, Font Size 100 and MCDM. The final menu opened through a virtual mouse
  click, with all four excluded entries absent. No test maps remain.
- Fullscreen close/toggle honored the discard guard. Native popout sizing was inspected
  down to the 720x480 logical content size, with Font Size 80/100/140. High Contrast and
  MCDM theme switches kept source intact; the editor rebinds its monospace font after a
  layout to avoid the native control's stale font rendering.
- Lua syntax, ASCII-only source and diff whitespace checks passed. The available
  `../dependencies/check-mod.ps1 -Mod "Region Map"` completed with **0 problems**, loading
  the other mods as libraries. The full-repository `tools/lua-typing/check.ps1` and baseline
  are absent, so that broader check could not run.

Deployment used the live CodeMod's `gitFolderPath`, since the general `gitfolder` setting
was empty. Select Overland Map in `code.monitorid`, copy and touch all changed runtime
files, use the app's F4 refresh, and verify the changed files' `localContents` match
the intended source. A bridge reload alone can execute the previous cached version.

Native file-picker cancellation and physical clipboard paste still need a manual check;
the file read/preview path and editor buffer limits were exercised through the bridge.

## Atlas, window and position-lock verification, 2026-10-15

The engine was released for testing. All changed loaded files were compared with source
after F4; the complete 29-file development mod is current. Lua syntax, ASCII and diff
checks passed; 13 window-host checks and 18 label checks passed; the available mod type
checker reported 0 problems in 38 seconds. The standard baseline checker remains absent.

- Hidden badges and the inline creation notice were inspected in the live Atlas.
  Revealed was checked by binding a copied UI record, then restoring the normal model:
  no map was shared with players for this test. Player preview excluded all unshared maps.
- The notice remained on both steps of New map and Add map. Adding a map to a disposable
  Location kept `mapShared=false`; Replace map image omitted the creation notice.
- Minimum-size window layouts were inspected at Font Size 80/100/140 with Default,
  MCDM and Warm Gold. The creation card expanded to fit its notice. This was not an
  exhaustive theme/font cross-product or a fresh Party-here layout check.
- The window border renders above its content and disappears in fullscreen. It is
  noninteractive, leaving the canvas and resize handles available.
- Canvas, label, pin, Atlas-card and Add-menu popups closed on a left click elsewhere.
  A real click on Replace map image still ran that menu action and closed the popup.
- A disposable label stayed fixed while locked, moved from (0.5, 0.45) to approximately
  (0.54668, 0.47766) after selection and an unlocked drag, and stayed fixed after relocking.
  No Move label action remained in its editor or context menu.

The disposable map, child Location/map and label were deleted and their absence checked.
The other developer's Labels verification map was preserved. Original map, window
geometry, font and scheme were restored; the game was left unfrozen. No publication
was performed. Keyboard limitations are recorded in [the window brief](../docs/PANEL_VIEW_BRIEF.md).
