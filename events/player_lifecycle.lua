-- events/player_lifecycle.lua
-- Brave New MTS players have no character once they are on a team surface.
-- The character-removal itself is gated on team-surface ownership (see
-- remote_player.ensure_remote_if_team_surface), so these handlers are safe to
-- fire during the landing-pen phase too -- they simply no-op until the player
-- is actually on their team's surface.
--
-- on_player_changed_surface (events/player_surface.lua) is the PRIMARY trigger
-- and catches the spawn into the world. These cover the rest: a player who
-- rejoins directly onto their team surface (no surface-change event), and the
-- no-landing-pen flow where MTS spawns the player within on_player_created.

local remote_player = require("scripts.remote_player")

local M = {}

function M.register()
    local function ensure(event)
        remote_player.ensure_remote_if_team_surface(game.get_player(event.player_index))
    end

    script.on_event(defines.events.on_player_created,     ensure)
    script.on_event(defines.events.on_player_joined_game, ensure)
    script.on_event(defines.events.on_player_respawned,   ensure)
end

return M
