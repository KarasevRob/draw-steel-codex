# Overland Map review follow-up

Continues `9ec2ced9` and its type corrections in `98e625ea`. This record describes the
offline review follow-up. The subsequent [live validation and publication record](../tests/LIVE_REVIEW_2026-10-17.md)
supersedes its deferred-live status. Git commits and pushes do not publish the CodeMod.

## Completed in the continuation

- Preview retains at most 100 skipped reasons and 100 duplicate names, shows exact totals,
  and never builds one panel per rejected entry. File import reads once and parses that
  text. Paste-limit messages use `importTextLimit`.
- Import disables its toolbar action while running and releases the lock before final
  UI reporting. Failed batches still attempt descriptions and notes for confirmed pins.
  Undo removes eligible confirmed pins independently, preserving pins whose row or
  sidecar changed, including edits between batches. The [import contract](IMPORT_FORMAT.md)
  documents non-atomic writes, timeout uncertainty, and retained sidecars after Undo.
- Travel sorting uses the shared case-folded name key. Log-menu IDs include the entry ID.
- Component rules live beside their constructors; `RegionMapStyles` retains common
  controls and assembles the root cascade. The move preserved all 251 style rules apart
  from replacing static font sizes with theme size classes. Canvas text still uses its
  user-selected/map-relative dimensions. No runtime files were added or reordered.
- Offline coverage now includes import commit/failure paths, 50,000 invalid entries,
  window Esc ownership and off-layer dragging, unknown pin-format fields and grouped Undo.
  A single runner and a GitHub Actions workflow execute the seven offline suites.
- Retired TECH_TASK IDs, missing output links and machine-specific evidence paths were
  removed. Old performance measurements are explicitly historical.

## Existing fixes retained

The preceding commits supply shared row writes, the Labels/PinText save queue, companion
hooks for cascades and Undo, fallback label formats, player leaf-patch rebasing, slider
release saves, targeted label updates, lazy image panels, navigation-independent artwork
retry and a window host with explicit focus ownership. Location/path side-panel autosave
still has store-specific controllers; further consolidation remains a maintenance item.

Stored names now accept up to 1024 Unicode characters independently of the 256-character
editor/write limit. This makes upgraded readers tolerant of future editor changes; it
cannot change an already-installed older client's 80-character validator. Clients using
that older build still need upgrading before sharing longer names.

## Host contract

`RegionMapPanel.Create` receives immutable host callbacks (`close`, `popOut`, `popIn`,
`toggleView`) and the initial mode. Content owns its own current mode and engagement
state. The host sends `regionMapHostMode(mode)` and `regionMapHostActive(engaged)` events;
`requestClose(continue)` flushes edits and checks import drafts before invoking the host
continuation. Switching fullscreen/window keeps the same content instance.

## Validation

- Seven offline suites: 115 checks passing. These use production Lua with in-memory
  engine substitutes and do not establish live input, networking or rendering behavior.
- Syntax and ASCII: all 40 runtime/test Lua files passed. Local Markdown links and
  `git diff --check` passed. All 251 component rules assembled in an isolated style check.
- Whole-repository LuaLS 3.19.2: zero problems, with all four worker results verified by
  the CI reporter. The checked source export contains every tracked file plus this
  change's new files, and its Lua bytes match the staged sources. The documented parent
  `tools/lua-typing/check.ps1` is absent; the direct CI command was used instead. The
  installed 3.19.1 binary was replaced for this run by a temporary official 3.19.2 download
  whose SHA-256 matched the release metadata.
- A preliminary direct workspace scan found nine problems only in unrelated untracked
  `output/segmented-stamina/` scratch files. Those files were left untouched and are not
  part of the checked source export or this commit.
- No live app changes, deployment or cloud publication were performed in this continuation.

Before merge, run two-client text/visibility races, foreground-panel Esc and focus,
off-layer title dragging, theme/font-size layout, actual parser/file-picker and upload
failure paths, and current 250-pin/image-label rendering timings. Whole-row versus
field-diff server upload semantics remain unverified without the engine/client test.

## Merge notes

Use a squash merge of the feature branch. The earlier `9b156d2` snapshot references
artwork code introduced in `18d1409`, and WIP commits intentionally represent partial
work. This continuation does not rewrite the published branch history.

The earlier terse commits included four user-visible changes: names accept 256
characters, Show route defaults off, path editing is Director-only, and Atlas cards have
map-action menus. Include these in the squash description/release notes along with the
review fixes; do not describe the branch as styling-only maintenance.
