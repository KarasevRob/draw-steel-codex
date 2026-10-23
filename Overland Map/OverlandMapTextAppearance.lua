local mod = dmhub.GetModLoading()

--- Text appearance data shared by labels and map pin names: the stored format,
--- its validation and permission rules, and the geometry both renderers use.
--- No panels are built here; the image view and editor are in OverlandMapControls.
--- @class OverlandMapTextAppearance: GameType
--- @field new fun(o?: table): OverlandMapTextAppearance
--- @field defaults table<string, any>
--- @field pinFields string[]
OverlandMapTextAppearance = RegisterGameType("OverlandMapTextAppearance")
local A, R = OverlandMapTextAppearance, OverlandMapRecords

--- Optional leaves use defaults; manual lengths are map-width fractions for labels and points for pins.
--- @class OverlandMapTextAppearanceFormat
--- @field outlineMode nil|"default"|"none"|"custom"
--- @field outlineWidth nil|number Native 0-1 thickness, displayed on a relative 0-100 scale.
--- @field outlineColor nil|string
--- @field backgroundImageId nil|string
--- @field backgroundFit nil|"fit"|"fill"|"stretch"
--- @field backgroundSizing nil|"auto"|"manual"
--- @field backgroundPadX nil|number Horizontal padding per side, in font-size multiples.
--- @field backgroundPadY nil|number Vertical padding per side, in font-size multiples.
--- @field backgroundWidth nil|number
--- @field backgroundHeight nil|number
--- @field backgroundX nil|number
--- @field backgroundY nil|number
--- @field backgroundOpacity nil|number
--- @field backgroundManualSet nil|boolean

A.defaults = {
    outlineMode = "default", outlineWidth = 0.1, outlineColor = "",
    backgroundImageId = "", backgroundFit = "fit", backgroundSizing = "auto",
    backgroundPadX = 0.5, backgroundPadY = 0.25, backgroundWidth = 0.1, backgroundHeight = 0.03,
    backgroundX = 0, backgroundY = 0, backgroundOpacity = 1,
    backgroundManualSet = false,
}

-- Manual image sizes and offsets: labels store fractions of the map width (the editor
-- allows up to 400%), pins store points. A larger stored value falls back to the default.
local labelSizeLimit, pinSizeLimit = 4, 4096

--- Black or white, whichever reads better against this text color (WCAG relative luminance).
--- @param color string "#rrggbb" or "#rrggbbaa"
--- @return string
function OverlandMapTextAppearance.Contrast(color)
    local function Channel(at)
        local n = (tonumber(color:sub(at, at + 1), 16) or 255) / 255
        if n <= 0.04045 then return n / 12.92 end
        return ((n + 0.055) / 1.055) ^ 2.4
    end
    local luminance = 0.2126 * Channel(2) + 0.7152 * Channel(4) + 0.0722 * Channel(6)
    return luminance > 0.179 and "#000000ff" or "#ffffffff"
end

--- The font to draw: the stored one when this client has it, else Berling or the first available.
--- @param font string
--- @return string
function OverlandMapTextAppearance.DisplayFont(font)
    local fallback = nil
    for _, available in ipairs(gui.availableFonts or {}) do
        if available == font then return font end
        if available == "berling" then fallback = available end
    end
    return fallback or (gui.availableFonts or {})[1] or "book"
end

--- @param value any
--- @return boolean
function OverlandMapTextAppearance.ValidColor(value)
    return type(value) == "string" and (value:match("^#%x%x%x%x%x%x$") ~= nil or value:match("^#%x%x%x%x%x%x%x%x$") ~= nil)
end
local ValidColor = A.ValidColor

--- @param key string
--- @return boolean
function OverlandMapTextAppearance.IsImageField(key)
    return A.defaults[key] ~= nil and key:sub(1, 10) == "background"
end

