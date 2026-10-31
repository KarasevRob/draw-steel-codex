# Native popout wheel delivery: engine handoff

Status: reproduced and isolated on 2026-10-14. The Overland Map mod now handles
panel-scoped wheel events, which work in the main window. The installed engine
does not deliver those events to its canvas in a native popout. No engine source
or binary was changed. Engine access is currently reserved for the label feature.

## Reproduction and measured behavior

1. Open an existing Overland Map, with the pointer over the map canvas rather
   than a scrolling editor or side panel.
2. Use a physical Windows mouse-wheel notch in the main application. Observe a
   single canvas `wheel` callback and one zoom step.
3. Choose Pop out, focus the native Overland Map window, and repeat over its canvas.
   Hover and click still work, but no canvas `wheel` callback arrives and zoom
   stays unchanged.
4. Return to app and repeat the main-window control check.

The live map was Broadhurst. The native HWND under the cursor and its foreground
focus were verified; its canvas reported hover and a valid local pointer position
near (0.5, 0.47037). This rules out testing the wrong window or missing its canvas.

The main-window control test delivered Lua delta 720 from one Windows notch
(raw delta 120). Overland zoom changed from 2.66001988046875 to
3.05902286253906, exactly x1.15; tactical-board zoom stayed 5.06805372238159.
The mod uses the wheel direction for one step, not the raw magnitude.

The bridge's synthetic `mouse` wheel action also failed to deliver a normal
panel wheel callback in the main window. Use physical OS input for the final
comparison; directly firing the Lua event only checks the mod's zoom math.

## Evidence in the installed engine

Read-only IL inspection used this assembly:

```text
D:\SteamLibrary\steamapps\common\Draw Steel Codex\Codex_Data\Managed\Assembly-CSharp.dll
SHA256 DF5BA6D9A4055085389A17E8ADA2105AC4F3C15C7CBBDB18E7135D5D89834E34
```

No engine source checkout was available. IL offsets below identify this build;
locate the named methods in the engine source rather than treating offsets as
source line numbers.

| Method | Observed behavior |
|---|---|
| `NativeWindowCanvas.UpdateMousePosition` | Adds native wheel input to `SheetRaycaster.synthesizedWheelDelta`. |
| `SheetRaycaster.DispatchSynthesizedEvents` | Selects a wheel target from raycast hits only when `GetComponent<ScrollWheelCollision>` succeeds (IL_0127). It stores that target in local 6, searches its parents for `IScrollHandler` (IL_01DF-0207), and dispatches only if that target exists (IL_04BF-0510). |
| `SheetPanel.OnScroll` | Handles scrolling, fires Lua `wheel` with `eventData.scrollDelta.y`, and bubbles to the parent when unhandled. This is the normal main-window path that reached the map. |
| `LuaInterface.get_mouseWheel` / `InputController.ScrollWheel` | Reads Unity's main-window `Zoom` input axis, gated by `mouseOverGameWindow`; it does not include the native synthesized delta. |
| `SheetScrollView.ScrollByWheel` | Scrolls a scroll container directly. Enabling a scroll view would change canvas behavior rather than repair generic panel event delivery. |

The map canvas has a `SheetPanel` scroll handler, but no `ScrollWheelCollision`
marker. The canvas and all inspected native ancestors had vertical scrolling
disabled. Consequently the synthesized dispatcher never selects its handler.
This explains both the missing Lua event and why the previous global wheel poll
could not support native popouts.

## Mod-side change already made

`RegionMapCanvas.lua` receives `wheel` on the canvas and forwards it to
`WheelZoom(delta, mouseX, mouseY)`. Cursor anchoring, zoom limits and camera-save
debouncing remain in that path. It consumes the canvas event so a main-window
notch does not also zoom the tactical board. The former `dmhub.mouseWheel`
polling path was removed.

This is verified for main-window physical input. It cannot make the native
dispatcher emit an event that it currently skips. The existing +/- camera
buttons are the available zoom workaround while the engine issue remains.

## Proposed engine change, not implemented

Inspect `SheetRaycaster.DispatchSynthesizedEvents` and retain its current
`ScrollWheelCollision` / scroll-view priority. When that pass finds no explicit
wheel target, select the first eligible `IScrollHandler` in the ordered raycast
results for the same window, searching each hit's ancestors in the same way as
the existing dispatch. Then use the existing pointer event and scroll dispatch.

The intended outcome is parity with normal Unity main-window panel routing:
plain panels can receive wheel events, while controls with dedicated scrolling
keep priority. Confirm hit ordering, visibility/interactivity filtering and
scroll-view handling against the actual engine source before implementing.
Do not add a hidden scroll container to the mod or process the same delta through
both the synthesized path and the global wheel getter.

## Verification after an engine fix

- Physical wheel over the native map produces one callback and one x1.15 zoom
  step, with the same cursor anchor as the main window. Reverse direction zooms
  out. The board and other windows do not react.
- Native lists, scroll views and text editors retain their normal wheel behavior;
  nested controls do not dispatch twice. Check numeric-input Ctrl-wheel and
  horizontal wheel input as well.
- A foreground modal or overlay receives input according to normal hit ordering;
  wheel does not leak through to the covered map. Title/resize chrome consumes it.
- Main-window canvas and scroll controls retain their current behavior, including
  board wheel input outside the in-app Overland Map window.
- Re-run the bridge synthetic-wheel check separately. Its result should not
  substitute for physical native-window verification.

The remaining keyboard retest for the in-app window is tracked separately in
[the window brief](PANEL_VIEW_BRIEF.md); it is not evidence of a wheel fix.
