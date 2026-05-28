-- events/starter_items.lua
-- Takes over MTS's starter-item delivery. A BNM team has no player character to
-- receive the admin-configured starter items, so we register a delivery override
-- with MTS (via mts-v1) and route the items into the team's passive provider
-- chest instead:
--   * teams that spawn LATER pick up the current list at base placement, via
--     starter_base.mts_starter_items() (a get_starter_items query); and
--   * when an admin adds items while teams are already spawned, MTS raises
--     on_starter_items_added and we top up every placed base here.
-- Together those two paths give every team the full admin list.
--
-- Registration mirrors the multiplayer-safe pattern in team_tab.lua: the remote
-- call (and event-id caching) happens only in setup() (on_init / on_config), and
-- register() re-attaches the handler each session from the cached id.

local starter_base = require("scripts.starter_base")

local M = {}

local function on_items_added(e)
    starter_base.add_items_to_spawned_bases(e.items)
end

--- Attach the event handler from the cached id. Safe in on_init/on_load/on_config
--- (no remote.call); identical on every peer.
function M.register()
    local id = storage.bnm_starter_items_event_id
    if id then script.on_event(id, on_items_added) end
end

--- Register the delivery override with MTS and cache the on_starter_items_added
--- event id. Needs remote.call, so on_init / on_configuration_changed only.
function M.setup()
    local iface = remote.interfaces["mts-v1"]
    if not iface then return end
    if iface.register_starter_item_delivery then
        remote.call("mts-v1", "register_starter_item_delivery", "brave-new-mts")
    end
    if iface.get_event_id then
        storage.bnm_starter_items_event_id =
            remote.call("mts-v1", "get_event_id", "on_starter_items_added")
    end
    M.register()
end

return M
