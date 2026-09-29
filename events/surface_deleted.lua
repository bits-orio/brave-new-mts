-- events/surface_deleted.lua
-- Forget a base when its surface is deleted outside a team release (an admin's
-- delete_surface, another mod), so its placed flag never blocks the planet
-- once the surface comes back. Uses the PRE event: the surface, and so its
-- name, is gone by on_surface_deleted. Idempotent with the on_team_released
-- path, and a no-op for surfaces that never had a base (platforms and the
-- like).
--
-- A lost outpost can then be re-founded by a clone. A lost home leaves its
-- team with no home base, which can no longer be eliminated: a member
-- arriving on the recreated surface founds a new home there, but a clone
-- founds an outpost. To end such a team, an admin runs /mts-disband.

local starter_base = require("scripts.starter_base")

local M = {}

local function on_pre_surface_deleted(e)
    local surface = game.surfaces[e.surface_index]
    if surface and surface.valid then starter_base.forget_surface(surface.name) end
end

--- Engine event only (no remote.call): safe in on_init/on_load/on_config.
function M.register()
    script.on_event(defines.events.on_pre_surface_deleted, on_pre_surface_deleted)
end

return M
