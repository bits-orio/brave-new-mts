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
    -- Walled starter base: BRE-roboport-mk2 (centre), 45 solar + 16 accumulator
    -- + 2 substation + poles, gates, loaders, a car, and a chest set
    -- (passive/active provider, requester, buffer, storage). ~37x16 tiles.
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
