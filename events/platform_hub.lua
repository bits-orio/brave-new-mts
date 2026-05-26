-- events/platform_hub.lua
-- Adds an "Establish base" button into the native space-platform-hub GUI, via
-- the mts-v1 register_platform_hub_widget API. The button is ALWAYS visible so
-- players can see the action exists; it is enabled only when a character clone
-- has been shipped to the hub and the platform is parked above one of the
-- team's planets that has no base yet. Clicking it consumes the clone, seeds
-- the starter base on the team's ground surface for that planet, and drops the
-- player's remote view down to it.
--
-- on_gui_click is dispatched centrally from control.lua (Factorio allows only
-- one handler for it), so M.register only wires the custom event handler.

local starter_base = require("scripts.starter_base")

local M = {}

local WIDGET_NAME      = "brave-new-mts-establish"
local ESTABLISH_BUTTON = "bnm_establish_base"
local CLONE            = "bnm-character-clone"

--- The team's ground-surface name for the planet this hub's platform is parked
--- above, plus a reason code when unavailable. MTS names each team's per-team
--- planet variant surface after the planet, so the platform's space-location
--- name resolves directly to a surface; get_surface_owner confirms it's this
--- player's team's surface (works regardless of variant naming).
local function target_for(player, hub)
    local platform = hub.surface and hub.surface.platform
    if not platform then return nil, "no_platform" end
    if platform.speed ~= 0 then return nil, "moving" end
    local loc = platform.space_location
    if not loc then return nil, "in_transit" end
    local surface = game.surfaces[loc.name]
    if not (surface and surface.valid) then return nil, "no_surface" end
    if not remote.interfaces["mts-v1"] then return nil, "no_mts" end
    if remote.call("mts-v1", "get_surface_owner", surface.name) ~= player.force.name then
        return nil, "not_team_planet"
    end
    return surface.name
end

local function hub_inventory(hub)
    return hub.get_inventory(defines.inventory.hub_main)
end

--- Assess whether a base can be established from this hub right now, and collect
--- ALL the reasons it can't. Returns: ready (bool), reasons (array of strings),
--- target surface name (or nil).
local function evaluate(player, hub)
    local surface_name, why = target_for(player, hub)
    local inv       = hub_inventory(hub)
    local has_clone = (inv and inv.get_item_count(CLONE) > 0) and true or false
    local placed    = (surface_name and storage.bases_placed
                       and storage.bases_placed[surface_name]) and true or false

    local reasons = {}
    if not has_clone then
        reasons[#reasons + 1] = "no Character Clone is aboard (ship one up in a rocket)"
    end
    if not surface_name then
        if why == "moving" or why == "in_transit" or why == "no_platform" then
            reasons[#reasons + 1] = "the platform isn't stopped at a planet"
        else
            reasons[#reasons + 1] = "this platform isn't above one of your team's planets"
        end
    elseif placed then
        reasons[#reasons + 1] = "your team already has a base on this planet"
    end

    local ready = has_clone and surface_name and not placed and true or false
    return ready, reasons, surface_name
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

    local ready, reasons = evaluate(player, hub)

    local btn = element[ESTABLISH_BUTTON]
    if not (btn and btn.valid) then
        btn = element.add{ type = "button", name = ESTABLISH_BUTTON }
    end
    btn.caption = { "", "[item=" .. CLONE .. "] Establish base" }
    apply_button_style(btn, ready and "green_button" or "red_button")

    if ready then
        btn.tooltip = { "", "Consume the [item=" .. CLONE .. "] and found your "
            .. "overseer base on this planet." }
    else
        btn.tooltip = "Can't establish a base here yet:\n• " .. table.concat(reasons, "\n• ")
    end
end

local function establish(player, hub)
    local ready, reasons, surface_name = evaluate(player, hub)
    if not ready then
        player.print("Can't establish a base: " .. table.concat(reasons, "; ") .. ".")
        return
    end

    local surface = game.surfaces[surface_name]
    if not (surface and surface.valid) then return end

    hub_inventory(hub).remove{ name = CLONE, count = 1 }
    starter_base.place(player.force.name, surface)
    -- Drop the overseer's view down to the new base; the character stays parked.
    player.set_controller{
        type     = defines.controllers.remote,
        surface  = surface,
        position = starter_base.BASE_ORIGIN,
    }
    player.print("Base established on " .. surface_name .. ".")
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
--- id. Safe only in on_init / on_configuration_changed -- never on_load.
function M.setup()
    local iface = remote.interfaces["mts-v1"]
    if not iface then return end
    if iface.register_platform_hub_widget then
        remote.call("mts-v1", "register_platform_hub_widget",
            { name = WIDGET_NAME, caption = "Brave New MTS", order = "z", position = "right" })
    end
    if iface.get_event_id then
        storage.bnm_hub_event_id =
            remote.call("mts-v1", "get_event_id", "on_platform_hub_gui_built")
    end
    M.register()
end

return M
