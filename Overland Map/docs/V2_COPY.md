# Overland Map V2 - Copy Manifest

Status: sections 1-17 SIGNED OFF by the user 2026-10-05. Sections 18-25 (V2.1, companion to
[V2_1_BRIEF.md](V2_1_BRIEF.md)) SIGNED OFF by the user 2026-10-08.
Companion to [V2_BRIEF.md](V2_BRIEF.md).
Reference wording and conventions for the mod. OverlandMapCopy.lua is the runtime
source; keep the corresponding entries here current when changing agreed wording.
Removed copy IDs are available in Git history.

The approved map-aids and personal hover-control wording is recorded in
[MAP_AIDS_BRIEF.md](MAP_AIDS_BRIEF.md); its `aids.*` entries extend this manifest.

## 1. Conventions

- US English, matching the rest of the app ("traveling", "color", "center").
- Sentence case for buttons, menu items, tooltips and headings ("Add location", not
  "Add Location"). "Director" and "Atlas" are capitalized as names.
- ASCII only (Lua source rule): "..." for an ellipsis, " - " as the separator where the
  mockup drew a middle dot. Breadcrumb separators are drawn as icons, not text.
- A menu item or button that opens a picker or dialog ends in "...".
- Placeholders: `{name}` a Location, `{map}` a map's Location name, `{party}` the Party's
  custom name, `{player}` a player's display name, `{count}` a number, `{query}` search text.
- Counts pick singular or plural: "1 location", "2 locations".
- Toasts last 10 s and pause on hover (R9). Undo closes the toast; no second toast.

## 2. Glossary (one name per concept, R12)

| Concept | UI term | Do not use |
|---|---|---|
| The one object (D4a) | location | label, place, marker, point of interest |
| A location's mark on a map | pin | marker, icon, token |
| A location's own image | map | overland map, child map, submap |
| The list of top-level maps | Atlas | library, maps list |
| The group of heroes | Party (in controls); `{party}` in the marker, status, toasts and log | group, heroes, tokens |
| Director-only state | Hidden | Director only, secret, private |
| Players can see it | Revealed | Shared, public, visible |
| Players can open a location's map | Map shared / Not shared; Atlas badges: Revealed / Hidden | published, public |
| Pushing the map to every screen | Show to players | present, share, broadcast |
| The Director's local preview | View as player | player view, preview |
| Party not at a location | traveling | travelling, free, moving |
| Pin size and text weight (D5b) | Importance: Major, Normal, Minor | tier, rank, size |
| How a pin is drawn (D5a) | Pin style: Icon + name, Name plate, Icon only | label style, display |
| Locations and labels cannot be dragged | Positions locked / Positions unlocked | edit mode, frozen |
| Travel history | Session log | journal, history, travel log |
| Forcing every name on | Show names | show labels |

## 3. Window and toolbar

