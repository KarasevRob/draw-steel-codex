# Map-wide pin text and description previews

Status: IMPLEMENTED in the development checkout, 2026-10-15. User signed off on the
design. See [verification](../tests/PIN_TEXT.md). Cloud publication is separate.

The [text appearance contract](TEXT_APPEARANCE_BRIEF.md) extends the original
background choices below with independent outlines and uploaded static images.

## Goal and confirmed scope

Let the Director format every Location name on one map from one settings section,
and let viewers read a short description preview by hovering a visible pin.

- One shared setting belongs to the map whose pins are being displayed. It applies
  to all its direct Location pins, including player-owned Locations.
- No inheritance or propagation to parent maps or child maps. A Location's pin on
  its parent uses the parent's style; its own map controls the pins inside it.
- Name text keeps a fixed on-screen size during map zoom and still respects the
  viewer's Font Size preference.
- Names stay horizontal. Reuse the label editor's font, size, bold/italic,
  alignment, spacing, text color, and background controls, with size in UI points
  rather than a percentage of map width.
- Major, Normal and Minor names each have a separate exact size in that map's
  shared style. The Director sets all three values directly; no fixed ratios.
- Hover shows the Location name plus the beginning of its description, ending in
  `...` when text is omitted. Never use Director notes or linked-journal contents.
- Changes stay inside `Overland Map/`; no engine, core UI, or unrelated feature edits.

## Decision ledger

| Date | Decision | Basis |
|---|---|---|
| 2026-10-15 | One shared pin-name style per individual map, without parent/child inheritance | User's feature request |
| 2026-10-15 | Pin hover previews the first few description sentences, with an ellipsis when shortened | User's feature request |
| 2026-10-15 | Keep fixed on-screen name size as the map zooms | User selected the recommended option |
| 2026-10-15 | Keep pin names horizontal; no shared rotation control | User selected the recommended option |
| 2026-10-15 | Separate exact sizes for Major, Normal and Minor pin names | User requested Importance-based differences with measurements defined by the user |
| 2026-10-15 | Save each change immediately | User selected immediate shared saving over Preview/Apply |
| 2026-10-15 | Left/center/right name anchoring | User chose a meaningful anchor control instead of always-centered names |
| 2026-10-15 | Complete design, including two-sentence/300-character hover previews | User: "signed off" |

## Decided design

### Typography

- Director-only **Pin text** section within **Settings > This map**, also reached
  through the existing Atlas **Map settings...** action.
- Font, Major/Normal/Minor sizes, bold, italic, name anchor, letter spacing, text color,
  and Default / Auto contrast / Plate / None background, with a plate-color control.
- Preserve existing visuals when a map has no custom format. Reset removes its
  override. Unavailable fonts fall back for rendering without rewriting data.
- Keep pin icons, Importance, visibility, selection, name decluttering and the
  viewer's Show names override. Format both ordinary names and Name plate pins;
  Icon only retains its current name-visibility rules.
- Keep names single-line; do not change Location name validation or text content.

Default sizes stay Major 18, Normal 15, Minor 13 at Font Size 100. Each is independently
editable from 6 to 72 pt, with one decimal place; changing one never recomputes the others.
Size remains independent of map zoom. Letter spacing uses the existing label range,
0-100% of the font size.

Name anchor aligns the pin point with the name's left edge, center, or right edge.
Left grows rightward; Right grows leftward. Center is the current default. Icon names
stay below the icon. Name plates use the same anchor at their Location point. This
never changes stored coordinates, Party destinations or path snapping. Icon hit areas
stay the same; existing Name plate click behavior stays with its visible plate/text.

All format fields are optional overrides, not a switch to independent-label defaults.
Changing only Normal size must leave the current font, boldness, color, outline and
background alone. Theme default is available for font/color. Background Default keeps
the current halo for icon names and themed backing for Name plates. Explicit Auto,
Plate or None overrides the backing for both forms without stacking two backgrounds.
None intentionally leaves an iconless Name plate as plain clickable text. Pin form
still controls icon presence and name visibility. No per-pin format override is added.

Place Font, the three Size inputs, Bold/Italic and Name anchor directly in Pin text.
Put Letter spacing, Text color and Background in a compact Text appearance disclosure.
Use the existing single Settings scroll area, without a nested scroller. Reset is shown
when the map has overrides, alongside the standard Saved / Saving... / Not saved - Retry
feedback. The regular side panel still provides the full description without hovering.

### Description preview

Show the first two sentences, up to 300 Unicode characters of
description including the ellipsis. The name is separate and remains complete. Fold
whitespace and paragraph breaks into spaces, prefer a complete word at the cap, and
append `...` whenever description text remains. Empty descriptions show only the name.
Handle ordinary sentence punctuation and avoid splitting UTF-8 characters, decimal
numbers and common short abbreviations. Tooltip typography follows the app theme,
separately from map lettering. This is automatic behavior, not another map setting.

### Editing and lifecycle

Each valid completed control change saves immediately and updates all viewers of
that map. No Apply step. Retain normal guarded Undo entries. Numeric/hex input must
not save incomplete or invalid text. Coalesce pending picker changes while a prior
write is in flight, preserving the latest choice rather than dropping busy updates.
Keep the existing Settings scroll area usable in the minimum window. Reset to
defaults is immediate and undoable.

Use one write in flight per map plus a merged pending leaf patch. Rebase each dispatch
on the newest row; unrelated remote changes must not be overwritten with a stale form.
Reset is a deliberate whole-format operation. Remember Undo only for confirmed batches,
using the existing revision/mutation conflict guard. A failed write retains Retry;
permission loss, deleted/removed maps and unload cancel unsent work. Picker callbacks
capture map ID and generation so they cannot change a different map after navigation.

