local mod = dmhub.GetModLoading()

--- Show to players (D10, R4, R5): the Director pushes the open map to every
--- client through GameHud's shared present slot; every recipient jumps to it.
--- Presenting is one-shot: nothing persists after the jump.
--- @class RegionMapPresent: GameType
--- @field new fun(o?: table): RegionMapPresent
RegionMapPresent = RegisterGameType("RegionMapPresent")
local C = RegionMapConstants
local Model = RegionMapModel
local Copy = RegionMapCopy

local T = Copy.T

--- @class RegionMapPresentController
--- @field ShowToPlayers fun()
--- @field Receive fun()

-- GameHud has one present slot shared by every feature. A slot is "foreign"
-- when another feature's presentation is still live there.
local function ForeignPresentation()
    local raw = GameHud.GetPresentDialogDocRaw()
    local data = raw ~= nil and raw.data or nil
    local current = data ~= nil and data.dialog or nil
    if type(current) ~= "table" or current.dialog == C.panelName then return nil end
    local args = current.args
    if type(args) == "table" and args.ttl ~= nil then
        local ok, age = pcall(TimestampAgeInSeconds, data.timestamp)
        if not ok or type(age) ~= "number" or age > args.ttl then return nil end
    end
    return tostring(current.dialog or "")
end

--- @param ctx RegionMapContext
--- @return RegionMapPresentController
function RegionMapPresent.Create(ctx)
    local controller = {}
    local ignoreNonce = nil --- @type nil|string our own presentation
    local lastNonce = nil --- @type nil|string the newest one this client handled
    local waiting = nil --- @type nil|{nonce: string, id: string, expiresAt: number}

    local function Send(map)
        if not ctx.IsAlive() or not Model.IsDirector() then return end
        local nonce = dmhub.GenerateGuid()
        ignoreNonce = nonce
        GameHud.PresentDialogToUsers(ctx.root, C.panelName, {
            regionMapLocationId = map.id, imageRevision = map.imageRevision, nonce = nonce, ttl = C.presentTtl,
        })
        RegionMapUndo.Notify("toast.showing", { map = Model.DisplayName(map) })
    end

    -- Replacing another feature's live presentation (a Negotiation, a Respite)
    -- would take it off every screen, so the engine's own dialog asks first.
    local function SendWithConfirm(map)
        local foreign = ForeignPresentation()
        if foreign == nil then
            Send(map)
            return
        end
        ctx.Confirm {
            title = T("tb.show"),
            message = Copy.Literal(foreign),
            confirm = T("tb.show"),
            onConfirm = function() Send(map) end,
        }
    end

    --- Director: show the open map. An unshared map asks "Share this map?" first (R4).
    function controller.ShowToPlayers()
        local map = ctx.CurrentMap()
        if map == nil or not Model.IsDirector() then return end
        if map.mapShared then
            SendWithConfirm(map)
            return
        end
        ctx.Confirm {
            title = T("dlg.share.title"),
            message = T("dlg.share.body", { map = Model.DisplayName(map) }),
            confirm = T("dlg.share.ok"),
            onConfirm = function()
                local ok, reason = Model.SetMapShared(map.id, true)
                if not ctx.Report(ok, reason) then return end
                local shared = Model.GetLocation(map.id)
                if shared ~= nil then SendWithConfirm(shared) end
            end,
        }
    end

    -- Jump once the map is readable here: the share may arrive a moment after
    -- the presentation, so a recipient retries until the presentation expires.
    local function TryJump()
        if waiting == nil then return end
        if dmhub.Time() > waiting.expiresAt then
            waiting = nil
            return
        end
        local map = Model.GetLocation(waiting.id)
        if map == nil or not Model.CanOpenMap(map) then return end
        waiting = nil
        ctx.FlushEdits()
        ctx.OpenMap(map.id, "jump")
        RegionMapUndo.Notify("toast.shown", { map = Model.DisplayName(map) })
    end

    --- Read the shared present slot after any change to it (and on refresh).
    function controller.Receive()
        if mod.unloaded then return end
        local doc = GameHud.GetPresentDialogDoc(C.panelName)
        if doc == nil or doc.data == nil then
            TryJump()
            return
        end
        local args = doc.data.dialog ~= nil and doc.data.dialog.args or nil
        if type(args) == "table" and type(args.nonce) == "string" and args.nonce ~= ""
            and type(args.regionMapLocationId) == "string" and args.nonce ~= lastNonce then
            local ageOk, age = pcall(TimestampAgeInSeconds, doc.data.timestamp)
            local ttl = math.min(Model.IsFinite(args.ttl) and args.ttl or 0, C.presentTtl)
            lastNonce = args.nonce
            if args.nonce ~= ignoreNonce and ageOk and Model.IsFinite(age) and age >= 0 and age < ttl then
                waiting = { nonce = args.nonce, id = args.regionMapLocationId, expiresAt = dmhub.Time() + ttl - age }
            end
        end
        TryJump()
    end

    return controller
end
