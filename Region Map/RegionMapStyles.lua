local mod = dmhub.GetModLoading()

--- Region Map's own style rules, merged over the active theme at the panel
--- root. Feature-specific selectors live here, never in DefaultStyles.lua.
--- Sizes that follow Font Size or zoom (pins, the Party, the side panel width)
--- are set per panel in code; everything else is here.
--- @class RegionMapStyles: GameType
--- @field new fun(o?: table): RegionMapStyles
RegionMapStyles = RegisterGameType("RegionMapStyles")
local Styles = RegionMapStyles
local C = RegionMapConstants

-- A floating chrome box over the map: theme surface with a quiet frame.
local function Chrome(selector, extra)
    local rule = {
        selectors = { selector },
        bgimage = true,
        bgcolor = "@bg",
        borderColor = "@border",
        borderWidth = 1,
        cornerRadius = 6,
    }
    for key, value in pairs(extra) do rule[key] = value end
    return rule
end

-- Warning and destructive text (Q26). @danger reads at only 3.4-4.0:1 as text on @bg in
-- the shipped themes, so the words take @fgStrong and the red goes on a bar at their left,
-- a mark that needs only 3:1 (the DefaultStyles.md multiselectChipRemove pattern).
local function Danger(selectors)
    return {
        selectors = selectors,
        color = "@fgStrong",
        bgimage = true,
        bgcolor = "clear",
        border = { x1 = 3, x2 = 0, y1 = 0, y2 = 0 },
        borderColor = "@danger",
        lpad = 8,
        borderBox = true,
    }
end

-- One Soft fade strip, opaque at outer and clear at inner, easing out so the edge
-- of the art never shows as a line.
local function FadeEdge(selector, place, outer, inner)
    local rule = {
        selectors = { selector },
        gradient = gui.Gradient {
            point_a = outer,
            point_b = inner,
            stops = {
                { position = 0, color = core.Color { r = 1, g = 1, b = 1, a = 1 } },
                { position = 0.4, color = core.Color { r = 1, g = 1, b = 1, a = 0.45 } },
                { position = 1, color = core.Color { r = 1, g = 1, b = 1, a = 0 } },
            },
        },
    }
    for key, value in pairs(place) do rule[key] = value end
    return rule
end

