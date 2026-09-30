-- tools/rig/lua/regress_platform.lua
-- regress.py's platform helpers, loaded into BNM's own state after
-- regress.lua: a platform made by script in orbit, its hub's inventory, the
-- Establish-base core as the hub button calls it, a pad's deliveries, and
-- what the /bnm-test-orbit command leaves a force.

REG = REG or {}
local R = REG

local CLONE = "bnm-character-clone"

--- A platform of `force_name` by name, or nil.
local function platform(force_name, name)
    for _, p in pairs(game.forces[force_name].platforms) do
        if p.valid and p.name == name then return p end
    end
    return nil
end

--- The hub of the named platform, or an error.
function R.hub(force_name, name)
    local p = platform(force_name, name)
    local hub = p and p.hub
    if not (hub and hub.valid) then error("no hub on platform " .. name) end
    return hub
end

--- A platform created by script straight into orbit of `planet_name`. That
--- path, unlike flying there, does not create the planet's surface.
function R.make_platform(force_name, planet_name, name)
    local p = platform(force_name, name)
    if not p then
        p = game.forces[force_name].create_space_platform{
            name = name, planet = planet_name, starter_pack = "space-platform-starter-pack",
        }
        p.apply_starter_pack()
    end
    return { name = p.name, location = p.space_location and p.space_location.name,
             hub = p.hub and p.hub.valid, planet_surface = game.planets[planet_name].surface ~= nil }
end

local function hub_inventory(hub) return hub.get_inventory(defines.inventory.hub_main) end

--- Put items into a platform hub: { name, count, quality }.
function R.hub_insert(force_name, name, stack)
    return hub_inventory(R.hub(force_name, name)).insert(stack)
end

--- Clones aboard, of any quality.
function R.clones(force_name, name)
    return hub_inventory(R.hub(force_name, name)).get_item_count_filtered{ name = CLONE }
end

function R.hub_count(force_name, name, item)
    return hub_inventory(R.hub(force_name, name)).get_item_count(item)
end

--- The Establish-base core, exactly as the hub button calls it.
function R.establish(force_name, name)
    local ok, reason, surface, home = R.module("events/platform_hub").establish_for(
        game.forces[force_name], R.hub(force_name, name))
    return { ok = ok, reason = reason, surface = surface, home = home or false }
end

-- ─── Pad deliveries ──────────────────────────────────────────────────

--- Ask the base's landing pad for `count` of `item` (a normal logistic request).
function R.pad_request(surface_name, item, count)
    local pad = R.module("scripts/starter_base").base_for(surface_name).pad
    local section = pad.get_logistic_sections().add_section()
    section.set_slot(1, { value = item, min = count })
    return true
end

function R.pad_count(surface_name, item)
    local rec = R.module("scripts/starter_base").base_for(surface_name)
    local pad = rec and rec.pad
    local net = rec and rec.roboport and rec.roboport.valid and rec.roboport.logistic_network
    return { pad = (pad and pad.valid) and pad.get_item_count(item) or 0,
             network = net and net.get_item_count(item) or 0 }
end

-- ─── What /bnm-test-orbit leaves behind ──────────────────────────────

--- A force's live platforms: name, where each is parked, clones aboard.
local function platforms_of(force)
    local out = {}
    for _, p in pairs(force.platforms) do
        if p.valid and p.scheduled_for_deletion == 0 then
            local hub = p.hub and p.hub.valid and p.hub
            out[#out + 1] = { name = p.name, at = p.space_location and p.space_location.name or false,
                              clones = hub and hub_inventory(hub).get_item_count_filtered{ name = CLONE } or 0 }
        end
    end
    return out
end

--- What the test command may change for a force: how many technologies it
--- has researched, whether each of `techs` is, whether `planet_name` is
--- unlocked and has a surface, and its platforms.
function R.orbit_state(force_name, planet_name, techs)
    local force = game.forces[force_name]
    local out = { researched = 0, techs = {}, unlocked = force.is_space_location_unlocked(planet_name),
                  surface = game.planets[planet_name].surface ~= nil, platforms = platforms_of(force) }
    for _, t in pairs(force.technologies) do
        if t.researched then out.researched = out.researched + 1 end
    end
    for _, name in pairs(techs) do out.techs[name] = force.technologies[name].researched end
    return out
end

return true
