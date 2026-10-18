# Text appearance verification

Date: 2026-10-16. Connected Codex build 10; Overland Map development checkout.

## Automated checks

- `TextAppearanceChecks.lua`: 13 checks covering outline defaults, validation, atomic
  image activation, Director-only image fields, player-owned text/outline edits, remembered
  formats, permission loss, Undo, unavailable references, queued remote edits, fit/crop
  geometry, image removal, manual sizing, loading generations/Retry and tooltip ownership.
- Existing Label checks: 18 passed. PinText checks: 15 passed. Artwork checks: 27 passed.
- All 31 runtime Lua files pass Lua 5.4.7 parsing and ASCII checks.
- `../dependencies/check-mod.ps1 -Mod 'Region Map'`: zero problems. The prescribed
  `../tools/lua-typing/check.ps1` is absent; this is a module check with the rest of the
  codex loaded as a library, not the unavailable whole-codex check.

## Live evidence

- Registered RegionMapTextAppearance before RegionMapLabels; confirmed the live 31-file
  order. Deployed sources were compared against CodeMod localContents after F4 reload.
- Used a private temporary map with three Importance-tier pins (including a Name plate)
  and one independent multiline label. Existing transparent wide artwork and portrait
  artwork exercised aspect ratios without uploading permanent test assets.
- Fit preserved the whole image; Fill centre-cropped; Stretch changed proportions.
  The loaded transparent image retained alpha with no forced plate behind it.
- Berling, Courier and Liberation Sans rendered configurable contours. Changing font,
  thickness and None/Custom rebuilt the text leaf without retaining the old material.
  Thick Courier outlines consume much of the glyph face, matching the research evidence.
- Manual image width remained 52.0533 local screen units after changing label text size
  from 4% to 5%. Text overflow stayed visible. Rotation and offsets followed the label.
- Selection included offset artwork. Hit checks selected the image, ignored the empty
  corridor between text and image, and ignored the image at zero opacity.
- A real pointer click on the offset Name plate image selected its Location. Icon pins
  retained their original hit discs.
- The chooser opened its upload/library interface. Selecting an existing asset through
  its SetValue/change path saved the ID and retained layout. Cancelling then invoking a
  captured late callback left the stored ID unchanged.
- Inspected the existing editors at fullscreen/100% and minimum 720x480 window geometry
  at 80%, 100% and 140% Font Size. Controls wrap/scroll within their panels. Also inspected
  the High Contrast scheme; local slider tracks use the theme border colour.
- A temporary native layer containing 250 real PinText compositions loaded all 250 image
  views. Ten subsequent parent translations caused zero additional image Load calls and
  zero recreated text leaves. This is a rebuild/load check, not a GPU/FPS benchmark.

## Bugs caught and corrected

- Initial native label measurements can still be 100x100 when a scheduled callback runs.
  Measurement now also follows the completed `rendered` event; cached text bounds matched
  the actual 447.90 x 153.61 native text size in the reproduction.
- The user reported a Normal town tooltip remaining over the tactical map after closing
  Overland Map. Reproduced: forwarded image hover put the tooltip on the parent pin; it
  survived pointer leave and pin destruction. Hover now assigns the tooltip to the actual
  hit surface, with explicit dehover/press/destroy cleanup. Verified tooltip destruction
  after a real pointer leave and when closing the map while still hovered. Removed the
  orphaned tooltip from the earlier build; the UI search then found zero matches.
- A cancelled picker previously accepted a captured delayed callback. The picker now
  checks its open lifetime and invalidates its generation on cancellation.

## Limits

No second client was available, so cross-client asset access and late-join rendering were
not exercised end to end. Player authorization, remote-edit rebasing and queue revocation
were checked in isolated production-model fixtures. The native OS file chooser and a
fresh image upload were not automated; the feature reuses the existing journal-image
upload/paste/library workflow. No performance claim is made for hundreds of unique textures.

## Cleanup

The temporary density layer is destroyed. The private test map, its pins and label are
removed through the model's deletion/cascade workflow. Original preferences, font size
and colour scheme are restored; Overland Map is left closed.
