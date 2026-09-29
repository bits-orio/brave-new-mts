-- TEST-ONLY candidate prototypes for the Fulgora starter base power study.
-- lab-acc-b<MJ>-f<kW>: accumulator with buffer <MJ> and input_flow_limit <kW>
-- (output stays at vanilla 300 kW unless noted).
-- lab-col-d<kJ>: lightning-collector with drain <kJ> per tick (vanilla 2500).
-- lab-rod-d<kJ>: lightning-rod with drain <kJ> per tick.
local function acc(b, f, out)
    local a = table.deepcopy(data.raw["accumulator"]["accumulator"])
    a.name = "lab-acc-b" .. b .. "-f" .. f .. (out and ("-o" .. out) or "")
    a.minable = { mining_time = 0.1, result = "accumulator" }
    a.placeable_by = { item = "accumulator", count = 1 }
    a.energy_source = {
        type = "electric",
        buffer_capacity = b .. "MJ",
        usage_priority = "tertiary",
        input_flow_limit = f .. "kW",
        output_flow_limit = (out or 300) .. "kW",
    }
    return a
end
local list = {}
for _, b in pairs({ 5, 8, 10, 12, 15, 20, 25, 30, 40 }) do
    for _, f in pairs({ 300, 600, 1000, 1500, 2000, 3000, 5000, 10000, 20000 }) do
        list[#list + 1] = acc(b, f)
    end
end
for _, d in pairs({ 1000, 500, 250, 100, 50, 20, 5 }) do
    local c = table.deepcopy(data.raw["lightning-attractor"]["lightning-collector"])
    c.name = "lab-col-d" .. d
    c.minable = { mining_time = 0.1, result = "lightning-collector" }
    c.placeable_by = { item = "lightning-collector", count = 1 }
    c.energy_source.drain = d .. "kJ"
    list[#list + 1] = c
    local r = table.deepcopy(data.raw["lightning-attractor"]["lightning-rod"])
    r.name = "lab-rod-d" .. d
    r.minable = { mining_time = 0.1, result = "lightning-rod" }
    r.placeable_by = { item = "lightning-rod", count = 1 }
    r.energy_source.drain = d .. "kJ"
    list[#list + 1] = r
end
data:extend(list)
