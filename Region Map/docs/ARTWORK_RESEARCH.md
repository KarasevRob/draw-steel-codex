# Overland Map - Artwork attachments research

2026-10-14. Idea [19](../IDEAS.md). The user approved the implementation plan below:
Directors and players open one attached still image locally; only Directors manage it.
The complete feature is deployed, its helper registration is persisted, and isolated and
live checks have run. Separate player-client checks remain outstanding. See
[checks](../tests/ARTWORK.md) for the evidence and limits.
Source anchors refer to the researched working tree at `3a3fd3d1`, including local changes;
line numbers will drift.

## 1. Frame and agreed behavior

**Problem.** Scene or reference artwork should be available at the Location or path it
belongs to, so a Director or player can click it and inspect it independently.

**Done looks like.** A visible attachment appears on a Location or point crawl path.
Clicking it opens a larger image for that viewer. They can close and reopen it themselves.
Other clients' windows, map navigation and Party position are unaffected. Preparation
controls allow only the Director to choose, replace and remove the attachment.

| Date | Decision | Rationale / source |
|---|---|---|
| 2026-10-14 | Attach artwork to Locations and paths | User's idea 19 |
| 2026-10-14 | Investigate it as the next feature | User requested research |
| 2026-10-14 | Both Directors and players click artwork to view it on their own | User's latest clarification; player opening is part of the core feature |
| 2026-10-14 | No artwork presentation or broadcast | User explicitly does not need the present ability; supersedes the earlier optional Show to players scope |
| 2026-10-14 | One optional still image; Director-only management, including player-owned Locations | Accepted implementation plan |
| 2026-10-14 | 160-pixel fitted preview before Description, after title/status/travel details | Accepted implementation plan |
| 2026-10-14 | Visibility follows the owner and both path endpoints; opening is a local snapshot | Accepted implementation plan |
| 2026-10-14 | Preserve the other developer's active testing session | Latest implementation instruction |

**Inherited constraints.** Implementation stays inside `Region Map/`, with no core or
engine edits (`V2_BRIEF.md:25`, `V2_1_BRIEF.md:43`). Keep current table names, schema
compatibility, ThemeEngine, responsive panels, View as player, save feedback and Undo.
Opening and closing the image are local UI actions. The existing V2 map-presentation
decisions remain in force; this feature does not reopen them.

**Out of scope by user instruction:** presenting artwork to other clients. Consequently,
there is no artwork presentable registration, shared presentation payload, broadcast
permission, presentation timeout, replacement confirmation or global stop action to build.

## 2. Approved first version

Use **one optional still image per Location or path**, displayed in a full-width,
160-logical-pixel frame before the description. The complete image fits inside automatic
dimensions with maximum bounds; it is neither cropped nor stretched. Open it with the
existing local viewer. Only the Director gets choose/replace/remove controls in the edit
flow, using the Journal image library and Undo. No attachment collapses the read section.

Artwork availability follows the owning Location/path's existing visibility.
Players who can read that object can click its artwork, subject to the image asset's own
read permissions. A Location's `mapShared` flag controls its own map, so it should not be
repurposed as artwork access. No separate artwork-reveal state is proposed.

Image bytes stay in the existing library. Store a separate attachment reference: a
Location's `imageId` already denotes its map and `icon` denotes its pin. An artwork change
must not invoke map-image replacement or map removal.

## 3. Existing RegionMod pieces

| Capability | Evidence | Consequence |
|---|---|---|
| Location map and pin images | `RegionMapRecords.lua:57-86` | Neither field is a spare attachment slot |
| Separate Location description/journal details | `RegionMapRecords.lua:21-34`; `RegionMapModel.lua:1292-1345` | Details saves lack the normal undo entry; prefer the main Location row |
| Path descriptions and Director notes | `RegionMapRecords.lua:145-172` | Add an optional attachment reference to the path row |
| Existing image picker | `RegionMapSidePanel.lua:663-685` | Reuse `gui.IconEditor` with `library = "journal"` |
| Location writes with undo | `RegionMapModel.lua:470-538` | Extend the write normalizer and use the existing audited write path |
| Path writes with undo | `RegionMapPaths.lua:460-590` | Extend its field whitelist and preserve busy/conflict handling |
| Optional fields on old records | `V2_1_BRIEF.md:279-284`; `RegionMapRecords.lua:558-560`, `:694-724` | Read absence as no attachment; do not bump strictly checked schema versions |
| Location read/edit panel | `RegionMapSidePanel.lua:308-370` | Add the preview beside existing content, within the same scrolling surface |
| Path read/edit panel | `RegionMapPathPanel.lua:276` | Reuse the same attachment component and local open behavior |

