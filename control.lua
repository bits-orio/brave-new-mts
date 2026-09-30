-- Brave New MTS - control.lua  (parked-character-pen branch)
-- Author: bits-orio
-- License: MIT
--
-- A remote-only experience layered on top of Multi-Team Support. PURE CONSUMER
-- of the public `mts-v1` interface -- never edits MTS source. Responsibilities:
--   1. Park each spawned team player's character in their team's walled cell in
--      the landing pen, and put the player in remote view of their team surface
--      (events/player_surface.lua, events/player_lifecycle.lua,
--      scripts/remote_player.lua, scripts/remote_view.lua, scripts/pen_cells.lua).
--      The body never touches the team surface -- so no charting, no
--      collisions, and placement is naturally ghosts that robots build.
--   2. Seed a self-running home base on each team's first surface
--      (events/player_surface.lua + scripts/starter_base.lua), and an outpost
--      wherever the team ships a Character Clone (events/platform_hub.lua).
--      Losing the home roboport eliminates the team; losing an outpost's
--      roboport loses only that outpost (events/roboport_loss.lua).
--   3. Block hand-craft / mining / item transfer via permissions
--      (scripts/permissions.lua).
--   4. Admin recovery commands (scripts/admin_commands.lua).

local permissions    = require("scripts.permissions")
local starter_base   = require("scripts.starter_base")
local remote_player  = require("scripts.remote_player")
local admin_commands = require("scripts.admin_commands")
local test_commands  = require("scripts.test_commands")

local ev_player_lifecycle = require("events.player_lifecycle")
local ev_player_surface   = require("events.player_surface")
local ev_team_tab         = require("events.team_tab")
local ev_roboport_loss    = require("events.roboport_loss")
local ev_platform_hub     = require("events.platform_hub")
local ev_starter_items    = require("events.starter_items")
local ev_team_cleanup     = require("events.team_cleanup")
local ev_team_rename      = require("events.team_rename")
local ev_surface_deleted  = require("events.surface_deleted")

-- Commands are added once per Lua state, here in the main chunk: init_events
-- runs in on_load AND on_configuration_changed, and a second add_command for
-- the same name is an error.
admin_commands.register()
test_commands.register()

local function init_events()
    ev_player_lifecycle.register()
    ev_player_surface.register()
    ev_team_tab.register()
    ev_roboport_loss.register()
    ev_platform_hub.register()
    ev_starter_items.register()
    ev_team_cleanup.register()
    ev_team_rename.register()
    ev_surface_deleted.register()
    -- Single on_gui_click handler (Factorio allows only one) dispatched to every
    -- module that needs clicks -- registering it per module would clobber.
    script.on_event(defines.events.on_gui_click, function(event)
        ev_team_tab.on_gui_click(event)
        ev_platform_hub.on_gui_click(event)
    end)
end

-- Storage keys where earlier builds cached mts-v1 event ids.
local STALE_EVENT_ID_KEYS = {
    "bnm_tab_event_id", "bnm_hub_event_id", "bnm_starter_items_event_id",
    "bnm_team_released_event_id", "bnm_team_renamed_event_id",
}

local function init_storage()
    storage.bases_placed  = storage.bases_placed  or {}  -- surface name -> base placed
    storage.bnm_base      = storage.bnm_base      or {}  -- surface name -> { force, roboport, home/outpost, ... }
    storage.park_index    = storage.park_index    or {}  -- force -> player_index -> slot
    storage.home_surface  = storage.home_surface  or {}  -- player_index -> team surface first arrived on
    storage.last_view     = storage.last_view     or {}  -- player_index -> own-team surface last viewed
    storage.last_view_pos = storage.last_view_pos or {}  -- player_index -> { surface, x, y } viewed on leaving
    storage.emptied_body  = storage.emptied_body  or {}  -- character unit_number -> player_index (emptied once)
    -- storage.bnm_repark: player_index -> tick, re-parks pending after a spectate
    -- (nil when empty; see events/player_lifecycle.lua).
    -- mts-v1 event ids are never stored: they shift with the mod set
    -- (scripts/mts_events.lua). Earlier versions cached them; drop those keys.
    for _, key in ipairs(STALE_EVENT_ID_KEYS) do storage[key] = nil end
end

-- Registrations MTS keeps in its own storage: on_init / on_configuration_changed
-- only. The matching event handlers are attached by init_events().
local function setup_mts_extensions()
    ev_team_tab.setup()
    ev_platform_hub.setup()
    ev_starter_items.setup()
end

-- ─── Lifecycle ─────────────────────────────────────────────────────────

script.on_init(function()
    log("[brave-new-mts] on_init fired")
    init_storage()
    permissions.apply()
    init_events()
    setup_mts_extensions()
end)

script.on_load(function()
    -- on_load must NOT write to storage (or to MTS's, so no setup here). Event
    -- registrations don't persist, so re-register them deterministically: from
    -- the queues in storage (player_lifecycle.lua) and this session's mts-v1
    -- event ids, a pure lookup that is legal here (scripts/mts_events.lua).
    init_events()
end)

script.on_configuration_changed(function()
    log("[brave-new-mts] on_configuration_changed fired")
    init_storage()
    permissions.apply()
    init_events()
    setup_mts_extensions()
    -- Bring older saves up to date: base records (home / outpost, chest lists),
    -- and bodies already parked, so the first reconnect after the update does
    -- not empty them. Both are idempotent.
    starter_base.migrate()
    remote_player.migrate()
end)
