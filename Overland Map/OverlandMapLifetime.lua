local mod = dmhub.GetModLoading()

--- @class OverlandMapLifetime: GameType
--- @field new fun(o?: table): OverlandMapLifetime
OverlandMapLifetime = RegisterGameType("OverlandMapLifetime")

local generation = 1
local gameId = dmhub.gameid
local listeners = {} --- @type table<function, boolean>
local Invalidate

--- Capture this before scheduling or submitting asynchronous work.
--- @return integer
function OverlandMapLifetime.Capture()
    if gameId ~= dmhub.gameid then
        Invalidate()
    end
    return generation
end

--- @param captured integer
--- @return boolean
function OverlandMapLifetime.Valid(captured)
    return not mod.unloaded and captured == generation and gameId == dmhub.gameid
end

--- @param callback fun()
--- @return fun() unsubscribe
function OverlandMapLifetime.Subscribe(callback)
    listeners[callback] = true
    return function() listeners[callback] = nil end
end

Invalidate = function()
    generation = generation + 1
    gameId = dmhub.gameid
    local current = {}
    for callback in pairs(listeners) do current[#current + 1] = callback end
    for _, callback in ipairs(current) do
        if listeners[callback] then callback() end
    end
end

mod.enterGameHandlers[#mod.enterGameHandlers + 1] = Invalidate
mod.unloadHandlers[#mod.unloadHandlers + 1] = Invalidate

--- Timers belong to the game in which they were requested, including busy-row retries.
--- @param delay number
--- @param callback fun()
--- @return fun() cancel
function OverlandMapLifetime.Schedule(delay, callback)
    local captured, cancelled = OverlandMapLifetime.Capture(), false
    dmhub.Schedule(delay, function()
        if not cancelled and OverlandMapLifetime.Valid(captured) then callback() end
    end)
    return function() cancelled = true end
end

--- A view's work additionally belongs to one binding, independent of game-scoped saves.
--- @class OverlandMapOwner
--- @field generation integer
--- @field game integer
--- @field identity any
--- @field alive boolean
local Owner = {}
Owner.__index = Owner

--- @param identity any
--- @return OverlandMapOwner
function OverlandMapLifetime.Owner(identity)
    return setmetatable({ generation = 1, game = OverlandMapLifetime.Capture(), identity = identity, alive = true }, Owner)
end

--- @param identity any
function Owner:Bind(identity)
    self.generation = self.generation + 1
    self.identity = identity
end

--- @return fun(): boolean
function Owner:Guard()
    local captured, identity = self.generation, self.identity
    return function()
        return self.alive and self.generation == captured and self.identity == identity
            and OverlandMapLifetime.Valid(self.game)
    end
end

function Owner:Destroy()
    self.alive = false
    self.generation = self.generation + 1
end
