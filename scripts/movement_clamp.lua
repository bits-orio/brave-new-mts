-- scripts/movement_clamp.lua
-- Character-less players can toggle into the physical (god) view and walk,
-- which charts fresh chunks and exposes the map. We can't block walking
-- outright (start_walking also drives remote-view panning), so we clamp the
-- physical body to (just past) already-charted territory.
--
-- The gate is the CONTROLLER, not the render mode: in remote view the player
-- is in controllers.remote (so is MTS's spectate), and panning there never
-- charts -- we skip it. Every physical-body state (the god controller, at any
-- zoom -- first-person OR the zoomed-out abstract view) charts on the move, so
-- we clamp all of them.
--
-- prev_physical_pos is stored ONLY while in an allowed position, so it is
-- always a valid spot to snap back to -- never the rejected one.

local CHUNK = 32

-- How far (tiles) the body may dip PAST the charted boundary before being
-- snapped back. Keep under CHUNK/2 (16) so we stay below half a chunk into
-- uncharted territory, where new charting doesn't trigger. Tune to taste.
local EDGE_SLACK = 14

local M = {}

local function chunk_charted_at(force, surface, x, y)
    return force.is_chunk_charted(surface, { math.floor(x / CHUNK), math.floor(y / CHUNK) })
end

--- Allowed if standing in a charted chunk, or within EDGE_SLACK tiles of one
--- orthogonally (i.e. we've dipped less than EDGE_SLACK tiles into uncharted).
local function position_allowed(force, surface, pos)
    return chunk_charted_at(force, surface, pos.x, pos.y)
        or chunk_charted_at(force, surface, pos.x - EDGE_SLACK, pos.y)
        or chunk_charted_at(force, surface, pos.x + EDGE_SLACK, pos.y)
        or chunk_charted_at(force, surface, pos.x, pos.y - EDGE_SLACK)
        or chunk_charted_at(force, surface, pos.x, pos.y + EDGE_SLACK)
end

function M.on_changed_position(player)
    if not (player and player.valid) then return end
    -- Only the character-less physical body. Skip remote view (and MTS
    -- spectate) -- both use the remote controller and don't chart on pan.
    if player.character then return end
    if player.controller_type == defines.controllers.remote then return end

    local surface = player.physical_surface or player.surface
    if not (surface and surface.valid) or surface.name == "landing-pen" then return end

    storage.prev_physical_pos = storage.prev_physical_pos or {}
    local pos = player.physical_position or player.position

    if position_allowed(player.force, surface, pos) then
        storage.prev_physical_pos[player.index] = { x = pos.x, y = pos.y }
        return
    end

    local prev = storage.prev_physical_pos[player.index]
    if prev then
        player.teleport(prev, surface)
    end
    player.print("Beyond charted territory — deploy radars to expand your reach.",
        { sound = defines.print_sound.never })
end

return M
