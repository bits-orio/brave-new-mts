-- scripts/base/oil_node.lua
-- A generous crude-oil node so a character-free team has oil to tap without
-- prospecting. Oil fields are a Nauvis feature: the caller places one on a
-- Nauvis base only.

local geometry = require("scripts.base.geometry")

local M = {}

local OIL_NAME = "crude-oil"

-- For crude oil the displayed yield is amount/3000 percent (verified in-game:
-- amount 150 000 showed 50%), so 300% == 900 000. It is placed well away from
-- the base but inside the central roboport's construction radius (110), so
-- bots can build a pumpjack on it.
local OIL_NODE_YIELD_PERCENT = 300
local OIL_NODE_AMOUNT        = OIL_NODE_YIELD_PERCENT * 3000
local OIL_NODE_DISTANCE      = 100   -- tiles from the base origin (roboport)

-- The distances tried in turn (the target, then fallbacks), and how many
-- evenly spaced angles are tried at each.
local OIL_NODE_RADII  = { OIL_NODE_DISTANCE, 64, 96 }
local OIL_SWEEP_STEPS = 12

-- Tiles charted on each side of the node, so it shows in remote view.
local OIL_CHART_RADIUS = 3

--- True if a crude-oil well can sit at `p`: buildable ground (so not water/cliffs)
--- and clear of any existing resource (so we never stack it on an ore patch).
local function oil_spot_is_clear(surface, p)
    if not surface.can_place_entity{ name = OIL_NAME, position = p } then return false end
    local on_ore = surface.find_entities_filtered{ position = p, radius = 2, type = "resource" }
    return #on_ore == 0
end

--- A starting angle (radians) for the oil-node sweep, derived from the MAP seed
--- (the main surface's seed -- one game-wide value, so every team gets the SAME
--- direction) rather than anything per-surface. Deterministic across multiplayer
--- peers; a different map seed gives a different direction, but within a game all
--- teams match.
local function oil_start_angle()
    local main = game.surfaces[1]
    local seed = (main and main.map_gen_settings and main.map_gen_settings.seed) or 0
    return (seed % 360) / 360 * 2 * math.pi
end

--- The first clear spot on a ring of candidate angles at the target distance,
--- then at the fallback distances; nil when there is none.
local function find_oil_spot(surface)
    local o     = geometry.BASE_ORIGIN
    local start = oil_start_angle()
    for _, dist in ipairs(OIL_NODE_RADII) do
        for step = 0, OIL_SWEEP_STEPS - 1 do
            local ang = start + (step / OIL_SWEEP_STEPS) * 2 * math.pi
            local p = { x = o.x + math.cos(ang) * dist, y = o.y + math.sin(ang) * dist }
            if oil_spot_is_clear(surface, p) then return p end
        end
    end
    return nil
end

--- Drop a single rich crude-oil node away from the base (so it doesn't crowd the
--- build) but inside the roboport's construction radius (so bots can reach it),
--- on a spot clear of water and ore. Charts it so it's visible.
function M.place(force, surface)
    if not prototypes.entity[OIL_NAME] then return end
    local p = find_oil_spot(surface)
    if not p then
        log("[brave-new-mts] no clear spot (no water / no ore) found for the starter oil node")
        return
    end
    local r = OIL_CHART_RADIUS
    surface.create_entity{ name = OIL_NAME, position = p, amount = OIL_NODE_AMOUNT }
    force.chart(surface, { { p.x - r, p.y - r }, { p.x + r, p.y + r } })
end

return M
