-- scripts/remote_player.lua
-- Parks a team player's CHARACTER in their team's landing-pen cell and puts the
-- player into remote view of their team surface. The character never sets foot
-- on the team surface, so it can't chart or collide with it -- and remote-view
-- placement is naturally ghosts, which robots build. No god controller, no
-- instant-build, no charting hacks.

local pen_cells = require("scripts.pen_cells")

local M = {}

local function is_team_force(name)
    return name:match("^team%-%d+$") ~= nil
end

--- Lowest free slot index within a team's cell for this player (stable once set).
local function slot_for(force_name, player_index)
    storage.park_index = storage.park_index or {}
    storage.park_index[force_name] = storage.park_index[force_name] or {}
    local slots = storage.park_index[force_name]
    if slots[player_index] then return slots[player_index] end

    local used = {}
    for _, s in pairs(slots) do used[s] = true end
    local idx = 0
    while used[idx] do idx = idx + 1 end
    slots[player_index] = idx
    return idx
end

--- Park `player` for their team and view their team surface. `team_surface` is
--- the surface to view; if omitted, the player's remembered home surface is used
--- (so a reconnecting player is re-asserted into remote view).
function M.park(player, team_surface)
    if not (player and player.valid) then return end
    if not remote.interfaces["mts-v1"] then return end

    local fn = player.force.name
    if not is_team_force(fn) then return end  -- not on a team (e.g. in the pen)

    storage.home_surface = storage.home_surface or {}
    if team_surface and team_surface.valid then
        storage.home_surface[player.index] = team_surface.name
    else
        local name = storage.home_surface[player.index]
        team_surface = name and game.surfaces[name]
    end
    if not (team_surface and team_surface.valid) then return end

    pen_cells.ensure_built()
    local pen = game.surfaces["landing-pen"]
    if not (pen and pen.valid) then return end

    -- Ensure a character exists to park (MTS provides one on spawn; create as a
    -- fallback for any path that doesn't).
    if not player.character then
        player.set_controller{ type = defines.controllers.god }
        player.create_character()
    end

    local pos = pen_cells.park_position(fn, slot_for(fn, player.index))
    if not pos then return end

    player.teleport(pos, pen)
    if player.character then player.character.destructible = false end
    player.set_controller{
        type     = defines.controllers.remote,
        surface  = team_surface,
        position = { 0, 0 },
    }
    log("[brave-new-mts] parked " .. player.name .. " in " .. fn
        .. " cell; viewing " .. team_surface.name)
end

--- Release a player's parked slot and home surface (on leaving a team). MTS's
--- return_to_pen moves the body back to the selection ring; we just free state.
function M.unpark(player)
    if not (player and player.valid) then return end
    if storage.park_index then
        for _, team in pairs(storage.park_index) do
            team[player.index] = nil
        end
    end
    if storage.home_surface then
        storage.home_surface[player.index] = nil
    end
end

return M
