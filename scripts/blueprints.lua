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
    default = "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",
    aquilo  = "",  -- TODO: Aquilo variant with extra solar (falls back to default for now).
}

--- Best-effort planet key for an MTS surface name (e.g. "mts-aquilo-3",
--- "team-3-nauvis"). Returns nil if no known planet fragment matches.
function M.planet_of(surface_name)
    local lowered = surface_name:lower()
    for _, planet in ipairs(PLANETS) do
        if lowered:find(planet, 1, true) then return planet end
    end
    return nil
end
local planet_of = M.planet_of

--- Returns the blueprint string for a surface, or "" if none is configured.
function M.for_surface(surface)
    local planet = planet_of(surface.name)
    if planet and M.blueprints[planet] and M.blueprints[planet] ~= "" then
        return M.blueprints[planet]
    end
    return M.blueprints.default
end

return M