--- Outline and image leaves.
--- @param key string
--- @param value any
--- @param pins nil|boolean true for map pin names, whose manual lengths are points
--- @return boolean
function OverlandMapTextAppearance.Valid(key, value, pins)
    if key == "outlineMode" then return value == "default" or value == "none" or value == "custom" end
    if key == "outlineColor" then return value == "" or ValidColor(value) end
    if key == "backgroundImageId" then return value == "" or R.IsArtworkId(value) end
    if key == "backgroundFit" then return value == "fit" or value == "fill" or value == "stretch" end
    if key == "backgroundSizing" then return value == "auto" or value == "manual" end
    if key == "backgroundManualSet" then return type(value) == "boolean" end
    if not R.IsFinite(value) then return false end
    local limit = pins and pinSizeLimit or labelSizeLimit
    if key == "outlineWidth" or key == "backgroundOpacity" then return value >= 0 and value <= 1 end
    if key == "backgroundPadX" or key == "backgroundPadY" then return value >= 0 and value <= 10 end
    if key == "backgroundWidth" or key == "backgroundHeight" then return value > 0 and value <= limit end
    if key == "backgroundX" or key == "backgroundY" then return math.abs(value) <= limit end
    return false
end

--- Typography both labels and pin names store: font, emphasis, spacing, colors and backing.
--- @param key string
--- @param value any
--- @return nil|boolean nil when key is not a shared typography key
function OverlandMapTextAppearance.ValidTypography(key, value)
    if key == "font" then return type(value) == "string" and #value > 0 and #value <= 128 end
    if key == "bold" or key == "italics" then return type(value) == "boolean" end
    if key == "spacing" then return R.IsFinite(value) and value >= 0 and value <= 1 end
    if key == "color" or key == "backgroundColor" then return ValidColor(value) end
    if key == "background" then return value == "auto" or value == "plate" or value == "none" or value == "image" end
    return nil
end

--- Asset availability never erases a stored reference or invalidates its owning row.
--- @param source any
--- @param pins nil|boolean
--- @return table<string, any>
function OverlandMapTextAppearance.Format(source, pins)
    local result = {}
    for key, default in pairs(A.defaults) do
        if pins and key == "backgroundWidth" then default = 180 end
        if pins and key == "backgroundHeight" then default = 30 end
        local value = R.Field(source, key, nil)
        result[key] = A.Valid(key, value, pins) and value or default
    end
    return result
end

--- @param id any
--- @return nil|ImageAssetLua asset
--- @return nil|string reason
function OverlandMapTextAppearance.ReadableAsset(id)
    local asset, reason = R.ArtworkAsset(id)
    if asset == nil then return nil, reason end
    local ok, allowed = pcall(function() return asset:HaveReadPermissions() end)
    if not ok or not allowed then return nil, "invalid" end
    return asset, nil
end

--- Whether changes may apply to current. Players never touch image settings or switch
--- to or from an image background; a newly chosen image must be readable.
--- @param current any
--- @param changes table
--- @param director boolean
--- @param reset nil|boolean
--- @return boolean
function OverlandMapTextAppearance.CanChange(current, changes, director, reset)
    if not director then
        for key, value in pairs(changes) do
            if A.IsImageField(key) then return false end
            if key == "background" and value ~= R.Field(current, key, "auto")
                and (value == "image" or R.Field(current, key, "auto") == "image") then return false end
        end
        if reset and R.Field(current, "background", "auto") == "image" then return false end
    end
    local image = changes.backgroundImageId
    if image ~= nil and image ~= false and image ~= "" and image ~= R.Field(current, "backgroundImageId", "") then
        if A.ReadableAsset(image) == nil then return false end
    end
    local mode = changes.background
    if mode == nil and not reset then mode = R.Field(current, "background", "auto") end
    if mode == "image" and (changes.background ~= nil or image ~= nil) then
        local id = image
        if id == nil then id = reset and "" or R.Field(current, "backgroundImageId", "") end
        if id == false or id == "" then return false end
    end
    return true
end

--- The keys of changes a player may not apply to current: image leaves and any switch
--- to or from an image background. The rest of the change set stays valid without them.
--- @param current any
--- @param changes table
--- @return table<string, boolean>
function OverlandMapTextAppearance.PlayerRefused(current, changes)
    local refused = {}
    for key, value in pairs(changes) do
        if A.IsImageField(key) then refused[key] = true end
        if key == "background" and value ~= R.Field(current, key, "auto")
            and (value == "image" or R.Field(current, key, "auto") == "image") then refused[key] = true end
    end
    return refused
end

