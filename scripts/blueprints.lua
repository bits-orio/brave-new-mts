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
    -- Walled starter base: bnm-roboport (centre), 47 solar + 16 accumulator
    -- + 2 substation + 2 medium pole + 7 lamp (the protected power core), a
    -- stone-wall perimeter, a logistic chest set (passive/active provider,
    -- requester, buffer, storage), inserters + loaders, and a tiled floor.
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
