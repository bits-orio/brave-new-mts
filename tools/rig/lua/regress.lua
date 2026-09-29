-- tools/rig/lua/regress.lua
-- Helpers for regress.py, loaded into BNM's OWN Lua state (probe state "bnm",
-- i.e. /sc __brave-new-mts__), where `storage` is BNM's storage and BNM's
-- modules are in package.loaded. They drive BNM's public functions the way
-- the game does (starter_base.place, platform_hub.establish_for) and read the
-- result back as plain tables for the Python side.
--
-- Code lives in the global REG for this Lua session only: nothing here is
-- saved, so regress.py re-runs this file after every server start. Engine
-- events that BNM reacts to (a roboport dying) are raised from the level state
-- by the caller, not from here, so BNM's handlers run as they would in play.

REG = REG or {}
local R = REG

local CLONE = "bnm-character-clone"

-- The power core starter_base.lua locks (PROTECTED_TYPES / PROTECTED_NAMES).
local CORE_TYPES = { "solar-panel", "accumulator", "lightning-attractor", "lamp", "display-panel" }
local CORE_NAMES = { ["substation"] = true, ["medium-electric-pole"] = true }

-- Never swept as a leftover (starter_base.lua SWEEP_SKIP), so never counted.
local NOT_BASE = { ["character"] = true, ["cargo-pod"] = true,
                   ["construction-robot"] = true, ["logistic-robot"] = true }

local function bnm(path) return package.loaded["__brave-new-mts__/" .. path .. ".lua"] end
local function starter_base() return bnm("scripts/starter_base") end

-- ─── Surfaces and bases ──────────────────────────────────────────────

--- A team planet surface, created the way MTS's planet_map does (the engine
--- makes MTS the owner), with a 3-chunk radius generated around the origin.
function R.surface(planet_name)
    local planet = game.planets[planet_name]
    if not planet then error("no planet " .. planet_name) end
    local s = planet.surface or planet.create_surface()
    s.request_to_generate_chunks({ 0, 0 }, 3)
    s.force_generate_chunk_requests()
    return s
end

--- Place a base with BNM's real placement. Returns what place() returned and
--- the record it left.
function R.place(force_name, planet_name, outpost)
    local s = R.surface(planet_name)
    local ok = starter_base().place(force_name, s, outpost and { outpost = true } or nil)
    local rec = starter_base().base_for(s.name)
    return { ok = ok, surface = s.name, home = rec and rec.home, outpost = rec and rec.outpost }
end

--- The live bnm-roboport of a force on a surface, or nil.
function R.roboport(surface_name, force_name)
    local s = game.surfaces[surface_name]
    return s and s.find_entities_filtered{ name = "bnm-roboport", force = force_name }[1] or nil
end

-- ─── Platforms ───────────────────────────────────────────────────────

--- A platform of `force_name` by name, or nil.
local function platform(force_name, name)
    for _, p in pairs(game.forces[force_name].platforms) do
        if p.valid and p.name == name then return p end
    end
    return nil
end

--- The hub of the named platform, or an error.
function R.hub(force_name, name)
    local p = platform(force_name, name)
    local hub = p and p.hub
    if not (hub and hub.valid) then error("no hub on platform " .. name) end
    return hub
end

--- A platform created by script straight into orbit of `planet_name`. That
--- path, unlike flying there, does not create the planet's surface.
function R.make_platform(force_name, planet_name, name)
    local p = platform(force_name, name)
    if not p then
        p = game.forces[force_name].create_space_platform{
            name = name, planet = planet_name, starter_pack = "space-platform-starter-pack",
        }
        p.apply_starter_pack()
    end
    return { name = p.name, location = p.space_location and p.space_location.name,
             hub = p.hub and p.hub.valid, planet_surface = game.planets[planet_name].surface ~= nil }
end

local function hub_inventory(hub) return hub.get_inventory(defines.inventory.hub_main) end

--- Put items into a platform hub: { name, count, quality }.
function R.hub_insert(force_name, name, stack)
    return hub_inventory(R.hub(force_name, name)).insert(stack)
end

--- Clones aboard, of any quality.
function R.clones(force_name, name)
    return hub_inventory(R.hub(force_name, name)).get_item_count_filtered{ name = CLONE }
