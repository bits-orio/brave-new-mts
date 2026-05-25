-- events/player_movement.lua
-- Keep character-less team players in remote view WITHOUT trapping them there.
--
-- We deliberately do NOT lock the controller on every change: pressing Esc
-- leaves remote view, and re-locking immediately ate the second Esc that opens
-- the pause menu (so players couldn't even quit). Instead we snap back to
-- remote view only when the physical body actually MOVES:
--   * Standing still in the physical view (e.g. to open the Esc menu) is fine.
--   * Any physical movement -- the only thing that charts the map -- bounces
--     the player straight back into remote view, so no new map is exposed.

local remote_player = require("scripts.remote_player")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_changed_position, function(event)
        local player = game.get_player(event.player_index)
        if not (player and player.valid) then return end
        -- Has a character (landing-pen team picker) -> leave alone.
        if player.character then return end
        -- Already in remote view -> panning there never charts.
        if player.controller_type == defines.controllers.remote then return end
        -- Character-less and moving in the physical view: snap back to remote
        -- view (ensure_remote_if_team_surface gates this to team surfaces).
        remote_player.ensure_remote_if_team_surface(player)
    end)
end

return M
