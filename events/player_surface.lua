-- events/player_surface.lua
-- PRIMARY trigger for both jobs: when a player arrives on a team-owned surface
-- (the spawn into the world, or travel to another team planet), strip their
-- character into remote view and seed the starter base for that surface.
--
-- on_player_changed_surface is a base-game event, so we don't depend on MTS's
-- internal surface-creation timing; we only ask MTS (via mts-v1) whether the
-- surface belongs to a team. The landing-pen surface is unowned, so the
-- team-selection phase is naturally skipped.
--
-- EMPIRICAL CHECKPOINT (Phase 3): with no character, does merely switching the
-- remote-view surface fire on_player_changed_surface? If so we may place bases
-- on planets the team is only *looking* at. If that proves true, switch the
-- base-placement trigger to the mts-v1 on_team_surface_created event.

local remote_player = require("scripts.remote_player")
local starter_base  = require("scripts.starter_base")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_changed_surface, function(event)
        local player = game.get_player(event.player_index)
        local owner, surface = remote_player.ensure_remote_if_team_surface(player)
        if owner then
            starter_base.place(owner, surface)
        end
    end)
end

return M
