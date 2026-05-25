-- events/player_controller.lua
-- Lock character-less team players into remote view. The physical (god)
-- controller is the only thing that charts the map (remote view never does),
-- so whenever a player leaves remote view onto a team surface we snap them
-- straight back. There is no engine API to disable per-player charting or to
-- lock a controller, so this on_player_controller_changed re-assert is the
-- supported approach (per the Factorio devs).
--
-- Guard: we only act when the NEW controller is not already remote, so our own
-- set_controller(remote) doesn't recurse.
--
-- KNOWN WART (verify in-game): pressing Esc exits remote view; snapping back
-- may interfere with opening the pause menu.

local remote_player = require("scripts.remote_player")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_controller_changed, function(event)
        local player = game.get_player(event.player_index)
        if not (player and player.valid) then return end
        if player.controller_type == defines.controllers.remote then return end
        remote_player.ensure_remote_if_team_surface(player)
    end)
end

return M
