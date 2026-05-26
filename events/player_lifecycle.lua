-- events/player_lifecycle.lua
-- Re-assert parking + remote view on the lifecycle events (using each player's
-- remembered home surface), and release the parked slot when a player leaves
-- their team. The primary parking trigger is arrival on a team surface
-- (events/player_surface.lua); these cover reconnects and respawns.

local remote_player = require("scripts.remote_player")

local M = {}

function M.register()
    local function reassert(event)
        remote_player.park(game.get_player(event.player_index))
    end

    script.on_event(defines.events.on_player_created,     reassert)
    script.on_event(defines.events.on_player_joined_game, reassert)
    script.on_event(defines.events.on_player_respawned,   reassert)

    -- Left a team (MTS moves them off the team force): free the parked slot.
    -- MTS's return_to_pen relocates the body to the selection ring.
    script.on_event(defines.events.on_player_changed_force, function(event)
        local player = game.get_player(event.player_index)
        if not (player and player.valid) then return end
        if not player.force.name:match("^team%-%d+$") then
            remote_player.unpark(player)
        end
    end)
end

return M
