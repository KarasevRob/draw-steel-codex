--- Shared vocabulary for the Overland Map mod: identity, storage names, limits,
--- layout metrics and timings. Every other Overland Map file reads these instead
--- of repeating literals.
--- @class OverlandMapConstants: GameType
--- @field new fun(o?: table): OverlandMapConstants
OverlandMapConstants = RegisterGameType("OverlandMapConstants")

-- Identity
-- Keep the registration name equal to the window.title copy string.
OverlandMapConstants.panelName = "Overland Map"
OverlandMapConstants.panelIcon = "phosphor/map-trifold.png"

-- Fresh storage intentionally does not read development data from before this rewrite.
OverlandMapConstants.schemaVersion = 1                -- the state document's schema
OverlandMapConstants.locationTableName = "OverlandMapLocations"
OverlandMapConstants.labelTableName = "OverlandMapLabels"
OverlandMapConstants.labelTextLimit = 256
OverlandMapConstants.labelByteLimit = 1024
OverlandMapConstants.labelMinSize = 0.001
OverlandMapConstants.labelMaxSize = 0.25
OverlandMapConstants.labelDefaultSize = 0.03
OverlandMapConstants.labelHandleSize = 24
OverlandMapConstants.logTableName = "OverlandMapLogEntries"
OverlandMapConstants.detailsTableName = "OverlandMapLocationDetails"
OverlandMapConstants.notesTableName = "OverlandMapLocationDirectorNotes"
OverlandMapConstants.locationSchemaVersion = 1
OverlandMapConstants.logSchemaVersion = 1
OverlandMapConstants.detailsSchemaVersion = 1
OverlandMapConstants.notesSchemaVersion = 1
OverlandMapConstants.stateDocumentId = "overlandMapState"
OverlandMapConstants.preferencesSettingId = "overlandmap:preferences"

-- Limits
OverlandMapConstants.textLimit = 256                   -- Names, in Unicode characters (new writes and editors)
-- Stored names are read up to this many characters. Keep it fixed: reading checks it, so a
-- client with a lower cap would hide rows (and their subtrees) that a newer client wrote.
OverlandMapConstants.textReadLimit = 1024
OverlandMapConstants.descriptionLimit = 4000
OverlandMapConstants.crumbPreviewLimit = 300           -- description characters a breadcrumb tooltip shows
OverlandMapConstants.descriptionByteLimit = 16384
OverlandMapConstants.noteLimit = 8000
OverlandMapConstants.noteByteLimit = 32768
OverlandMapConstants.journalIdLimit = 512
OverlandMapConstants.maxRevision = 9007199254740991    -- largest integer a double holds exactly
OverlandMapConstants.maxDepth = 16                     -- deepest Location nesting; also stops cycle walks
OverlandMapConstants.logCap = 500                      -- newest session log entries kept per game (R15)
OverlandMapConstants.logRowsPerFrame = 40              -- log rows built per frame; a full log builds over several frames
OverlandMapConstants.undoDepth = 20                    -- undo entries kept per session

-- Allowed values, in the order the editors list them. OverlandMapRecords builds its checks
-- from these lists. The values are stored in rows, so never rename one.
OverlandMapConstants.pinStyles = { "iconName", "plate", "iconOnly" }
OverlandMapConstants.importances = { "major", "normal", "minor" }
OverlandMapConstants.visibilities = { "hidden", "revealed" }
OverlandMapConstants.scaleUnits = { "mi", "km" }

-- Map image size guidance (V2.1 J1, brief W5): a newly picked image narrower or wider
-- than this warns with a toast; nothing is blocked. Measured 2026-10-08.
OverlandMapConstants.imageMinWidth = 1500             -- narrower blurs as soon as it is zoomed in
OverlandMapConstants.imageRecommendedWidth = 4000     -- shown in the hint and the warnings
OverlandMapConstants.imageMaxWidth = 12000            -- wider loads slowly for players
OverlandMapConstants.artworkHeight = 160
OverlandMapConstants.artworkTimeout = 10

