-- scripts/movement_clamp.lua
-- Character-less players can toggle into the physical first-person view and
-- walk, which charts fresh chunks and exposes the map. We can't block walking
-- outright (start_walking also drives remote-view panning), so we clamp the
-- physical body to already-charted territory -- the Brave New OARC approach.
--
-- Remote view (render_mode ~= game) is never clamped, so camera panning stays
-- free. Only the physical first-person view (render_mode == game), where
-- walking actually charts, is constrained.

local CHUNK = 32

local M = {}

--- Charted here AND the diagonal neighbours are charted-or-ungenerated -- a
--- buffer so the body can't walk right up to the fog edge and reveal beyond.
local function chunk_charted(force, surface, cx, cy)
    return force.is_chunk_charted(surface, {cx, cy})
        and (force.is_chunk_charted(surface, {cx - 2, cy - 2}) or not surface.is_chunk_generated({cx - 2, cy - 2}))
        and (force.is_chunk_charted(surface, {cx - 2, cy + 2}) or not surface.is_chunk_generated({cx - 2, cy + 2}))
        and (force.is_chunk_charted(surface, {cx + 2, cy - 2}) or not surface.is_chunk_generated({cx + 2, cy - 2}))
        and (force.is_chunk_charted(surface, {cx + 2, cy + 2}) or not surface.is_chunk_generated({cx + 2, cy + 2}))
end

function M.on_changed_position(player)
    if not (player and player.valid) then return end
    -- Only the character-less physical body, only in the physical view.
    if player.character then return end
    if player.render_mode ~= defines.render_mode.game then return end

    local surface = player.physical_surface or player.surface
    if not (surface and surface.valid) or surface.name == "landing-pen" then return end

    storage.prev_physical_pos = storage.prev_physical_pos or {}
    local pos   = player.physical_position or player.position
    local prev  = storage.prev_physical_pos[player.index] or pos
    local force = player.force

    local cx = math.floor(pos.x / CHUNK)
    local cy = math.floor(pos.y / CHUNK)
    if not chunk_charted(force, surface, cx, cy) then
        -- Allow sliding along whichever axis stays in charted territory.
        if chunk_charted(force, surface, cx, math.floor(prev.y / CHUNK)) then
            prev = { x = pos.x, y = prev.y }
        elseif chunk_charted(force, surface, math.floor(prev.x / CHUNK), cy) then
            prev = { x = prev.x, y = pos.y }
        end
        player.teleport(prev, surface)
        player.print("Beyond charted territory — deploy radars to expand your reach.",
            { sound = defines.print_sound.never })
        pos = prev
    end

    storage.prev_physical_pos[player.index] = pos
end

return M
