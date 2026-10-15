# Text outlines, uploaded fonts, and decorative backgrounds

Research date: 2026-10-15. Status: RESEARCH, not an implementation brief or approval
to change runtime behavior. Scope: Overland Map (`Region Map/`).

## Findings

| Capability | Finding | Remaining work |
|---|---|---|
| Outline colour and thickness | Feasible within the mod. A fresh live preview confirmed per-glyph outlines in three fonts. | Format fields, controls, material refresh handling, and fine thickness calibration. |
| Upload and use a TTF/OTF font | No supported runtime route found in the exposed mod API. Current choices come from the app build. | Engine/API support, or confirmation of an undocumented packaged-font workflow. |
| User-uploaded image background | Feasible within the mod using the existing image library and GUI image surfaces. | General image fit/padding rules, upload/selection UI, and loading fallback. |

The user confirmed **still images** and clarified that users upload their own background
artwork. A scroll/banner is only an example; the feature must accommodate arbitrary
supported still images without requiring a prepared template. No runtime files, game
records, preferences, or uploaded assets were changed during this research. A temporary
outline comparison panel was mounted, inspected, and removed without reload.

## Existing decisions retained

- Independent labels keep per-label formatting, map-relative size, rotation, multiline
  text, existing authorship rules, autosave and Undo.
- Pin text keeps one shared format on the current map, independent of parent/child maps,
  fixed screen size during zoom, horizontal text, user-defined Importance sizes, and
  immediate saves. Only Directors edit this shared format.
- Styling does not reveal hidden content or change Location coordinates, path snapping,
  icon size, decluttering, or the Show names preference.

These extensions serve Directors who want more control over map lettering; existing
maps should continue to look the same until their styles are edited.

## 1. Outlines

### Verified capability

The native styles expose `textOutlineWidth` and `textOutlineColor`
(`Definitions/Style.lua:29-30,70`). The public declaration does not specify pixel units
or a validated range. Existing call sites use values including 0.1, 0.3, and 1.

Live probe on the connected build 10: fresh 32-point labels, white text, magenta outline,
widths 0, 0.1, 0.3, 0.6 and 1, in Berling, Courier and Liberation Sans. Observed:

- At zero, there is no magenta outline.
- Nonzero values draw contours around individual glyphs; there is no rectangular plate.
- The same value has markedly different visual weight across fonts. Courier is already
  almost filled with outline colour at 0.3; Liberation Sans fills substantially at 0.6;
  Berling retains a visible white face even at 1.

This directly supersedes the broad claim in two DocumentSystem comments that these
properties always produce a slab (`DocumentSystem.lua:8868-8872,13185-13192`). The older
label brief correctly records its earlier experiment; it is not evidence that outlines
cannot work in the current rendering context.

