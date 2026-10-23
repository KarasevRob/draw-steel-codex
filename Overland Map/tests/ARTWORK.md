# Artwork attachment checks

Historical verification is summarized below. Temporary machine-readable artifacts were removed from the repository; the runnable suite is [ArtworkChecks.lua](ArtworkChecks.lua).

`ArtworkChecks.lua` loads the production model and component into a separate Lua
environment with disposable in-memory tables, timers, image responses and panel events.
It never registers game types, writes live data, mounts a real panel or changes settings.

From the repository root:

```powershell
& ../dependencies/lua/bin/lua.exe 'Overland Map/tests/ArtworkChecks.lua' run
```

It can also run through the bridge without touching the current developer's fixture:

```lua
local checks = assert(loadfile("C:/path/to/draw-steel-codex/Overland Map/tests/ArtworkChecks.lua"))()
checks.Run()
```

## Automated coverage

For Locations and paths: attach/replace/remove, same-value no-op, one Undo entry, stale
Undo, player and View as player model guards, malformed/missing/raw/video references,
local owner-routed open, loading timeout and late success, picker None and dismissal,
duplicate callbacks, unrelated edits, conflicting attachment edits, leaving the editor,
mod unload, busy-write retries, permission changes (including Undo) and failed/refused
optimistic upload Retry.
Closing after a write starts preserves its eventual Undo entry.

Additional cases cover a hidden path endpoint, stale load callbacks, unavailable/restricted
assets, explicit Retry, asset-update recovery, read-only player-owned edit previews, map
image replacement/removal, full-row deletion Undo, and a 3,002-Location index with zero
artwork requests. These assertions exercise production Lua but simulate engine responses.

## Live acceptance, in a disposable session after deployment

Do not run UI-driving tests or reload the session while another developer is using it.
Create a shared point crawl map with two revealed Locations and a path. Use one portrait
and one landscape Journal image, then remove the disposable map when finished.

| Area | Check | Status |
|---|---|---|
| Core | Attach/open/close/reopen/replace/remove/Undo on both object types; one Undo each | Isolated and live app/model/UI checks pass |
| Permissions | Real player and View as player, including a player-owned Location | Isolated player checks and live View as player pass; real player client pending |
| Independent viewing | Director and player open different images; closing one leaves the other alone | Pending real clients |
| Assets | Ordinary player-readable image; missing/restricted/video assets | Simulated pass; live video rejection and malformed unavailable state pass; real player pending |
| Compatibility | Absent/malformed fields retain owner; map changes retain artwork; deletion Undo restores it | Isolated and live pass |
| Races | Slow upload; rapidly switch selection; cancel picker; duplicate result; busy/conflicting writes; stale Undo | Simulated pass; live stale picker callbacks after role loss pass; slow real uploads pending |
| Loading | Cached, slow past 10 seconds, late recovery, Retry, selected asset updates | Simulated pass; live cached loading pass; slow network recovery pending |
| Input | Enter in active read section; typing/search/picker/modal input unaffected; Escape closes viewer only | Live main-window Enter/Escape and search Enter pass; native OS keyboard pending |
| Layout | Fullscreen/popout at 720x480 and 1000x800, Font Size 80/100/140, both themes, portrait/landscape | Fullscreen/native preview inspected; 12 native geometry cases pass; later desktop captures blank |
| Performance | Existing large-map live fixture, no eager loads or added pan/zoom work | 3,002-Location isolated pass; live timing pending |

## Validation and rollout record, 2026-10-14

- Lua 5.4.7 syntax and ASCII checks pass for all 28 RegionMod runtime/test Lua files.
  Diff whitespace is clean and all 12 artwork strings match the copy manifest.
- 27 isolated checks pass. A failed optimistic write initially skipped its retry; the
  regression now requires another upload and exactly one confirmed Undo entry.
- A read-only live probe examined 1,870 image-asset keys: all fit the library-ID shape.
  A sample asset's `loaded` and `HaveReadPermissions()` values were booleans and its
  backing `imageid` was a string. The probe changed no UI or game state.
- Required `../tools/lua-typing/check.ps1`, `tools/lua-typing/baseline.json` and the
  parent engine source checkout are absent. No repository-standard full-check pass or
  restored baseline is claimed. The available `../dependencies/check-mod.ps1` diagnoses
  RegionMod with the other modules loaded as libraries: **0 problems** (31 seconds).
- The broader tooling search covered accessible files on C:, D: and G:, hidden folders,
  dependency installations, cached scripts and this repository's history. It found the
  installed LuaLS binary and `check-mod.ps1` plus a cached copy, but no standard checker,
  type baseline, generator scripts or engine typing reference. E: was not ready; protected
  OS directories were inaccessible. No baseline was fabricated from current diagnostics.