Main-row storage preserves artwork through map-image replacement/removal, which patch
map-specific fields on a copied Location row (`RegionMapModel.lua:710`, `:1117`).
Location/path deletion soft-hides the full row, so Undo can restore its attachment too
(`RegionMapModel.lua:1057`; `RegionMapPaths.lua:608`). Detaching clears only the reference,
not the image asset.

Current JSON import creates bare Locations and does not import artwork or paths
(`RegionMapImport.lua:59`; `IMPORT_FORMAT.md:36`). No operational RegionMod cloning or
export flow was found. Artwork import is additional scope, not a prerequisite.

## 4. Reuse the existing local viewer

The established owner-aware call is:

```lua
GameHud.instance:ViewJournalEntry{
    image = imageId,
    owner = clickedControl,
}
```

DocumentSystem already uses this pattern (`DocumentSystem/DocumentSystem.lua:1756`).
It opens a local image modal with automatic sizing, `maxWidth` and `maxHeight` of 1024,
and click/Escape dismissal (`DMHub Game Hud/Journal.lua:266-306`). It can serve the
Director and player alike; no sender/receiver flow or new player viewer is needed.

The owner matters: modal routing uses the clicked control's native window
(`DMHub Core UI/Gui.lua:215-242`). The simpler `dmhub.ViewSign(imageid)` wrapper does not
pass an owner, so it is unsuitable for opening from a RegionMod popout.

RegionMod uses `EXIT_CHARACTER_SHEET - 1` fullscreen and `EXIT_DIALOG` in a popout
(`RegionMapPanel.lua:21-29`). The modal's `EXIT_MODAL_DIALOG` priority wins, so the source
supports Escape closing the image before the map/window (`DMHub Core UI/Hud.lua:93-154`).
The live verification below covers native owner routing; physical native Escape remains
an acceptance check.

Implementation verification confirmed owner routing into the native window. The shared
viewer can exceed a small window at its default image size, so the call also supplies
aspect-preserving `width`/`height`, bounded by the owner window and the same 1024-pixel cap.
The viewer, click/Escape dismissal and local snapshot lifetime remain the existing ones.

The viewer is a simple enlarged image, not a zoom/pan browser. Reusing it avoids a custom
viewer lifecycle. Its local image snapshot does not automatically follow a later
attachment replacement; the read panel should refresh, and reopening should use the new
reference. This snapshot behavior is the approved first version.

## 5. Assets, visibility and editing

`gui.IconEditor` already handles library selection and upload
(`DMHub Core UI/IconEditor.lua:3`; `Definitions/assets.lua:130`). The journal picker
library and Journal's imported Document image assets are not necessarily the same
collection. The picker also accepts videos; if the first version is still artwork, check
the selected asset's `isVideo` rather than assume an image-only picker flag exists.

`dmhub.GetImageInfo(id, callback)` reports dimensions or nil
(`Definitions/dmhub.lua:317-320`). Guard callbacks against selection changes, stale
attachment references and closed/unloaded panels. `RichImage` explicitly guards repeated
callback handling (`DocumentSystem/RichImage.lua:73-92`).

Removing artwork must only clear the attachment. Library removal or soft deletion does
not prove an existing reference has stopped resolving
(`Definitions/ImageAssetLua.lua:11`; `Definitions/GameAsset.lua:14`).

Image assets have their own viewing permissions: `HaveReadPermissions()` is the explicit
API used by the component, and the picker hides GM Secret assets from players
(`Definitions/ImageAssetLua.lua:3`; `DMHub Core UI/IconEditor.lua:767`). A replicated
image id alone does not prove a player can load it. Verify normal and restricted assets
on a real player client, with a useful unavailable-image state. No automatic change to
asset permissions is proposed or established by the research.

