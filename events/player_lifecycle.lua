-- events/player_lifecycle.lua
-- Brave New MTS players have no character. The engine can hand a player a
-- body on three paths -- creation, joining, and respawn -- so we strip it on
-- all three and drop the player into remote view.
--
-- ORDER NOTE: this mod depends on multi-team-support, so MTS's own
-- on_player_created handler (which claims a team slot and spawns the player
-- into the world) runs BEFORE ours. We remove the character it just created.
-- Confirm this ordering holds in-game during Phase 2.

local remote_player = require("scripts.remote_player")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_created, function(event)
        remote_player.make_remote(game.get_player(event.player_index))
    end)

    script.on_event(defines.events.on_player_joined_game, function(event)
        remote_player.make_remote(game.get_player(event.player_index))
    end)

    script.on_event(defines.events.on_player_respawned, function(event)
        remote_player.make_remote(game.get_player(event.player_index))
    end)
end

return M
