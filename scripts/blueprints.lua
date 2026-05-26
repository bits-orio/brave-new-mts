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
    -- Walled starter base: bnm-roboport (centre), 45 solar + 16 accumulator
    -- + 2 substation + poles, gates, loaders, a car, a chest set (passive/active
    -- provider, requester, buffer, storage), and a refined-concrete floor.
    default = "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",
    aquilo  = "",  -- TODO: Aquilo variant with extra solar (falls back to default for now).
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
