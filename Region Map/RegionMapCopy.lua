--- Every user-facing Region Map string, keyed by the copy manifest ID
--- (docs/V2_COPY.md). Change wording here and in the manifest together; a
--- string that is not in the manifest does not ship.
--- @class RegionMapCopy: GameType
--- @field new fun(o?: table): RegionMapCopy
RegionMapCopy = RegisterGameType("RegionMapCopy")

-- Keys ending in ".one" are the singular form of the key without it. T() picks
-- one automatically when args.count == 1, so callers always pass the plural ID.
RegionMapCopy.strings = {
    -- 3. Window and toolbar
    ["window.title"] = "Overland Map",
    ["tb.search"] = "Search locations",
    ["tb.add"] = "Add location",
    ["tb.lock.on"] = "Pins locked - click to unlock",
    ["tb.lock.off"] = "Pins unlocked - click to lock",
    ["tb.ruler"] = "Ruler",
    ["tb.show"] = "Show this map to players",
    ["tb.viewAs.off"] = "View as player",
    ["tb.viewAs.on"] = "Stop viewing as player",
    ["tb.log"] = "Session log",
    ["tb.expand.off"] = "Expand",
    ["tb.expand.on"] = "Restore window size",
    ["tb.settings"] = "Overland Map settings",

    -- 4. Breadcrumb and Atlas
    ["crumb.root"] = "Atlas",
    ["crumb.hover"] = "{name}\n{description}\n{hint}",
    ["crumb.hover.nameOnly"] = "{name}\n{hint}",
    ["crumb.hint.up"] = "Click to go to this map. Right-click to read about it.",
    ["crumb.hint.current"] = "Click to read about this map.",
    ["atlas.card.open"] = "Open {map}",
    ["atlas.card.party"] = "Party here",
    ["atlas.card.notShared"] = "Not shared",
    ["atlas.card.count"] = "{count} locations",
    ["atlas.card.count.one"] = "{count} location",
    ["atlas.new.picker"] = "Choose a map image",
    ["atlas.new.defaultName"] = "New map",
    ["atlas.empty.director.title"] = "No maps yet",
    ["atlas.empty.director.body"] = "Create your first map from any image.",
    ["atlas.empty.player.title"] = "No maps yet",
    ["atlas.empty.player.body"] = "Maps appear here when the Director shares them.",

    -- 5. Map surface
    ["cam.fit"] = "Fit map",
    ["cam.zoomOut"] = "Zoom out",
    ["cam.zoomIn"] = "Zoom in",
    ["cam.names"] = "Show names",
    ["pin.hover"] = "{name}\n{description}",
    ["pin.hover.nameOnly"] = "{name}",
    ["party.defaultName"] = "Party",
    ["party.tooltip.move"] = "{party} - drag to move",
    ["party.tooltip"] = "{party}",
    ["status.at"] = "{party} at {name}",
    ["status.traveling"] = "{party} - traveling",
    ["status.elsewhere"] = "{party} on {map}",
    ["status.elsewhere.tooltip"] = "Go to the Party",
    ["status.none"] = "{party} is not on a map",
    ["status.none.hint"] = "Right-click a map to place the Party.",
    ["banner.viewAs"] = "Viewing as player - hidden locations are not shown",
    ["chip.unlocked"] = "Pins unlocked - drag to move",
    ["hint.add"] = "Click the map to add a location. Esc to stop.",
    ["hint.move"] = "Click where {name} should go. Esc cancels.",
    ["hint.ruler"] = "Ruler: click a start, then an end. Only you see it. Esc stops.",

    -- 6. Right-click menus
    ["ctx.map.add"] = "Add location here",
    ["ctx.map.party"] = "Place Party here",

    -- 7. Side panel, read mode
    ["panel.close"] = "Close",
    ["panel.meta"] = "{importance} - {visibility}",
    ["panel.eye.hidden"] = "Hidden - click to reveal to players",
    ["panel.eye.revealed"] = "Revealed - click to hide from players",
    ["panel.map.off"] = "Not shared - click to share this map",
    ["panel.map.on"] = "Map shared - click to stop sharing",
    ["panel.desc.empty"] = "No description yet.",
    ["panel.journal"] = "Read in journal",
    ["panel.author"] = "Added by {player}",
    ["panel.partyHere"] = "{party} is here",
    ["panel.moveParty"] = "Move Party here",
    ["panel.openMap"] = "Open map",
    ["panel.edit"] = "Edit",
    ["panel.more"] = "More actions",
    ["panel.notes"] = "Director notes",
    ["panel.notes.sub"] = "Players don't see these",

    -- 8. The "..." menu
    ["menu.move"] = "Move",
    ["menu.moveToMap"] = "Move to map...",
    ["menu.hide"] = "Hide from players",
    ["menu.reveal"] = "Reveal to players",
    ["menu.addMap"] = "Add map...",
    ["menu.replaceImage"] = "Replace map image...",
    ["menu.removeMap"] = "Remove map",
    ["menu.linkJournal"] = "Link journal entry...",
    ["menu.changeJournal"] = "Change journal entry...",
    ["menu.unlinkJournal"] = "Unlink journal entry",
    ["menu.delete"] = "Delete",
    ["picker.moveToMap.title"] = "Move {name} to...",
    ["picker.moveToMap.hint"] = "It goes to the middle of that map. Unlock pins to place it exactly.",

    -- 9. Side panel, edit mode
    ["edit.visibility"] = "Visibility",
    ["edit.visibility.hidden"] = "Hidden",
    ["edit.visibility.revealed"] = "Revealed",
    ["edit.name"] = "Name",
    ["edit.name.placeholder"] = "Name this location",
    ["edit.name.fallback"] = "Unnamed location",
    ["edit.icon"] = "Icon",
    ["edit.icon.choose"] = "Choose icon...",
    ["edit.icon.clear"] = "No icon",
    ["edit.icon.picker"] = "Choose an icon",
    ["edit.icon.tab.map"] = "Map icons",
    ["edit.icon.tab.library"] = "Library",
    ["edit.style"] = "Pin style",
    ["edit.style.iconName"] = "Icon + name",
    ["edit.style.plate"] = "Name plate",
    ["edit.style.iconOnly"] = "Icon only",
    ["edit.importance"] = "Importance",
    ["edit.importance.major"] = "Major",
    ["edit.importance.normal"] = "Normal",
    ["edit.importance.minor"] = "Minor",
    ["edit.desc"] = "Description",
    ["edit.desc.placeholder"] = "A line or two that players read.",
    ["edit.journal"] = "Journal entry",
    ["edit.notes"] = "Director notes",
    ["edit.notes.placeholder"] = "Only you see these.",
    ["edit.saving"] = "Saving...",
    ["edit.saved"] = "Saved",
    ["edit.notSaved"] = "Not saved",
    ["edit.retry"] = "Retry",
    ["edit.done"] = "Done",

    -- 10. Toasts
    ["toast.hid"] = "{name} hidden from players",
    ["toast.revealed"] = "{name} revealed to players",
    ["toast.mapShared"] = "{map} shared with players",
    ["toast.mapUnshared"] = "{map} no longer shared",
    ["toast.moved"] = "{name} moved",
    ["toast.movedToMap"] = "{name} moved to {map}",
    ["toast.partyAt"] = "{party} moved to {name}",
    ["toast.partyTraveling"] = "{party} is traveling",
    ["toast.partyPlaced"] = "{party} placed on {map}",
    ["toast.deleted"] = "{name} deleted",
    ["toast.deletedTree"] = "{name} and {count} locations inside it deleted",
    ["toast.deletedTree.one"] = "{name} and {count} location inside it deleted",
    ["toast.mapRemoved"] = "Map removed from {name}",
    ["toast.showing"] = "Showing {map} to players",
    ["toast.shown"] = "The Director showed you {map}",
    ["toast.saveFailed"] = "Couldn't save. Check your connection.",
    ["toast.undo"] = "Undo",
    ["toast.retry"] = "Retry",

    -- 19. Image size guidance (V2.1)
    ["image.hint"] = "Best at {recommended} px wide. Under {min} px it blurs when zoomed in; over {max} px it loads slowly.",
    ["toast.image.small"] = "This image is {width} x {height} px. Maps look best at {recommended} px wide; smaller images blur when zoomed in.",
    ["toast.image.large"] = "This image is {width} x {height} px and may load slowly. {recommended} px wide is enough.",
    ["toast.replaceImage"] = "Replace image...",

    -- 11. Dialogs
    ["dlg.delete.title"] = "Delete {name}?",
    ["dlg.delete.body"] = "This also deletes {count} locations inside it.",
    ["dlg.delete.body.one"] = "This also deletes {count} location inside it.",
    ["dlg.delete.party"] = "The Party moves to {map}.",
    ["dlg.delete.ok"] = "Delete",
    ["dlg.removeMap.title"] = "Remove the map from {name}?",
    ["dlg.removeMap.body"] = "The map image is removed and the {count} locations pinned on it are deleted.",
    ["dlg.removeMap.body.one"] = "The map image is removed and the {count} location pinned on it is deleted.",
    ["dlg.removeMap.body.empty"] = "The map image is removed.",
    ["dlg.removeMap.ok"] = "Remove map",
    ["dlg.share.title"] = "Share this map?",
    ["dlg.share.body"] = "Players can't see {map} yet. Share it to show it to them.",
    ["dlg.share.ok"] = "Share and show",
    ["dlg.cancel"] = "Cancel",

    -- 12. Search
    ["search.placeholder"] = "Search locations",
    ["search.none"] = "No locations match \"{query}\".",
    ["search.hint"] = "Enter opens the top result.",

    -- 13. Settings popover
    ["set.title"] = "Overland Map settings",
    ["set.party"] = "Party",
    ["set.party.name"] = "Party name",
    ["set.party.image"] = "Party image",
    ["set.party.image.choose"] = "Choose image...",
    ["set.party.image.reset"] = "Use the banner",
    ["set.party.playersMove"] = "Players can move the Party",
    ["set.playersAdd"] = "Players can add locations",
    ["set.map"] = "This map",
    ["set.map.scale"] = "Map scale",
    ["set.map.scale.none"] = "Not set",
    ["set.map.scale.value"] = "{distance} {unit} between the two scale points",
    ["set.map.scale.set"] = "Set scale...",
    ["set.map.scale.hint"] = "Click two points on the map, then enter the distance between them.",
    ["set.map.scale.distance"] = "Distance",
    ["set.map.scale.unit.mi"] = "miles",
    ["set.map.scale.unit.km"] = "kilometers",
    ["set.map.pace"] = "Travel pace per day",
    ["set.map.border"] = "Map border",
    ["set.map.border.hint"] = "New maps start with the border you picked last.",
    ["set.border.none"] = "None",
    ["set.border.fade"] = "Soft fade",
    ["set.border.torn"] = "Torn edge",
    ["set.border.frame"] = "Frame",
    ["set.border.needsArt"] = "Not available yet: this border needs its art.",
    ["set.game"] = "Whole game",

    -- Import (V2.1 manifest section 20)
    ["menu.import"] = "Import locations...",
    ["import.picker"] = "Choose a JSON file of locations",
    ["import.title"] = "Import locations",
    ["import.summary"] = "Import {count} locations into {map}?",
    ["import.summary.one"] = "Import 1 location into {map}?",
    ["import.skipped"] = "{count} entries will be skipped:",
    ["import.skipped.one"] = "1 entry will be skipped:",
    ["import.skip.noName"] = "Entry {n}: it has no name.",
    ["import.skip.name"] = "Entry {n}: its name is over 80 characters or has a line break.",
    ["import.skip.position"] = "Entry {n}: u and v must both be between 0 and 1, or both left out.",
    ["import.skip.field"] = "Entry {n}: {field} is not a valid value.",
    ["import.skip.tooLong"] = "Entry {n}: {field} is too long.",
    ["import.duplicates"] = "{count} names are already on this map; they will be added again:",
    ["import.duplicates.one"] = "1 name is already on this map; it will be added again:",
    ["import.placement"] = "Locations without a position are set out in rows near the center of the map. Unlock pins to place them exactly. One Undo removes the whole import.",
    ["import.ok"] = "Import {count} locations",
    ["import.ok.one"] = "Import 1 location",
    ["import.tooMany"] = "This file has {count} locations, but {map} has room for {room} more (a map holds up to 250). Nothing will be imported; split the file and import it in parts.",
    ["import.error.json"] = "This file isn't valid JSON, so nothing was imported.",
    ["import.error.empty"] = "This file has no locations in it.",
    ["import.error.allSkipped"] = "None of the entries in this file can be imported:",
    ["dlg.close"] = "Close",
    ["toast.imported"] = "{count} locations imported into {map}",
    ["toast.imported.one"] = "1 location imported into {map}",
    ["set.you"] = "Only for you",
    ["set.reduceMotion"] = "Reduce motion",

    -- 18. Map mode (V2.1)
    ["mode.title"] = "What kind of map?",
    ["mode.free"] = "Free map",
    ["mode.free.desc"] = "Drag the Party anywhere on it.",
    ["mode.pointcrawl"] = "Point crawl map",
    ["mode.pointcrawl.desc"] = "The Party travels along paths you draw.",
    ["mode.permanent"] = "You can't change this later.",
    ["mode.back"] = "Back",
    ["side.addMap.title"] = "Add a map to {name}",
    ["chip.pointcrawl"] = "Point crawl",
    ["hint.pointcrawl.empty"] = "Add locations, then join them with the Path tool.",

    -- 21. Paths (V2.1)
    ["tb.path"] = "Path tool",
    ["tb.path.disabled"] = "Add at least two locations to draw a path.",
    ["hint.path.start"] = "Click the location the path starts from. Esc to stop.",
    ["hint.path.next"] = "Click the map to add a bend, or click the location the path ends at. Right-click or Backspace removes the last bend. Esc cancels this path.",
    ["hint.redraw"] = "Redraw {path}: click the map to add bends, then click {name}. Esc cancels.",
    ["menu.connect"] = "Connect to...",
    ["picker.connect.title"] = "Connect {name} to...",
    ["picker.connect.none"] = "No other locations on this map.",
    ["menu.redraw"] = "Redraw line",
    ["path.title.noType"] = "Path: {a} - {b}",
    ["path.title.unnamed"] = "{type}: {a} - {b}",
    ["path.label"] = "{path} - {time}",
    ["path.ends"] = "Between {a} and {b}",
    ["path.time"] = "{time}",
    ["path.time.both"] = "{time} from {a}, {backTime} from {b}",
    ["path.time.oneWay"] = "{time}, from {a} to {b} only",
    ["path.type.none"] = "No type",
    ["path.waits"] = "Revealed - players see it once {name} is revealed.",
    ["path.note"] = "Danger or requirement",
    ["path.note.sub"] = "Players don't see this",
    ["path.note.placeholder"] = "Only you see this.",
    ["edit.path.name.placeholder"] = "Name this path (optional)",
    ["edit.path.type"] = "Type",
    ["edit.path.time"] = "Travel time",
    ["edit.path.unit.hint"] = "The unit is set in Settings.",
    ["edit.path.timeRange"] = "Enter a time of 0 or more.",
    ["edit.path.back"] = "The other way",
    ["edit.path.back.same"] = "Same",
    ["edit.path.back.different"] = "Different time",
    ["edit.path.back.none"] = "Not possible",
    ["edit.path.backTime"] = "Time from {b}",
    ["edit.path.bends"] = "Unlock pins to drag the line's bends. Right-click a bend to remove it; drag a + to add one.",
    ["panel.paths"] = "Paths",
    ["panel.paths.row"] = "{dest} by {path} - {time}",
    ["panel.paths.none"] = "No paths yet.",
    ["toast.pathDeleted"] = "{path} deleted",
    ["dlg.delete.paths"] = "This also deletes {count} paths.",
    ["dlg.delete.paths.one"] = "This also deletes 1 path.",
    ["dlg.moveToMap.title"] = "Move {name} to {map}?",
    ["dlg.moveToMap.body"] = "Its {count} paths on this map are deleted.",
    ["dlg.moveToMap.body.one"] = "Its 1 path on this map is deleted.",
    ["dlg.moveToMap.ok"] = "Move",

    -- 22. Path types and travel time (V2.1)
    ["set.timeUnit"] = "Travel time",
    ["set.timeUnit.days"] = "Days",
    ["set.timeUnit.watches"] = "Watches",
    ["set.timeUnit.hint"] = "A watch is 4 hours; 6 watches make a day.",
    ["set.pathTypes"] = "Path types",
    ["set.pathTypes.hint"] = "Each type has its own line on the map.",
    ["set.pathType.edit"] = "Edit",
    ["set.pathType.name"] = "Name",
    ["set.pathType.newName"] = "New type",
    ["set.pathType.pattern"] = "Line",
    ["set.pathType.color"] = "Color",
    ["set.pathType.width"] = "Width",
    ["set.pathType.sameLook"] = "Looks the same as {type}. Change the line or width to tell them apart.",
    ["set.pathType.delete"] = "Delete type",
    ["set.pathType.add"] = "Add path type",
    ["pattern.solid"] = "Solid",
    ["pattern.dashed"] = "Dashed",
    ["pattern.dotted"] = "Dotted",
    ["pattern.double"] = "Double",
    ["pattern.dashDot"] = "Dash-dot",
    ["pattern.longDash"] = "Long dash",
    ["color.parchment"] = "Parchment",
    ["color.blue"] = "Blue",
    ["color.ochre"] = "Ochre",
    ["color.violet"] = "Violet",
    ["color.rust"] = "Rust",
    ["color.ink"] = "Ink",
    ["width.thin"] = "Thin",
    ["width.normal"] = "Normal",
    ["width.thick"] = "Thick",
    ["type.road"] = "Road",
    ["type.trail"] = "Trail",
    ["type.river"] = "River",
    ["type.sea"] = "Sea",
    ["type.underground"] = "Underground",
    ["type.secret"] = "Secret",
    ["dlg.deleteType.title"] = "Delete {type}?",
    ["dlg.deleteType.body"] = "{count} paths use it. They stay on the map as a plain line with no type.",
    ["dlg.deleteType.body.one"] = "1 path uses it. It stays on the map as a plain line with no type.",
    ["dlg.deleteType.ok"] = "Delete type",
    ["toast.typeDeleted"] = "{type} deleted",
    ["time.days"] = "{count} days",
    ["time.days.one"] = "1 day",
    ["time.watches"] = "{count} watches",
    ["time.watches.one"] = "1 watch",
    ["time.daysWatches"] = "{days} and {watches}",
    ["time.none"] = "no time",

    -- 23. Travel (V2.1)
    ["party.section"] = "Party",
    ["party.status.at"] = "{party} is at {name}",
    ["party.status.onPath"] = "{party} is on {path}, {time} from {name}",
    ["party.travelTo"] = "Travel to",
    ["party.travel.row"] = "{dest} by {path}",
    ["party.travel.none"] = "No paths lead on from here.",
    ["party.travel.offPath"] = "{party} is not on a location or a path. Right-click a path or a location to place it.",
    ["party.travel.offPath.player"] = "{party} is not on a path.",
    ["party.travel.noPermission"] = "Only the Director can move {party}.",
    ["party.tooltip.travel"] = "{party} - click to travel",
    ["hint.dragTravel"] = "On this map {party} travels along paths. Click it to travel.",
    ["ctx.party.travelMenu"] = "Travel to",
    ["ctx.party.travel"] = "Travel to {dest} by {path} ({time})",
    ["ctx.path.place"] = "Place Party on {path}",
    ["dlg.stop.title"] = "Stop {party} on {path}",
    ["dlg.stop.field"] = "Time already spent from {name}",
    ["dlg.stop.of"] = "of {time}",
    ["dlg.stop.swap"] = "Count from {name} instead",
    ["dlg.stop.hint"] = "Going on takes the rest of the time; turning back takes the time spent.",
    ["dlg.stop.range"] = "Enter a time above 0 and under {time}.",
    ["dlg.stop.ok"] = "Place Party",
    ["dlg.hiddenTravel.title"] = "{path} is hidden",
    ["dlg.hiddenTravel.body"] = "Players don't know this path yet. Reveal it before {party} travels?",
    ["dlg.hiddenTravel.reveal"] = "Reveal and travel",
    ["dlg.hiddenTravel.keep"] = "Travel without revealing",
    ["toast.traveled"] = "{party} traveled from {from} to {to}{by} - {time}",
    ["toast.stopped"] = "{party} stopped on {path}",
    ["status.onPath"] = "{party} on {path}",

    -- 24. Session log (V2.1)
    ["log.leg"] = "Traveled from {from} to {to}{by} - {time}",
    ["log.leg.on"] = "Traveled on to {to}{by} - {time}",
    ["log.leg.back"] = "Turned back to {to}{by} - {time}",
    -- The {by} piece: the leading space is part of it, so "no path name" leaves no gap.
    ["leg.by"] = " by {path}",
    ["log.stopped"] = "Stopped on {path}, {time} from {name}",
    ["log.stopped.noPath"] = "Stopped on the way, {time} from {name}",

    -- 14. Ruler
    ["ruler.distance"] = "{distance} {unitShort}",
    ["ruler.withTime"] = "{distance} {unitShort} - {time}",
    ["ruler.unitShort.mi"] = "mi",
    ["ruler.unitShort.km"] = "km",
    ["ruler.time.under"] = "under half a day",
    -- Pass count = days as well so "1 day" picks the singular.
    ["ruler.time.days"] = "{days} days",
    ["ruler.time.days.one"] = "{days} day",
    ["ruler.uncalibrated"] = "{percent}% of map width",
    ["ruler.uncalibrated.hint"] = "Set this map's scale in Settings to measure distance.",

    -- 15. Session log
    ["log.title"] = "Session log",
    ["log.day.today"] = "Today",
    ["log.day.yesterday"] = "Yesterday",
    ["log.day.date"] = "{month} {day}",
    ["log.arrived"] = "Arrived at {name}",
    ["log.traveling"] = "Traveling from {name}",
    ["log.travelingOn"] = "Traveling on {map}",
    ["log.placed"] = "Placed on {map}",
    ["log.by"] = "Moved by {who}",
    ["log.by.director"] = "the Director",
    ["log.merged"] = "{count} moves merged",
    ["log.merged.one"] = "{count} move merged",
    ["log.addNote"] = "Add note",
    ["log.editNote"] = "Edit note",
    ["log.deleteEntry"] = "Delete entry",
    ["log.undoLast"] = "Undo last change",
    ["log.showRoute"] = "Show route",
    ["log.empty"] = "No travel yet. Entries appear when the Party moves.",

    -- 16. Limits and load (migrate.done was dropped with the V1 migration, brief R17)
    ["limit.locations"] = "This map has 250 locations, the most it can hold. Delete some to add more.",
    ["load.missing"] = "Overland Map needs a newer Draw Steel Codex and was not loaded. Missing: {list}",
}

