-- tools/rig/hooks/bnm_rig_data.lua
-- TEST-ONLY prototypes. stage.sh --hooks copies this into the STAGED copy of
-- Brave New MTS and requires it from the staged data.lua. It never ships: it
-- lives under tools/, which the release zip excludes.
--
-- bnm-rig-load: a constant electrical consumer for power measurements. The
-- vanilla electric-energy-interface is "tertiary" (it charges and discharges
-- like an accumulator), so it cannot model a load. This one is
-- "secondary-input", the same class as the roboport, radar and lamps, so it
-- competes for power exactly like a real machine and never feeds energy back.
--
-- Set the load at runtime (J per tick; 1 kW = 1000/60 J/tick):
--   e.power_usage = kw * 1000 / 60
--   e.electric_buffer_size = e.power_usage * 2
-- It has no collision, so it can sit anywhere inside a pole's supply area
-- (e.g. on the roboport) without blocking anything.

local eei = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
eei.name = "bnm-rig-load"
eei.localised_name = { "", "Rig test load" }
eei.minable = nil
eei.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
eei.collision_mask = { layers = {} }
eei.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
eei.energy_source = {
    type = "electric",
    usage_priority = "secondary-input",
    buffer_capacity = "1MJ",
    input_flow_limit = "1GW",
    output_flow_limit = "0W",
}
eei.energy_production = "0W"
eei.energy_usage = "0W"
eei.gui_mode = "none"

data:extend({ eei })
