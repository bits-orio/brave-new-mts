-- prototypes/bnm_roboport.lua
-- A self-contained mega-roboport for the starter base: ~2x reach, 4x energy,
-- 16 charging docks, 20 robot slots. It reuses the vanilla roboport's graphics
-- and 4x4 footprint, recoloured with a bold Google-red tint to mark it as a
-- special, one-of-a-kind structure (no custom art needed).
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

-- ─── Distinct look: a glowing Google-red "overseer" roboport ────────────
-- tint multiplies the vanilla sprite, so a bold colour marks it as a special,
-- one-of-a-kind structure. Recolour by editing BNM_TINT -- Google palette:
--   blue   #4285F4  { 0.259, 0.522, 0.957 }
--   red    #EA4335  { 0.918, 0.263, 0.208 }
--   yellow #FBBC05  { 0.984, 0.737, 0.020 }
--   green  #34A853  { 0.204, 0.659, 0.325 }
local BNM_TINT = { r = 0.918, g = 0.263, b = 0.208, a = 1.0 }  -- Google red

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

-- A bright red charging glow to match.
rb.recharging_light = { intensity = 0.6, size = 5, color = { r = 1.0, g = 0.30, b = 0.25 } }

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
