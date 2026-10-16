# Text appearance: engine findings and custom fonts

Evidence collected 2026-10-15/16 in the connected build 10. Outlines and uploaded
static backgrounds are implemented; their current contract is
[TEXT_APPEARANCE_BRIEF.md](TEXT_APPEARANCE_BRIEF.md), with
[verification](../tests/TEXT_APPEARANCE.md). Superseded implementation proposals and
unanswered questions resolved by that design have been removed.

## Native rendering findings

- textOutlineWidth and textOutlineColor draw individual glyph contours. Fresh
  32-point labels were inspected in Berling, Courier and Liberation Sans at native
  widths 0, 0.1, 0.3, 0.6 and 1.
- Thickness has markedly different visual weight across fonts. Larger values can
  consume much of the glyph face; the value is not a measured pixel width.
- These observations supersede earlier comments claiming the native effect always
  makes a rectangular slab.
- Native text can retain a previous outline/font material. The implementation
  replaces the text leaf when its effective material changes, keeping the parent
  transform and selection.
- Image fitting uses actual destination geometry for Fit, normalized centre cropping
  for Fill, and the destination rectangle for Stretch. Native nostretch is not Fit.
- The library picker supplies still-image assets. Delayed callbacks need editor,
  target, asset-value and picker-lifetime guards.
- Manual label backgrounds stay independent of text size. Pins use screen-relative
  dimensions; independent labels use map-relative dimensions.

## Uploaded custom fonts

No confirmed mod-only TTF/OTF upload route was found. This is an unresolved capability
investigation, not an approval for engine changes.

gui.availableFonts lists font IDs configured for the app build, not fonts installed
in Windows. Both editors use those IDs. An arbitrary font name or local file path
does not load a font; unavailable stored IDs fall back without rewriting the record.

The exposed API and working call-site searches found no runtime font upload,
registration or font-asset creation workflow. CodeMod resources expose an Images
editor, not a font-resource editor. A file picker alone does not solve loading.

Definitions/Style.lua mentions module-supplied fonts by asset name. No shipping
CodeMod example or public upload API in this checkout established how a Director
could supply one. Confirm that packaging route before concluding it is impossible.

An engine handoff would need to define shared storage and IDs, client download/cache
behavior, glyph/material generation, font family/weight/style metadata, fallback,
resource limits and change notifications. Unity offers lower-level facilities, but
that does not establish their availability through the DMHub Lua API:
[FontEngine loading](https://docs.unity3d.com/ja/current/ScriptReference/TextCore.LowLevel.FontEngine.LoadFontFace.html),
[TextMeshPro font-asset creation](https://docs.unity3d.com/ja/Packages/com.unity.textmeshpro%403.0/api/TMPro.TMP_FontAsset.CreateFontAsset.html).

Pre-rendered lettering in map artwork preserves its look across clients but loses
editable font text. It is a workaround, not custom-font support.
