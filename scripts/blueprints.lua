-- scripts/blueprints.lua
-- What a starter base is made of: the one human-designed blueprint, the
-- per-planet swaps made to it, and the text on its sign. starter_base.lua
-- (scripts/base/) decides where the base goes, builds it and stocks its chests.
--
-- Every planet gets the SAME footprint. Planet power is tuned by swapping
-- entities in their blueprint slots, never by a second blueprint:
--   * solar panels and accumulators become the planet's uncraftable tuned
--     copies (profile.solar_panel / profile.accumulator, written by the data
--     stage into the bnm-planet-profiles mod-data);
--   * Fulgora: one solar slot becomes a vanilla lightning collector (layout
--     D1, measured on the rig); the lamps stay lamps;
--   * freezing planets (Aquilo): the radar and inserter become bnm-radar and
--     bnm-inserter, which need no heat.
-- A swap is made only when its target prototype exists, so the base still
-- builds, all vanilla, if the data stage did not create it.
--
-- The blueprint holds the whole base: power, the roboport, walls, floor tiles
-- and the logistic chests, including the requester that feeds robots to the
-- roboport (its request is part of the blueprint). The chests are empty here;
-- scripts/base/kits.lua fills them from its kits, so item lists live in code.
-- The kit items an outpost's sign names come from those kits too.

local kits = require("scripts.base.kits")

local M = {}

-- The human-designed starter base, exported from the game. The roboport is
-- found by prototype type, and every position below is relative to it.
M.BLUEPRINT = "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"

-- Fulgora (layout D1): the solar panel in this slot becomes a vanilla
-- lightning collector. The 2x2 collector sits in the 3x3 slot's corner that
-- touches the roboport, so it moves by COLLECTOR_SHIFT. Only the exact
-- vanilla name gets the engine's strike-priority bonus that beats the ruin
-- attractor at every Fulgora surface's origin, so never swap in a copy.
local COLLECTOR       = "lightning-collector"
local COLLECTOR_SLOT  = { x = 3.5, y = -1.5 }
local COLLECTOR_SHIFT = { x = -0.5, y = 0.5 }

-- ─── The sign ─────────────────────────────────────────────────────────

-- The display panel's text comes from here, not from the blueprint, so it can
-- be true for each planet. Unpowered robots slow to 20% speed
-- (speed_multiplier_when_out_of_energy); they do not fall out of the sky.
local SIGN_HEAD = "[font=default-bold]Keep the [entity=bnm-roboport] powered[/font]\n"
    .. "It shares power with everything you build. Robots it cannot "
    .. "recharge slow to 20% speed. They do not crash.\n"

local SIGN_ROLE = {
    home    = "[color=255,80,80]If this roboport is destroyed, your team is eliminated.[/color]",
    outpost = "[color=255,160,60]If this roboport is destroyed, this outpost is lost. "
        .. "Your home base is safe.[/color]",
}

-- Why each planet is different. What the kit brings for it is not typed here:
-- an outpost's sign names it from its kit (kits.sign_icons).
local SIGN_PLANET = {
    nauvis   = "Accumulators carry the night. Add power before you outgrow them.",
    vulcanus = "Some resources may lie past this roboport's reach.",
    fulgora  = "Lightning strikes at night. Robots flying outside the collector's "
        .. "cover get hit.",
    gleba    = "The pentapods will come.",
    aquilo   = "This core never freezes. Most machines you build do, without heat.",
}

--- The sign's text for a base on `planet_base` (e.g. "gleba"). Only an
--- outpost names kit items: a home gets the home kit, not its planet's.
local function sign_text(planet_base, home)
    local text = SIGN_HEAD .. SIGN_ROLE[home and "home" or "outpost"]
    local line = SIGN_PLANET[planet_base]
    if line then text = text .. "\n" .. line end
    local icons = not home and kits.sign_icons(planet_base) or ""
    if icons ~= "" then text = text .. "\nIn the kit: " .. icons end
    return text
end

-- ─── Decoding and swaps ───────────────────────────────────────────────

--- Import a blueprint string; returns its entity and tile lists (may be empty).
local function decode(bp_string)
    local inv = game.create_inventory(1)
    inv.insert{ name = "blueprint", count = 1 }
    local stack = inv[1]
    local ok = pcall(function() stack.import_stack(bp_string) end)
    local entities = ok and stack.get_blueprint_entities() or nil
    local tiles    = ok and stack.get_blueprint_tiles() or nil
    inv.destroy()
    return entities or {}, tiles or {}
end

--- The roboport's blueprint position and name, found by prototype type so any
--- roboport mod works. nil when the blueprint has none.
local function find_roboport(entities)
    for _, e in pairs(entities) do
        local proto = prototypes.entity[e.name]
        if proto and proto.type == "roboport" then
            return e.position.x, e.position.y, e.name
        end
    end
    return nil
end

--- vanilla name -> planet replacement, for the swaps whose target exists.
local function swaps_for(profile)
    local swaps = {}
    local function add(from, to)
        if to and prototypes.entity[to] then swaps[from] = to end
    end
    add("solar-panel", profile.solar_panel)
    add("accumulator", profile.accumulator)
    if profile.freezing then
        add("radar",    "bnm-radar")
        add("inserter", "bnm-inserter")
    end
    return swaps
end

local function is_collector_slot(e, ox, oy)
    return e.name == "solar-panel"
        and math.abs(e.position.x - ox - COLLECTOR_SLOT.x) < 0.01
        and math.abs(e.position.y - oy - COLLECTOR_SLOT.y) < 0.01
end

--- Apply the planet's swaps in place. Slots are matched relative to the
--- roboport (ox, oy), so the offset must be known before anything is renamed.
local function substitute(entities, profile, ox, oy)
    local swaps     = swaps_for(profile)
    local collector = profile.fulgora and prototypes.entity[COLLECTOR] ~= nil
    for _, e in pairs(entities) do
        if collector and is_collector_slot(e, ox, oy) then
            e.name     = COLLECTOR
            e.position = { x = e.position.x + COLLECTOR_SHIFT.x,
                           y = e.position.y + COLLECTOR_SHIFT.y }
        elseif swaps[e.name] then
            e.name = swaps[e.name]
        end
    end
end

local function set_sign_text(entities, planet_base, home)
    for _, e in pairs(entities) do
        local proto = prototypes.entity[e.name]
        if proto and proto.type == "display-panel" then
            e.text = sign_text(planet_base, home)
        end
    end
end

-- ─── Public API ──────────────────────────────────────────────────────

--- The base to build for a planet profile (see starter_base.profile_for):
--- { entities, tiles, ox, oy, roboport } where (ox, oy) is the roboport's
--- blueprint position and `roboport` its prototype name. `home` picks the
--- sign's wording. nil when the blueprint has no roboport.
function M.plan_for(profile, home)
    local entities, tiles = decode(M.BLUEPRINT)
    local ox, oy, roboport = find_roboport(entities)
    if not roboport then return nil end
    substitute(entities, profile, ox, oy)
    set_sign_text(entities, profile.base, home)
    return { entities = entities, tiles = tiles, ox = ox, oy = oy, roboport = roboport }
end

return M
