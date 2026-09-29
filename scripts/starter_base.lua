-- scripts/starter_base.lua
-- Seeds a self-running starter base on a team surface, so a character-free,
-- cheat-free team can bootstrap a bot factory. A team's first base is its
-- HOME: losing its roboport eliminates the team. A base founded later with a
-- Character Clone is an OUTPOST: losing its roboport wipes only that outpost
-- (M.lose_outpost), and another clone re-founds it. Placement is idempotent
-- per surface (storage.bases_placed[surface.name]).
--
-- M.place, in order:
--   1. Generate the ground. Off-world surfaces start with no generated chunks,
--      and generating them after the build overwrites the floor and drops
--      cliffs and ocean into the base.
--   2. Clear the site: enemies inside the roboport's construction area
--      (worms outrange the footprint and shoot down robots), cargo moved aside
--      (it holds the team's items), leftovers of a lost base swept with their
--      inventories pooled, then obstacles and resources.
--   3. Build the blueprint (scripts/blueprints.lua, swapped per planet) as
--      REAL entities centred on its roboport, each with its own blueprint
--      settings. There are no bots or materials yet to build ghosts.
--   4. Outposts get a cargo landing pad below the south wall: without one,
--      nothing a platform carries reaches the ground.
--   5. Stock the chests. Home: the Nauvis kit, crash-site loot and MTS admin
--      items. Outpost: a short planet kit.
--   6. Lock the power core (unless the team already unlocked it) and record
--      the base in storage.bnm_base.

local blueprints = require("scripts.blueprints")

local M = {}

-- The base is centred on a CHUNK CENTRE (16,16), not the spawn corner (0,0).
-- The roboport's construction area reveals whole chunks around the roboport's
-- chunk; that reveal is only symmetric when the roboport sits at the chunk's
-- centre -- otherwise it spills a chunk toward +x/+y. Players never stand here
-- (their character is parked in the pen), and remote view is centred here too.
M.BASE_ORIGIN = { x = 16, y = 16 }

-- The home base's anti-soft-lock kit, dropped into its passive provider
-- chests so the logistic network has stock to bootstrap from. Edit
-- names/counts here to retune. Any name that isn't a valid item is skipped
-- (and logged) at placement time.
M.STARTER_ITEMS = {
    { name = "transport-belt",        count = 240 },
    { name = "medium-electric-pole",  count = 20  },
    { name = "inserter",              count = 12  },
    { name = "pipe",                  count = 10  },
    { name = "burner-inserter",       count = 8   },
    { name = "underground-belt",      count = 4  },
    { name = "splitter",              count = 4  },
    { name = "pipe-to-ground",        count = 4  },
    { name = "small-lamp",            count = 4  },
    { name = "stone-furnace",         count = 4   },
    { name = "assembling-machine-3",  count = 1   },
    { name = "electric-mining-drill", count = 3   },
    { name = "steam-engine",          count = 2   },
    { name = "lab",                   count = 2   },
    { name = "boiler",                count = 2   },
    { name = "offshore-pump",         count = 1   },
    { name = "advanced-circuit",      count = 4  },
    -- Defense + early mid-tier bootstrap.
    { name = "gun-turret",            count = 4   },
    { name = "firearm-magazine",      count = 100  },
}

-- An outpost's kit: the common list plus its planet's (the landing pad is
-- placed as an entity, not stocked). Nauvis-only items are left out. The
-- relay roboports are there because the first research trigger on Vulcanus
-- (calcite) and Fulgora (ruin vault) measured just outside the 110-tile
-- construction radius on one seed.
local OUTPOST_KIT_COMMON = {
    { name = "medium-electric-pole", count = 20  },
    { name = "transport-belt",       count = 100 },
    { name = "inserter",             count = 10  },
    { name = "pipe",                 count = 10  },
}
local OUTPOST_KITS = {
    vulcanus = {
        { name = "electric-mining-drill", count = 3  },
        { name = "roboport",              count = 1  },
        { name = "construction-robot",    count = 10 },
        { name = "steel-chest",           count = 4  },
    },
    fulgora = {
        { name = "electric-mining-drill", count = 2  },
        { name = "roboport",              count = 2  },
        { name = "construction-robot",    count = 15 },
        { name = "lightning-rod",         count = 10 },  -- cover for robots flying at night
        { name = "steel-chest",           count = 4  },
    },
    gleba = {
        { name = "gun-turret",         count = 6   },
        { name = "firearm-magazine",   count = 200 },
        { name = "roboport",           count = 1   },
        { name = "construction-robot", count = 10  },
    },
    aquilo = {
        { name = "heating-tower",         count = 1  },
        { name = "heat-pipe",             count = 20 },
        { name = "solid-fuel",            count = 50 },
        { name = "electric-mining-drill", count = 1  },
    },
}
local OUTPOST_KIT_OTHER = {
    { name = "roboport",           count = 1  },
    { name = "construction-robot", count = 10 },
}

-- Robots seeded into the roboport when the runtime setting is missing; the
-- same as the settings' default.
local DEFAULT_ROBOTS = 50

-- Repair packs seeded into the central roboport's material slots so the
-- construction network auto-repairs battle damage from the start.
local STARTER_REPAIR_PACKS = 10

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

-- Chunks generated around the base before anything is placed: one more than
-- the chart margin, so it covers the whole reveal and the 220x220
-- construction area the enemy sweep clears.
local GENERATE_RADIUS = CHART_CHUNK_MARGIN + 1

-- The outpost landing pad: centred under the roboport, its top edge PAD_GAP
-- tiles below the footprint's bottom edge, on a PAD_FLOOR floor so it stands
-- even over water, lava or oil ocean.
local PAD_NAME  = "cargo-landing-pad"
local PAD_GAP   = 3
local PAD_FLOOR = "refined-concrete"

-- A generous crude-oil node so a character-free team has oil to tap without
-- prospecting. For crude oil the displayed yield is amount/3000 percent (verified
-- in-game: amount 150 000 showed 50%), so 300% == 900 000. It is placed well away
-- from the base but inside the central roboport's construction radius (110), so
-- bots can build a pumpjack on it.
local OIL_NODE_YIELD_PERCENT = 300
local OIL_NODE_AMOUNT        = OIL_NODE_YIELD_PERCENT * 3000
local OIL_NODE_DISTANCE      = 100   -- tiles from the base origin (roboport)

-- How far around the spawn origin to sweep for crash-site debris. The freeplay
-- wreckage sits near (0,0) -- where MTS spawns the team -- while the base is
-- offset to the chunk centre, so the sweep must cover the whole spawn area, not
-- just the base footprint.
local CRASH_SEARCH_RADIUS = 96

-- The profiles the data stage writes per planet (data-final-fixes.lua).
local PROFILES_MOD_DATA = "bnm-planet-profiles"

-- ─── Planet profiles ─────────────────────────────────────────────────

--- "mts-gleba-3" -> "gleba": MTS names each team's planet copy
--- mts-<base>-<slot>. Any other name is its own base.
local function base_planet_name(name)
    return name:match("^mts%-(.+)%-%d+$") or name
end

--- The data stage's profile for a planet, or nil when the mod-data or the
--- entry is missing (an older data stage).
local function stored_profile(planet_name)
    local md = prototypes.mod_data[PROFILES_MOD_DATA]
    local planets = md and md.get("planets")
    return planets and planets[planet_name] or nil
end

local function entity_or_nil(name)
    if name and prototypes.entity[name] then return name end
    return nil
end

-- ─── Storage records ─────────────────────────────────────────────────

--- The force's home base record, or nil.
local function home_of(force_name)
    for _, base in pairs(storage.bnm_base or {}) do
        if base.force == force_name and base.home then return base end
    end
    return nil
end

--- True if the force has any base recorded. Its first base is its home.
local function has_base(force_name)
    for _, base in pairs(storage.bnm_base or {}) do
        if base.force == force_name then return true end
    end
    return false
end

--- File a logistic chest under the record's providers or storage chests.
local function add_chest(record, chest)
    local mode = chest.prototype.logistic_mode
    if mode == "passive-provider" then
        record.providers[#record.providers + 1] = chest
    elseif mode == "storage" then
        record.storage_chests[#record.storage_chests + 1] = chest
    end
end

--- A new list: `a` then `b` (either may be nil).
local function joined(a, b)
    local out = {}
    for _, v in ipairs(a or {}) do out[#out + 1] = v end
    for _, v in ipairs(b or {}) do out[#out + 1] = v end
    return out
end

-- ─── Item delivery ───────────────────────────────────────────────────

--- Insert one {name, count, quality} stack across `chests` in order, then the
--- logistic network. Returns how many did not fit.
local function insert_stack(stack, chests, network)
    if not (stack.count and stack.count > 0) then return 0 end
    if not prototypes.item[stack.name] then
        log("[brave-new-mts] item '" .. tostring(stack.name) .. "' is not a known item -- skipping")
        return 0
    end
    local left = stack.count
    for _, chest in ipairs(chests) do
        if left == 0 then return 0 end
        if chest.valid then
            left = left - chest.insert{ name = stack.name, count = left, quality = stack.quality }
        end
    end
    if left > 0 and network and network.valid then
        left = left - network.insert{ name = stack.name, count = left, quality = stack.quality }
    end
    return left
end

--- Deliver an item list (or name-keyed pool) across `chests`, then the
--- network; log whatever is left over rather than dropping it silently.
local function deliver(items, chests, network)
    local lost = {}
    for _, stack in pairs(items) do
        local left = insert_stack(stack, chests, network)
        if left > 0 then lost[#lost + 1] = left .. "x " .. stack.name end
    end
    if #lost > 0 then
        log("[brave-new-mts] no room in the base's chests for: " .. table.concat(lost, ", "))
    end
end

--- The logistic network of a base's live roboport, or nil.
local function network_of(record)
    local roboport = record.roboport
    return roboport and roboport.valid and roboport.logistic_network or nil
end

--- Kits go to passive providers first; salvage goes to storage chests first.
local function kit_chests(record)
    return joined(record.providers, record.storage_chests)
end
local function salvage_chests(record)
    return joined(record.storage_chests, record.providers)
end

--- The admin-configured starter items tracked by MTS. With BNM loaded these are
--- routed into the team's home chests instead of a (non-existent) player
--- inventory, so every team -- including ones that spawn after an admin adds
--- items -- gets them once. Empty when MTS has none or is too old to expose
--- the query.
local function mts_starter_items()
    if not remote.interfaces["mts-v1"] then return {} end
    local ok, items = pcall(remote.call, "mts-v1", "get_starter_items")
    if ok and type(items) == "table" then return items end
    return {}
end

--- What a base's chests start with: the home kit, or the outpost's planet kit.
local function kit_for(profile, home)
    if home then return M.STARTER_ITEMS end
    return joined(OUTPOST_KIT_COMMON, OUTPOST_KITS[profile.base] or OUTPOST_KIT_OTHER)
end

local function stock_kits(built, profile, home)
    local chests, network = kit_chests(built), network_of(built)
    deliver(kit_for(profile, home), chests, network)
    if home then deliver(mts_starter_items(), chests, network) end
end

-- ─── Site preparation ────────────────────────────────────────────────

--- Add every item in `entity`'s inventories to `pool` (keyed by name and
--- quality, each value a {name, quality, count} stack).
local function pool_inventories(entity, pool)
    for i = 1, entity.get_max_inventory_index() do
        local inv = entity.get_inventory(i)
        if inv and inv.valid then
            for _, c in pairs(inv.get_contents()) do
                local key   = c.name .. "/" .. c.quality
                local stack = pool[key] or { name = c.name, quality = c.quality, count = 0 }
                stack.count = stack.count + c.count
                pool[key]   = stack
            end
        end
    end
end

--- Generate the ground under and around the base, synchronously. Generation
--- is deterministic, so every multiplayer peer builds the same terrain in the
--- same tick. Chunks that already exist (a home surface MTS pre-generated, a
--- re-founded outpost) are left alone.
local function generate_ground(surface, origin)
    surface.request_to_generate_chunks(origin, GENERATE_RADIUS)
    surface.force_generate_chunk_requests()
end

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

-- Cargo a team has already dropped to this planet lands near origin as a
-- "cargo-pod-container" (type temporary-container); a pod may also be present.
-- We must NOT destroy it -- it holds the player's items. Instead, scoot any
-- such cargo that overlaps the site just outside it. Returns silently if
-- there's nowhere clear to move a pod: the leftover sweep then pools what it
-- holds into the new base's chests.
local function relocate_cargo(surface, area)
    local cargo = surface.find_entities_filtered{
        area = area,
        type = { "temporary-container", "cargo-pod" },
    }
    local margin = 6  -- push clear of the site's edge before settling
    for _, e in pairs(cargo) do
        if e.valid then
            -- Aim just past whichever side edge the cargo is nearest.
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
local function collect_crash_debris(surface, pool)
    local names = crash_site_names()
    if #names == 0 then return end
    local R = CRASH_SEARCH_RADIUS
    for _, e in pairs(surface.find_entities_filtered{ name = names, area = { { -R, -R }, { R, R } } }) do
        if e.valid then
            pool_inventories(e, pool)
            e.destroy()
        end
    end
end

-- Never swept as a leftover: a body, a pod still flying down, robots in the air.
local SWEEP_SKIP = {
    ["character"]          = true,
    ["cargo-pod"]          = true,
    ["construction-robot"] = true,
    ["logistic-robot"]     = true,
}

--- A lost outpost being re-founded leaves its entities (unlocked by
--- M.lose_outpost) and their ghosts in the site. Pool their inventories and
--- destroy them, so nothing blocks the new build and no item is lost.
local function sweep_leftovers(force, surface, area, pool)
    local n = 0
    for _, e in pairs(surface.find_entities_filtered{ area = area, force = force }) do
        if e.valid and not SWEEP_SKIP[e.type] then
            pool_inventories(e, pool)
            e.destroy()
            n = n + 1
        end
    end
    if n > 0 then
        log("[brave-new-mts] swept " .. n .. " leftover entities from the base site on " .. surface.name)
    end
end

--- Clear the site so the base places cleanly and never sits on ore.
local function clear_obstacles(surface, area)
    local obstacles = surface.find_entities_filtered{
        area = area,
        type = { "tree", "simple-entity", "simple-entity-with-owner", "cliff", "fish", "resource" },
    }
    for _, e in pairs(obstacles) do
        if e.valid then e.destroy() end
    end
    surface.destroy_decoratives{ area = area }
end

-- ─── Site geometry ───────────────────────────────────────────────────

--- World-space box around the blueprint's entity centres, plus CLEAR_MARGIN.
local function footprint_area(origin, plan)
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for _, e in pairs(plan.entities) do
        local x, y = e.position.x - plan.ox, e.position.y - plan.oy
        minx, maxx = math.min(minx, x), math.max(maxx, x)
        miny, maxy = math.min(miny, y), math.max(maxy, y)
    end
    return {
        { origin.x + minx - CLEAR_MARGIN, origin.y + miny - CLEAR_MARGIN },
        { origin.x + maxx + CLEAR_MARGIN, origin.y + maxy + CLEAR_MARGIN },
    }
end

--- Half a blueprint entity's height in tiles, turned by its direction.
local function half_height(e)
    local proto = prototypes.entity[e.name]
    if not proto then return 0.5 end
    local d = e.direction
    local turned = d == defines.direction.east or d == defines.direction.west
    return (turned and proto.tile_width or proto.tile_height) / 2
end

--- Where an outpost's landing pad goes: centred on the roboport's x, its top
--- edge PAD_GAP tiles below the blueprint's bottom edge (entity centres plus
--- half their height). nil when the pad prototype does not exist.
local function pad_site(origin, plan)
    local proto = prototypes.entity[PAD_NAME]
    if not proto then return nil end
    local bottom = -math.huge
    for _, e in pairs(plan.entities) do
        bottom = math.max(bottom, e.position.y - plan.oy + half_height(e))
    end
    local w, h = proto.tile_width, proto.tile_height
    local top, left = origin.y + bottom + PAD_GAP, origin.x - w / 2
    return {
        position = { x = origin.x, y = top + h / 2 },
        area     = { { left, top }, { left + w, top + h } },
    }
end

--- The base's footprint, its pad (outposts only) and the box covering both.
local function site_for(origin, plan, outpost)
    local footprint = footprint_area(origin, plan)
    local pad = outpost and pad_site(origin, plan) or nil
    local area = footprint
    if pad then
        area = {
            { math.min(footprint[1][1], pad.area[1][1]), math.min(footprint[1][2], pad.area[1][2]) },
            { math.max(footprint[2][1], pad.area[2][1]), math.max(footprint[2][2], pad.area[2][2]) },
        }
    end
    return { footprint = footprint, pad = pad, area = area }
end

--- Get the site ready to build on. Returns the pool of salvaged items (crash
--- loot at home, leftovers of a lost base) for the new chests.
local function prepare_site(force, surface, origin, site, plan, home)
    generate_ground(surface, origin)
    local roboport = prototypes.entity[plan.roboport]
    clear_enemies(surface, origin, roboport.construction_radius or 0)
    relocate_cargo(surface, site.area)
    local pool = {}
    if home then collect_crash_debris(surface, pool) end
    sweep_leftovers(force, surface, site.area, pool)
    clear_obstacles(surface, site.area)
    return pool
end

-- ─── Building ────────────────────────────────────────────────────────

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

--- Lay the blueprint's floor tiles, origin-centred on the roboport like the
--- entities. No-op if the blueprint has no tiles.
local function place_tiles(surface, origin, plan)
    if #plan.tiles == 0 then return end
    local tiles = {}
    for _, t in pairs(plan.tiles) do
        tiles[#tiles + 1] = {
            name = t.name,
            position = { x = origin.x + t.position.x - plan.ox,
                         y = origin.y + t.position.y - plan.oy },
        }
    end
    surface.set_tiles(tiles)
end

-- The power core stays NON-MINABLE until the team opts into "I know what I am
-- doing": losing any of it would strand the base. It is the power generation
-- and storage, the lightning attractors that shield it (and the Fulgora
-- collector that is its night power), the substations and main poles, the
-- lights and the sign. Everything else is minable from the start, so a team
-- can freely redesign the base. The central roboport is never minable and is
-- handled separately.
local PROTECTED_TYPES = {
    ["solar-panel"]         = true,
    ["accumulator"]         = true,
    ["lightning-attractor"] = true,
    ["lamp"]                = true,
    ["display-panel"]       = true,
}
local PROTECTED_NAMES = {
    ["substation"]           = true,  -- the blueprint's three substations
    ["medium-electric-pole"] = true,  -- main poles, should a blueprint carry any
}
local function is_power_core(entity)
    return PROTECTED_TYPES[entity.type] or PROTECTED_NAMES[entity.name] or false
end

-- Blueprint entity fields that are not create_entity parameters. Everything
-- else (request filters, the sign's text and icon, recipes, filters, ...) is
-- passed straight through: create_entity takes the blueprint's own formats.
local NOT_PARAMS = { entity_number = true, wires = true, tags = true, items = true }

--- Create one blueprint entity as a real entity, with its blueprint settings.
local function create_from_blueprint(surface, force, origin, plan, e)
    if not prototypes.entity[e.name] then
        log("[brave-new-mts] blueprint references unknown entity '" .. tostring(e.name) .. "' -- skipping")
        return nil
    end
    local params = {}
    for k, v in pairs(e) do
        if not NOT_PARAMS[k] then params[k] = v end
    end
    params.position    = { x = origin.x + e.position.x - plan.ox, y = origin.y + e.position.y - plan.oy }
    params.force       = force
    params.raise_built = true
    local created = surface.create_entity(params)
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
    if created.type == "logistic-container" then add_chest(built, created) end
    if is_power_core(created) then
        if locked then created.minable_flag = false end
        built.protected[#built.protected + 1] = created
    end
    check_requests(e, created)
end

--- Build every blueprint entity, origin-centred on the roboport. Returns
--- { roboport, protected, providers, storage_chests }.
local function build_base(force, surface, origin, plan, locked)
    local built = { protected = {}, providers = {}, storage_chests = {} }
    for _, e in pairs(plan.entities) do
        local created = create_from_blueprint(surface, force, origin, plan, e)
        if created then register_created(built, created, e, locked) end
    end
    return built
end

--- Lay the pad's floor and place the pad. Not part of the locked core.
local function place_landing_pad(force, surface, pad)
    if prototypes.tile[PAD_FLOOR] then
        local tiles = {}
        for x = pad.area[1][1], pad.area[2][1] - 1 do
            for y = pad.area[1][2], pad.area[2][2] - 1 do
                tiles[#tiles + 1] = { name = PAD_FLOOR, position = { x = x, y = y } }
            end
        end
        surface.set_tiles(tiles)
    end
    local created = surface.create_entity{
        name = PAD_NAME, position = pad.position, force = force, raise_built = true,
    }
    if not created then log("[brave-new-mts] failed to place '" .. PAD_NAME .. "' (collision?)") end
    return created
end

-- ─── Oil and charting ────────────────────────────────────────────────

--- True if a crude-oil well can sit at `p`: buildable ground (so not water/cliffs)
--- and clear of any existing resource (so we never stack it on an ore patch).
local function oil_spot_is_clear(surface, p)
    if not surface.can_place_entity{ name = "crude-oil", position = p } then return false end
    local on_ore = surface.find_entities_filtered{ position = p, radius = 2, type = "resource" }
    return #on_ore == 0
end

--- A starting angle (radians) for the oil-node sweep, derived from the MAP seed
--- (the main surface's seed -- one game-wide value, so every team gets the SAME
--- direction) rather than anything per-surface. Deterministic across multiplayer
--- peers; a different map seed gives a different direction, but within a game all
--- teams match.
local function oil_start_angle()
    local main = game.surfaces[1]
    local seed = (main and main.map_gen_settings and main.map_gen_settings.seed) or 0
    return (seed % 360) / 360 * 2 * math.pi
end

--- Drop a single rich crude-oil node away from the base (so it doesn't crowd the
--- build) but inside the roboport's construction radius (so bots can reach it).
--- Sweeps a ring of candidate angles at the target distance, with a couple of
--- fallback radii, for a spot clear of water and ore. Charts it so it's visible.
--- Oil fields are a Nauvis feature: the caller places one on a Nauvis base only.
local function place_oil_node(force, surface)
    if not prototypes.entity["crude-oil"] then return end
    local o     = M.BASE_ORIGIN
    local start = oil_start_angle()
    for _, dist in ipairs({ OIL_NODE_DISTANCE, 64, 96 }) do
        for step = 0, 11 do
            local ang = start + (step / 12) * 2 * math.pi
            local p = { x = o.x + math.cos(ang) * dist, y = o.y + math.sin(ang) * dist }
            if oil_spot_is_clear(surface, p) then
                surface.create_entity{ name = "crude-oil", position = p, amount = OIL_NODE_AMOUNT }
                force.chart(surface, { { p.x - 3, p.y - 3 }, { p.x + 3, p.y + 3 } })
                return
            end
        end
    end
    log("[brave-new-mts] no clear spot (no water / no ore) found for the starter oil node")
end

--- Chart whole chunks symmetrically around the base footprint, so the reveal is
--- centred on the base (force.chart reveals whole 32-tile chunks; we work in
--- chunk units to avoid the chunk-boundary asymmetry of a raw tile box).
local function chart_base(force, surface, area)
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

-- ─── Placement ───────────────────────────────────────────────────────

--- Track the base per surface, so the minable toggle, the roboport-loss
--- handler and admin item grants can find it. `protected` is the power core;
--- `providers` / `storage_chests` receive later deliveries.
local function record_base(force_name, surface_name, built, home, locked)
    storage.bnm_base = storage.bnm_base or {}
    storage.bnm_base[surface_name] = {
        force          = force_name,
        home           = home,
        outpost        = not home,
        roboport       = built.roboport,
        protected      = built.protected,
        providers      = built.providers,
        storage_chests = built.storage_chests,
        pad            = built.pad,
        unlocked       = not locked,
    }
    storage.bases_placed[surface_name] = true
end

--- Build a base and record it. Returns true only when its roboport stands.
local function found_base(force, surface, home)
    local profile = M.profile_for(surface)
    local plan = blueprints.plan_for(profile, home)
    if not plan then
        log("[brave-new-mts] the starter blueprint has no roboport -- no base on " .. surface.name)
        return false
    end
    local origin = M.BASE_ORIGIN
    local site   = site_for(origin, plan, not home)
    local pool   = prepare_site(force, surface, origin, site, plan, home)
    place_tiles(surface, origin, plan)
    local locked = not M.is_unlocked(force.name)
    local built  = build_base(force, surface, origin, plan, locked)
    deliver(pool, salvage_chests(built), network_of(built))
    if not (built.roboport and built.roboport.valid) then
        log("[brave-new-mts] no roboport was built on " .. surface.name .. " -- base not recorded")
        return false
    end
    built.pad = site.pad and place_landing_pad(force, surface, site.pad) or nil
    stock_kits(built, profile, home)
    if profile.base == "nauvis" then place_oil_node(force, surface) end
    chart_base(force, surface, site.footprint)  -- no character stands here to chart it
    record_base(force.name, surface.name, built, home, locked)
    return true
end

--- Grant construction robotics so bot-driven play is possible from the start.
local function grant_construction_robotics(force)
    local cr = force.technologies["construction-robotics"]
    if cr and not cr.researched then
        cr.researched = true
        force.print("[Brave New MTS] Construction robotics research has been unlocked for your team.")
    end
end

-- ─── Migration ───────────────────────────────────────────────────────

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
    for _, chest in pairs(chests) do add_chest(base, chest) end
end

--- 0.1.x placed the home base on the team's Nauvis and outposts elsewhere.
local function on_home_planet(surface_name)
    local surface = game.surfaces[surface_name]
    local base = surface and surface.valid and M.profile_for(surface).base
        or base_planet_name(surface_name)
    return base == "nauvis"
end

-- ─── Public API ──────────────────────────────────────────────────────

--- The planet profile for a surface: { base, solar_panel, accumulator,
--- fulgora, freezing } (see docs/fixup-plan.md). Read from the data stage's
--- mod-data by surface.planet.name; a surface with no planet gets the Nauvis
--- profile. Falls back gracefully (vanilla everything, base from the planet
--- name) when the mod-data, the entry or a named prototype does not exist.
function M.profile_for(surface)
    local planet = surface.planet
    local name   = planet and planet.name or "nauvis"
    local stored = stored_profile(name) or {}
    local base   = stored.base or base_planet_name(name)
    local fulgora, freezing = stored.fulgora, stored.freezing
    if fulgora == nil then fulgora = base == "fulgora" end
    if freezing == nil then
        freezing = planet and planet.prototype.entities_require_heating or false
    end
    return {
        base        = base,
        solar_panel = entity_or_nil(stored.solar_panel),
        accumulator = entity_or_nil(stored.accumulator),
        fulgora     = fulgora,
        freezing    = freezing,
    }
end

--- The storage.bnm_base record for a surface name, or nil.
function M.base_for(surface_name)
    return storage.bnm_base and storage.bnm_base[surface_name] or nil
end

--- Place a starter base for `force_name` on `surface` (idempotent). The
--- force's first base is its home; opts.outpost = true marks an off-world
--- base founded with a clone. Returns true only when a base with a live
--- roboport was built in this call.
function M.place(force_name, surface, opts)
    if not (surface and surface.valid) then return false end
    storage.bases_placed = storage.bases_placed or {}
    if storage.bases_placed[surface.name] then return false end
    local force = game.forces[force_name]
    if not (force and force.valid) then return false end

    local home = not (opts and opts.outpost) and not has_base(force_name)
    if not found_base(force, surface, home) then return false end
    grant_construction_robotics(force)
    log("[brave-new-mts] starter " .. (home and "home base" or "outpost") .. " placed for "
        .. force_name .. " on " .. surface.name)
    return true
end

--- Forget a surface's base, so it can be founded again.
function M.forget_surface(surface_name)
    if storage.bnm_base then storage.bnm_base[surface_name] = nil end
    if storage.bases_placed then storage.bases_placed[surface_name] = nil end
end

--- Wipe an outpost whose roboport was lost: its locked core becomes minable,
--- so the team's bots can salvage it, and the surface is forgotten, so a clone
--- can re-found it (M.place then sweeps what is left in the site). A home base
--- is never wiped here. Returns true if an outpost was wiped.
function M.lose_outpost(surface_name)
    local base = M.base_for(surface_name)
    if not (base and base.outpost) then return false end
    for _, e in pairs(base.protected or {}) do
        if e.valid then e.minable_flag = true end
    end
    M.forget_surface(surface_name)
    return true
end

--- Push an admin's freshly-added starter items into every HOME base already
--- placed, once per team. Teams that haven't spawned yet pick the items up at
--- placement time via mts_starter_items(), so between the two paths every
--- team ends up with the full admin list exactly once.
function M.add_items_to_spawned_bases(items)
    if not (storage.bnm_base and items and #items > 0) then return end
    for _, base in pairs(storage.bnm_base) do
        if base.home then deliver(items, kit_chests(base), network_of(base)) end
    end
end

--- Unlock the team's power core so it can be mined too, opt-in once the team
--- accepts the soft-lock risk. The roboport always stays non-minable. Applies
--- to all the team's bases; bases founded later are built unlocked.
function M.unlock_minable(force_name)
    if not storage.bnm_base then return end
    for _, base in pairs(storage.bnm_base) do
        if base.force == force_name then
            base.unlocked = true
            for _, e in pairs(base.protected) do
                if e.valid then e.minable_flag = true end
            end
        end
    end
end

--- Forget all per-surface base state for a force, so a team that later recycles
--- this slot gets a fresh base. MTS deletes the team's surfaces on disband; if
--- we kept `bases_placed` set for those (recycled) surface names, M.place would
--- early-return and never re-chart the new base -- leaving the new occupant
--- unable to see their surface. Keyed off bnm_base (which records the owning
--- force per surface), since the surfaces themselves are already gone by the
--- time on_team_released fires.
function M.cleanup_force(force_name)
    if not storage.bnm_base then return end
    for surface_name, base in pairs(storage.bnm_base) do
        if base.force == force_name then M.forget_surface(surface_name) end
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

--- Upgrade 0.1.x base records: the provider chest lists, and the home/outpost
--- flags (the home is the base on the team's Nauvis; any other is an
--- outpost). Idempotent; call from on_configuration_changed.
function M.migrate()
    storage.bases_placed = storage.bases_placed or {}
    storage.bnm_base     = storage.bnm_base or {}
    local area, decoded = nil, false  -- the footprint all 0.1.x bases share
    for surface_name, base in pairs(storage.bnm_base) do
        if base.providers == nil then
            if not decoded then
                decoded = true
                local plan = blueprints.plan_for({ base = "nauvis" }, true)
                area = plan and footprint_area(M.BASE_ORIGIN, plan)
            end
            migrate_chests(surface_name, base, area)
        end
    end
    for surface_name, base in pairs(storage.bnm_base) do
        if base.home == nil and base.outpost == nil then
            base.home    = on_home_planet(surface_name) and home_of(base.force) == nil
            base.outpost = not base.home
        end
    end
end

return M