Unity documents outline thickness as affecting both sides of the glyph contour, which
is consistent with the observed loss of white fill at larger values. This is supporting
engine context, not proof of DMHub's exact numeric conversion.
[TextMeshPro distance-field outline documentation](https://docs.unity.cn/Packages/com.unity.textmeshpro%404.0/manual/ShadersDistanceField.html).

### Proposed mod implementation

- Add optional outline colour/width overrides to the existing label format and the
  map's `pinNameFormat`. An explicit zero disables the outline. Missing pin overrides
  retain the current behavior: normal names use the theme-coloured 0.3 halo in Default
  background mode; Name plates and explicit backgrounds have no halo.
- Expose fine thickness adjustment and the existing alpha-capable colour picker, with
  a preview in the selected font. Do not label the native value as pixels without a
  measured conversion. Final range, units, defaults, and wording are still design choices.
- Keep outline controls independent of background mode: a user can intentionally put
  outlined lettering over their uploaded image. Existing appearance remains the fallback when no
  new outline settings exist.
- Reuse both save queues and guarded Undo. Add new leaves to format validation and the
  render signatures; preserve safe fallback for malformed optional data.

The pin renderer already replaces its text leaves when changing font or removing an
outline because the native component can retain the previous material
(`RegionMapCanvas.lua:518-532`, `tests/PIN_TEXT.md`). Extend that mechanism to the new
effective outline state. Independent labels need equivalent handling for their text
child while retaining the parent transform, selection, and measurement lifecycle.

A label's outline should scale with its map-relative text transform; a pin's outline
should remain screen-relative with its name. These are the intended semantics. Exact
thickness at small/large zoom, rotation, Font Size changes and alpha still needs the
feature's targeted acceptance pass. The current probe establishes feasibility, not a
pixel-accurate thickness contract or all-font compatibility.

### Relevant code

- `RegionMapLabels.lua:35-70`: current label format/defaults and safe reads.
- `RegionMapLabelPanel.lua:60-118`: numeric and colour controls.
- `RegionMapLabelLayer.lua:61-113`: text/background children, cached binding, deferred
  measurement; native outline is currently forced to zero.
- `RegionMapPinText.lua:10-39,192-228`: sparse pin format, effective defaults, and drawing.
- `RegionMapCanvas.lua:510-586`: pin binding and parent-format invalidation.

## 2. Uploaded custom fonts

### What is supported now

`gui.availableFonts` is documented as the font IDs configured on GameConfig for the
current white-label build (`Definitions/gui.lua:5`). It is not a list of the user's
Windows-installed fonts. The connected app currently exposes 15 IDs:

```text
colvillain, gothville, metallord, book, display, berling, newzald, tengwar,
drawsteelglyphs, drawsteelpotencies, courier, liberationsans, dwarvishrunes,
goblinscratch, infernalscript
```

Both mod editors use this list; arbitrary new names are rejected on write or fall back
when read (`RegionMapLabels.lua:75-82,200-206`, `RegionMapLabelPanel.lua:47-53`,
`RegionMapPinText.lua:51-58`). A font name or local file path alone does not load a font.

The generated API and working call-site searches found no TTF/OTF font upload, import,
registration, or font-asset class. A file picker returns a path, but no exposed font
consumer follows it. CodeMod resources expose `images` and an Images editor rather than
a font-resource workflow (`Definitions/CodeModInterface.lua:4-12`,
`DMHub Compendium/CodeMod.lua:1361-1481`).

There is one unresolved lead: `Definitions/Style.lua:19` mentions module-supplied fonts
by asset name. No public CodeMod upload API or shipping example found in this checkout
explains how to supply one. This may describe packaged engine assets; it does not prove
a Director can upload a font in a game. Engine source is unavailable at the checked
checkout locations, so the conclusion is **no confirmed mod-only upload route**, rather
than an assertion that every possible packaging route is impossible.

### What genuine support would require

Unity has lower-level source-font loading and TextMeshPro font-asset creation facilities.
That makes an engine extension plausible, but those facilities are not exposed by this
mod API. [FontEngine source-font loading](https://docs.unity3d.com/ja/current/ScriptReference/TextCore.LowLevel.FontEngine.LoadFontFace.html),
[TextMeshPro font-asset creation](https://docs.unity3d.com/ja/Packages/com.unity.textmeshpro%403.0/api/TMPro.TMP_FontAsset.CreateFontAsset.html).

An engine handoff should establish upload/storage of the font file, a stable shared font
ID, download/cache behavior for every client and late joiner, glyph/material generation,
font family/weight/style metadata, fallback for missing glyphs/assets, resource limits,
and a change notification so open font dropdowns can refresh. This work exceeds the
current mod-only implementation scope.

For precedent, Foundry introduced an Additional Fonts workflow with upload, family,
weight and style metadata and integration into font selectors. That is a useful UX
pattern, not evidence that DMHub supports the same mechanism.
[Foundry 10.270 release notes](https://foundryvtt.com/releases/10.270).

A mod-only alternative is pre-rendered lettering in a transparent image or baked into
the map. It preserves visual identity across clients but loses editable font text;
an independent image-label overlay would itself be a separate feature.

## 3. User-uploaded still image backgrounds

### Supported path

The existing journal-image library picker accepts uploads and library selections
(`DMHub Core UI/IconEditor.lua:842-878,1138-1164`). Region Map already uses that path
for maps and artwork. GUI panels support `bgimage` and `bgimageStreamed`, and normal
blending supports image alpha (`Definitions/Style.lua:9-10`, `Definitions/Panel.lua:25`).

Store a shared image asset ID, never a machine-local path. Add an Image background mode
to each independent label and to the shared map pin format. Users upload their own
supported still image or select one already in the library. Preserve its colours and
transparency with a neutral white tint. Keep the text above it; image fitting and text
padding must accommodate arbitrary artwork. PNG alpha is useful for irregular edges,
but a scroll shape, transparent image, or prescribed template is not required.

For labels, the existing background parent can own the image and continue to rotate and
scale with its text. For pins, the two existing name forms need the same background
settings. A separate image child may be needed to preserve a solid loading fallback
without covering the text. Keep regular icon targets unchanged; retain Name plate
clickability over its visible text/background area.

### General image fitting

| Method | Suitable use | Tradeoff |
|---|---|---|
| Stretch the complete image | Artwork intended to fill the text area | Changes the proportions of the uploaded artwork. |
| Fit the whole image, preserving aspect ratio | Arbitrary images whose edges should remain visible | Can leave unused space or require a larger background area. |
| Fill and crop, preserving aspect ratio | Artwork intended to cover the entire text area | Can crop meaningful details near the edges. |
| Optional nine-slice | Images deliberately prepared with stretchable regions | Requires image-specific insets; unsuitable as an assumption for arbitrary uploads. |

The baseline is a general upload-and-fit workflow with text padding. The default fitting
mode and whether background dimensions need independent controls remain design choices.
Nine-slice is a possible advanced option, not a prerequisite or the default image contract.
`bgslice` is exposed and used by shipping UI, including the default dialog panel
(`Definitions/Style.lua:86`, `DMHub Core UI/DefaultStyles.lua:2037`). Unity's general
nine-slice model preserves corners while stretching the appropriate edges and centre.
[Unity nine-slicing documentation](https://docs.unity.com/en-us/engine/6000.3/manual/unity2d/sprite/9-slice/9-slicing).

Do not assume arbitrary uploads have useful slicing metadata. The API declaration says
normalized coordinates, while existing Lua passes values such as 20 and 100. Exact
DMHub inset semantics would need a separate proof if advanced slicing is included.
No UI texture-repeat contract was found. Neither slicing metadata nor repeating-texture
preparation is required for the general uploaded-image feature.

Image backgrounds do not imply curved lettering. Existing straight label text and
horizontal pin names remain intact unless that separate feature is requested.

### Loading, permissions and performance

- Reuse the artwork asset validation/read-permission checks, generation guards,
  loading timeout and Retry patterns (`RegionMapRecords.lua:230-259`,
  `RegionMapArtwork.lua:43-51,211-244,265-297,365-375`).
- Keep the text and a readable fallback visible while an image loads or is unavailable.
  Avoid silently accepting a video: the shared picker also permits video files, while
  the requested feature is static artwork.
- Pin-background selection is already Director-only through map settings. For player-owned
  independent labels, whether owners may choose/upload backgrounds remains a decision;
  do not silently change existing label authorship rights.
- Include image identity and fitting settings in render signatures. Load/style only when
  they change, not during panning. Measure image-heavy scenes before promising a texture
  budget or frame rate.
- Test asset readability from a second client and after reload, unavailable assets,
  long and multiline text, reset, Undo, rotation/zoom, and Font Size changes.

## Decision ledger and next design step

| Decision | Status |
|---|---|
| Research all three capabilities within the mod's scope | Requested by user, 2026-10-15 |
| Background artwork is a still image | Confirmed by user, 2026-10-15 |
| Users upload their own images; the scroll is only an example | Clarified by user, 2026-10-15; supersedes the prepared-scroll recommendation |
| Existing per-label versus per-map scope and zoom behavior | Retained from the signed-off designs |
| Outline controls/units/defaults and independent image fit/padding controls | Proposed; not signed off |
| Runtime custom font upload | Await engine capability/packaging clarification |
| Default image fitting, padding and independent dimensions | Open design choices for arbitrary uploaded images |

Recommended sequence: design configurable outlines and static image backgrounds as the
next mod changes, and track font uploading as a separate engine capability question.
Before implementation, settle outline units/range, image fitting/padding, and background
selection rights for player-owned labels, one category at a time. No feature copy or
runtime implementation is approved by this research alone.