-- Month names for log.day.date, indexed 1..12. Not locale-aware: the manifest is US English.
RegionMapCopy.months = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

local missingReported = {} --- @type table<string, boolean>

--- Escape rich-text markup so user text (a Location name, a player's name)
--- never renders as markup.
--- @param value any
--- @return string
function RegionMapCopy.Literal(value)
    return (tostring(value or ""):gsub("<", "<noparse><</noparse>"))
end

--- Pick the singular or plural form for a count: Count(1, "location", "locations").
--- @param count integer
--- @param singular string
--- @param plural string
--- @return string
function RegionMapCopy.Count(count, singular, plural)
    if count == 1 then return singular end
    return plural
end

--- The string for a manifest ID with {placeholders} filled in. Values are
--- escaped for markup unless raw is true (use raw for text inputs and chat,
--- which do not render markup). An unknown ID logs once and returns the ID,
--- so a gap is visible in testing and never crashes the UI.
--- @param id string
--- @param args nil|table<string, any>
--- @param raw nil|boolean
--- @return string
function RegionMapCopy.T(id, args, raw)
    local text = RegionMapCopy.strings[id]
    if text == nil then
        if not missingReported[id] then
            missingReported[id] = true
            print("REGION_MAP: missing copy " .. tostring(id))
        end
        return tostring(id)
    end
    if args == nil then return text end
    if args.count ~= nil then
        text = RegionMapCopy.Count(args.count, RegionMapCopy.strings[id .. ".one"] or text, text)
    end
    return (text:gsub("{(%w+)}", function(key)
        local value = args[key]
        if value == nil then return "{" .. key .. "}" end
        if raw then return tostring(value) end
        return RegionMapCopy.Literal(value)
    end))
end
