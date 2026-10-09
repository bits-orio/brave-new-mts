-- scripts/planet_delete.lua
-- A team deletes its copy of a planet, to start over there. The surface and
-- everything on it go, and the team's next Character Clone above the planet
-- founds a fresh outpost on new ground (events/platform_hub.lua creates the
-- surface again). The team leader does it from the team tab
-- (scripts/team_tab/delete_section.lua). The home planet is never deleted:
-- its base is the one whose loss ends the team.
--
-- The surface goes through game.delete_surface, as an admin's delete would,
-- and events/surface_deleted.lua forgets the base record. Not MTS's
-- retire_team_surface: that also drops MTS's planet-to-team entry, and a
-- planet created again without it has no owner, so Establish base would
-- refuse it.

local remote_player = require("scripts.remote_player")
local remote_view   = require("scripts.remote_view")
local starter_base  = require("scripts.starter_base")

local M = {}

local function owner(surface)
    return remote.call("mts-v1", "get_surface_owner", surface.name)
end

local function is_home(surface)
    local base = starter_base.base_for(surface.name)
    return (base and base.home) or starter_base.is_home_planet(surface.planet.name)
end

--- Why the team cannot delete the planet surface `surface_name`, or nil.
function M.refusal(force_name, surface_name)
    if not remote.interfaces["mts-v1"] then return "Multi-Team Support isn't running" end
    local surface = game.surfaces[surface_name]
    if not (surface and surface.valid and surface.planet) then return "there is no such planet" end
    if owner(surface) ~= force_name then return "that planet isn't your team's" end
    if is_home(surface) then return "your home planet can't be deleted" end
    return nil
end

--- The surface names of the planets the team may delete, sorted.
function M.deletable(force_name)
    if not remote.interfaces["mts-v1"] then return {} end
    local out = {}
    for _, name in pairs(remote.call("mts-v1", "list_team_surfaces", force_name)) do
        if not M.refusal(force_name, name) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

--- Move every connected player looking at the surface back onto their own
--- team's ground, before the surface goes. park() leaves alone anyone it
--- cannot park (a player in the pen, a rival's spectator).
local function repark_viewers(surface_name)
    remote_view.forget_surface(surface_name)
    for _, player in pairs(game.connected_players) do
        if player.surface.name == surface_name then remote_player.park(player) end
    end
end

--- Delete the team's planet surface `surface_name`. The engine deletes it at
--- the end of the tick. Returns ok, and the reason when not.
function M.delete(force_name, surface_name)
    local why = M.refusal(force_name, surface_name)
    if why then return false, why end
    repark_viewers(surface_name)
    game.delete_surface(surface_name)
    log("[brave-new-mts] " .. force_name .. " deleted its planet " .. surface_name)
    return true
end

return M