- A direct full-workspace LuaLS run completed: **0 RegionMod diagnostics**, 11,049 in
  625 other files (mostly unused locals, redefinitions and whitespace). Its report is
  `%TEMP%/luals-artwork-full-734f41da83fd4342a5e459bbe700e130/check.json`. This is not a
  historical-baseline comparison. The final RegionMod check also reports **0 problems**.
- After the user released the engine for testing, registration was verified through
  `register_lua_file` using `Overland Map/RegionMapArtwork.lua`: index 16, immediately
  before the detail panels. The app's console contains both the successful `/CodeMod/`
  write and `Verified RegionMapArtwork in cloud.`
- The development module directory was named `Overland Map`, while the source
  directory is `Region Map`. Read the current CodeMod git-folder setting before deploying. The repository deploy script's dry run failed because its
  configured git folder was empty and its fallback belongs to another machine. The
  feature files were copied together to the confirmed live folder, checked against
  `localContents`, and reloaded. Concurrent import/log changes were preserved.
- Live checks used one disposable point crawl map, two Locations and a path. The Location
  picker attached/replaced/removed an image and Undo restored it. The path picker attached
  an image; its actual None cell removed it and Undo restored it. A path replacement
  through the model left an already-open image as a snapshot; later opens used the new image.
- View as player hid all attachment-management controls for both editors, closed open
  pickers, ignored their saved callbacks and refused model writes without changing row
  revisions. Switching a path editor now keeps its preview in read mode. A hidden endpoint
  hid its path and artwork. A malformed field left the path visible and was removable.
- Real Enter dispatch initially missed a read section because the canvas owned focus.
  The shell now forwards the focused canvas's Enter event only to the active artwork read
  section. Live Return opened the viewer; Escape closed it while keeping the detail panel.
  Search still accepted text and used Enter to select its result without opening an image.
- Native image opening used the originating window's modal layer, leaving the main modal
  layer empty. The 600x800 portrait originally exceeded a 720x513 native viewport; fitted
  arguments now render it at about 385x513 while preserving the existing 1024-pixel cap.
- At both window sizes, all six Default/Warm Gold and 80/100/140 combinations kept the
  preview at 160 logical pixels and retained aspect ratio within its frame. A landscape
  preview was also measured and the fullscreen portrait/landscape views inspected.
  A native preview was captured locally; that temporary screenshot is not retained.
  Later OS captures were uniformly blank; the final native viewer fit is backed by engine
  geometry, not a usable final screenshot. Targeted native OS key injection could not find
  the window, so native physical Escape remains a manual check.
- Adding/replacing/removing a Location's map and moving the Location retained its artwork.
  Deleting that Location also removed its path; Undo restored both complete artwork rows.
  Deletion left an already-open viewer intact. A real video asset was rejected without a write.
- All four disposable rows were removed with confirmed uploads. The Party remained
  unchanged, font/theme were restored, and only the view preferences changed by these
  checks were restored, preserving concurrent preference edits. The helper registration
  remains live. No `RegionMapArtwork` errors or unresolved-theme-token errors were found.
- A core `DockablePanel.FindInstance` cleanup error interrupted one hot reload. Reloading
  again after closing test panels restored registration; no core code was changed.

## Cloud publication, 2026-10-14

The user requested all current Overland Map changes in the cloud version. The standard
CodeMod `CommitChanges` workflow published changelists
`57a62295-388b-42fc-84c9-f72840ca1b96` and `b766ca37-df8b-4693-bb75-6b72bd2abc19`
for engine 0.0.857. This includes the log actions above the entries and Show route default
off, as well as the artwork, paths and import work. All 26 registered runtime sources now
match the repository after line-ending normalization; no deployed changes remain pending.
Successful server write responses contain both changelists and the expected file hashes.
The development checkout remains open. Syntax, all 27 artwork checks, 15 live parser
inputs and the available module type check passed again before publication.
The temporary publication export is no longer retained; these IDs describe that historical publication, not the current branch.

Runtime feature files: `RegionMapRecords.lua`, `RegionMapModel.lua`, `RegionMapPaths.lua`,
`RegionMapConstants.lua`, `RegionMapCopy.lua`, `RegionMapArtwork.lua`,
`RegionMapSidePanel.lua`, `RegionMapPathPanel.lua`, `RegionMapStyles.lua`, `RegionMapPanel.lua`. Preserve and
coordinate any concurrent changes in these files when deploying.