-- Map borders (V2.1 K1), in the order of the Settings tiles. A new map takes the
-- border the Director picked last, Soft fade before any pick (K5, K8).
OverlandMapConstants.borders = { "none", "fade", "torn", "frame" }
OverlandMapConstants.defaultBorder = "fade"
-- Library image ids of the border art (docs/BORDER_ART.md). While "" the tile is disabled.
OverlandMapConstants.borderTornMask = ""
OverlandMapConstants.borderFrameImage = ""
-- JSON import (V2.1 idea 9). Locations without a position are set out in a grid with
-- columns this far apart (share of the map's width) and rows closer, since a pin with its
-- name is wider than tall. Rows are created importBatch at a time, each batch waiting
-- for the server; a batch that has not answered in importWait seconds fails.
OverlandMapConstants.importSpacing = 0.11
OverlandMapConstants.importRowShare = 0.45            -- row gap / column gap, on screen
OverlandMapConstants.importBatch = 10
OverlandMapConstants.importWait = 20
OverlandMapConstants.importTextLimit = 100000
OverlandMapConstants.importPreviewLimit = 100
-- Leave encoding headroom: a native-limit truncation must still fail the character check.
OverlandMapConstants.importEditorLimit = 4 * (OverlandMapConstants.importTextLimit + 1)
OverlandMapConstants.importCardWidth = 900
OverlandMapConstants.importCardHeight = 640
OverlandMapConstants.importNarrowWidth = 760

-- The soft fade band: this share of the image's shorter side on screen, at most fadeMaxWidth px.
OverlandMapConstants.fadeShare = 0.06
OverlandMapConstants.fadeMaxWidth = 72

-- Point crawl (V2.1 7.2/7.3). A map's mode is set when it is made and never changes (A4).
OverlandMapConstants.modes = { "free", "pointcrawl" }
OverlandMapConstants.pathTableName = "OverlandMapPaths"   -- persisted; never rename
OverlandMapConstants.pathSchemaVersion = 1
OverlandMapConstants.pathBendLimit = 32
OverlandMapConstants.pathTypeIdLimit = 64
-- Travel times are stored in watches (4 hours); the unit setting changes only the display (C9).
OverlandMapConstants.watchesPerDay = 6
OverlandMapConstants.pathTimeMax = OverlandMapConstants.watchesPerDay * 999 -- watches; a typo guard, not a game rule
OverlandMapConstants.defaultTimeUnit = "days"
OverlandMapConstants.pathTimeUnits = { "days", "watches", "custom" }
OverlandMapConstants.pathBacks = { "same", "different", "none" } -- the other way: same time, its own time, not possible
-- Line looks (N1, Q3). Patterns and widths are drawn in screen pixels, the same at every zoom (Q2).
OverlandMapConstants.pathPatterns = { "solid", "dashed", "dotted", "double", "dashDot", "longDash" }
OverlandMapConstants.pathWidthOrder = { "thin", "normal", "thick" }
OverlandMapConstants.pathWidths = { thin = 2, normal = 3, thick = 4 }
-- The path colours are map ink, not UI chrome, so they stay the same in every theme.
OverlandMapConstants.pathColorOrder = { "parchment", "blue", "ochre", "violet", "rust", "ink" }
OverlandMapConstants.pathColors = {
    parchment = "#F2EDE1", blue = "#6FA8DC", ochre = "#C9A06A",
    violet = "#B48EAD", rust = "#D08770", ink = "#1A1A1E",
}
-- Casing under every line (Q1): dark under light colours, light under Ink.
OverlandMapConstants.pathCasingDark = "#141416"
OverlandMapConstants.pathCasingLight = OverlandMapConstants.pathColors.parchment
OverlandMapConstants.pathCasing = 1.5                  -- px each side
OverlandMapConstants.pathHalo = 4                      -- px each side of the casing, selected path (Q5)
OverlandMapConstants.pathBadgeSize = 16                -- eye-slash on hidden paths (Q12)
-- A hidden path's line fades to this; 0.6 keeps every colour at 3:1 or more against its
-- casing (measured). The eye-slash badge, not the fade, says "hidden".
OverlandMapConstants.pathHiddenOpacity = 0.6
-- Path labels (Q11). With Show names on, a label shows only where it fits: its line
-- on screen is at least labelFit of its width, and it clears pins and other labels.
-- Widths are estimated (charWidth em per character) so no frame waits on a measure.
OverlandMapConstants.pathLabelSize = 13
OverlandMapConstants.pathLabelCharWidth = 0.52
OverlandMapConstants.pathLabelPad = 8                  -- px each side; matches the style's hpad
OverlandMapConstants.pathLabelFit = 0.8
OverlandMapConstants.pathLabelGap = 4                  -- px kept clear around a label
-- Starter types (C4, N1, Q3): every pattern differs, so no two tell apart by colour alone.
OverlandMapConstants.starterPathTypes = {
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
OverlandMapConstants.pathPieceLimit = 2500
-- Path editing.
OverlandMapConstants.firstPathType = "road"            -- the first path of a game: Road, 1 day (Q8)
OverlandMapConstants.firstPathTime = OverlandMapConstants.watchesPerDay -- watches: 1 day
-- A second path between the same two pins bows out by this share of its length, per path (Q9).
OverlandMapConstants.pathParallelOffset = 0.12
OverlandMapConstants.pathHandleSize = 10               -- bend handle disc, px (Q5)
OverlandMapConstants.pathHandleHit = 24                -- its hit area, px
OverlandMapConstants.pathPlusSize = 14                 -- the "+" at a segment's middle that adds a bend

-- Curated pin icons (D5d): key -> Phosphor mask, tinted by style rules.
-- Verified live 2026-10-06 (every path loads a 256 px sprite).
OverlandMapConstants.pinIcons = {
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
OverlandMapConstants.pinIconOrder = {
    "city", "town", "castle", "tower", "temple", "tavern", "camp", "port",
    "bridge", "forest", "cave", "dungeon", "danger", "treasure", "quest", "poi",
}
OverlandMapConstants.defaultPinIcon = "poi"            -- drawn when a Location has no icon

-- Camera
OverlandMapConstants.minZoom = 1
OverlandMapConstants.maxZoom = 20
OverlandMapConstants.zoomWheelStep = 1.15
-- Wheel notches closer together than this are one zoom: the path and route lines
-- stretch meanwhile and are placed again once, when the wheel rests this long.
OverlandMapConstants.zoomSettleSeconds = 0.15
OverlandMapConstants.zoomButtonStep = 1.25
OverlandMapConstants.panFine = 16                      -- arrow keys pan the camera
OverlandMapConstants.panCoarse = 64                    -- with Shift held
OverlandMapConstants.canvasDragThreshold = 4           -- screen px before a press becomes a drag
OverlandMapConstants.openZoom = 4                      -- how far the camera zooms into a pin before its map opens
OverlandMapConstants.partyFocusZoom = 2                -- the status chip zooms in at least this far, so going to the Party always shows a move

-- Pins. Sizes are screen pixels at Font Size 100 and stay constant at every zoom.
OverlandMapConstants.pinDisc = { major = 36, normal = 28, minor = 24 }
OverlandMapConstants.pinNameSize = { major = 18, normal = 15, minor = 13 }
OverlandMapConstants.pinHitMin = 24
OverlandMapConstants.pinBadgeSize = 14                 -- hidden / has-a-map badges on a pin's corners
OverlandMapConstants.partySize = 40                    -- Party banner disc
OverlandMapConstants.partySnapRadius = 32              -- a dropped Party snaps to a pin this close
OverlandMapConstants.declutterZoom = { minor = 1.5, normal = 1.0 } -- below this zoom, names of that importance hide
OverlandMapConstants.routeDotSpacing = 14
OverlandMapConstants.routeDotSize = 5
-- Most route dots drawn at once (only the visible part is drawn); also the most points
-- one merged "traveling" log entry collects before a new entry starts.
OverlandMapConstants.routeDotLimit = 600
OverlandMapConstants.rulerWidth = 3                    -- ruler line thickness, screen px
OverlandMapConstants.rulerEndSize = 10                 -- ruler end dots

-- Popovers (Search, Settings, Map aids) under the toolbar
OverlandMapConstants.popoverWidth = 340
OverlandMapConstants.searchResultLimit = 30

-- Window layout
OverlandMapConstants.sidePanelWidth = 320
OverlandMapConstants.narrowWidth = 720                 -- below this the side panel takes the full width
OverlandMapConstants.atlasCardWidth = 200
OverlandMapConstants.atlasCardHeight = 168
OverlandMapConstants.atlasThumbHeight = 104            -- a card's image, and the New map card's image picker
-- The toolbar (top right) and camera controls (bottom left) sit chromeInset from the
-- window's edges; the side panel and popovers start below the toolbar, and toasts sit
-- above the camera controls, the same gap away.
OverlandMapConstants.chromeInset = 8
OverlandMapConstants.chromeBarHeight = 38
OverlandMapConstants.breadcrumbHeight = 34
OverlandMapConstants.belowChromeBar = OverlandMapConstants.chromeInset * 2 + OverlandMapConstants.chromeBarHeight

-- Timings (seconds)
-- Active: pointer over the canvas, a drag, or a transition. 0.001 means every frame;
-- a fixed 0.02 (50 Hz) skipped frames on 60 Hz+ screens, so pans and zooms judder.
OverlandMapConstants.canvasThinkActive = 0.001
OverlandMapConstants.canvasThinkIdle = 0.25
OverlandMapConstants.hostThinkHover = 0.03             -- a hovered in-app window polls for clicks that should raise it
OverlandMapConstants.rootThink = 0.1
OverlandMapConstants.refreshDelay = 0.05               -- coalesces bursts of table/document changes
OverlandMapConstants.cameraSaveDelay = 0.5
OverlandMapConstants.saveRecheckDelay = 0.5            -- an image attachment still saving checks its upload again after this
OverlandMapConstants.undoTick = 0.25                   -- the undo toast's timer, and polls while an undo waits for its writes
OverlandMapConstants.undoSettleSeconds = 5             -- an undo gives up waiting for its writes after this
OverlandMapConstants.presentTtl = 10
OverlandMapConstants.autosaveDelay = 1.5               -- side panel saves after this long without typing
OverlandMapConstants.busyRetryDelay = 0.3              -- a write waits this long while a save of the same row is in flight
OverlandMapConstants.busyRetries = 10                  -- most retries for one-off writes (save queues retry until the row is free)
OverlandMapConstants.undoMergeSeconds = 5             -- saves of one label or map's text this close together share one Undo
OverlandMapConstants.afterLayoutDelay = 0.05           -- a panel just shown has laid out: focus its input, scroll it
OverlandMapConstants.toastSeconds = 10                 -- paused while hovered (R9)
OverlandMapConstants.transitionSeconds = 0.3           -- zoom into a pin, then crossfade to its map
-- The Party banner walking a leg or stop along its path's line (point crawl maps).
OverlandMapConstants.partyMoveSpeed = 450              -- screen px per second at the current zoom
OverlandMapConstants.partyMoveMinSeconds = 0.6         -- a short hop still reads as a move
OverlandMapConstants.partyMoveMaxSeconds = 2           -- a leg across the whole map never drags on
OverlandMapConstants.partyMoveEdge = 0.15              -- share of the walk spent stepping off / onto a pin's side
OverlandMapConstants.partyMoveFresh = 5                -- only legs logged this recently play; older ones (late join, reopen) do not
OverlandMapConstants.controlsFadeSeconds = 2           -- camera controls fade after this long without pointer movement

-- Native and in-app windows share resize bounds but keep separate placement.
OverlandMapConstants.windowWidth = 1000
OverlandMapConstants.windowHeight = 800
OverlandMapConstants.windowMinWidth = 720
OverlandMapConstants.windowMinHeight = 480
OverlandMapConstants.windowMaxWidth = 4096
OverlandMapConstants.windowMaxHeight = 2160
OverlandMapConstants.popoutHeight = 720
OverlandMapConstants.panelWidth = 900
OverlandMapConstants.panelHeight = 600
OverlandMapConstants.panelTitleHeight = 36
OverlandMapConstants.panelMargin = 12
-- The icon rails' measures (DocumentSystem.lua ICON_RAIL_*, IconRailTop), in layer
-- units before Font Size zoom: the fullscreen map sits between the rails.
OverlandMapConstants.railButton = 40
OverlandMapConstants.railInset = 12
OverlandMapConstants.railGap = 8
OverlandMapConstants.railStopGap = 12
OverlandMapConstants.railTopMin = 64

-- Icons (Phosphor masks, tinted by style rules). Verified live 2026-10-06.
OverlandMapConstants.iconParty = "phosphor/users-three.png"
OverlandMapConstants.iconAdd = "phosphor/plus-bold.png"
OverlandMapConstants.iconImport = "phosphor/file-arrow-up.png"
OverlandMapConstants.iconLocked = "phosphor/lock-simple.png"
OverlandMapConstants.iconUnlocked = "phosphor/lock-simple-open.png"
OverlandMapConstants.iconShow = "phosphor/presentation.png"
OverlandMapConstants.iconViewAs = "phosphor/user-focus.png"
OverlandMapConstants.iconFit = "phosphor/arrows-out-simple-fill.png"
OverlandMapConstants.iconZoomIn = "phosphor/magnifying-glass-plus-bold.png"
OverlandMapConstants.iconZoomOut = "phosphor/magnifying-glass-minus-bold.png"
OverlandMapConstants.iconNames = "phosphor/text-aa.png"
OverlandMapConstants.iconCrumb = "phosphor/caret-right-fill.png"
OverlandMapConstants.iconCaret = "phosphor/caret-down-fill.png"
OverlandMapConstants.iconClose = "phosphor/x-bold.png"
OverlandMapConstants.iconMore = "phosphor/dots-three-bold.png"
OverlandMapConstants.iconEye = "phosphor/eye.png"
OverlandMapConstants.iconEyeSlash = "phosphor/eye-slash.png"
OverlandMapConstants.iconMap = "phosphor/map-trifold.png"
OverlandMapConstants.iconSearch = "phosphor/magnifying-glass-bold.png"
OverlandMapConstants.iconRuler = "phosphor/ruler.png"
OverlandMapConstants.iconLog = "phosphor/scroll.png"
OverlandMapConstants.iconPopOut = "drawsteel/Icons_Nav_MaxWindow.png"  -- the host's own pop out and pop in icons
OverlandMapConstants.iconPopIn = "drawsteel/Icons_Nav_MinWindow.png"
OverlandMapConstants.iconWindow = "phosphor/corners-in.png"
OverlandMapConstants.iconFullscreen = "phosphor/corners-out.png"
OverlandMapConstants.iconSettings = "phosphor/gear-six.png"
OverlandMapConstants.iconPath = "phosphor/path.png"
