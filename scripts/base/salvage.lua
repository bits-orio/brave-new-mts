-- scripts/base/salvage.lua
-- The salvage pool: what a cleared site held, gathered before the build and
-- delivered into the new base after its kit, so salvage never crowds out the
-- kit. At home it is the crash site's loot; on a re-founded outpost, the lost
-- base's leftovers and whatever the team built around them. What no chest or
-- pad can hold is spilled for the robots (scripts/item_delivery.lua).

local item_delivery = require("scripts.item_delivery")
local geometry      = require("scripts.base.geometry")
local landing_pad   = require("scripts.base.landing_pad")
local records       = require("scripts.base.records")

local M = {}

-- How far around the spawn origin to sweep for crash-site debris. The freeplay
-- wreckage sits near (0,0) -- where MTS spawns the team -- while the base is
-- offset to the chunk centre, so the sweep must cover the whole spawn area, not
-- just the base footprint.
local CRASH_SEARCH_RADIUS = 96

-- Never swept as a leftover: a body, a pod still flying down, robots in the air.
local SWEEP_SKIP = {
    ["character"]          = true,
    ["cargo-pod"]          = true,
    ["construction-robot"] = true,
    ["logistic-robot"]     = true,
}

-- Salvage fills the chests robots empty on their own, storage chests first,
-- then the landing pad. Requester and buffer chests are left out: no robot
-- takes an unrequested item back out of either (a requester draws on a
-- buffer only when set to), and salvage in the roboport's feeder would crowd
-- out the robots it requests.
local SALVAGE_MODES = { "storage", "passive-provider", "active-provider" }

-- ─── Gathering ───────────────────────────────────────────────────────

--- All crash-site-spaceship* entity prototype names (the ship plus every wreck
--- piece), discovered generically so mod-added variants are covered too.
local function crash_site_names()
    local names = {}
    for name in pairs(prototypes.entity) do
        if name:find("^crash%-site") then names[#names + 1] = name end
    end
    return names
end

--- Pool the contents of all crash-site debris around the spawn, then remove
--- it. The wreck pieces are containers holding the freeplay starting items;
--- draining them lands the loot in the team's chests instead of deleting it
--- with the wreckage. Runs before the build so the (large) ship hull can't
--- block base entities from placing.
function M.collect_crash_debris(surface, pool)
    local names = crash_site_names()
    if #names == 0 then return end
    local R = CRASH_SEARCH_RADIUS
    for _, e in pairs(surface.find_entities_filtered{ name = names, area = { { -R, -R }, { R, R } } }) do
        if e.valid then
            item_delivery.pool_contents(e, pool)
            e.destroy()
        end
    end
end

--- How many of each entity a starter base is built with: the blueprint's,
--- after the planet's swaps, and the landing pad. All are normal quality.
local function base_counts(plan)
    local counts = { [landing_pad.PAD_NAME] = 1 }
    for _, e in pairs(plan.entities) do counts[e.name] = (counts[e.name] or 0) + 1 end
    return counts
end

--- True if `entity` may be one of the old base's own buildings, which the new
--- base replaces; it uses up one of its name in `budget`. Past one base's
--- worth of a name, or at any other quality, it is something the team built.
--- A replacement the team built for a destroyed base part counts as a base
--- part: the new base re-supplies it.
local function take_base_part(entity, budget)
    local left = entity.quality.name == "normal" and budget[entity.name] or 0
    if left == 0 then return false end
    budget[entity.name] = left - 1
    return true
end

--- Pool the item that places `entity`, the one robots would build it from.
local function pool_placing_item(entity, pool)
    local items = entity.prototype.items_to_place_this
    local item  = items and items[1]
    if item then item_delivery.pool_add(pool, item.name, entity.quality.name, item.count) end
end

--- A lost outpost being re-founded leaves its entities (unlocked by
--- lose_outpost), their ghosts and whatever the team built around them in
--- the site. Pool what they hold and destroy them, so nothing blocks the new
--- build and no item is lost. What the team built also comes back as the item
--- that places it. Up to one base's worth of the base's own buildings
--- (base_counts of `plan`) does not, since the new base replaces them.
function M.sweep_leftovers(force, surface, area, pool, plan)
    local budget = base_counts(plan)
    local n = 0
    for _, e in pairs(surface.find_entities_filtered{ area = area, force = force }) do
        if e.valid and not SWEEP_SKIP[e.type] then
            item_delivery.pool_contents(e, pool)
            if not take_base_part(e, budget) then pool_placing_item(e, pool) end
            e.destroy()
            n = n + 1
        end
    end
    if n > 0 then
        log("[brave-new-mts] swept " .. n .. " leftover entities from the base site on " .. surface.name)
    end
end

-- ─── Delivering ──────────────────────────────────────────────────────

--- Everything salvage may fill, in order (see SALVAGE_MODES).
local function salvage_targets(built)
    local targets = {}
    for _, mode in ipairs(SALVAGE_MODES) do
        for _, chest in ipairs(built.chests) do
            if chest.valid and chest.prototype.logistic_mode == mode then
                targets[#targets + 1] = chest
            end
        end
    end
    local pad = built.pad and built.pad.valid
        and built.pad.get_inventory(defines.inventory.cargo_landing_pad_main)
    if pad then targets[#targets + 1] = pad end
    return targets
end

--- Deliver the salvage pool into the new base; spill what no chest or pad
--- can hold around the roboport, for the robots to bring in.
function M.deliver(pool, built, force, surface)
    local left = item_delivery.deliver(pool, salvage_targets(built), records.network_of(built))
    if #left == 0 then return end
    item_delivery.spill(left, { surface = surface, position = geometry.BASE_ORIGIN, force = force })
    log("[brave-new-mts] spilled salvage for the robots to bring in on " .. surface.name
        .. ": " .. item_delivery.describe(left))
end

return M
