-- events/team_cleanup.lua
-- When MTS releases a team slot (on_team_released), it has already deleted that
-- team's surfaces. We must forget our matching per-surface state so a team that
-- later recycles the same slot -- and thus the same surface name -- gets a fresh
-- starter base instead of being silently skipped (which would leave the new
-- occupant staring at an unrevealed, base-less surface).
--
-- Its spent rescues are forgotten too, so the next team in the slot gets the
-- full allowance. The team's pen cell is cleared too: bodies of members who were offline when
-- the team ended are moved out (MTS returns only connected members to the pen),
-- and the cell label goes back to the slot's reset name. MTS resets the name
-- without raising on_team_renamed, so it is re-read from get_team_info.
--
-- Registration follows the multiplayer-safe pattern in team_tab.lua: register()
-- attaches the handler each session, with the event id looked up that session
-- (scripts/mts_events.lua).

local starter_base  = require("scripts.starter_base")
local rescue        = require("scripts.rescue")
local remote_player = require("scripts.remote_player")
local pen_cells     = require("scripts.pen_cells")
local mts_events    = require("scripts.mts_events")
local teams         = require("scripts.teams")

local M = {}

local function on_team_released(e)
    starter_base.cleanup_force(e.force_name)
    rescue.cleanup_force(e.force_name)
    remote_player.cleanup_force(e.force_name)
    pen_cells.evict_cell(e.force_name)
    pen_cells.set_label(e.force_name, teams.display_name(e.force_name))
end

--- Attach the handler. Safe in on_init/on_load/on_config; identical on every
--- peer.
function M.register()
    local id = mts_events.id("on_team_released")
    if id then script.on_event(id, on_team_released) end
end

return M
