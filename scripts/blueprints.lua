-- scripts/blueprints.lua
-- Maps a team surface to the starter-base blueprint string used to seed it.
--
-- The SAME blueprint works for every planet except Aquilo, which needs extra
-- solar panels (per design). `default` is used for any surface without a
-- specific entry. Paste real exported blueprint strings here in Phase 3.
--
-- The blueprint should contain the power build (solar / accumulators /
-- substations) and a roboport. Logistic chests and their starting items are
-- placed by starter_base.lua, NOT the blueprint, so they can be kept in sync
-- with the anti-soft-lock item list in code.

local M = {}

-- Known planet name fragments we test surface names against (lower-case).
local PLANETS = { "nauvis", "vulcanus", "fulgora", "gleba", "aquilo" }

-- planet key -> exported blueprint string. Empty string == not configured yet.
M.blueprints = {
    default = "",  -- TODO(phase3): paste the standard starter-base blueprint.
    aquilo  = "",  -- TODO(phase3): Aquilo variant with extra solar panels.
}

--- Best-effort planet key for an MTS surface name (e.g. "mts-aquilo-3",
--- "team-3-nauvis"). Returns nil if no known planet fragment matches.
local function planet_of(surface_name)
    local lowered = surface_name:lower()
    for _, planet in ipairs(PLANETS) do
        if lowered:find(planet, 1, true) then return planet end
    end
    return nil
end

--- Returns the blueprint string for a surface, or "" if none is configured.
function M.for_surface(surface)
    local planet = planet_of(surface.name)
    if planet and M.blueprints[planet] and M.blueprints[planet] ~= "" then
        return M.blueprints[planet]
    end
    return M.blueprints.default
end

return M
