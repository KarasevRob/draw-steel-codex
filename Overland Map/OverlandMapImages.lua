local mod = dmhub.GetModLoading()

--- @class OverlandMapImages: GameType
--- @field new fun(o?: table): OverlandMapImages
OverlandMapImages = RegisterGameType("OverlandMapImages")

--- @class OverlandMapImageRequest
--- @field id string
--- @field source string
--- @field status "loading"|"ready"|"unavailable"
--- @field width nil|number
--- @field height nil|number
--- @field dimensionsKnown boolean
--- @field textureReady boolean
--- @field Cancel fun()
--- @field Dimensions fun(width: any, height: any): boolean
--- @field Loaded fun(width: any, height: any): boolean
--- @field Failed fun()

--- Dimensions alone do not prove that the texture loaded. A late texture can recover a timeout.
--- @class OverlandMapImageSpec
--- @field id string
--- @field source string
--- @field valid fun(): boolean
--- @field changed fun(request: OverlandMapImageRequest)

--- @param spec OverlandMapImageSpec
--- @return OverlandMapImageRequest
function OverlandMapImages.Request(spec)
    local owner = OverlandMapLifetime.Owner(spec.id .. ":" .. spec.source)
    local guard = owner:Guard()
    local request = { id = spec.id, source = spec.source, status = "loading",
        dimensionsKnown = false, textureReady = false }
    local function Valid() return guard() and spec.valid() end
    --- @param status "loading"|"ready"|"unavailable"
    local function Notify(status)
        if not Valid() then return end
        request.status = status
        spec.changed(request)
    end
    function request.Dimensions(width, height)
        if not Valid() or type(width) ~= "number" or type(height) ~= "number"
            or width ~= width or height ~= height or width <= 0 or height <= 0
            or width == math.huge or height == math.huge then return false end
        request.width, request.height, request.dimensionsKnown = width, height, true
        if request.textureReady then Notify("ready") end
        return true
    end
    function request.Loaded(width, height)
        if request.status == "ready" and request.width == width and request.height == height then return false end
        if not request.Dimensions(width, height) then return false end
        request.textureReady = true
        Notify("ready")
        return true
    end
    function request.Failed() Notify("unavailable") end
    local cancelTimer = OverlandMapLifetime.Schedule(OverlandMapConstants.artworkTimeout, function()
        if request.status == "loading" then request.Failed() end
    end)
    function request.Cancel()
        owner:Destroy()
        cancelTimer()
    end
    return request
end

--- Dimension lookup shares game and identity guards without implying texture readiness.
--- @param imageId string
--- @param onSize fun(width: integer, height: integer)
--- @param valid fun(): boolean
--- @return fun() cancel
function OverlandMapImages.Size(imageId, onSize, valid)
    local request = OverlandMapImages.Request { id = imageId, source = "dimensions", valid = valid, changed = function() end }
    local reported = false
    local function Report(dims)
        if reported or type(dims) ~= "table" then return end
        local width, height = tonumber(dims.width), tonumber(dims.height)
        if width == nil or height == nil then return end
        if request.Dimensions(width, height) then
            reported = true
            onSize(math.floor(width + 0.5), math.floor(height + 0.5))
            request.Cancel()
        end
    end
    local dims = gui.TryGetImageDimensions(imageId)
    if dims ~= nil then Report(dims) else gui.GetImageDimensionsCallback(imageId, Report) end
    return request.Cancel
end
