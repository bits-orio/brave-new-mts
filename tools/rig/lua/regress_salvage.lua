-- tools/rig/lua/regress_salvage.lua
-- regress.py's helpers for what a re-found must keep whole, loaded into BNM's
-- own state after regress.lua: vehicles with equipment, a train on its rails
-- and items that carry data (an equipment grid, a set-up blueprint) in and
-- around an outpost's site, and where each of them is after the sweep.

REG = REG or {}
local R = REG

local FLOOR = "refined-concrete"   -- laid under the fixtures, so they stand on any planet

--- The area BNM's re-found sweeps on an outpost's surface (scripts/base/geometry.lua site_for).
function R.sweep_area(surface_name)
    local s = game.surfaces[surface_name]
    local plan = R.module("scripts/blueprints").plan_for(R.module("scripts/starter_base").profile_for(s), false)
    local geometry = R.module("scripts/base/geometry")
    return geometry.site_for(geometry.BASE_ORIGIN, plan, true).area
end

local function equipment(grid)
    local n = 0
    for _, c in pairs(grid.get_contents()) do n = n + c.count end
    return n
end

--- "spidertron eq=3" or "blueprint set-up" for a stack that carries data, else nil.
local function data_of(stack)
    if not stack.valid_for_read then return nil end
    if stack.is_blueprint then return stack.name .. (stack.is_blueprint_setup() and " set-up" or " blank") end
    if stack.grid then return stack.name .. " eq=" .. equipment(stack.grid) end
    return nil
end