end

function R.hub_count(force_name, name, item)
    return hub_inventory(R.hub(force_name, name)).get_item_count(item)
end

--- The Establish-base core, exactly as the hub button calls it.
function R.establish(force_name, name)
    local ok, reason, surface = bnm("events/platform_hub").establish_for(
        game.forces[force_name], R.hub(force_name, name))
    return { ok = ok, reason = reason, surface = surface }
end

-- ─── Inspecting a base ───────────────────────────────────────────────

--- The site of a base: its walls' box, and the landing pad below it (found on
--- the ground, so a lost outpost's pad counts too), grown by 3 tiles
--- (starter_base's CLEAR_MARGIN), i.e. what a re-found sweeps.
local function site(s, force_name)
    local walls = s.find_entities_filtered{ type = "wall", force = force_name,
        area = { { -100, -100 }, { 132, 132 } } }
    if #walls == 0 then return nil end
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for _, w in pairs(walls) do
        local p, h, wd = w.position, w.prototype.tile_height / 2, w.prototype.tile_width / 2
        x1, y1 = math.min(x1, p.x - wd), math.min(y1, p.y - h)
        x2, y2 = math.max(x2, p.x + wd), math.max(y2, p.y + h)
    end
    local pad = s.find_entities_filtered{ type = "cargo-landing-pad", force = force_name,
        area = { { x1, y2 }, { x2, y2 + 20 } } }[1]
    local bottom = pad and (pad.position.y + pad.prototype.tile_height / 2) or y2
    return { walls = #walls, wall_bottom = y2, pad = pad,
             area = { { x1 - 3, y1 - 3 }, { x2 + 3, bottom + 3 } } }
end

local function add_contents(entity, into)
    for i = 1, entity.get_max_inventory_index() do
        local inv = entity.get_inventory(i)
        if inv and inv.valid then
            for _, c in pairs(inv.get_contents()) do
                local key = c.quality == "normal" and c.name or (c.name .. "/" .. c.quality)
                into[key] = (into[key] or 0) + c.count
            end
        end
    end
end

--- Items held by a list of entities, keyed "name" (or "name/quality").
local function contents(list)
    local out = {}
    for _, e in pairs(list or {}) do
        if e.valid then add_contents(e, out) end
    end
    return out
end

local function is_core(e)
    if CORE_NAMES[e.name] then return true end
    for _, t in pairs(CORE_TYPES) do if e.type == t then return true end end
    return false
end

--- Everything regress.py asserts about the base (or its leftovers) on a
--- surface: the record, the roboport and its network, the pad and its gap
--- to the south wall, the lock state of the power core, entity counts in the
--- site, what the chests hold, and whether the ground under it is generated.
function R.base(surface_name, force_name)
    local s = game.surfaces[surface_name]
    if not (s and s.valid) then return { exists = false } end
    local rec = starter_base().base_for(surface_name)
    force_name = force_name or (rec and rec.force)
    local out = { exists = true, recorded = rec ~= nil,
                  placed = storage.bases_placed and storage.bases_placed[surface_name] == true }
    if rec then
        out.home, out.outpost, out.unlocked = rec.home, rec.outpost, rec.unlocked
        out.providers = #(rec.providers or {})
        out.storage_chests = #(rec.storage_chests or {})
        out.storage_contents = contents(rec.storage_chests)
        out.provider_contents = contents(rec.providers)
    end

    local rp = R.roboport(surface_name, force_name)
    if rp then
        local net = rp.logistic_network
        out.roboport = { unit = rp.unit_number, x = rp.position.x, y = rp.position.y,
                         frozen = rp.frozen, minable = rp.minable_flag, network = net ~= nil,
                         construction_robots = net and net.all_construction_robots or 0,
                         is_record = rec ~= nil and rec.roboport == rp }
    end

    local st = site(s, force_name)
    local pad = st and st.pad
    if pad then
        local top = pad.position.y - pad.prototype.tile_height / 2
        out.pad = { x = pad.position.x, y = pad.position.y, name = pad.name,
                    gap = top - st.wall_bottom, minable = pad.minable_flag,
                    is_record = rec ~= nil and rec.pad == pad }
    end

    out.chunks_generated = 0
    for c in s.get_chunks() do
        if s.is_chunk_generated(c) then out.chunks_generated = out.chunks_generated + 1 end
    end
    if not st then return out end
    out.walls = st.walls
    out.out_of_map = s.count_tiles_filtered{ area = st.area, name = "out-of-map" }

    -- Entity counts and container contents in the site, and the core's locks.
    out.counts, out.core, out.core_locked = {}, 0, 0
    local held = {}
    for _, e in pairs(s.find_entities_filtered{ area = st.area, force = force_name }) do
        if not NOT_BASE[e.type] then
            out.counts[e.name] = (out.counts[e.name] or 0) + 1
            if e.type ~= "roboport" then add_contents(e, held) end
            if is_core(e) then
                out.core = out.core + 1
                if not e.minable_flag then out.core_locked = out.core_locked + 1 end
            end
        end
    end
    out.site_contents = held
    return out
end

--- Put items into the first chest of a base's `kind` list ("providers" or
--- "storage_chests"). Returns how many went in.
function R.chest_insert(surface_name, kind, stack)
    local rec = starter_base().base_for(surface_name)
    local chest = rec and rec[kind] and rec[kind][1]
    if not (chest and chest.valid) then error("no " .. kind .. " chest on " .. surface_name) end
    return chest.insert(stack)
