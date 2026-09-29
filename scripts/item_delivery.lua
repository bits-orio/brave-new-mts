-- scripts/item_delivery.lua
-- Moves items into a base without losing any. The starter base uses it to
-- pool what a cleared site held (crash-site loot, a lost outpost's leftovers),
-- to fill a base's chests with kits and salvage, and to spill whatever no
-- chest can hold onto the ground, marked for the team's robots to bring in.
--
-- A pool is a script inventory (game.create_inventory) that grows as things
-- are moved in. Items go in and out of it as whole stacks, so each keeps its
-- data: a vehicle's equipment grid, a set-up blueprint, its spoilage.
-- Whoever makes a pool destroys it once it is delivered. An item list (a
-- kit) is an array of {name, quality, count} stacks.

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

local POOL_SIZE     = 100     -- the slots a new pool starts with
local POOL_MAX_SIZE = 65535   -- the most slots a script inventory can have
-- Slots an entity may need beyond its inventories and belt lanes: the
-- item(s) mining it gives and an inserter's hand.
local SPARE_SLOTS   = 4

-- ─── Pools ───────────────────────────────────────────────────────────

--- A new, empty pool.
function M.new_pool()
    return game.create_inventory(POOL_SIZE)
end

--- The most stacks `entity` can give up: a slot per inventory slot and per
--- item on its belt lanes, plus SPARE_SLOTS.
local function stacks_in(entity)
    local n = SPARE_SLOTS
    for i = 1, entity.get_max_inventory_index() do
        local inv = entity.get_inventory(i)
        if inv and inv.valid then n = n + #inv end
    end
    if BELT_TYPES[entity.type] then
        for i = 1, entity.get_max_transport_line_index() do n = n + #entity.get_transport_line(i) end
    end
    return n
end

--- Grow `pool` until it can take every stack `entity` gives up. False when
--- that would pass POOL_MAX_SIZE.
local function make_room(pool, entity)
    local short = stacks_in(entity) - pool.count_empty_stacks()
    if short <= 0 then return true end
    if #pool + short > POOL_MAX_SIZE then return false end
    pool.resize(#pool + short)
    return true
end

--- Move `stack` into `into` (an inventory, a chest or a logistic network),
--- as much of it as fits, data and all. True if all of it went.
local function move_stack(stack, into)
    stack.count = stack.count - into.insert(stack)
    return not stack.valid_for_read
end

--- Move what `entity` holds into `pool` as whole stacks: its inventories and
--- an inserter's hand. Belt lanes are M.mine's: nothing emptied this way (a
--- lost base's own buildings, crash wreckage, what no item places) is a
--- belt. False, with nothing moved, when the pool cannot grow to hold it.
function M.take(entity, pool)
    if not make_room(pool, entity) then return false end
    for i = 1, entity.get_max_inventory_index() do
        local inv = entity.get_inventory(i)
        if inv and inv.valid then
            for j = 1, #inv do
                if inv[j].valid_for_read then move_stack(inv[j], pool) end
            end
        end
    end
    local hand = entity.type == "inserter" and entity.held_stack
    if hand and hand.valid_for_read then move_stack(hand, pool) end
    return true
end

--- Mine `entity` into `pool` as a player would, removing it: the item that
--- places it (a vehicle's with its equipment grid), everything it holds as
--- whole stacks, the items on its belt lanes and an inserter's hand. True if
--- it was mined.
function M.mine(entity, pool)
    if not make_room(pool, entity) then return false end
    return entity.mine{ inventory = pool, force = false, ignore_minable = true, raise_destroyed = false }
end

--- Deliver one pool stack, whole, across `targets` in order, then the network.
local function deliver_stack(stack, targets, network)
    for _, target in ipairs(targets) do
        if target.valid and move_stack(stack, target) then return end
    end
    if network and network.valid then move_stack(stack, network) end
end

--- Deliver every stack in `pool` across `targets` (chests or inventories) in
--- order, then the logistic network. What fits nowhere stays in the pool.
function M.deliver_pool(pool, targets, network)
    for i = 1, #pool do
        local stack = pool[i]
        if stack.valid_for_read then deliver_stack(stack, targets, network) end
    end
end

--- Spill what is left in `pool` around `at.position` on `at.surface`, marked
--- for deconstruction by `at.force`, so its robots carry it into a chest as
--- one frees up. Each stack goes down as one pile: one item per entity would
--- scatter thousands of entities over the base.
function M.spill_pool(pool, at)
    for i = 1, #pool do
        local stack = pool[i]
        if stack.valid_for_read then
            at.surface.spill_item_stack{
                position = at.position, force = at.force, stack = stack,
                allow_belts = false, drop_full_stack = true,
            }
            stack.clear()
        end
    end
end

-- ─── Item lists ──────────────────────────────────────────────────────

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

--- Deliver an item list across `targets`, then the network. Returns the
--- stacks that did not fit, as an item list (empty when all did).
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

return M
