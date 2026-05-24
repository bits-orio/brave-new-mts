-- events/player_surface.lua
-- Starter-base placement is triggered the first time a team member reaches an
-- owned team surface. on_player_changed_surface is a base-game event, so we
-- don't depend on MTS's internal surface-creation timing; we only ask MTS
-- (via mts-v1) whether the surface belongs to a team. This naturally covers
-- the home surface and every planet the team later travels to.
--
-- EMPIRICAL CHECKPOINT (Phase 3): with no character, does merely switching
-- the remote-view surface fire on_player_changed_surface? If so we may place
-- bases on planets the team is only *looking* at. If that proves true, switch
-- the trigger to the mts-v1 on_team_surface_created event instead.

local starter_base = require("scripts.starter_base")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_changed_surface, function(event)
        local player = game.get_player(event.player_index)
        if not (player and player.valid) then return end
        starter_base.maybe_place_for_player(player)
    end)
end

return M
