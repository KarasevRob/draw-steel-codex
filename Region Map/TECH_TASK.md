# Region Map - Technical Task: bring the mod to project standards

**Superseded by [TECH_TASK_V2.md](TECH_TASK_V2.md).** Kept for history: the V1 code is gone and V1 data is no
longer read.

Status: implemented in source 2026-10-05, except RM-21 (skipped on request); live
verification and file registration outstanding (see "Implementation record" below).
Written 2026-10-04 from a full review of the working tree (code, UI flows, host
integration, typing, performance, repo hygiene). Line numbers in sections 1-5 refer to the
2026-10-04 working tree, before the file split.

## Implementation record (2026-10-05)

| ID | State | Where |
|---|---|---|
| RM-01 | Done | `RegionMapPresent.lua` `Receive` / `ViewerBusy` / `AcceptFocus`: whole-map presents use the pending-focus slot with `labelId = nil`; busy viewers get an offer |
| RM-02 | Done | `RegionMapModel.LabelCount` counts what the viewer sees; `TotalLabelCount` for Director copy |
| RM-03 | Done | `gui.SearchInput` (editlag 0.15) in both lists; seams hidden while filtering |
| RM-04 | Done | `WriteParty` returns a reason; `PARTY_ERRORS` in the shell; Present disabled with a tooltip reason; players see Party status text, no dead button; card hides Move Party when the viewer can never use it |
| RM-05 | Done | Every confirm `execute` reports "The map changed before this could be applied." |
| RM-06 | Done | Map names escaped in Unpublish/Delete titles; all user text goes through `LiteralText` |
| RM-07 | Done | Canvas size changes only re-lay out; gestures are cancelled only on a layout-mode switch; workspace bar is one fixed row, collapsed when empty |
| RM-08 | Done | `RegionMap.lua` open handler `00-regionmap` seeds `_tmp_location` and defers to the rail; `FitHostWindow` via the DialogResize contract; dock mode keeps the floating window |
| RM-09 | Done | `PresentWithConfirm` in `RegionMapPresent.lua`; `persistAfterPresentation` removed |
| RM-10 | Done in source | One capability check; typed namespaces; no `RegionMapAddon`; narrow model API plus `RegionMapModel.testing`. `Main.lua` and `RegionMapViews.lua` are comment-only and must be removed in the in-app mod tools |
| RM-11 | See LuaLS result below | `@class` records, typed accessors, global-name definitions |
| RM-12 | Done | 13 files (README section 2). Largest: Panel 864, Canvas 817, Model 816 lines |
| RM-13 | Done | Card is the only label editor: double-click rename (session draft "name"), `deleteButton` + `requireConfirm`, Move on map; drawer editor and nudge buttons removed |
| RM-14 | Done | Navigation stack in the shell; one toolbar back button and Esc |
| RM-15 | Done | Present in toolbar (map) and card (location); one game-wide Party toggle, placed in the footer next to the Party status (the toolbar wrapped at 1000 px with it) |
| RM-16 | Done in source | Row grammar, chips, Phosphor Party glyph, section headers with `ExpandoArrow`, type scale, `deleteButton`, neutral/success/danger notice, layout classes, gear + right-click menu, canvas tool banner. Screenshots outstanding |
| RM-17 | Done | Canvas think 0.02 s only while hovered/focused/gesturing/loading, else 0.25 s; root think 0.25 s; layout from `rendered` via a scheduled event |
| RM-18 | Done | Camera saves debounced 0.5 s, flushed on map switch and destroy; one camera per visible map |
| RM-19 | Done | Coalesced refresh (0.05 s); one label index per refresh; precomputed sort keys; marker font written only on change. Timing not measured |
| RM-20 | Done | `cleanupComplete` on tombstones; one label scan per open |
| RM-21 | Skipped | On request. Old fixture backed up (below); it targets the removed `RegionMapAddon` API |
| RM-22 | Done | `README.md` and `docs/` in the mod; `REGION_MAP.md` and `output/region-map-review/` removed; `deploy.ps1` and `.gitignore` restored (personal script at `%USERPROFILE%\tools\deploy-codex.ps1`; `.serena/` and `.idea/` moved to `.git/info/exclude`) |
| RM-23 | Recommendations applied | README section 4 |

