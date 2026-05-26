-- events/player_surface.lua
-- PRIMARY trigger: when a player's character lands on a team-owned surface (the
-- spawn into the world), seed the starter base there and then PARK the
-- character in the team's landing-pen cell, switching the player to remote view
-- of the team surface.
--
-- After parking, the character is on the landing-pen surface, so the re-fired
-- surface-change (to the pen, which has no team owner) is ignored -- no loop.

local remote_player = require("scripts.remote_player")
local starter_base  = require("scripts.starter_base")

local M = {}

function M.register()
    script.on_event(defines.events.on_player_changed_surface, function(event)
        local player = game.get_player(event.player_index)
        if not (player and player.valid) then return end
        if not remote.interfaces["mts-v1"] then return end

        local surface = player.physical_surface or player.surface
        if not (surface and surface.valid) then return end

        local owner = remote.call("mts-v1", "get_surface_owner", surface.name)
        if not owner then return end  -- not a team surface (pen, etc.)

        starter_base.place(owner, surface)
        remote_player.park(player, surface)
    end)
end

return M