--- A format a player can save: an image background becomes Auto contrast and image leaves go.
--- @param format nil|table
--- @return table
function OverlandMapTextAppearance.PlayerFormat(format)
    local result = DeepCopy(format or {})
    if result.background == "image" then result.background = "auto" end
    for key in pairs(A.defaults) do if A.IsImageField(key) then result[key] = nil end end
    return result
end

--- A remembered format made safe to start a new text with: an unreadable image falls
--- back to Auto contrast and a font this client lacks to its display font.
--- @param format table
--- @return table
function OverlandMapTextAppearance.UsableFormat(format)
    local result = DeepCopy(format)
    if type(result.font) == "string" then result.font = A.DisplayFont(result.font) end
    local image = result.backgroundImageId
    if result.background == "image" and (type(image) ~= "string" or image == "" or A.ReadableAsset(image) == nil) then
        result.background = "auto"
    end
    if type(image) == "string" and image ~= "" and A.ReadableAsset(image) == nil then result.backgroundImageId = "" end
    return result
end

--- @param pins boolean
--- @return table<string, any>
function OverlandMapTextAppearance.RemoveImagePatch(pins)
    local changes = {} --- @type table<string, any>
    changes.background = "auto"
    if pins then changes.background = false end
    for key, value in pairs(A.defaults) do
        if A.IsImageField(key) then
            if pins then changes[key] = false else changes[key] = value end
        end
    end
    return changes
end

--- @param a any
--- @param b any
--- @return boolean
function OverlandMapTextAppearance.SameImages(a, b)
    if R.Field(a, "background", "auto") ~= R.Field(b, "background", "auto")
        and (R.Field(a, "background", "auto") == "image" or R.Field(b, "background", "auto") == "image") then return false end
    for key in pairs(A.defaults) do
        if A.IsImageField(key) and not dmhub.DeepEqual(R.Field(a, key, nil), R.Field(b, key, nil)) then return false end
    end
    return true
end

--- @param format table
--- @param defaultWidth number
--- @param defaultColor string
--- @return number width
--- @return string color
function OverlandMapTextAppearance.Outline(format, defaultWidth, defaultColor)
    if format.outlineMode == "none" then return 0, defaultColor end
    if format.outlineMode == "custom" then
        local color = format.outlineColor
        if color == nil or color == "" then color = A.Contrast(format.color) end
        return format.outlineWidth or 0.1, color
    end
    return defaultWidth, defaultColor
end

--- Font and outline: when this changes, renderers build a new native text label
--- instead of restyling the old one.
--- @param format table
--- @param defaultWidth number
--- @param defaultColor string
--- @return string
function OverlandMapTextAppearance.MaterialKey(format, defaultWidth, defaultColor)
    local width, color = A.Outline(format, defaultWidth, defaultColor)
    return table.concat({ tostring(format.font), tostring(width), tostring(color) }, "|")
end

--- Rectangles stay in text-local coordinates; unit converts map fractions or pin points.
--- @param format table
--- @param textWidth number
--- @param textHeight number
--- @param fontSize number
--- @param unit number
--- @return table
function OverlandMapTextAppearance.Geometry(format, textWidth, textHeight, fontSize, unit)
    local width = textWidth + 2 * format.backgroundPadX * fontSize
    local height = textHeight + 2 * format.backgroundPadY * fontSize
    if format.backgroundSizing == "manual" then
        width, height = format.backgroundWidth * unit, format.backgroundHeight * unit
    end
    local x, y = format.backgroundX * unit, format.backgroundY * unit
    local text = { x1 = -textWidth / 2, x2 = textWidth / 2, y1 = -textHeight / 2, y2 = textHeight / 2 }
    local image = { x1 = x - width / 2, x2 = x + width / 2, y1 = y - height / 2, y2 = y + height / 2 }
    return { text = text, image = image,
        x1 = math.min(text.x1, image.x1), x2 = math.max(text.x2, image.x2),
        y1 = math.min(text.y1, image.y1), y2 = math.max(text.y2, image.y2) }
end

--- @param rect table
--- @param x number
--- @param y number
--- @return boolean
function OverlandMapTextAppearance.Contains(rect, x, y)
    return x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2
end

