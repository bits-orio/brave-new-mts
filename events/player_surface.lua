-- events/player_surface.lua
-- PRIMARY trigger: when a player's character lands on their own team's surface
-- (the spawn into the world), seed the starter base there and then PARK the
-- character in the team's landing-pen cell, switching the player to remote view
-- of the team surface.
--
-- After parking, the character is on the landing-pen surface, so the re-fired
-- surface-change (to the pen, which has no team owner) is ignored -- no loop.
--
-- The same event also fires when a remote-view player switches the surface
-- they look at; an own-team surface is remembered so a reconnect returns there.
-- The map editor (and remote view opened from it) is observation, not arrival,
-- and is ignored entirely.

local remote_player = require("scripts.remote_player")
local starter_base  = require("scripts.starter_base")

local M = {}

local function on_changed_surface(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    if not remote.interfaces["mts-v1"] then return end
    if player.physical_controller_type == defines.controllers.editor then return end

    if player.controller_type == defines.controllers.remote then
        remote_player.remember_view(player)
    end

    local surface = player.physical_surface or player.surface
    if not (surface and surface.valid) or surface.platform then return end

    local owner = remote.call("mts-v1", "get_surface_owner", surface.name)
    if not owner then return end  -- not a team surface (pen, etc.)
    -- Only a player arriving on their OWN team's surface founds or parks there.
    if owner ~= player.force.name then return end

    starter_base.place(owner, surface)
    remote_player.park(player, surface)
end

function M.register()
    script.on_event(defines.events.on_player_changed_surface, on_changed_surface)
end

return M
