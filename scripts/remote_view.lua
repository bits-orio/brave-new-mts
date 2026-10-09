-- scripts/remote_view.lua
-- What a parked player's remote view shows (scripts/remote_player.lua parks
-- them and switches them into it).
--
-- Which surface a re-park views, in order: the last own-team surface the
-- player looked at in remote view (storage.last_view), their home surface
-- (storage.home_surface, set when they first arrived), then the team's home
-- base. The view is centred on the base's roboport, except on a reconnect:
-- a player who left while looking at their own team's ground gets that spot
-- back (storage.last_view_pos, used once).

local starter_base = require("scripts.starter_base")

local M = {}

local function owner_of(surface_name)
    return remote.call("mts-v1", "get_surface_owner", surface_name)
end

--- The named surface, if it exists and `force_name` owns it.
function M.owned_surface(name, force_name)
    local surface = name and game.surfaces[name]
    if surface and surface.valid and owner_of(surface.name) == force_name then
        return surface
    end
end

--- The surface name of a team's home (first) base, if one is recorded.
function M.team_home(force_name)
    local _, surface_name = starter_base.home_of(force_name)
    return surface_name
end

--- Where the view on `surface` is centred: the spot the player was looking at
--- when they left, if that was on this surface, else the base's roboport. The
--- spot is used once, so a later re-park (a spectate's return, /bnm-repark)
--- centres on the base again. Reading it clears it: call this only once the
--- park can no longer fail, or a failed park loses the reconnect's spot.
function M.position_for(player, surface)
    local spots = storage.last_view_pos
    local spot  = spots and spots[player.index]
    if not spot then return starter_base.BASE_ORIGIN end
    spots[player.index] = nil
    if spot.surface ~= surface.name then return starter_base.BASE_ORIGIN end
    return { x = spot.x, y = spot.y }
end

--- The surface a re-park views (see the header for the order), or nil.
function M.surface_for(player)
    local fn = player.force.name
    local last = storage.last_view and storage.last_view[player.index]
    local home = storage.home_surface and storage.home_surface[player.index]
    return M.owned_surface(last, fn) or M.owned_surface(home, fn)
        or M.owned_surface(M.team_home(fn), fn)
end

--- The surface a player is looking at, if it is their own team's ground
--- (platforms excluded: a re-park centres the view on a base origin).
local function viewed_own_ground(player)
    local surface = player.surface
    if not (surface and surface.valid) or surface.platform then return nil end
    if owner_of(surface.name) ~= player.force.name then return nil end
    return surface
end

--- Remember the surface a remote-view player is looking at, if it is their own
--- team's ground. Returns that surface, or nil.
function M.remember_view(player)
    local surface = viewed_own_ground(player)
    if not surface then return nil end
    storage.last_view = storage.last_view or {}
    storage.last_view[player.index] = surface.name
    return surface
end

--- Drop every player's reference to a surface that is about to be deleted,
--- so a re-park made before the deletion lands never picks it.
function M.forget_surface(surface_name)
    for _, key in ipairs({ "last_view", "home_surface" }) do
        local names = storage[key] or {}
        for index, name in pairs(names) do
            if name == surface_name then names[index] = nil end
        end
    end
    local spots = storage.last_view_pos or {}
    for index, spot in pairs(spots) do
        if spot.surface == surface_name then spots[index] = nil end
    end
end

--- A player is leaving: if they are in remote view of their own team's ground
--- (not from the map editor), remember the surface and the spot, so their
--- reconnect's park() puts the view back there.
function M.remember_view_spot(player)
    if not (player and player.valid) then return end
    if not remote.interfaces["mts-v1"] then return end
    if player.controller_type ~= defines.controllers.remote then return end
    if player.physical_controller_type == defines.controllers.editor then return end
    local surface = M.remember_view(player)
    if not surface then return end
    storage.last_view_pos = storage.last_view_pos or {}
    storage.last_view_pos[player.index] = {
        surface = surface.name, x = player.position.x, y = player.position.y,
    }
end

return M