Backups of everything removed or reverted: `%USERPROFILE%\tools\region-map-backup-2026-10-04\`.

Live smoke test (2026-10-05, app build 10, Director session, 1000x800 test window): all
12 runtime files loaded from the repo through a scratch loader with in-memory tables, a
fake state document and a stubbed GameHud present slot (the CodeMod is not installed, and
`--harness` was not honored by this build). Verified: labels pane and live search; location
card, description edit and save, double-click rename, gear menu; library with Draft chip,
Party icon, escaped markup in names; Present sends `regionMapId`/`ttl`/nonce, is blocked on
drafts, and asks before replacing a live foreign presentation (RM-09); RM-01 busy viewer
keeps the inline editor text and gets a counting-down offer, accepting pushes a back entry,
an idle viewer switches at once; RM-02 counts 249 vs 254 by role; RM-04 `permission`
reason; player view hides Director controls and Director-only labels. Layout defects found
and fixed in that session: vertically centered pane/card content, toolbar wrap, oversized
pane/card headers, search field overflow, oversized checkbox, a Records helper split error.
Not covered: rail/dock open paths and `FitHostWindow` (needs the registered CodeMod),
multiplayer, font scales, Warm Gold scheme, 720x480.

Outstanding:
1. Register the new files in the Region Map CodeMod, in README order, with
   `mcp__dmhub__register_lua_file`. The CodeMod is not installed in the current game
   (it was removed on 2026-09-06), so registration needs a game where it exists.
2. Remove `Main.lua` and `RegionMapViews.lua` from the CodeMod in the in-app mod tools.
3. Live checks (section 5 items 4-5) and the upstream `check.ps1` run.

## 1. Scope and constraints

Region Map remains an **opt-in CodeMod** (nominally part of "Core modules", not part of the
core runtime). Every task below must respect these constraints:

| Constraint | Meaning for this task |
|---|---|
| **Zero core changes** | Edit only files inside `Region Map/`. Do not edit `DocumentSystem/`, `DMHub Core UI/`, `DMHub Game Hud/`, `Definitions/`, `DefaultStyles.lua`, `main.lua`, `deploy.ps1`, `.gitignore`, or `tests/`. |
| Opt-in mod | The mod may be installed against an older core. Feature-detect host APIs at one place and degrade without errors. |
| File registration | New `.lua` files are added to the mod's own CodeMod with `mcp__dmhub__register_lua_file` (`Region Map/<file>.lua`, with `before`/`after`), then confirm Firebase persistence. Never hand-edit `main.lua`. File removal (`Main.lua`) is done in the in-app mod tools; the MCP bridge cannot unregister. |
| Project standards | `CLAUDE.md`, `UI_BEST_PRACTICES.md`, `ThemeEngine.md`, `DefaultStyles.md`, `STYLE_GUIDE.md`. ASCII-only Lua. `borderBox = true` with padding. `@tokens` only inside ThemeEngine-routed rules. |
| Typing | New files must check clean (0 problems). |
| Reference module | `Draw Steel Respite/` (RSP*) is the closest in-repo example of a well-structured feature module: constants file, session/rules file, shell, one file per pane, typed namespaces. |

## 2. Baseline (2026-10-04)

| Check | Result |
|---|---|
| `..\dependencies\lua\bin\luac.exe -p` on all 7 files | Pass (stock Lua 5.4.6; engine is 5.4.7) |
| ASCII-only | Pass |
| Regression fixture (`output/region-map-review/regression.txt`) under standalone `lua.exe` | 56 / 56 groups pass |
| LuaLS 3.19.1 over the whole codex with the repo `.luarc.json` | **24 problems in Region Map** (18 warnings, 6 hints); target is 0 |
| Live app / multiplayer | Not verified (bridge unavailable during review) |

Tooling installed for this work (portable, outside the repo):

- `..\dependencies\lua\bin\{lua,luac}.exe`
- `..\dependencies\lua-language-server\bin\lua-language-server.exe`, run as
  `--check=<repo root> --checklevel=Hint --check_format=json --logpath=<dir>` (about 8 min),
  then filter `check.json` to `Region Map`. The upstream `tools/lua-typing/check.ps1` is not
  available on this machine; run it upstream before merge (read-only, no core change).

## 3. Task list

Priority: **P1** = correctness / data safety, **P2** = standards compliance needed for
integration, **P3** = quality / performance.

| ID | Pri | Title |
|---|---|---|
| RM-01 | P1 | Whole-map Present discards recipients' unsaved text |
| RM-02 | P1 | Label limit reveals Director-only labels to players |
| RM-03 | P1 | Label search filters only on Enter |
| RM-04 | P1 | Misleading errors and non-functional controls |
| RM-05 | P1 | Confirm dialogs silently do nothing when the guard expired |
| RM-06 | P1 | Map names unescaped in modal titles |
| RM-07 | P1 | Unrelated layout changes cancel an in-progress drag |
| RM-08 | P2 | Window opening and default size without hijacking the icon rail |
| RM-09 | P2 | Present: guard before replacing another presentation; remove dead flag |
| RM-10 | P2 | Bootstrap, namespaces and model API surface |
| RM-11 | P2 | Typing to 0 problems |
| RM-12 | P2 | Split the 2,490-line controller |
| RM-13 | P2 | Merge the legacy Labels drawer editor into the location card |
| RM-14 | P2 | One navigation/back mechanism |
| RM-15 | P2 | One place per action (Present, Party permission) |
| RM-16 | P2 | STYLE_GUIDE and ThemeEngine pass |
| RM-17 | P3 | Input polling cost |
| RM-18 | P3 | Camera persistence writes and unbounded camera keys |
| RM-19 | P3 | Full refresh cost on every shared edit |
| RM-20 | P3 | Deletion cleanup cost grows forever |
| RM-21 | P2 | Mod-local tests |
| RM-22 | P2 | Mod-local docs and artifact cleanup |
| RM-23 | - | Decisions required before release |

Suggested order: RM-01..07, RM-11, RM-10, RM-08, RM-09, RM-12..16, RM-17..20, RM-21/22
throughout. RM-01..07 and RM-11 need neither the running app nor new files.

---

### RM-01 (P1) Whole-map Present discards recipients' unsaved text

**Problem.** `HandlePresentation` (`RegionMapPanel.lua:1813-1816`) calls
`SetSelectedMap(map.id, true)` unconditionally. When the recipient is on another map,
`ApplySelectedMap` runs `CancelTransientInteraction` (`:695`, destroys the inline new-label
editor) and `CloseDrawer` (`:736` -> `DiscardDrawerDraft` `:364`, discards the label-rename
draft). The location-focus branch already checks a busy state (`:1805-1808`); the map branch
does not.

**Change.**
1. Extract the busy expression at `:1805-1808` into `local function ViewerBusy()` and use it
   in both branches.
2. Store whole-map presents in the existing `pendingFocus` slot with `labelId = nil`:
   ```lua
   root.data.pendingFocus = {
       nonce = args.nonce, mapId = map.id, labelId = nil,
       imageRevision = map.imageRevision,
       expiresAt = dmhub.Time() + math.min(args.ttl, 10) - age,
       generation = root.data.viewInteractionGeneration, phase = "offered",
   }
   if ViewerBusy() and root.data.selectedMapId ~= map.id then
       presentOffer.text = "View presented map"
       presentOffer:SetClass("collapsed", false)
   else
       AcceptFocus()
   end
   ```
3. `TryApplyPendingFocus` (`:1746`): when `pending.labelId == nil`, `FitCurrentMap(true)`
   instead of centering on a label. `AcceptFocus` (`:1721-1729`): skip label validation when
   `labelId == nil`.

**Acceptance.** A recipient with an open inline label editor containing text, on a different
map, receives a Present: the text survives, an offer appears, accepting it switches and fits
once. An idle recipient switches immediately (current behavior). New regression group.

### RM-02 (P1) Label limit reveals Director-only labels to players

**Problem.** `LabelCount` counts Director-only labels (`RegionMapModel.lua:465-467`); used at
`RegionMapPanel.lua:808, 838, 2031, 2410` and `Model:893`. Players are told "250 or more
labels" and lose Add Label while seeing fewer.

**Change.** Count what the viewer can see; the limit is already soft (overshoot is allowed):
```lua
local function LabelCount(mapId)
    return #LabelsForMap(mapId, dmhub.isDM)
