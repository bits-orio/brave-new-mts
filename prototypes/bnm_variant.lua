-- prototypes/bnm_variant.lua
-- Builds the uncraftable copies of vanilla entities that the starter base
-- places in its footprint (planet-tuned panels and accumulators, non-freezing
-- radar and inserter; bnm_planet_power.lua decides which exist). Every copy
-- follows the same rules, so none of them can leak into a team's economy:
--
--   * no item, no recipe and no placeable_by: only script can place one, and
--     a ghost of one can never be built (no item exists to build it from).
--     With placeable_by, bots could build unlimited tuned copies from vanilla
--     items through blueprints.
--   * not-blueprintable, and no ghost when it dies.
--   * mining returns the ordinary vanilla item, so a team that tears one down
--     gets a normal building back, never a tuned one.
--   * no next_upgrade, so an upgrade planner can't turn it into anything.
--   * a light green tint, from the roboport's colour family, so players can
--     tell the tuned base buildings from their own.

local M = {}

local TINT = { r = 0.7, g = 1.0, b = 0.7, a = 1.0 }

-- Sprite fields to tint, per entity type. Shadows are left alone.
local GRAPHICS = {
    ["solar-panel"] = { "picture", "overlay" },
    ["accumulator"] = { "chargable_graphics" },
    ["radar"]       = { "pictures", "integration_patch" },
    ["inserter"]    = { "platform_picture", "hand_base_picture",
                        "hand_open_picture", "hand_closed_picture" },
}

--- Tint every sprite in a graphics definition, however deeply it nests
--- (layers, 4-way sheets, accumulator charge animations...).
local function tint_sprites(def)
    if type(def) ~= "table" then return end
    local is_sprite = def.filename or def.filenames or def.stripes
    if is_sprite and not def.draw_as_shadow then
        def.tint = TINT
    end
    for key, child in pairs(def) do
        -- Stripes are file slices of this sprite, not sprites of their own.
        if key ~= "stripes" then tint_sprites(child) end
    end
end

local function tint_icons(e)
    if e.icon then
        e.icons = { { icon = e.icon, icon_size = e.icon_size or 64, tint = TINT } }
        e.icon, e.icon_size = nil, nil
    elseif e.icons then
        for _, layer in pairs(e.icons) do layer.tint = TINT end
    end
end

local function add_flag(e, flag)
    e.flags = e.flags or {}
    for _, f in pairs(e.flags) do
        if f == flag then return end
    end
    e.flags[#e.flags + 1] = flag
end

--- A deep copy of data.raw[spec.type][spec.from] named spec.name, following
--- the rules in the header. Returns the prototype for the caller to tune and
--- data:extend.
---   spec = { type, from, name, localised_name, localised_description }
function M.make(spec)
    local vanilla = data.raw[spec.type][spec.from]
    local e = table.deepcopy(vanilla)
    e.name                  = spec.name
    e.localised_name        = spec.localised_name
    e.localised_description = spec.localised_description
    e.placeable_by          = nil
    e.next_upgrade          = nil
    e.create_ghost_on_death = false
    e.minable = {
        mining_time = (vanilla.minable and vanilla.minable.mining_time) or 0.1,
        result      = (vanilla.minable and vanilla.minable.result) or spec.from,
    }
    add_flag(e, "not-blueprintable")
    for _, field in pairs(GRAPHICS[spec.type] or {}) do
        tint_sprites(e[field])
    end
    tint_icons(e)
    return e
end

return M
