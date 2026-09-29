-- events/starter_items.lua
-- Takes over MTS's starter-item delivery. A BNM team has no player character to
-- receive the admin-configured starter items, so we register a delivery override
-- with MTS (via mts-v1) and route the items into the team's passive provider
-- chest instead:
--   * teams that spawn LATER pick up the current list at base placement, via
--     mts_starter_items() in scripts/base/kits.lua (a get_starter_items query); and
--   * when an admin adds items while teams are already spawned, MTS raises
--     on_starter_items_added and we top up every placed base here.
-- Together those two paths give every team the full admin list.
--
-- Registration mirrors the multiplayer-safe pattern in team_tab.lua: the
-- delivery override is registered only in setup() (on_init / on_config), and
-- register() attaches the handler each session, with the event id looked up
-- that session (scripts/mts_events.lua).

local starter_base = require("scripts.starter_base")
local mts_events   = require("scripts.mts_events")

local M = {}

local function on_items_added(e)
    starter_base.add_items_to_spawned_bases(e.items)
end

--- Attach the event handler. Safe in on_init/on_load/on_config; identical on
--- every peer.
function M.register()
    local id = mts_events.id("on_starter_items_added")
    if id then script.on_event(id, on_items_added) end
end

--- Register the delivery override with MTS. It writes MTS's storage, so
--- on_init / on_configuration_changed only.
function M.setup()
    local iface = remote.interfaces["mts-v1"]
    if iface and iface.register_starter_item_delivery then
        remote.call("mts-v1", "register_starter_item_delivery", "brave-new-mts")
    end
end

return M