end

--- Ask the base's landing pad for `count` of `item` (a normal logistic request).
function R.pad_request(surface_name, item, count)
    local pad = starter_base().base_for(surface_name).pad
    local section = pad.get_logistic_sections().add_section()
    section.set_slot(1, { value = item, min = count })
    return true
end

function R.pad_count(surface_name, item)
    local rec = starter_base().base_for(surface_name)
    local pad = rec and rec.pad
    local net = rec and rec.roboport and rec.roboport.valid and rec.roboport.logistic_network
    return { pad = (pad and pad.valid) and pad.get_item_count(item) or 0,
             network = net and net.get_item_count(item) or 0 }
end

--- Surfaces still recorded for a force: { [surface] = "home" | "outpost" }.
function R.bases_of(force_name)
    local out = {}
    for name, rec in pairs(storage.bnm_base or {}) do
        if rec.force == force_name then out[name] = rec.home and "home" or "outpost" end
    end
    return out
end

--- Place a ghost of `name` somewhere buildable 20 to 40 tiles north of the
--- roboport, inside its construction area. Returns its position.
function R.place_ghost(surface_name, force_name, name)
    local s = game.surfaces[surface_name]
    local rp = R.roboport(surface_name, force_name)
    for dy = 20, 40 do
        for dx = -12, 12, 3 do
            local p = { x = rp.position.x + dx + 0.5, y = rp.position.y - dy + 0.5 }
            if s.can_place_entity{ name = name, position = p, force = force_name,
                                   build_check_type = defines.build_check_type.manual_ghost } then
                s.create_entity{ name = "entity-ghost", inner_name = name, position = p, force = force_name }
                return { x = p.x, y = p.y, distance = math.sqrt(dx * dx + dy * dy) }
            end
        end
    end
    error("no buildable spot for a " .. name .. " ghost on " .. surface_name)
end

--- Whether the ghost at `pos` has been built: { built, ghost }.
function R.ghost_state(surface_name, name, pos)
    local s = game.surfaces[surface_name]
    local area = { { pos.x - 0.4, pos.y - 0.4 }, { pos.x + 0.4, pos.y + 0.4 } }
    return { built = #s.find_entities_filtered{ name = name, area = area } > 0,
             ghost = #s.find_entities_filtered{ ghost_name = name, area = area } > 0 }
end

--- The radar and inserter of a base (by type) with their frozen state.
function R.machines(surface_name, force_name)
    local s = game.surfaces[surface_name]
    local out = {}
    for _, t in pairs({ "radar", "inserter" }) do
        local e = s.find_entities_filtered{ type = t, force = force_name,
            area = { { -20, -20 }, { 52, 52 } } }[1]
        out[t] = e and { name = e.name, frozen = e.frozen } or false
    end
    return out
end

return true
