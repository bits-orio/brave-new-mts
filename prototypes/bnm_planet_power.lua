-- prototypes/bnm_planet_power.lua
-- Planet-tuned power for the starter base, and the per-planet profile that
-- tells the runtime which prototypes to place (mod-data "bnm-planet-profiles").
--
-- The base keeps the human-designed Nauvis footprint on every planet. Where
-- the sun is weaker than on Nauvis, the runtime puts uncraftable, tuned panels
-- and accumulators in the same slots (bnm_variant.lua has the rules every
-- copy follows):
--
--   * solar-power >= 100% (Nauvis, Vulcanus): vanilla panels and accumulators.
--   * Fulgora: lightning plus the sun. Vanilla panels, one vanilla lightning
--     collector in a panel slot (placed by the runtime), and
--     bnm-accumulator-fulgora to bank the strikes and carry the base through
--     the day, when no lightning falls.
--   * any other planet: panel output scaled by 100 / solar-power, accumulator
--     buffer scaled by day length (never below vanilla), both times a margin:
--     1.5 at 5% sun or less, else 1.25. The buffer gets 3% more on top
--     (BUFFER_MARGIN): these bases are storage-bound, and the lamps' night
--     draw does not scale, so the margin alone lands about 10 kW short of the
--     targets. Gleba gets 150 kW panels and 9.20 MJ accumulators (about
--     1.09 MW sustained); Aquilo 9 MW panels (90 kW in its 1% sun) and
--     22.07 MJ (about 1.31 MW).
--
-- Planets whose entities freeze (Aquilo) also get bnm-radar and bnm-inserter,
-- which need no heating. The roboport never freezes anywhere (bnm_roboport.lua).
--
-- Runs in data-final-fixes, after MTS has copied every planet once per team
-- (mts-<planet>-<slot>) and made the vanilla radar passive. Every planet,
-- copy or not, gets a profile. Stats come from the copy's base planet, and
-- each prototype is built once per base planet.

local variant = require("prototypes.bnm_variant")

local PROFILES = "bnm-planet-profiles"

-- Nauvis reference: vanilla solar-panel output (W), vanilla accumulator
-- buffer (J) and flow (W), Nauvis solar power (%) and day length (ticks).
local PANEL_OUTPUT   = 60000
local ACC_BUFFER     = 5000000
local ACC_FLOW       = 300000
local NAUVIS_SOLAR   = 100
local NAUVIS_DAY     = 25200

-- Extra accumulator buffer on top of the margin. The sustained load of a
-- storage-bound base scales with the margin, except the lamps' 15 kW at night,
-- which comes straight out of the storage. 1.03 clears the power targets
-- (Gleba 1.08 MW, Aquilo 1.30 MW) by about 10 kW; 1.02 would leave less than
-- the rig's sweep can resolve.
local BUFFER_MARGIN  = 1.03

-- Fulgora's accumulator, measured on the rig (design D1: 1.08 MW sustained,
-- no empty day in 1,080 base-days). 16 x 10 MJ covers the strike-free day,
-- and the 1 MW input catches about 3x more of each strike than 300 kW does.
local FULGORA_ACC = { buffer = "10MJ", input = "1MW", output = "300kW" }

--- "mts-gleba-3" -> "gleba". Any other name is its own base.
local function base_of(name)
    return name:match("^mts%-(.+)%-%d+$") or name
end

--- A surface property of `planet`, or `default` when it is missing or zero.
local function property(planet, key, default)
    local value = planet.surface_properties and planet.surface_properties[key]
    if not value or value == 0 then return default end
    return value
end

--- Solar power (%) and day length (ticks) that decide the tuning: the base
--- planet's when it exists, else the planet's own.
local function sun_of(planet)
    local source = data.raw.planet[base_of(planet.name)] or planet
    return property(source, "solar-power", NAUVIS_SOLAR),
           property(source, "day-night-cycle", NAUVIS_DAY)
end

local function margin(solar)
    return solar <= 5 and 1.5 or 1.25
end

local function watts(w)   return string.format("%.0fW", w) end
local function joules(j)  return string.format("%.0fJ", j) end

--- The base planet's display name: its own override, else its locale key.
local function planet_name(base)
    local planet = data.raw.planet[base]
    if planet and planet.localised_name then
        return table.deepcopy(planet.localised_name)
    end
    return { "space-location-name." .. base }
