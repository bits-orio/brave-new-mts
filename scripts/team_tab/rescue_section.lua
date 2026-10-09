-- scripts/team_tab/rescue_section.lua
-- The team tab's rescues (scripts/rescue.lua): the team's cards
-- (scripts/team_tab/rescue_cards.lua), then either a line saying no base needs
-- one or each base whose roboport is out of power, with a button for the team
-- leader that spends a rescue on it.

local rescue  = require("scripts.rescue")
local chat    = require("scripts.chat")
local cards   = require("scripts.team_tab.rescue_cards")
local widgets = require("scripts.team_tab.widgets")

local M = {}

local RESCUE = "rescue"

local ABOUT = "A rescue refills a base's roboport that ran out of power, at once. Without one, "
    .. "its robots stay stopped until the base's power has recharged it."

local ALL_POWERED = "[img=utility/check_mark_green] No base needs a rescue: every roboport has power."

local NONE_LEFT = "Your team has no rescues left. An admin can still restart a roboport with "
    .. "/bnm-rescue."

local TOOLTIP = "Spend one of your team's rescues to refill this base's roboport now."

local function dark_row(parent, surface_name, can_rescue)
    local row = widgets.row(parent)
    widgets.label(row, { "", "[img=utility/warning_icon] ", widgets.planet_label(surface_name),
        ": roboport out of power" }, widgets.ROW_LABEL_WIDTH)
    if can_rescue then
        widgets.surface_button(row, RESCUE, surface_name, "Spend a rescue", "green_button", TOOLTIP)
    end
end

--- What needs a rescue now: nothing, or each dark base.
local function status(player, body)
    local force_name = player.force.name
    local dark = rescue.dark_bases(force_name)
    if #dark == 0 then
        widgets.label(body, ALL_POWERED)
        return
    end
    local left = rescue.left(force_name)
    local can_rescue = left > 0 and widgets.is_leader(player)
    for _, surface_name in ipairs(dark) do dark_row(body, surface_name, can_rescue) end
    if left == 0 then widgets.label(body, NONE_LEFT) end
end

--- The Rescues panel: how many are left, the cards, then what needs one.
function M.build(player, parent)
    local force_name = player.force.name
    local body = widgets.section(parent, "Rescues: " .. rescue.left(force_name) .. " of "
        .. rescue.allowance() .. " left")
    widgets.label(body, ABOUT)
    cards.draw(body, force_name)
    status(player, body)
end

local function announce(player, surface_name)
    local left = rescue.left(player.force.name)
    player.force.print({ "", chat.PREFIX, player.name, " spent a rescue on your ",
        widgets.planet_label(surface_name), " base: its roboport is full again, so its "
        .. "robots are back at work. Rescues left: " .. left .. "." })
    log("[brave-new-mts] " .. player.name .. " (" .. player.force.name .. ") spent a rescue on "
        .. surface_name .. "; " .. left .. " left")
end

--- nil for another section's element; true (rebuild the tab) for the button.
function M.on_click(player, el)
    if el.name ~= widgets.PREFIX .. RESCUE then return nil end
    if not widgets.is_leader(player) then return true end
    local surface_name = el.tags.surface
    local ok, why = rescue.spend(player.force.name, surface_name, player.name)
    if ok then
        announce(player, surface_name)
    else
        player.print(chat.PREFIX .. "Can't rescue that base: " .. why .. ".")
    end
    return true
end

return M