Location editing allows the owner or Director (`RegionMapModel.lua:187-232`), but artwork
management is explicitly Director-only. `UpdateLocation` guards it even for player-owned
rows and calls bypassing the UI. `UpdatePath` retains its Director-only guard. View as
player denies both. Players editing their Location retain a read-only preview/open action.

Player access to a path also requires both endpoints to be visible
(`RegionMapPaths.lua:80-94`). Use the existing readable Location/path lookups and View
as player gates before rendering or opening attachments. RegionMod's Hidden/Revealed
rules remain UI access rules, not a new server privacy boundary.

## 6. Settled decisions

| Category | Approved behavior |
|---|---|
| Storage | Optional `artworkImageId` on each main row; unchanged schemas/tables; no migration |
| Validation | New nonempty values must resolve to still-image assets; raw IDs rejected; empty clears |
| Legacy rows | Missing/malformed attachments never invalidate the owner; Director can replace or clear |
| Picker | Journal `gui.IconEditor`, categories hidden, live edit off, clipboard right-click disabled |
| Removal | None and Remove use the same undoable write; library asset remains |
| Loading | Actual image-loaded event and valid dimensions; 10-second recoverable timeout, Retry and asset updates |
| Races | Capture kind/id/attachment/generation; compare attachment, not whole-row revision; stale/duplicate results ignored |
| Writes | Existing audited uploads, save feedback, one Undo entry per confirmed change; same image is a no-op |
| Local viewer | Recheck owner visibility and asset before `ViewJournalEntry{image=..., owner=...}`; snapshot survives source changes |
| Keyboard | Enter in active read section, guarded against typing/search/pickers/modals; existing Escape dismissal |
| Performance | Only selected artwork loads; no additions to pan/zoom loops or pin/path indexes |
| Exclusions | Galleries, captions, custom zoom/pan, URLs, attachment JSON import and presentation |

