-- scripts/base/migration.lua
-- Upgrades 0.1.x base records. 0.1.x kept one `provider` chest per base and
-- had no home/outpost flags; it placed the home base on the team's Nauvis
-- and outposts elsewhere, every base from the Nauvis blueprint.

local blueprints = require("scripts.blueprints")
local geometry   = require("scripts.base.geometry")
local profiles   = require("scripts.base.profiles")
local records    = require("scripts.base.records")

local M = {}

-- The planet 0.1.x put every home base on, and built every base's plan for.
local HOME_PLANET = profiles.HOME_PLANET

--- 0.1.x kept one `provider` chest. Re-find the base's passive provider and
--- storage chests in its footprint.
local function migrate_chests(surface_name, base, area)
    base.providers, base.storage_chests = {}, {}
    base.provider = nil
    local surface = game.surfaces[surface_name]
    if not (surface and surface.valid and area) then return end
    local chests = surface.find_entities_filtered{
        area = area, force = base.force, type = "logistic-container",
    }
    for _, chest in pairs(chests) do records.add_chest(base, chest) end
end

--- 0.1.x placed the home base on the team's Nauvis and outposts elsewhere.
local function on_home_planet(surface_name)
    local surface = game.surfaces[surface_name]
    local base = surface and surface.valid and profiles.profile_for(surface).base
        or profiles.base_planet_name(surface_name)
    return base == HOME_PLANET
end

--- Give every record without chest lists its providers and storage chests.
--- The footprint all 0.1.x bases share is decoded once, and only if needed.
local function migrate_chest_lists()
    local area, decoded = nil, false
    for surface_name, base in pairs(storage.bnm_base) do
        if base.providers == nil then
            if not decoded then
                decoded = true
                local plan = blueprints.plan_for({ base = HOME_PLANET }, true)
                area = plan and geometry.footprint_area(geometry.BASE_ORIGIN, plan)
            end
            migrate_chests(surface_name, base, area)
        end
    end
end

--- Flag every record without a role: the home is the base on the team's
--- Nauvis; any other is an outpost.
local function migrate_roles()
    for surface_name, base in pairs(storage.bnm_base) do
        if base.home == nil and base.outpost == nil then
            base.home    = on_home_planet(surface_name) and records.home_of(base.force) == nil
            base.outpost = not base.home
        end
    end
end

--- Upgrade 0.1.x base records: the provider chest lists, and the home/outpost
--- flags (the home is the base on the team's Nauvis; any other is an
--- outpost). Idempotent; call from on_configuration_changed.
function M.migrate()
    storage.bases_placed = storage.bases_placed or {}
    storage.bnm_base     = storage.bnm_base or {}
    migrate_chest_lists()
    migrate_roles()
end

return M
