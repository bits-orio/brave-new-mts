-- tools/rig/lua/regress.lua
-- Helpers for regress.py, loaded into BNM's OWN Lua state (probe state "bnm",
-- i.e. /sc __brave-new-mts__), where `storage` is BNM's storage and BNM's
-- modules are in package.loaded. They drive BNM's public functions the way
-- the game does (starter_base.place, platform_hub.establish_for) and read the
-- result back as plain tables for the Python side.
--
-- Code lives in the global REG for this Lua session only: nothing here is
-- saved, so regress.py re-runs these files after every server start. Engine
-- events that BNM reacts to (a roboport dying) are raised from the level state
-- by the caller, not from here, so BNM's handlers run as they would in play.
--
-- This file is the shared core (surfaces, placing, reading a base back) and
-- loads first; the others add to REG by concern:
--   regress_platform.lua  platforms, the Establish core, pad deliveries
--   regress_site.lua      what the checks do in a site: a ghost, full chests,
--                         what the team built, the ground, the locks
--   regress_records.lua   the base records as plain values, placing twice
--   regress_player.lua    a simulated player's leave and reconnect

REG = REG or {}
local R = REG

-- The power core BNM locks (scripts/base/power_core.lua PROTECTED_TYPES / PROTECTED_NAMES).
local CORE_TYPES = { "solar-panel", "accumulator", "lightning-attractor", "lamp", "display-panel" }
local CORE_NAMES = { ["substation"] = true, ["medium-electric-pole"] = true }

-- Never swept as a leftover (scripts/base/salvage.lua SWEEP_SKIP), so never counted.
local NOT_BASE = { ["character"] = true, ["cargo-pod"] = true,
                   ["construction-robot"] = true, ["logistic-robot"] = true, ["spider-leg"] = true }

--- A loaded BNM module by path, e.g. R.module("scripts/starter_base").
function R.module(path) return package.loaded["__brave-new-mts__/" .. path .. ".lua"] end
local function starter_base() return R.module("scripts/starter_base") end

--- True for anything a base or its site holds: all but a body, a pod, a robot
--- or a spider's leg.
function R.in_base(e) return not NOT_BASE[e.type] end

--- True for an entity of the power core BNM locks.
function R.is_core(e)
    if CORE_NAMES[e.name] then return true end
    for _, t in pairs(CORE_TYPES) do if e.type == t then return true end end
    return false
end

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

--- Surfaces still recorded for a force: { [surface] = "home" | "outpost" }.
function R.bases_of(force_name)
    local out = {}
    for name, rec in pairs(storage.bnm_base or {}) do
        if rec.force == force_name then out[name] = rec.home and "home" or "outpost" end
    end
    return out
end

-- ─── Inspecting a base ───────────────────────────────────────────────

--- The site of a base: its walls' box, and the landing pad below it (found on
--- the ground, so a lost outpost's pad counts too), grown by 3 tiles
--- (scripts/base/geometry.lua CLEAR_MARGIN), i.e. what a re-found sweeps.
function R.site(s, force_name)
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

--- Add what `entity` holds in its inventories to `into`, keyed "name" (or
--- "name/quality").
function R.add_contents(entity, into)
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

--- Items held by a list of entities.
local function contents(list)
    local out = {}
    for _, e in pairs(list or {}) do
        if e.valid then R.add_contents(e, out) end
    end
    return out
end

--- The record's side of R.base: its flags and what its chests hold.
local function record_part(out, rec)
    out.home, out.outpost, out.unlocked = rec.home, rec.outpost, rec.unlocked
    out.providers = #(rec.providers or {})
    out.storage_chests = #(rec.storage_chests or {})
    out.storage_contents = contents(rec.storage_chests)
    out.provider_contents = contents(rec.providers)
end

--- The roboport and its network, as R.base reports them.
local function roboport_part(rp, rec)
    local net = rp.logistic_network
    return { unit = rp.unit_number, x = rp.position.x, y = rp.position.y,
             frozen = rp.frozen, minable = rp.minable_flag, network = net ~= nil,
             construction_robots = net and net.all_construction_robots or 0,
             is_record = rec ~= nil and rec.roboport == rp }
end

--- The pad and its gap to the south wall, as R.base reports them.
local function pad_part(st, rec)
    local pad = st.pad
    local top = pad.position.y - pad.prototype.tile_height / 2
    return { x = pad.position.x, y = pad.position.y, name = pad.name,
             gap = top - st.wall_bottom, minable = pad.minable_flag,
             is_record = rec ~= nil and rec.pad == pad }
end

--- Entity counts and container contents in the site, and the core's locks.
local function site_part(out, s, st, force_name)
    out.walls = st.walls
    out.out_of_map = s.count_tiles_filtered{ area = st.area, name = "out-of-map" }
    out.counts, out.core, out.core_locked, out.site_contents = {}, 0, 0, {}
    for _, e in pairs(s.find_entities_filtered{ area = st.area, force = force_name }) do
        if R.in_base(e) then
            out.counts[e.name] = (out.counts[e.name] or 0) + 1
            if e.type ~= "roboport" then R.add_contents(e, out.site_contents) end
            if R.is_core(e) then
                out.core = out.core + 1
                if not e.minable_flag then out.core_locked = out.core_locked + 1 end
            end
        end
    end
end

local function chunks_generated(s)
    local n = 0
    for c in s.get_chunks() do
        if s.is_chunk_generated(c) then n = n + 1 end
    end
    return n
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
    if rec then record_part(out, rec) end
    local rp = R.roboport(surface_name, force_name)
    if rp then out.roboport = roboport_part(rp, rec) end
    local st = R.site(s, force_name)
    if st and st.pad then out.pad = pad_part(st, rec) end
    out.chunks_generated = chunks_generated(s)
    if st then site_part(out, s, st, force_name) end
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

return true
