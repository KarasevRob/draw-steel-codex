# Tabletop patterns for Overland Map

Technical report, 2026-10-18. Scope: the Overland Map CodeMod in `Overland Map/`.
Status: research and recommendations, not an approved implementation brief.

Originally audited at `4fa42db8`; rechecked after the rebase at
`9b6092bb79c682f51181c0cd8a49c787a4586dc9` on 2026-10-18, including the working
tree's map-aids changes. The rebase changed no tracked `Overland Map/` source between
those commits. The Tabletop, shared GUI and document changes were reviewed against
the report's conclusions; source links below now target the rebased checkout.
Source links use repository-relative paths and line anchors; function names are
included because line numbers will move. Examples marked **source excerpt** come
from existing code. **Illustrative** examples describe possible mod-local code;
they are not implemented APIs or complete production components.

## 1. Findings and evidence

Tabletop's most useful contribution is its separation of content, window controls,
interaction, and saved state. Applying those boundaries consistently could improve
the whole mod: images, editors, navigation, canvas tools, and operation feedback.
Its tactical-map renderer is a different system from our image-based map canvas.

The recommended starting points are image-request lifecycle consolidation, shared
editor lifecycle mechanics, common canvas gesture handling, and operation planning
in the model. These can stay inside this mod and use existing public GUI APIs.
Tabletop's private functions remain reference implementations. The rebase also
introduces public extension points for personal table items and external-window
minimization, plus a shared file-upload helper. Those can become optional runtime
dependencies after capability and lifecycle checks.

### Current compatibility: can an Overland map be dragged onto Tabletop?

**No. Dragging an Overland map from the Atlas onto Tabletop like a tactical map
is not currently implemented.** The existing window provides a foundation for
coexistence, but does not register the mod as a Tabletop map.

| Workflow | Current status |
|---|---|
| Open Overland Map from the rail or Game menu | Implemented |
| Switch to its movable, resizable in-app Window view | Implemented, using the same documents UI layer as Tabletop |
| Drag an Atlas map onto the table to open it there | No Atlas-to-Tabletop drag/drop adapter |
| Use Tabletop minimize, window-switcher, follow or spatial-sharing behavior for Overland Map | No integration; each has the API and scope limits discussed below |
| Confirm coexistence with the rebased Tabletop in a running app | Still requires live testing; the connected app lacks the new Tabletop APIs |

