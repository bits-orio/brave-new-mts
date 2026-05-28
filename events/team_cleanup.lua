-- events/team_cleanup.lua
-- When MTS releases a team slot (on_team_released), it has already deleted that
-- team's surfaces. We must forget our matching per-surface state so a team that
-- later recycles the same slot -- and thus the same surface name -- gets a fresh
-- starter base instead of being silently skipped (which would leave the new
-- occupant staring at an unrevealed, base-less surface).
--
-- Registration follows the multiplayer-safe pattern in team_tab.lua: the
-- remote.call (and event-id caching) happen only in setup() (on_init/on_config),
-- and register() re-attaches the handler each session from the cached id.

local starter_base  = require("scripts.starter_base")
local remote_player = require("scripts.remote_player")

local M = {}

local function on_team_released(e)
    starter_base.cleanup_force(e.force_name)
    remote_player.cleanup_force(e.force_name)
end

--- Attach the handler from the cached id. Safe in on_init/on_load/on_config
--- (no remote.call); identical on every peer.
function M.register()
    local id = storage.bnm_team_released_event_id
    if id then script.on_event(id, on_team_released) end
end

--- Cache the on_team_released event id. Needs remote.call, so on_init /
--- on_configuration_changed only.
function M.setup()
    local iface = remote.interfaces["mts-v1"]
    if iface and iface.get_event_id then
        storage.bnm_team_released_event_id =
            remote.call("mts-v1", "get_event_id", "on_team_released")
    end
    M.register()
end

return M
