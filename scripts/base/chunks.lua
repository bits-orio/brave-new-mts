-- scripts/base/chunks.lua
-- The chunks around a base: generated before anything is placed, and charted
-- once it stands. Off-world surfaces start with no generated chunks, and
-- generating them after the build overwrites the floor and drops cliffs and
-- ocean into the base. No character stands on a team surface to chart it.

local M = {}

-- Charting and generation work in whole chunks of this many tiles.
local CHUNK_SIZE = 32

-- Whole chunks of margin to chart (reveal) around the base footprint, so the
-- base is visible in remote view (no character stands on the team surface).
-- Charting works in whole 32-tile chunks; expanding the footprint's chunk span
-- equally on all sides keeps the reveal centred on the base.
local CHART_CHUNK_MARGIN = 3

-- Chunks generated around the base before anything is placed: one more than
-- the chart margin, so it covers the whole reveal and the 220x220
-- construction area the enemy sweep clears.
local GENERATE_RADIUS = CHART_CHUNK_MARGIN + 1

--- Generate the ground under and around the base, synchronously. Generation
--- is deterministic, so every multiplayer peer builds the same terrain in the
--- same tick. Chunks that already exist (a home surface MTS pre-generated, a
--- re-founded outpost) are left alone.
function M.generate(surface, origin)
    surface.request_to_generate_chunks(origin, GENERATE_RADIUS)
    surface.force_generate_chunk_requests()
end

--- Chart whole chunks symmetrically around the base footprint, so the reveal is
--- centred on the base (force.chart reveals whole 32-tile chunks; we work in
--- chunk units to avoid the chunk-boundary asymmetry of a raw tile box).
function M.chart(force, surface, area)
    local C = CHUNK_SIZE
    local cmin_x = math.floor(area[1][1] / C) - CHART_CHUNK_MARGIN
    local cmin_y = math.floor(area[1][2] / C) - CHART_CHUNK_MARGIN
    local cmax_x = math.floor(area[2][1] / C) + CHART_CHUNK_MARGIN
    local cmax_y = math.floor(area[2][2] / C) + CHART_CHUNK_MARGIN
    force.chart(surface, {
        { cmin_x * C,           cmin_y * C },
        { cmax_x * C + (C - 1), cmax_y * C + (C - 1) },
    })
end

return M