end
```
Drive `state.labelCount` (`Panel:2031`) from the visible count; keep the total only for
Director-facing text (delete confirmation).

**Acceptance.** With 249 shared + 5 Director-only labels a player can add a label; a Director
cannot. Regression group for both roles.

### RM-03 (P1) Label search filters only on Enter

**Problem.** `edit`/`change` update a draft (`Panel:1282-1289`) but the list filters on
`root.data.labelSearch` (`:1332`), which only `enter` sets. Map search filters live
(`RegionMapViews.lua:88`).

**Change.** Use the house search control and filter live in both lists:
```lua
gui.SearchInput {
    classes = { "regionMapSearch" }, borderBox = true, editlag = 0.15,
    placeholderText = "Search labels",
    edit = function(element)
        root.data.labelSearch = TrimSingleLine(element.text)
        UpdateDrawerView()
    end,
}
```
Remove the `search` field from the drawer draft machinery. Style per STYLE_GUIDE "Search
field" (bordered variant, `@border`, focus `@fgStrong`, fontSize 13).

**Acceptance.** Typing filters both lists within 0.15 s; seams hide while filtering.

### RM-04 (P1) Misleading errors and non-functional controls

| Location | Problem | Change |
|---|---|---|
| `Panel:894` | Any failed Party placement says "Only the Director can move Party." | `WriteParty` (`Model:543`) returns `false, reason` with reason in `"permission" \| "unpublished" \| "invalid" \| "unavailable"`; map each to its own copy. |
| `Panel:2033`, `:1703` | Present enabled on drafts, then a modal error | `SetControlEnabled(presentButton, dmhub.isDM and map ~= nil and map.published)`; reason via `linger = gui.Tooltip(...)`. |
| `Panel:2554-2556` | Players get a clickable "Party: Director moves" button that does nothing | Director: toggle. Player: plain `gui.Label` (muted) with the status. |
| `RegionMapViews.lua:259` | Every card shows players "Only the Director can move Party." | Collapse the Move Party action when the viewer can never use it; show a reason only for transient unavailability. |

**Acceptance.** No control is clickable without effect; every error names the actual cause.

### RM-05 (P1) Confirm dialogs silently do nothing when the guard expired

**Location.** `Panel:1013, 1092, 1258` (`if not guard() then return end`).

**Change.** `if not guard() then SetNotice("The map changed before this could be applied.", 3); return end`.

### RM-06 (P1) Map names unescaped in modal titles

**Location.** `Panel:1066, 1087`.

**Change.** `string.format("Delete %s?", Model.LiteralText(current.name))`; audit every
`string.format`/concatenation of user text in the mod for the same.

### RM-07 (P1) Unrelated layout changes cancel an in-progress drag (plausible, not reproduced)

**Problem.** The canvas `think` cancels gestures on any size change (`Panel:2296-2302`). The
workspace bar wraps 50%-wide buttons (`:2573-2575`), so a banner appearing mid-drag (e.g. an
incoming Present offer) changes the canvas height.

**Change.**
1. Workspace bar: fixed single-row height, auto-width buttons, collapsed when empty.
2. Canvas `think` on size change: `UpdateCanvasLayout()` only. Cancel gestures only when the
   layout mode changes, which `UpdateWorkspaceLayout` already does (`:1592-1597`).

**Acceptance.** Showing/hiding the offer, unsaved-changes button or notice during a label or
Party drag does not cancel it; a side/bottom/full mode switch still does.

---

### RM-08 (P2) Window opening and default size without hijacking the icon rail

**Problem.** `RegionMap.lua:83-108` registers `"00-region-map-window"` so it sorts before the
rail's `"iconrail"` handler (`DockablePanel.lua:939`, `DocumentSystem.lua:11827`) and opens
its own 1000x800 window in every mode. Menu / Present / `ShowPanelByName` opens therefore skip
the rail button, anchoring, `RailSweepTransient`, geometry persistence (`onMoved`/`onResized`,
`DocumentSystem.lua:9126-9143`) and `RefreshRails`, while rail-button and pin opens
(`DocumentSystem.lua:20003`) use the rail: two different behaviors for one panel.

Root cause it was working around: rail windows open at `PanelDocument.DefaultWidth = 380`
(`DocumentSystem.lua:4602`) and `PresentPanel` does not clamp width to `minWidth` (`:4967`).

**Mod-only solution** using documented host contracts:
- `CustomDocument:PresentDocument` honors `self._tmp_location` size/position
  (`DocumentSystem.lua:4183-4188`; documented as the panel's remembered geometry at `:4587-4590`).
- External window resizes follow the overlay contract in `DMHub Core UI/DialogResize.lua:29-34`:
  write `selfStyle.width/height`, then announce deltas via `dialog.data.resizePanel`
  (`DocumentSystem.lua:4497-4501`; same pattern as the window shade, `:5545-5554`).

**Change A - cooperative open handler** (replace `RegionMap.lua:83-108`):
```lua
-- Runs before the icon rail's "iconrail" handler (ids run in sorted order) so the
-- first open of a session can carry the map's default size. In rail mode it only
-- seeds geometry and returns false: the rail still owns the button, anchoring,
-- pinning and persistence. With the rail off, a 720px canvas cannot live in a
-- 364px dock column, so the mod hosts its own floating window.
RegisterDockablePanelOpenHandler("00-regionmap", function(panelName, operation)
    if mod.unloaded or string.lower(panelName or "") ~= string.lower(PANEL_NAME) then
        return false
    end
    local doc = PanelDocument.Get(PANEL_NAME)
    if doc == nil then return false end
    if not doc:has_key("_tmp_location") and operation ~= "hide" then
        doc._tmp_location = {
            width = C.windowWidth, height = C.windowHeight,
            screenx = dmhub.screenDimensionsBelowTitlebar.x,
            screeny = dmhub.screenDimensionsBelowTitlebar.y,
        }
    end
    if rawget(_G, "RailModeActive") ~= nil and RailModeActive() then
        return false
    end
    -- legacy dock mode: keep the existing PresentDocumentOpen / PresentPanel / ClosePanel branch
end)
```
Leave `x`/`y`/`moved` unset so the rail's anchor and centering still apply
(`DocumentSystem.lua:4191-4199`). Seed only when `_tmp_location` is absent so a user-resized
or restored size is never overwritten.

**Change B - content-side correction** for opens that bypass handlers (rail button, pin,
restore). From the root `create`, `root:ScheduleEvent("regionMapFitHost", 0.01)` (not from
`rendered`; UI_BEST_PRACTICES forbids layout writes there):
```lua
-- Grow the host window to the map's minimum, or to its default on a first open at
-- the host's generic size. Follows the resize overlay's documented contract
-- (DMHub Core UI/DialogResize.lua): write the size, then announce it as deltas.
local function FitHostWindow(root)
    local window = root:FindParentWithClass("journalViewer")
    if window == nil or not window.valid or PanelDocument.IsPinned(PANEL_NAME) then return end
    local doc = PanelDocument.Get(PANEL_NAME)
    local w, h = window.selfStyle.width, window.selfStyle.height
    if doc == nil or type(w) ~= "number" or type(h) ~= "number" then return end
    local targetW = math.max(w, C.windowMinWidth)
    local targetH = math.max(h, C.windowMinHeight)
    if not doc:has_key("_tmp_location") and w == PanelDocument.DefaultWidth then
        targetW, targetH = C.windowWidth, C.windowHeight
    end
    if targetW == w and targetH == h then return end
    window.selfStyle.width, window.selfStyle.height = targetW, targetH
    local overlay = window.data.resizePanel
    if overlay ~= nil and overlay.valid then
        overlay:FireEventTree("resize", nil, { deltax = targetW - w, deltay = targetH - h })
    end
    doc._tmp_location = {
        x = window.x, y = window.y, width = targetW, height = targetH,
        screenx = dmhub.screenDimensionsBelowTitlebar.x,
        screeny = dmhub.screenDimensionsBelowTitlebar.y,
    }
