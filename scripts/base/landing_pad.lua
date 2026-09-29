-- scripts/base/landing_pad.lua
-- An outpost's cargo landing pad: without one, nothing a platform carries
-- reaches the ground. It is minable, not part of the locked core.

local M = {}

-- The outpost landing pad: centred under the roboport, its top edge PAD_GAP
-- tiles below the footprint's bottom edge, on a PAD_FLOOR floor so it stands
-- even over water, lava or oil ocean.
M.PAD_NAME      = "cargo-landing-pad"
local PAD_GAP   = 3
local PAD_FLOOR = "refined-concrete"

--- Half a blueprint entity's height in tiles, turned by its direction.
local function half_height(e)
    local proto = prototypes.entity[e.name]
    if not proto then return 0.5 end
    local d = e.direction
    local turned = d == defines.direction.east or d == defines.direction.west
    return (turned and proto.tile_width or proto.tile_height) / 2
end

--- Where an outpost's landing pad goes: centred on the roboport's x, its top
--- edge PAD_GAP tiles below the blueprint's bottom edge (entity centres plus
--- half their height). nil when the pad prototype does not exist.
function M.site(origin, plan)
    local proto = prototypes.entity[M.PAD_NAME]
    if not proto then return nil end
    local bottom = -math.huge
    for _, e in pairs(plan.entities) do
        bottom = math.max(bottom, e.position.y - plan.oy + half_height(e))
    end
    local w, h = proto.tile_width, proto.tile_height
    local top, left = origin.y + bottom + PAD_GAP, origin.x - w / 2
    return {
        position = { x = origin.x, y = top + h / 2 },
        area     = { { left, top }, { left + w, top + h } },
    }
end

--- Lay the PAD_FLOOR tiles under the pad, when that tile exists.
local function lay_floor(surface, area)
    if not prototypes.tile[PAD_FLOOR] then return end
    local tiles = {}
    for x = area[1][1], area[2][1] - 1 do
        for y = area[1][2], area[2][2] - 1 do
            tiles[#tiles + 1] = { name = PAD_FLOOR, position = { x = x, y = y } }
        end
    end
    surface.set_tiles(tiles)
end

--- Lay the pad's floor and place the pad (`pad` is what M.site returned).
function M.place(force, surface, pad)
    lay_floor(surface, pad.area)
    local created = surface.create_entity{
        name = M.PAD_NAME, position = pad.position, force = force, raise_built = true,
    }
    if not created then log("[brave-new-mts] failed to place '" .. M.PAD_NAME .. "' (collision?)") end
    return created
end

return M
