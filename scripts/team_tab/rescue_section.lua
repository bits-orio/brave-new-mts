-- scripts/team_tab/rescue_section.lua
-- The team tab's rescues (scripts/rescue.lua): how many the team has left, each
-- base whose roboport is out of power, and for the team leader a button that
-- spends a rescue on it.

local rescue  = require("scripts.rescue")
local chat    = require("scripts.chat")
local widgets = require("scripts.team_tab.widgets")

local M = {}

local RESCUE = "rescue"

local ABOUT = "If a base's roboport runs out of power, its network shuts down and its robots "
    .. "stop until the base's power has recharged it. A rescue refills it at once."

local TOOLTIP = "Spend one of your team's rescues to refill this base's roboport now."

local function dark_row(parent, surface_name, can_rescue)
    local row = widgets.row(parent)
    widgets.label(row, { "", widgets.planet_label(surface_name), ": roboport out of power" },
        widgets.ROW_LABEL_WIDTH)
    if can_rescue then
        widgets.surface_button(row, RESCUE, surface_name, "Rescue", "green_button", TOOLTIP)
    end
end

--- The heading with the rescues left, then every dark base.
function M.build(player, parent)
    local force_name = player.force.name
    local left = rescue.left(force_name)
    widgets.heading(parent, "Rescues: " .. left .. " of " .. rescue.allowance() .. " left")
    widgets.label(parent, ABOUT)
    local dark = rescue.dark_bases(force_name)
    if #dark == 0 then
        widgets.label(parent, "Every base's roboport has power.")
        return
    end
    local can_rescue = left > 0 and widgets.is_leader(player)
    for _, surface_name in ipairs(dark) do dark_row(parent, surface_name, can_rescue) end
end

local function announce(player, surface_name)
    local left = rescue.left(player.force.name)
    player.force.print({ "", chat.PREFIX, player.name, " spent a rescue on your ",
        widgets.planet_label(surface_name), " base: its roboport is full again, so its "
        .. "robots are back at work. Rescues left: " .. left .. "." })
    log("[brave-new-mts] " .. player.name .. " (" .. player.force.name .. ") spent a rescue on "
        .. surface_name .. "; " .. left .. " left")
end

--- nil for another section's element; true (rebuild the tab) for Rescue.
function M.on_click(player, el)
    if el.name ~= widgets.PREFIX .. RESCUE then return nil end
    if not widgets.is_leader(player) then return true end
    local surface_name = el.tags.surface
    local ok, why = rescue.spend(player.force.name, surface_name)
    if ok then
        announce(player, surface_name)
    else
        player.print(chat.PREFIX .. "Can't rescue that base: " .. why .. ".")
    end
    return true
end

return M
