-- tools/rig/lua/regress_rescue.lua
-- regress.py's helpers for a roboport out of power and the team's way back
-- (checks 17 and 18: fed first, rescues) and for deleting a planet (check 19),
-- loaded into BNM's own state after regress.lua. A base is starved with the
-- sun frozen, its accumulators and roboport emptied, and optionally a
-- bnm-rig-load (tools/rig/hooks: a secondary-input load, as a machine is) on
-- its network.

REG = REG or {}
local R = REG

local LOAD = "bnm-rig-load"
local FAKE_VIEWER = 9998   -- no real player has it; regress_player.lua uses 9999

local function rescue() return R.module("scripts/rescue") end
local function planet_delete() return R.module("scripts/planet_delete") end

--- A base's roboport and network, as the checks judge them.
function R.robo_state(surface_name)
    local base = R.module("scripts/starter_base").base_for(surface_name)
    local rp = base and base.roboport
    if not (rp and rp.valid) then return { exists = false } end
    local cell = rp.logistic_cell
    return { exists = true, energy_mj = rp.energy / 1e6, buffer_mj = rp.electric_buffer_size / 1e6,
             transmitting = (cell and cell.transmitting) or false, network = rp.logistic_network ~= nil,
             dark = rescue().is_dark(base) }
end

--- Set the test load on the force's network on `s` to `kw` (0 removes it).
local function set_load(s, force_name, position, kw)
    local load = s.find_entities_filtered{ name = LOAD, force = force_name }[1]
    if kw == 0 then
        if load then load.destroy() end
        return
    end
    load = load or s.create_entity{ name = LOAD, position = position, force = force_name }
    local per_tick = kw * 1000 / 60
    load.power_usage = per_tick
    load.electric_buffer_size = per_tick * 2
end

--- Starve a base: the sun frozen at `daytime` (0 noon, 0.5 midnight), its
--- accumulators and roboport emptied, and a test load of `load_kw` on it.
function R.starve(surface_name, force_name, daytime, load_kw)
    local s = game.surfaces[surface_name]
    s.daytime = daytime
    s.freeze_daytime = true
    for _, a in pairs(s.find_entities_filtered{ type = "accumulator", force = force_name }) do a.energy = 0 end
    local rp = R.roboport(surface_name, force_name)
    rp.energy = 0
    set_load(s, force_name, rp.position, load_kw)
    return true
end

--- Let the day run again and take the test load away.
function R.unstarve(surface_name, force_name)
    local s = game.surfaces[surface_name]
    s.freeze_daytime = false
    set_load(s, force_name, nil, 0)
    return true
end

-- ─── Rescues ─────────────────────────────────────────────────────────

--- rescue.spend, as the team tab's Rescue button calls it.
function R.rescue_spend(force_name, surface_name)
    local ok, why = rescue().spend(force_name, surface_name)
    return { ok = ok, reason = why or false, left = rescue().left(force_name) }
end

--- The team's rescues left, after forgetting what it spent (a released slot).
function R.rescue_reset(force_name)
    rescue().cleanup_force(force_name)
    return rescue().left(force_name)
end

-- ─── Deleting a planet ───────────────────────────────────────────────

function R.deletable(force_name)
    return planet_delete().deletable(force_name)
end

--- planet_delete.delete, as the team tab's confirm button calls it.
function R.delete_planet(force_name, surface_name)
    local ok, why = planet_delete().delete(force_name, surface_name)
    return { ok = ok, reason = why or false }
end

--- A stand-in viewer whose last view, home surface and reconnect spot are
--- all on `surface_name`, so a delete can be seen to drop each.
function R.fake_viewer(surface_name)
    for _, key in pairs({ "last_view", "home_surface" }) do
        storage[key] = storage[key] or {}
        storage[key][FAKE_VIEWER] = surface_name
    end
    storage.last_view_pos = storage.last_view_pos or {}
    storage.last_view_pos[FAKE_VIEWER] = { surface = surface_name, x = 0, y = 0 }
    return true
end

--- What is left of the stand-in viewer's references; forgets them.
function R.fake_viewer_left()
    local out = { last_view = storage.last_view[FAKE_VIEWER] or false,
                  home_surface = storage.home_surface[FAKE_VIEWER] or false,
                  spot = storage.last_view_pos[FAKE_VIEWER] ~= nil }
    storage.last_view[FAKE_VIEWER] = nil
    storage.home_surface[FAKE_VIEWER] = nil
    storage.last_view_pos[FAKE_VIEWER] = nil
    return out
end
