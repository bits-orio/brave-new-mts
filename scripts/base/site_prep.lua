-- scripts/base/site_prep.lua
-- Gets the site ready to build on: the ground generated, enemies inside the
-- roboport's construction area removed (worms outrange the footprint and
-- shoot down robots), cargo moved aside (it holds the team's items), the
-- salvage pooled (scripts/base/salvage.lua), then obstacles and resources
-- cleared.

local chunks  = require("scripts.base.chunks")
local salvage = require("scripts.base.salvage")

local M = {}

-- Cargo that may already sit in the site: a landed pod's container, or a pod.
local CARGO_TYPES = { "temporary-container", "cargo-pod" }
local CARGO_MARGIN = 6   -- push clear of the site's edge before settling
-- find_non_colliding_position's search radius and precision for moved cargo.
local CARGO_SEARCH_RADIUS, CARGO_SEARCH_PRECISION = 32, 1

-- What stands in the way of the build, or would leave the base on ore.
local OBSTACLE_TYPES = {
    "tree", "simple-entity", "simple-entity-with-owner", "cliff", "fish", "resource",
}

--- Remove enemies inside the roboport's construction area. That area is a
--- SQUARE of half-width construction_radius around the roboport, not a circle:
--- a radius query would miss its corners (about a fifth of the area). MTS
--- clones main Nauvis into each team's copy, so biters that expanded into the
--- empty starting area arrive with the surface; worms outrange the base and
--- shoot down its robots. Destroyed rather than killed: no loot, kill
--- statistics or pollution-driven evolution.
local function clear_enemies(surface, origin, radius)
    local n = 0
    local found = surface.find_entities_filtered{
        area  = { { origin.x - radius, origin.y - radius }, { origin.x + radius, origin.y + radius } },
        force = "enemy",
    }
    for _, e in pairs(found) do
        if e.valid then
            e.destroy()
            n = n + 1
        end
    end
    if n > 0 then
        log("[brave-new-mts] cleared " .. n .. " enemy entities around the base on " .. surface.name)
    end
end

--- A spot just past whichever side edge of `area` the cargo at `p` is nearest.
local function beside(area, p)
    return {
        x = (p.x < (area[1][1] + area[2][1]) / 2)
            and area[1][1] - CARGO_MARGIN or area[2][1] + CARGO_MARGIN,
        y = p.y,
    }
end

-- Cargo a team has already dropped to this planet lands near origin as a
-- "cargo-pod-container" (type temporary-container); a pod may also be present.
-- We must NOT destroy it -- it holds the player's items. Instead, scoot any
-- such cargo that overlaps the site just outside it. Returns silently if
-- there's nowhere clear to move a pod: the leftover sweep then pools what it
-- holds into the new base's chests.
local function relocate_cargo(surface, area)
    local cargo = surface.find_entities_filtered{ area = area, type = CARGO_TYPES }
    for _, e in pairs(cargo) do
        if e.valid then
            local target = beside(area, e.position)
            local pos = surface.find_non_colliding_position(e.name, target,
                CARGO_SEARCH_RADIUS, CARGO_SEARCH_PRECISION)
            if pos then e.teleport(pos) end
        end
    end
end

--- Clear the site so the base places cleanly and never sits on ore.
local function clear_obstacles(surface, area)
    local obstacles = surface.find_entities_filtered{ area = area, type = OBSTACLE_TYPES }
    for _, e in pairs(obstacles) do
        if e.valid then e.destroy() end
    end
    surface.destroy_decoratives{ area = area }
end

--- Get the site ready to build on. Returns the pool of salvaged items (crash
--- loot at home, leftovers of a lost base) for the new chests;
--- salvage.deliver frees it.
function M.prepare(force, surface, origin, site, plan, home)
    chunks.generate(surface, origin)
    local roboport = prototypes.entity[plan.roboport]
    clear_enemies(surface, origin, roboport.construction_radius or 0)
    relocate_cargo(surface, site.area)
    local pool = salvage.new_pool()
    if home then salvage.collect_crash_debris(surface, pool) end
    salvage.sweep_leftovers(force, surface, site.area, pool, plan)
    clear_obstacles(surface, site.area)
    return pool
end

return M
