-- Brave New MTS - control.lua  (parked-character-pen branch)
-- Author: bits-orio
-- License: MIT
--
-- A remote-only experience layered on top of Multi-Team Support. PURE CONSUMER
-- of the public `mts-v1` interface -- never edits MTS source. Responsibilities:
--   1. Park each spawned team player's character in their team's walled cell in
--      the landing pen, and put the player in remote view of their team surface
--      (events/player_surface.lua, events/player_lifecycle.lua,
--      scripts/remote_player.lua, scripts/pen_cells.lua). The body never touches
--      the team surface -- so no charting, no collisions, and placement is
--      naturally ghosts that robots build.
--   2. Seed a self-running starter base on each team surface
--      (events/player_surface.lua + scripts/starter_base.lua).
--   3. Block hand-craft / mining / item transfer via permissions
--      (scripts/permissions.lua).

local permissions = require("scripts.permissions")

local ev_player_lifecycle = require("events.player_lifecycle")
local ev_player_surface   = require("events.player_surface")
local ev_team_tab         = require("events.team_tab")
local ev_roboport_loss    = require("events.roboport_loss")
local ev_platform_hub     = require("events.platform_hub")
local ev_starter_items    = require("events.starter_items")
local ev_team_cleanup     = require("events.team_cleanup")
local ev_team_rename      = require("events.team_rename")

local function init_events()
    ev_player_lifecycle.register()
    ev_player_surface.register()
    ev_team_tab.register()
    ev_roboport_loss.register()
    ev_platform_hub.register()
    ev_starter_items.register()
    ev_team_cleanup.register()
    ev_team_rename.register()
    -- Single on_gui_click handler (Factorio allows only one) dispatched to every
    -- module that needs clicks -- registering it per module would clobber.
    script.on_event(defines.events.on_gui_click, function(event)
        ev_team_tab.on_gui_click(event)
        ev_platform_hub.on_gui_click(event)
    end)
end

local function init_storage()
    storage.bases_placed = storage.bases_placed or {}  -- surface name -> base placed
    storage.bnm_base     = storage.bnm_base     or {}  -- surface name -> { force, roboport, protected, unlocked }
    storage.park_index   = storage.park_index   or {}  -- force -> player_index -> slot
    storage.home_surface = storage.home_surface or {}  -- player_index -> team surface name
    -- storage.bnm_tab_event_id / bnm_hub_event_id: cached mts-v1 custom event ids
    -- (set in on_init/on_configuration_changed via the modules' setup()).
end

-- ─── Lifecycle ─────────────────────────────────────────────────────────

script.on_init(function()
    log("[brave-new-mts] on_init fired")
    init_storage()
    permissions.apply()
    init_events()
    -- remote.call is legal here (all interfaces are registered before on_init):
    -- register our MTS UI extensions and cache their custom event ids.
    ev_team_tab.setup()
    ev_platform_hub.setup()
    ev_starter_items.setup()
    ev_team_cleanup.setup()
    ev_team_rename.setup()
end)

script.on_load(function()
    -- on_load must NOT write to storage and must NOT remote.call. Event
    -- registrations don't persist, so re-register them -- deterministically,
    -- using the event id cached in storage during on_init (see team_tab.lua).
    init_events()
end)

script.on_configuration_changed(function()
    log("[brave-new-mts] on_configuration_changed fired")
    init_storage()
    permissions.apply()
    init_events()
    -- Re-register the MTS UI extensions and refresh their cached event ids (they
    -- can change if the mod set changed, which is exactly when this fires).
    ev_team_tab.setup()
    ev_platform_hub.setup()
    ev_starter_items.setup()
    ev_team_cleanup.setup()
    ev_team_rename.setup()
end)
