-- tools/rig/lua/regress_player.lua
-- regress.py's simulated player, loaded into BNM's own state after
-- regress.lua. A real player needs a client, so a stand-in table drives
-- scripts/remote_player.lua's leave and reconnect path (check 12).

REG = REG or {}
local R = REG

local FAKE_INDEX = 9999

--- A stand-in for a LuaPlayer of `force_name`, looking at `surface_name` at
--- `pos`. park() calls only plain fields and functions on it; set_controller
--- records its parameters in `calls`.
local function fake_player(force_name, surface_name, pos, calls, controller)
    return {
        valid = true, connected = true, index = FAKE_INDEX, name = "reg-fake-player",
        force = game.forces[force_name], surface = game.surfaces[surface_name], position = pos,
        controller_type = controller or defines.controllers.remote,
        physical_controller_type = defines.controllers.character,
        character = { valid = true, unit_number = -FAKE_INDEX, clear_items_inside = function() end },
        teleport = function() return true end,
        set_controller = function(p)
            calls[#calls + 1] = { surface = p.surface and p.surface.name,
                                  x = p.position and p.position.x, y = p.position and p.position.y }
        end,
    }
end

local function forget_fake(force_name)
    for _, key in pairs({ "home_surface", "last_view", "last_view_pos" }) do
        if storage[key] then storage[key][FAKE_INDEX] = nil end
    end
    if storage.park_index and storage.park_index[force_name] then
        storage.park_index[force_name][FAKE_INDEX] = nil
    end
    if storage.emptied_body then storage.emptied_body[-FAKE_INDEX] = nil end
end

local function spot() return storage.last_view_pos and storage.last_view_pos[FAKE_INDEX] end

--- Drive remote_player's leave and reconnect path with a fake player of
--- `force_name`: leave while looking at `a` (own ground), reconnect, re-park;
--- leave looking at `rival` (another team's ground) or in the character
--- controller; leave on `a`, then look at `b` before the re-park.
function R.sim_reconnect(force_name, a, b, rival)
    local rp = R.module("scripts/remote_player")
    local calls, out = {}, {}
    local here = { x = 60.5, y = -30.25 }
    forget_fake(force_name)
    rp.remember_view_spot(fake_player(force_name, a, here, calls))
    out.stored = spot() and { surface = spot().surface, x = spot().x, y = spot().y } or false
    out.last_view = storage.last_view[FAKE_INDEX]
    out.reconnect = rp.park(fake_player(force_name, a, { x = 0, y = 0 }, calls)) and calls[#calls] or false
    out.consumed = spot() == nil
    out.repark = rp.park(fake_player(force_name, a, { x = 0, y = 0 }, calls)) and calls[#calls] or false
    forget_fake(force_name)
    rp.remember_view_spot(fake_player(force_name, rival, here, calls))
    out.rival_stored = spot() ~= nil
    rp.remember_view_spot(fake_player(force_name, a, here, calls, defines.controllers.character))
    out.character_stored = spot() ~= nil
    rp.remember_view_spot(fake_player(force_name, a, here, calls))
    storage.last_view[FAKE_INDEX] = b
    out.moved = rp.park(fake_player(force_name, b, { x = 0, y = 0 }, calls)) and calls[#calls] or false
    out.moved_consumed = spot() == nil
    forget_fake(force_name)
    return out
end

return true