--- Every item that carries data in the force's site (all its inventories)
--- and on the ground around the base, as data_of strings, sorted.
function R.data_items(surface_name, force_name)
    local s, out = game.surfaces[surface_name], {}
    local function add(stack)
        local d = data_of(stack)
        if d then out[#out + 1] = d end
    end
    for _, e in pairs(s.find_entities_filtered{ area = R.site(s, force_name).area, force = force_name }) do
        for i = 1, e.get_max_inventory_index() do
            local inv = e.get_inventory(i)
            if inv and inv.valid then for j = 1, #inv do add(inv[j]) end end
        end
    end
    for _, e in pairs(s.find_entities_filtered{ type = "item-entity", area = { { -84, -84 }, { 116, 116 } } }) do
        add(e.stack)
    end
    table.sort(out)
    return out
end

local function lay_floor(s, area)
    local tiles = {}
    for x = math.floor(area[1][1]), math.ceil(area[2][1]) - 1 do
        for y = math.floor(area[1][2]), math.ceil(area[2][2]) - 1 do
            tiles[#tiles + 1] = { name = FLOOR, position = { x, y } }
        end
    end
    s.set_tiles(tiles)
end

--- A vehicle `v.name` at `v.position` with the equipment `v.grid` and, when
--- given, `v.items` in its inventory `v.inventory`.
local function vehicle(s, force_name, v)
    local e = s.create_entity{ name = v.name, position = v.position, force = force_name }
    for _, eq in ipairs(v.grid) do e.grid.put{ name = eq } end
    if v.items then e.get_inventory(v.inventory).insert(v.items) end
    return e
end

--- Put a `name` item into `inv` with `n` pieces of `eq` in its grid.
local function equipped_item(inv, name, eq, n)
    inv.insert{ name = name }
    local stack = inv.find_item_stack(name)
    if not stack.grid then stack.create_grid() end
    for _ = 1, n do stack.grid.put{ name = eq } end
end

--- Items with data in chests: an iron chest the team built holding a
--- spidertron item with 2 pieces of equipment, a modular armor with 1 and a
--- set-up blueprint; and a spidertron item with 1 piece in one of the base's
--- own storage chests, which the sweep empties rather than mines.
local function data_chests(s, force_name, position, base)
    local chest = s.create_entity{ name = "iron-chest", position = position, force = force_name }
    local inv = chest.get_inventory(defines.inventory.chest)
    equipped_item(inv, "spidertron", "exoskeleton-equipment", 2)
    equipped_item(inv, "modular-armor", "solar-panel-equipment", 1)
    inv.insert{ name = "blueprint" }
    inv.find_item_stack("blueprint").set_blueprint_entities({
        { entity_number = 1, name = "iron-chest", position = { 0.5, 0.5 } } })
    equipped_item(base.storage_chests[1].get_inventory(defines.inventory.chest),
        "spidertron", "exoskeleton-equipment", 1)
end

--- Six rails across the gap above the pad (`y` their centre row), with a
--- locomotive on them carrying 10 coal. Returns the rails built and the locomotive.
local function train(s, force_name, x0, y)
    local rails = 0
    for i = 0, 5 do
        local r = s.create_entity{ name = "straight-rail", position = { x0 + 2 * i, y },
                                   direction = defines.direction.east, force = force_name }
        if r then rails = rails + 1 end
    end
    local loco = s.create_entity{ name = "locomotive", position = { x0 + 6, y },
                                  direction = defines.direction.east, force = force_name }
    if loco then loco.get_inventory(defines.inventory.fuel).insert{ name = "coal", count = 10 } end
    return rails, loco
end

--- How many of `spider`'s legs lie in `area`, found the way the sweep finds them.
local function legs_in(s, area, spider)
    local n = 0
    for _, found in pairs(s.find_entities_filtered{ area = area, type = "spider-leg" }) do
        for _, leg in pairs(spider.get_spider_legs()) do
            if leg == found then n = n + 1 end
        end
    end
    return n
end

--- Build, around a force's outpost (pad centre P): an equipped spidertron (3
--- pieces, 50 iron plate in its trunk) beside the pad, an equipped tank (2
--- pieces, 20 wood as fuel) on its other side, the train of `train` above
--- it, the data_chests, and a spidertron (1 piece) parked just outside the site
--- with legs reaching in. Returns what the check needs to find them again.
function R.build_data_extras(surface_name, force_name)
    local s, area = game.surfaces[surface_name], R.sweep_area(surface_name)
    local p = R.site(s, force_name).pad.position
    lay_floor(s, { { area[1][1] - 8, p.y - 7 }, { area[2][1], area[2][2] } })
    local spider = vehicle(s, force_name, { name = "spidertron", position = { p.x - 11, p.y },
        grid = { "exoskeleton-equipment", "exoskeleton-equipment", "personal-roboport-equipment" },
        inventory = defines.inventory.spider_trunk, items = { name = "iron-plate", count = 50 } })
    local tank = vehicle(s, force_name, { name = "tank", position = { p.x + 11, p.y },
        grid = { "solar-panel-equipment", "solar-panel-equipment" },
        inventory = defines.inventory.fuel, items = { name = "wood", count = 20 } })
    local rails, loco = train(s, force_name, p.x - 13, p.y - 5)
    data_chests(s, force_name, { p.x + 4.5, p.y - 5.5 }, R.module("scripts/starter_base").base_for(surface_name))
    local outside = vehicle(s, force_name, { name = "spidertron", position = { area[1][1] - 2.5, p.y },
        grid = { "exoskeleton-equipment" } })
    local ob = outside.bounding_box
    return { spider_eq = equipment(spider.grid), tank_eq = equipment(tank.grid), rails = rails,
             loco = loco ~= nil, data = R.data_items(surface_name, force_name),
             outside = { unit = outside.unit_number, x = outside.position.x, y = outside.position.y,
                         eq = equipment(outside.grid), legs_in = legs_in(s, area, outside),
                         body_out = ob.right_bottom.x < area[1][1] } }
end

--- After the re-found: the data items, the outside spider (by unit number)
--- and how many rails and locomotives still stand in the swept area.
function R.data_after(surface_name, force_name, outside_unit)
    local s, area = game.surfaces[surface_name], R.sweep_area(surface_name)
    local o = game.get_entity_by_unit_number(outside_unit)
    return { data = R.data_items(surface_name, force_name),
             outside = o and { x = o.position.x, y = o.position.y, eq = equipment(o.grid) } or false,
             rails = s.count_entities_filtered{ area = area, type = "straight-rail" },
             locos = s.count_entities_filtered{ area = area, type = "locomotive" } }
end

return true