--- @param mode string
--- @param boxWidth number
--- @param boxHeight number
--- @param imageWidth number
--- @param imageHeight number
--- @return number width
--- @return number height
--- @return nil|table crop
function OverlandMapTextAppearance.Fit(mode, boxWidth, boxHeight, imageWidth, imageHeight)
    if mode == "fit" then
        local scale = math.min(boxWidth / imageWidth, boxHeight / imageHeight)
        return imageWidth * scale, imageHeight * scale, nil
    end
    if mode == "fill" then
        local imageAspect, boxAspect = imageWidth / imageHeight, boxWidth / boxHeight
        local w, h = math.min(1, boxAspect / imageAspect), math.min(1, imageAspect / boxAspect)
        return boxWidth, boxHeight, { x1 = (1 - w) / 2, x2 = (1 + w) / 2, y1 = (1 - h) / 2, y2 = (1 + h) / 2 }
    end
    return boxWidth, boxHeight, nil
end

-- Map pin name format ----------------------------------------------------------------------------

--- Sparse overrides belong to the map, never to one of its pins.
--- @class OverlandMapPinNameFormat: OverlandMapTextAppearanceFormat
--- @field font nil|string
--- @field majorSize nil|number
--- @field normalSize nil|number
--- @field minorSize nil|number
--- @field bold nil|boolean
--- @field italics nil|boolean
--- @field anchor nil|string
--- @field spacing nil|number
--- @field color nil|string
--- @field background nil|string
--- @field backgroundColor nil|string

A.pinFields = { "font", "majorSize", "normalSize", "minorSize", "bold", "italics", "anchor",
    "spacing", "color", "background", "backgroundColor" }
for key in pairs(A.defaults) do A.pinFields[#A.pinFields + 1] = key end
table.sort(A.pinFields)
local pinKnown = R.SetOf(A.pinFields)

--- @param key string
--- @param value any
--- @return boolean
function OverlandMapTextAppearance.ValidPin(key, value)
    if A.defaults[key] ~= nil then return A.Valid(key, value, true) end
    local typography = A.ValidTypography(key, value)
    if typography ~= nil then return typography end
    if key == "majorSize" or key == "normalSize" or key == "minorSize" then
        return R.IsFinite(value) and value >= 6 and value <= 72 and math.abs(value * 10 - math.floor(value * 10 + 0.5)) < 0.00001
    end
    if key == "anchor" then return value == "left" or value == "center" or value == "right" end
    return false
end
local ValidPin = A.ValidPin

--- The overrides this client understands; bad leaves fall back independently and never
--- affect Location validity.
--- @param stored any a map's pinNameFormat
--- @return table<string, any>
function OverlandMapTextAppearance.PinOverrides(stored)
    local result = {}
    for _, key in ipairs(A.pinFields) do
        local value = R.Field(stored, key, nil)
        if ValidPin(key, value) then result[key] = value end
    end
    return result
end

--- false clears a leaf, except bold and italics, where false is a value.
--- @param format table changed in place
--- @param patch table
--- @return table format
function OverlandMapTextAppearance.MergePinPatch(format, patch)
    for key, value in pairs(patch) do
        if value == false and key ~= "bold" and key ~= "italics" then format[key] = nil else format[key] = value end
    end
    return format
end

--- @param patch any
--- @return boolean
function OverlandMapTextAppearance.ValidPinPatch(patch)
    if type(patch) ~= "table" then return false end
    for key, value in pairs(patch) do
        if not pinKnown[key] or (value ~= false and not ValidPin(key, value)) then return false end
        if key == "font" and value ~= false and A.DisplayFont(value) ~= value then return false end
    end
    return true
end

--- The stored format after a patch, or nil when the patch is invalid or not permitted.
--- Keys this client does not know are kept, so a newer client's settings survive an edit here.
--- @param stored any a map's pinNameFormat
--- @param patch table
--- @param reset boolean start from no overrides
--- @param director boolean
--- @return nil|table
function OverlandMapTextAppearance.ApplyPinPatch(stored, patch, reset, director)
    if not A.ValidPinPatch(patch) or type(reset) ~= "boolean" then return nil end
    if not A.CanChange(A.PinOverrides(stored), patch, director, reset) then return nil end
    local base = {}
    if not reset and type(stored) == "table" then
        for key, value in pairs(stored) do
            if not pinKnown[key] or ValidPin(key, value) then base[key] = DeepCopy(value) end
        end
    end
    return A.MergePinPatch(base, patch)
end
