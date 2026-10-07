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
    ["window.title"] = "Region Map",
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
    ["tb.settings"] = "Region Map settings",

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
    ["atlas.new"] = "New map",
    ["atlas.new.hint"] = "Choose an image to start a top-level map",
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
    ["search.result.path"] = "{map} > {parent}",
    ["search.none"] = "No locations match \"{query}\".",
    ["search.hint"] = "Enter opens the top result.",

    -- 13. Settings popover
    ["set.title"] = "Region Map settings",
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
    ["set.you"] = "Only for you",
    ["set.reduceMotion"] = "Reduce motion",

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
    ["load.missing"] = "Region Map needs a newer Draw Steel Codex and was not loaded. Missing: {list}",
}

-- Month names for log.day.date, indexed 1..12. Not locale-aware: the manifest is US English.
RegionMapCopy.months = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

local missingReported = {} --- @type table<string, boolean>

--- Escape rich-text markup so user text (a Location name, a player's name)
--- never renders as markup. Same rule as V1 RegionMapModel.LiteralText.
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
