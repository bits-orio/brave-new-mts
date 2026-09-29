-- scripts/base/power_core.lua
-- What stays non-minable in a starter base, and when: locked as the base is
-- built, unlocked when the team opts in, released when an outpost is lost.
--
-- The power core stays NON-MINABLE until the team opts into "I know what I am
-- doing": losing any of it would strand the base. It is the power generation
-- and storage, the lightning attractors that shield it (and the Fulgora
-- collector that is its night power), the substations and main poles, the
-- lights and the sign. Planet-tuned copies are locked for good (is_tuned).
-- Everything else is minable from the start, so a team can freely redesign
-- the base. The central roboport is never minable and is handled separately
-- (scripts/base/builder.lua).

local M = {}

local PROTECTED_TYPES = {
    ["solar-panel"]         = true,
    ["accumulator"]         = true,
    ["lightning-attractor"] = true,
    ["lamp"]                = true,
    ["display-panel"]       = true,
}
local PROTECTED_NAMES = {
    ["substation"]           = true,  -- the blueprint's three substations
    ["medium-electric-pole"] = true,  -- main poles, should a blueprint carry any
}
local function is_power_core(entity)
    return PROTECTED_TYPES[entity.type] or PROTECTED_NAMES[entity.name] or false
end

--- A planet-tuned copy (prototypes/bnm_variant.lua: bnm-solar-panel-gleba,
--- bnm-radar, ...). It stays non-minable even once the team unlocks its core:
--- no item can place one again, and mining one returns an ordinary building
--- that gives far less power (or freezes) on that planet. Having no placing
--- item is what makes that loss permanent, so it is also the test.
local function is_tuned(entity)
    local items = entity.prototype.items_to_place_this
    return not (items and items[1])
end

--- Lock a power core entity (unless the team unlocked it) or a tuned copy
--- (always), and list it in built.protected.
function M.lock(built, created, locked)
    local tuned = is_tuned(created)
    if not (tuned or is_power_core(created)) then return end
    if locked or tuned then created.minable_flag = false end
    built.protected[#built.protected + 1] = created
end

--- Mark a base unlocked and make its core minable, all but the tuned copies.
function M.unlock(base)
    base.unlocked = true
    for _, e in pairs(base.protected) do
        if e.valid and not is_tuned(e) then e.minable_flag = true end
    end
end

--- Make a lost base's whole core minable, tuned copies included, so the
--- team's bots can salvage it.
function M.release(base)
    for _, e in pairs(base.protected or {}) do
        if e.valid then e.minable_flag = true end
    end
end

return M
