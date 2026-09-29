-- tools/rig/lua/regress_records.lua
-- regress.py's helpers for BNM's base records, loaded into BNM's own state
-- after regress.lua: every record as plain values (to prove a refused admin
-- command changed nothing), and placing a base twice (to prove place() is
-- idempotent per surface).

REG = REG or {}
local R = REG

-- ─── Records as plain values ─────────────────────────────────────────

local function unit(e) return (e and e.valid) and e.unit_number or false end

local function units(list)
    local out = {}
    for i, e in ipairs(list or {}) do out[i] = unit(e) end
    return out
end

--- Every base record as plain values, to compare before and after: its
--- flags, the unit numbers of its roboport, pad, core and chests (false once
--- gone), its bases_placed flag, and any placed flag with no record.
function R.records()
    local placed, out = storage.bases_placed or {}, {}
    for name, rec in pairs(storage.bnm_base or {}) do
        out[name] = { force = rec.force, home = rec.home, outpost = rec.outpost, unlocked = rec.unlocked,
                      roboport = unit(rec.roboport), pad = unit(rec.pad), protected = units(rec.protected),
                      providers = units(rec.providers), storage_chests = units(rec.storage_chests),
                      placed = placed[name] == true }
    end
    for name in pairs(placed) do
        if not out[name] then out[name] = { placed_only = true } end
    end
    return out
end

-- ─── Placing twice ───────────────────────────────────────────────────

--- What a force has on a surface, as a fingerprint that changes if anything
--- is built, removed or rebuilt: how many entities, the sum of their unit
--- numbers (never reused), and the roboport's unit.
function R.footprint(surface_name, force_name)
    local out = { entities = 0, unit_sum = 0 }
    for _, e in pairs(game.surfaces[surface_name].find_entities_filtered{ force = force_name }) do
        if R.in_base(e) then
            out.entities = out.entities + 1
            out.unit_sum = out.unit_sum + (e.unit_number or 0)
        end
    end
    local rp = R.roboport(surface_name, force_name)
    out.roboport = rp and rp.unit_number or false
    return out
end

--- The footprint and what the site's containers hold, read in one tick.
local function snapshot(surface_name, force_name)
    return { footprint = R.footprint(surface_name, force_name),
             contents = R.base(surface_name, force_name).site_contents or {} }
end

--- Found a base with place(), then call place() on the same surface again
--- with the same opts and with the other kind (home or outpost), all in this
--- tick so no robot moves anything in between. Returns what each call
--- returned, a snapshot after the first call and after the others, and
--- whether the record is still the table the first call made.
function R.place_twice(force_name, planet_name, outpost)
    local s, sb = R.surface(planet_name), R.module("scripts/starter_base")
    local opts, other = outpost and { outpost = true } or nil, not outpost and { outpost = true } or nil
    local out = { first = sb.place(force_name, s, opts) }
    local rec = sb.base_for(s.name)
    out.home, out.once = rec and rec.home, snapshot(s.name, force_name)
    out.second = sb.place(force_name, s, opts)
    out.other = sb.place(force_name, s, other)
    out.again = snapshot(s.name, force_name)
    out.same_record = rec ~= nil and sb.base_for(s.name) == rec
    return out
end

--- place() once more on a surface that already has a base, later on: what
--- it returned and the footprint after it.
function R.place_again(force_name, surface_name)
    local ok = R.module("scripts/starter_base").place(force_name, game.surfaces[surface_name])
    return { ok = ok, footprint = R.footprint(surface_name, force_name) }
end

return true
