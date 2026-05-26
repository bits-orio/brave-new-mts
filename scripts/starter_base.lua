-- scripts/starter_base.lua
-- Seeds a self-running starter base on a team surface so a character-free,
-- cheat-free team can bootstrap a bot factory. Placement is idempotent per
-- surface (storage.bases_placed[surface.name]).
--
-- Strategy (the blueprint's roboport is detected generically by prototype type):
--   1. Import the blueprint and centre it on its roboport, so the roboport
--      lands at the team's spawn origin (MTS always spawns at 0,0).
--   2. CLEAR the footprint first: remove obstacles (trees, rocks, cliffs, fish)
--      so no entity fails to place, and resources (ore/oil) so the base never
--      sits on an ore patch. The base has no miners -- the team mines elsewhere.
--   3. Create the blueprint's entities as REAL working entities (not ghosts) --
--      there are no bots or materials yet to build ghosts. Power poles
--      auto-connect on placement, so explicit circuit wires aren't restored.
--   4. Seed power: charge accumulators and the roboport buffer so a night-one
--      base doesn't deadlock before solar ramps.
--   5. Seed bots into the roboport (counts from mod settings).

local blueprints = require("scripts.blueprints")

local M = {}

-- The base is centred on a CHUNK CENTRE (16,16), not the spawn corner (0,0).
-- The roboport's construction area reveals whole chunks around the roboport's
-- chunk; that reveal is only symmetric when the roboport sits at the chunk's
-- centre -- otherwise it spills a chunk toward +x/+y. Players never stand here
-- (their character is parked in the pen), and remote view is centred here too.
M.BASE_ORIGIN = { x = 16, y = 16 }

-- Anti-soft-lock starter kit, dropped into a passive provider chest in the
-- blueprint so the logistic network has stock to bootstrap from. Edit
-- names/counts here to retune. Any name that isn't a valid item is skipped
-- (and logged) at placement time.
M.STARTER_ITEMS = {
    { name = "transport-belt",        count = 100 },
    { name = "medium-electric-pole",  count = 20  },
    { name = "inserter",              count = 12  },
    { name = "pipe",                  count = 10  },
    { name = "burner-inserter",       count = 8   },
    { name = "underground-belt",      count = 4  },
    { name = "splitter",              count = 4  },
    { name = "pipe-to-ground",        count = 4  },
    { name = "small-lamp",            count = 4  },
    { name = "stone-furnace",         count = 4   },
    { name = "assembling-machine-2",  count = 1   },
    { name = "electric-mining-drill", count = 1   },
    { name = "steam-engine",          count = 2   },
    { name = "lab",                   count = 2   },
    { name = "boiler",                count = 2   },
    { name = "offshore-pump",         count = 1   },
    { name = "advanced-circuit",      count = 4  },
    -- Defense + early mid-tier bootstrap.
    { name = "gun-turret",            count = 4   },
    { name = "firearm-magazine",      count = 100  },
}

-- Joules to pre-load into each accumulator so the base survives night one.
-- Clamped to the accumulator's actual buffer size.
local ACCUMULATOR_SEED_ENERGY = 5000000  -- 5 MJ

-- Extra tiles cleared around the blueprint's footprint.
local CLEAR_MARGIN = 3

-- Whole chunks of margin to chart (reveal) around the base footprint, so the
-- base is visible in remote view (no character stands on the team surface).
-- Charting works in whole 32-tile chunks; expanding the footprint's chunk span
-- equally on all sides keeps the reveal centred on the base.
local CHART_CHUNK_MARGIN = 3

-- ─── Internal helpers ──────────────────────────────────────────────────

local function bot_counts()
    local c = settings.global["bnm-construction-robots"]
    local l = settings.global["bnm-logistic-robots"]
    return (c and c.value) or 100, (l and l.value) or 50
end

-- Repair packs seeded into the central roboport's material slots so the
-- construction network auto-repairs battle damage from the start.
local STARTER_REPAIR_PACKS = 10

--- Fill a freshly-created roboport with starter bots, repair packs and a full
--- energy buffer.
local function seed_roboport(roboport, construction, logistic)
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

--- Drop the anti-soft-lock starter kit into a passive provider chest, so the
--- logistic network has stock to bootstrap the first builds from. Unknown item
--- names are skipped (logged) rather than crashing the placement.
local function seed_provider_chest(chest)
    for _, stack in ipairs(M.STARTER_ITEMS) do
        if stack.count and stack.count > 0 then
            if prototypes.item[stack.name] then
                chest.insert{ name = stack.name, count = stack.count }
            else
                log("[brave-new-mts] starter item '" .. tostring(stack.name)
                    .. "' is not a known item -- skipping")
            end
        end
    end
end

--- Pre-charge an accumulator so the base has stored power on the first night.
local function seed_accumulator(accumulator)
    local cap = accumulator.electric_buffer_size or ACCUMULATOR_SEED_ENERGY
    accumulator.energy = math.min(ACCUMULATOR_SEED_ENERGY, cap)
end

--- The roboport's blueprint position, used to offset every entity so the
--- roboport lands at the spawn origin. Detected by prototype type, so it works
--- for any roboport mod (K2 Roboports, vanilla, ...).
local function roboport_offset(bp_entities)
    for _, e in pairs(bp_entities) do
        local proto = prototypes.entity[e.name]
        if proto and proto.type == "roboport" then
            return e.position.x, e.position.y
        end
    end
    return 0, 0
end

--- Import a blueprint string and return its entity list (may be empty).
local function decode_blueprint(bp_string)
    local inv = game.create_inventory(1)
    inv.insert{ name = "blueprint", count = 1 }
    local stack = inv[1]
    local ok = pcall(function() stack.import_stack(bp_string) end)
    local entities = ok and stack.get_blueprint_entities() or nil
    local tiles    = ok and stack.get_blueprint_tiles() or nil
    inv.destroy()
    return entities or {}, tiles or {}
end

--- Lay the blueprint's floor tiles, origin-centred on the roboport like the
--- entities. No-op if the blueprint has no tiles.
local function place_tiles(surface, origin, bp_tiles, ox, oy)
    if #bp_tiles == 0 then return end
    local tiles = {}
    for _, t in pairs(bp_tiles) do
        tiles[#tiles + 1] = {
            name = t.name,
            position = { x = origin.x + t.position.x - ox,
                         y = origin.y + t.position.y - oy },
        }
    end
    surface.set_tiles(tiles)
end

--- World-space bounding box of the footprint once centred on the origin.
local function footprint_area(origin, bp_entities, ox, oy)
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for _, e in pairs(bp_entities) do
        local x, y = e.position.x - ox, e.position.y - oy
        if x < minx then minx = x end
        if x > maxx then maxx = x end
        if y < miny then miny = y end
        if y > maxy then maxy = y end
    end
    return {
        { origin.x + minx - CLEAR_MARGIN, origin.y + miny - CLEAR_MARGIN },
        { origin.x + maxx + CLEAR_MARGIN, origin.y + maxy + CLEAR_MARGIN },
    }
end

--- Clear the footprint so the base places cleanly and never sits on ore.
local function clear_footprint(surface, area)
    local obstacles = surface.find_entities_filtered{
        area = area,
        type = { "tree", "simple-entity", "simple-entity-with-owner", "cliff", "fish", "resource" },
    }
    for _, e in pairs(obstacles) do
        if e.valid then e.destroy() end
    end
    surface.destroy_decoratives{ area = area }
end

-- Cargo a team has already dropped to this planet lands near origin as a
-- "cargo-pod-container" (type temporary-container); a pod may also be present.
-- We must NOT destroy it -- it holds the player's items. Instead, scoot any
-- such cargo that overlaps the base footprint just outside it. Returns silently
-- if there's nowhere clear to move a pod (better to fail one base entity than
-- to delete a team's cargo).
local function relocate_cargo(surface, area)
    local cargo = surface.find_entities_filtered{
        area = area,
        type = { "temporary-container", "cargo-pod" },
    }
    local margin = 6  -- push clear of the footprint edge before settling
    for _, e in pairs(cargo) do
        if e.valid then
            -- Aim just past whichever footprint edge the cargo is nearest.
            local p = e.position
            local target = {
                x = (p.x < (area[1][1] + area[2][1]) / 2)
                    and area[1][1] - margin or area[2][1] + margin,
                y = p.y,
            }
            local pos = surface.find_non_colliding_position(e.name, target, 32, 1)
            if pos then e.teleport(pos) end
        end
    end
end

-- The power core kept NON-MINABLE until the team opts into "I know what I am
-- doing": losing any of it would strand the base. Everything else in the
-- starter base is minable from the start, so a team can freely redesign it.
-- The central roboport is always non-minable and is handled separately.
local PROTECTED_TYPES = {
    ["solar-panel"] = true,   -- power generation
    ["accumulator"] = true,   -- night-one storage
    ["lamp"]        = true,   -- the lights
}
local PROTECTED_NAMES = {
    ["substation"]           = true,  -- the two substations
    ["medium-electric-pole"] = true,  -- the two medium poles
}
local function is_power_core(proto)
    return PROTECTED_TYPES[proto.type] or PROTECTED_NAMES[proto.name] or false
end

--- Place all blueprint entities as real entities, origin-centred on the
--- roboport, seeding power and bots as they are created. Only the power core
--- (solar / accumulators / substations / main poles / lights) and the central
--- roboport are made non-minable, so the team can't accidentally strand itself;
--- everything else stays minable. Returns the roboport and the protected list.
local function build_base(force, surface, origin, bp_entities, ox, oy)
    local construction, logistic = bot_counts()
    local roboport, protected, provider = nil, {}, nil
    for _, e in pairs(bp_entities) do
        local proto = prototypes.entity[e.name]
        if not proto then
            log("[brave-new-mts] blueprint references unknown entity '"
                .. tostring(e.name) .. "' -- skipping")
        else
            local created = surface.create_entity{
                name        = e.name,
                position    = { x = origin.x + e.position.x - ox,
                                y = origin.y + e.position.y - oy },
                direction   = e.direction,
                force       = force,
                recipe      = e.recipe,
                raise_built = true,
            }
            if created then
                if proto.type == "roboport" then
                    roboport = created
                    created.minable = false  -- the heart of the base; never minable
                    seed_roboport(created, construction, logistic)
                else
                    if proto.type == "accumulator" then seed_accumulator(created) end
                    -- Stock the FIRST passive provider chest with the starter kit.
                    if not provider and proto.logistic_mode == "passive-provider" then
                        provider = created
                    end
                    -- Lock only the power core; the rest stays minable.
                    if is_power_core(proto) then
                        created.minable = false
                        protected[#protected + 1] = created
                    end
                end
            else
                log("[brave-new-mts] failed to place '" .. e.name .. "' (collision?)")
            end
        end
    end
    if provider then
        seed_provider_chest(provider)
    else
        log("[brave-new-mts] no passive provider chest in blueprint -- starter kit not placed")
    end
    return roboport, protected
end

--- Chart whole chunks symmetrically around the base footprint, so the reveal is
--- centred on the base (force.chart reveals whole 32-tile chunks; we work in
--- chunk units to avoid the chunk-boundary asymmetry of a raw tile box).
local function chart_base(force, surface, origin, bp_entities, ox, oy)
    local area = footprint_area(origin, bp_entities, ox, oy)
    local C = 32
    local cmin_x = math.floor(area[1][1] / C) - CHART_CHUNK_MARGIN
    local cmin_y = math.floor(area[1][2] / C) - CHART_CHUNK_MARGIN
    local cmax_x = math.floor(area[2][1] / C) + CHART_CHUNK_MARGIN
    local cmax_y = math.floor(area[2][2] / C) + CHART_CHUNK_MARGIN
    force.chart(surface, {
        { cmin_x * C,           cmin_y * C },
        { cmax_x * C + (C - 1), cmax_y * C + (C - 1) },
    })
end

-- ─── Public API ──────────────────────────────────────────────────────

--- Place a starter base for `force_name` on `surface` (idempotent).
function M.place(force_name, surface)
    if not (surface and surface.valid) then return end
    storage.bases_placed = storage.bases_placed or {}
    if storage.bases_placed[surface.name] then return end

    local force = game.forces[force_name]
    if not (force and force.valid) then return end

    local bp_string = blueprints.for_surface(surface)
    if not bp_string or bp_string == "" then return end  -- none configured yet

    local bp_entities, bp_tiles = decode_blueprint(bp_string)
    if #bp_entities == 0 then
        log("[brave-new-mts] blueprint for " .. surface.name .. " decoded to 0 entities")
        return
    end

    local origin = M.BASE_ORIGIN  -- chunk centre, so the roboport reveal is symmetric
    local ox, oy = roboport_offset(bp_entities)

    local area = footprint_area(origin, bp_entities, ox, oy)
    relocate_cargo(surface, area)  -- preserve any cargo the team already dropped here
    clear_footprint(surface, area)
    place_tiles(surface, origin, bp_tiles, ox, oy)
    local roboport, protected = build_base(force, surface, origin, bp_entities, ox, oy)

    -- Reveal the base on the map (no character stands here to chart it).
    chart_base(force, surface, origin, bp_entities, ox, oy)

    -- Track the base per surface so the minable toggle and the roboport
    -- loss-condition can find it. `protected` is the power core (non-minable
    -- until the team opts in); everything else is already minable.
    storage.bnm_base = storage.bnm_base or {}
    storage.bnm_base[surface.name] = {
        force     = force_name,
        roboport  = roboport,
        protected = protected,
        unlocked  = false,
    }

    storage.bases_placed[surface.name] = true
    log("[brave-new-mts] starter base placed for " .. force_name .. " on " .. surface.name)
end

--- Unlock the team's power core (solar / accumulators / substations / poles /
--- lights) so it can be mined too, opt-in once the team accepts the soft-lock
--- risk. The roboport always stays non-minable. Applies to all the team's bases.
function M.unlock_minable(force_name)
    if not storage.bnm_base then return end
    for _, base in pairs(storage.bnm_base) do
        if base.force == force_name then
            base.unlocked = true
            for _, e in pairs(base.protected) do
                if e.valid then e.minable = true end
            end
            -- roboport stays non-minable, always.
        end
    end
end

--- True if the team has opted to make its starter base minable.
function M.is_unlocked(force_name)
    if not storage.bnm_base then return false end
    for _, base in pairs(storage.bnm_base) do
        if base.force == force_name and base.unlocked then return true end
    end
    return false
end

return M
