-- events/team_tab.lua
-- Registers a "Brave New MTS" tab in MTS's Team Settings panel (via the
-- mts-v1 register_team_tab API) and fills it with a soft-lock warning plus a
-- one-time, leader-only "I know what I am doing" button that makes the locked
-- power core of every base minable (except the permanent roboports and the
-- planet-tuned copies, which no item can place again).

local starter_base = require("scripts.starter_base")
local mts_events   = require("scripts.mts_events")
local teams        = require("scripts.teams")
local chat         = require("scripts.chat")

local M = {}

local TAB_NAME      = "brave-new-mts"
local UNLOCK_BUTTON = "bnm_unlock_minable"

-- Mirrors the power core (scripts/base/power_core.lua): solar panels,
-- accumulators, substations, lamps, lightning collectors (Fulgora) and the
-- display panel, plus the planet-tuned copies (is_tuned), which stay locked
-- even after the unlock. The sign is part of the core, so every string says
-- so the same way (CORE). STAYS_LOCKED is what the unlock never frees: the
-- roboport (scripts/base/builder.lua) and the tuned copies. README.md ("The
-- base is permanent") and docs/portal.md (Features) repeat these rules and
-- cannot be built from here: change them together.
local CORE         = "power core (warning sign included)"
local STAYS_LOCKED = "The central roboports and the green-tinted, planet-tuned "
    .. "buildings stay locked, because nothing can place one again."

local WARNING =
    "You can already mine and redesign most of your bases. The power core "
    .. "stays locked: solar panels, accumulators, substations, lamps, lightning "
    .. "collectors and the power warning sign, so you can't accidentally kill "
    .. "your own power and strand your team.\n\n"
    .. "Unlocking lets you mine / deconstruct that power core too, on every base "
    .. "your team has or founds later, to rebuild it your way. " .. STAYS_LOCKED
    .. " The tuned buildings are the panels, accumulators, radar and inserter "
    .. "made for their planet.\n\n"
    .. "[color=1,0.5,0.2]Warning:[/color] if you remove your power before "
    .. "replacements are running, your team can be soft-locked with no way to "
    .. "recover. This is one-way."

local UNLOCKED_NOTE = "[color=0,1,0]Your " .. CORE .. " is now mineable on every "
    .. "base. " .. STAYS_LOCKED .. "[/color]"

local UNLOCKED_PRINT = chat.PREFIX .. "Power core unlocked on every base: it can "
    .. "now be mined / deconstructed. " .. STAYS_LOCKED
    .. " Be careful not to soft-lock the team."

local LEADER_ONLY_NOTE = "[color=1,0.65,0]Only your team leader can change this.[/color]"

local UNLOCK_TOOLTIP = "Make the locked " .. CORE .. " mineable on every base. "
    .. STAYS_LOCKED .. " One-way."

local LABEL_WIDTH = 360

local function is_leader(player)
    local info = teams.info(player.force.name)
    return info ~= nil and info.leader_player_index == player.index
end

--- A label that wraps at the tab's width.
local function wrapped_label(parent, caption)
    local label = parent.add{ type = "label", caption = caption }
    label.style.single_line   = false
    label.style.maximal_width = LABEL_WIDTH
    return label
end

--- The unlock button for the leader, a note for anyone else. The button must
--- stay a DIRECT child of `element`: on_gui_click rebuilds through el.parent.
local function build_unlock_control(player, element)
    element.add{ type = "line" }
    if not is_leader(player) then
        wrapped_label(element, LEADER_ONLY_NOTE)
        return
    end
    element.add{ type = "button", name = UNLOCK_BUTTON,
        caption = "I know what I am doing", tooltip = UNLOCK_TOOLTIP }
end

--- Fill the tab content frame for `player`.
local function build_tab(player, element)
    if not (player and player.valid and element and element.valid) then return end
    element.clear()
    local warn = wrapped_label(element, WARNING)
    warn.style.bottom_margin = 8  -- space before the note or the line below
    if starter_base.is_unlocked(player.force.name) then
        wrapped_label(element, UNLOCKED_NOTE)
        return
    end
    build_unlock_control(player, element)
end

function M.on_gui_click(event)
    local el = event.element
    if not (el and el.valid and el.name == UNLOCK_BUTTON) then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) or not is_leader(player) then return end

    starter_base.unlock_minable(player.force.name)
    player.force.print(UNLOCKED_PRINT)
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
