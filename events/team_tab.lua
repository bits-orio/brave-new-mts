-- events/team_tab.lua
-- Registers a "Brave New MTS" tab in MTS's Team Settings panel (via the
-- mts-v1 register_team_tab API) and fills it, one section per concern in
-- scripts/team_tab/:
--   unlock_section.lua   the soft-lock warning and the one-time power-core unlock
--   rescue_section.lua   rescues for a base whose roboport ran out of power
--   delete_section.lua   deleting one of the team's planets, to found it again
-- Every button acts for the team leader only; other members see the state and
-- a note saying so.
--
-- A section has build(player, parent, opts) and on_click(player, element),
-- which returns nil for an element that is not its own, false when it changed
-- the tab in place, or true plus build options to rebuild the tab.

local mts_events = require("scripts.mts_events")
local widgets    = require("scripts.team_tab.widgets")

local SECTIONS = {
    require("scripts.team_tab.unlock_section"),
    require("scripts.team_tab.rescue_section"),
    require("scripts.team_tab.delete_section"),
}

local M = {}

local TAB_NAME = "brave-new-mts"
local ROOT     = widgets.PREFIX .. "root"

--- Fill the tab content frame for `player`.
local function build_tab(player, element, opts)
    if not (player and player.valid and element and element.valid) then return end
    element.clear()
    local root = element.add{ type = "flow", name = ROOT, direction = "vertical" }
    for _, section in ipairs(SECTIONS) do section.build(player, root, opts or {}) end
    if not widgets.is_leader(player) then
        root.add{ type = "line" }
        widgets.label(root, widgets.LEADER_ONLY_NOTE)
    end
end

--- The tab's root flow holding `el`, or nil for an element outside the tab.
local function root_of(el)
    while el and el.name ~= ROOT do el = el.parent end
    return el
end

--- Called from control.lua's single on_gui_click dispatcher.
function M.on_gui_click(event)
    local el = event.element
    if not (el and el.valid and el.name:sub(1, #widgets.PREFIX) == widgets.PREFIX) then return end
    local root = root_of(el)
    local player = game.get_player(event.player_index)
    if not (root and player and player.valid) then return end
    local frame = root.parent  -- the tab content frame MTS gave us
    for _, section in ipairs(SECTIONS) do
        local rebuild, opts = section.on_click(player, el)
        if rebuild ~= nil then
            if rebuild then build_tab(player, frame, opts) end
            return
        end
    end
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
