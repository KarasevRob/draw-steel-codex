local mod = dmhub.GetModLoading()

--Credits for third-party creators whose art the app shows (scene backdrops,
--key art, location art). Each creator is registered once, with a logo and a
--link; any screen that shows their work puts CreatorCredit.Badge on it, or
--builds the whole screen on CreatorCredit.Backdrop, so the credit looks and
--behaves the same everywhere: the creator's logo in a corner of the art,
--with a tooltip naming them, that opens their site when clicked.
--
--To credit a new creator:
--  1. Upload their logo as a core image asset: white (or light) on a
--     transparent background, since it is drawn over art.
--  2. Add a CreatorCredit.Register call at the bottom of this file.
--  3. Either pass creator = "<id>" wherever their art is shown, or tag the
--     art once with CreatorCredit.RegisterArt(imageid, "<id>") and let
--     Backdrop find the credit from the image.
--
--A creator's logo and link could later come from a creator organization's
--branding (/ModuleAuthor/{orgid} logo + url) instead of this file; Register
--is the one place that would change.

--- @class CreatorCreditInfo
--- @field id string
--- @field name string Shown in the badge's tooltip ("Art by <name>").
--- @field logo string Image id of the logo, light on transparent.
--- @field logoWidth number The logo image's pixel size, for its aspect ratio.
--- @field logoHeight number
--- @field url nil|string The creator's site; the badge opens it when clicked.

CreatorCredit = {
    --- @type table<string, CreatorCreditInfo>
    creators = {},

    --- Image (or video) id -> creator id, for art tagged with RegisterArt.
    --- @type table<string, string>
    art = {},

    --- Image (or video) id -> creator id, learned from the "Art by" setting
    --- of [[scene]] tags as they are shown (TagSceneArt).
    --- @type table<string, string>
    sceneArt = {},
}

--- Adds (or replaces) a creator.
--- @param id string
--- @param info {name: string, logo: string, logoWidth: number, logoHeight: number, url: nil|string}
function CreatorCredit.Register(id, info)
    CreatorCredit.creators[id] = {
        id = id,
        name = info.name,
        logo = info.logo,
        logoWidth = info.logoWidth,
        logoHeight = info.logoHeight,
        url = info.url,
    }
end

--- Tags a piece of art (an image or video id) as a creator's work.
--- @param imageid string
--- @param creatorid string
function CreatorCredit.RegisterArt(imageid, creatorid)
    CreatorCredit.art[imageid] = creatorid
end

--- @param id nil|string
--- @return nil|CreatorCreditInfo
function CreatorCredit.Get(id)
    if id == nil then
        return nil
    end
    return CreatorCredit.creators[id]
end

--- Records (or, with nil, clears) the credit a [[scene]] tag's "Art by"
--- setting gives its art. Code that shows a scene calls this as it resolves
--- the scene's image, so anything drawing that image can find the credit
--- with ForArt.
--- @param imageid nil|string
--- @param creatorid nil|string
function CreatorCredit.TagSceneArt(imageid, creatorid)
    if imageid == nil or imageid == "" then
        return
    end
    if creatorid == nil or creatorid == "" or CreatorCredit.creators[creatorid] == nil then
        CreatorCredit.sceneArt[imageid] = nil
    else
        CreatorCredit.sceneArt[imageid] = creatorid
    end
end

--- The creator credited for a piece of art, if it was tagged.
--- @param imageid nil|string
--- @return nil|CreatorCreditInfo
function CreatorCredit.ForArt(imageid)
    if imageid == nil then
        return nil
    end
    return CreatorCredit.Get(CreatorCredit.art[imageid] or CreatorCredit.sceneArt[imageid])
end

