-- scripts/starter_base.lua
-- Seeds a self-running starter base on a team surface so a character-free,
-- cheat-free team can bootstrap a bot factory. Placement is idempotent per
-- surface (storage.bases_placed[surface.name]).
--
-- Strategy (closely follows the Brave New OARC pattern, adapted for K2):
--   1. Import the configured blueprint and centre it on its roboport so the
--      roboport lands at the team's spawn origin (MTS always spawns at 0,0).
--   2. Create the blueprint's entities as REAL, working entities (not ghosts)
--      -- there are no bots or materials yet to build ghosts.
--   3. Seed power: charge accumulators and the roboport buffer so a night-one
--      base doesn't deadlock before solar ramps.
--   4. Seed bots into the roboport.
--   5. Place logistic chests pre-filled with starter items so bots have stock
--      to build the team's first expansion (the anti-soft-lock seed).
--   6. Guarantee raw resources under/near the base so production can actually
--      flow without hand-mining.

local blueprints = require("scripts.blueprints")

local M = {}

-- ─── Tunables (Phase 3 will finalise these once the blueprint exists) ───

-- Bots seeded into the base roboport. Construction bots build the blueprints
-- the player draws; logistic bots service requests.
local STARTER_CONSTRUCTION_ROBOTS = 50
local STARTER_LOGISTIC_ROBOTS      = 25

-- Joules to pre-load into each accumulator so the base survives night one.
-- Clamped to the accumulator's actual buffer size.
local ACCUMULATOR_SEED_ENERGY = 5000000  -- 5 MJ

-- ─── Internal helpers ──────────────────────────────────────────────────

--- Fill a freshly-created roboport with starter bots and a full energy buffer.
local function seed_roboport(roboport)
    local inv = roboport.get_inventory(defines.inventory.roboport_robot)
    if inv then
        inv.insert{ name = "construction-robot", count = STARTER_CONSTRUCTION_ROBOTS }
        inv.insert{ name = "logistic-robot",     count = STARTER_LOGISTIC_ROBOTS }
    end
    -- Start charged so bots can fly before the power network spins up.
    roboport.energy = roboport.electric_buffer_size or roboport.energy
end

--- Pre-charge an accumulator so the base has stored power on the first night.
local function seed_accumulator(accumulator)
    local cap = accumulator.electric_buffer_size or ACCUMULATOR_SEED_ENERGY
    accumulator.energy = math.min(ACCUMULATOR_SEED_ENERGY, cap)
end

--- Find the roboport entity in a blueprint and return its position, so we can
--- offset every entity to land the roboport at the spawn origin.
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
    inv.destroy()
    return entities or {}
end

--- Place all blueprint entities as real entities, origin-centred on the
--- roboport, and seed power as they are created.
local function build_base(force, surface, origin, bp_entities)
    local ox, oy = roboport_offset(bp_entities)
    for _, e in pairs(bp_entities) do
        local proto = prototypes.entity[e.name]
        if not proto then
            log("[brave-new-mts] blueprint references unknown entity '"
                .. tostring(e.name) .. "' -- skipping")
        else
            local created = surface.create_entity{
                name      = e.name,
                position  = { x = origin.x + e.position.x - ox,
                              y = origin.y + e.position.y - oy },
                direction = e.direction,
                force     = force,
                recipe    = e.recipe,
                raise_built = true,
            }
            if created then
                if proto.type == "roboport"    then seed_roboport(created)    end
                if proto.type == "accumulator" then seed_accumulator(created) end
            end
        end
    end
end

--- Place the logistic chests holding the team's anti-soft-lock starter items.
--- TODO(phase3): finalise positions, chest types (K2 / passive-provider /
--- storage), and the item list to match the chosen blueprint.
local function place_starter_chests(force, surface, origin)
    -- Placeholder: intentionally empty until the blueprint + item list exist.
    -- Will create a small cluster of chests near `origin` and insert the
    -- starter items so construction bots have stock to build the first base.
end

--- Guarantee raw resources under/near the base so production can flow without
--- hand-mining (cheat mode is intentionally OFF).
--- TODO(phase3): place ore/oil patches sized to the blueprint's miners.
local function guarantee_resources(force, surface, origin)
    -- Placeholder: per-planet resource seeding added in Phase 3.
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
    if not bp_string or bp_string == "" then
        -- No blueprint configured for this surface yet (Phase 1/3). Don't mark
        -- the surface placed, so it gets seeded once a blueprint is added.
        return
    end

    local origin = { x = 0, y = 0 }  -- MTS always spawns players at origin.
    local bp_entities = decode_blueprint(bp_string)

    build_base(force, surface, origin, bp_entities)
    place_starter_chests(force, surface, origin)
    guarantee_resources(force, surface, origin)

    storage.bases_placed[surface.name] = true
    log("[brave-new-mts] starter base placed for " .. force_name
        .. " on " .. surface.name)
end

--- Called on on_player_changed_surface: place a base if the player has just
--- reached a team surface that doesn't have one yet.
function M.maybe_place_for_player(player)
    if not remote.interfaces["mts-v1"] then return end

    local surface = player.physical_surface or player.surface
    if not (surface and surface.valid) then return end

    storage.bases_placed = storage.bases_placed or {}
    if storage.bases_placed[surface.name] then return end

    local owner = remote.call("mts-v1", "get_surface_owner", surface.name)
    if not owner then return end  -- not a team-owned surface

    M.place(owner, surface)
end

return M
