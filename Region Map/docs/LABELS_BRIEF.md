# Overland Map labels

Decided with the user and implemented on 2026-10-14. Verification and delivery status
are recorded in [../tests/LABELS.md](../tests/LABELS.md).
This supersedes idea 15's provisional scope in [IDEAS_RESEARCH.md](IDEAS_RESEARCH.md).
The implementation is locally deployed; publication and fixture cleanup are paused.

## Agreed behavior

Labels are independent map lettering, without Location pins, descriptions, child maps,
or Party destinations. The first version supports straight text with explicit line
breaks, every available app font, bold/italic, alignment, colors, size, rotation, and
letter spacing. Curves, JSON import, grouping, duplication, bulk edits, cross-map copying,
and manual stacking controls are deferred.

The Director manages all labels. A game-wide **Players can manage their own labels**
setting defaults off; when enabled, players may create and manage their own. Turning it
off makes their existing labels read-only. View as player remains read-only. Ownership
does not transfer when the Director edits a label.

Director labels start Hidden, player labels Revealed. Only the Director changes that
visibility. Players see/search only revealed labels on accessible maps. Filtering applies
before matching search text, generating snippets/counts, hit testing, or opening an editor.

Text grows with the map and never automatically hides because of zoom or overlap. Size is
a percentage of map width; UI Font Size scales the controls/handles, without changing the
text's proportional footprint on the map. Position is the text block's center; alignment
does not change it. Centers stay on the map and rendering uses canvas clipping.

| Initial formatting | Value |
|---|---|
| Font, color, style | Berling, white, regular, centered |
| Size | 3% of map width, range 0.1-25% |
| Letter spacing | 0%, range 0-100% of font size |
| Rotation | 0; free rotation, Shift snaps to 15 degrees |
| Text | 256 Unicode characters / 1,024 bytes, explicit line breaks, no automatic wrapping |
| Background | Auto contrast |

Auto contrast is a snug automatic black/white backing, chosen for contrast with the text
color rather than by sampling map pixels. Plate is a larger padded rounded rectangle
with independent color/opacity, initially black at 75%. None draws plain text. A genuine
per-glyph halo was explicitly dropped after the engine review.

Remember successfully saved formatting per user/game; omit text, rotation, and visibility.
Unavailable stored fonts fall back for rendering without rewriting the saved choice.

## Interaction

The + button offers permitted Location/Label actions, or directly activates the only
available action. Right-click also offers Add label here. Placement opens the existing
side-panel area as a label editor. Creating/editing does not change the map's lock state.

Locked labels pass ordinary clicks and drags through. Explicit Edit label actions in
context menus/search still work. Unlocked labels require selection before a drag moves
them; dragging unselected lettering pans. Selected, unlocked labels have resize/rotation
handles, with numeric fields and Move label as alternatives. Resize is uniform about the
center. Foreground map objects retain priority; transform handles are drawn above them.

Show labels is a separate per-user/game preference, initially on. Search includes typed
Location/Label results and map breadcrumbs, ranked by prefix then other matches, followed
by normalized name, kind, and stable ID. Selecting a result centers/highlights it locally;
authorized users also have Edit label. Search/editor selection temporarily draws that
permitted label while Show labels is off, without changing the preference.

Arrow keys choose a search result, Enter opens it, and Ctrl+Enter edits a permitted label.
Enter in the text editor inserts a newline. Escape cancels a transform before leaving the
editor; the same event must not also navigate or close the map. Existing text-field Undo
and modal/picker input handling retain priority.

## Saving and compatibility

Autosave after 1.5 seconds or field exit, and flush on editor closure/selection change.
A new label remains local until its first valid nonblank save; retries retain its ID.
Closing saves valid changes, discards an empty unsent draft, and never implicitly deletes
an upload that later succeeds.

Serialize immutable batches per label. Each confirmed creation, autosave batch, completed
transform, visibility change, and deletion gets one Undo entry. Failures stop the queue
and retain Retry. Recheck role, ownership, map access and visibility before writing,
retrying, or undoing. Permission loss, deletion/hiding, and unloading cancel applicable
unsent work and previews. Accepted writes may settle without reopening stale editors.

Store schema-1 RegionMapMapLabelRecord rows in RegionMapMapLabels. Existing schemas and
the obsolete V1 label table remain unchanged. Keep structural validation separate from
viewer access. Map replacement and moving a containing Location preserve labels; map
removal/subtree deletion include affected labels in the same Undo, with counts in the
confirmation. Undo validates the maps that its whole operation will restore.

## Evidence and verification

The live engine probe confirmed that renderedWidth/Height remain natural dimensions at
scale 1, 2 and 20 and at 45-degree rotation; renderedScale contains the transform. Explicit
newlines increase the measured height. Use cached natural bounds and inverse rotation for
hit testing. Scaling the whole map layer is an existing measured performance trap; pan
slides the layer and zoom updates guarded per-label transforms.

The visual probe found that textOutlineWidth did not produce the required backing in this
build. The Auto contrast implementation therefore draws its snug backing explicitly.

Completed verification includes 18 isolated production-model/UI checks, 27 artwork
regression checks, disposable Director-client fixtures, selected native/in-app layout
checks, and synchronous Lua performance measurements. Separate player clients, physical
modifier/arrow input and whole-frame performance remain unverified. Exact coverage and
tooling limitations are recorded in [../tests/LABELS.md](../tests/LABELS.md).

Delivery uses the existing Overland Map CodeMod ec447c62-03db-4416-a5a2-0b013c0f3893.
Register helpers in dependency order, deploy the complete module, audit the code-only
package, and never switch the user's current game to publish/install it.
The three helpers are already registered and the 29-file module was deployed locally.
The last verified installable package is version 2, before labels; no labels publication
or installation is claimed. The user's latest instruction limits further work to docs.
