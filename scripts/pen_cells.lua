-- scripts/pen_cells.lua
-- Per-team holding cells in MTS's landing pen. Each team gets a small walled
-- 3x3 box arranged on a ring around the pen island, labelled with the team
-- name. Spawned-in players' characters are parked in their team's box (while
-- they play entirely through remote view of their team surface), so teammates
-- visibly stand together -- and separate from un-spawned players, who remain on
-- the pen's selection ring at the centre.
--
-- Built once, lazily, after the pen surface exists. Boxes float in the void
-- beyond the pen island; tiles + walls are laid AFTER chunk generation so MTS's
-- pen chunk handler (rings + entity-clearing) doesn't wipe them.

local SURFACE    = "landing-pen"
local FLOOR_TILE = "lab-dark-1"   -- distinct shade from the pen's lab-dark-2
local WALL       = 2              -- wall ring + floor edge at ±2 (5x5 footprint, 3x3 interior)
local RING_MIN   = 26             -- minimum ring radius from pen centre
local BOX_ARC    = 6              -- arc length reserved per box (tiles)

local M = {}

-- ─── Team list + ring geometry ─────────────────────────────────────────

local function team_list()
    if not remote.interfaces["mts-v1"] then return {} end
    local ok, list = pcall(remote.call, "mts-v1", "get_team_list")
    if not ok or type(list) ~= "table" then return {} end
    -- Sort by the team's numeric slot, not the string name -- otherwise the
    -- cells go team-1, team-10, team-11, ..., team-2 around the ring.
    table.sort(list, function(a, b)
        local na = tonumber(a.force_name:match("(%d+)")) or math.huge
        local nb = tonumber(b.force_name:match("(%d+)")) or math.huge
        if na ~= nb then return na < nb end
        return a.force_name < b.force_name
    end)
    return list
end

local function ring_radius(n)
    return math.max(RING_MIN, (n * BOX_ARC) / (2 * math.pi))
end

local function box_center(i, n)
    local r = ring_radius(n)
    local a = (i - 1) * (2 * math.pi / n)
    return {
        x = math.floor(r * math.cos(a) + 0.5),
        y = math.floor(r * math.sin(a) + 0.5),
    }
end

-- ─── Build ─────────────────────────────────────────────────────────────

local function build_box(surface, c, label)
    local tiles = {}
    for dx = -WALL, WALL do
        for dy = -WALL, WALL do
            tiles[#tiles + 1] = { name = FLOOR_TILE, position = { c.x + dx, c.y + dy } }
        end
    end
    surface.set_tiles(tiles)

    for d = -WALL, WALL do
        for _, p in ipairs({
            { c.x + d, c.y - WALL }, { c.x + d, c.y + WALL },
            { c.x - WALL, c.y + d }, { c.x + WALL, c.y + d },
        }) do
            surface.create_entity{ name = "stone-wall", position = p, force = "neutral" }
        end
    end

    -- Return the render object so the caller can keep it and update the text
    -- later (e.g. when the team is renamed).
    return rendering.draw_text{
        text      = label,
        surface   = surface,
        target    = { c.x, c.y - WALL - 2 },
        color     = { r = 1, g = 0.9, b = 0.6 },
        scale     = 1.0,
        alignment = "center",
        -- A natively large font renders crisp; scaling a small font up is blurry.
        font      = "default-large-bold",
    }
end

--- Build all team cells once. Safe to call repeatedly (no-op after first build).
function M.ensure_built()
    if storage.cells_built then return end
    local surface = game.surfaces[SURFACE]
    if not (surface and surface.valid) then return end

    local teams = team_list()
    local n = #teams
    if n == 0 then return end

    local r = ring_radius(n)
    surface.request_to_generate_chunks({ 0, 0 }, math.ceil((r + WALL + 1) / 32) + 1)
    surface.force_generate_chunk_requests()

    storage.cell_center = {}
    storage.cell_label  = {}
    for i, team in ipairs(teams) do
        local c = box_center(i, n)
        storage.cell_center[team.force_name] = c
        storage.cell_label[team.force_name] =
            build_box(surface, c, team.display_name or team.force_name)
    end
    storage.cells_built = true
    log("[brave-new-mts] built " .. n .. " team cells in the landing pen")
end

-- ─── Park slots within a box ───────────────────────────────────────────

-- Up to 9 teammates per cell, packed inside the 3x3 interior.
local SLOT_OFFSETS = {
    { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
    { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
}

--- Update a team's cell label (e.g. after a rename). No-op if the cells aren't
--- built yet -- ensure_built will draw the current name when it runs.
function M.set_label(force_name, label)
    local obj = storage.cell_label and storage.cell_label[force_name]
    if obj and obj.valid then obj.text = label end
end

--- Parking position inside a team's box for the Nth teammate (0-based).
function M.park_position(force_name, index_in_team)
    local c = storage.cell_center and storage.cell_center[force_name]
    if not c then return nil end
    local off = SLOT_OFFSETS[(index_in_team % #SLOT_OFFSETS) + 1]
    return { x = c.x + off[1], y = c.y + off[2] }
end

return M
