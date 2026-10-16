# Text appearance: outlines and uploaded backgrounds

Design agreed 2026-10-15/16. Status: IMPLEMENTED. Scope: Overland Map only.

This is the current contract. [Research notes](TEXT_APPEARANCE_RESEARCH.md) retain
engine findings and the unresolved custom-font investigation.

## Decisions

- Labels retain individual formatting, map-relative size, rotation and ownership. Pin
  text retains one style per map, fixed screen size, horizontal names and exact
  importance-based font sizes. No parent/child inheritance.
- Outline modes are Default, None and Custom. Custom has a colour/alpha picker, hex
  input and thickness slider plus number, 0-100 in steps of 1 (UI value / 100 gives native width,
  not pixels). Initial Custom thickness is 10; initial colour contrasts with text.
  Missing overrides preserve legacy appearance. Custom outline works with every backing.
- Users upload arbitrary supported still artwork or choose a library image. No prepared
  scroll template is required. Font uploads, animation, tiling and nine-slicing are excluded.
- Image defaults: Fit, Automatic sizing, horizontal/vertical padding 50%/25% of text size
  per side, zero offsets and 100% opacity. Fill centre-crops; Stretch distorts to fill.
- Manual label dimensions start at the current automatic box and use map-width fractions.
  Manual pin dimensions start at 180 x 30 pt and apply equally to every importance tier.
  Manual image dimensions remain fixed when text changes or the label resize handle moves.
  Text never clips, shrinks or changes wrapping to fit an image.
- Offsets use the same units as manual dimensions; positive X moves right, positive Y
  down in the label's local coordinate system. Padding is Automatic-only.
- Controls live in the existing editors. The map is the only preview. No Apply button.
- Directors control ALL image configuration. Player owners may still edit text and
  outlines. An active Director-managed image freezes background-mode controls for players.
  Existing label movement, rotation and deletion remain available under existing rules.
- Switching modes retains image settings. Replacement retains layout. Remove clears image
  settings and returns to label Auto contrast or pin Default without deleting the asset.

## Rendering and persistence

Text and image are separate siblings. Labels keep their text-centred origin; selection
encloses both rectangles, resize uses text bounds, and rotation uses the saved origin.
Hit testing excludes the empty corridor between offset rectangles and excludes unloaded
or zero-opacity art. Icon hit discs stay unchanged; name-plate art forwards interactions
to its Location. Pin name anchoring does not move with the art.

Optional flat appearance leaves extend the existing label record and map pinNameFormat.
The new helper is registered immediately before RegionMapLabels. No schema migration or
rewrites of existing rows are required. Store library asset IDs, never local paths.
Availability is a rendering concern, so missing/deleted/unreadable assets retain their
saved references. New asset selections validate read permission and reject video.

Existing queues, receipts and guarded Undo are reused. Selection plus Image mode is one
patch; removal is one patch. Player restrictions also cover writes, remembered formats,
queued work, Retry and Undo. An image-load retry does not save data.

Streamed images keep readable text during loading or failure. Loaded images preserve
their own transparency. Loading has a 10-second timeout and local Retry; callbacks check
generation, panel lifetime and module unload. Native text leaves are recreated on font
or outline-material changes. Geometry is cached and panning does not reload images.

## Validation contract

Run appearance permission/geometry tests, existing Label/PinText/Artwork checks, runtime
syntax and ASCII checks, and available module type checks. Verify live image fitting,
alpha, offsets, opacity, text overflow, outline/font transitions, picker lifetimes,
manual resize semantics, anchoring and actual click behavior. Inspect minimum window and
80/100/140% Font Size. Verify reload/asset loss and another client where available.
Remove fixtures and restore user preferences after verification.

Verification results and remaining environment limitations are recorded in
[TEXT_APPEARANCE.md](../tests/TEXT_APPEARANCE.md).
