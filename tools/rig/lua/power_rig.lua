-- tools/rig/lua/power_rig.lua
-- Power-measurement rig, loaded into the LEVEL (scenario) Lua state by
-- power_test.py (probe.Rig.run_file(..., state="level")). It never touches
-- BNM's or MTS's state: the base itself is placed from the bnm state by the
-- caller, then this file finds the entities on the surface and watches them.
--
-- One "run" per surface. A run owns a constant test load (bnm-rig-load, from
-- tools/rig/hooks), resets the base to a known state (accumulators and roboport
-- full, daytime = noon), then samples every R.SAMPLE ticks for `cycles` full
-- day/night cycles, snapshotting the network's flow statistics at each cycle
-- boundary. Data lives in storage.rig (level state), code in the global RIG,
-- which is re-installed after a server restart by simply re-running this file.

RIG = RIG or {}
local R = RIG
R.SAMPLE = 7          -- odd interval, unlikely to clash with a scenario nth-tick handler
R.EMPTY_FRACTION = 0.001  -- accumulators count as "empty" below 0.1% of capacity

local function st()
    storage.rig = storage.rig or { runs = {} }
    return storage.rig
end

--- Create a per-team planet surface the same way MTS does
--- (planet_map.get_or_create_planet_surface): planet.create_surface, then
--- force-generate a 3-chunk radius around the origin.
function R.create_surface(planet, slot)
    local name = "mts-" .. planet .. "-" .. slot
    local pl = game.planets[name]
    if not pl then error("no planet " .. name) end
    local s = pl.surface or pl.create_surface()
    s.request_to_generate_chunks({ 0, 0 }, 3)
    s.force_generate_chunk_requests()
    return s.name
end

local function acc_sum(run)
    local e = 0
    for _, a in pairs(run.accs) do if a.valid then e = e + a.energy end end
    return e
end

local function snapshot(run)
    local s = game.surfaces[run.surface]
    local stats = run.pole.valid and run.pole.electric_network_statistics
    return {
        tick = game.tick,
        daytime = s.daytime,
        inp = stats and stats.input_counts or {},    -- consumption, J (cumulative)
        out = stats and stats.output_counts or {},   -- production, J (cumulative)
        acc = acc_sum(run),
        robo = run.roboport.valid and run.roboport.energy or -1,
    }
end

