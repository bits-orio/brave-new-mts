-- events/player_controller.lua
-- Zoom continuity when a player drops from remote view back into the physical
-- view (e.g. pressing Esc). We ONLY match the zoom here -- we do NOT re-lock
-- the controller (that trapped players and broke the Esc menu) and we do NOT
-- move the body (it's already pinned at origin by remote_player.make_remote).
--
-- Entering remote view is handled in make_remote, so we ignore that direction.

local M = {}

function M.register()
    script.on_event(defines.events.on_player_controller_changed, function(event)
        local player = game.get_player(event.player_index)
        if not (player and player.valid) then return end
        if player.character then return end                              -- pen / character: ignore
        if player.controller_type == defines.controllers.remote then return end  -- entering remote: handled elsewhere

        -- Dropped into the physical view on a team surface: match the zoom we
        -- left remote view at. Body stays where it is (pinned at origin).
        if not remote.interfaces["mts-v1"] then return end
        local surface = player.physical_surface or player.surface
        if not (surface and surface.valid) then return end
        if not remote.call("mts-v1", "get_surface_owner", surface.name) then return end

        local z = storage.view_zoom and storage.view_zoom[player.index]
        if z then player.zoom = z end
    end)
end

return M