| ID | String | When / notes |
|---|---|---|
| window.title | Overland Map | Rail button and window title (the panel's registered name, `OverlandMapConstants.panelName`) and the title of the load.missing chat message. Was "Overland Map" until 2026-10-08 |
| tb.search | Search locations | Tooltip |
| tb.add | Add location | Tooltip |
| tb.import | Import locations | Tooltip; Director, open maps only; beside Add |
| tb.lock.on | Positions locked - click to unlock locations and labels | Tooltip, default state |
| tb.lock.off | Positions unlocked - click to lock locations and labels | Tooltip |
| tb.ruler | Ruler | Tooltip |
| tb.show | Show this map to players | Tooltip, Director only |
| tb.viewAs.off | View as player | Tooltip, Director only |
| tb.viewAs.on | Stop viewing as player | Tooltip |
| tb.log | Session log | Tooltip |
| tb.settings | Overland Map settings | Tooltip, Director only |
| tb.window | Switch to window view inside the app | Tooltip, fullscreen view; separate from Pop out |
| tb.fullscreen | Switch to fullscreen | Tooltip, in-app window view |
| tb.popOut | Pop out into its own window | Tooltip, both in-app views |
| tb.popIn | Return to app | Tooltip, popped-out map only; restores remembered in-app view |
| tb.close | Close the map | Fullscreen toolbar or in-app title-bar tooltip |
| window.options | Window options | In-app title-bar menu tooltip |
| window.reset | Reset window size and position | Window menu; centered default size |

## 4. Breadcrumb and Atlas

| ID | String | When / notes |
|---|---|---|
| crumb.root | Atlas | First breadcrumb item and the Atlas heading |
| crumb.hover | {name} / start of the description / {hint} | Tooltip of a Location crumb (idea 8, added 2026-10-07). The description is cut at 300 characters, at a word, with "..." |
| crumb.hover.nameOnly | {name} / {hint} | The same, for a Location with no description |
| crumb.hint.up | Click to go to this map. Right-click to read about it. | {hint} on an ancestor crumb. Right-click opens it in the side panel without leaving the open map |
| crumb.hint.current | Click to read about this map. | {hint} on the crumb of the open map |
| atlas.card.open | Open {map} | Card tooltip |
| atlas.card.party | Party here | Chip on the card whose map holds the Party |
| atlas.card.hidden | Hidden | Director-only Atlas badge when the map is not shared with players |
| atlas.card.revealed | Revealed | Director-only Atlas badge when the map is shared with players |
| atlas.card.count | {count} locations | Card footer |
| atlas.new.picker | Choose a map image | Image picker title |
| atlas.new.defaultName | New map | Name of a new map until renamed (opens with the name selected) |
| map.new.hidden | New maps are hidden from players until you share them. | Always-visible inline notice on both steps of Atlas New map and Location Add map; absent for Replace map image. User approved 2026-10-14 |
| atlas.empty.director.title | No maps yet | Director, empty Atlas |
| atlas.empty.director.body | Create your first map from any image. | With a "New map" button |
| atlas.empty.player.title | No maps yet | Player, nothing shared |
| atlas.empty.player.body | Maps appear here when the Director shares them. | |

## 5. Map surface

| ID | String | When / notes |
|---|---|---|
| cam.fit | Fit map | Tooltip |
| cam.zoomOut | Zoom out | Tooltip |
| cam.zoomIn | Zoom in | Tooltip |
| cam.names | Show names | Tooltip; the button shows its on state |
| pin.hover | {name} / first line of the description | Two lines; second line omitted when empty |
| party.tooltip.move | {party} - drag to move | Viewer may move the Party |
| party.tooltip | {party} | Viewer may not move it |
| status.at | {party} at {name} | Status chip |
| status.traveling | {party} - traveling | Free on this map, or at a location the player cannot see (R3) |
| status.elsewhere | {party} on {map} | Party is on another map; click goes there |
| status.elsewhere.tooltip | Go to the Party | Since 2026-10-11 the tooltip of every status the chip shows except "not on a map": a click always takes the camera to the Party (key unchanged) |
| status.none | {party} is not on a map | |
| status.none.hint | Right-click a map to place the Party. | Tooltip, Director only |
| banner.viewAs | Viewing as player - hidden locations are not shown | Director, View as player on (R9) |
| chip.unlocked | Positions unlocked - drag locations or selected labels to move | While unlocked (R6), updated 2026-10-15 |
| hint.add | Click the map to add a location. Esc to stop. | "+" active (R10) |
| hint.move | Click where {name} should go. Esc cancels. | "Move" from the menu |
| hint.ruler | Ruler: click a start, then an end. Only you see it. Esc stops. | Ruler active (R7) |

## 6. Right-click menus

| ID | String | When / notes |
|---|---|---|
| ctx.map.add | Add location here | Anyone who may add locations |
| ctx.map.party | Place Party here | Director, any map (R12) |
| ctx.pin | (the "..." menu, section 8) | Right-click on a pin (R12) |

## 7. Side panel, read mode

| ID | String | When / notes |
|---|---|---|
| panel.close | Close | Tooltip |
| panel.meta | {importance} - {visibility} | Director, e.g. "Major - Hidden" |
| panel.eye.hidden | Hidden - click to reveal to players | Eye tooltip |
| panel.eye.revealed | Revealed - click to hide from players | Eye tooltip |
| panel.map.off | Not shared - click to share this map | Map icon tooltip |
| panel.map.on | Map shared - click to stop sharing | Map icon tooltip |
| panel.desc.empty | No description yet. | Director only; players see nothing |
| panel.journal | Read in journal | Link |
| panel.author | Added by {player} | Player-made locations only (R11) |
| panel.partyHere | {party} is here | |
| panel.moveParty | Move Party here | Button |
| panel.openMap | Open map | Button; players see it only once the map is shared (R4) |
| panel.edit | Edit | Button |
| panel.more | More actions | "..." tooltip; Location side panel and Director's Atlas map cards |
| panel.notes | Director notes | Collapsible header, Director only |
| panel.notes.sub | Players don't see these | Under the header |

## 8. The "..." menu

| ID | String | When / notes |
|---|---|---|
| menu.move | Move | Pick a new spot by clicking |
| menu.moveToMap | Move to map... | Opens the map picker (R10) |
| menu.hide | Hide from players | Director, location Revealed |
| menu.reveal | Reveal to players | Director, location Hidden |
| menu.addMap | Add map... | Location without a map |
| menu.replaceImage | Replace map image... | Location with a map |
| menu.removeMap | Remove map | Location with a map (R12) |
| menu.mapSettings | Map settings... | Atlas map: opens that map and its Settings, including scale, pace and border |
| menu.shareMap | Share map with players | Atlas map, not shared; same write and Undo as the side panel's share button |
| menu.unshareMap | Stop sharing map | Atlas map, shared |
| menu.linkJournal | Link journal entry... | No link yet |
| menu.changeJournal | Change journal entry... | Linked |
| menu.unlinkJournal | Unlink journal entry | Linked |
| menu.delete | Delete | Danger color |
| picker.moveToMap.title | Move {name} to... | Map picker |
| picker.moveToMap.hint | It goes to the middle of that map. Unlock pins to place it exactly. | |

Players see Move, Move to map..., and Delete on their own locations only.

Top-level maps use the same complete menu in the Atlas and the Location side panel
(2026-10-14). It also reuses Open map, Edit, Import locations, Read in journal (when
available) and Show this map to players. Import, Settings and Show to players open the
selected card's map first. Related entries are separated; Delete is last. Add location,
Path tool, Ruler and View as player stay in the map toolbar, outside the Atlas menu.

## 9. Side panel, edit mode

| ID | String | When / notes |
|---|---|---|
| edit.visibility | Visibility | First row, Director only (R1) |
| edit.visibility.hidden | Hidden | Segment |
| edit.visibility.revealed | Revealed | Segment |
| edit.name | Name | |
| edit.name.placeholder | Name this location | New locations start with an empty, focused name |
| edit.name.fallback | Unnamed location | Shown if the name is left empty |
| edit.icon | Icon | |
| edit.icon.choose | Choose icon... | |
| edit.icon.clear | No icon | |
| edit.icon.picker | Choose an icon | Picker title |
| edit.icon.tab.map | Map icons | Curated set (D5d) |
| edit.icon.tab.library | Library | Any library image |
| edit.style | Pin style | |
| edit.style.iconName | Icon + name | |
| edit.style.plate | Name plate | |
| edit.style.iconOnly | Icon only | |
| edit.importance | Importance | |
| edit.importance.major | Major | |
| edit.importance.normal | Normal | |
| edit.importance.minor | Minor | |
| edit.desc | Description | |
| edit.desc.placeholder | A line or two that players read. | |
| edit.journal | Journal entry | Shows the linked title, or the "Link journal entry..." button |
| edit.notes | Director notes | Director only |
| edit.notes.placeholder | Only you see these. | |
| edit.saving | Saving... | Autosave (D13b) |
| edit.saved | Saved | |
| edit.notSaved | Not saved | Warning color, with Retry (R11) |
| edit.retry | Retry | |
| edit.done | Done | |

## 10. Toasts

| ID | String | Undo | When |
|---|---|---|---|
| toast.hid | {name} hidden from players | Yes | |
| toast.revealed | {name} revealed to players | Yes | |
| toast.mapShared | {map} shared with players | Yes | |
| toast.mapUnshared | {map} no longer shared | Yes | |
| toast.moved | {name} moved | Yes | Pin dragged or placed with Move |
| toast.movedToMap | {name} moved to {map} | Yes | |
| toast.partyAt | {party} moved to {name} | Yes | Undo also removes the log entry (R3) |
| toast.partyTraveling | {party} is traveling | Yes | |
| toast.partyPlaced | {party} placed on {map} | Yes | Place Party here |
| toast.deleted | {name} deleted | Yes | |
| toast.deletedTree | {name} and {count} locations inside it deleted | Yes | |
| toast.mapRemoved | Map removed from {name} | Yes | |
| toast.showing | Showing {map} to players | No | Director (D10d) |
| toast.shown | The Director showed you {map} | No | Recipients (R5) |
| toast.saveFailed | Couldn't save. Check your connection. | No | A non-form write failed; has a Retry button |
| toast.undo | Undo | | Button label |
| toast.retry | Retry | | Button label |

## 11. Dialogs

| ID | String | Notes |
|---|---|---|
| dlg.delete.title | Delete {name}? | Only when it has a map or child locations (D7d) |
| dlg.delete.body | This also deletes {count} locations inside it. | |
| dlg.delete.party | The Party moves to {map}. | Added when the Party is inside |
| dlg.delete.ok | Delete | Danger |
| dlg.removeMap.title | Remove the map from {name}? | |
| dlg.removeMap.body | The map image is removed and the {count} locations pinned on it are deleted. | Without children: "The map image is removed." |
| dlg.removeMap.ok | Remove map | Danger |
| dlg.share.title | Share this map? | "Show to players" on a map that is not shared (R4) |
| dlg.share.body | Players can't see {map} yet. Share it to show it to them. | |
| dlg.share.ok | Share and show | |
| dlg.cancel | Cancel | All dialogs |

## 12. Search

| ID | String | When / notes |
|---|---|---|
| search.placeholder | Search locations | |
| search.none | No locations match "{query}". | |
| search.hint | Enter opens the top result. | Under the field (R9) |

## 13. Settings popover

| ID | String | When / notes |
|---|---|---|
| set.title | Overland Map settings | |
| set.party | Party | Section |
| set.party.name | Party name | Default value "Party" (D11b) |
| set.party.image | Party image | |
| set.party.image.choose | Choose image... | |
| set.party.image.reset | Use the banner | Back to the default marker |
| set.party.playersMove | Players can move the Party | |
| set.playersAdd | Players can add locations | D9d |
| set.map | This map | Section |
| set.map.scale | Map scale | |
| set.map.scale.none | Not set | |
| set.map.scale.value | {distance} {unit} between the two scale points | |
| set.map.scale.set | Set scale... | |
| set.map.scale.hint | Click two points on the map, then enter the distance between them. | |
| set.map.scale.distance | Distance | |
| set.map.scale.unit.mi | miles | Unit choice |
| set.map.scale.unit.km | kilometers | Unit choice |
| set.map.pace | Travel pace per day | Optional; empty hides travel time |
| set.you | Only for you | Section |
| set.reduceMotion | Reduce motion | R9 |

## 14. Ruler

| ID | String | When / notes |
|---|---|---|
| ruler.distance | {distance} {unitShort} | "9 mi", "14 km" |
| ruler.withTime | {distance} {unitShort} - {time} | When a pace is set |
| ruler.time.under | under half a day | Under 0.5 days |
| ruler.time.days | {days} days | Rounded to the nearest half day; "1 day" |
| ruler.uncalibrated | {percent}% of map width | No scale set (D14c) |
| ruler.uncalibrated.hint | Set this map's scale in Settings to measure distance. | Tooltip, Director only |

## 15. Session log

| ID | String | When / notes |
|---|---|---|
| log.title | Session log | |
| log.day.today | Today | Date heading |
| log.day.yesterday | Yesterday | |
| log.day.date | {month} {day} | Older entries, e.g. "September 28" |
| log.arrived | Arrived at {name} | Party snapped to a location |
| log.traveling | Traveling from {name} | Party dropped free after being at a location |
| log.travelingOn | Traveling on {map} | Party dropped free with no previous location |
| log.placed | Placed on {map} | Place Party here |
| log.by | Moved by {who} | {who} is "the Director" or a player's name |
| log.merged | {count} moves merged | Consecutive traveling drops (R8) |
| log.addNote | Add note | Director |
| log.editNote | Edit note | Entry action, Director |
| log.deleteEntry | Delete entry | Entry action, Director |
| log.undoLast | Undo last change | R9 |
| log.showRoute | Show route | Toggle for the drawn past route; off by default; above the entries |
| log.empty | No travel yet. Entries appear when the Party moves. | |

## 16. Limits, load and migration

| ID | String | When / notes |
|---|---|---|
| load.missing | Overland Map needs a newer Draw Steel Codex and was not loaded. Missing: {list} | As V1, with the new name |

## 17. Choices made in this manifest

These follow from the brief but were not spelled out there; signing off the manifest
signs these off too.

1. "traveling" (US), not "travelling", to match the app.
2. Controls say "Party" ("Move Party here", "Place Party here"); the custom name appears in
   the marker, status, toasts and log, so buttons never grow with a long name.
3. " - " replaces the mockup's middle dot (ASCII-only source).
4. The status chip names the map when the Party is elsewhere, and clicking it goes there.
5. Remove map deletes the locations pinned on that map, after a confirm, like Delete (D7d).
6. Superseded 2026-10-14: Atlas cards now show the Director either "Hidden" or "Revealed"
   from the map's sharing state. The former "Not shared"-only treatment is removed.
7. Director-made locations show no author line; only player-made ones do (R11). The
   mockup's "Added by the Director" is dropped.
8. A one-time migration notice to the Director.
9. Travel pace is optional and has no default; without it the ruler shows distance only.

---

# V2.1 additions (signed off 2026-10-08)

Same conventions and glossary as sections 1-2. New placeholders:
- `{path}`: a path's display name, which is its name, else its type's name;
- `{type}`: a path type's name;
- `{time}`: a travel time formatted by section 22;
- `{from}`, `{to}`, `{a}`, `{b}`, `{dest}`: Location names;
- `{width}`, `{height}`, `{min}`, `{recommended}`, `{max}`: pixel numbers;
- `{n}`: an entry number in an import file;
- `{by}`: the piece `leg.by`, or empty when the path has no name and no type.

New glossary rows:

| Concept | UI term | Do not use |
|---|---|---|
| A connection between two locations | path | route, road, edge, link |
| A path's kind (Road, River...) | path type | category, style |
| A map whose Party moves along paths | Point crawl map | pointcrawl, node map, graph |
| A map with free Party moves | Free map | normal map, open map |
| One move of the Party along one path | travel (verb); leg in the log | trip, journey, hop |

## 18. Map mode

| ID | String | When / notes |
|---|---|---|
| mode.title | What kind of map? | Step 1 of the Atlas New map card and of Add map (A1) |
| mode.free | Free map | Button |
| mode.free.desc | Drag the Party anywhere on it. | Under the button |
| mode.pointcrawl | Point crawl map | Button |
| mode.pointcrawl.desc | The Party travels along paths you draw. | Under the button |
| mode.permanent | You can't change this later. | Under both buttons (A4, Q21) |
| mode.back | Back | Step 2, returns to step 1 |
| side.addMap.title | Add a map to {name} | Side panel heading while choosing the kind and the image |
| chip.pointcrawl | Point crawl | Chip on the Atlas card and in the side panel map meta (A2) |
| hint.pointcrawl.empty | Add locations, then join them with the Path tool. | Director, point crawl map with fewer than 2 locations (Q21) |

## 19. Image size guidance and border

| ID | String | When / notes |
|---|---|---|
| image.hint | Best at {recommended} px wide. Under {min} px it blurs when zoomed in; over {max} px it loads slowly. | Always visible under the side panel image picker, and the second line of the Atlas New map card tooltip under `atlas.new.picker` (J2). Numbers from J1 (W5): 1500 / 4000 / 12000 |
| toast.image.small | This image is {width} x {height} px. Maps look best at {recommended} px wide; smaller images blur when zoomed in. | After picking; no Undo (J3) |
| toast.image.large | This image is {width} x {height} px and may load slowly. {recommended} px wide is enough. | After picking; no Undo |
| toast.replaceImage | Replace image... | Button on both size toasts (Q25) |
| set.map.border | Map border | Row in "This map" |
| set.map.border.hint | New maps start with the border you picked last. | Under the tiles (K5) |
| set.border.none | None | Tile |
| set.border.fade | Soft fade | Tile |
| set.border.torn | Torn edge | Tile |
| set.border.frame | Frame | Tile |
| set.border.needsArt | Not available yet: this border needs its art. | Tooltip on a disabled tile (K3) |
| set.game | Whole game | Settings section (Q22) |

## 20. Import

| ID | String | When / notes |
|---|---|---|
| import.picker | Choose a JSON file of locations | File dialog prompt |
| import.title | Import locations | Editor, preview and error card title |
| import.summary | Import {count} locations into {map}? | `.one`: "Import 1 location into {map}?" |
| import.skipped | {count} entries will be skipped: | `.one`: "1 entry will be skipped:" |
| import.skip.noName | Entry {n}: it has no name. | |
| import.skip.name | Entry {n}: its name is over {limit} characters or contains a line break, control character or bidi mark. | `limit` is the shared name limit, now 256 |
| import.skip.position | Entry {n}: u and v must both be between 0 and 1, or both left out. | |
| import.skip.field | Entry {n}: {field} is not a valid value. | pinStyle, importance, visibility, icon |
| import.skip.tooLong | Entry {n}: {field} is too long. | description over 4000, note over 8000 |
| import.duplicates | {count} names are already on this map; they will be added again: | `.one`: "1 name is already on this map; it will be added again:" |
| import.placement | Locations without a position are set out in rows near the center of the map. Unlock pins to place them exactly. Undo removes imported locations that have not been edited since. | Q24 |
| import.ok | Import {count} locations | `.one`: "Import 1 location" |
| import.error.json | This file isn't valid JSON, so nothing was imported. | Error card |
| import.error.empty | This file has no locations in it. | Error card |
| import.error.allSkipped | None of the entries in this file can be imported: | Error card, then the reasons |
| dlg.close | Close | Error and refusal cards |
| toast.imported | {count} locations imported into {map} | Undo: yes. `.one`: "1 location imported into {map}" |

### Paste editor (idea 18, agreed 2026-10-14)

| ID | String | When / notes |
|---|---|---|
| import.into | Into {map} | Captured destination |
| import.paste | Paste JSON | Visible editor label |
| import.file | Choose file... | Native file picker, then preview |
| import.fill | Fill with example | Asks before replacing a nonempty draft |
| import.preview | Preview | Validate pasted JSON; no writes |
| import.back | Back | Return to the editor |
| import.count | {count} / {limit} characters | Unicode code points |
| import.draftHint | Drafts are not saved. Use Choose file... for larger imports. | Under editor |
| import.discard | Discard pasted JSON? | Cancel, Esc and mod-owned host closing |
| import.discard.ok | Discard | Confirmation action; Cancel keeps editing |
| import.replace | Replace pasted JSON with the example? | Example replacement |
| import.replace.ok | Replace | Confirmation action |
| import.useFile | Use this file and discard pasted JSON? | A valid file replaces the draft only on confirmation |
| import.useFile.ok | Use file | Confirmation action |
| import.text.json | This text isn't valid JSON. Nothing was imported. | Draft remains editable |
| import.text.empty | This JSON has no locations in it. | Pasted empty input/list |
| import.text.allSkipped | None of the entries in this JSON can be imported: | Then existing skip reasons |
| import.text.tooLong | This text exceeds {limit} characters. Shorten it or choose a JSON file. | Reject before parsing |
| import.unavailable | This map is no longer available for import. | Preserve draft |
| import.permission | Only the Director can import locations. | Rechecked before preview and commit |
| import.help | JSON contract | Swagger-style field reference beside editor, below it when narrow |
| import.copyContract | Copy contract | Copies all fields and rules as plain text without changing the draft |
| import.copied | Copied | Button feedback for two seconds |
| import.help.shape | Location[] \| { locations: Location[] } | Two accepted payload shapes |
| import.help.required | * required; all other fields optional. | `name` carries the asterisk |
| import.help.name | 1..{limit} chars; trimmed; single line. | Shared name limit: 256 |
| import.help.description | maxLength: {limit}; default: "". / Visible when revealed. | Description limit; slash is a line break |
| import.help.note | maxLength: {limit}; default: "". / Director only. | Director note limit |
| import.help.icon | enum: {icons} / Omitted: default pin. | Curated icon keys from Constants |
| import.help.pinStyle | enum: iconName \| plate \| iconOnly / default: iconName | |
| import.help.importance | enum: major \| normal \| minor / default: normal | |
| import.help.visibility | enum: hidden \| revealed / default: hidden | |
| import.help.u | 0..1; left -> right; requires v. | |
| import.help.v | 0..1; top -> bottom; requires u. | |
| import.help.behavior | Scope: Director; selected map; flat Locations. / Write: append; duplicate names warn; one Undo. / Unknown fields: ignored. Invalid entries: skipped. / Missing u/v: centered grid. / Text: trim; CRLF/CR -> LF; no other controls except TAB. / Limits: Unicode chars; paste {limit}; files uncapped. | Terse operational rules below fields |

The helper uses Swagger as its visual reference (2026-10-14): monospaced field names,
type labels, a required marker and separated field rows. Standard field names and
`string`/`number` type keywords are shown verbatim. The clipboard assembles the same
fields and terse descriptions as plain text. It contains no OpenAPI document.

`import.example` is plain JSON with two entries under `locations`. Kell's Ferry has
`icon: port`, `pinStyle: iconName`, `importance: major`, `visibility: hidden`, `u: 0.42`,
`v: 0.61`, description "A rope ferry over the Brinewater, run by the Kell family for six
generations." and note "The ferryman owes the Thieves' Guild 40 gp." The second entry
contains only `name: Old Watchtower`. Both therefore import Hidden. Explanations live in
the help, never in JSON comments. The existing four-entry file example remains available.

## 21. Paths

| ID | String | When / notes |
|---|---|---|
| tb.path | Path tool | Tooltip, Director, point crawl maps only |
| tb.path.disabled | Add at least two locations to draw a path. | Tooltip while disabled (Q7) |
| hint.path.start | Click the location the path starts from. Esc to stop. | Path tool, no draft |
| hint.path.next | Click the map to add a bend, or click the location the path ends at. Right-click or Backspace removes the last bend. Esc cancels this path. | Path tool, draft started |
| hint.redraw | Redraw {path}: click the map to add bends, then click {name}. Esc cancels. | Redraw line (Q6) |
| menu.connect | Connect to... | Pin "..." menu and right-click, Director, point crawl maps (E1) |
| picker.connect.title | Connect {name} to... | Picker heading |
| picker.connect.none | No other locations on this map. | |
| menu.redraw | Redraw line | Path "..." menu |
| path.title.noType | Path: {a} - {b} | Panel title of a path with no name and no type |
| path.title.unnamed | {type}: {a} - {b} | Panel title of a path with a type but no name |
| path.label | {path} - {time} | Label on the map (F3, Q11) |
| path.ends | Between {a} and {b} | Read mode |
| path.time | {time} | Read mode, same both ways |
| path.time.both | {time} from {a}, {backTime} from {b} | Different time (W2) |
| path.time.oneWay | {time}, from {a} to {b} only | Not possible the other way (W2) |
| path.type.none | No type | Chip and label of a path whose type was deleted (N3) |
| path.waits | Revealed - players see it once {name} is revealed. | Director, an end is hidden (H1) |
| path.note | Danger or requirement | Read and edit, Director only (C5) |
| path.note.sub | Players don't see this | Under the heading |
| path.note.placeholder | Only you see this. | |
| edit.path.name.placeholder | Name this path (optional) | Empty name shows the type |
| edit.path.type | Type | |
| edit.path.time | Travel time | |
| edit.path.unit.hint | The unit is set in Settings. | |
| edit.path.timeRange | Enter a time of 0 or more. | Invalid number |
| edit.path.back | The other way | W2 |
| edit.path.back.same | Same | Segment |
| edit.path.back.different | Different time | Segment |
| edit.path.back.none | Not possible | Segment |
| edit.path.backTime | Time from {b} | Shown with "Different time" |
| edit.path.bends | Unlock pins to drag the line's bends. Right-click a bend to remove it; drag a + to add one. | Under the form (Q5) |
| panel.paths | Paths | Section in a location's read mode, point crawl maps (Q10) |
| panel.paths.row | {dest} by {path} - {time} | Row; hidden paths get the eye-slash |
| panel.paths.none | No paths yet. | |
| toast.pathDeleted | {path} deleted | Undo: yes (E3) |
| dlg.delete.paths | This also deletes {count} paths. | Added to the delete and remove-map confirms (B5); `.one`: "This also deletes 1 path." A location with paths always asks |
| dlg.moveToMap.title | Move {name} to {map}? | Only when it has paths |
| dlg.moveToMap.body | Its {count} paths on this map are deleted. | `.one`: "Its 1 path on this map is deleted." |
| dlg.moveToMap.ok | Move | |

Hide and reveal use `menu.hide`, `menu.reveal`, `toast.hid`, `toast.revealed` and the
`panel.eye.*` tooltips, with `{name}` as the path's display name. Delete uses `menu.delete`.
Name, Description and Visibility reuse `edit.name`, `edit.desc`, `edit.desc.placeholder` and
`edit.visibility.*`.

## 22. Path types and travel time

| ID | String | When / notes |
|---|---|---|
| set.timeUnit | Travel time | Row in "Whole game" (C9) |
| set.timeUnit.days | Days | Segment |
| set.timeUnit.watches | Watches | Segment |
| set.timeUnit.hint | A watch is 4 hours; 6 watches make a day. | |
| set.pathTypes | Path types | Row in "Whole game" (C6) |
| set.pathTypes.hint | Each type has its own line on the map. | |
| set.pathType.edit | Edit | Row button |
| set.pathType.name | Name | |
| set.pathType.newName | New type | Name of an added type |
| set.pathType.pattern | Line | |
| set.pathType.color | Color | |
| set.pathType.width | Width | |
| set.pathType.sameLook | Looks the same as {type}. Change the line or width to tell them apart. | Q3 |
| set.pathType.delete | Delete type | Danger color |
| set.pathType.add | Add path type | |
| pattern.solid / .dashed / .dotted / .double / .dashDot / .longDash | Solid / Dashed / Dotted / Double / Dash-dot / Long dash | Line choices (N1, Q3) |
| color.parchment / .blue / .ochre / .violet / .rust / .ink | Parchment / Blue / Ochre / Violet / Rust / Ink | Swatch tooltips (Q26) |
| width.thin / .normal / .thick | Thin / Normal / Thick | Segments |
| type.road / .trail / .river / .sea / .underground / .secret | Road / Trail / River / Sea / Underground / Secret | Starter type names (C4); editable content |
| dlg.deleteType.title | Delete {type}? | Only when paths use it (N3) |
| dlg.deleteType.body | {count} paths use it. They stay on the map as a plain line with no type. | `.one`: "1 path uses it. It stays on the map as a plain line with no type." |
| dlg.deleteType.ok | Delete type | Danger |
| toast.typeDeleted | {type} deleted | Undo: yes |
| time.days | {count} days | `.one`: "1 day" |
| time.watches | {count} watches | `.one`: "1 watch" |
| time.daysWatches | {days} and {watches} | Days unit, not whole days: "1 day and 2 watches" |
| time.none | no time | A time of 0 |

## 23. Travel

| ID | String | When / notes |
|---|---|---|
| party.section | Party | Side panel heading, point crawl maps (G1) |
| party.status.at | {party} is at {name} | |
| party.status.onPath | {party} is on {path}, {time} from {name} | |
| party.travelTo | Travel to | List heading |
| party.travel.row | {dest} by {path} | Row; the time on its second line (Q18) |
| party.travel.none | No paths lead on from here. | |
| party.travel.offPath | {party} is not on a location or a path. Right-click a path or a location to place it. | Director (G6) |
| party.travel.offPath.player | {party} is not on a path. | Player |
| party.travel.noPermission | Only the Director can move {party}. | Player, switch off |
| party.tooltip.travel | {party} - click to travel | Banner on point crawl maps, viewer may move it (Q17) |
| hint.dragTravel | On this map {party} travels along paths. Click it to travel. | Toast after a drag snaps back; no Undo |
| ctx.party.travelMenu | Travel to | Right-click submenu, if the menu supports one |
| ctx.party.travel | Travel to {dest} by {path} ({time}) | Flat right-click entry otherwise |
| ctx.path.place | Place Party on {path} | Director, right-click near a path (Q4) |
| dlg.stop.title | Stop {party} on {path} | G3 |
| dlg.stop.field | Time already spent from {name} | Q14 |
| dlg.stop.of | of {time} | After the field |
| dlg.stop.swap | Count from {name} instead | Swap button |
| dlg.stop.hint | Going on takes the rest of the time; turning back takes the time spent. | |
| dlg.stop.range | Enter a time above 0 and under {time}. | |
| dlg.stop.ok | Place Party | |
| dlg.hiddenTravel.title | {path} is hidden | W1 |
| dlg.hiddenTravel.body | Players don't know this path yet. Reveal it before {party} travels? | |
| dlg.hiddenTravel.reveal | Reveal and travel | |
| dlg.hiddenTravel.keep | Travel without revealing | Players see the leg with no path name and no line |
| toast.traveled | {party} traveled from {from} to {to}{by} - {time} | Undo: yes |
| toast.stopped | {party} stopped on {path} | Undo: yes |
| status.onPath | {party} on {path} | Status chip |

## 24. Session log

| ID | String | When / notes |
|---|---|---|
| log.leg | Traveled from {from} to {to}{by} - {time} | One leg (I1, Q19) |
| log.leg.on | Traveled on to {to}{by} - {time} | Leaving from partway, forward; the rest of the time (Q15) |
| log.leg.back | Turned back to {to}{by} - {time} | Leaving from partway, back |
| leg.by | by {path} | The `{by}` piece, with a leading space; empty when the path has no name and no type, or for players on a secret leg |
| log.stopped | Stopped on {path}, {time} from {name} | Partway stop (N2) |
| log.stopped.noPath | Stopped on the way, {time} from {name} | Players, secret or hidden path |

## 25. Choices made in the V2.1 additions

1. "Travel without revealing" replaces the ledger's working label "Travel in secret": the
   glossary bans "secret" for visibility. "Secret" survives only as a starter type name,
   which is content the Director can rename.
2. A leg reads "from {from} to {to} by {path}" everywhere (Q19). A path with no name uses its
   type's name. With neither, "by ..." is dropped, so there is never "the The Ferry Run".
3. Times in the Days unit that are not whole days read "1 day and 2 watches".
4. Import says "locations" in lowercase, matching "Add location" (Q20).
5. The Party menu uses one "Travel to" submenu if the engine's context menu has submenus,
   and flat "Travel to {dest} by {path} ({time})" entries if it does not.
6. A Location with paths always confirms before Delete, Remove map or Move to map, and the
   confirm names the path count (B5).
7. *Made while building P6; signed off by the user 2026-10-10.* Inside the "Travel to" submenu
   each entry is `ctx.party.travel` without its leading "Travel to", which the submenu
   already says: "Kell's Ferry by King's Road (2 days)".
8. *Made while building P6; signed off by the user 2026-10-10.* Leaving from partway, the toast
   is the log line (`log.leg.on`, `log.leg.back`) instead of `toast.traveled`, whose
   "from {from}" would name an end the Party did not set out from on that leg.

## 26. Location and path image attachments

Approved in the implementation plan on 2026-10-14. Shared by both detail panels.

| ID | String | When / notes |
|---|---|---|
| artwork.section | Image | Director edit section, before Description |
| artwork.open | Open image | Local viewer; same action as clicking the preview |
| artwork.choose | Choose image... | No attachment |
| artwork.replace | Replace image... | Existing or malformed attachment |
| artwork.remove | Remove image | Clears the reference, with Undo |
| artwork.loading | Loading image... | Within the reserved preview frame |
| artwork.unavailable | Image unavailable. | Missing/unreadable/video asset or load timeout |
| artwork.retry | Retry | Fresh load or guarded failed write |
| artwork.still | Choose a still image. | Video candidate rejected; old attachment retained |
| artwork.updated | Image updated | Confirmed attach/replace, with one Undo entry |
| artwork.removed | Image removed | Confirmed removal, with one Undo entry |
| artwork.changed | Image changed. Choose again. | A newer attachment wins over a delayed chooser/write |

Save status and save-failure feedback reuse `edit.saving`, `edit.notSaved`,
`toast.saveFailed`, and the existing Retry/Undo controls.

## Map labels (decided 2026-10-14)

The behavior and defaults are in [LABELS_BRIEF.md](LABELS_BRIEF.md). This copy is
implemented in the development checkout; the complete labels cloud update is not yet
published. See [verification and delivery status](../tests/LABELS.md).

The player-management switch defaults off; Show labels defaults on and affects only the
viewer. View as player has no management controls. Auto contrast means a snug automatic
black/white backing, while Plate uses the selected background color/opacity.

Save feedback reuses `edit.saving`, `edit.saved`, `edit.notSaved`, `toast.saveFailed`,
`toast.retry`, and the existing Undo control. Visibility and Done reuse the existing copy.
`label.forced` accompanies `label.hiddenLocal` when selection temporarily shows one label.
Plural deletion counts use `label.deleteCount`, with `.one` selected for a count of one.

| ID | Text |
|---|---|
| label.title | Label |
| label.location | Location |
| label.new | New label |
| label.add | Add label |
| label.addHere | Add label here |
| label.edit | Edit label |
| label.delete | Delete label |
| label.players | Players can manage their own labels |
| label.text | Text |
| label.font | Font |
| label.bold | Bold |
| label.italics | Italic |
| label.alignment | Alignment |
| label.left | Left |
| label.center | Center |
| label.right | Right |
| label.size | Size (% of map width) |
| label.angle | Rotation (degrees) |
| label.spacing | Letter spacing (%) |
| label.color | Text color |
| label.background | Background |
| label.auto | Auto contrast |
| label.plate | Plate |
| label.none | None |
| label.backgroundColor | Background color |
| label.show | Show labels |
| label.search | Search locations and labels |
| label.searchNone | No locations or labels match "{query}". |
| label.searchHint | Arrows select. Enter opens. Ctrl+Enter edits a label. |
| label.added | Label added |
| label.updated | Label updated |
| label.moved | Label moved |
| label.resized | Label resized |
| label.rotated | Label rotated |
| label.deleted | Label deleted |
| label.deleteCount | Also deletes {count} labels. |
| label.deleteCount.one | Also deletes 1 label. |
| label.placeHint | Click or press Enter to place a label. Esc cancels. |
| label.hiddenLocal | Labels are hidden for you. |
| label.forced | The selected label is shown temporarily. |
| label.addMenu | Add |

## Map-wide pin text (signed off 2026-10-15)

Settings > This map. The controls apply only to direct Location pins on this map.
Font, bold/italic, spacing, colors, backgrounds, anchors, Importance tiers, save status
and Retry reuse their existing strings above. Hover keeps `pin.hover` / `pin.hover.nameOnly`.

| ID | Text |
|---|---|
| pinText.title | Pin text |
| pinText.scope | All location names on this map. |
| pinText.size | Size (pt) |
| pinText.anchor | Name anchor |
| pinText.appearance | Text appearance |
| pinText.themeFont | Theme default |
| pinText.themeColor | Use theme color |
| pinText.default | Default |
| pinText.plateColor | Plate color |
| pinText.reset | Reset pin text |

## Text outlines and image backgrounds (design agreed 2026-10-16)

The existing label and map-wide pin text editors share these controls. Image configuration
is Director-only. Outline controls follow existing label ownership. Existing background
choices, save statuses and Retry retain their existing strings.

| ID | Text |
|---|---|
| appearance.outline | Outline |
| appearance.default | Default |
| appearance.none | None |
| appearance.custom | Custom |
| appearance.outlineOff | Default: no outline. |
| appearance.outlineHalo | Default: halo on icon names; no outline on name plates. |
| appearance.outlineColor | Outline colour |
| appearance.outlineWidth | Thickness |
| appearance.thicknessHint | Relative scale, not pixels. Appearance varies by font. |
| appearance.image | Image |
| appearance.choose | Choose image... |
| appearance.replace | Replace image... |
| appearance.remove | Remove image |
| appearance.backgroundFit | Image fit |
| appearance.fit | Fit |
| appearance.fill | Fill |
| appearance.stretch | Stretch |
| appearance.fitHint | Fit keeps the whole image. Fill crops edges. Stretch changes proportions. |
| appearance.backgroundSizing | Sizing |
| appearance.auto | Automatic |
| appearance.manual | Manual |
| appearance.padding | Padding (% of text size, per side) |
| appearance.backgroundPadX | Horizontal |
| appearance.backgroundPadY | Vertical |
| appearance.dimensionsMap | Dimensions (% of map width) |
| appearance.dimensionsPin | Dimensions (pt; all importance levels) |
| appearance.backgroundWidth | Width |
| appearance.backgroundHeight | Height |
| appearance.offsetMap | Background offset (% of map width) |
| appearance.offsetPin | Background offset (pt) |
| appearance.backgroundX | X (right) |
| appearance.backgroundY | Y (down) |
| appearance.backgroundOpacity | Image opacity (%) |
| appearance.more | More image settings |
| appearance.managed | Image background managed by Director |
| appearance.loading | Loading image... |
| appearance.unavailable | Image unavailable |
| appearance.invalidImage | Choose an accessible still image. |
| appearance.video | Video backgrounds are not supported. Choose a still image. |
| appearance.previewEmpty | No locations on this map to preview. |
| appearance.previewHidden | No pin names visible. Turn on Show names or zoom in to preview. |
