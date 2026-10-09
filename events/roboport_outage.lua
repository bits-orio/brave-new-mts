-- events/roboport_outage.lua
-- Tells a team when one of its bases' roboports goes dark (its network shut
-- down for lack of power, scripts/rescue.lua) and how to get it back: the
-- base's power recharges it in time, or the team leader spends a rescue now.
-- A team with none left is pointed at an admin.
--
-- A scan, because the engine raises no event when a roboport's network
-- switches off. It reads one cell per base, every 10 seconds: a dark roboport
-- stays dark for minutes. base.dark remembers what was announced, so each
-- outage is announced once; the return is silent (a rescue says so itself).

local rescue = require("scripts.rescue")
local chat   = require("scripts.chat")

local M = {}

local INTERVAL = 600  -- ticks

local function remedy(force_name)
    local left = rescue.left(force_name)
    if left == 0 then
        return "Your team has no rescues left; an admin can restart it with /bnm-rescue."
    end
    return "Your team leader can restart it now with a rescue, in Team Settings > Brave New MTS ("
        .. left .. " left)."
end

local function announce(force_name, surface_name)
    local force, surface = game.forces[force_name], game.surfaces[surface_name]
    if not (force and surface) then return end
    force.print({ "", chat.PREFIX, "Your ", chat.planet_label(surface), " base's roboport is out "
        .. "of power, so its robots have stopped. It restarts once the base's power has recharged "
        .. "it. ", remedy(force_name) })
    log("[brave-new-mts] " .. force_name .. "'s roboport on " .. surface_name .. " is out of power")
end

local function scan()
    for surface_name, base in pairs(storage.bnm_base or {}) do
        local dark = rescue.is_dark(base)
        if dark and not base.dark then announce(base.force, surface_name) end
        base.dark = dark or nil
    end
end

--- Engine event only: safe in on_init, on_load and on_configuration_changed.
function M.register()
    script.on_nth_tick(INTERVAL, scan)
end

return M
