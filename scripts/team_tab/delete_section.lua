-- scripts/team_tab/delete_section.lua
-- The team tab's planet deletion (scripts/planet_delete.lua): every planet the
-- team may delete, and for the team leader a Delete button that asks once
-- more, in its own row, before the planet goes.

local planet_delete = require("scripts.planet_delete")
local chat          = require("scripts.chat")
local widgets       = require("scripts.team_tab.widgets")

local M = {}

local DELETE, CONFIRM, CANCEL = "delete", "delete_confirm", "delete_cancel"

local ABOUT = "Deleting a planet removes your team's copy of it and everything on it: "
    .. "buildings, items and robots. To build there again, ship a Character Clone to a "
    .. "platform above it and press Establish base. Your home planet can't be deleted."

local function planet_row(parent, surface_name, leader)
    local row = widgets.row(parent)
    widgets.label(row, widgets.planet_label(surface_name), widgets.ROW_LABEL_WIDTH)
    if leader then
        widgets.surface_button(row, DELETE, surface_name, "Delete...", "red_button",
            "Asks once more before anything is deleted.")
    end
end

--- The heading, then each planet the team may delete. opts.skip names one
--- deleted this tick, which still exists until the tick ends.
function M.build(player, parent, opts)
    widgets.heading(parent, "Delete a planet")
    widgets.label(parent, ABOUT)
    local leader, shown = widgets.is_leader(player), 0
    for _, surface_name in ipairs(planet_delete.deletable(player.force.name)) do
        if surface_name ~= opts.skip then
            planet_row(parent, surface_name, leader)
            shown = shown + 1
        end
    end
    if shown == 0 then widgets.label(parent, "Your team has no other planets.") end
end

--- Turn a planet's row into the question, with Delete and Cancel.
local function ask(row, surface_name)
    row.clear()
    local label = widgets.planet_label(surface_name)
    widgets.label(row, { "", "Delete ", label, " and everything on it? This can't be undone." },
        widgets.ROW_LABEL_WIDTH)
    widgets.surface_button(row, CONFIRM, surface_name, { "", "Delete ", label }, "red_button")
    widgets.surface_button(row, CANCEL, surface_name, "Cancel")
end

local function announce(player, surface_name)
    player.force.print({ "", chat.PREFIX, player.name, " deleted your team's ",
        widgets.planet_label(surface_name), ". To build there again, ship a Character Clone to a "
        .. "platform above it and press Establish base." })
end

--- Delete the planet, for the leader. Returns the tab's rebuild options.
local function confirm(player, surface_name)
    local ok, why = planet_delete.delete(player.force.name, surface_name)
    if not ok then
        player.print(chat.PREFIX .. "Can't delete that planet: " .. why .. ".")
        return {}
    end
    announce(player, surface_name)
    return { skip = surface_name }
end

--- nil for another section's element; false when the row was changed in
--- place (Delete...); true, opts to rebuild the tab (Cancel, Delete).
function M.on_click(player, el)
    local name = el.name:sub(#widgets.PREFIX + 1)
    if name ~= DELETE and name ~= CONFIRM and name ~= CANCEL then return nil end
    if name == CANCEL or not widgets.is_leader(player) then return true end
    if name == DELETE then
        ask(el.parent, el.tags.surface)
        return false
    end
    return true, confirm(player, el.tags.surface)
end

return M
