--- Shared vocabulary for the Region Map mod: identity, storage names, limits,
--- layout metrics and timings. Every other Region Map file reads these instead
--- of repeating literals.
--- @class RegionMapConstants: GameType
--- @field new fun(o?: table): RegionMapConstants
RegionMapConstants = RegisterGameType("RegionMapConstants")

-- Identity
-- The panel's registered name is also the title on its window and rail button; keep it equal
-- to the copy string window.title. Renamed from "Region Map" 2026-10-08, so saved window
-- placement under the old name no longer applies.
RegionMapConstants.panelName = "Overland Map"
RegionMapConstants.panelIcon = "phosphor/map-trifold.png"

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
RegionMapConstants.logRowsPerFrame = 40              -- log rows built per frame; a full log builds over several frames
RegionMapConstants.undoDepth = 20                    -- undo entries kept per session

-- Allowed values, in the order the editors list them. RegionMapRecords builds its checks
-- from these lists. The values are stored in rows, so never rename one.
RegionMapConstants.pinStyles = { "iconName", "plate", "iconOnly" }
RegionMapConstants.importances = { "major", "normal", "minor" }
RegionMapConstants.visibilities = { "hidden", "revealed" }
RegionMapConstants.scaleUnits = { "mi", "km" }

-- Map image size guidance (V2.1 J1, brief W5): a newly picked image narrower or wider
-- than this warns with a toast; nothing is blocked. Measured 2026-10-08 (TECH_TASK_V2_1).
RegionMapConstants.imageMinWidth = 1500             -- narrower blurs as soon as it is zoomed in
RegionMapConstants.imageRecommendedWidth = 4000     -- shown in the hint and the warnings
RegionMapConstants.imageMaxWidth = 12000            -- wider loads slowly for players

