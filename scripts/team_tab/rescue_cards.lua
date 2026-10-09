-- scripts/team_tab/rescue_cards.lua
-- The team's rescues drawn as cards, one per rescue the map setting allows:
-- the unused ones first (the green Brave New Roboport, "Ready"), then the
-- spent ones (a grey cross, "Used", and the planet each went on).

local rescue  = require("scripts.rescue")
local widgets = require("scripts.team_tab.widgets")

local M = {}

local COLUMNS = 4   -- 4 cards and their gaps fit the panel's width
local CARD_WIDTH, CARD_HEIGHT, ICON_SIZE, GAP = 76, 100, 40, 8
local READY_COLOR = { 0.55, 1, 0.55 }
local USED_COLOR  = { 0.6, 0.6, 0.6 }

local READY_TIP = "Unused. When a base's roboport runs out of power, the team leader can "
    .. "spend this rescue to refill it at once."

--- A card: a dark inset with an icon and a bold status, all sharing a tooltip.
local function card(parent, sprite, status, color, tooltip)
    local frame = parent.add{ type = "frame", direction = "vertical",
        style = "deep_frame_in_shallow_frame", tooltip = tooltip }
    frame.style.size = { CARD_WIDTH, CARD_HEIGHT }
    frame.style.padding = 6
    frame.style.horizontal_align = "center"
    local icon = frame.add{ type = "sprite", sprite = sprite, tooltip = tooltip }
    icon.style.size = ICON_SIZE
    icon.style.stretch_image_to_widget_size = true
    local label = frame.add{ type = "label", caption = status, tooltip = tooltip }
    label.style.font = "default-bold"
    label.style.font_color = color
    return frame
end

local function used_card(parent, record)
    local where = widgets.planet_label(record.surface)
    local tooltip = { "", "Used on ", where, record.by and (" by " .. record.by) or "", "." }
    local frame = card(parent, "utility/not_available", "Used", USED_COLOR, tooltip)
    local planet = frame.add{ type = "label", caption = where, tooltip = tooltip }
    planet.style.font = "default-small"
    planet.style.font_color = USED_COLOR
end

--- The cards for the team, or a line saying the server gives none.
function M.draw(parent, force_name)
    local allowance = rescue.allowance()
    if allowance == 0 then
        widgets.label(parent, "This server gives teams no rescues.")
        return
    end
    local spent = rescue.spent(force_name)
    local used = math.min(#spent, allowance)
    local cards = parent.add{ type = "table", column_count = math.min(COLUMNS, allowance) }
    cards.style.horizontal_spacing = GAP
    cards.style.vertical_spacing = GAP
    for _ = 1, allowance - used do card(cards, "item/bnm-roboport", "Ready", READY_COLOR, READY_TIP) end
    for i = #spent - used + 1, #spent do used_card(cards, spent[i]) end
end

return M
