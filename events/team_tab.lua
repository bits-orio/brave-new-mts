-- events/team_tab.lua
-- Registers a "Brave New MTS" tab in MTS's Team Settings panel (via the
-- mts-v1 register_team_tab API) and fills it with a soft-lock warning plus a
-- one-time, leader-only "I know what I am doing" button that makes the locked
-- power core of every base minable (except the permanent roboports and the
-- planet-tuned copies, which no item can place again).

local starter_base = require("scripts.starter_base")
local mts_events   = require("scripts.mts_events")

local M = {}

local TAB_NAME      = "brave-new-mts"
local UNLOCK_BUTTON = "bnm_unlock_minable"

-- Mirrors the power core (scripts/base/power_core.lua): solar panels,
-- accumulators, substations, lamps, lightning collectors (Fulgora) and the
-- display panel, plus the planet-tuned copies (is_tuned), which stay locked
-- even after the unlock.
local WARNING =
    "You can already mine and redesign most of your bases. The power core "
    .. "stays locked: solar panels, accumulators, substations, lamps, lightning "
    .. "collectors and the power warning sign, so you can't accidentally kill "
    .. "your own power and strand your team. The green-tinted, planet-tuned "
    .. "panels, accumulators, radar and inserter stay locked even after you "
    .. "unlock, because nothing can ever place one again.\n\n"
    .. "Unlocking lets you mine / deconstruct that power core too, on every base "
    .. "your team has or founds later, to rebuild it your way. The central "
    .. "roboports can NEVER be removed.\n\n"
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
            caption = "[color=0,1,0]Your power core and warning sign are now "
                .. "mineable too (except the central roboports and the "
                .. "planet-tuned buildings).[/color]",
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
            tooltip = "Make the locked power core and warning sign mineable on "
                .. "every base. The roboports and the green-tinted, planet-tuned "
                .. "buildings stay locked, because nothing can place one again. "
                .. "One-way.",
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

function M.on_gui_click(event)
    local el = event.element
    if not (el and el.valid and el.name == UNLOCK_BUTTON) then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) or not is_leader(player) then return end

    starter_base.unlock_minable(player.force.name)
    player.force.print("Power core unlocked on every base: it can now be mined / "
        .. "deconstructed (except the central roboports and the planet-tuned "
        .. "buildings). Be careful not to soft-lock the team.")
    build_tab(player, el.parent)  -- el.parent is the tab content frame
end

local function on_tab_built(e)
    if e.tab_name == TAB_NAME then
        build_tab(game.get_player(e.player_index), e.element)
    end
end

--- Register handlers DETERMINISTICALLY. Called from on_init, on_load AND
--- on_configuration_changed, so it must be identical on every peer. The
--- on_team_tab_built id is looked up this session (scripts/mts_events.lua),
--- never cached: a cached id goes stale when the mod set changes.
--- Registering lazily (e.g. on a one-shot tick) is NOT multiplayer-safe: a client
--- joining mid-game hasn't run that tick yet, so its handler set differs from the
--- long-running server's and the join is rejected ("event handlers not identical").
-- on_gui_click is dispatched centrally from control.lua (only one handler may
-- be registered for it), so M.register only wires the custom event handler.
function M.register()
    local id = mts_events.id("on_team_tab_built")
    if id then script.on_event(id, on_tab_built) end
end

--- Register our tab with MTS. It persists the spec in its own storage, so this
--- runs in on_init / on_configuration_changed only, never on_load. `mod` lets
--- MTS drop the tab if BNM is removed from the save.
function M.setup()
    local iface = remote.interfaces["mts-v1"]
    if iface and iface.register_team_tab then
        remote.call("mts-v1", "register_team_tab",
            { name = TAB_NAME, caption = "Brave New MTS", order = "z", mod = script.mod_name })
    end
end

return M
