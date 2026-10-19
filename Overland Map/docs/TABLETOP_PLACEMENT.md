# Tabletop placement and window integration

The single existing Overland host can be placed and minimized on the personal Tabletop.
It keeps its content tree through window/fullscreen switches and minimization. It does
not create tactical maps, share placement, follow the Director, or create a second host.

## Placement and activation

Windowed Atlas cards use the engine's native drag threshold. The preview is drawn only
when `dmhub.panelDropSurface == "table"`; other UI and tactical map windows reject the
drop. Preview and commit use `Host:Placement`, with the saved size, pointer centering,
Font Size scale and the same work-area clamp. Escape cancels the drag before normal
Overland navigation. A crossed drag threshold suppresses the release-click even on an
invalid, cancelled or revoked drop.

Every permitted map card has a focusable, press-swallowing icon control named by its
tooltip **Open {map} on tabletop**. It is available to players and Directors in both
in-app views. The More menu remains Director-only. Native popouts use Return to app.
The non-drag action uses saved placement, or the existing centered default. A window
that cannot meet the minimum size leaves navigation unchanged and shows the size notice.

Minimize is available on the window title and fullscreen toolbar. It flushes valid edits,
ends pointer gestures, settles pending navigation and releases focus, Escape and the
fullscreen action-bar override. Import and unfinished-path drafts remain in the same
content tree. Permission, selection and layout reconciliation precede restoration.
Explicit activation raises a window and focuses it; fullscreen remains behind other
windows. Automatic restoration does not raise or focus the host.

Restore through the movable button, its rail entry, the permanent launcher, Ctrl+Tab
(including reverse switching), the Windows menu, or a valid incoming presentation.
Closing while minimized first restores the host to show the existing discard guard;
cancelling leaves it visible.

## Window state machine

`OverlandMapHost` keeps one state for the map: `closed`, `native`, `open`, `minimizing`,
`minimized` or `restoring`. Every change goes through one transition function, which
refuses moves that are not allowed, refuses moves by a replaced host, and saves `hostState`
only for viewer choices. The state itself guards late animation callbacks: a restore
finishes only while the host is still `restoring`. `minimizing` lasts until Tabletop
reports that the button has landed (`MinimizeExternal` option `done`); if Tabletop drops
that callback, reconciliation settles it once no flight is running. Automatic
restoration is tracked separately as viewer intent, not as a window state.

`OverlandMapTabletop` is the only file that calls `Tabletop`. It checks each feature on
its own: `provider` (Ctrl+Tab and the Windows menu), `minimize` and `place` (Atlas drops).
A build missing any one function of a feature hides only that feature.

## Personal persistence

The existing `overlandmap:preferences` per-game preference adds:

| Field | Value |
| --- | --- |
| `hostState` | `closed`, `open`, `minimized` or `native` |
| `selectionKind` | `atlas` or `map`; written together with `selectedMapId` |
| `minimizedPosition` | `{x, y}` in documents-layer units |

`inAppView`, `windowGeometry` and camera preferences retain their previous meanings.
Missing lifecycle fields never open a window automatically. Missing `selectionKind`
retains the legacy last-map/first-map fallback until an explicit selection. An unavailable
explicit target displays Atlas without replacing the saved target. Delayed data may
complete restoration only until a newer user action or presentation.

The module's lifecycle timer runs outside the collapsed host. It waits for the current
game, laid-out documents layer, readable preferences and map table; it does not wait for
loading progress to equal 1. Generic destruction, HUD replacement and Lua unload release
transient panels without writing `closed`. Only accepted close writes `closed`.

The movable button uses `overlandmapwindow:main`, distinct from the permanent launcher.
Rail slots remain owned by the existing rail-layout system. Unavailable or disabled rails
fall back to a clamped table button; teardown retains the slot and deliberate close
purges it. Native ownership respects live popouts and same-session `popoutwindows`
records. Fresh application launches do not recreate native windows.

Without the shared Tabletop capabilities, new affordances are hidden. An automatically
restored minimized layout falls back to a visible in-app host, retaining its preference
until the viewer acts or integration becomes available.

## Shared contracts

- `Tabletop.RegisterWindowProvider(id, ownerMod, collect)` replaces registrations by ID
  and returns an identity-safe unsubscribe. `ExternalWindows()` returns a deduplicated
  snapshot, isolates provider failures and guards activation against replacement,
  unloaded owners, invalid panels and changed game identity. Both the switcher and
  Windows menu consume these records; Overland registers `external:overland-map`.
- `Tabletop.ScreenToLayer(x, y)` requires valid screen dimensions and a laid-out layer.
  It returns nil when unavailable. The existing internal coordinate helper is retained
  for legacy Tabletop callers.
- `RefreshExternal(rec)` reconciles both button coordinates, scale, layer and rail
  presence. `buttonOps.placementChanged(rec)` lets the owner persist completed placement.
- `ReleaseExternal(rec)` cancels animations and removes transient buttons while retaining
  rail placement. `CloseExternal(rec)` also purges the rail slot.
- `MinimizeExternal(rec, from, options)` and `RestoreExternal(rec, to, done, options)`
  accept trailing `{animate = false}` and complete through the normal path immediately.
  Callers without options, including PDF viewers, retain animation behavior.

## Verification

Run `Overland Map/tests/RunOffline.lua` with the bundled Lua interpreter. The added
`TabletopIntegrationChecks` execute the production host and complete shared-interface
sections with isolated GUI/engine services. `TabletopContentChecks` exercise the real
shell, Atlas controls, preferences and presentation controller. These checks do not
simulate native input routing or prove rendered layout.

Coverage includes valid/invalid/cancelled drops, exact preview placement at 80/100/140%
scale, release-click suppression, player controls, Atlas/legacy/unavailable selections,
delayed data, drafts, minimized close cancellation, stale transitions, reload and game
changes, provider replacement/unload, switcher ordering, button movement, rails, layer
replacement, legacy PDF calls, startup focus and presentation retries.

Live integration remains gated by the connected build: `Tabletop` and `WindowSwitcher`
are not initialized, and the shared HUD CodeMod is not checked out. Registered file
names alone do not establish that these runtime capabilities are present. Required live
acceptance on a compatible build:

- Director/player access, no accidental sharing, native mouse drag and keyboard control
  activation, Ctrl+Tab/Shift+Ctrl+Tab, Windows menu and theme changes.
- Minimum window geometry and Font Size 80/100/140%, fullscreen minimize/restore,
  action-bar restoration and input reaching other windows.
- Present while minimized, including delayed sharing; rail docking/undocking and toggles.
- Rejoin, Lua reload and full restart with open/minimized/closed/native preferences;
  PDF minimize/restore and tactical map/scene switching.

The standard parent `tools/lua-typing/check.ps1` is absent. Validation uses the documented
LuaLS CLI with the repository configuration. See the
[test report](../tests/TABLETOP_2026-10-19.md) for results and deployment
evidence; unavailable checks must not be recorded as passed.
