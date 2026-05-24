-- scripts/remote_player.lua
-- Turns a player into a character-free remote builder: destroy the character
-- and put the player into remote view. With no character, handcrafting and
-- hand-mining are impossible by construction, so no permission group is
-- needed -- the player can only place blueprints, and construction robots
-- build them from the network.
--
-- EMPIRICAL CHECKPOINTS (Phase 2):
--   * Does destroying the character drop the player into a controller that
--     can place ghosts, or must we explicitly set the remote controller?
--   * Does set_controller{type=remote} work with NO backing character?
--   * What happens on death/respawn given there is no character?

local M = {}

--- Remove the player's character (if any) and ensure they are in remote view.
function M.make_remote(player)
    if not (player and player.valid) then return end

    -- Anchor the remote camera at wherever the player currently is.
    local surface  = player.physical_surface  or player.surface
    local position = player.physical_position or player.position

    if player.character then
        player.character.destroy()
    end

    if player.controller_type ~= defines.controllers.remote then
        player.set_controller{
            type     = defines.controllers.remote,
            surface  = surface,
            position = position,
        }
    end
end

return M
