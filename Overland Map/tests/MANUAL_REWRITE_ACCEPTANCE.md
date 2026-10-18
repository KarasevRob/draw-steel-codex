# Overland Map manual acceptance

Status: pending human testing, by user direction on 2026-10-18. Use one client only.
The automated and bridge-driven evidence is in [the live record](LIVE_REWRITE_2026-10-18.md).
The comparison with pre-rewrite performance is separately deferred; it is not a
prerequisite for recording these manual results.

## Setup and recording

Use the current developer deployment, record the app version, OS, host mode, Font Size
and theme, and create disposable maps. Include two pins connected by a bent path, a
label, compass and calibrated scale bar. Put a path handle beneath a pin or Party
to exercise overlap. Keep existing user maps out of the fixture.

For each item, record Pass/Fail/Blocked, host, exact steps and observed behavior.
Leave unperformed items unchecked. After a failed gesture, record whether one Undo
restores the original value, whether the map changed, and whether an extra click
opened a reader or editor. Do not count a bridge event as a physical-input result.

## Pointer and gesture checks

- [ ] Click a pin with no motion, then with motion smaller than the drag threshold.
  It opens its reader without moving the pin. A real drag moves once; release does
  not also activate the pin, and one Undo restores the original position.
- [ ] Double-click an unlocked editable pin. Its editor stays open after release.
  A later single click opens the reader normally. Repeat locked and in View as
  player; unauthorized editing must remain unavailable.
- [ ] Drag a selected path bend and insertion handle where they overlap a pin or
  Party. The handle wins; the pin/Party stays fixed. Right-click a selected bend to
  remove it once, then Undo. Ordinary pin/path/label overlap keeps its existing order.
- [ ] Drag/resize/rotate a label and compass with their editors closed, then open
  the editor and compare numeric values. Move the scale bar; its Distance and measured
  endpoints retain the same length. Test the None background on bright/dark artwork.
- [ ] Move Party on a free map, including snapping near a pin. Verify one movement
  and one Undo. On a point crawl, dragging must retain the established travel behavior.
- [ ] Use left/right/middle buttons in their supported roles, context menus and
  panning. No unsupported button should cause a movement write or extra commit.
- [ ] Leave the canvas while holding a drag, return, then release. Repeat by leaving
  the native window and releasing outside it. No preview should stick or commit twice.
- [ ] During a drag, press Escape, move focus elsewhere, open a foreground dialog,
  switch hosts, resize, close the view, and Alt-Tab away (separate attempts). Verify
  cancellation, unchanged authored values, and no stray release action on return.
- [ ] Exercise ruler and calibration with both two-click and drag workflows.
  Measure on rectangular artwork at Fit and 20x; cancellation must leave no new
  calibration or unfinished preview.

## Keyboard and transitions

- [ ] Tab and Shift+Tab through Name, Description, Director notes and host controls.
  Focus is visible, reachable controls are not skipped, and typing stays in the
  focused field. Repeat in fullscreen, minimum in-app window and native popout.
- [ ] Activate focused host buttons with Enter and Space. Exactly one activation
  occurs, without a tactical shortcut firing behind the view. Check native popout
  independently; the installed engine's native keyboard path is not yet verified.
- [ ] Check Escape order: popup/dialog, active gesture/tool, editor/selection, map
  navigation, then host close. Cancelling a pin drag must not also leave the map.
- [ ] Enter numeric label/aid size, angle and position values, including bounds and
  invalid text. Use field exit/confirmation and verify saved values and one Undo.
- [ ] Type an unfinished valid Location/path/label edit and immediately navigate,
  select another record, close the editor or transfer hosts. It saves to the original
  record. A blank unsent creation draft is discarded without creating a row.
- [ ] Resize and toggle fullscreen/window while editing text or drawing an unfinished
  path. Keep the same draft, selection and focus. Import text must survive resizing;
  closing or native transfer must retain its explicit discard guard.
- [ ] Close a log note editor after typing. Reopen it to verify save-on-close. Check
  import Cancel/Back/Discard and native clipboard/file-picker cancellation separately.
- [ ] Use View as player while editing and while hovering restricted content. Hidden
  records, routes, notes and stale images disappear promptly; no forbidden action
  becomes available. Return to Director view and verify only permitted edits saved.

## Host and visual checks

- [ ] At Font Size 80/100/140%, inspect fullscreen, the 720x480 logical in-app minimum
  and native popout. Test long names/north text, scale-label collisions, scrolling,
  bright/dark/dense artwork and contrasting themes. Controls and editing handles
  remain reachable; artwork dimensions and measured distances remain unchanged.
- [ ] Move and resize the in-app window, close/reopen it, then use Reset window.
  Geometry persists and Reset restores a visible default window. A background window
  raises before closing. Native return opens exactly one active map view.
- [ ] Toggle Reduce motion and repeat Fit, nested-map navigation and idle controls.
  Reduced motion avoids camera transitions/control fading without changing geometry.
- [ ] Check native-popout wheel scrolling/zoom. If still unavailable, record the
  existing [engine limitation](../docs/POPOUT_WHEEL_ENGINE_HANDOFF.md), not a pass.

## Finish

Remove only the disposable records, restore theme/font/window preferences, and record
the completed matrix in the live verification record. Report engine limitations and
unperformed cases explicitly. Do not introduce a second client or publish the mod.
