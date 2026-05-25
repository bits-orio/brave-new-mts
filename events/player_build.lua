-- events/player_build.lua
-- Humans build ONLY through blueprints + robots. In the physical view a player
-- can pull items from the base chests and hand-place real entities, bypassing
-- the bot economy. There's no permission that blocks real-entity placement
-- without also blocking ghost/blueprint placement (both use input_action.build),
-- so we handle it here: cancel any REAL entity a player builds by hand and
-- refund the item. Ghosts (entity-ghost / tile-ghost), which robots construct,
-- are left alone -- that's the intended way to build.
--
-- Only player-built entities on team surfaces are affected: script-/robot-built
-- entities have no player_index, and the landing pen / non-team surfaces are
-- skipped via the mts-v1 owner check.

local M = {}

function M.register()
    script.on_event(defines.events.on_built_entity, function(event)
        local entity = event.entity
        if not (entity and entity.valid) then return end
        if entity.type == "entity-ghost" or entity.type == "tile-ghost" then return end

        local player = event.player_index and game.get_player(event.player_index)
        if not (player and player.valid) then return end  -- script/robot build: ignore

        if not remote.interfaces["mts-v1"] then return end
        if not remote.call("mts-v1", "get_surface_owner", entity.surface.name) then return end

        local pos = entity.position
        player.mine_entity(entity, true)  -- remove and refund the item to the player
        player.create_local_flying_text{
            text     = "Place blueprints — robots build for you.",
            position = pos,
        }
    end)
end

return M
