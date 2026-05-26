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
    "You can already mine and redesign most of your starter base. Only the "
    .. "power core stays locked: solar panels, accumulators, substations, the "
    .. "main power poles and the lights -- so you can't accidentally kill your "
    .. "own power and strand your team.\n\n"
    .. "Unlocking lets you mine / deconstruct that power core too, to rebuild "
    .. "it your way. The central roboport can NEVER be removed.\n\n"
    .. "[color=1,0.5,0.2]Warning:[/color] if you remove your power before "
    .. "replacements are running, your team can be soft-locked with no way to "
    .. "recover. This is one-way."

local function is_leader(player)
    if not remote.interfaces["mts-v1"] then return false end
    local info = remote.call("mts-v1", "get_team_info", player.force.name)
    return info ~= nil and info.leader_player_index == player.index
end

--- Fill the tab content frame for `player`.
local function build_tab(player, element)
    if not (player and player.valid and element and element.valid) then return end
    element.clear()

    local warn = element.add{ type = "label", caption = WARNING }
    warn.style.single_line   = false
    warn.style.maximal_width = 360
    warn.style.bottom_margin = 8

    if starter_base.is_unlocked(player.force.name) then
        local ok = element.add{
            type    = "label",
            caption = "[color=0,1,0]Your power core is now mineable too "
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

local function on_tab_built(e)
    if e.tab_name == TAB_NAME then
        build_tab(game.get_player(e.player_index), e.element)
    end
end

--- Register handlers DETERMINISTICALLY. Called from on_init, on_load AND
--- on_configuration_changed, so it must be identical on every peer and must NOT
--- remote.call (illegal in on_load). The on_team_tab_built event id is read from
--- storage, where M.setup() cached it during on_init / on_configuration_changed.
--- Registering lazily (e.g. on a one-shot tick) is NOT multiplayer-safe: a client
--- joining mid-game hasn't run that tick yet, so its handler set differs from the
--- long-running server's and the join is rejected ("event handlers not identical").
function M.register()
    script.on_event(defines.events.on_gui_click, on_gui_click)
    local id = storage.bnm_tab_event_id
    if id then script.on_event(id, on_tab_built) end
end

--- Side-effecting setup that needs remote.call: register our tab with MTS (it
--- persists the spec in its own storage) and cache the on_team_tab_built event
--- id. Safe only in on_init / on_configuration_changed -- never on_load. Re-runs
--- M.register() so the freshly-cached id is attached this session too.
function M.setup()
    local iface = remote.interfaces["mts-v1"]
    if not iface then return end
    if iface.register_team_tab then
        remote.call("mts-v1", "register_team_tab",
            { name = TAB_NAME, caption = "Brave New MTS", order = "z" })
    end
    if iface.get_event_id then
        storage.bnm_tab_event_id =
            remote.call("mts-v1", "get_event_id", "on_team_tab_built")
    end
    M.register()
end

return M
