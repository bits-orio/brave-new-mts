-- events/platform_hub.lua
-- Adds an "Establish base" button into the native space-platform-hub GUI, via
-- the mts-v1 register_platform_hub_widget API. The button is ALWAYS visible so
-- players can see the action exists; it is enabled only when a Character Clone
-- of any quality is aboard, the hub belongs to the player's team, and the
-- platform is parked above one of the team's planets that has no base yet.
--
-- The core, M.establish_for(force, hub), needs no player (so it can be tested
-- headless): it creates the planet's surface if it doesn't exist yet, founds an
-- OUTPOST there (starter_base.place with { outpost = true }), and only then
-- consumes one clone. The click handler wraps it for the player: it moves their
-- remote view down to the new base and tells the team.
--
-- The widget polls evaluate(), which must never create a surface.
--
-- on_gui_click is dispatched centrally from control.lua (Factorio allows only
-- one handler for it), so M.register only wires the custom event handler.

local starter_base = require("scripts.starter_base")

local M = {}

local WIDGET_NAME      = "brave-new-mts-establish"
local ESTABLISH_BUTTON = "bnm_establish_base"
local CLONE            = "bnm-character-clone"

local REASONS = {
    not_parked      = "the platform isn't stopped at a planet",
    not_team_planet = "this platform isn't above one of your team's planets",
    no_mts          = "Multi-Team Support isn't running",
}

--- The planet this hub's platform is parked at, or nil plus a reason code.
--- `space_location` is set only while parked. Do NOT test `speed`: it is still
--- above zero for about 940 ticks after arrival, while the hub already shows
--- the platform as parked.
local function target_for(force, hub)
    local platform = hub.surface and hub.surface.platform
    if not platform then return nil, "not_parked" end
    local loc = platform.space_location
    if not loc then return nil, "not_parked" end
    local planet = game.planets[loc.name]
    if not planet then return nil, "not_parked" end  -- a space location, not a planet
    if not remote.interfaces["mts-v1"] then return nil, "no_mts" end
    local surface = planet.surface
    if surface and surface.valid then
        if remote.call("mts-v1", "get_surface_owner", surface.name) ~= force.name then
            return nil, "not_team_planet"
        end
    elseif not force.is_space_location_unlocked(planet.name) then
        -- No surface yet, so MTS cannot name an owner. MTS unlocks only a
        -- team's own planet variants; establish_for confirms ownership once
        -- the surface exists.
        return nil, "not_team_planet"
    end
    return planet
end

local function hub_inventory(hub)
    return hub.get_inventory(defines.inventory.hub_main)
end

--- Quality of a clone aboard (normal preferred), or nil if there is none. Any
--- quality founds a base. get_item_count(name) counts normal quality only, so
--- read get_contents, which every 2.0 version has.
local function clone_quality(inv)
    if not inv then return nil end
    local found
    for _, item in pairs(inv.get_contents()) do
        if item.name == CLONE then
            if item.quality == "normal" then return "normal" end
            found = found or item.quality
        end
    end
    return found
end