-- Map borders (V2.1 K1), in the order of the Settings tiles. A new map takes the
-- border the Director picked last, Soft fade before any pick (K5, K8).
RegionMapConstants.borders = { "none", "fade", "torn", "frame" }
RegionMapConstants.defaultBorder = "fade"
-- Library image ids of the border art (docs/BORDER_ART.md). While "" the tile is disabled.
RegionMapConstants.borderTornMask = ""
RegionMapConstants.borderFrameImage = ""
-- JSON import (V2.1 idea 9). Locations without a position are set out in a grid with
-- columns this far apart (share of the map's width) and rows closer, since a pin with its
-- name is wider than tall. Rows are created importBatch at a time, each batch waiting
-- for the server; a batch that has not answered in importWait seconds fails.
RegionMapConstants.importSpacing = 0.11
RegionMapConstants.importRowShare = 0.45            -- row gap / column gap, on screen
RegionMapConstants.importBatch = 10
RegionMapConstants.importWait = 20

-- The soft fade band: this share of the image's shorter side on screen, at most fadeMaxWidth px.
RegionMapConstants.fadeShare = 0.06
RegionMapConstants.fadeMaxWidth = 72

-- Point crawl (V2.1 7.2/7.3). A map's mode is set when it is made and never changes (A4).
RegionMapConstants.modes = { "free", "pointcrawl" }
RegionMapConstants.pathTableName = "RegionMapPaths"   -- persisted; never rename
RegionMapConstants.pathSchemaVersion = 1
RegionMapConstants.pathBendLimit = 32
RegionMapConstants.pathTypeIdLimit = 64
-- Travel times are stored in watches (4 hours); the unit setting changes only the display (C9).
RegionMapConstants.watchesPerDay = 6
RegionMapConstants.pathTimeMax = RegionMapConstants.watchesPerDay * 999 -- watches; a typo guard, not a game rule
RegionMapConstants.defaultTimeUnit = "days"
RegionMapConstants.pathTimeUnits = { "days", "watches" }
RegionMapConstants.pathBacks = { "same", "different", "none" } -- the other way: same time, its own time, not possible
-- Line looks (N1, Q3). Patterns and widths are drawn in screen pixels, the same at every zoom (Q2).
RegionMapConstants.pathPatterns = { "solid", "dashed", "dotted", "double", "dashDot", "longDash" }
RegionMapConstants.pathWidthOrder = { "thin", "normal", "thick" }
RegionMapConstants.pathWidths = { thin = 2, normal = 3, thick = 4 }
-- The path colours are map ink, not UI chrome, so they stay the same in every theme.
RegionMapConstants.pathColorOrder = { "parchment", "blue", "ochre", "violet", "rust", "ink" }
RegionMapConstants.pathColors = {
    parchment = "#F2EDE1", blue = "#6FA8DC", ochre = "#C9A06A",
    violet = "#B48EAD", rust = "#D08770", ink = "#1A1A1E",
}
-- Casing under every line (Q1): dark under light colours, light under Ink.
RegionMapConstants.pathCasingDark = "#141416"
RegionMapConstants.pathCasingLight = RegionMapConstants.pathColors.parchment
RegionMapConstants.pathCasing = 1.5                  -- px each side
RegionMapConstants.pathHalo = 4                      -- px each side of the casing, selected path (Q5)
RegionMapConstants.pathBadgeSize = 16                -- eye-slash on hidden paths (Q12)
-- A hidden path's line fades to this; 0.6 keeps every colour at 3:1 or more against its
-- casing (measured, V21-18). The eye-slash badge, not the fade, says "hidden".
RegionMapConstants.pathHiddenOpacity = 0.6
-- Path labels (Q11). With Show names on, a label shows only where it fits: its line
-- on screen is at least labelFit of its width, and it clears pins and other labels.
-- Widths are estimated (charWidth em per character) so no frame waits on a measure.
RegionMapConstants.pathLabelSize = 13
RegionMapConstants.pathLabelCharWidth = 0.52
RegionMapConstants.pathLabelPad = 8                  -- px each side; matches the style's hpad
RegionMapConstants.pathLabelFit = 0.8
RegionMapConstants.pathLabelGap = 4                  -- px kept clear around a label
-- Starter types (C4, N1, Q3): every pattern differs, so no two tell apart by colour alone.
RegionMapConstants.starterPathTypes = {
    { id = "road", pattern = "solid", color = "parchment", width = "thick" },
    { id = "trail", pattern = "dashed", color = "parchment", width = "normal" },
    { id = "river", pattern = "double", color = "blue", width = "normal" },
    { id = "sea", pattern = "dashDot", color = "blue", width = "normal" },
    { id = "underground", pattern = "dotted", color = "ochre", width = "thick" },
    { id = "secret", pattern = "longDash", color = "violet", width = "thin" },
}
-- Line pieces (marks and casings) placed at once; past it a segment draws as one solid bar.
-- F4, measured 2026-10-10 with 250 pins and 315 segments: 1401 pieces at fit, 2329 three
-- zoom steps in, the cap reached only at the deepest zoom. A re-place of ~2300 costs ~30 ms.
RegionMapConstants.pathPieceLimit = 2500
-- Path editing (V21-11, V21-14).
RegionMapConstants.firstPathType = "road"            -- the first path of a game: Road, 1 day (Q8)
RegionMapConstants.firstPathTime = RegionMapConstants.watchesPerDay -- watches: 1 day
-- A second path between the same two pins bows out by this share of its length, per path (Q9).
RegionMapConstants.pathParallelOffset = 0.12
RegionMapConstants.pathHandleSize = 10               -- bend handle disc, px (Q5)
RegionMapConstants.pathHandleHit = 24                -- its hit area, px
RegionMapConstants.pathPlusSize = 14                 -- the "+" at a segment's middle that adds a bend

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
-- Wheel notches closer together than this are one zoom: the path and route lines
-- stretch meanwhile and are placed again once, when the wheel rests this long.
RegionMapConstants.zoomSettleSeconds = 0.15
RegionMapConstants.zoomButtonStep = 1.25
RegionMapConstants.panFine = 16                      -- arrow keys pan the camera
RegionMapConstants.panCoarse = 64                    -- with Shift held
RegionMapConstants.canvasDragThreshold = 4           -- screen px before a press becomes a drag
RegionMapConstants.openZoom = 4                      -- how far the camera zooms into a pin before its map opens
RegionMapConstants.partyFocusZoom = 2                -- the status chip zooms in at least this far, so going to the Party always shows a move

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
RegionMapConstants.atlasThumbHeight = 104            -- a card's image, and the New map card's image picker
-- The toolbar (top right) and camera controls (bottom left) sit chromeInset from the
-- window's edges; the side panel and popovers start below the toolbar, and toasts sit
-- above the camera controls, the same gap away.
RegionMapConstants.chromeInset = 8
RegionMapConstants.chromeBarHeight = 38
RegionMapConstants.breadcrumbHeight = 34
RegionMapConstants.belowChromeBar = RegionMapConstants.chromeInset * 2 + RegionMapConstants.chromeBarHeight

-- Timings (seconds)
-- Active: pointer over the canvas, a drag, or a transition. 0.001 means every frame;
-- a fixed 0.02 (50 Hz) skipped frames on 60 Hz+ screens, so pans and zooms judder.
RegionMapConstants.canvasThinkActive = 0.001
RegionMapConstants.canvasThinkIdle = 0.25
RegionMapConstants.rootThink = 0.1
RegionMapConstants.refreshDelay = 0.05               -- coalesces bursts of table/document changes
RegionMapConstants.cameraSaveDelay = 0.5
RegionMapConstants.saveRecheckDelay = 0.5            -- an edit form still showing Saving... checks again after this
RegionMapConstants.undoTick = 0.25                   -- the undo toast's timer, and polls while an undo waits for its writes
RegionMapConstants.undoSettleSeconds = 5             -- an undo gives up waiting for its writes after this
RegionMapConstants.presentTtl = 10
RegionMapConstants.autosaveDelay = 1.5               -- side panel saves after this long without typing
RegionMapConstants.busyRetryDelay = 0.3              -- Delete / Remove map wait this long while a save of the row is in flight
RegionMapConstants.busyRetries = 10                  -- then report Not saved
RegionMapConstants.afterLayoutDelay = 0.05           -- a panel just shown has laid out: focus its input, scroll it
RegionMapConstants.toastSeconds = 10                 -- paused while hovered (R9)
RegionMapConstants.transitionSeconds = 0.3           -- zoom into a pin, then crossfade to its map
-- The Party banner walking a leg or stop along its path's line (point crawl maps).
RegionMapConstants.partyMoveSpeed = 450              -- screen px per second at the current zoom
RegionMapConstants.partyMoveMinSeconds = 0.6         -- a short hop still reads as a move
RegionMapConstants.partyMoveMaxSeconds = 2           -- a leg across the whole map never drags on
RegionMapConstants.partyMoveEdge = 0.15              -- share of the walk spent stepping off / onto a pin's side
RegionMapConstants.partyMoveFresh = 5                -- only legs logged this recently play; older ones (late join, reopen) do not
RegionMapConstants.controlsFadeSeconds = 2           -- camera controls fade after this long without pointer movement

-- Native popout window (the map is otherwise fullscreen). The popout opens at
-- windowWidth x popoutHeight; the bounds limit resizing it.
RegionMapConstants.windowWidth = 1000
RegionMapConstants.windowHeight = 800
RegionMapConstants.windowMinWidth = 720
RegionMapConstants.windowMinHeight = 480
RegionMapConstants.windowMaxWidth = 4096
RegionMapConstants.windowMaxHeight = 2160
RegionMapConstants.popoutHeight = 720
-- The icon rails' measures (DocumentSystem.lua ICON_RAIL_*, IconRailTop), in layer
-- units before Font Size zoom: the fullscreen map sits between the rails.
RegionMapConstants.railButton = 40
RegionMapConstants.railInset = 12
RegionMapConstants.railGap = 8
RegionMapConstants.railStopGap = 12
RegionMapConstants.railTopMin = 64

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
RegionMapConstants.iconSearch = "phosphor/magnifying-glass-bold.png"
RegionMapConstants.iconRuler = "phosphor/ruler.png"
RegionMapConstants.iconLog = "phosphor/scroll.png"
RegionMapConstants.iconPopOut = "drawsteel/Icons_Nav_MaxWindow.png"  -- the host's own pop out and pop in icons
RegionMapConstants.iconPopIn = "drawsteel/Icons_Nav_MinWindow.png"
RegionMapConstants.iconSettings = "phosphor/gear-six.png"
RegionMapConstants.iconPath = "phosphor/path.png"
