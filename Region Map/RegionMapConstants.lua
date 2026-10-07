--- Shared vocabulary for the Region Map mod: identity, storage names, limits,
--- layout metrics and timings. Every other Region Map file reads these instead
--- of repeating literals.
--- @class RegionMapConstants: GameType
--- @field new fun(o?: table): RegionMapConstants
RegionMapConstants = RegisterGameType("RegionMapConstants")

-- Identity
RegionMapConstants.panelName = "Region Map"
RegionMapConstants.panelIcon = "phosphor/map-trifold.png"
RegionMapConstants.openHandlerId = "00-regionmap"   -- sorts before the icon rail's "iconrail" handler

-- Storage. Table and document names are persisted; never rename them.
-- The details and notes tables date from V1 and keep their row format.
RegionMapConstants.schemaVersion = 1                -- the state document's schema
RegionMapConstants.locationTableName = "RegionMapLocations"
RegionMapConstants.logTableName = "RegionMapLogEntries"
RegionMapConstants.detailsTableName = "RegionMapLocationDetails"
RegionMapConstants.notesTableName = "RegionMapLocationDirectorNotes"
RegionMapConstants.locationSchemaVersion = 1
RegionMapConstants.logSchemaVersion = 1
RegionMapConstants.detailsSchemaVersion = 1
RegionMapConstants.notesSchemaVersion = 1
RegionMapConstants.stateDocumentId = "regionMapState"
RegionMapConstants.preferencesSettingId = "regionmap:preferences"

-- Limits
RegionMapConstants.labelLimit = 250                  -- soft per-map creation guard, counted per viewer
RegionMapConstants.textLimit = 80                    -- Location names, in characters
RegionMapConstants.descriptionLimit = 4000
RegionMapConstants.crumbPreviewLimit = 300           -- description characters a breadcrumb tooltip shows
RegionMapConstants.descriptionByteLimit = 16384
RegionMapConstants.noteLimit = 8000
RegionMapConstants.noteByteLimit = 32768
RegionMapConstants.journalIdLimit = 512
RegionMapConstants.maxRevision = 9007199254740991    -- largest integer a double holds exactly
RegionMapConstants.maxDepth = 16                     -- deepest Location nesting; also stops cycle walks
RegionMapConstants.logCap = 500                      -- newest session log entries kept per game (decision 8.1)
RegionMapConstants.undoDepth = 20                    -- undo entries kept per session

-- Curated pin icons (D5d): key -> Phosphor mask, tinted by style rules.
-- Verified live 2026-10-06 (every path loads a 256 px sprite).
RegionMapConstants.pinIcons = {
    city = "phosphor/buildings.png",
    town = "phosphor/house-line.png",
    castle = "phosphor/castle-turret.png",
    camp = "phosphor/tent.png",
    tavern = "phosphor/beer-stein.png",
    temple = "phosphor/bank.png",
    dungeon = "phosphor/skull.png",
    cave = "phosphor/mountains.png",
    forest = "phosphor/tree-evergreen.png",
    port = "phosphor/anchor.png",
    bridge = "phosphor/bridge.png",
    tower = "phosphor/lighthouse.png",
    danger = "phosphor/warning.png",
    treasure = "phosphor/coins.png",
    quest = "phosphor/flag.png",
    poi = "phosphor/map-pin.png",
}
-- Picker order of the curated icons.
RegionMapConstants.pinIconOrder = {
    "city", "town", "castle", "tower", "temple", "tavern", "camp", "port",
    "bridge", "forest", "cave", "dungeon", "danger", "treasure", "quest", "poi",
}
RegionMapConstants.defaultPinIcon = "poi"            -- drawn when a Location has no icon

-- Camera
RegionMapConstants.minZoom = 1
RegionMapConstants.maxZoom = 20
RegionMapConstants.zoomWheelStep = 1.15
RegionMapConstants.zoomButtonStep = 1.25
RegionMapConstants.panFine = 16                      -- arrow keys pan the camera
RegionMapConstants.panCoarse = 64                    -- with Shift held
RegionMapConstants.canvasDragThreshold = 4           -- screen px before a press becomes a drag
RegionMapConstants.openZoom = 4                      -- how far the camera zooms into a pin before its map opens

-- Pins. Sizes are screen pixels at Font Size 100 and stay constant at every zoom.
RegionMapConstants.pinDisc = { major = 36, normal = 28, minor = 24 }
RegionMapConstants.pinNameSize = { major = 18, normal = 15, minor = 13 }
RegionMapConstants.pinHitMin = 24
RegionMapConstants.pinBadgeSize = 14                 -- hidden / has-a-map badges on a pin's corners
RegionMapConstants.partySize = 40                    -- Party banner disc
RegionMapConstants.partySnapRadius = 32              -- a dropped Party snaps to a pin this close
RegionMapConstants.declutterZoom = { minor = 1.5, normal = 1.0 } -- below this zoom, names of that importance hide
RegionMapConstants.routeDotSpacing = 14
RegionMapConstants.routeDotSize = 5
RegionMapConstants.routeDotLimit = 600               -- most route dots drawn at once (only the visible part is drawn)
RegionMapConstants.rulerWidth = 3                    -- ruler line thickness, screen px
RegionMapConstants.rulerEndSize = 10                 -- ruler end dots

