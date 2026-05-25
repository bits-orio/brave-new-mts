-- events/player_build.lua
-- Everything a player places must be built by robots, never instant-built by
-- hand. A character-less player is backed by the god controller, which
-- instant-builds blueprints as FREE real entities -- bypassing the bot economy.
-- So when a player builds a real entity, we replace it with a ghost, which
-- robots then construct from the logistic network.
--
-- In remote view placement is already a ghost (entity-ghost) and passes through
-- untouched. Script-/robot-built entities have no player_index and are ignored.
-- Scoped to team surfaces via the mts-v1 owner check.

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

        -- Capture what was placed, then replace the free instant-build with a
        -- ghost so robots construct it from the network.
        local surface = entity.surface
        local ghost = {
            name       = "entity-ghost",
            inner_name = entity.name,
            position   = entity.position,
            direction  = entity.direction,
            force      = entity.force,
        }
        if entity.quality then ghost.quality = entity.quality.name end
        if entity.type == "assembling-machine" then
            local ok, recipe = pcall(function() return entity.get_recipe() end)
            if ok and recipe then ghost.recipe = recipe.name end
        end

        entity.destroy()
        surface.create_entity(ghost)
    end)
end

return M