The [Overland window host](../OverlandMap.lua#L429) creates its own panel on
`GameHud.instance.documentsPanel`, and its
[registration](../OverlandMap.lua#L558) supplies the rail/Game-menu entry. Tactical
maps instead explicitly wire
[Tabletop drag/drop handlers](../../DMHub%20Core%20Panels/MapsPanel.lua#L763).
[Overland's Atlas](../OverlandMapAtlas.lua) has no equivalent handlers. Its map IDs
refer to mod records, not engine tactical maps; passing them to
[Tabletop.OpenMap](../../DMHub%20Game%20Hud/Tabletop.lua#L3501) would not render the
Overland canvas.

A future adapter could make an Atlas drag open or raise the existing Overland
host at the drop position, using its guarded map-navigation and window-placement
paths. That would need to preserve the single-host, pending-edit and permission
rules. The personal-item API in section 8 offers a separate reference-card route;
it does not automatically embed the interactive Overland canvas. Neither option
is implemented or approved by this report.

### Rebase verdict

The core analysis stands. Three integrations are now more concrete, and the new
collaboration behavior needs explicit boundaries:

| Rebased capability | Effect on this report | Mod-sized opportunity or limit |
|---|---|---|
| `Tabletop.itemKinds`, `OpenItem` and row-drag helpers | Adds a direct integration route | Personal map/Location reference cards can reuse Tabletop's frame, grips and layout persistence; see section 8 |
| External-window minimize/restore helpers | Qualifies the earlier private-implementation assessment | Our single in-app host could minimize without adopting Tabletop's map renderer; see section 9 |
| `FileDrops` and clipboard APIs | Adds reusable input plumbing | Still-image drops into existing image fields; preserve validation and upload ownership; see section 5 |
| Director placement following and pings | Adds collaboration precedents | Optional map-view following or coordinate pings require mod-specific protocols; see section 6 |
| Director's Screen | Adds sharing semantics we must not inherit accidentally | Position can change sharing in Tabletop; moving an Overland Map object must retain its current meaning |
| Window switcher and Windows menu | Exposes a current integration limit | Their collectors have no public external-provider hook; generic window integration is not automatic |
| Layer readiness, grip hover handling, theme refresh, `groupOpacity`, `boxShadow` | Strengthens existing lifecycle/rendering recommendations | Useful local refinements; new engine styles still need live capability checks |

Evidence has three levels:

- **Source verified:** Tabletop and Region Map call sites, public API definitions,
  and the existing design and validation documents linked throughout this report.
- **Live capability checked:** the earlier probe exposed the existing window
  resizer and horizontal, vertical, and both diagonal resize cursors. A fresh
  read-only probe after the rebase still found no `Tabletop`, `FileDrops`,
  `WindowSwitcher`, `DirectorScreen` or `DocumentImport` global in the connected
  build 10 app. `dmhub.tabletopMode`, `mapViewportActive`, `GetClipboardImageSize`,
  `GetClipboardFiles` and `ShowTabletopArrow` were also unavailable. The rebased
  features were therefore source-verified, not visually or behaviorally tested.
- **Geometry checked:** 64 standalone Lua assertions covered projected resizing
  at five angles, three zoom factors, opposing handle directions, minimum clamping,
  and invalid geometry. This was a mathematical check, not a native drag, popout,
  or performance test.

No engine source checkout was available at the checked locations. Existing native
path research has separate recorded assembly inspection and live evidence. No
performance improvement from the proposals below has been measured. Two-client
live tests remain excluded as previously requested.

## 2. Coverage across the mod

| Area | Tabletop precedent | Useful adaptation | Assessment |
|---|---|---|---|
| Canvas tools | Card grips and drag previews | Common gesture lifecycle and cursor feedback for pins, Party, bends, ruler, labels and aids | High value; preserve operation-specific rules |
| Map and attachment images | Shared scene view and document faces | Common request identity, dimensions, status and retry contract | High value; retain specialized geometry |
| Location/path editors | Controls backed by store adapters | Shared debounce, flush, cancellation and busy-retry mechanics | High value; saves use different stores |
| Refresh orchestration | `SyncShares` signatures and retained panels | Component-specific update inputs | Instrument before changing |
| Actions and confirmations | Data/view separation and store commands | Model-owned operation summaries and reusable action entry points | High value where duplication exists |
| Atlas, breadcrumbs and search | Bounded map preview tooltip | Reusable viewer-filtered summary and thumbnail presentation | Modest feature extension |
| Location/path readers | Content reused in cards/windows; public personal item kinds | Common reader composition and optional pinned references | Public integration available; extra surfaces need design |
| Window host | Placement records, reparenting and external-window helpers | Clear host/session lifetime boundary; optional minimize | Much already implemented; minimize has a public route |
| Sharing and presenting | Share widget/store boundary | Consistent state and permission feedback | Preserve distinct existing semantics |
| Paths, routes and ruler | Rendering separated from window controls | Explicit geometry/render boundary | Useful foundation; native shapes are separate research |
| Import and session log | Bounded previews and explicit teardown | Consistent participation in host-close and permission lifecycle | Targeted work; retain existing batching |
| Image-field input | `FileDrops.UploadImage` and drag ghosts | Still-image drops for map, attachment, compass and background fields | Public helper; optional and capability-gated |
| Collaboration | Director layout ownership and transient pings | Optional follow/view or attention features in image coordinates | New product decisions; keep Show to players unchanged |
| Settings and preferences | Personal window layout separate from shared items | Extend existing per-viewer preferences for any approved shortcuts | Already established in Session |
| Theme, Font Size and layout | Scoped styles and separate content scaler | Consistent artwork versus control scaling | Already present; avoid double scaling |

Existing pooled drawing elements, cached style writes, personal preferences, row
writes, guarded Undo, and companion cleanup hooks are foundations to retain.
This report does not recommend replacing them merely to resemble Tabletop.

## 3. Rendering composition and window lifetime

Tabletop map windows use `#MapView` for the current tactical map and
`#MapSnapshot:<mapid>` for inactive tactical-map views. New covers and overlays
make inactive windows look more like the live map; this does not give each window
an independent live renderer. The engine uses the live
panel's rectangle for camera and input behavior. These keys do not render arbitrary
Region Map records or capture our Lua canvas. See
[BuildWindow](../../DMHub%20Game%20Hud/Tabletop.lua#L1846) and the
[viewport API](../../Definitions/dmhub.lua#L208).

Cards and document tiles instead use ordinary GUI panels: a fixed-size content
panel inside a sized outer frame, with separate controls and hit regions. The
following **source excerpt** from
[ApplyCardScale](../../DMHub%20Game%20Hud/Tabletop.lua#L5079) shows that split:

```lua
local w, h = ItemSize(card)
local s = card.scale or 1
panel.selfStyle.width = math.floor(w * s)
panel.selfStyle.height = math.floor(h * s)
--the frame draws nothing itself; its corners shape the face's shadow.
panel.selfStyle.cornerRadius = (card.shadowRadius or 0) * s
card.scaler.selfStyle.scale = s
--the titlebar is at least as wide as the card (see BuildCard).
if card.titlebar ~= nil and card.titlebar.valid then
    card.titlebar.selfStyle.minWidth = math.floor(w * s)
end
for _, grip in ipairs(card.grips) do
    if grip ~= except then
        PlaceGrip(card, grip)
    end
end
```

The actively dragged grip is not repositioned underneath the native drag system.
This is an implementation detail of Tabletop's input model, not a reason to change
our canvas's current gesture ownership.

Scene windows reuse a public content view. **Source excerpt** from
[BuildSceneWindow](../../DMHub%20Game%20Hud/Tabletop.lua#L8628):

```lua
local view = FullscreenDisplay.CreateSceneView{fit = "contain", textScale = 0.5}
```

The same [CreateSceneView](../../DMHub%20Game%20Hud/FullscreenDisplay.lua#L101)
also serves fullscreen scenes. Its host controls fit and surrounding chrome.
Region Map can adopt this composition pattern for image readers and summaries;
the scene component itself includes caption, credit and video behavior that does
not belong in our calibrated canvas.

Our host already retains the same content when switching between fullscreen and
the in-app window, and already uses
[gui.WindowResizePanel](../OverlandMap.lua#L448). The native popout has a separate
host lifecycle. Tabletop's
[PlaceWindow](../../DMHub%20Game%20Hud/Tabletop.lua#L2217) and
[map HUD reparenting](../../DMHub%20Game%20Hud/Tabletop.lua#L3069) are useful
references, but do not establish that live panels can be transferred between
native OS windows safely.

Keep three distinct coordinate domains:

| Domain | Examples | Scaling rule |
|---|---|---|
| Image coordinates | Pin anchors, path bends, compass position, calibrated endpoints | Follow map geometry and camera |
| Artwork-sized content | Map labels, compass artwork, scale-bar labels | Follow map zoom; preserve authored proportions |
| Application controls | Toolbar, editor fields, selection handles, pin controls | Respect application Font Size and host layout |

Do not put all three under one new scale wrapper. Tabletop's local style resets
also solve its own parent cascade; copying selector-less resets into Region Map
could change every descendant. Retain the mod's component classes and existing
[UIScale handling](../OverlandMapSession.lua#L365).

### Host readiness and visual state

The rebase explicitly delays restoring saved Tabletop geometry until
[LayerReady](../../DMHub%20Game%20Hud/Tabletop.lua#L305) reports a laid-out
documents layer. Its [LayerSize](../../DMHub%20Game%20Hud/Tabletop.lua#L289) avoids
treating the native initial 100-by-100 rectangle as a real work area. This is a
useful regression case for our window restoration: do not clamp and save against
placeholder dimensions. Retain Region Map's own work-area, containment and UI-scale
calculations; `Tabletop.LayerRect()` is not a substitute for them in every host.

Tabletop now refreshes retained titlebars through
[ThemeEngine.OnThemeChanged](../../DMHub%20Game%20Hud/Tabletop.lua#L948), pruning
invalid panels. Apply that lifecycle principle to any future retained reference
faces and floating controls, using our component styles. It is not evidence that
our existing theme updates are broken.

Two new engine styles are relevant beyond aids:

- [groupOpacity](../../Definitions/Style.lua#L68) fades an entire subtree. It could
  simplify a preview or host transition that currently has to coordinate multiple
  layers. It still receives mouse input, even at zero opacity; disable input and
  actually hide or destroy a departing surface. Never use fading to enforce
  visibility permissions. Preserve Reduce Motion behavior.
- [boxShadow](../../Definitions/Style.lua#L89) follows `cornerRadius` and supports
  style transitions. It could supply consistent depth for floating readers,
  editors and drag ghosts. Keep it in component styles, outside measured artwork
  geometry; it must not affect aid calibration, hit bounds or window containment.

These properties were found in the rebased definitions, not tested in the older
connected app. Gate any adoption and retain a working fallback. No performance
gain from replacing an existing visual layer is established.

## 4. Canvas interactions, previews and selection

[CardGrip](../../DMHub%20Game%20Hud/Tabletop.lua#L5115) builds transparent,
interactive edge/corner panels with `hoverCursor`, `draggable`, `beginDrag`,
`dragging` and `drag`. [CardGrips](../../DMHub%20Game%20Hud/Tabletop.lua#L5239)
places edges before corners so corners win their overlap.

The updated grip code keeps separate card-hover and grip-hover flags because
native hover/dehover events can arrive in either order, and keeps the controls
shown during a drag. That is a useful pattern for our selection chrome and any
contextual action strip. It does not supply rotation or replace selected-object
hit priority. `g_sharing.TookControl` at grip release opts a player out of Director
placement following; it is unrelated to our gesture ownership or Undo.

Region Map has a different responsibility: overlapping pins, paths, text and aids
must remain usable. Its [canvas dispatcher](../OverlandMapCanvas.lua#L374) already
owns hit priority, initial snapshots, previews, completion and cancellation.
Extracting common lifecycle mechanics is more useful than making every rendered
object an independently draggable panel.

An **illustrative callback contract** for an operation could be:

```lua
---@class MapGestureAdapter
---@field isCurrent fun(): boolean
---@field canEdit fun(): boolean
---@field read fun(): table
---@field preview fun(start: table, dx: number, dy: number): table
---@field clearPreview fun()
---@field commit fun(patch: table): boolean

local function FinishGesture(gesture, cancelled)
    local adapter = gesture.adapter
    adapter.clearPreview()
    if cancelled or not gesture.moved or gesture.patch == nil then return end
    if not adapter.isCurrent() or not adapter.canEdit() then return end
    adapter.commit(gesture.patch)
end
```

This is a proposed internal boundary, not a new public API. The real controller
must consume the release exactly once, retain the gesture's map/object identity,
and preserve the existing click-versus-drag behavior. Cancellation must cover
Escape, tool changes, navigation, loss of permission, Undo and host teardown.
Commit adapters continue using existing model methods and save queues.

The shared lifecycle should support different operations rather than assign all
objects the same transform tools:

| Target | Shared mechanics | Rules that remain specialized |
|---|---|---|
| Location pin | Threshold, preview, cursor, release | Ownership, locks, map bounds and move Undo |
| Party | Pointer tracking, preview and target feedback | Snapping, point-crawl restrictions, travel/log semantics |
| Path bend | Handle hits, preview, cancellation | Bend insertion/removal, endpoint validity |
| Ruler/calibration | Pointer tracking and temporary geometry | Measurements, units and calibration confirmation |
| Label | Selection and transform controls | Text size, visibility, ownership, background geometry |
| Compass | Selection and transform controls | Image aspect, fixed anchor, upright independent north text |
| Scale bar | Selection and movement | Distance owns length; no generic resize/rotation in current design |

### Resize mathematics

Tabletop projects a corner drag onto the artwork diagonal to preserve aspect.
It also moves the origin to hold the opposite edge fixed. Region Map's approved
aid behavior keeps the anchor fixed, so only the projection principle transfers.

This **illustrative pure helper** calculates a scalar from the initial rotated
anchor-to-handle vector and the pointer delta:

```lua
local function ProjectedSize(startSize, vx, vy, dx, dy, minimum, maximum)
    local function Finite(n)
        return type(n) == "number" and n == n and math.abs(n) < math.huge
    end
    for _, n in ipairs({ startSize, vx, vy, dx, dy, minimum, maximum }) do
        if not Finite(n) then return nil end
    end
    if minimum <= 0 or maximum < minimum then return nil end
    local length2 = vx * vx + vy * vy
    if not Finite(length2) or length2 <= 0 then return nil end
    local value = startSize * (1 + (dx * vx + dy * vy) / length2)
    if not Finite(value) then return nil end
    return math.max(minimum, math.min(maximum, value))
end
```

For a corner, rotate `(signX * width / 2, signY * height / 2)` by the initial
object angle to obtain `vx, vy`. For an edge, zero the other coordinate before
rotation. Always use the initial geometry: repeatedly measuring the growing
object introduces drift. Crossing the anchor clamps to the minimum rather than
flipping the image. This helper assumes all seven arguments are supplied.

Compass resizing must use the image rectangle; label resizing must use its text
rectangle. Decorative backgrounds and upright north text can have independent
bounds. Shared selection controls therefore need separate sizing geometry,
visual bounds, and hit geometry. Existing
[label geometry](../OverlandMapLabelLayer.lua#L197) and
[aid geometry](../OverlandMapAids.lua#L339) demonstrate these differences.

### Native dragging and cursor feedback

The GUI supports drag events without moving a panel. This **illustrative probe**
uses public APIs demonstrated by
[FloatInput](../../DMHub%20Core%20UI/ParticleValue.lua#L48):

```lua
local function CreateDragProbe(onPreview, onRelease)
    return gui.Panel {
        width = 100, height = 40,
        bgimage = "panels/square.png",
        draggable = true, dragMove = false, swallowPress = true,
        data = { active = false },
        beginDrag = function(element)
            element.data.active = true
        end,
        dragging = function(element)
            if not element.data.active then return end
            onPreview(element.dragDelta.x, element.dragDelta.y)
        end,
        drag = function(element)
            if not element.data.active then return end
            element.data.active = false
            onRelease()
        end,
    }
end
```

The caller must attach the returned panel during the same frame. This is a
feasibility probe, not a production gesture controller: it omits cancellation,
permission changes, popout behavior and commit handling. The documented API does
not establish a general native drag-cancel contract. A replacement of polling
would require live evidence for those cases and would not eliminate the canvas's
animation, hover and other input work.

Cursor feedback can be adopted independently. Resolve the cursor from the same
hit result that selects the operation. The documented
[OverrideMouseCursor](../../Definitions/dmhub.lua#L1441) supports a short timed
override; it is global, so ownership and expiry need testing around other panels
and popouts. Feature-detect cursor IDs. The inspected app had no dedicated
rotation cursor, and Tabletop's card implementation supplies no rotation gizmo.

## 5. Images and reusable content views

Tabletop's [document item](../../DMHub%20Game%20Hud/Tabletop.lua#L7308) separates
its face from the outer movable frame. Its scene window similarly delegates
content to `CreateSceneView`. For Region Map, the most valuable equivalent is a
shared still-image request contract with specialized presenters.

Existing entry points are [AppearanceImage](../OverlandMapSession.lua#L595),
[attachment loading](../OverlandMapArtwork.lua#L293),
[map loading](../OverlandMapCanvas.lua#L970), and
[compass loading](../OverlandMapAids.lua#L240). They already implement important
guards; consolidation must retain their behavior rather than replace it with a
bare `imageLoaded` callback.

An **illustrative acceptance guard** for a request result is:

```lua
local function AcceptImage(scope, ticket, panel, width, height)
    if not scope.isAlive() or not panel.valid then return false end
    if ticket.generation ~= scope.generation then return false end
    if ticket.ownerKey ~= scope.ownerKey then return false end
    if ticket.assetKey ~= scope.assetKey then return false end
    local finite = RegionMapRecords.IsFinite
    return finite(width) and finite(height) and width > 0 and height > 0
end
```

Here `scope` and `ticket` are proposed plain runtime tables. `ownerKey` identifies
the map/object/editor binding; `assetKey` includes the current resolved image
reference. Rebinding, replacement, retry and destruction invalidate the generation.
The caller must also recheck the current asset mapping where it can change.

The common contract should cover request identity, dimensions, status transitions,
retry and asset-change observation. Keep these choices with each presenter:

- Map: camera restoration, image revision, edge treatment and crossfade.
- Atlas/summary: thumbnail fitting and bounded layout.
- Attachment: availability message and enlarged viewer in the originating host.
- Decoration: fit/fill/stretch, offsets, opacity and contrast fallback.
- Compass: image aspect, north orientation and independent text.

Do not add an unrelated cache: the engine and current appearance helper already
cache asset state. `CreateSceneView` has fallback dimension checks for cached
stills and streamed video; this is a robustness precedent, not proof that our
still-image loaders currently miss events. Test those cases before changing them.

### New input route: still-image drops and paste

[FileDrops.UploadImage](../../DMHub%20Core%20UI/FileDrops.lua#L106) is a public
helper extracted from Tabletop's new file-drop workflow. It returns an asset ID
that is available locally immediately; successful upload is a later callback.
That distinction matters for a shared map record. A local preview is not evidence
that another viewer can load the asset.

The mod-sized adaptation is a drop target on an existing image field: map artwork,
Location/path attachment, custom compass or decorative background. Use the current
still-image picker contract, author permissions and write methods. Do not make an
ordinary canvas drop replace map artwork or bypass its replacement reminder.

This **illustrative upload fragment** assumes the caller has already accepted one
supported still image and bound `request` to the current field/editor generation:

```lua
local function UploadStillForField(path, request)
    local drops = rawget(_G, "FileDrops")
    if type(drops) ~= "table" or type(drops.UploadImage) ~= "function" then
        return nil
    end
    if not request.isCurrent() or not request.canEdit() then return nil end
    return drops.UploadImage(path, {
        upload = function(imageId)
            if request.isCurrent() and request.canEdit() then
                request.acceptUploaded(imageId)
            end
        end,
        error = function(message)
            if request.isCurrent() then request.showError(message) end
        end,
    })
end
```

`request` and its callbacks are proposed mod-local adapters. `acceptUploaded` must
use the existing field validation and save path; the immediate return value may
only drive a scoped preview. Production code also needs the picker's library/type
options, cancellation and stale-error handling, and a definition of how an upload
interacts with pending edits. Closing or rebinding invalidates the request; it
does not cancel an already started native upload. Keep the old saved reference on
failure and preserve Retry. Accept only supported still formats and retain image
dimension checks, regardless of the file extension.

[FileDrops.ShowGhost](../../DMHub%20Core%20UI/FileDrops.lua#L146) supplies reusable
drop feedback with an `isActive` lifetime predicate. The new
[clipboard image/file APIs](../../Definitions/dmhub.lua#L1757) are another optional
input route, but require separate capability checks and the same validation;
clipboard file enumeration is Windows-specific. The current picker remains the
fallback.

Do not call [TableDropDialog](../../DMHub%20Game%20Hud/TableDropDialog.lua#L3) as a
Region Map import wizard. It creates tactical maps, scenes or journal items and
uses a 140-pixel-square heuristic, which has no relationship to our calibrated
regional distances. Similarly,
[DocumentImport.ImportFiles](../../DocumentSystem/DocumentImport.lua#L1922) creates
journal content; it does not validate our JSON import format. Video, audio,
creature drops and document conversion are outside this adaptation.

## 6. Editors, commands and persistence

Tabletop's [share-store interface](../../DMHub%20Game%20Hud/Tabletop.lua#L3994)
lets one widget work with tactical map visibility or shared-document items.
**Source excerpt:**

```lua
--- @class TabletopShareStore
--- @field state fun(): nil|string nil, "all" or "some"
--- @field isSharedWith fun(userid: string): boolean
--- @field share fun() share with every player (a click)
--- @field unshare fun()
--- @field shareAll fun() "All players" in the menu
--- @field setPlayer fun(userid: string, on: boolean)
```

[DocStore](../../DMHub%20Game%20Hud/Tabletop.lua#L4005) and
[MapStore](../../DMHub%20Game%20Hud/Tabletop.lua#L4033) implement it;
[ShareControl](../../DMHub%20Game%20Hud/Tabletop.lua#L4219) consumes it. These are
private Tabletop implementations. The adaptable idea is a small control-to-data
boundary where more than one real backend needs the same UI.

### Autosave and draft lifecycle

[Location autosave](../OverlandMapSidePanel.lua#L280) and
[path autosave](../OverlandMapPathPanel.lua#L186) independently track pending fields,
debounce timers, busy retries and lifecycle flushing. Share the scheduling and
draft-lifetime mechanics while preserving their backing-store differences.

Our [SaveQueue](../OverlandMapUndo.lua#L287) already provides immutable batches,
failure recovery, permission checks and observers. The current aid wiring is a
**source excerpt** showing the existing adapter pattern:

```lua
local queue = RegionMapUndo.SaveQueue {
    canEdit = Aids.CanEdit,
    busy = function(id) return R.PendingWrite(C.locationTableName, id) ~= nil end,
    send = function(id, batch, callbacks)
        local change = batch.changes
        return Model.SetMapAid(id, change.aid, change.patch, change.action, callbacks, batch.retry)
    end,
}
```

This excerpt relies on the aliases defined in [RegionMapAids](../OverlandMapAids.lua#L21).
Do not assume a Location edit is one equivalent batch: its name, public details
and private note use separate stores and completion callbacks. Preserve existing
Undo grouping and recovery behavior when deciding whether to extend SaveQueue or
extract only common scheduling.

Import drafts require a discard decision; log notes have their own save-on-close
behavior. They can participate in a shared host-lifecycle contract without being
converted into the same autosave policy. Inspect and test each close path before
claiming consistency. The [maintenance audit](CLEANUP_AUDIT.md) records this as an
evidence gap, not an established data-loss bug.

Tabletop's [SaveLayout/SaveSoon](../../DMHub%20Game%20Hud/Tabletop.lua#L232) writes
a deferred personal layout snapshot. It does not replace our shared
[WriteRow](../OverlandMapRecords.lua#L557), per-table revision rules, Retry or guarded
Undo. [RegisterCompanion](../OverlandMapModel.lua#L108) already connects optional
content to deletion, permission changes and Undo; retain and extend that mechanism.

### Actions and removal summaries

Atlas and Location actions already share
[MenuEntries](../OverlandMapSidePanel.lua#L162). Avoid creating a generic command
framework merely to wrap that code. Extract a reusable action only when another
surface, such as an approved drop target, needs it.

A concrete opportunity is removal planning. The
[confirmation UI](../OverlandMapSidePanel.lua#L52) computes affected descendants and
paths while [model deletion](../OverlandMapModel.lua#L1240) separately computes the
actual cascade. A read-only model summary could supply the confirmation counts and
Party consequence from the same planning logic used by execution. Execution must
revalidate permission, pending writes and changed contents before acting; a cached
summary must never authorize a later destructive operation by itself.

This is a prevention/maintenance proposal. The audit did not reproduce a count
mismatch. It must preserve whole-operation Undo, optional aids, labels, sidecars,
and all existing Party rescue behavior.

### Sharing remains distinct from presenting

Pin visibility, map sharing and Show to players mean different things in this mod.
[RegionMapPresent](../OverlandMapPresent.lua#L3) is a one-shot presentation with a
nonce, expiry and delayed-share handling. Tabletop's persistent item sharing and
forced maximization must not replace those semantics.

The share-store boundary may help a future design for per-map player edit settings
(open idea 21). Per-player sharing audiences are a separate product/data decision;
they are not implied by that idea. Existing visibility filtering remains UI-only,
as documented in the mod's accepted data contract; this report adds no server-side
privacy guarantee.

### New collaboration precedents

The rebase adds three separate behaviors. None is a replacement for
`RegionMapPresent`:

| Tabletop behavior | Potential Overland Map use | Required boundary |
|---|---|---|
| [Director placement following](../../DMHub%20Game%20Hud/Tabletop.lua#L9860) publishes item rectangles and source viewport size; a player's move/resize opts out until Follow is selected | Optional following of a Director's map view | Use map identity and image-space camera state, not tabletop window rectangles; define opt-out and navigation behavior |
| [Pings](../../DMHub%20Game%20Hud/Tabletop.lua#L10160) use transient remote events, sender identity, duplicate suppression, a per-key send limit and shared-item visibility checks | Draw attention to a visible Location or map coordinate | Own event name, map/image revision, normalized coordinates, expiry, deduplication, rate limit and recipient access checks; no Party movement or shared-row save |
| [Director's Screen](../../DMHub%20Game%20Hud/DirectorScreen.lua#L3) uses where an item is dropped to decide sharing; held-back items are faded | Clear feedback about private/shared state | Do not attach spatial sharing semantics to our pins, aids, references or host without a separately decided contract |

The useful refactoring pattern is to keep durable content, personal view state and
ephemeral attention events separate. A coordinate ping should be ignored when its
map/image binding is stale or inaccessible, and should not move the camera or
open another map unless that behavior is explicitly designed. Following likewise
needs a separate opt-in lifecycle, permission reconciliation and competing-Director
policy; copying the new table-rectangle protocol would not solve those concerns.

These are optional collaboration ideas, not additions to the approved feature.
The generic personal item API described below does not participate automatically
in Tabletop's sharing, pings, placement following or Director's Screen.

## 7. Targeted refresh and performance

Tabletop retains panels and avoids repeated work when relevant state is unchanged.
**Source excerpt** from [SyncShares](../../DMHub%20Game%20Hud/Tabletop.lua#L4696):

```lua
table.sort(forcedIds)
local signature = string.format("%s|%s", tostring(doc.data.seq), table.concat(forcedIds, ","))
if signature == g_shareSignature then
    return
end
g_shareSignature = signature
```

Region Map already uses revision/signature caches, pooled cards and path pieces,
batched log rows, and direct layer translation during panning.
[RefreshAll](../OverlandMapPanel.lua#L728) still binds several components together,
but a bind does not necessarily rebuild them. Instrument before restructuring it.

Useful update domains would be:

| Change | Views normally affected |
|---|---|
| Camera pan/zoom | Canvas layout and visible drawing pieces |
| Selection | Selected controls, reader/editor and relevant highlighting |
| Attachment completion | Owning presenter and dependent geometry |
| Save status | Editor status and toast state |
| Path style | Affected paths and path editor/sample |
| Party/log update | Party display, travel choices, route and log |
| Permission/view-mode change | Immediate global visibility and active-operation reconciliation |

Any cache key must include its actual dependencies: map identity, relevant record
revision, selection, permissions, personal visibility, pending queue version and
asset state as appropriate. A global table revision alone cannot represent every
input. Retain a full reconciliation path and never skip permission cleanup because
a visual signature appears unchanged.

Measure bind counts, panels created/destroyed, style writes, layout time and frame
time on the same fixture before and after a change. Preserve the existing
[rendering constraints](../README.md#5-performance): panning uses `panel.x/y`,
style writes are cached, and zoom settles before expensive final placement.
Changing polling to native drag events does not by itself demonstrate a speedup.

## 8. Atlas, navigation and content previews

Tabletop's [ShowPreviewTooltip](../../DMHub%20Game%20Hud/Tabletop.lua#L3153)
combines a map name, status and bounded thumbnail. Its tactical snapshot and combat
status do not apply here, but the composition can serve breadcrumbs and search.

An **illustrative summary reader using existing model APIs** is:

```lua
local function ReadMapSummary(id)
    local map = RegionMapModel.GetLocation(id)
    if map == nil or not RegionMapModel.CanOpenMap(map) then return nil end
    local party = RegionMapModel.Party()
    local result = {
        id = map.id,
        name = RegionMapModel.DisplayName(map),
        imageId = map.imageId,
        visibleCount = RegionMapModel.VisibleDescendantCount(map.id),
        partyInside = party ~= nil and RegionMapModel.IsInSubtree(map.id, party.mapId),
    }
    if RegionMapModel.IsDirector() then result.mapShared = map.mapShared end
    return result
end
```

The presenter must escape literal text using existing copy helpers, bound its
dimensions, and recheck visibility when refreshed. Descriptions must use the
existing public preview rules; Director notes do not enter the summary. The
example returns data and creates no panels or shared writes.

[Atlas cards](../OverlandMapAtlas.lua#L111) already reuse panels and only change the
thumbnail image when its ID changes. Breadcrumbs already have filtered text
previews and rebuild when their path/name key changes. A common summary helper is
worth introducing when an approved second presentation actually needs it.

Possible extensions, all requiring product decisions:

- **Breadcrumb/search map preview:** identify the destination without leaving the
  current map. Respect Show hover text and immediate dismissal; retain a non-hover
  route to details. Use source artwork, not `#MapSnapshot`.
- **Pinned reference card:** keep a Location/path description or attachment visible
  while selecting something else. Keep read-only reference state separate from
  the active editor; define close, refresh and access-revocation behavior.
- **Personal shortcuts/recent maps:** reuse per-viewer/game preferences and current
  access checks. Do not keep an inaccessible map alive through a cached shortcut.
- **Contextual action strip:** expose frequent selected-object actions near the
  object, while retaining menus and keyboard alternatives. Bound it against the
  canvas and other controls; avoid adding a toolbar to every pin.

### New public integration: personal table references

[Tabletop.itemKinds](../../DMHub%20Game%20Hud/Tabletop.lua#L7980) now lets another
module supply a content face while Tabletop owns movement, resizing, removal and
personal layout persistence. The concrete external consumer is
[Audio's soundboard kind](../../DMHub%20Core%20Panels/Audio.lua#L4239). This makes a
pinned map/Location reference a practical optional integration, without creating a
second live Overland Map canvas or copying private card-frame functions.

| Kind member or API | Verified responsibility |
|---|---|
| `available()` | Kind-wide availability for this viewer; false hides its items while retaining their saved layout entries |
| `exists(key)` | Record lifetime; false removes the item from the table and saved personal layout |
| `size(key)`, `face(key)` | Base dimensions and module-owned content panel; the face owns data/theme refresh and interactions |
| `defaultScale`, `cornerRadius` | Optional initial scale and shadow shape |
| `name(key)` | Documented in the kind contract, but the current generic item builder does not consume it; supply explicit naming/hover behavior in the face |
| [OpenItem](../../DMHub%20Game%20Hud/Tabletop.lua#L8193) | Opens or raises one item per kind/key; optional `screen` position is in screen pixels |
| [ItemRowDragging](../../DMHub%20Game%20Hud/Tabletop.lua#L8310), [ItemRowDragEnded](../../DMHub%20Game%20Hud/Tabletop.lua#L8296) | Reuse the face for a noninteractive drag preview and clean it up |

Register a uniquely named kind such as `overland-map-reference`, with stable map
or Location IDs as keys. This **illustrative opener** uses existing APIs after
that kind has been registered:

```lua
local function OpenMapReference(mapId, screen)
    local tabletop = rawget(_G, "Tabletop")
    if type(tabletop) ~= "table"
        or type(tabletop.itemKinds) ~= "table"
        or tabletop.itemKinds["overland-map-reference"] == nil
        or type(tabletop.IsActive) ~= "function"
        or type(tabletop.OpenItem) ~= "function" then
        return
    end
    if not tabletop.IsActive() then return end
    local map = RegionMapModel.GetLocation(mapId)
    if map == nil or not RegionMapModel.CanOpenMap(map) then return end
    tabletop.OpenItem("overland-map-reference", mapId, {screen = screen})
end
```

This opens a reference face, not a live map window. The face should use the common
viewer-filtered summary and image request contract, and explicitly implement any
Open map action. Tabletop does not supply automatic content refresh, click-to-open
behavior or permission filtering for the module's face.

There are two important lifetime limits. The generic item builder checks
availability/existence once per second; that is insufficient for immediate
permission revocation. Its `available()` is kind-wide, while `exists(key) == false`
permanently removes that saved reference. The mod must separately reconcile
per-record access and decide whether inaccessible references are redacted or
removed. Never leave cached content visible until the next polling tick.

Registration and faces also need mod-unload guards, correct game binding, scoped
observers and theme refresh. Inspect registration ownership on reload instead of
overwriting another module's kind. Preserve Show hover text for any hover-only
content. The persisted `{kind, key, x, y, scale}` is personal layout, not a shared
map edit or an Undo operation. Layout privacy does not make the underlying map
data private. Keep this optional when the public APIs or tabletop host are absent.

## 9. Drag-and-drop, windows and larger extensions

Tabletop's [RowDragging](../../DMHub%20Game%20Hud/Tabletop.lua#L5987) creates
noninteractive previews on demand, moves them while the target is valid, and
destroys them when the operation ends. Its
[map-row preview](../../DMHub%20Game%20Hud/Tabletop.lua#L6279) is another precedent.

An **illustrative preview lifecycle fragment** is:

```lua
local function UpdatePreview(preview, parent, createPreview, allowed, x, y)
    if allowed and (preview == nil or not preview.valid) then
        preview = createPreview()
        parent:AddChild(preview)
        preview:MakeNonInteractiveRecursive()
    end
    if preview ~= nil and preview.valid then
        preview:SetClass("collapsed", not allowed)
        if allowed then preview.x, preview.y = x, y end
    end
    return preview
end
```

The parent must be valid, the returned preview retained by the operation, and the
preview destroyed on release/cancellation/teardown. `x/y` must be in that parent's
coordinate system. Target resolution belongs to Region Map's own UI; engine
`tabletopDragSurface` and `panelDropSurface` describe tactical-map/table targets,
not our image canvas.

A drop could become an alternative to an existing placement or Move to map action.
It must not silently create new reparenting semantics. Current
[MoveToMap](../OverlandMapModel.lua#L818) rejects invalid descendants, checks rights,
removes connected paths, can move Party state, and places the Location at the
destination's centre. A position-specific drop would need a deliberately extended
model operation and one coherent Undo, not two unrelated writes. Consequences
should be previewed and confirmed where the existing action requires it.

### New public integration: minimizing the existing host

Tabletop now provides [external-window helpers](../../DMHub%20Game%20Hud/Tabletop.lua#L2897).
This changes the earlier assessment that window adaptation only had private
implementations to study. The
[PDF viewer](../../DMHub%20Core%20Panels/JournalPDFViewer.lua#L4531) is an existing
consumer of `MinimizeExternal` and `RestoreExternal`.

| Responsibility | Owner |
|---|---|
| Window panel, content, saved geometry, hide/show/focus, pending-editor lifecycle | Region Map |
| Record with `id`, a stable `railKey`, and `buttonOps` including an image callback | Region Map; use the existing button-operation contract |
| Transient `minimized`, `iconX/iconY` and minimized button; animation between rectangles | Tabletop helper |
| Availability check, close cleanup and rail-removal callback | Region Map calls `CanMinimizeExternal`, `CloseExternal`, and `UndockExternal` at the appropriate transitions |

Rectangles are `{x, y, w, h}` in documents-layer units, with a top-left origin.
`PanelRect` converts an in-app panel; `LayerRect` describes the whole documents
layer. The helper does not persist external window state with Tabletop's layout,
and calling minimize does not hide the owning window. Reuse our existing host
state and geometry persistence, and define how its current rail shortcut relates
to a new minimized button so closing one does not purge an unrelated rail entry.

This **illustrative restore adapter** shows the extra lifetime check needed around
the public callback. `host` is a proposed mod-local adapter, and the caller has
already verified all required helpers and an in-app documents-layer host:

```lua
local function RestoreHost(tabletop, record, rectangle, host)
    if not host.isCurrent() or not record.minimized then return end
    local generation = host.generation
    tabletop.RestoreExternal(record, rectangle, function()
        if not host.isCurrent() or host.generation ~= generation then return end
        if record.closed or record.minimized then return end
        host.showAndFocus()
    end)
end
```

The owner increments its generation on close, replacement or host change. A late
animation callback must not reopen a closed window or override a newer minimize.
Minimize is not host teardown: decide explicitly whether a draft stays bound or
flushes, while retaining the existing navigation/close rules. Native OS popouts
remain a separate lifecycle; these helpers do not bridge them into Tabletop.

### Window discovery and scope limits

The new [window switcher](../../DMHub%20Game%20Hud/WindowSwitcher.lua#L265) collects
tactical maps, scenes and recognized journal windows. The
[Windows menu](../../DMHub%20Game%20Hud/Tabletop.lua#L9720) has the same fixed kinds.
There is no public provider registry for an arbitrary mod window. Neither an
external minimized button, `raiseOnPress`, nor a rail entry automatically adds
Overland Map to these collectors. The new
[activationOrder](../../Definitions/Panel.lua#L96) property is an MRU ordering
counter, not a registration mechanism. `WindowSwitcher.JournalWindows` exposes a
getter, not a provider hook.

If system-wide discovery becomes a requirement, it needs a small public core hook
outside this mod's current scope. Do not monkeypatch the collectors or disguise
Overland Map as a journal window. Its existing rail shortcut remains a working
entry point without such an integration.

Tabletop's [snapping](../../DMHub%20Game%20Hud/Tabletop.lua#L354),
[map-window minimize](../../DMHub%20Game%20Hud/Tabletop.lua#L2828), and
[restore](../../DMHub%20Game%20Hud/Tabletop.lua#L2867) remain useful references.
Our [approved window scope](PANEL_VIEW_BRIEF.md#decision-map-and-exclusions)
explicitly excludes snapping, side docking, tabs and simultaneous map windows.
Its full containment differs from Tabletop's partial-offscreen clamp. Minimize
through the new public helpers is feasible, but its value still needs weighing
against the current rail's reopen/raise action. Multiple live views would require
separate camera, selection, draft, observer and permission lifetimes; this report
does not propose that architecture. The new tactical map rail and creature-drop
targets do not change those boundaries.

## 10. Paths, route history, ruler and native drawing

Separating content from presentation also applies to geometry. Current
[Paths.Points](../OverlandMapPaths.lua#L154) is already shared by rendering and
[travel slicing](../OverlandMapTravel.lua#L73). The mod also has shared pools and
stretch/clipping helpers; do not reimplement those as a new drawing framework.

A useful future boundary would make authored points, sampled/visible geometry,
hit testing, arc-length lookup and stroke presentation explicit. This matters if
curves or a different renderer are approved: visible paths, selection, labels,
Party positions and historical routes must agree.

The [native Shapes API](../../Definitions/Shapes.lua) is adjacent capability
research, not a feature provided by Tabletop's `#ShapesView`. Existing
[curved-path research](CURVED_PATHS_RESEARCH.md) recorded these synthetic
construction observations:

| Fixture | UI-panel drawing | Shared native shape surface |
|---|---|---|
| 50 paths, 24 segments, casing plus stroke | 2,400 panels; about 369 ms | 100 shapes; about 6 ms |

Those figures do not include equivalent complete deferred rendering/GPU work and
are not production FPS comparisons. The research also records unresolved mesh
cleanup, texture-resolution and repeated-rebuild questions. No in-place point
update or dash-pattern API was established. Retain the production renderer until
resource cleanup, zoom sharpness, stroke patterns and frame-time behavior are
verified. If investigated, use a shared drawing surface rather than one per path.

## 11. Recommended sequence and acceptance

| Order | Work | Observable acceptance |
|---|---|---|
| 1 | Consolidate image-request and editor lifecycle mechanics | Replacement, retry, navigation and close retain current ownership and save behavior |
| 2 | Extract common canvas gesture handling and selection controls | Consistent cursor/handle behavior; specialized pin, Party, path and measurement rules unchanged |
| 3 | Derive operation summaries from model planning where duplicated | Confirmation and execution use the same rules and revalidate before writing |
| 4 | Measure and narrow refresh work where expensive | Fewer unnecessary binds/style writes with no stale permissions, selection or feedback |
| 5 | Design bounded map previews | Faster identification without navigation or disclosure of filtered fields |
| Optional integration | Evaluate public personal-item and still-image-drop APIs first; external minimize next if useful | A concrete benefit without duplicating card chrome, upload plumbing or host state |
| Later | Evaluate pings, view following and alternate drawing separately | Each earns its own design and live evidence |

The first work should be behavior-preserving refactoring with small adapters and
existing helpers. Do not combine image loading, editor persistence and all input
tools into one universal object framework. Runtime file splits require normal live
CodeMod registration; this report creates no runtime component or dependency.

Before an optional Tabletop integration, check the actual running APIs, not just
this checkout. The rebased [IsActive](../../DMHub%20Game%20Hud/Tabletop.lua#L149)
means an in-game, non-lobby session; the old `tabletop:enabled` setting is no longer
its activation contract. A missing global in the current app is an unavailable
feature, not a disabled setting to switch on. Retain existing mod behavior when
the helper is absent, incomplete, inactive or its layer is not ready.

Validation for any approved implementation should include:

- Existing eight offline suites and focused new checks for the behavior changed;
  Lua syntax/ASCII and full LuaLS for runtime changes.
- Fullscreen, minimum in-app window and native popout; Font Size 80/100/140;
  contrasting themes; dense maps and long content.
- Pointer leaving the canvas/window, overlapping targets, locked state, Escape,
  navigation, host changes and destruction during active gestures.
- Pending saves, busy rows, failure/Retry, remote changes simulated offline, one
  Undo per operation, and permission revocation during previews or callbacks.
- Cached/missing/replaced images, timeout followed by late success, stale uploads,
  callback ownership, and unchanged references after a failed load.
- View as player, personal preference isolation, immediate hover-text dismissal,
  and source-content filtering on every preview/reference surface.
- Optional integrations with APIs absent and present; fresh/partial layer layout;
  personal references after deletion, revoked access, game change and mod reload;
  minimize/restore followed by close, re-minimize or a popout transition; no
  automatic sharing from personal cards or spatial placement.
- File-drop rejection and upload completion after rebinding, close or permission
  loss; clipboard support absent; old references retained on failure. Pings/follow,
  if approved, need offline stale-message, duplicate, rate-limit and audience tests.
- Comparable performance fixtures and resource observations before claiming an
  optimization. Preserve the requested skip of two-client live tests.

Preserve the existing scope decisions in [IDEAS](../IDEAS.md): deferred hex work,
saved-for-later multi-leg routing, and unresolved font/engine capabilities are not
authorized by this report. Tactical tokens, combat, arbitrary desktop windows,
and engine development remain outside this mod assessment.

## 12. Tabletop source map

| Topic | Source entry point |
|---|---|
| Whole implementation | [Tabletop.lua](../../DMHub%20Game%20Hud/Tabletop.lua) |
| Personal placement persistence | [SaveLayout / SaveSoon](../../DMHub%20Game%20Hud/Tabletop.lua#L232) |
| Window clamp and snap | [ClampWindow](../../DMHub%20Game%20Hud/Tabletop.lua#L341), [SnapWindow](../../DMHub%20Game%20Hud/Tabletop.lua#L354) |
| Live/frozen map window | [BuildWindow](../../DMHub%20Game%20Hud/Tabletop.lua#L1846) |
| Host reparenting | [PlaceWindow](../../DMHub%20Game%20Hud/Tabletop.lua#L2217) |
| Hover preview | [ShowPreviewTooltip](../../DMHub%20Game%20Hud/Tabletop.lua#L3153) |
| Store boundary and sharing control | [TabletopShareStore](../../DMHub%20Game%20Hud/Tabletop.lua#L3994), [ShareControl](../../DMHub%20Game%20Hud/Tabletop.lua#L4219) |
| Change gating | [SyncShares](../../DMHub%20Game%20Hud/Tabletop.lua#L4696) |
| Content scaling | [ApplyCardScale](../../DMHub%20Game%20Hud/Tabletop.lua#L5079) |
| Resize behavior | [CardGrip](../../DMHub%20Game%20Hud/Tabletop.lua#L5115), [CardGrips](../../DMHub%20Game%20Hud/Tabletop.lua#L5239) |
| Transient drag previews | [RowDragging](../../DMHub%20Game%20Hud/Tabletop.lua#L5987), [MapRowDragging](../../DMHub%20Game%20Hud/Tabletop.lua#L6279) |
| Document content/frame composition | [BuildDocItem](../../DMHub%20Game%20Hud/Tabletop.lua#L7308) |
| Reused scene content | [BuildSceneWindow](../../DMHub%20Game%20Hud/Tabletop.lua#L8628), [CreateSceneView](../../DMHub%20Game%20Hud/FullscreenDisplay.lua#L101) |
| Activation and layout readiness | [IsActive](../../DMHub%20Game%20Hud/Tabletop.lua#L149), [LayerReady](../../DMHub%20Game%20Hud/Tabletop.lua#L305) |
| Personal item extension | [Kind contract](../../DMHub%20Game%20Hud/Tabletop.lua#L7980), [OpenItem](../../DMHub%20Game%20Hud/Tabletop.lua#L8193), [Audio consumer](../../DMHub%20Core%20Panels/Audio.lua#L4239) |
| External-window integration | [Contract and helpers](../../DMHub%20Game%20Hud/Tabletop.lua#L2897), [PDF consumer](../../DMHub%20Core%20Panels/JournalPDFViewer.lua#L4531) |
| Window discovery limit | [CollectWindows](../../DMHub%20Game%20Hud/WindowSwitcher.lua#L265), [WindowsMenuEntries](../../DMHub%20Game%20Hud/Tabletop.lua#L9720) |
| Image upload/drop helpers | [UploadImage](../../DMHub%20Core%20UI/FileDrops.lua#L106), [ShowGhost](../../DMHub%20Core%20UI/FileDrops.lua#L146), [TableDropDialog](../../DMHub%20Game%20Hud/TableDropDialog.lua#L3) |
| Collaboration | [Director placement](../../DMHub%20Game%20Hud/Tabletop.lua#L9860), [Pings](../../DMHub%20Game%20Hud/Tabletop.lua#L10160), [Director's Screen](../../DMHub%20Game%20Hud/DirectorScreen.lua#L3) |
| Theme and subtree rendering | [Theme refresh](../../DMHub%20Game%20Hud/Tabletop.lua#L948), [groupOpacity](../../Definitions/Style.lua#L68), [boxShadow](../../Definitions/Style.lua#L89) |

Related Region Map references: [current behavior](../README.md),
[maintenance candidates](CLEANUP_AUDIT.md), [window contract](PANEL_VIEW_BRIEF.md),
[map-aids contract](MAP_AIDS_BRIEF.md), [appearance contract](TEXT_APPEARANCE_BRIEF.md),
and [validation evidence](../tests/README.md).

Report checks after the rebase: relative file/heading links and numeric line
anchors were checked, including the source symbols at relocated anchors. All 14
Lua examples pass the repository interpreter's syntax check and contain ASCII
only; source excerpts were compared with the current files. The pure resizing
example passes the 64 assertions described above. GUI examples were not executed
live. This review changed documentation only; it did not deploy the rebased code
or rerun runtime suites/LuaLS for the pre-existing Lua changes.