-- Popovers (Search, Settings) under the toolbar
RegionMapConstants.popoverWidth = 340
RegionMapConstants.searchResultLimit = 30

-- Window layout
RegionMapConstants.sidePanelWidth = 320
RegionMapConstants.narrowWidth = 720                 -- below this the side panel takes the full width
RegionMapConstants.atlasCardWidth = 200
RegionMapConstants.atlasCardHeight = 168

-- Timings (seconds)
RegionMapConstants.canvasThinkActive = 0.02          -- pointer over the canvas, a drag, or a transition
RegionMapConstants.canvasThinkIdle = 0.25
RegionMapConstants.rootThink = 0.1
RegionMapConstants.refreshDelay = 0.05               -- coalesces bursts of table/document changes
RegionMapConstants.cameraSaveDelay = 0.5
RegionMapConstants.presentTtl = 10
RegionMapConstants.imageTimeout = 10
RegionMapConstants.autosaveDelay = 1.5               -- side panel saves after this long without typing
RegionMapConstants.busyRetryDelay = 0.3              -- Delete / Remove map wait this long while a save of the row is in flight
RegionMapConstants.busyRetries = 10                  -- then report Not saved
RegionMapConstants.toastSeconds = 10                 -- paused while hovered (R9)
RegionMapConstants.transitionSeconds = 0.3           -- zoom into a pin, then crossfade to its map
RegionMapConstants.controlsFadeSeconds = 2           -- camera controls fade after this long without pointer movement

-- Host window (icon-rail window or the mod's own floating window)
RegionMapConstants.windowWidth = 1000
RegionMapConstants.windowHeight = 800
RegionMapConstants.windowMinWidth = 720
RegionMapConstants.windowMinHeight = 480
RegionMapConstants.windowMaxWidth = 4096              -- large enough for Expand on wide screens
RegionMapConstants.windowMaxHeight = 2160
RegionMapConstants.popoutHeight = 720
RegionMapConstants.hostEdgeMargin = 40             -- the app menu bar sits inside that space
RegionMapConstants.hostVirtualHeight = 1080         -- PresentDocument places windows in a space this tall
-- Expand: the icon rails' measures (DocumentSystem.lua ICON_RAIL_*), in window units before Font Size zoom.
RegionMapConstants.expandRailButton = 40
RegionMapConstants.expandRailInset = 12
RegionMapConstants.expandTopInset = 64
RegionMapConstants.expandGap = 8

-- Icons (Phosphor masks, tinted by style rules). Verified live 2026-10-06.
RegionMapConstants.iconParty = "phosphor/users-three.png"
RegionMapConstants.iconAdd = "phosphor/plus-bold.png"
RegionMapConstants.iconLocked = "phosphor/lock-simple.png"
RegionMapConstants.iconUnlocked = "phosphor/lock-simple-open.png"
RegionMapConstants.iconShow = "phosphor/presentation.png"
RegionMapConstants.iconViewAs = "phosphor/user-focus.png"
RegionMapConstants.iconFit = "phosphor/arrows-out-simple-fill.png"
RegionMapConstants.iconZoomIn = "phosphor/magnifying-glass-plus-bold.png"
RegionMapConstants.iconZoomOut = "phosphor/magnifying-glass-minus-bold.png"
RegionMapConstants.iconNames = "phosphor/text-aa.png"
RegionMapConstants.iconCrumb = "phosphor/caret-right-fill.png"
RegionMapConstants.iconCaret = "phosphor/caret-down-fill.png"
RegionMapConstants.iconClose = "phosphor/x-bold.png"
RegionMapConstants.iconMore = "phosphor/dots-three-bold.png"
RegionMapConstants.iconEye = "phosphor/eye.png"
RegionMapConstants.iconEyeSlash = "phosphor/eye-slash.png"
RegionMapConstants.iconMap = "phosphor/map-trifold.png"
RegionMapConstants.iconImage = "phosphor/image.png"
RegionMapConstants.iconSearch = "phosphor/magnifying-glass-bold.png"
RegionMapConstants.iconRuler = "phosphor/ruler.png"
RegionMapConstants.iconLog = "phosphor/scroll.png"
RegionMapConstants.iconExpand = "phosphor/corners-out.png"
RegionMapConstants.iconRestore = "phosphor/corners-in.png"
RegionMapConstants.iconSettings = "phosphor/gear-six.png"
