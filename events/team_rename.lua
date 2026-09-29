-- events/team_rename.lua
-- When a team is renamed (MTS on_team_renamed), update the team's label on its
-- landing-pen cell so the pen stays in sync with the team's chosen name.
--
-- Registration follows the multiplayer-safe pattern in team_tab.lua: register()
-- attaches the handler each session, with the event id looked up that session
-- (scripts/mts_events.lua).

local pen_cells  = require("scripts.pen_cells")
local mts_events = require("scripts.mts_events")

local M = {}

local function on_team_renamed(e)
    pen_cells.set_label(e.force_name, e.new_name)
end

--- Attach the handler. Safe in on_init/on_load/on_config; identical on every
--- peer.
function M.register()
    local id = mts_events.id("on_team_renamed")
    if id then script.on_event(id, on_team_renamed) end
end

return M