--- Dropdown options for picking a creator: "None" (id "none") then every
--- registered creator by name.
--- @return {id: string, text: string}[]
function CreatorCredit.DropdownOptions()
    local result = {}
    for id, info in pairs(CreatorCredit.creators) do
        result[#result+1] = { id = id, text = info.name }
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    table.insert(result, 1, { id = "none", text = "None" })
    return result
end

--"https://www.czepeku.com/" -> "czepeku.com", for the tooltip.
local function ShortUrl(url)
    local s = url:gsub("^https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    return s
end

local BADGE_STYLES = {
    {
        selectors = { "creatorCreditLogo" },
        opacity = 0.8,
        transitionTime = 0.15,
    },
    {
        selectors = { "creatorCreditLogo", "parent:hover" },
        opacity = 1,
        scale = 1.05,
    },
}

--- A creator's logo as a small badge, by default floating in the bottom-right
--- corner of the panel it is added to. Hovering names the creator; clicking
--- opens their site (through the app's usual confirm-before-opening prompt).
--- Returns nil for an unknown creator, so callers can add it unconditionally.
--- @param options {creator: string, width: nil|number, halign: nil|string, valign: nil|string, hmargin: nil|number, vmargin: nil|number}
--- @return nil|Panel
function CreatorCredit.Badge(options)
    local info = CreatorCredit.Get(options.creator)
    if info == nil then
        return nil
    end
    local url = info.url
    local width = options.width or 170
    local height = math.floor(width * info.logoHeight / info.logoWidth + 0.5)

    local tooltip = string.format("Art by %s", info.name)
    if url ~= nil then
        tooltip = string.format("%s\nClick to visit %s", tooltip, ShortUrl(url))
    end

    return gui.Panel{
        classes = { "creatorCreditBadge" },
        floating = true,
        halign = options.halign or "right",
        valign = options.valign or "bottom",
        hmargin = options.hmargin or 24,
        vmargin = options.vmargin or 20,
        width = width,
        height = height,
        --a panel with no bgimage is not hit-tested.
        bgimage = "panels/square.png",
        bgcolor = "clear",
        styles = BADGE_STYLES,
        hoverCursor = cond(url ~= nil, "hand", nil),
        linger = function(element)
            gui.Tooltip(tooltip)(element)
        end,
        click = function(element)
            if url ~= nil then
                dmhub.OpenURL(url)
            end
        end,

        gui.Panel{
            classes = { "creatorCreditLogo" },
            interactable = false,
            width = "100%",
            height = "100%",
            bgimage = info.logo,
            bgcolor = "white",
        },
    }
end

--The imageRect that shows an image of aspect imageAspect covering a box of
--boxAspect, cropped around focus (fx, fy) in 0..1 (0.5 = centred).
local function CoverRect(boxAspect, imageAspect, fx, fy)
    local wFrac, hFrac = 1, 1
    if imageAspect > boxAspect then
        wFrac = boxAspect / imageAspect
    else
        hFrac = imageAspect / boxAspect
    end
    local left = (1 - wFrac) * fx
    local top = (1 - hFrac) * fy
    return { x1 = left, x2 = left + wFrac, y1 = 1 - top - hFrac, y2 = 1 - top }
end

local BACKDROP_STYLES = {
    {
        selectors = { "creatorBackdropArt" },
        opacity = 0,
        transitionTime = 0.45,
    },
    {
        selectors = { "creatorBackdropArt", "shown" },
        opacity = 1,
    },
    --drops the art to transparent at once, so ReplayFade can ease it back in.
    {
        selectors = { "creatorBackdropArt", "instant" },
        transitionTime = 0,
    },
}

--- Re-plays a backdrop's fade-in, for a backdrop kept alive and shown again
--- (e.g. un-collapsed) rather than rebuilt.
--- @param backdrop Panel
function CreatorCredit.ReplayFade(backdrop)
    backdrop:FireEventTree("creatorBackdropReplay")
end

--- A full-bleed art backdrop: the art cover-fitted to width x height on black,
--- fading in once it has loaded, with the creator's badge in the bottom-right
--- corner over a soft shade that keeps the logo legible on bright art.
---
--- options:
---   width, height  the backdrop's size in the parent's units (required).
---   image          the still (or, with video, its poster).
---   video          optional looping video drawn over the still once it plays.
---   aspect         the art's width / height. Omit to read it from the image.
---   focusX, focusY where to crop around when the aspects differ (0.5 = centre).
---   creator        creator id; defaults to the creator tagged on the video or image.
---   badge          optional overrides for CreatorCredit.Badge, or false for none.
---   children       panels to draw over the art (and under the badge).
--- @param options table
--- @return Panel
function CreatorCredit.Backdrop(options)
    local width = options.width
    local height = options.height
    local boxAspect = width / height
    local fx = options.focusX or 0.5
    local fy = options.focusY or 0.5
    local aspect = options.aspect

    --One art layer: a fresh panel stays invisible until its image has
    --loaded and then fires imageLoaded, which is when it fades in.
    local ArtLayer = function(imageid)
        return gui.Panel{
            classes = { "creatorBackdropArt" },
            floating = true,
            halign = "center",
            valign = "center",
            width = width,
            height = height,
            interactable = false,
            bgimage = imageid,
            bgcolor = "white",
            data = { loaded = false },
            create = function(element)
                if aspect ~= nil then
                    element.selfStyle.imageRect = CoverRect(boxAspect, aspect, fx, fy)
                end
            end,
            --art that has not loaded yet fades in on imageLoaded anyway.
            creatorBackdropReplay = function(element)
                if not element.data.loaded then
                    return
                end
                element:SetClass("instant", true)
                element:SetClass("shown", false)
                element:ScheduleEvent("creatorBackdropFadeIn", 0.05)
            end,
            creatorBackdropFadeIn = function(element)
                element:SetClass("instant", false)
                element:SetClass("shown", true)
            end,
            imageLoaded = function(element)
                element.data.loaded = true
                if aspect ~= nil then
                    element:SetClass("shown", true)
                    return
                end
                local lookup = imageid
                if lookup:sub(1, 4) == "md5:" then
                    lookup = lookup:sub(5)
                end
                gui.GetImageDimensionsCallback(lookup, function(dims)
                    if mod.unloaded or not element.valid then
                        return
                    end
                    if dims ~= nil and (dims.width or 0) > 0 and (dims.height or 0) > 0 then
                        element.selfStyle.imageRect = CoverRect(boxAspect, dims.width / dims.height, fx, fy)
                    end
                    element:SetClass("shown", true)
                end)
            end,
        }
    end

    local children = {}
    if type(options.image) == "string" and options.image ~= "" then
        children[#children+1] = ArtLayer(options.image)
    end
    if type(options.video) == "string" and options.video ~= "" then
        children[#children+1] = ArtLayer(options.video)
    end
    for _,child in ipairs(options.children or {}) do
        children[#children+1] = child
    end

    local info = CreatorCredit.Get(options.creator) or CreatorCredit.ForArt(options.video) or CreatorCredit.ForArt(options.image)
    if info ~= nil and options.badge ~= false then
        --darkens the bottom-right corner under the logo; transparent by the
        --middle of the screen so the art is otherwise untouched.
        children[#children+1] = gui.Panel{
            floating = true,
            halign = "right",
            valign = "bottom",
            width = math.min(width, 900),
            height = math.min(height, 260),
            interactable = false,
            bgimage = "panels/square.png",
            bgcolor = "black",
            gradient = gui.Gradient{
                point_a = { x = 1, y = 0 },
                point_b = { x = 0, y = 1 },
                stops = {
                    { position = 0, color = core.Color{ r = 1, g = 1, b = 1, a = 0.6 } },
                    { position = 0.45, color = core.Color{ r = 1, g = 1, b = 1, a = 0.2 } },
                    { position = 0.8, color = core.Color{ r = 1, g = 1, b = 1, a = 0 } },
                },
            },
        }
        local badgeOptions = { creator = info.id }
        if type(options.badge) == "table" then
            for k,v in pairs(options.badge) do
                badgeOptions[k] = v
            end
        end
        children[#children+1] = CreatorCredit.Badge(badgeOptions)
    end

    return gui.Panel{
        classes = { "creatorBackdrop" },
        floating = true,
        halign = "center",
        valign = "center",
        width = width,
        height = height,
        flow = "none",
        --opaque black: what shows until the art fades in, and what keeps
        --whatever is behind the backdrop from showing through.
        bgimage = "panels/square.png",
        bgcolor = "black",
        styles = BACKDROP_STYLES,
        children = children,
    }
end

--- Creators whose art ships with the app. ---------------------------------

CreatorCredit.Register("czepeku", {
    name = "Czepeku Scenes",
    logo = "4e3b9a3b-b6bb-4e85-b626-9536b1c2585a",
    logoWidth = 242,
    logoHeight = 79,
    url = "https://czepeku.com",
})
