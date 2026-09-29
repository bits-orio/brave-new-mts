-- scripts/base/builder.lua
-- Builds the blueprint (scripts/blueprints.lua, swapped per planet) as REAL
-- entities centred on its roboport, each with its own blueprint settings.
-- There are no bots or materials yet to build ghosts. The roboport starts
-- stocked and charged, the accumulators charged, and the power core locked
-- (scripts/base/power_core.lua).

local power_core = require("scripts.base.power_core")
local records    = require("scripts.base.records")

local M = {}

-- Robots seeded into the roboport when the runtime setting is missing; the
-- same as the settings' default.
local DEFAULT_ROBOTS = 50

-- Repair packs seeded into the central roboport's material slots so the
-- construction network auto-repairs battle damage from the start.
local STARTER_REPAIR_PACKS = 10

-- Joules to pre-load into each accumulator so the base survives night one.
-- Clamped to the accumulator's actual buffer size.
local ACCUMULATOR_SEED_ENERGY = 5000000  -- 5 MJ

-- Blueprint entity fields that are not create_entity parameters. Everything
-- else (request filters, the sign's text and icon, recipes, filters, ...) is
-- passed straight through: create_entity takes the blueprint's own formats.
local NOT_PARAMS = { entity_number = true, wires = true, tags = true, items = true }

-- ─── Seeding ─────────────────────────────────────────────────────────

local function bot_counts()
    local c = settings.global["bnm-construction-robots"]
    local l = settings.global["bnm-logistic-robots"]
    return (c and c.value) or DEFAULT_ROBOTS, (l and l.value) or DEFAULT_ROBOTS
end

--- Fill a freshly-created roboport with starter bots, repair packs and a full
--- energy buffer.
local function seed_roboport(roboport)
    local construction, logistic = bot_counts()
    local inv = roboport.get_inventory(defines.inventory.roboport_robot)
    if inv then
        if construction > 0 then inv.insert{ name = "construction-robot", count = construction } end
        if logistic    > 0 then inv.insert{ name = "logistic-robot",     count = logistic }    end
    end
    local mat = roboport.get_inventory(defines.inventory.roboport_material)
    if mat and STARTER_REPAIR_PACKS > 0 then
        mat.insert{ name = "repair-pack", count = STARTER_REPAIR_PACKS }
    end
    -- Start charged so bots can fly before the power network spins up.
    roboport.energy = roboport.electric_buffer_size or roboport.energy
end

--- Pre-charge an accumulator so the base has stored power on the first night.
local function seed_accumulator(accumulator)
    local cap = accumulator.electric_buffer_size or ACCUMULATOR_SEED_ENERGY
    accumulator.energy = math.min(ACCUMULATOR_SEED_ENERGY, cap)
end

-- ─── Creating ────────────────────────────────────────────────────────

--- Where a blueprint position lands in the world, origin-centred on the
--- roboport (plan.ox, plan.oy).
local function world_position(origin, plan, position)
    return { x = origin.x + position.x - plan.ox, y = origin.y + position.y - plan.oy }
end

--- Lay the blueprint's floor tiles, origin-centred on the roboport like the
--- entities. No-op if the blueprint has no tiles.
function M.place_tiles(surface, origin, plan)
    if #plan.tiles == 0 then return end
    local tiles = {}
    for _, t in pairs(plan.tiles) do
        tiles[#tiles + 1] = { name = t.name, position = world_position(origin, plan, t.position) }
    end
    surface.set_tiles(tiles)
end

--- Create one blueprint entity as a real entity, with its blueprint settings.
local function create_from_blueprint(ctx, e)
    if not prototypes.entity[e.name] then
        log("[brave-new-mts] blueprint references unknown entity '" .. tostring(e.name) .. "' -- skipping")
        return nil
    end
    local params = {}
    for k, v in pairs(e) do
        if not NOT_PARAMS[k] then params[k] = v end
    end
    params.position    = world_position(ctx.origin, ctx.plan, e.position)
    params.force       = ctx.force
    params.raise_built = true
    local created = ctx.surface.create_entity(params)
    if not created then log("[brave-new-mts] failed to place '" .. e.name .. "' (collision?)") end
    return created
end

--- 2.0.77 takes a logistic chest's request_filters in the blueprint's own
--- {sections = ...} form, not the documented SlotFilter array. Log if an
--- engine update stops honouring it, so a lost request is never silent.
local function check_requests(e, created)
    local sections = e.request_filters and e.request_filters.sections
    local wanted = sections and sections[1] and sections[1].filters
    if not (wanted and #wanted > 0) then return end
    local got = created.get_logistic_sections()
    local first = got and got.get_section(1)
    if first and first.filters_count > 0 then return end
    log("[brave-new-mts] '" .. e.name .. "' lost its blueprint logistic request")
end

--- Seed, file and lock one created entity. The FIRST roboport is the base's
--- heart: never minable, whatever the team has unlocked.
local function register_created(built, created, e, locked)
    if created.type == "roboport" and not built.roboport then
        built.roboport = created
        created.minable_flag = false
        seed_roboport(created)
        return
    end
    if created.type == "accumulator" then seed_accumulator(created) end
    if created.type == "logistic-container" then
        records.add_chest(built, created)
        built.chests[#built.chests + 1] = created
    end
    power_core.lock(built, created, locked)
    check_requests(e, created)
end

--- Build every blueprint entity of a founding context (scripts/base/founding.lua),
--- origin-centred on the roboport. Returns
--- { roboport, protected, providers, storage_chests, chests }, where `chests`
--- is every logistic chest (only salvage uses it, so it is not recorded).
function M.build(ctx)
    local built = { protected = {}, providers = {}, storage_chests = {}, chests = {} }
    for _, e in pairs(ctx.plan.entities) do
        local created = create_from_blueprint(ctx, e)
        if created then register_created(built, created, e, ctx.locked) end
    end
    return built
end

return M
