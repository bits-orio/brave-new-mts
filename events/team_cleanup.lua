-- events/team_cleanup.lua
-- When MTS releases a team slot (on_team_released), it has already deleted that
-- team's surfaces. We must forget our matching per-surface state so a team that
-- later recycles the same slot -- and thus the same surface name -- gets a fresh
-- starter base instead of being silently skipped (which would leave the new
-- occupant staring at an unrevealed, base-less surface).
--
-- The team's pen cell is cleared too: bodies of members who were offline when
-- the team ended are moved out (MTS returns only connected members to the pen),
-- and the cell label goes back to the slot's reset name. MTS resets the name
-- without raising on_team_renamed, so it is re-read from get_team_info.
--
-- Registration follows the multiplayer-safe pattern in team_tab.lua: the
-- remote.call (and event-id caching) happen only in setup() (on_init/on_config),
-- and register() re-attaches the handler each session from the cached id.

local starter_base  = require("scripts.starter_base")
local remote_player = require("scripts.remote_player")
local pen_cells     = require("scripts.pen_cells")

local M = {}

local function on_team_released(e)
    starter_base.cleanup_force(e.force_name)
    remote_player.cleanup_force(e.force_name)
    pen_cells.evict_cell(e.force_name)
    local info = remote.interfaces["mts-v1"]
        and remote.call("mts-v1", "get_team_info", e.force_name)
    pen_cells.set_label(e.force_name, (info and info.display_name) or e.force_name)
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