Copy is approved in [V2_COPY.md section 26](V2_COPY.md#26-location-and-path-image-attachments).

## 7. Implementation

1. **Records and writes.** Optional `artworkImageId` is on both main row types.
   `R.ArtworkValue` safely reads absent/bad values without consulting asset availability.
   Validate new values through `NormalizeChanges` (`RegionMapModel.lua:505`) and
   `NormalizeFields` (`RegionMapPaths.lua:498`). Do not make attachment validity a
   condition of `IsValidLocationFields` or `IsValidPathFields`: rejecting the whole row
   would hide its Location/path. Keep schema versions and existing audited Undo.
2. **Reusable attachment UI.** `RegionMapArtwork.lua` provides the picker, fitted preview
   and local open action. Object kind/id, initial attachment and operation generation are
   captured before choosing/loading. Every write and busy retry rechecks permission,
   owner existence, attachment value and panel/mod liveness. Description saves do not
   cancel image selection. Confirmed writes retain Undo even if the editor was closed.
3. **Read/edit integration.** The image appears for permitted Directors and players in the
   existing read panels. Clicking opens the local viewer with the clicked control as
   owner. An Open control and scoped Enter handler share that action. Directors get choose, replace
   and remove, with the existing save/Undo feedback.
   Input events follow keyboard focus in the engine: the shell subscribes the canvas to
   Enter only while an artwork read section is active, and forwards to that section's
   guarded handler. Switching a path editor to View as player returns it to read mode.
4. **Validation and deployment.** Copy/styles remain in RegionMod. The live registration
   workflow confirms `RegionMapArtwork` at index 16, before the two detail panels; the
   console records the successful cloud write and verification. All ten feature files
   were deployed together and their cached contents checked before reload.

**Feature files:** `RegionMapRecords.lua`, `RegionMapModel.lua`, `RegionMapPaths.lua`,
`RegionMapSidePanel.lua`, `RegionMapPathPanel.lua`, `RegionMapCopy.lua`,
`RegionMapStyles.lua`, `RegionMapArtwork.lua`, `RegionMapConstants.lua` and `RegionMapPanel.lua`.
No artwork changes to `RegionMapPresent.lua` or GameHud presentation registration
are needed.

**Scope.** The previous 650-950-line estimate and score 11 included presentation and are
superseded. The implementation uses optional fields, one shared component, two detail-panel
integrations and a scoped keyboard handoff from the shell. Remaining acceptance work is
separate player-client asset access, slow real uploads and native OS keyboard delivery.

The root already monitors Location/path tables (`RegionMapPanel.lua:857`). Artwork writes
still cause the ordinary data revision refresh of pins/paths
(`RegionMapCanvas.lua:531`; `RegionMapPathLayer.lua:440`). Load only the selected object's
preview and explicitly opened image; avoid image loads in map pan/zoom loops.

## 8. Focused acceptance matrix

| Area | Check |
|---|---|
| Core flow | Attach, click to enlarge, close, reopen, replace, remove and Undo on a Location and a path |
| Independent viewing | Director and player open/close images independently, including different images; neither action changes another client's UI |
| Existing images | Map replacement/removal and pin-icon changes preserve artwork; artwork changes do not alter child maps |
| Compatibility | Old/malformed optional attachment fields never hide the owning Location/path |
| Deletion | Soft-delete Location/path and Undo restores its attachment; detaching preserves the reusable library asset |
| Visibility | Director, player and View as player on revealed/hidden objects and paths with a hidden endpoint; direct open rechecks access |
| Editing | Players can view without gaining attachment-edit rights; chosen ownership policy is enforced in writes |
| Asset access | Real player loads an ordinary image; restricted/missing/video assets follow the chosen policy and show a useful unavailable state |
| Async changes | Switch selection, delete the target, close or reload while picking/loading; stale callbacks never write to the wrong object |
| Undo and sync | Newer remote changes refuse stale Undo and refresh the preview; reopening uses the latest attachment |
| Windows | Fullscreen and native popout; opening uses the source window; close/Escape leaves the map alive without click-through |
| Layout/accessibility | 720x480 and 1000x800; Font Size 80/100/140; Default/Warm Gold; keyboard open/close; portrait/landscape/small/large images |
| Performance | Existing large-map fixture; no eager images for unselected objects or new per-frame work; compare first versus cached open |

## 9. Evidence and validation limits

Prior research used a connected in-game Director client. The live screenshot showed
Overland Map's Locations, paths and Party. A Location read panel was opened via its pin
handler. Runtime probes confirmed `gui.IconEditor`, `RichImage`, `dmhub.ViewSign` and
`GameHud.instance.ViewJournalEntry` are loaded; `dmhub.GetImageInfo` resolved an existing
image to 1293 by 680 pixels. These establish available building blocks, not a completed
attachment feature or successful player-client test. No live attachment was written.

Implementation validation is recorded in [tests/ARTWORK.md](../tests/ARTWORK.md): isolated
model/UI-event fixtures exercise production code without touching the connected session.
A read-only live API probe confirmed the asset key shape and explicit permission method.
Fullscreen and a native preview were visually inspected. Live geometry checks cover both
window sizes, three Font Size settings and Default/Warm Gold. Desktop captures later
returned blank images, so the final native viewer fit was checked with runtime dimensions.
Independent real-client behavior and restricted player assets remain unverified.

Foundry's journal image pages and map-note links provide a precedent for image access from
a map object. [Foundry journal documentation](https://foundryvtt.com/article/journal/).
Roll20 handouts let viewers click an associated image for a larger view.
[Roll20 journal documentation](https://help.roll20.net/hc/en-us/articles/360039675133-Journal).
These are product precedents; the demand evidence is the user's request and clarification.
No DMHub community request counts or votes were collected.

Implementation rechecked the prerequisites: `../dependencies/lua/bin/luac.exe` exists;
`../tools/lua-typing/check.ps1`, `tools/lua-typing/baseline.json` and an engine checkout at
`../Assets` do not. The available `../dependencies/check-mod.ps1` loads other modules as
libraries and checks RegionMod; it does not replace or restore the missing standard
baseline/full checker. A broader search through accessible files on C:, D: and G:, caches
and repository history also found no standard source; RegionMod's available check reports
zero problems. A direct whole-workspace LuaLS scan completed with 11,049 diagnostics
outside RegionMod and none inside it; without the historical baseline it is not a standard
baseline-comparison pass. The user initially held deployment, then explicitly released the
engine for testing. Test fixtures were removed and view settings restored after validation.