--- Assess whether `force` can establish a base from this hub right now, and
--- collect ALL the reasons it can't. Returns: ready (bool), reasons (array of
--- strings), target LuaPlanet (or nil). Never creates a surface.
local function evaluate(force, hub)
    local reasons = {}
    if hub.force.name ~= force.name then
        return false, { "this platform belongs to another team" }, nil
    end
    local planet, why = target_for(force, hub)
    local has_clone   = clone_quality(hub_inventory(hub)) ~= nil
    -- A planet's surface is named after the planet.
    local placed      = planet and starter_base.base_for(planet.name) ~= nil

    if not has_clone then
        reasons[#reasons + 1] = "no Character Clone is aboard (ship one up in a rocket)"
    end
    if not planet then
        reasons[#reasons + 1] = REASONS[why] or why
    elseif placed then
        reasons[#reasons + 1] = "your team already has a base on this planet"
    end

    local ready = has_clone and planet ~= nil and not placed
    return ready, reasons, planet
end

--- The base planet of an MTS team variant: "mts-vulcanus-3" -> "vulcanus".
local function base_planet(planet_name)
    return planet_name:match("^mts%-(.+)%-%d+$") or planet_name
end

--- Tell MTS a team founded its first base on a planet, for its first-to-reach
--- announcement and the Awards records. MTS dedupes repeat reports, so a
--- re-founded outpost is not announced twice.
local function report_milestone(force, planet_name)
    local iface = remote.interfaces["mts-v1"]
    if not (iface and iface.report_milestone) then return end
    local base     = base_planet(planet_name)
    local category = "bnm-base-" .. base
    if iface.register_milestone then  -- idempotent: overwrites the same entry
        remote.call("mts-v1", "register_milestone", {
            category        = category,
            verb            = "establish",
            noun            = (base:gsub("^%l", string.upper)) .. " outpost",
            first_threshold = 1,
        })
    end
    remote.call("mts-v1", "report_milestone", force.name, category, 1)
end

--- Found an outpost for `force` from `hub`. Returns ok, reason (when not ok),
--- and the new base's surface name. The clone is consumed only once the base
--- stands, so a failed placement costs nothing.
function M.establish_for(force, hub)
    if not (hub and hub.valid and hub.type == "space-platform-hub") then
        return false, "that is not a platform hub"
    end
    local ready, reasons, planet = evaluate(force, hub)
    if not ready then return false, table.concat(reasons, "; ") end

    -- The surface may not exist yet (the platform was never flown here, or it
    -- was deleted). MTS owns it the moment it is created, so confirm now.
    local surface = planet.surface or planet.create_surface()
    if remote.call("mts-v1", "get_surface_owner", surface.name) ~= force.name then
        return false, REASONS.not_team_planet
    end

    if not starter_base.place(force.name, surface, { outpost = true }) then
        return false, "the starter base could not be placed here (your clone was kept)"
    end

    local inv = hub_inventory(hub)
    local quality = clone_quality(inv)
    if not (quality and inv.remove{ name = CLONE, quality = quality, count = 1 } == 1) then
        log("[brave-new-mts] outpost on " .. surface.name .. " placed, but no clone was left to consume")
    end
    report_milestone(force, planet.name)
    log("[brave-new-mts] " .. force.name .. " established an outpost on " .. surface.name)
    return true, nil, surface.name
end

-- Make the button big and bold; assigning a style resets it, so size after.
local function apply_button_style(btn, style_name)
    btn.style                          = style_name
    btn.style.minimal_width            = 220
    btn.style.minimal_height           = 40
    btn.style.horizontally_stretchable = true
    btn.style.font                     = "default-large-bold"
end

--- Fill / refresh the anchored widget. Updates the button IN PLACE (no clear),
--- so the bounded refresh poll doesn't make it flicker. Green when ready to
--- establish, red otherwise, with a tooltip listing every blocking reason.
local function build_widget(player, element, hub)
    if not (player and player.valid and element and element.valid
            and hub and hub.valid) then return end

    local ready, reasons = evaluate(player.force, hub)

    local btn = element[ESTABLISH_BUTTON]
    if not (btn and btn.valid) then
        btn = element.add{ type = "button", name = ESTABLISH_BUTTON }
    end
    btn.caption = { "", "[item=" .. CLONE .. "] Establish base" }
    apply_button_style(btn, ready and "green_button" or "red_button")

    if ready then
        btn.tooltip = "Consume one [item=" .. CLONE .. "] and found an outpost on "
            .. "this planet. If its roboport is destroyed, only this outpost is "
            .. "lost; your home base is safe, and another clone re-founds it."
    else
        btn.tooltip = "Can't establish a base here yet:\n• " .. table.concat(reasons, "\n• ")
    end
end

local function planet_label(surface)
    return surface.planet and surface.planet.prototype.localised_name or surface.name
end

--- The click, for a player: establish, then drop their remote view onto the
--- new base (the character stays parked in the pen) and tell the team.
local function establish(player, hub)
    local ok, reason, surface_name = M.establish_for(player.force, hub)
    if not ok then
        player.print("Can't establish a base: " .. reason .. ".")
        return
    end
    local surface = game.surfaces[surface_name]
    player.set_controller{
        type     = defines.controllers.remote,
        surface  = surface,
        position = starter_base.BASE_ORIGIN,
    }
    player.force.print({ "", "[Brave New MTS] ", player.name, " founded an outpost on ",
        planet_label(surface), ". If its roboport is destroyed, only this outpost ",
        "is lost, and another clone re-founds it." })
end

--- Handler for the mts-v1 on_platform_hub_gui_built event.
local function on_widget_built(e)
    if e.widget_name ~= WIDGET_NAME then return end
    build_widget(game.get_player(e.player_index), e.element, e.entity)
end

--- Called from control.lua's single on_gui_click dispatcher.
function M.on_gui_click(event)
    local el = event.element
    if not (el and el.valid and el.name == ESTABLISH_BUTTON) then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local hub = player.opened
    if not (hub and hub.object_name == "LuaEntity"
            and hub.valid and hub.type == "space-platform-hub") then return end
    establish(player, hub)
end

--- Deterministic handler registration (MP-safe): the event id is read from
--- storage, cached by M.setup() during on_init / on_configuration_changed.
function M.register()
    local id = storage.bnm_hub_event_id
    if id then script.on_event(id, on_widget_built) end
end

--- Side-effecting setup that needs remote.call: register the hub widget with
--- MTS (persisted in its storage) and cache the on_platform_hub_gui_built event
--- id. Safe only in on_init / on_configuration_changed -- never on_load. `mod`
--- lets MTS drop the registration if BNM is removed from the save.
function M.setup()
    local iface = remote.interfaces["mts-v1"]
    if not iface then return end
    if iface.register_platform_hub_widget then
        remote.call("mts-v1", "register_platform_hub_widget", {
            name = WIDGET_NAME, caption = "Brave New MTS", order = "z",
            position = "right", mod = script.mod_name,
        })
    end
    if iface.get_event_id then
        storage.bnm_hub_event_id =
            remote.call("mts-v1", "get_event_id", "on_platform_hub_gui_built")
    end
    M.register()
end

return M
