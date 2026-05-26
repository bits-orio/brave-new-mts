-- prototypes/bnm_roboport.lua
-- A self-contained mega-roboport for the starter base, modelled on the Brave
-- New OARC roboport: ~2x reach, 4x energy, 16 charging docks, 20 robot slots.
-- It reuses the vanilla roboport's graphics and 4x4 footprint (no custom art).
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

-- ─── Item: exists for placement/blueprints, but has NO recipe ───────────
local item = table.deepcopy(data.raw.item["roboport"])
item.name          = NAME
item.localised_name = { "", "Brave New Roboport" }
item.place_result  = NAME
item.order         = (item.order or "c") .. "-bnm"

data:extend({ rb, item })