--- Register a surface whose starter base is already placed.
--- o = { force, planet, slot, load_kw, cycles, busy_bots, label }
function R.add_run(sname, o)
    local s = game.surfaces[sname]
    local f = o.force
    local run = { surface = sname, planet = o.planet, slot = o.slot, force = f,
                  label = o.label, busy_bots = o.busy_bots, damage = {}, died = {} }
    run.roboport = s.find_entities_filtered{ name = "bnm-roboport", force = f }[1]
    if not run.roboport then error("no bnm-roboport on " .. sname) end
    run.radar = s.find_entities_filtered{ type = "radar", force = f }[1]
    run.accs = s.find_entities_filtered{ type = "accumulator", force = f }
    run.pole = s.find_entities_filtered{ name = "substation", force = f }[1]
        or s.find_entities_filtered{ type = "electric-pole", force = f }[1]
    run.load = s.find_entities_filtered{ name = "bnm-rig-load" }[1]
        or s.create_entity{ name = "bnm-rig-load", position = run.roboport.position, force = f }
    run.base = s.find_entities_filtered{ force = f }  -- snapshot of the base, for health / freeze scans
    run.acc_cap = 0
    for _, a in pairs(run.accs) do run.acc_cap = run.acc_cap + a.electric_buffer_size end
    st().runs[sname] = run
    R.reset(sname, o)
    return { surface = sname, accs = #run.accs, acc_cap = run.acc_cap,
             load_network = run.load.electric_network_id, base_network = run.pole.electric_network_id,
             base_entities = #run.base }
end

--- Put a run back into its start state with a (new) test load.
function R.reset(sname, o)
    local run = st().runs[sname]
    local s = game.surfaces[sname]
    o = o or {}
    run.load_kw = o.load_kw or run.load_kw or 0
    run.cycles = o.cycles or run.cycles or 3
    local pu = run.load_kw * 1000 / 60
    run.load.power_usage = pu
    run.load.electric_buffer_size = math.max(pu * 2, 1)
    run.load.energy = run.load.electric_buffer_size
    if o.refill ~= false then
        for _, a in pairs(run.accs) do if a.valid then a.energy = a.electric_buffer_size end end
        if run.roboport.valid then run.roboport.energy = run.roboport.electric_buffer_size end
        s.daytime = o.daytime or 0
    end
    run.cycle_ticks = s.ticks_per_day
    run.t0 = game.tick
    run.samples, run.acc_empty_samples = 0, 0
    run.acc_min, run.acc_min_at = math.huge, nil
    run.robo_min, run.robo_min_at = math.huge, nil
    run.frozen = {}
    run.cyc = { { acc_min = math.huge, robo_min = math.huge, empty = 0 } }
    run.snap = { snapshot(run) }
    run.damage, run.died, run.damage_by_daytime = {}, {}, {}
    run.done = false
    run.lightning_dmg_base, run.lightning_dmg_bots = 0, 0
end

-- Keep construction bots flying (for the lightning-vs-robots probe): every call,
-- order the belts they built last time deconstructed and drop fresh ghosts.
local function busy_bots(run)
    local s = game.surfaces[run.surface]
    local rp = run.roboport
    if not rp.valid then return end
    for _, b in pairs(s.find_entities_filtered{ name = "transport-belt", force = run.force }) do
        b.order_deconstruction(run.force)
    end
    run.rng = run.rng or game.create_random_generator(run.slot or 1)
    local placed = 0
    for _ = 1, 40 do
        local ang, dist = run.rng() * 2 * math.pi, 20 + run.rng() * 70
        local p = { x = rp.position.x + math.cos(ang) * dist, y = rp.position.y + math.sin(ang) * dist }
        if s.can_place_entity{ name = "transport-belt", position = p, force = run.force } then
            s.create_entity{ name = "entity-ghost", inner_name = "transport-belt", position = p, force = run.force }
            placed = placed + 1
            if placed >= 12 then break end
        end
    end
end

local FROZEN_KEYS = { "roboport", "radar" }

function R.sample()
    local tick = game.tick
    for _, run in pairs(st().runs) do
        if not run.done and run.roboport.valid then
            local rel = tick - run.t0
            local k = math.floor(rel / run.cycle_ticks)        -- current cycle, 0-based
            if k >= #run.snap then                             -- crossed a day boundary
                run.snap[#run.snap + 1] = snapshot(run)
                if k >= run.cycles then run.done = true end
                run.cyc[#run.cyc + 1] = { acc_min = math.huge, robo_min = math.huge, empty = 0 }
            end
            if not run.done then
                local c = run.cyc[#run.cyc]
                local acc = acc_sum(run)
                local re = run.roboport.energy
                run.samples = run.samples + 1
                if acc < run.acc_min then run.acc_min, run.acc_min_at = acc, rel end
                if re < run.robo_min then run.robo_min, run.robo_min_at = re, rel end
                if acc < c.acc_min then c.acc_min = acc end
                if re < c.robo_min then c.robo_min = re end
                if acc <= run.acc_cap * R.EMPTY_FRACTION then
                    run.acc_empty_samples = run.acc_empty_samples + 1
                    c.empty = c.empty + 1
                end
                for _, key in pairs(FROZEN_KEYS) do
                    local e = run[key]
                    if e and e.valid and e.frozen and not run.frozen[key] then run.frozen[key] = rel end
                end
                if run.samples % 50 == 0 then   -- slower scan: anything else in the base frozen?
                    for _, e in pairs(run.base) do
                        if e.valid and e.frozen and not run.frozen[e.name] then run.frozen[e.name] = rel end
                    end
                end
                if run.busy_bots and run.samples % 43 == 0 then busy_bots(run) end
            end
        end
    end
end

local function on_damaged(e)
    local ent = e.entity
    if not (ent and ent.valid) then return end
    local run = st().runs[ent.surface.name]
    if not run then return end
    local key = ent.name .. "|" .. e.damage_type.name .. "|" .. ((e.cause and e.cause.valid and e.cause.name) or "-")
    run.damage[key] = (run.damage[key] or 0) + 1
    -- When in the day it happens (10 buckets of daytime, 0 = noon, 5 = midnight).
    run.damage_by_daytime = run.damage_by_daytime or {}
    local b = math.floor(ent.surface.daytime * 10) + 1
    run.damage_by_daytime[b] = (run.damage_by_daytime[b] or 0) + 1
end

local function on_died(e)
    local ent = e.entity
    if not (ent and ent.valid) then return end
    local run = st().runs[ent.surface.name]
    if not run then return end
    local key = ent.name .. "|" .. ((e.damage_type and e.damage_type.name) or "-")
    run.died[key] = (run.died[key] or 0) + 1
end

--- (Re)register the sampler and the damage probes. Call after loading this file.
function R.start(speed)
    script.on_nth_tick(R.SAMPLE, R.sample)
    script.on_event(defines.events.on_entity_damaged, on_damaged)
    script.on_event(defines.events.on_entity_died, on_died)
    if speed then game.speed = speed end
    return true
end

function R.stop()
    script.on_nth_tick(R.SAMPLE, nil)
    script.on_event(defines.events.on_entity_damaged, nil)
    script.on_event(defines.events.on_entity_died, nil)
    game.speed = 1
    return true
end

function R.status()
    local total, done, left = 0, 0, 0
    for _, run in pairs(st().runs) do
        total = total + 1
        if run.done then done = done + 1
        else
            local rem = run.t0 + run.cycles * run.cycle_ticks - game.tick
            if rem > left then left = rem end
        end
    end
    return { tick = game.tick, total = total, done = done, ticks_left = left, speed = game.speed }
end

local KW = 60 / 1000   -- J per tick-span -> kW, after dividing by the span in ticks

--- Everything measured for one run, per cycle, in kW / MJ.
function R.report(sname)
    local run = st().runs[sname]
    local s = game.surfaces[sname]
    local r = {
        surface = sname, planet = run.planet, label = run.label, load_kw = run.load_kw,
        cycle_ticks = run.cycle_ticks, cycles_done = #run.snap - 1, done = run.done,
        acc_cap_mj = run.acc_cap / 1e6,
        acc_min_mj = run.acc_min / 1e6, acc_min_at = run.acc_min_at,
        acc_empty_samples = run.acc_empty_samples, samples = run.samples,
        robo_min_mj = run.robo_min / 1e6, robo_min_at = run.robo_min_at,
        frozen = run.frozen, damage = run.damage, died = run.died,
        damage_by_daytime = run.damage_by_daytime,
        solar_mult = s.solar_power_multiplier,
        daytimes = { dusk = s.dusk, evening = s.evening, morning = s.morning, dawn = s.dawn },
        cycles = {},
    }
    for i = 1, #run.snap - 1 do
        local a, b = run.snap[i], run.snap[i + 1]
        local dt = b.tick - a.tick
        local c = { ticks = dt, cons = {}, prod = {},
                    acc_start_mj = a.acc / 1e6, acc_end_mj = b.acc / 1e6,
                    robo_start_mj = a.robo / 1e6, robo_end_mj = b.robo / 1e6,
                    acc_min_mj = run.cyc[i].acc_min / 1e6, robo_min_mj = run.cyc[i].robo_min / 1e6,
                    empty_samples = run.cyc[i].empty }
        for n, v in pairs(b.inp) do c.cons[n] = (v - (a.inp[n] or 0)) / dt * KW end
        for n, v in pairs(b.out) do c.prod[n] = (v - (a.out[n] or 0)) / dt * KW end
        r.cycles[i] = c
    end
    return r
end

function R.reports()
    local out = {}
    for name in pairs(st().runs) do out[#out + 1] = R.report(name) end
    return out
end

function R.forget(sname) st().runs[sname] = nil end

return true