Store optional `pinNameFormat` on the existing map Location record. New maps start
with the normal default. Preserve custom format on Replace map image; clear it on
Remove map so a later Add map starts normally. Deletion/Undo restores the whole row.
Moving a Location between maps changes the style of its pin to the destination's;
its own map's pin-text style remains intact.

Malformed optional formatting must fall back safely without hiding an otherwise
valid map. New writes validate fields, reject invalid values, and require a Director
with an existing map. View as player cannot edit the shared format.

## Decision map

| Category | Treatment |
|---|---|
| Data and sync | Shared optional map field; direct-map lookup only; no migration or new table |
| Audience | Director edits; each viewer sees formatted pins they may already access |
| Surface | Existing This map settings; no new toolbar button or independent window |
| Controls | Existing label-format vocabulary; screen-relative size; no rotation |
| States | Defaults, custom values, reset, map change, permission loss, remote edit, reload |
| Copy | Reuse existing format labels; approve new section/scope/save/reset text in the final brief |
| Accessibility | Honor Font Size; readable backgrounds; regular side panel remains the non-hover route to descriptions |
| Performance | Restyle existing pin panels only when the normalized map-style key changes |
| Regression | Preserve pin forms, icon size, permissions, decluttering, Show names, camera and movement |
| Scope exclusions | Individual pin-style overrides, inheritance, label transforms, new hover-description field, journal excerpts |

## Settings sketch and copy

```text
Pin text
All location names on this map.
Font                 [Theme default       v]
Size (pt)            Major     Normal    Minor
                     [18.0]    [15.0]    [13.0]
[x] Bold             [ ] Italic
Name anchor          [Left] [Center] [Right]
> Text appearance
  Letter spacing (%) [0]
  Text color         [x] Use theme color
  Background         [Default v]
  Plate color        [color / hex]  (when Plate)
[Reset pin text]      Saved
```

Approved new copy: **Pin text**, **All location names on this map.**, **Size (pt)**,
**Name anchor**, **Text appearance**, **Theme default**, **Use theme color**,
**Default**, **Plate color**, **Reset pin text**. Reuse the existing font, importance,
bold/italic, left/center/right, spacing, color, background and save/retry strings.
All displayed copy remains in RegionMapCopy and the copy manifest.

## Independent critique resolutions

UX/Director and technical/accessibility reviews were completed before final review.
Their material findings are incorporated: meaningful anchoring; explicit background
precedence; sparse overrides preserving legacy visuals; exact tier sizes; queued,
permission-checked immediate saves with feedback; parent-format cache invalidation;
and safe defaults rather than treating optional formatting as structural map validity.
Reset must explicitly restore effective style properties, not assume assigning nil to
a native style enum clears it. Font/color defaults must track theme changes. Reuse the
existing constrained/scaled color picker so it fits the smallest map window.

## Implementation evidence

- `RegionMapCanvas.lua:570` and `RegionMapModel.lua:236`: rendering already selects
  only direct children of the open map.
- `RegionMapCanvas.lua:278`: name visibility is controlled by selection, Show names,
  pin form, Importance and zoom. Styling must not replace that policy.
- `RegionMapCanvas.lua:288`: current hover reads the description's first physical
  line. `RegionMapModel.lua:1293` rechecks viewer access before returning details.
- `RegionMapCanvas.lua:404,440,513`: normal and Name plate text are separate panels.
  Both need all resolved fields applied, including defaults when changing/resetting.
- `RegionMapCanvas.lua:510`: the per-pin signature lacks the parent map's format.
  Include a normalized format key so an edit restyles unchanged child records.
- `RegionMapConstants.lua:193`: legacy text sizes are Major 18, Normal 15, Minor 13.
  `RegionMapSession.lua:329` provides the established Font Size scaling path.
- `RegionMapLabels.lua:35,50,64` and `RegionMapLabelLayer.lua:77`: label format
  vocabulary, safe fallback, available fonts, character spacing and background
  rendering already exist. Label map-relative size is unsuitable for pin names.
- `RegionMapRecords.lua:57` and `RegionMapModel.lua:505,560,757`: existing record,
  normalized updates, field clearing and map-settings write patterns.
- `RegionMapPopovers.lua:217,322,522,617`: Director-only This map settings live in
  the existing scrollable, height-clamped popover.
- `RegionMapModel.lua:727,1109`: Replace image preserves map-owned fields; Remove
  map needs an explicit clear for this optional setting.
- `RegionMapPanel.lua:430`: breadcrumb preview is a useful presentation precedent,
  but its byte slicing must not be copied into Unicode-safe sentence truncation.
- External precedent: Foundry's Map Notes expose font, size, color and anchoring.
  This supports the control vocabulary, not this mod's per-map storage design.
  [Official Map Notes documentation](https://foundryvtt.com/article/map-notes/).

Source anchors record the pre-implementation audit and may shift after edits.

## Verification plan

Test one map with a parent and nested map: changing one style affects only its
direct pins. Cover normal/plate/icon-only names, existing/default/malformed format,
unavailable font, reset, Undo, replacement/removal, player view and a remote change.
Check short/long/multiline/Unicode descriptions, sentence boundaries and empty text;
hidden pins and Director notes never enter a player's tooltip.

Inspect the actual settings and pin text at ordinary/minimum window width and
Font Size 80/100/140. Compare zoom levels to confirm fixed on-screen text size.
Use a bounded disposable fixture and stop when these checks pass; do not repeat
the unrelated Atlas-shortening tests. Run syntax, ASCII and available mod typing.
