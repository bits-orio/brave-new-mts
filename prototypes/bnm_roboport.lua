-- prototypes/bnm_roboport.lua
-- A self-contained mega-roboport for the starter base: ~2x reach, 4x energy,
-- 16 charging docks, 20 robot slots. It reuses the vanilla roboport's graphics
-- and 4x4 footprint, recoloured with a radioactive uranium-green glow to mark
-- it as a special, one-of-a-kind structure (no custom art needed).
--
-- Crucially it has NO RECIPE, so players can never craft one -- the only copies
-- that exist are the ones this mod places at each team's spawn (via the starter
-- blueprint). It IS minable (returns its own item) so the team can relocate it
-- with bots, but it can never be duplicated. Stamping a blueprint that contains
-- it just makes an unbuildable ghost (no obtainable item), so it can't be
-- copied that way either.

local NAME = "bnm-roboport"

-- ─── Entity: vanilla roboport, scaled up ───────────────────────────────
local rb = table.deepcopy(data.raw.roboport["roboport"])
rb.name                  = NAME
rb.localised_name        = { "", "Brave New Roboport" }
rb.localised_description  = { "", "A self-powered mega-roboport seeded at spawn. Cannot be crafted." }
rb.minable               = { mining_time = 1, result = NAME }
rb.placeable_by          = { item = NAME, count = 1 }
rb.next_upgrade          = nil

rb.logistics_radius      = (rb.logistics_radius   or 25) * 2   -- 25 -> 50
rb.construction_radius   = (rb.construction_radius or 55) * 2  -- 55 -> 110
rb.robot_slots_count     = 20
rb.material_slots_count  = 8
rb.recharge_minimum      = "160MJ"
rb.charging_energy       = "1MW"
rb.energy_usage          = "200kW"   -- 4x vanilla 50kW
rb.energy_source.buffer_capacity  = "400MJ"  -- 4x vanilla 100MJ
rb.energy_source.input_flow_limit = "20MW"   -- 4x vanilla 5MW

-- 16 charging docks on a 4x4 grid (vanilla has 4).
rb.charging_offsets = {
    { -1.5,  1.5 }, { -0.5,  1.5 }, { 0.5,  1.5 }, { 1.5,  1.5 },
    { -1.5,  0.5 }, { -0.5,  0.5 }, { 0.5,  0.5 }, { 1.5,  0.5 },
    { -1.5, -0.5 }, { -0.5, -0.5 }, { 0.5, -0.5 }, { 1.5, -0.5 },
    { -1.5, -1.5 }, { -0.5, -1.5 }, { 0.5, -1.5 }, { 1.5, -1.5 },
}

-- Remaining stat overrides (footprint / graphics stay vanilla).
rb.resistances = {
    { type = "fire",   percent = 60 },
    { type = "impact", percent = 30 },
}
rb.is_military_target           = true
rb.charge_approach_distance     = 5
rb.request_to_open_door_timeout = 15

-- ─── Distinct look: a radioactive uranium-green "overseer" roboport ─────
-- The recolour tint multiplies the vanilla sprite; an extra additive glow
-- layer over the base makes it actually radiate (like uranium ore). Recolour
-- by editing BNM_TINT. Uranium green is the canonical Factorio glow colour:
--   uranium  { r = 0.1, g = 1.0, b = 0.1 }
local BNM_TINT = { r = 0.15, g = 1.0, b = 0.15, a = 1.0 }  -- uranium green

local function tint_layers(def)
    if type(def) ~= "table" then return end
    if def.layers then
        for _, l in pairs(def.layers) do tint_layers(l) end
    elseif def.filename and not def.draw_as_shadow then
        def.tint = BNM_TINT
    end
end

for _, key in ipairs({ "base", "base_patch", "base_animation",
                       "door_animation_up", "door_animation_down" }) do
    tint_layers(rb[key])
end

-- Strong always-on uranium glow: an additive copy of the base sprite drawn as
-- glow, so the roboport visibly radiates green even when idle.
local base_layers = rb.base and rb.base.layers
if base_layers and base_layers[1] then
    local glow = table.deepcopy(base_layers[1])
    glow.draw_as_shadow = nil
    glow.draw_as_glow   = true
    glow.blend_mode     = "additive"
    glow.tint           = BNM_TINT
    base_layers[#base_layers + 1] = glow
end

-- A bright uranium-green charging glow to match.
rb.recharging_light = { intensity = 0.8, size = 6, color = { r = 0.1, g = 1.0, b = 0.1 } }

-- Recolour the entity's map/alert icon too.
if rb.icon then
    rb.icons = { { icon = rb.icon, icon_size = rb.icon_size or 64, tint = BNM_TINT } }
    rb.icon  = nil
end

-- ─── Item: exists for placement/blueprints, but has NO recipe ───────────
local item = table.deepcopy(data.raw.item["roboport"])
item.name          = NAME
item.localised_name = { "", "Brave New Roboport" }
item.place_result  = NAME
item.order         = (item.order or "c") .. "-bnm"
if item.icon then
    item.icons = { { icon = item.icon, icon_size = item.icon_size or 64, tint = BNM_TINT } }
    item.icon  = nil
end

data:extend({ rb, item })