end
```
Also keep the window on screen: if `window.x + targetW` exceeds the 1920-based virtual width
that `PresentDocument` positions in (`DocumentSystem.lua:4172`), shift `window.x` left.
Native popouts have no `journalViewer` ancestor and are a no-op (their height comes from the
registration's `popoutHeight`).

**Change C - registration.** Keep `minWidth = 720` (user resizes are already clamped by
`PanelDocument:WindowResizeOptions`, `DocumentSystem.lua:4652`). Keep deriving content
`minHeight` from `WindowResizeOptions` (public), moved into a named helper. Constants
`windowWidth`, `windowHeight`, `windowMinWidth`, `windowMinHeight` live in
`RegionMapConstants.lua` (RM-12).

**Containment.** `_tmp_location`, `data.resizePanel`, the `journalViewer` class and
`RailModeActive` are documented host details, not a formal API. Keep all of RM-08 in one
"host adapter" block in `RegionMap.lua`, guard with `rawget`/`pcall`, and fall back to the
host default size if any detail disappears.

**Acceptance.**
- Rail mode: first open from rail button, menu and Present each yields 1000x800; reopen in the
  same session keeps the user's size; pin, grouping, anchoring and the one-transient-window
  rule match other panels.
- Dock mode (`iconrail` setting off): opens as a floating window.
- Resize handles stay on the window edges after the content-side correction.

### RM-09 (P2) Present: guard before replacing another presentation; remove dead flag

**Context.** GameHud has one shared present slot (`GameHud.lua:1529-1608`); Negotiation,
Respite and Montage use it persistently. Using it is the established pattern. Presenting
replaces whatever is shown on every client (`GameHud.lua:1569-1573`).

**Change.**
1. Wrap both senders (`Panel:1709`, `:2515`):
   ```lua
   local function PresentWithConfirm(args)
       local raw = GameHud.GetPresentDialogDocRaw()
       local current = raw and raw.data and raw.data.dialog
       local foreign = current ~= nil and current.dialog ~= PANEL_NAME
           and (current.args == nil or current.args.ttl == nil
                or TimestampAgeInSeconds(raw.data.timestamp) <= current.args.ttl)
       local function Send()
           local nonce = dmhub.GenerateGuid()
           root.data.ignorePresentNonce = nonce
           args.nonce = nonce
           GameHud.PresentDialogToUsers(root, PANEL_NAME, args)
       end
       if not foreign then Send(); return end
       gui.ModalMessage {
           title = "Replace the current presentation?",
           message = "Players are viewing something else. Presenting the map replaces it.",
           options = { { text = "Present", execute = Send }, { text = "Cancel", execute = function() end } },
       }
   end
   ```
2. Delete `data.persistAfterPresentation` (`Panel:2594`): with `keeplocal = false` GameHud
   clears `m_presentedDialog` (`GameHud.lua:1537-1539`), so the flag never applies.

**Acceptance.** Presenting while a Negotiation is presented asks first; presenting over an
expired or Region Map presentation does not.

### RM-10 (P2) Bootstrap, namespaces and model API surface

1. **One capability check** in `RegionMap.lua`, only for host APIs an older core may lack
   (`RegisterDockablePanelOpenHandler`, `PanelDocument`, `GameHud.RegisterPresentableDialog`,
   `gui.IconEditor`). On failure: one visible message (print plus a chat/system notice), then stop.
2. **Remove per-file guards and `ready` flags** (`RegionMapPanel.lua:11-15`,
   `RegionMapViews.lua:8`, `RegionMap.lua:35-39`). CodeMod file order guarantees load order;
   the guards turn real load errors into silent "skipped" prints.
3. **Typed namespaces** instead of `RegionMapAddon = rawget(_G, "RegionMapAddon") or {}`,
   following `Draw Steel Respite/RSPConstants.lua:3-6`:
   ```lua
   --- Data access and permission rules for Region Map.
   --- @class RegionMapModel: GameType
   --- @field new fun(o?: table): RegionMapModel
   RegionMapModel = RegisterGameType("RegionMapModel")
   ```
   Keep `rawget(_G, ...)` only for genuinely optional globals (`EscapePriority`,
   `RailModeActive`).
4. **Model public API**: export only what the UI calls (map/label/sidecar/Party operations,
   view builders, preferences). `UploadRecord`, `Audit`, `PendingWrite`, raw table accessors
   become local (`RegionMapModel.lua:1016-1073` currently exports about 50 internals, contrary
   to the design doc's own rule). Expose internals for tests only as
   `RegionMapModel.testing`, created when the test sets `REGION_MAP_TESTING = true` before
   loading.
5. **`Main.lua`**: remove from the CodeMod file list in the in-app mod tools, then delete the
   file.

### RM-11 (P2) Typing to 0 problems

No shared stubs are regenerated (`gen_table_overloads.py` writes `Definitions/` and
`DMHub Utils/TableCache.lua`, which are core files).

1. Full `@class` blocks for the five record types, e.g.:
   ```lua
   --- A text label placed on a region map image (normalized u/v coordinates).
   --- @class RegionMapLabelRecord: GameType
   --- @field new fun(o?: table): RegionMapLabelRecord
   --- @field id string
   --- @field schemaVersion integer
   --- @field mapId string
   --- @field text string
   --- @field u number
   --- @field v number
   --- @field ownerId string
   --- @field ownerName string
   --- @field createdByDirector boolean
   --- @field visibility "shared"|"director"
   --- @field revision integer
   --- @field hidden boolean
   --- @field mutationId string
   --- @field createdBy string
   --- @field createdByName string
   --- @field createdAt any
   --- @field updatedBy string
   --- @field updatedByName string
   --- @field updatedAt any
   RegionMapLabelRecord = RegisterGameType("RegionMapLabelRecord")
   ```
   Same for `RegionMapRecord`, `RegionMapTombstoneRecord`, `RegionMapLocationDetailRecord`,
   `RegionMapLocationDirectorNoteRecord`.
2. Typed accessors instead of generated overloads:
   ```lua
   --- @return table<string, RegionMapLabelRecord>
   local function LabelsTable()
       return (dmhub.GetTable(Addon.labelTableName) or {}) --[[@as table<string, RegionMapLabelRecord>]]
   end
   ```
   Same for maps, tombstones and both sidecar tables; route `ReadSidecar` (`Model:693`) and
   `HideSidecar` (`Model:798`) through the accessors.
3. Current diagnostics:

   | Location | Diagnostic | Fix |
   |---|---|---|
   | `RegionMapModel.lua:27, 30, 33, 36, 38` | inject-field | `@class` blocks (item 1) |
   | `RegionMapModel.lua:728, 842` | need-check-nil | `if map == nil then return nil end` after `GetMap` |
   | `RegionMapPanel.lua:416` (x2) | need-check-nil | `local data = doc and doc.data; if data == nil then return end` |
   | `RegionMapPanel.lua:638-641` | need-check-nil | `if layout == nil then root.data.layout = nil; return end` |
   | `RegionMapPanel.lua:866, 868, 1237, 1243` | assign-type-mismatch | `local children = {} --- @type Panel[]` (and `result`) |
   | `RegionMapPanel.lua:822, 1277, 2658` | unused-local | remove or rename to `_` |
   | `RegionMapPanel.lua:1322` | need-check-nil, undefined-field | `local selected = nil --- @type RegionMapLabelRecord\|nil`, assign in an `if` |
   | `RegionMap.lua:88` | redefined-local | rename inner `document` to `panelDoc` |
   | `RegionMapViews.lua:109` | assign-type-mismatch (`stretch = true`) | stub false positive (`IconEditor.lua:75` consumes it); `---@diagnostic disable-next-line: assign-type-mismatch` with a one-line reason |

4. `@param`/`@return` on public functions; `--- @cast element Panel` in event handlers.

**Acceptance.** LuaLS reports 0 problems for every file under `Region Map/`; upstream
`check.ps1` passes before merge.

### RM-12 (P2) Split the 2,490-line controller

**Problem.** `CreateRegionMapPanel` (`RegionMapPanel.lua:206-2692`) is one closure with about
60 forward-declared locals and 22 `selfStyle` writes. It contradicts UI_BEST_PRACTICES (inline
child declarations, event-based communication, constants table).

**Target layout** (register each new file via MCP in this order):

| Order | File | Contents (moved from) |
|---|---|---|
| 1 | `RegionMapConstants.lua` (new) | All magic numbers: zoom steps 1.15 / 1.25, nudge 2 / 16 / 64, pane width 320 and gap 8, breakpoints 936 / 960 / 984, inline-editor offsets 130 / 112 / 18, think intervals, `LABEL_LIMIT`, `TEXT_LIMIT`, preview 400, draft cap 20, Present TTL 10, image timeout 10, window sizes (RM-08) |
| 2 | `RegionMapJournal.lua` | unchanged |
| 3 | `RegionMapModel.lua` | narrowed API (RM-10) |
| 4 | `RegionMapStyles.lua` | feature rules (RM-16) |
| 5 | `RegionMapCanvas.lua` (new) | image, markers, Party, focus halo, pointer/wheel/keyboard, camera (`Panel:443-680`, `:2089-2383`). Root handles `bindState`, `setTool`, `centerOn`, `fit`; fires `markerSelected`, `placeRequested`, `cameraChanged`. |
| 6 | `RegionMapLibrary.lua` (new) | manage-maps pane: list, create, rename, replace image, publish, delete (`Panel:954-1169`, `Views.CreateMapForm`, `Views.CreateMapList`) |
| 7 | `RegionMapLocationCard.lua` (new) | `Views.CreateLocationCard` plus RM-13 |
| 8 | `RegionMapPresent.lua` (new) | send/receive, pending focus, offer (`Panel:1700-1817`) |
| 9 | `RegionMapPanel.lua` | shell: toolbar, workspace layout, refresh routing, session drafts, navigation (RM-14) |
| 10 | `RegionMap.lua` | bootstrap, registration, host adapter (RM-08) |

`RegionMapViews.lua` is dissolved into 6 and 7. Components communicate with `FireEventTree`
and custom events; the shell holds references only to component roots.

**Acceptance.** No file over about 800 lines; regression suite green; behavior unchanged except
where other tasks change it.

### RM-13 (P2) Merge the legacy Labels drawer editor into the location card

**Problem.** Two label editors: `BuildLabelEditor` (`Panel:1181-1275`: name, audience
dropdown, nudge buttons, Move on map, Delete) and the location card (description, audience
toggle, Party, Present, journal). "Edit name" jumps from the card to the drawer
(`Panel:2494-2499`); Delete exists only in the drawer.

**Change.**
- Rename: double-click the card title (STYLE_GUIDE interaction grammar); the name draft joins
  the session draft cache as section `"name"` (this also removes the RM-01 drawer-draft loss
  path permanently).
- Delete: `gui.Button{ classes = {"deleteButton", "sizeS"}, requireConfirm = true, ... }`.
- Movement: keep keyboard nudges on the focused canvas and a "Move on map" action; drop the
  `< ^ v >` text buttons.
- Labels pane becomes a searchable list only; a row click calls `OpenLocation`.
- Delete `BuildLabelEditor`, `BuildNudgeRow`, `drawerDraft`, `EnsureDrawerDraft`,
  `UpdateDrawerDraft`, `MarkDrawerDraftSaved`, `drawerEditorKey`.

### RM-14 (P2) One navigation/back mechanism

**Problem.** Five back affordances: "Back to map", drawer header "Map", "Back to location",
"Back to previous view", plus per-surface Escape handling.

**Change.** A navigation stack owned by the shell:
```lua
root.data.nav = { { pane = "map" } }
-- push { pane = "location", id = ... }, { pane = "editor", section = ... }, { pane = "library" }
local function NavPush(entry) ... UpdateWorkspaceLayout() end
local function NavBack() if #root.data.nav > 1 then table.remove(root.data.nav) end ... end
```
One header back button (`phosphor/arrow-left-bold.png` plus the destination name) and Escape
both call `NavBack`. Present's return path pushes a snapshot onto the same stack.

### RM-15 (P2) One place per action

- Present: toolbar (map) and card (location). Remove "Present to Players" from the map form
  (`RegionMapViews.lua:122`).
- Party permission: one Director control in the toolbar labeled "Players can move Party (all
  maps)"; remove the checkbox from the per-map form (`RegionMapViews.lua:133`); players see
  status text only (RM-04).

### RM-16 (P2) STYLE_GUIDE and ThemeEngine pass

All rules stay in `RegionMapStyles.lua` via `ThemeEngine.MergeStyles`; nothing is added to
`DefaultStyles.lua`.

| Area | Current | Required |
|---|---|---|
| List rows (labels, maps) | Filled `@bgAlt` at rest, `vmargin`, 2px full border, no hover (`Styles:287-305`); map rows are bordered text buttons (`Views:75`) | Row grammar from `DMHub Core Panels/MapsPanel.lua` `{mapRow}`: transparent rest (`bgimage = "panels/square.png"`, `bgcolor = "clear"`), fixed `height = 34`, `width = "100%"`, `hpad = 12`, `borderBox = true`, no margins; hover `@bgAlt` with `transitionTime = 0.1`; selected `@bgAlt` + `border = {x1 = 3}` `@accent`, name bold `@fgStrong` via `parent:selected`; seams as `border = {y1 = 1}` `@border` at 0.2 opacity, hidden while filtering |
| Status tags | `[Draft] [Shared] [Party]` text (`Panel:1315, 1830`) | Right-aligned muted chip (10-11, `@fgMuted`) and 14px `phosphor/users-three.png`; text tags remain only inside dropdown options |
| Iconography | Party marker letter "P" (`Panel:492-501`); `< ^ v >` text buttons | Phosphor masks (`phosphor/users-three-fill.png` tinted by rule); nudges removed per RM-13 |
| Section headers | "Description" / "Director notes" as plain labels; notes toggle is a button | Header grammar: 13 bold `@fg`, 0.35-opacity underline; notes use `gui.ExpandoArrow` with `bgimage = "phosphor/caret-down-fill.png"` |
| Type scale | Literal `fontSize` 11-22 (`Styles:239, 256, 312, 319, 375, 383, 431, 444`) | Size classes / STYLE_GUIDE scale (rows 14, headers 13, reference 10-11) |
| Destructive styling | `regionMapDangerButton` custom color (`Styles:276`); `withDanger` on a text button (`Views:142`, no effect) | `deleteButton` + `requireConfirm`, or the `danger` class |
| Notice color | `@accent` (link color) (`Styles:443`) | `@fgMuted` neutral; `success` / `danger` classes by outcome |
| Dead rules | `compact` (`Styles:217`); `narrowHost` (`Styles:44`) applied via `SetClassTree` on every width change but never true (560 < 720 min) | Delete both and `ApplyResponsiveState` (`Panel:2045-2051`) |
| Inline `selfStyle` | Layout modes (`Panel:1603-1613`), half-width buttons (`Views:168, 214`, `Panel:2575`) | Classes `regionMapContent` + `side/bottom/full`, `regionMapPane` + `side/bottom`, `regionMapHalf`; canvas `width = "100% available"` in side mode (removes `"100%-328"`). Only the computed bottom-pane height stays in `selfStyle`. |
| Card density | 12+ stacked bordered buttons | Primary visible (Edit description, Move Party here, Present location); secondary (Reveal/Hide, journal link actions, Move on map, Delete) behind a `settingsButton` gear plus right-click menu |
| Tool instructions | Footer status line, far from the canvas | Floating banner at the top-center of the canvas (`floating = true` inline) |

**Acceptance.** ui-harness screenshots at 720x480, 1000x800 and wide; Font Size 80 / 100 /
140%; color scheme Default <-> Warm Gold tracks with no magenta (`THEME_ENGINE:: unresolved`)
log lines.

---

### RM-17 (P3) Input polling cost

Canvas `think` every 0.02 s (wheel, mouse buttons, seven `KeyPressed` reads) and root `think`
every 0.1 s run while the window is open, even idle (`Panel:2236, 2589`). Wheel polling itself
is the codex pattern (`CreateMapDialog.lua:4535`).

**Change.** Canvas `hover`/`dehover` set `thinkTime` to 0.02 / 0.25; key polling only when
`element.hasFocus`; root `think` at 0.25 keeping only the role check; workspace layout driven
by the content's `rendered` event (class toggles only).

### RM-18 (P3) Camera persistence writes and unbounded camera keys

Every wheel notch, zoom click and arrow pan rewrites the whole preferences setting
(`Panel:797, 2198, 2209, 2323`; `Model:624-634`). Camera keys are `mapId:imageRevision` and
never pruned (`Model:628`).

**Change.** Debounce: set a dirty flag and `root:ScheduleEvent("regionMapSaveCamera", 0.5)`;
flush on `destroy` and on map switch. In `SaveCamera`, keep only the current revision per map
and drop keys for maps not returned by `VisibleMaps()`.

### RM-19 (P3) Full refresh cost on every shared edit

Any change in the map/label/tombstone tables by any user runs `RefreshAll` directly
(`Panel:2627`), which re-validates every label in the game several times through pcall'd
`Field` reads, and sorts maps with a UTF-8 fold inside the comparator (`Model:325-332`).
During pans, `fontSize` is written to every marker every frame (`Panel:644-651`).

**Change.** Coalesce `refreshAssets` with `ScheduleEvent` (0.05 s) like the card watcher;
build one validated `mapId -> labels` index per refresh and pass it down to `LabelsForMap`,
`LabelStateForMap`, `LabelCount`, `UpdateDrawerView`; precompute sort keys before
`table.sort`; write marker `fontSize` only when the zoom-derived value changes.

**Acceptance.** Measure refresh time with 250 labels on one map and 3 x 250 across maps,
before and after; record numbers in the README.

### RM-20 (P3) Deletion cleanup cost grows forever

`ResumeDeletions` (`Model:977-987`) runs on every Director open (`Panel:2615`) and loops every
tombstone times every label; tombstones are never removed.

**Change.** Mark finished cleanup on the tombstone (`cleanupComplete = true`, one write) and
skip those; scan labels once per open against a set of tombstoned map IDs.

---

### RM-21 (P2) Mod-local tests

Move `output/region-map-review/regression.txt` to `Region Map/tests/region_map_test.lua`:
- Header per repo convention:
  `--Run from <parent>: dependencies/lua/bin/lua.exe "draw-steel-codex/Region Map/tests/region_map_test.lua"`
- Derive the repo root from `arg[0]`; no machine-specific paths.
- Load internals through `RegionMapModel.testing` (RM-10).
- Add groups for RM-01, RM-02, RM-03, RM-07, RM-09.
- Never register the file in the CodeMod. Deploy the mod with explicit paths so the test file
  is not copied into the git folder.

### RM-22 (P2) Mod-local docs and artifact cleanup

- Move `REGION_MAP.md` (repo root) to `Region Map/README.md`, trimmed to design, data model,
  player-facing copy and open acceptance items. Drop dated evidence logs, the stale section 9
  and machine paths (`C:/Users/ElderHex/...`, root file lines 431 and 442).
- Move `output/region-map-ui-guide/*` to `Region Map/docs/`.
- Delete `output/region-map-review/` (baseline and history source copies, historical
  `reproduce.txt`, `preflight.*`); git history keeps them.
- Commit `RegionMapJournal.lua` and `RegionMapViews.lua` (currently untracked) or their RM-12
  replacements.
- Keep `deploy.ps1` and `.gitignore` edits out of this change set. Before restoring them,
  copy the edited `deploy.ps1` to a personal location outside the repo (for example
  `%USERPROFILE%\tools\deploy-codex.ps1`, with `$repo` as a parameter) and fix it there:
  rename `$Profile` to `$CodexProfile` (it shadows PowerShell's automatic `$PROFILE`); skip
  `D` entries and take the new path from `R old -> new` in status-based discovery. Then
  `git checkout -- deploy.ps1 .gitignore`.

### RM-23 Decisions required before release

| Topic | Options | Recommendation |
|---|---|---|
| Director notes / Director-only labels are stored in game tables synced to every client; hiding is UI-only (`Model:35-38`). No Director-only table API exists in `Definitions/`. | (a) accept and document; (b) store notes in the Director's per-game preference (no co-Director sharing) | (a), with the notes section labeled "Hidden from players' screens" |
| `UpdateLabel` writes the whole row (`Model:843`); a concurrent move and rename lose one change | keep; or re-read and apply only changed fields at upload time, as `SaveSidecar` does (`Model:777`) | Apply changed fields only |
| Whether non-Director clients can write data tables at all is unverified | If blocked, player labels must move to a shared document | Make player label creation the first multiplayer test |

## 4. Out of scope

- Any change to core files (see section 1).
- The host-level gap that rail windows open below a panel's `minWidth`: the mod works around
  it (RM-08); report it to core maintainers separately.
- Deferred features F01-F12 from the design doc.

## 5. Definition of done

1. `..\dependencies\lua\bin\luac.exe -p` passes for every `Region Map/*.lua`; ASCII-only.
2. LuaLS: 0 problems in `Region Map/`; upstream `tools/lua-typing/check.ps1` passes.
3. `Region Map/tests/region_map_test.lua` passes under `dependencies/lua/bin/lua.exe`,
   including the new groups.
4. ui-harness screenshots for RM-13..16 at the sizes, font scales and schemes in RM-16.
5. Live checks with the DMHub bridge (`/mcp`):
   - rail and dock open paths (RM-08);
   - one Director and two players: player table writes, Present to a busy player, label limit
     visibility (RM-01, RM-02, RM-23);
   - Present while a Negotiation is presented (RM-09).
6. `git status` shows changes only under `Region Map/` (plus the removal of
   `REGION_MAP.md` and `output/region-map-*` moved into the mod folder).
7. Deployed with explicit paths; the CodeMod file list matches section RM-12's order.
