-- scripts/base/salvage.lua
-- The salvage pool: what a cleared site held, gathered before the build and
-- delivered into the new base after its kit, so salvage never crowds out the
-- kit. At home it is the crash site's loot; on a re-founded outpost, the lost
-- base's leftovers and whatever the team built around them. Items move as
-- whole stacks, so a vehicle keeps its equipment and a blueprint what it
-- holds. What no chest or pad can hold is spilled for the robots
-- (scripts/item_delivery.lua).

local item_delivery = require("scripts.item_delivery")
local landing_pad   = require("scripts.base.landing_pad")
local records       = require("scripts.base.records")

local M = {}

-- How far around the spawn origin to sweep for crash-site debris. The freeplay
-- wreckage sits near (0,0) -- where MTS spawns the team -- while the base is
-- offset to the chunk centre, so the sweep must cover the whole spawn area, not
-- just the base footprint.
local CRASH_SEARCH_RADIUS = 96

-- Never swept as a leftover: a body, a pod still flying down, robots in the
-- air, and a spider's legs. Removing a leg removes its whole spider, so its
-- body takes them along, and a spider parked outside the site with a leg
-- reaching in is left alone.
local SWEEP_SKIP = {
    ["character"]          = true,
    ["cargo-pod"]          = true,
    ["construction-robot"] = true,
    ["logistic-robot"]     = true,
    ["spider-leg"]         = true,
}

-- Salvage fills the chests robots empty on their own, storage chests first,
-- then the landing pad. Requester and buffer chests are left out: no robot
-- takes an unrequested item back out of either (a requester draws on a
-- buffer only when set to), and salvage in the roboport's feeder would crowd
-- out the robots it requests.
local SALVAGE_MODES = { "storage", "passive-provider", "active-provider" }

--- A new, empty salvage pool (scripts/item_delivery.lua). M.deliver frees it.
M.new_pool = item_delivery.new_pool

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
        if e.valid and item_delivery.take(e, pool) then e.destroy() end
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

--- True if an item places `entity`, the one robots would build it from.
local function has_placing_item(entity)
    local items = entity.prototype.items_to_place_this
    return items ~= nil and items[1] ~= nil
end

--- Clear one leftover into `pool`. What the team built is mined, so it comes
--- back as the item that places it (a vehicle's with its equipment grid)
--- along with everything it held; anything else is emptied and destroyed.
--- What cannot be removed yet (a rail under a train) is left untouched:
--- mining it would take the train with it. True once it is gone.
local function sweep_one(job, pool)
    local e = job.entity
    if not e.valid then return true end
    if not e.can_be_destroyed() then return false end
    if job.refund then return item_delivery.mine(e, pool) end
    return item_delivery.take(e, pool) and e.destroy()
end

--- Sweep each job's entity into `pool`. Returns the jobs still standing.
local function sweep(jobs, pool)
    local stuck = {}
    for _, job in ipairs(jobs) do
        if not sweep_one(job, pool) then stuck[#stuck + 1] = job end
    end
    return stuck
end

--- Log how many leftovers were swept, and name any left standing.
local function log_sweep(surface, swept, stuck)
    local where = " leftover entities from the base site on " .. surface.name
    if swept > 0 then log("[brave-new-mts] swept " .. swept .. where) end
    if #stuck == 0 then return end
    local names = {}
    for _, job in ipairs(stuck) do names[#names + 1] = job.entity.name end
    log("[brave-new-mts] could not sweep " .. #stuck .. where .. ": " .. table.concat(names, ", "))
end

--- A lost outpost being re-founded leaves its entities (unlocked by
--- lose_outpost), their ghosts and whatever the team built around them in
--- the site. Move what they hold into the pool and remove them, so nothing
--- blocks the new build and no item is lost. What the team built also comes
--- back as the item that places it. Up to one base's worth of the base's own
--- buildings (base_counts of `plan`) does not, since the new base replaces
--- them. What could not go on the first pass (a rail under a train) is tried
--- once more, after what stood on it. `ctx` is the founding context
--- (scripts/base/founding.lua): its force's entities in its site are swept.
function M.sweep_leftovers(ctx, pool)
    local budget, jobs = base_counts(ctx.plan), {}
    local found = ctx.surface.find_entities_filtered{ area = ctx.site.area, force = ctx.force }
    for _, e in pairs(found) do
        if e.valid and not SWEEP_SKIP[e.type] then
            local refund = not take_base_part(e, budget) and has_placing_item(e)
            jobs[#jobs + 1] = { entity = e, refund = refund }
        end
    end
    local stuck = sweep(sweep(jobs, pool), pool)
    log_sweep(ctx.surface, #jobs - #stuck, stuck)
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

--- Deliver the salvage pool into the base `built` for the founding context
--- `ctx`; spill what no chest or pad can hold around the roboport, for the
--- robots to bring in. Frees the pool.
function M.deliver(ctx, pool, built)
    item_delivery.deliver_pool(pool, salvage_targets(built), records.network_of(built))
    if not pool.is_empty() then
        local left = pool.get_contents()
        item_delivery.spill_pool(pool, { surface = ctx.surface, position = ctx.origin, force = ctx.force })
        log("[brave-new-mts] spilled salvage for the robots to bring in on " .. ctx.surface.name
            .. ": " .. item_delivery.describe(left))
    end
    pool.destroy()
end

return M
