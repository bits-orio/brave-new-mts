-- scripts/item_delivery.lua
-- Moves items into a base without losing any. starter_base.lua uses it to
-- pool what a cleared site held (crash-site loot, a lost outpost's leftovers),
-- to fill a base's chests with kits and salvage, and to spill whatever no
-- chest can hold onto the ground, marked for the team's robots to bring in.
--
-- A pool is keyed by "name/quality"; each value is a {name, quality, count}
-- stack. An item list is an array of the same stacks.

local M = {}

-- Entities that carry items on belt lanes rather than in an inventory.
local BELT_TYPES = {
    ["transport-belt"]   = true,
    ["underground-belt"] = true,
    ["splitter"]         = true,
    ["lane-splitter"]    = true,
    ["loader"]           = true,
    ["loader-1x1"]       = true,
    ["linked-belt"]      = true,
}

--- Add `count` of an item to `pool`.
function M.pool_add(pool, name, quality, count)
    local key   = name .. "/" .. quality
    local stack = pool[key] or { name = name, quality = quality, count = 0 }
    stack.count = stack.count + count
    pool[key]   = stack
end

local function pool_counts(pool, counts)
    for _, c in pairs(counts) do M.pool_add(pool, c.name, c.quality, c.count) end
end

--- Add everything `entity` holds to `pool`: its inventories, the items on its
--- belt lanes and an inserter's hand.
function M.pool_contents(entity, pool)
    for i = 1, entity.get_max_inventory_index() do
        local inv = entity.get_inventory(i)
        if inv and inv.valid then pool_counts(pool, inv.get_contents()) end
    end
    if BELT_TYPES[entity.type] then
        for i = 1, entity.get_max_transport_line_index() do
            pool_counts(pool, entity.get_transport_line(i).get_contents())
        end
    end
    local hand = entity.type == "inserter" and entity.held_stack
    if hand and hand.valid_for_read then
        M.pool_add(pool, hand.name, hand.quality.name, hand.count)
    end
end

--- Insert one stack across `targets` (chests or inventories) in order, then
--- the logistic network. Returns how many did not fit.
local function insert_stack(stack, targets, network)
    if not (stack.count and stack.count > 0) then return 0 end
    if not prototypes.item[stack.name] then
        log("[brave-new-mts] item '" .. tostring(stack.name) .. "' is not a known item -- skipping")
        return 0
    end
    local left = stack.count
    for _, target in ipairs(targets) do
        if left == 0 then return 0 end
        if target.valid then
            left = left - target.insert{ name = stack.name, count = left, quality = stack.quality }
        end
    end
    if left > 0 and network and network.valid then
        left = left - network.insert{ name = stack.name, count = left, quality = stack.quality }
    end
    return left
end

--- Deliver an item list (or a pool) across `targets`, then the network.
--- Returns the stacks that did not fit, as an item list (empty when all did).
function M.deliver(items, targets, network)
    local left = {}
    for _, stack in pairs(items) do
        local n = insert_stack(stack, targets, network)
        if n > 0 then left[#left + 1] = { name = stack.name, quality = stack.quality, count = n } end
    end
    return left
end

--- "12x iron-plate, 3x stone" for a log line.
function M.describe(stacks)
    local parts = {}
    for _, stack in ipairs(stacks) do parts[#parts + 1] = stack.count .. "x " .. stack.name end
    return table.concat(parts, ", ")
end

--- Spill `stacks` on the ground around `at.position` on `at.surface`, marked
--- for deconstruction by `at.force`, so its robots carry them into a chest as
--- one frees up. Each goes down in whole-stack piles: one item per entity
--- would scatter thousands of entities over the base.
function M.spill(stacks, at)
    for _, stack in ipairs(stacks) do
        local size = prototypes.item[stack.name].stack_size
        local left = stack.count
        while left > 0 do
            local n = math.min(left, size)
            at.surface.spill_item_stack{
                position = at.position, force = at.force,
                stack = { name = stack.name, count = n, quality = stack.quality },
                allow_belts = false, drop_full_stack = true,
            }
            left = left - n
        end
    end
end

return M
