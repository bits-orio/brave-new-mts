-- scripts/remote_player.lua
-- Turns a player into a character-free remote builder: destroy the character
-- and put the player into remote view. With no character, handcrafting and
-- hand-mining are impossible by construction, so no permission group is
-- needed -- the player can only place blueprints, and construction robots
-- build them from the network.
--
-- We strip the character only once the player is on a TEAM-owned surface.
-- MTS's landing-pen / team-selection phase happens on the (unowned)
-- "landing-pen" surface, where the player keeps a character so MTS's pen GUI
-- behaves normally. The character MTS creates when a team is claimed is the
-- one we remove, on arrival at the team surface.

local M = {}

local function controller_name(ct)
    for name, value in pairs(defines.controllers) do
        if value == ct then return name end
    end
    return tostring(ct)
end

--- Remove the player's character (if any) and ensure they are in remote view.
function M.make_remote(player)
    if not (player and player.valid) then return end

    local had_character = player.character ~= nil
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

    log(("[brave-new-mts] make_remote %s on %s: had_character=%s -> controller=%s character=%s")
        :format(player.name, surface.name, tostring(had_character),
                controller_name(player.controller_type),
                tostring(player.character ~= nil)))
end

--- Strip the character iff the player is on a team-owned surface (queried from
--- mts-v1). Returns the owning force name + surface when it acted, so callers
--- can chain starter-base placement; returns nil otherwise (e.g. landing pen).
function M.ensure_remote_if_team_surface(player)
    if not (player and player.valid) then return nil end
    if not remote.interfaces["mts-v1"] then return nil end

    local surface = player.physical_surface or player.surface
    if not (surface and surface.valid) then return nil end

    local owner = remote.call("mts-v1", "get_surface_owner", surface.name)
    if not owner then return nil end  -- not a team surface (landing pen, etc.)

    M.make_remote(player)
    return owner, surface
end

return M
