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
    -- Walled starter base: kr-large-roboport (centre), 34 solar + 8 accumulator
    -- + 2 substation + poles, 4 stone-furnace, 10 inserter, and a chest set
    -- (passive/active provider, requester, buffer, storage). ~33x16 tiles.
    default = "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",
    aquilo  = "",  -- TODO(phase3): Aquilo variant with extra solar (falls back to default for now).
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
