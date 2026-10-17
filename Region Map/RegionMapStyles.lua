local mod = dmhub.GetModLoading()

--- Shared controls and theme subscription for the map. Each component supplies
--- its own Styles() rules; Build merges them once at the shell root.
--- @class RegionMapStyles: GameType
--- @field new fun(o?: table): RegionMapStyles
RegionMapStyles = RegisterGameType("RegionMapStyles")
local Styles = RegionMapStyles
local C = RegionMapConstants

-- A floating chrome box over the map: theme surface with a quiet frame.
function RegionMapStyles.Chrome(selector, extra)
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
function RegionMapStyles.Danger(selectors)
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
function RegionMapStyles.FadeEdge(selector, place, outer, inner)
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


--- Component rules, resolved by the shell against the active theme.
--- @return table[]
function RegionMapStyles.Styles()
    return {
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
        {
            selectors = { "regionMapConfirmLayer" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "#000000aa",
        },
        RegionMapStyles.Chrome("regionMapConfirm", {
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
            color = "@fg",
            textAlignment = "center",
            textWrap = true,
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
            color = "@fgMuted",
            textWrap = true,
        },
        {
            selectors = { "regionMapBody" },
            width = "100%",
            height = "auto",
            tmargin = 8,
            color = "@fg",
            textWrap = true,
        },
        {
            selectors = { "regionMapLink" },
            halign = "left",
            width = "auto",
            height = "auto",
            tmargin = 6,
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
            color = "@fgMuted",
        },
        RegionMapStyles.Danger({ "regionMapStateLine", "danger" }),
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
            color = "@fg",
            textWrap = false,
        },
        {
            selectors = { "regionMapHint" },
            width = "100%",
            height = "auto",
            tmargin = 4,
            color = "@fgMuted",
            textWrap = true,
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
        {
            selectors = { "regionMapSideTitle", "noIcon" },
            width = "100%-40",
        },
        {
            selectors = { "regionMapSideChip" },
            halign = "left",
            tmargin = 4,
        },
        {
            selectors = { "regionMapThumbChip" },
            halign = "left",
            valign = "top",
            lmargin = 4,
            tmargin = 4,
        },
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
            color = "@fg",
        },
        {
            selectors = { "regionMapPathTime" },
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "regionMapRowName", "parent:regionMapTravelText" },
            textWrap = true,
        },
        {
            selectors = { "regionMapButton", "regionMapStopSwap" },
            halign = "left",
            tmargin = 8,
        },
        RegionMapStyles.Danger({ "regionMapHint", "danger" }),
        RegionMapStyles.Danger({ "regionMapLink", "danger" }),
        {
            selectors = { "regionMapLink", "danger", "hover" },
            color = "@fg",
        },
    }
end

--- @return table[]
function RegionMapStyles.Build()
    local result = {}
    for _, group in ipairs({
        RegionMapStyles.Styles(),
        RegionMapPanel.Styles(),
        RegionMapSession.HostStyles(),
        RegionMapCanvas.Styles(),
        RegionMapImport.Styles(),
        RegionMapArtwork.Styles(),
        RegionMapAtlas.Styles(),
        RegionMapCanvasTools.Styles(),
        RegionMapPopovers.Styles(),
        RegionMapLogPanel.Styles(),
        RegionMapPathLayer.Styles(),
        RegionMapPartyPanel.Styles(),
        RegionMapPathPanel.Styles(),
        RegionMapLabelLayer.Styles(),
        RegionMapSession.Styles(),
        RegionMapLabelPanel.Styles(),
    }) do
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
        element:FireEventTree("regionMapThemeChanged")
    end)
end

--- @param element Panel the Region Map root
function RegionMapStyles.Unsubscribe(element)
    if element.data.themeSubscription ~= nil then
        element.data.themeSubscription:Deregister()
        element.data.themeSubscription = nil
    end
end
