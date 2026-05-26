-- scripts/pen_cutout.lua
-- A walled, water-moated cutout carved into MTS's landing-pen surface. This is
-- the holding cell for the PARKED CHARACTERS of spawned-in players: their body
-- sits here (invulnerable, contained by walls + water) while the player plays
-- entirely through remote view of their team surface. Because the character is
-- never on the team surface, it can't chart or collide with it.
--
-- The cutout sits below the pen island (which has radius ~21). It's built once,
-- lazily, after the pen surface exists -- placed AFTER chunk generation so MTS's
-- pen chunk handler (which tiles rings and clears entities) doesn't wipe it.

local M = {}

local SURFACE     = "landing-pen"
local CENTER      = { x = 0, y = 48 }  -- clear of the pen island + moat
local FLOOR_HALF  = 10                 -- 21x21 floor of walkable tiles
local WATER_BAND  = 2                  -- water moat thickness around the floor
local FLOOR_TILE  = "lab-dark-1"       -- distinct shade from the pen's lab-dark-2
local PARK_HALF   = 8                  -- park slots kept inside the wall ring
local PARK_STEP   = 2

-- ─── Build ─────────────────────────────────────────────────────────────

--- Build the cutout once: floor + water moat tiles, and a stone-wall ring at
--- the floor edge. No-op if already built or the pen surface doesn't exist yet.
function M.ensure_built()
    if storage.cutout_built then return end
    local surface = game.surfaces[SURFACE]
    if not (surface and surface.valid) then return end

    -- Make sure the chunks under the cutout exist before we tile them.
    local reach = FLOOR_HALF + WATER_BAND + 1
    surface.request_to_generate_chunks(CENTER, math.ceil(reach / 32) + 1)
    surface.force_generate_chunk_requests()

    local tiles = {}
    local edge  = FLOOR_HALF + WATER_BAND
    for dx = -edge, edge do
        for dy = -edge, edge do
            local name = (math.abs(dx) <= FLOOR_HALF and math.abs(dy) <= FLOOR_HALF)
                and FLOOR_TILE or "water"
            tiles[#tiles + 1] = { name = name, position = { CENTER.x + dx, CENTER.y + dy } }
        end
    end
    surface.set_tiles(tiles)

    -- Stone-wall ring at the floor perimeter (placed after chunk gen, so MTS's
    -- entity-clearing chunk handler won't remove it).
    for d = -FLOOR_HALF, FLOOR_HALF do
        for _, pos in ipairs({
            { CENTER.x + d,          CENTER.y - FLOOR_HALF },
            { CENTER.x + d,          CENTER.y + FLOOR_HALF },
            { CENTER.x - FLOOR_HALF, CENTER.y + d },
            { CENTER.x + FLOOR_HALF, CENTER.y + d },
        }) do
            surface.create_entity{ name = "stone-wall", position = pos, force = "neutral" }
        end
    end

    storage.cutout_built = true
    log("[brave-new-mts] landing-pen cutout built at ("
        .. CENTER.x .. "," .. CENTER.y .. ")")
end

-- ─── Park slots ────────────────────────────────────────────────────────

--- Map a 0-based slot index to a parking position on a grid inside the cutout.
function M.get_park_position(slot)
    local span = 2 * PARK_HALF
    local cols = math.floor(span / PARK_STEP) + 1
    local col  = slot % cols
    local row  = math.floor(slot / cols)
    return {
        x = CENTER.x - PARK_HALF + col * PARK_STEP,
        y = CENTER.y - PARK_HALF + (row * PARK_STEP) % (span + 1),
    }
end

--- True if a position lies within the cutout's floor (used to check whether a
--- character is currently parked).
function M.contains(position)
    return math.abs(position.x - CENTER.x) <= FLOOR_HALF
       and math.abs(position.y - CENTER.y) <= FLOOR_HALF
end

return M
