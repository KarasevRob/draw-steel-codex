# Region Map V2 - Copy Manifest

Status: SIGNED OFF by the user 2026-10-05. Companion to [V2_BRIEF.md](V2_BRIEF.md).
Every user-facing string in V2 is listed here. A string that is not in this file does not
ship. IDs are the keys the code will use, so a wording change touches this file and one
lookup table only.

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
| A location's own image | map | region map, child map, submap |
| The list of top-level maps | Atlas | library, maps list |
| The group of heroes | Party (in controls); `{party}` in the marker, status, toasts and log | group, heroes, tokens |
| Director-only state | Hidden | Director only, secret, private |
| Players can see it | Revealed | Shared, public, visible |
| Players can open a location's map | Map shared / Not shared | published, public |
| Pushing the map to every screen | Show to players | present, share, broadcast |
| The Director's local preview | View as player | player view, preview |
| Party not at a location | traveling | travelling, free, moving |
| Pin size and text weight (D5b) | Importance: Major, Normal, Minor | tier, rank, size |
| How a pin is drawn (D5a) | Pin style: Icon + name, Name plate, Icon only | label style, display |
| Pins cannot be dragged | Pins locked / Pins unlocked | edit mode, frozen |
| Travel history | Session log | journal, history, travel log |
| Forcing every name on | Show names | show labels |

## 3. Window and toolbar

| ID | String | When / notes |
|---|---|---|
| window.title | Region Map | Rail button and window title (unchanged from V1) |
| tb.search | Search locations | Tooltip |
| tb.add | Add location | Tooltip |
| tb.lock.on | Pins locked - click to unlock | Tooltip, default state |
| tb.lock.off | Pins unlocked - click to lock | Tooltip |
| tb.ruler | Ruler | Tooltip |
| tb.show | Show this map to players | Tooltip, Director only |
| tb.viewAs.off | View as player | Tooltip, Director only |
| tb.viewAs.on | Stop viewing as player | Tooltip |
| tb.log | Session log | Tooltip |
| tb.expand.off | Expand | Tooltip |
| tb.expand.on | Restore window size | Tooltip |
| tb.settings | Region Map settings | Tooltip, Director only |

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
| atlas.card.notShared | Not shared | Chip, Director only. A shared map has no chip |
| atlas.card.count | {count} locations | Card footer |
| atlas.new | New map | Last card |
| atlas.new.hint | Choose an image to start a top-level map | Under "New map" |
| atlas.new.picker | Choose a map image | Image picker title |
| atlas.new.defaultName | New map | Name of a new map until renamed (opens with the name selected) |
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
| status.elsewhere.tooltip | Go to the Party | |
| status.none | {party} is not on a map | |
| status.none.hint | Right-click a map to place the Party. | Tooltip, Director only |
| banner.viewAs | Viewing as player - hidden locations are not shown | Director, View as player on (R9) |
| chip.unlocked | Pins unlocked - drag to move | While unlocked (R6) |
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
| panel.more | More actions | "..." tooltip |
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
| menu.linkJournal | Link journal entry... | No link yet |
| menu.changeJournal | Change journal entry... | Linked |
| menu.unlinkJournal | Unlink journal entry | Linked |
| menu.delete | Delete | Danger color |
| picker.moveToMap.title | Move {name} to... | Map picker |
| picker.moveToMap.hint | It goes to the middle of that map. Unlock pins to place it exactly. | |

Players see Move, Move to map..., and Delete on their own locations only.

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
| search.result.path | {map} > {parent} | Second line of a result; ">" drawn as an icon |
| search.none | No locations match "{query}". | |
| search.hint | Enter opens the top result. | Under the field (R9) |

## 13. Settings popover

| ID | String | When / notes |
|---|---|---|
| set.title | Region Map settings | |
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
| log.showRoute | Show route | Toggle for the drawn past route |
| log.empty | No travel yet. Entries appear when the Party moves. | |

## 16. Limits, load and migration

| ID | String | When / notes |
|---|---|---|
| limit.locations | This map has 250 locations, the most it can hold. Delete some to add more. | Creation guard (D13f) |
| load.missing | Region Map needs a newer Draw Steel Codex and was not loaded. Missing: {list} | Unchanged from V1 |
| ~~migrate.done~~ | ~~Region Map updated: your maps and labels are now locations. Nothing was removed.~~ | Dropped 2026-10-06 with the migration (brief R17) |

## 17. Choices made in this manifest

These follow from the brief but were not spelled out there; signing off the manifest
signs these off too.

1. "traveling" (US), not "travelling", to match the app.
2. Controls say "Party" ("Move Party here", "Place Party here"); the custom name appears in
   the marker, status, toasts and log, so buttons never grow with a long name.
3. " - " replaces the mockup's middle dot (ASCII-only source).
4. The status chip names the map when the Party is elsewhere, and clicking it goes there.
5. Remove map deletes the locations pinned on that map, after a confirm, like Delete (D7d).
6. Atlas cards show only "Not shared"; a shared map has no chip. The mockup's "Shared"
   chip and its "Shared with the table" panel line are dropped.
7. Director-made locations show no author line; only player-made ones do (R11). The
   mockup's "Added by the Director" is dropped.
8. A one-time migration notice to the Director.
9. Travel pace is optional and has no default; without it the ruler shows distance only.