end

-- ─── Tuned prototypes, one set per base planet ──────────────────────────

local function solar_panel(base, solar)
    local panel = variant.make({
        type = "solar-panel", from = "solar-panel", name = "bnm-solar-panel-" .. base,
        localised_name        = { "entity-name.bnm-solar-panel", planet_name(base) },
        localised_description = { "entity-description.bnm-solar-panel",
                                  planet_name(base), tostring(solar) },
    })
    panel.production = watts(PANEL_OUTPUT * (NAUVIS_SOLAR / solar) * margin(solar))
    data:extend({ panel })
    return panel.name
end

--- An accumulator copy with the given energy_source limits (strings).
local function accumulator(base, description, buffer, input, output)
    local acc = variant.make({
        type = "accumulator", from = "accumulator", name = "bnm-accumulator-" .. base,
        localised_name        = { "entity-name.bnm-accumulator", planet_name(base) },
        localised_description = { description, planet_name(base) },
    })
    local source = acc.energy_source   -- usage_priority stays vanilla's
    source.buffer_capacity   = buffer
    source.input_flow_limit  = input
    source.output_flow_limit = output
    data:extend({ acc })
    return acc.name
end

local function solar_accumulator(base, solar, day)
    local m = margin(solar)
    local flow = watts(ACC_FLOW * m)
    return accumulator(base, "entity-description.bnm-accumulator",
        joules(ACC_BUFFER * math.max(1, day / NAUVIS_DAY) * m * BUFFER_MARGIN), flow, flow)
end

--- Builds a base planet's prototypes and returns the profile fields every
--- copy of that planet shares.
local function tune(base, solar, day)
    if base == "fulgora" then
        return {
            accumulator = accumulator(base, "entity-description.bnm-accumulator-fulgora",
                FULGORA_ACC.buffer, FULGORA_ACC.input, FULGORA_ACC.output),
            fulgora = true,
        }
    end
    if solar >= NAUVIS_SOLAR then return {} end
    return {
        solar_panel = solar_panel(base, solar),
        accumulator = solar_accumulator(base, solar, day),
    }
end

-- ─── Non-freezing radar and inserter ────────────────────────────────────

--- One LocalisedString naming the given base planets: "Aquilo", "A, B".
--- At most 10 names, which keeps it within the 20-parameter limit.
local function planet_list(bases)
    local sorted = {}
    for base in pairs(bases) do sorted[#sorted + 1] = base end
    table.sort(sorted)
    local list = { "" }
    for i = 1, math.min(#sorted, 10) do
        if i > 1 then list[#list + 1] = ", " end
        list[#list + 1] = planet_name(sorted[i])
    end
    return list
end

--- bnm-<from>: a copy of the vanilla entity with no heating need. Its name
--- keeps the vanilla entity's own as __2__, so MTS's "Passive Radar" shows.
local function no_freeze(type_name, from, planets)
    local vanilla = data.raw[type_name][from]
    local e = variant.make({
        type = type_name, from = from, name = "bnm-" .. from,
        localised_name = { "entity-name.bnm-" .. from, planets,
                           vanilla.localised_name or { "entity-name." .. from } },
        localised_description = { "entity-description.bnm-" .. from, planets },
    })
    e.heating_energy = "0kW"
    data:extend({ e })
end

-- ─── Profiles ───────────────────────────────────────────────────────────

local function sorted_planet_names()
    local names = {}
    for name in pairs(data.raw.planet or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local tuned    = {}   -- base planet -> profile fields shared by its copies
local freezing = {}   -- base planets whose entities freeze
local planets  = {}   -- planet name -> profile

for _, name in ipairs(sorted_planet_names()) do
    local planet = data.raw.planet[name]
    local base = base_of(name)
    tuned[base] = tuned[base] or tune(base, sun_of(planet))
    local cold = planet.entities_require_heating == true
    if cold then freezing[base] = true end
    planets[name] = {
        base        = base,
        solar_panel = tuned[base].solar_panel,
        accumulator = tuned[base].accumulator,
        fulgora     = tuned[base].fulgora == true,
        freezing    = cold,
    }
end

if next(freezing) then
    local names = planet_list(freezing)
    no_freeze("radar", "radar", names)
    no_freeze("inserter", "inserter", names)
end

data:extend({
    { type = "mod-data", name = PROFILES, data = { planets = planets } },
})
