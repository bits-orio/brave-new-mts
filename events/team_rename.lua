-- events/team_rename.lua
-- When a team is renamed (MTS on_team_renamed), update the team's label on its
-- landing-pen cell so the pen stays in sync with the team's chosen name.
--
-- Registration follows the multiplayer-safe pattern in team_tab.lua: the
-- remote.call (and event-id caching) happen only in setup() (on_init/on_config),
-- and register() re-attaches the handler each session from the cached id.

local pen_cells = require("scripts.pen_cells")

local M = {}

local function on_team_renamed(e)
    pen_cells.set_label(e.force_name, e.new_name)
end

--- Attach the handler from the cached id. Safe in on_init/on_load/on_config
--- (no remote.call); identical on every peer.
function M.register()
    local id = storage.bnm_team_renamed_event_id
    if id then script.on_event(id, on_team_renamed) end
end

--- Cache the on_team_renamed event id. Needs remote.call, so on_init /
--- on_configuration_changed only.
function M.setup()
    local iface = remote.interfaces["mts-v1"]
    if iface and iface.get_event_id then
        storage.bnm_team_renamed_event_id =
            remote.call("mts-v1", "get_event_id", "on_team_renamed")
    end
    M.register()
end

return M