-- Window frame: canvas, breadcrumb, toolbar, camera controls, status, banners, toast.
local function ShellStyles()
    return {
        {
            selectors = { "regionMapRoot" },
            width = "100%",
            height = "100%",
            minWidth = 0,
            minHeight = 0,
            flow = "none",
            bgimage = true,
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "regionMapCanvas" },
            width = "100%",
            height = "100%",
            minWidth = 0,
            minHeight = 0,
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "regionMapImage" },
            bgcolor = "white",
        },
        -- Soft fade strips: the canvas color, with the gradient giving only the alpha.
        -- Gradient points are in the strip's own 0..1 box, y = 0 at the bottom.
        {
            selectors = { "regionMapFadeEdge" },
            bgimage = true,
            bgcolor = "@bgAlt",
        },
        FadeEdge("regionMapFadeLeft", { halign = "left", height = "100%" }, { x = 0, y = 0.5 }, { x = 1, y = 0.5 }),
        FadeEdge("regionMapFadeRight", { halign = "right", height = "100%" }, { x = 1, y = 0.5 }, { x = 0, y = 0.5 }),
        FadeEdge("regionMapFadeTop", { valign = "top", width = "100%" }, { x = 0.5, y = 1 }, { x = 0.5, y = 0 }),
        FadeEdge("regionMapFadeBottom", { valign = "bottom", width = "100%" }, { x = 0.5, y = 0 }, { x = 0.5, y = 1 }),
        Chrome("regionMapBreadcrumb", {
            width = "auto",
            height = C.breadcrumbHeight,
            -- Reserve the full Director toolbar, including Import and the fullscreen controls.
            maxWidth = "100%-460",
            flow = "horizontal",
            halign = "left",
            valign = "top",
            lmargin = C.chromeInset,
            tmargin = C.chromeInset,
            hpad = 10,
            borderBox = true,
        }),
        {
            selectors = { "regionMapCrumb" },
            width = "auto",
            height = "auto",
            maxWidth = 220,
            valign = "center",
            fontSize = 14,
            color = "@fg",
            textWrap = false,
        },
        {
            selectors = { "regionMapCrumb", "hover" },
            color = "@fgStrong",
            transitionTime = 0.1,
        },
        {
            selectors = { "regionMapCrumb", "current" },
            color = "@fgStrong",
            bold = true,
        },
        {
            selectors = { "regionMapCrumbSep" },
            width = 10,
            height = 10,
            valign = "center",
            hmargin = 6,
            bgcolor = "@fgMuted",
        },
        Chrome("regionMapToolbar", {
            width = "auto",
            height = C.chromeBarHeight,
            flow = "horizontal",
            halign = "right",
            valign = "top",
            rmargin = C.chromeInset,
            tmargin = C.chromeInset,
            hpad = 3,
            borderBox = true,
        }),
        {
            selectors = { "regionMapIconButton" },
            width = 32,
            height = 32,
            halign = "left",
            valign = "center",
            hmargin = 1,
            bgcolor = "clear",
            cornerRadius = 4,
        },
        {
            selectors = { "regionMapIconButton", "hover" },
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = { "regionMapIconButton", "on" },
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "regionMapIconButton", "disabled" },
            opacity = 0.4,
        },
        {
            selectors = { "regionMapIconGlyph" },
            width = 18,
            height = 18,
            halign = "center",
            valign = "center",
            bgcolor = "@fg",
        },
        {
            selectors = { "regionMapIconGlyph", "parent:hover" },
            bgcolor = "@fgStrong",
        },
        {
            selectors = { "regionMapIconGlyph", "parent:on" },
            bgcolor = "@accent",
        },
        Chrome("regionMapCameraControls", {
            width = "auto",
            height = C.chromeBarHeight,
            flow = "horizontal",
            halign = "left",
            valign = "bottom",
            lmargin = C.chromeInset,
            bmargin = C.chromeInset,
            hpad = 3,
            borderBox = true,
            opacity = 1,
            transitionTime = 0.3,
        }),
        -- Faded, not hidden: about 3:1 against the map (R9).
        {
            selectors = { "regionMapCameraControls", "faded" },
            opacity = 0.55,
            transitionTime = 0.6,
        },
        Chrome("regionMapStatus", {
            width = "auto",
            height = "auto",
            maxWidth = 360,
            halign = "right",
            valign = "bottom",
            rmargin = 8,
            bmargin = 8,
            hpad = 10,
            vpad = 6,
            borderBox = true,
            fontSize = 13,
            color = "@fgStrong",
            textWrap = false,
        }),
        {
            selectors = { "regionMapStatus", "link" },
            color = "@accent",
        },
        {
            selectors = { "regionMapStatus", "link", "hover" },
            color = "@accentHover",
        },
        {
            selectors = { "regionMapBanners" },
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
            lmargin = 8,
            tmargin = 48,
        },
        Chrome("regionMapBanner", {
            width = "auto",
            height = "auto",
            maxWidth = 460,
            halign = "left",
            bmargin = 4,
            hpad = 10,
            vpad = 5,
            borderBox = true,
            borderColor = "@accent",
            fontSize = 13,
            color = "@fgStrong",
            textWrap = true,
        }),
        -- Confirm dialog: a dimmed layer over this window only, so the rest of the app stays usable.
        {
            selectors = { "regionMapConfirmLayer" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "#000000aa",
        },
        Chrome("regionMapConfirm", {
            width = 420,
            maxWidth = "90%",
            height = "auto",
            halign = "center",
            valign = "center",
            flow = "vertical",
            pad = 20,
            borderBox = true,
            borderColor = "@accent",
        }),
        {
            selectors = { "regionMapConfirmTitle" },
            width = "100%",
            height = "auto",
            fontSize = 18,
            bold = true,
            color = "@fgStrong",
            textAlignment = "center",
            textWrap = true,
        },
        {
            selectors = { "regionMapConfirmBody" },
            width = "100%",
            height = "auto",
            tmargin = 10,
            fontSize = 14,
            color = "@fg",
            textAlignment = "center",
            textWrap = true,
        },
        {
            selectors = { "regionMapConfirm", "regionMapImportCard" },
            width = C.importCardWidth,
            height = C.importCardHeight,
            -- Percentage caps apply to content bounds, so reserve the card's padding.
            maxWidth = "90%-40",
            maxHeight = "90%-40",
        },
        {
            selectors = { "regionMapConfirm", "regionMapImportCard", "importNarrow" },
            pad = 8,
            borderBox = true,
            maxWidth = "90%-16",
            maxHeight = "90%-16",
        },
        {
            selectors = { "regionMapImportEditBody" },
            width = "100%-16",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "top",
        },
        {
            selectors = { "regionMapImportScroll" },
            width = "100%",
            height = "100% available",
            minHeight = 0,
            tmargin = 10,
        },
        {
            selectors = { "regionMapImportColumns" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",
        },
        {
            selectors = { "regionMapImportColumns", "importNarrow" },
            flow = "vertical",
        },
        {
            selectors = { "regionMapImportEditColumn" },
            width = "60%-12",
            height = "auto",
            flow = "vertical",
            valign = "top",
            rmargin = 12,
        },
        {
            selectors = { "regionMapImportHelpColumn" },
            width = "40%",
            height = "auto",
            flow = "vertical",
            valign = "top",
        },
        {
            selectors = { "regionMapImportEditColumn", "importNarrow" },
            width = "100%",
            rmargin = 0,
        },
        {
            selectors = { "regionMapImportHelpColumn", "importNarrow" },
            width = "100%",
            tmargin = 12,
        },
        {
            selectors = { "regionMapTextArea", "regionMapImportEditor" },
            height = 320,
            tmargin = 6,
        },
        {
            selectors = { "regionMapTextArea", "regionMapImportEditor", "importNarrow" },
            height = 240,
        },
        {
            selectors = { "regionMapImportTarget" },
            textAlignment = "center",
            tmargin = 4,
            color = "@fgMuted",
        },
        {
            selectors = { "regionMapImportCounter" },
            tmargin = 6,
            color = "@fgMuted",
        },
        {
            selectors = { "regionMapImportContract" },
            width = "100%",
            height = 320,
            tmargin = 6,
            pad = 8,
        },
        {
            selectors = { "regionMapImportContract", "importNarrow" },
            height = 240,
        },
        {
            selectors = { "regionMapImportContractText" },
            width = "auto",
            minWidth = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            fontSize = 12,
            textWrap = false,
            color = "@fg",
        },
        Danger({ "regionMapImportError" }),
        {
            selectors = { "regionMapImportError" },
            tmargin = 8,
        },
        {
            selectors = { "regionMapImportActions" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 10,
        },
        {
            selectors = { "regionMapImportActions", "importNarrow" },
            tmargin = 4,
        },
        {
            selectors = { "regionMapButton", "parent:regionMapImportActions" },
            width = "auto",
            minWidth = 80,
            maxWidth = "100%",
            height = "auto",
            minHeight = 30,
            hpad = 12,
            vpad = 6,
            borderBox = true,
            rmargin = 8,
            bmargin = 4,
            textWrap = true,
        },
        {
            selectors = { "regionMapImportLines" },
            width = "100%-16",               -- clears the scrollbar when the list scrolls
            halign = "left",
            height = "auto",
            flow = "vertical",
            valign = "top",                  -- a list taller than the scroll box would otherwise center in it
        },
        {
            selectors = { "regionMapImportLine" },
            width = "100%",
            height = "auto",
            fontSize = 14,
            color = "@fg",
            textWrap = true,
        },
        {
            selectors = { "regionMapImportLine", "lead" },
            fontSize = 15,
            color = "@fgStrong",
        },
        {
            selectors = { "regionMapImportLine", "heading" },
            tmargin = 10,
            bold = true,
        },
        {
            selectors = { "regionMapImportLine", "item" },
            fontSize = 13,
            lmargin = 12,
            width = "100%-12",
            tmargin = 2,
        },
        {
            selectors = { "regionMapImportLine", "note" },
            tmargin = 12,
            fontSize = 13,
            color = "@fgMuted",
        },
        {
            selectors = { "regionMapConfirmButtons" },
            width = "auto",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            tmargin = 18,
        },
        {
            selectors = { "regionMapButton", "parent:regionMapConfirmButtons" },
            hmargin = 6,
        },
        Chrome("regionMapToast", {
            width = "auto",
            height = "auto",
            minHeight = 38,
            maxWidth = "80%",
            flow = "horizontal",
            halign = "center",
            valign = "bottom",
            bmargin = C.belowChromeBar,
            hpad = 12,
            vpad = 4,
            borderBox = true,
            borderColor = "@fgMuted",
        }),
        {
            selectors = { "regionMapToastText" },
            width = "auto",
            height = "auto",
            maxWidth = 420,
            valign = "center",
            fontSize = 14,
            color = "@fgStrong",
            textWrap = true,
        },
        {
            selectors = { "regionMapToastButton" },
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 14,
            fontSize = 14,
            bold = true,
            color = "@accent",
        },
        {
            selectors = { "regionMapToastButton", "hover" },
            color = "@accentHover",
        },
    }
end

-- Pins and the Party. Names always sit on a halo (text outline) or a plate (R9).
local function PinStyles()
    return {
        -- A clear background makes the whole hit area clickable; a panel with
        -- no image receives no pointer events.
        {
            selectors = { "regionMapPin" },
            flow = "none",
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = { "regionMapPin", "hiddenPin" },
            opacity = 0.55,
        },
        -- Pins and the Party while their map image is still loading.
        {
            selectors = { "regionMapWaiting" },
            opacity = 0,
            priority = 10,
        },
        {
            selectors = { "regionMapPinDisc" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@fgStrong",
            borderWidth = 2,
        },
        {
            selectors = { "regionMapPinDisc", "parent:hover" },
            borderColor = "@accent",
        },
        {
            selectors = { "regionMapPinDisc", "parent:selected" },
            borderColor = "@accent",
            borderWidth = 3,
        },
        {
            selectors = { "regionMapPinDisc", "parent:snapTarget" },
            bgcolor = "@accent",
            borderColor = "@fgStrong",
            borderWidth = 3,
        },
        {
            selectors = { "regionMapPinGlyph" },
            width = "62%",
            height = "62%",
            halign = "center",
            valign = "center",
            bgcolor = "@fgStrong",
        },
        -- A library image keeps its own colors.
        {
            selectors = { "regionMapPinGlyph", "image" },
            width = "80%",
            height = "80%",
            bgcolor = "white",
        },
        {
            selectors = { "regionMapPinName" },
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "top",
            color = "@fgStrong",
            fontFace = "@label",
            bold = true,
            textAlignment = "center",
            textWrap = false,
            -- Outline width is a 0..1 fraction of the glyph; larger values erode the text.
            textOutlineWidth = 0.3,
            textOutlineColor = "@bg",
        },
        {
            selectors = { "regionMapPinName", "plate" },
            valign = "center",
            hpad = 7,
            vpad = 2,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 4,
            textOutlineWidth = 0,
        },
        {
            selectors = { "regionMapPinName", "plate", "parent:hover" },
            borderColor = "@accent",
        },
        {
            selectors = { "regionMapPinName", "plate", "parent:selected" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "regionMapPinName", "plate", "parent:snapTarget" },
            borderColor = "@accent",
            borderWidth = 3,
        },
        {
            selectors = { "regionMapPinBadge" },
            width = 14,
            height = 14,
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@fgStrong",
            borderWidth = 1,
            cornerRadius = 7,
        },
        {
            selectors = { "regionMapPinBadgeGlyph" },
            width = "72%",
            height = "72%",
            halign = "center",
            valign = "center",
            bgcolor = "@fgStrong",
        },
        {
            selectors = { "regionMapParty" },
            flow = "none",
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = { "regionMapPartyDisc" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "@accent",
            borderColor = "@fgStrong",
            borderWidth = 3,
        },
        {
            selectors = { "regionMapPartyDisc", "parent:hover" },
            borderColor = "@accentHover",
        },
        {
            selectors = { "regionMapPartyGlyph" },
            width = "60%",
            height = "60%",
            halign = "center",
            valign = "center",
            bgcolor = "@bg",
        },
        {
            selectors = { "regionMapPartyGlyph", "image" },
            width = "100%",
            height = "100%",
            bgcolor = "white",
        },
        {
            selectors = { "regionMapPartyName" },
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "top",
            hpad = 6,
            vpad = 1,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@accent",
            borderWidth = 1,
            cornerRadius = 4,
            color = "@fgStrong",
            bold = true,
            fontSize = 13,
            textWrap = false,
        },
    }
end

-- The side panel (STYLE_GUIDE section headers and rows).
local function SidePanelStyles()
    return {
        {
            selectors = { "regionMapSide" },
            -- Starts under the toolbar, which stays usable while the panel is open.
            height = "100%-" .. C.belowChromeBar,
            tmargin = C.belowChromeBar,
            halign = "right",
            valign = "top",
            flow = "vertical",
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@border",
            borderWidth = 1,
        },
        {
            selectors = { "regionMapSideScroll" },
            width = "100%",
            height = "100%",
            hpad = 14,
            vpad = 12,
            borderBox = true,
        },
        {
            selectors = { "regionMapSideBody" },
            width = "100%",
            height = "auto",
            valign = "top",
            flow = "vertical",
        },
        {
            selectors = { "regionMapSideHeader" },
            width = "100%",
            height = "auto",
            minHeight = 32,
            flow = "horizontal",
        },
        {
            selectors = { "regionMapSideIcon" },
            halign = "left",
            width = 22,
            height = 22,
            valign = "center",
            rmargin = 8,
            bgcolor = "@fgStrong",
        },
        {
            selectors = { "regionMapSideIcon", "image" },
            bgcolor = "white",
        },
        {
            selectors = { "regionMapSideTitle" },
            -- Room for the icon and the close button; "available" widths on
            -- wrapping labels measure too tall.
            width = "100%-70",
            height = "auto",
            valign = "center",
            fontSize = 18,
            bold = true,
            color = "@fgStrong",
            textWrap = true,
        },
        {
            selectors = { "regionMapSideRow" },
            width = "100%",
            height = "auto",
            minHeight = 26,
            flow = "horizontal",
            tmargin = 4,
        },
        {
            selectors = { "regionMapMeta" },
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = 12,
            color = "@fgMuted",
            textWrap = true,
        },
        {
            selectors = { "regionMapBody" },
            width = "100%",
            height = "auto",
            tmargin = 8,
            fontSize = 14,
            color = "@fg",
            textWrap = true,
        },
        {
            selectors = { "regionMapLink" },
            halign = "left",
            width = "auto",
            height = "auto",
            tmargin = 6,
            fontSize = 14,
            color = "@accent",
        },
        {
            selectors = { "regionMapLink", "hover" },
            color = "@accentHover",
        },
        {
            selectors = { "regionMapRule" },
            width = "100%",
            height = 1,
            vmargin = 10,
            bgimage = true,
            bgcolor = "@border",
            opacity = 0.35,
        },
        {
            selectors = { "regionMapButtonRow" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 6,
        },
        {
            selectors = { "regionMapButton" },
            halign = "left",
            width = "auto",
            minWidth = 84,
            height = 28,
            hpad = 10,
            borderBox = true,
            rmargin = 6,
            bmargin = 6,
            priority = 6,
        },
        {
            selectors = { "regionMapSectionHeader" },
            width = "100%",
            height = 28,
            flow = "horizontal",
        },
        {
            selectors = { "regionMapSectionLabel" },
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 4,
            fontSize = 14,
            bold = true,
            color = "@fg",
        },
        {
            selectors = { "regionMapSectionLabel", "parent:hover" },
            color = "@fgStrong",
        },
        {
            selectors = { "regionMapFormLabel" },
            width = "100%",
            height = "auto",
            tmargin = 10,
            bmargin = 3,
            fontSize = 12,
            color = "@fgMuted",
        },
        {
            selectors = { "regionMapInput" },
            width = "100%",
            height = 30,
            -- The theme's input padding must stay inside the 100%.
            borderBox = true,
        },
        {
            selectors = { "regionMapTextArea" },
            -- The theme's input rule adds hpad 10 per side outside the width, and a
            -- TextEditor keeps it despite borderBox (measured live), so 20 less.
            width = "100%-20",
            height = 96,
        },
        {
            selectors = { "regionMapSegments" },
            width = "100%",
            height = 28,
            flow = "horizontal",
        },
        {
            selectors = { "regionMapSegment" },
            height = "100%",
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@border",
            borderWidth = 1,
            fontSize = 13,
            color = "@fg",
            textAlignment = "center",
        },
        {
            selectors = { "regionMapSegment", "hover" },
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "regionMapSegment", "selected" },
            bgcolor = "@bgInverse",
            color = "@fgInverse",
            bold = true,
        },
        {
            selectors = { "regionMapStateLine" },
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            fontSize = 12,
            color = "@fgMuted",
        },
        Danger({ "regionMapStateLine", "danger" }),
        {
            selectors = { "regionMapIconGrid" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 4,
        },
        {
            selectors = { "regionMapIconChoice" },
            width = 36,
            height = 36,
            rmargin = 4,
            bmargin = 4,
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 4,
        },
        {
            selectors = { "regionMapIconChoice", "hover" },
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "regionMapIconChoice", "selected" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        -- Rows follow STYLE_GUIDE.md "Row grammar": clear at rest, @bgAlt on hover.
        {
            selectors = { "regionMapRow" },
            width = "100%",
            height = 32,
            flow = "horizontal",
            hpad = 8,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = { "regionMapRow", "hover" },
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = { "regionMapRowName" },
            width = "100%",
            height = "auto",
            valign = "center",
            fontSize = 14,
            color = "@fg",
            textWrap = false,
        },
        {
            selectors = { "regionMapHint" },
            width = "100%",
            height = "auto",
            tmargin = 4,
            fontSize = 12,
            color = "@fgMuted",
            textWrap = true,
        },
    }
end

-- The Atlas gallery of top-level maps.
local function AtlasStyles()
    return {
        {
            selectors = { "regionMapAtlas" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "regionMapAtlasBody" },
            width = "100%",
            height = "auto",
            valign = "top",
            flow = "vertical",
            hpad = 16,
            vpad = 16,
            borderBox = true,
        },
        {
            selectors = { "regionMapAtlasGrid" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
        },
        Chrome("regionMapCard", {
            width = C.atlasCardWidth,
            height = C.atlasCardHeight,
            halign = "left",
            valign = "top",
            flow = "vertical",
            rmargin = 12,
            bmargin = 12,
            pad = 6,
            borderBox = true,
        }),
        {
            selectors = { "regionMapCard", "hover" },
            borderColor = "@accent",
            transitionTime = 0.1,
        },
        {
            selectors = { "regionMapCard", "notShared" },
            opacity = 0.75,
        },
        {
            selectors = { "regionMapCardThumb" },
            width = "100%",
            height = C.atlasThumbHeight,
            bgcolor = "white",
            cornerRadius = 4,
        },
        {
            selectors = { "regionMapCardName" },
            width = "100%",
            height = "auto",
            tmargin = 6,
            fontSize = 14,
            bold = true,
            color = "@fgStrong",
            textWrap = false,
        },
        Chrome("regionMapCardActions", {
            width = 34,
            height = 34,
            halign = "right",
            valign = "top",
            flow = "none",
            margin = 4,
        }),
        {
            selectors = { "regionMapCardMeta" },
            width = "100%",
            height = "auto",
            tmargin = 2,
            flow = "horizontal",
        },
        {
            selectors = { "regionMapCardText" },
            width = "auto",
            height = "auto",
            rmargin = 6,
            fontSize = 11,
            color = "@fgMuted",
            textWrap = false,
        },
        {
            selectors = { "regionMapChip" },
            width = "auto",
            height = "auto",
            rmargin = 4,
            hpad = 5,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bgAlt",
            cornerRadius = 3,
            fontSize = 11,
            color = "@fg",
        },
        Chrome("regionMapEmpty", {
            width = "90%",
            maxWidth = 460,
            height = "auto",
            halign = "center",
            valign = "center",
            bmargin = 16,
            flow = "vertical",
            pad = 18,
            borderBox = true,
        }),
        {
            selectors = { "regionMapEmptyTitle" },
            width = "100%",
            height = "auto",
            textAlignment = "center",
            fontSize = 16,
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "regionMapEmptyBody" },
            width = "100%",
            height = "auto",
            tmargin = 6,
            textAlignment = "center",
            fontSize = 14,
            color = "@fgMuted",
            textWrap = true,
        },
    }
end

-- M3 tools: the drawn route, the ruler, the popovers and the session log.
local function ToolStyles()
    return {
        {
            selectors = { "regionMapOverlay" },
            width = "100%",
            height = "100%",
            flow = "none",
        },
        {
            selectors = { "regionMapRouteDot" },
            width = C.routeDotSize,
            height = C.routeDotSize,
            bgimage = true,
            bgcolor = "@accent",
            -- A ring in the theme's background colour keeps the route readable where it runs
            -- along a path of the same colour (Default's accent is parchment, like Road).
            borderColor = "@bg",
            borderWidth = 1.5,
            cornerRadius = C.routeDotSize / 2,
            opacity = 0.85,
        },
        {
            selectors = { "regionMapRulerLine" },
            height = C.rulerWidth,
            bgimage = true,
            bgcolor = "@accent",
        },
        {
            selectors = { "regionMapRulerEnd" },
            width = C.rulerEndSize,
            height = C.rulerEndSize,
            bgimage = true,
            bgcolor = "@accent",
            borderColor = "@bg",
            borderWidth = 2,
            cornerRadius = C.rulerEndSize / 2,
        },
        Chrome("regionMapRulerLabel", {
            width = "auto",
            height = "auto",
            hpad = 8,
            vpad = 3,
            borderBox = true,
            borderColor = "@accent",
            fontSize = 13,
            bold = true,
            color = "@fgStrong",
            textWrap = false,
        }),
        Chrome("regionMapPopover", {
            width = C.popoverWidth,
            maxWidth = "100%-16",
            -- Sized to its content; the scroll inside it caps the height at the
            -- space between the toolbar and the bottom controls (RegionMapPopovers).
            height = "auto",
            halign = "right",
            valign = "top",
            rmargin = C.chromeInset,
            tmargin = C.belowChromeBar,
            flow = "vertical",
            borderColor = "@accent",
        }),
        {
            selectors = { "regionMapPopoverScroll" },
            width = "100%",
            height = "auto",
            hpad = 12,
            vpad = 10,
            borderBox = true,
        },
        {
            selectors = { "regionMapPopoverBody" },
            width = "100%",
            height = "auto",
            valign = "top",
            flow = "vertical",
        },
        {
            selectors = { "regionMapPopoverTitle" },
            width = "100%",
            height = "auto",
            bmargin = 4,
            fontSize = 16,
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "regionMapPopoverInput" },
            -- The theme's input padding lands outside the width on a gui.SearchInput, and
            -- borderBox does not take it back; 28 less fits the panel padding (measured live).
            width = "100%-28",
            height = 30,
            -- The search field's own hpad (room for the magnifier) must stay inside the 100%.
            borderBox = true,
        },
        {
            selectors = { "regionMapPopoverList" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 6,
        },
        {
            selectors = { "regionMapResult" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 8,
            vpad = 5,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 4,
        },
        {
            selectors = { "regionMapResult", "hover" },
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = { "regionMapResultPathRow" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 1,
        },
        {
            selectors = { "regionMapResultPath" },
            halign = "left",
            width = "auto",
            height = "auto",
            maxWidth = 140,
            valign = "center",
            fontSize = 11,
            color = "@fgMuted",
            textWrap = false,
        },
        {
            selectors = { "regionMapCrumbSep", "small" },
            halign = "left",
            width = 7,
            height = 7,
            hmargin = 4,
        },
        {
            selectors = { "regionMapCheck" },
            width = "100%",
            height = 26,
            tmargin = 6,
        },
        {
            selectors = { "regionMapNumber" },
            width = 120,
            halign = "left",
        },
        -- Border tiles in Settings: the pick shows as an accent frame and a bold name,
        -- so it never relies on color alone.
        {
            selectors = { "regionMapBorderTiles" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 2,
        },
        {
            selectors = { "regionMapBorderTile" },
            width = "25%",
            height = "auto",
            flow = "vertical",
            hpad = 3,
            vpad = 3,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 4,
        },
        {
            selectors = { "regionMapBorderTile", "available", "hover" },
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        -- Opacity does not pass to children, so a tile without art dims its parts.
        {
            selectors = { "regionMapBorderPreview", "parent:needsArt" },
            opacity = 0.35,
        },
        {
            selectors = { "regionMapBorderName", "parent:needsArt" },
            opacity = 0.6,
        },
        {
            selectors = { "regionMapBorderPreview" },
            width = "100%",
            height = 44,
            bgimage = true,
            bgcolor = "white",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 3,
        },
        {
            selectors = { "regionMapBorderPreview", "parent:selected" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "regionMapBorderName" },
            width = "100%",
            height = "auto",
            tmargin = 3,
            fontSize = 12,
            textAlignment = "center",
            color = "@fgMuted",
        },
        {
            selectors = { "regionMapBorderName", "parent:selected" },
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "regionMapSideTitle", "noIcon" },
            width = "100%-40",
        },
        {
            selectors = { "regionMapLogDay" },
            width = "100%",
            height = "auto",
            tmargin = 12,
            bmargin = 2,
            fontSize = 12,
            bold = true,
            color = "@fgMuted",
        },
        {
            selectors = { "regionMapLogEntry" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            bmargin = 6,
        },
        {
            selectors = { "regionMapLogText" },
            width = "100%-40",
            height = "auto",
            valign = "center",
            fontSize = 14,
            color = "@fgStrong",
            textWrap = true,
        },
        {
            selectors = { "regionMapLogText", "hover" },
            color = "@accent",
        },
        {
            selectors = { "regionMapLogNote" },
            width = "100%",
            height = "auto",
            tmargin = 3,
            lmargin = 8,
            fontSize = 13,
            italics = true,
            color = "@fg",
            textWrap = true,
        },
    }
end

-- V2.1 point crawl: the map kind choice, path lines, the path panel and path types in Settings.
local function PathStyles()
    return {
        -- The kind choice (A1), on the Atlas New map card and in the side panel.
        -- Both New map steps fit the standard card height, so that card keeps it.
        {
            selectors = { "regionMapModeChoice" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 4,
        },
        {
            selectors = { "regionMapModeButton" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            bmargin = 4,
            hpad = 6,
            vpad = 4,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 4,
        },
        {
            selectors = { "regionMapModeButton", "hover" },
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            transitionTime = 0.1,
        },
        {
            selectors = { "regionMapModeName" },
            width = "100%",
            height = "auto",
            fontSize = 13,
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "regionMapModeDesc" },
            width = "100%",
            height = "auto",
            fontSize = 12,
            color = "@fg",
            textWrap = true,
        },
        {
            selectors = { "regionMapModeNote" },
            width = "100%",
            height = "auto",
            fontSize = 11,
            color = "@fgMuted",
            textWrap = true,
        },
        {
            selectors = { "regionMapCardBack" },
            halign = "right",
            tmargin = 0,
            fontSize = 12,
        },
        {
            selectors = { "regionMapSideChip" },
            halign = "left",
            tmargin = 4,
        },
        -- The Atlas card's meta row is full, so the map kind sits on the thumbnail's corner.
        {
            selectors = { "regionMapThumbChip" },
            halign = "left",
            valign = "top",
            lmargin = 4,
            tmargin = 4,
        },
        -- Path lines: colours are set per piece in code; the halo follows the theme accent.
        {
            selectors = { "regionMapPathPiece" },
            bgimage = true,
        },
        {
            selectors = { "regionMapPathHalo" },
            bgimage = true,
            bgcolor = "@accent",
            opacity = 0.55,
        },
        {
            selectors = { "regionMapPathBadge" },
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@fgStrong",
            borderWidth = 1,
        },
        -- Bend handles (Q5): a light disc with a dark ring reads on light and dark art.
        {
            selectors = { "regionMapPathHandle" },
            bgimage = true,
            bgcolor = C.pathCasingLight,
            borderColor = C.pathCasingDark,
            borderWidth = 2,
        },
        {
            selectors = { "regionMapPathPlus" },
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@accent",
            borderWidth = 1,
        },
        {
            selectors = { "regionMapPathPlusGlyph" },
            width = "70%",
            height = "70%",
            halign = "center",
            valign = "center",
            bgcolor = "@accent",
        },
        Chrome("regionMapPathLabel", {
            width = "auto",
            height = "auto",
            hpad = 8,
            vpad = 2,
            borderBox = true,
            cornerRadius = 4,
            color = "@fgStrong",
            textWrap = false,
        }),
        -- The path panel's type chip: the line sample and the type name.
        {
            selectors = { "regionMapPathChip" },
            width = "auto",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            tmargin = 6,
            hpad = 6,
            vpad = 3,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bgAlt",
            cornerRadius = 3,
        },
        {
            selectors = { "regionMapPathSample" },
            valign = "center",
        },
        {
            selectors = { "regionMapChipText" },
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 6,
            fontSize = 13,
            color = "@fg",
        },
        {
            selectors = { "regionMapPathTime" },
            bold = true,
            color = "@fgStrong",
        },
        -- A Location's Paths rows wrap, so a one-way time fits; hidden paths end in the eye-slash.
        {
            selectors = { "regionMapPathRow" },
            height = "auto",
            vpad = 6,
        },
        {
            selectors = { "regionMapPathRowName" },
            width = "100%-22",
            halign = "left",
            textWrap = true,
        },
        {
            selectors = { "regionMapPathRowEye" },
            width = 16,
            height = 16,
            halign = "right",
            valign = "center",
            bgcolor = "@fgMuted",
        },
        -- Travel to rows (Q18): "{dest} by {path}" in body text, the time under it.
        {
            selectors = { "regionMapTravelText" },
            width = "100%-22",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "center",
        },
        {
            selectors = { "regionMapRowName", "parent:regionMapTravelText" },
            textWrap = true,
        },
        -- The stop card's swap button sits left under the time field.
        {
            selectors = { "regionMapButton", "regionMapStopSwap" },
            halign = "left",
            tmargin = 8,
        },
        -- The edit form's travel time: a short number field with its unit beside it.
        {
            selectors = { "regionMapTimeRow" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
        },
        {
            selectors = { "regionMapTimeInput" },
            width = 100,
            halign = "left",
        },
        {
            selectors = { "regionMapTimeUnit" },
            width = "auto",
            halign = "left",
            valign = "center",
            lmargin = 8,
        },
        Danger({ "regionMapHint", "danger" }),
        -- Path types in Settings: rows with the line sample, one editor open at a time.
        {
            selectors = { "regionMapTypeRow" },
            cornerRadius = 4,
        },
        {
            selectors = { "regionMapTypeRow", "selected" },
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "regionMapTypeName" },
            width = "100%-90",
            lmargin = 8,
        },
        -- The chosen type reads apart from a hovered one, which shares the row fill.
        {
            selectors = { "regionMapTypeName", "parent:selected" },
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "regionMapTypeEdit" },
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            fontSize = 13,
            color = "@accent",
        },
        {
            selectors = { "regionMapTypeEdit", "parent:hover" },
            color = "@accentHover",
        },
        {
            selectors = { "regionMapTypeEditor" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            bmargin = 6,
            hpad = 8,
            vpad = 6,
            borderBox = true,
            bgimage = true,
            bgcolor = "@bgAlt",
            cornerRadius = 4,
        },
        {
            selectors = { "regionMapSwatches" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
        },
        -- 24 px swatches (Q26); the pick shows a check and an accent ring, Ink a light ring.
        {
            selectors = { "regionMapSwatch" },
            width = 28,
            height = 28,
            rmargin = 6,
            flow = "none",
            bgimage = true,
            bgcolor = "clear",
            borderColor = "@border",
            borderWidth = 1,
            cornerRadius = 14,
        },
        {
            selectors = { "regionMapSwatch", "hover" },
            borderColor = "@fgStrong",
        },
        {
            selectors = { "regionMapSwatch", "selected" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "regionMapSwatchFill" },
            width = 24,
            height = 24,
            halign = "center",
            valign = "center",
            bgimage = true,
            cornerRadius = 12,
        },
        {
            selectors = { "regionMapSwatchFill", "parent:ink" },
            borderColor = "@fgStrong",
            borderWidth = 1,
        },
        {
            selectors = { "regionMapSwatchCheck" },
            width = 14,
            height = 14,
            halign = "center",
            valign = "center",
            bgcolor = C.pathCasingDark,
            opacity = 0,
        },
        {
            selectors = { "regionMapSwatchCheck", "parent:selected" },
            opacity = 1,
        },
        {
            selectors = { "regionMapSwatchCheck", "parent:ink" },
            bgcolor = C.pathCasingLight,
        },
        Danger({ "regionMapLink", "danger" }),
        {
            selectors = { "regionMapLink", "danger", "hover" },
            color = "@fg",
        },
    }
end

--- The complete rule list for MergeStyles.
--- @return table[]
function RegionMapStyles.Build()
    local result = {}
    for _, group in ipairs({ ShellStyles(), PinStyles(), SidePanelStyles(), AtlasStyles(), ToolStyles(), PathStyles() }) do
        for _, rule in ipairs(group) do result[#result + 1] = rule end
    end
    return result
end

--- Re-merge the rules whenever the color scheme changes.
--- @param element Panel the Region Map root
function RegionMapStyles.Subscribe(element)
    element.data.themeSubscription = ThemeEngine.OnThemeChanged(mod, function()
        if mod.unloaded or not element.valid then return end
        element.styles = ThemeEngine.MergeStyles(Styles.Build())
        element:UpdateStyle()
    end)
end

--- @param element Panel the Region Map root
function RegionMapStyles.Unsubscribe(element)
    if element.data.themeSubscription ~= nil then
        element.data.themeSubscription:Deregister()
        element.data.themeSubscription = nil
    end
end
