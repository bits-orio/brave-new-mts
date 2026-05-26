-- events/team_tab.lua
-- Registers a "Brave New MTS" tab in MTS's Team Settings panel (via the
-- mts-v1 register_team_tab API) and fills it with a soft-lock warning plus a
-- one-time, leader-only "I know what I am doing" button that makes the starter
-- base minable (except the permanent roboport).

local starter_base = require("scripts.starter_base")

local M = {}

local TAB_NAME      = "brave-new-mts"
local UNLOCK_BUTTON = "bnm_unlock_minable"

local WARNING =
    "Your starter base can't be mined or deconstructed by default, so you "
    .. "can't accidentally tear down your own power and strand your team.\n\n"
    .. "Unlocking lets you mine / deconstruct the starter base (power, belts, "
    .. "chests, walls, ...) to redesign your spawn. The central roboport can "
    .. "NEVER be removed.\n\n"
    .. "[color=1,0.5,0.2]Warning:[/color] if you remove your power or bots "
    .. "before replacements are running, your team can be soft-locked with no "
    .. "way to recover. This is one-way."

local function is_leader(player)
    if not remote.interfaces["mts-v1"] then return false end
    local info = remote.call("mts-v1", "get_team_info", player.force.name)
    return info ~= nil and info.leader_player_index == player.index
end

--- Fill the tab content frame for `player`.
local function build_tab(player, element)
    if not (player and player.valid and element and element.valid) then return end
    element.clear()
    element.style.vertical_spacing = 8

    local warn = element.add{ type = "label", caption = WARNING }
    warn.style.single_line  = false
    warn.style.maximal_width = 360

    if starter_base.is_unlocked(player.force.name) then
        local ok = element.add{
            type    = "label",
            caption = "[color=0,1,0]Your starter base is now mineable "
                .. "(except the central roboport).[/color]",
        }
        ok.style.single_line  = false
        ok.style.maximal_width = 360
        return
    end

    element.add{ type = "line" }

    if is_leader(player) then
        element.add{
            type    = "button",
            name    = UNLOCK_BUTTON,
            caption = "I know what I am doing",
            tooltip = "Make the starter base mineable (except the roboport). One-way.",
        }
    else
        local note = element.add{
            type    = "label",
            caption = "[color=1,0.65,0]Only your team leader can change this.[/color]",
        }
        note.style.single_line  = false
        note.style.maximal_width = 360
    end
end

local function on_gui_click(event)
    local el = event.element
    if not (el and el.valid and el.name == UNLOCK_BUTTON) then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) or not is_leader(player) then return end

    starter_base.unlock_minable(player.force.name)
    player.force.print("Starter base unlocked: it can now be mined / deconstructed "
        .. "(except the central roboport). Be careful not to soft-lock the team.")
    build_tab(player, el.parent)  -- el.parent is the tab content frame
end

function M.register()
    -- remote.call is illegal in on_load / the main chunk, so defer the tab
    -- registration and event-id lookup to a one-shot tick (re-armed each session).
    script.on_nth_tick(1, function()
        script.on_nth_tick(1, nil)
        local iface = remote.interfaces["mts-v1"]
        if not (iface and iface.register_team_tab) then return end
        remote.call("mts-v1", "register_team_tab",
            { name = TAB_NAME, caption = "Brave New MTS", order = "z" })
        local id = remote.call("mts-v1", "get_event_id", "on_team_tab_built")
        if id then
            script.on_event(id, function(e)
                if e.tab_name == TAB_NAME then
                    build_tab(game.get_player(e.player_index), e.element)
                end
            end)
        end
    end)

    script.on_event(defines.events.on_gui_click, on_gui_click)
end

return M
