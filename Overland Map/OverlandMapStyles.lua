local mod = dmhub.GetModLoading()

--- Shared style helpers and theme subscription for the map. Each component supplies
--- its own Styles() rules; Build merges them once at the shell root.
--- @class OverlandMapStyles: GameType
--- @field new fun(o?: table): OverlandMapStyles
OverlandMapStyles = RegisterGameType("OverlandMapStyles")
local Styles = OverlandMapStyles
local C = OverlandMapConstants

-- A floating chrome box over the map: theme surface with a quiet frame.
function OverlandMapStyles.Chrome(selector, extra)
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
function OverlandMapStyles.Danger(selectors)
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
function OverlandMapStyles.FadeEdge(selector, place, outer, inner)
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
function OverlandMapStyles.Styles()
    return {
        {
            selectors = { "overlandMapIconButton" },
            width = 32,
            height = 32,
            halign = "left",
            valign = "center",
            hmargin = 1,
            bgcolor = "clear",
            cornerRadius = 4,
        },
        {
            selectors = { "overlandMapIconButton", "hover" },
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = { "overlandMapIconButton", "on" },
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "overlandMapIconButton", "disabled" },
            opacity = 0.4,
        },
        {
            selectors = { "overlandMapIconGlyph" },
            width = 18,
            height = 18,
            halign = "center",
            valign = "center",
            bgcolor = "@fg",
        },
        {
            selectors = { "overlandMapIconGlyph", "parent:hover" },
            bgcolor = "@fgStrong",
        },
        {
            selectors = { "overlandMapIconGlyph", "parent:on" },
            bgcolor = "@accent",
        },
        {
            selectors = { "overlandMapConfirmLayer" },
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "#000000aa",
        },
        OverlandMapStyles.Chrome("overlandMapConfirm", {
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
            selectors = { "overlandMapConfirmTitle" },
            width = "100%",
            height = "auto",
            bold = true,
            color = "@fgStrong",
            textAlignment = "center",
            textWrap = true,
        },
        {
            selectors = { "overlandMapConfirmBody" },
            width = "100%",
            height = "auto",
            tmargin = 10,
            color = "@fg",
            textAlignment = "center",
            textWrap = true,
        },
        {
            selectors = { "overlandMapConfirmButtons" },
            width = "auto",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            tmargin = 18,
        },
        {
            selectors = { "overlandMapButton", "parent:overlandMapConfirmButtons" },
            hmargin = 6,
        },
        {
            selectors = { "overlandMapSide" },
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
            selectors = { "overlandMapSideScroll" },
            width = "100%",
            height = "100%",
            hpad = 14,
            vpad = 12,
            borderBox = true,
        },
        {
            selectors = { "overlandMapSideBody" },
            width = "100%",
            height = "auto",
            valign = "top",
            flow = "vertical",
        },
        {
            selectors = { "overlandMapSideHeader" },
            width = "100%",
            height = "auto",
            minHeight = 32,
            flow = "horizontal",
        },
        {
            selectors = { "overlandMapSideIcon" },
            halign = "left",
            width = 22,
            height = 22,
            valign = "center",
            rmargin = 8,
            bgcolor = "@fgStrong",
        },
        {
            selectors = { "overlandMapSideIcon", "image" },
            bgcolor = "white",
        },
        {
            selectors = { "overlandMapSideTitle" },
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
            selectors = { "overlandMapSideRow" },
            width = "100%",
            height = "auto",
            minHeight = 26,
            flow = "horizontal",
            tmargin = 4,
        },
        {
            selectors = { "overlandMapMeta" },
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            color = "@fgMuted",
            textWrap = true,
        },
        {
            selectors = { "overlandMapBody" },
            width = "100%",
            height = "auto",
            tmargin = 8,
            color = "@fg",
            textWrap = true,
        },
        {
            selectors = { "overlandMapLink" },
            halign = "left",
            width = "auto",
            height = "auto",
            tmargin = 6,
            color = "@accent",
        },
        {
            selectors = { "overlandMapLink", "hover" },
            color = "@accentHover",
        },
        {
            selectors = { "overlandMapRule" },
            width = "100%",
            height = 1,
            vmargin = 10,
            bgimage = true,
            bgcolor = "@border",
            opacity = 0.35,
        },
        {
            selectors = { "overlandMapButtonRow" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 6,
        },
        {
            selectors = { "overlandMapButton" },
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
            selectors = { "overlandMapSectionHeader" },
            width = "100%",
            height = 28,
            flow = "horizontal",
        },
        {
            selectors = { "overlandMapSectionLabel" },
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 4,
            bold = true,
            color = "@fg",
        },
        {
            selectors = { "overlandMapSectionLabel", "parent:hover" },
            color = "@fgStrong",
        },
        {
            selectors = { "overlandMapFormLabel" },
            width = "100%",
            height = "auto",
            tmargin = 10,
            bmargin = 3,
            color = "@fgMuted",
        },
        {
            selectors = { "overlandMapInput" },
            width = "100%",
            height = 30,
            -- The theme's input padding must stay inside the 100%.
            borderBox = true,
        },
        {
            selectors = { "overlandMapTextArea" },
            -- The theme's input rule adds hpad 10 per side outside the width, and a
            -- TextEditor keeps it despite borderBox (measured live), so 20 less.
            width = "100%-20",
            height = 96,
        },
        {
            selectors = { "overlandMapSegments" },
            width = "100%",
            height = 28,
            flow = "horizontal",
        },
        {
            selectors = { "overlandMapSegment" },
            height = "100%",
            bgimage = true,
            bgcolor = "@bg",
            borderColor = "@border",
            borderWidth = 1,
            color = "@fg",
            textAlignment = "center",
        },
        {
            selectors = { "overlandMapSegment", "hover" },
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "overlandMapSegment", "selected" },
            bgcolor = "@bgInverse",
            color = "@fgInverse",
            bold = true,
        },
        {
            selectors = { "overlandMapStateLine" },
            halign = "left",
            width = "auto",
            height = "auto",
            valign = "center",
            color = "@fgMuted",
        },
        OverlandMapStyles.Danger({ "overlandMapStateLine", "danger" }),
        {
            selectors = { "overlandMapIconGrid" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            tmargin = 4,
        },
        {
            selectors = { "overlandMapIconChoice" },
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
            selectors = { "overlandMapIconChoice", "hover" },
            bgcolor = "@bgAlt",
        },
        {
            selectors = { "overlandMapIconChoice", "selected" },
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = { "overlandMapRow" },
            width = "100%",
            height = 32,
            flow = "horizontal",
            hpad = 8,
            borderBox = true,
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = { "overlandMapRow", "hover" },
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = { "overlandMapRowIcon" },
            width = 16,
            height = 16,
            valign = "center",
            rmargin = 6,
            bgcolor = "@fgMuted",
        },
        {
            selectors = { "overlandMapRowName" },
            -- "available" leaves room for an optional leading icon.
            width = "100% available",
            height = "auto",
            valign = "center",
            color = "@fg",
            textWrap = false,
        },
        {
            selectors = { "overlandMapHint" },
            width = "100%",
            height = "auto",
            tmargin = 4,
            color = "@fgMuted",
            textWrap = true,
        },
        {
            selectors = { "overlandMapCrumbSep", "small" },
            halign = "left",
            width = 7,
            height = 7,
            hmargin = 4,
        },
        {
            selectors = { "overlandMapCheck" },
            width = "100%",
            height = 26,
            tmargin = 6,
        },
        {
            selectors = { "overlandMapNumber" },
            width = 120,
            halign = "left",
        },
        {
            selectors = { "overlandMapSideTitle", "noIcon" },
            width = "100%-40",
        },
        {
            selectors = { "overlandMapSideChip" },
            halign = "left",
            tmargin = 4,
        },
        {
            selectors = { "overlandMapThumbChip" },
            halign = "left",
            valign = "top",
            lmargin = 4,
            tmargin = 4,
        },
        {
            selectors = { "overlandMapPathChip" },
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
            selectors = { "overlandMapPathSample" },
            valign = "center",
        },
        {
            selectors = { "overlandMapChipText" },
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 6,
            color = "@fg",
        },
        {
            selectors = { "overlandMapPathTime" },
            bold = true,
            color = "@fgStrong",
        },
        {
            selectors = { "overlandMapRowName", "parent:overlandMapTravelText" },
            textWrap = true,
        },
        {
            selectors = { "overlandMapButton", "overlandMapStopSwap" },
            halign = "left",
            tmargin = 8,
        },
        OverlandMapStyles.Danger({ "overlandMapHint", "danger" }),
        OverlandMapStyles.Danger({ "overlandMapLink", "danger" }),
        {
            selectors = { "overlandMapLink", "danger", "hover" },
            color = "@fg",
        },
    }
end

--- @return table[]
function OverlandMapStyles.Build()
    local result = {}
    for _, group in ipairs({
        OverlandMapStyles.Styles(),
        OverlandMapPanel.Styles(),
        OverlandMapControls.HostStyles(),
        OverlandMapCanvas.Styles(),
        OverlandMapImport.Styles(),
        OverlandMapArtwork.Styles(),
        OverlandMapAtlas.Styles(),
        OverlandMapCanvasTools.Styles(),
        OverlandMapPopovers.Styles(),
        OverlandMapQuickAdd.Styles(),
        OverlandMapLogPanel.Styles(),
        OverlandMapPathLayer.Styles(),
        OverlandMapPartyPanel.Styles(),
        OverlandMapPathPanel.Styles(),
        OverlandMapLabelLayer.Styles(),
        OverlandMapAidLayer.Styles(),
        OverlandMapControls.Styles(),
        OverlandMapLabelPanel.Styles(),
    }) do
        for _, rule in ipairs(group) do result[#result + 1] = rule end
    end
    return result
end

--- Re-merge the rules whenever the color scheme changes.
--- @param element Panel the Overland Map root
function OverlandMapStyles.Subscribe(element)
    element.data.themeSubscription = ThemeEngine.OnThemeChanged(mod, function()
        if mod.unloaded or not element.valid then return end
        element.styles = ThemeEngine.MergeStyles(Styles.Build())
        element:UpdateStyle()
        element:FireEventTree("overlandMapThemeChanged")
    end)
end

--- @param element Panel the Overland Map root
function OverlandMapStyles.Unsubscribe(element)
    if element.data.themeSubscription ~= nil then
        element.data.themeSubscription:Deregister()
        element.data.themeSubscription = nil
    end
end
