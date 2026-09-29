-- scripts/base/profiles.lua
-- The planet profile a base is built for: which planet a surface is a copy
-- of, and the planet-tuned power entities the data stage made for it
-- (data-final-fixes.lua). scripts/blueprints.lua turns a profile into the
-- entities to build.

local M = {}

-- The profiles the data stage writes per planet (data-final-fixes.lua).
local PROFILES_MOD_DATA = "bnm-planet-profiles"

-- The planet whose profile a surface with no planet gets.
local DEFAULT_PLANET = "nauvis"

-- The planet MTS spawns every team on, so the planet a team's home base is on.
M.HOME_PLANET = "nauvis"

--- "mts-gleba-3" -> "gleba": MTS names each team's planet copy
--- mts-<base>-<slot>. Any other name is its own base.
function M.base_planet_name(name)
    return name:match("^mts%-(.+)%-%d+$") or name
end

--- True if the named planet (e.g. "mts-nauvis-3") is a copy of the home planet.
function M.is_home_planet(planet_name)
    return M.base_planet_name(planet_name) == M.HOME_PLANET
end

--- The data stage's profile for a planet, or nil when the mod-data or the
--- entry is missing (an older data stage).
local function stored_profile(planet_name)
    local md = prototypes.mod_data[PROFILES_MOD_DATA]
    local planets = md and md.get("planets")
    return planets and planets[planet_name] or nil
end

local function entity_or_nil(name)
    if name and prototypes.entity[name] then return name end
    return nil
end

--- The planet profile for a surface: { base, solar_panel, accumulator,
--- fulgora, freezing } (see docs/fixup-plan.md). Read from the data stage's
--- mod-data by surface.planet.name; a surface with no planet gets the Nauvis
--- profile. Falls back gracefully (vanilla everything, base from the planet
--- name) when the mod-data, the entry or a named prototype does not exist.
function M.profile_for(surface)
    local planet = surface.planet
    local name   = planet and planet.name or DEFAULT_PLANET
    local stored = stored_profile(name) or {}
    local base   = stored.base or M.base_planet_name(name)
    local fulgora, freezing = stored.fulgora, stored.freezing
    if fulgora == nil then fulgora = base == "fulgora" end
    if freezing == nil then
        freezing = planet and planet.prototype.entities_require_heating or false
    end
    return {
        base        = base,
        solar_panel = entity_or_nil(stored.solar_panel),
        accumulator = entity_or_nil(stored.accumulator),
        fulgora     = fulgora,
        freezing    = freezing,
    }
end

return M
