-- scripts/base/geometry.lua
-- Where a base sits: its origin, the box its blueprint covers, and the site
-- to clear, which for an outpost takes in the landing pad below it.

local landing_pad = require("scripts.base.landing_pad")

local M = {}

-- The base is centred on a CHUNK CENTRE (16,16), not the spawn corner (0,0).
-- The roboport's construction area reveals whole chunks around the roboport's
-- chunk; that reveal is only symmetric when the roboport sits at the chunk's
-- centre -- otherwise it spills a chunk toward +x/+y. Players never stand here
-- (their character is parked in the pen), and remote view is centred here too.
M.BASE_ORIGIN = { x = 16, y = 16 }

-- Extra tiles cleared around the blueprint's footprint.
local CLEAR_MARGIN = 3

--- World-space box around the blueprint's entity centres, plus CLEAR_MARGIN.
function M.footprint_area(origin, plan)
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for _, e in pairs(plan.entities) do
        local x, y = e.position.x - plan.ox, e.position.y - plan.oy
        minx, maxx = math.min(minx, x), math.max(maxx, x)
        miny, maxy = math.min(miny, y), math.max(maxy, y)
    end
    return {
        { origin.x + minx - CLEAR_MARGIN, origin.y + miny - CLEAR_MARGIN },
        { origin.x + maxx + CLEAR_MARGIN, origin.y + maxy + CLEAR_MARGIN },
    }
end

--- The smallest box covering boxes `a` and `b`.
local function union(a, b)
    return {
        { math.min(a[1][1], b[1][1]), math.min(a[1][2], b[1][2]) },
        { math.max(a[2][1], b[2][1]), math.max(a[2][2], b[2][2]) },
    }
end

--- The base's footprint, its pad (outposts only) and the box covering both.
function M.site_for(origin, plan, outpost)
    local footprint = M.footprint_area(origin, plan)
    local pad = outpost and landing_pad.site(origin, plan) or nil
    local area = pad and union(footprint, pad.area) or footprint
    return { footprint = footprint, pad = pad, area = area }
end

return M
