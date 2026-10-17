# Overland Map - Remaining maintenance candidates

The 2026-10-10 audit led to the completed shared-controls, pooling, preference and
dead-code cleanup. Its task lists and completed commit log have been removed.
The candidates below remain useful leads; their old line numbers and counts are
obsolete. Reproduce or recheck each against current code before changing behavior.

## Behavior checks still needing evidence

- Reduce motion: confirm that Go to the Party saves the resulting camera.
- Arrow-key panning during a camera animation: confirm the animation yields to input.
- Import versus typed names: confirm whether internal line breaks should be rejected
  or folded consistently.
- Closing the whole window while typing a log note: confirm the draft is flushed.
- Narrow layouts: compare selection keep-visible offsets with the actual panel inset.
- Large imports: measure the batch-create path and sidecar writes in the live app.

These are inherited audit findings, not a claim that the current build reproduces
every issue. Fixed route-dot attachment and preference-copy findings are omitted.

Review follow-up on 2026-10-17 reproduced B4 (case-sensitive Travel sorting) and fixed
it with the shared name key. B5's duplicate log-menu IDs now include the entry ID.
Both are covered by the isolated import/maintenance suite. Import names reject controls,
bidi marks and internal line breaks; the preview caps diagnostic rows.

## Possible consolidation

- Row writes and Undo entry construction across Locations, paths, log entries and
  sidecars. Preserve each table's removable-field rules, invalidation scope and
  whole-row Undo behavior.
- Location/path autosave controllers and side-panel frames. Location edits span
  multiple stores; path edits do not.
- Image selection wells, guarded busy retries and deletion planning. Confirmation
  counts must agree with the model's actual cascade.
- State-document access helpers. Preserve the persisted revision schemes.
- Tool and panel-mode dispatch if another interaction mode justifies it. Preserve
  the distinct pin, Party and empty-canvas behavior.
- Context boundaries where components call sibling UI modules directly.
- Theme contrast for destructive actions and image wells, and remaining copy
  assembled outside RegionMapCopy.

No refactor is scheduled by this document. Recheck existing shared helpers first;
subsequent features may already have removed a proposed duplication.

## Constraints worth retaining

- Do not merge the row, state-key and Party revision schemes casually.
- Keep the log's narrow invalidation and audited whole-row Undo restores.
- Camera, Party and crossfade easing serve different purposes.
- Preserve NaN handling in the model's numeric helpers.
- Keep performance-sensitive position changes on panel.x/y; a selfStyle write
  can restyle an entire layer. See [README performance notes](../README.md#5-performance).
- Measure before changing pooling, cache signatures, sliding or zoom layout.
- New runtime files require live CodeMod registration; file splitting alone is
  not a reason to introduce a new module dependency.
