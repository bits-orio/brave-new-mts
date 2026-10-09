-- scripts/team_tab/widgets.lua
-- What the team tab's sections share: the leader rule, a planet's name, a
-- section panel, wrapped text, a row, and the name prefix every element they
-- click on carries, so the click dispatcher (events/team_tab.lua) passes over
-- other GUIs' clicks with one string test.

local teams = require("scripts.teams")
local chat  = require("scripts.chat")

local M = {}

M.PREFIX = "bnm_tab_"
M.LABEL_WIDTH = 336      -- inside a section panel's padding
M.ROW_LABEL_WIDTH = 200  -- a label beside a button
M.LEADER_ONLY_NOTE = "[color=1,0.65,0]Only your team leader can change this.[/color]"

local PANEL_PADDING = 8

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

--- A section of the tab: a panel with a title bar, as the game's own windows
--- set theirs apart. Returns the flow its contents go into.
function M.section(parent, title)
    local panel = parent.add{ type = "frame", direction = "vertical", style = "inside_shallow_frame" }
    panel.style.horizontally_stretchable = true
    local head = panel.add{ type = "frame", style = "subheader_frame" }
    head.style.horizontally_stretchable = true
    head.add{ type = "label", caption = title, style = "subheader_caption_label" }
    local body = panel.add{ type = "flow", direction = "vertical" }
    body.style.padding = PANEL_PADDING
    body.style.vertical_spacing = 6
    return body
end

--- A label that wraps at `width` (the panel's width by default).
function M.label(parent, caption, width)
    local label = parent.add{ type = "label", caption = caption }
    label.style.single_line   = false
    label.style.maximal_width = width or M.LABEL_WIDTH
    return label
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
