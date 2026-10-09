-- scripts/team_tab/widgets.lua
-- What the team tab's sections share: the leader rule, a planet's name, wrapped
-- text, a section heading, a row, and the name prefix every element they click
-- on carries, so the click dispatcher (events/team_tab.lua) passes over other
-- GUIs' clicks with one string test.

local teams = require("scripts.teams")
local chat  = require("scripts.chat")

local M = {}

M.PREFIX = "bnm_tab_"
M.LABEL_WIDTH = 360
M.ROW_LABEL_WIDTH = 220  -- a label beside a button
M.LEADER_ONLY_NOTE = "[color=1,0.65,0]Only your team leader can change this.[/color]"

--- True if the player leads their team, which every button in the tab needs.
function M.is_leader(player)
    local info = teams.info(player.force.name)
    return info ~= nil and info.leader_player_index == player.index
end

--- A surface's planet as the tab names it. A tab can be older than the
--- surface's deletion, so a surface that is gone is named by its name.
function M.planet_label(surface_name)
    local surface = game.surfaces[surface_name]
    return surface and chat.planet_label(surface) or surface_name
end

--- A label that wraps at `width` (the tab's width by default).
function M.label(parent, caption, width)
    local label = parent.add{ type = "label", caption = caption }
    label.style.single_line   = false
    label.style.maximal_width = width or M.LABEL_WIDTH
    return label
end

--- A line, then a section's bold heading.
function M.heading(parent, caption)
    parent.add{ type = "line" }
    return parent.add{ type = "label", caption = caption, style = "caption_label" }
end

--- A horizontal row: a label and its buttons.
function M.row(parent)
    local row = parent.add{ type = "flow", direction = "horizontal" }
    row.style.vertical_align = "center"
    return row
end

--- A button for the planet surface `surface_name`, named `name` (PREFIX added).
function M.surface_button(parent, name, surface_name, caption, style, tooltip)
    return parent.add{ type = "button", name = M.PREFIX .. name, caption = caption, style = style,
        tooltip = tooltip, tags = { surface = surface_name } }
end

return M
