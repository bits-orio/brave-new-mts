-- scripts/movement_clamp.lua
-- Character-less players can toggle into the physical first-person/god view and
-- walk, which charts fresh chunks and exposes the map. We can't block walking
-- outright (start_walking also drives remote-view panning), so we clamp the
-- physical body to already-charted territory -- the Brave New OARC approach.
--
-- Remote view (render_mode ~= game) is never clamped, so camera panning stays
-- free. Only the physical view (render_mode == game), where walking actually
-- charts, is constrained.
--
-- prev_physical_pos is stored ONLY while standing in a charted chunk, so it is
-- always a valid "good" position to snap back to -- never the uncharted spot
-- we're trying to reject.

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
    local pos = player.physical_position or player.position
    local cx  = math.floor(pos.x / CHUNK)
    local cy  = math.floor(pos.y / CHUNK)

    if chunk_charted(player.force, surface, cx, cy) then
        -- Standing on charted ground: remember it as the snap-back point.
        storage.prev_physical_pos[player.index] = { x = pos.x, y = pos.y }
        return
    end

    -- Uncharted: snap back to the last charted position.
    local prev = storage.prev_physical_pos[player.index]
    if prev then
        player.teleport(prev, surface)
    end
    player.print("Beyond charted territory — deploy radars to expand your reach.",
        { sound = defines.print_sound.never })

    log(("[brave-new-mts] clamp %s render=%s ctrl=%s pos=(%.1f,%.1f) -> prev=%s")
        :format(player.name, tostring(player.render_mode), tostring(player.controller_type),
                pos.x, pos.y, prev and ("(" .. prev.x .. "," .. prev.y .. ")") or "nil"))
end

return M
