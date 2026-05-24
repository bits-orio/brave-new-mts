-- events/player_movement.lua
-- Clamp character-less physical movement to charted areas (see
-- scripts/movement_clamp.lua). Event-driven: fires only when the player's
-- position actually changes.

local movement_clamp = require("scripts.movement_clamp")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_changed_position, function(event)
        movement_clamp.on_changed_position(game.get_player(event.player_index))
    end)
end

return M
