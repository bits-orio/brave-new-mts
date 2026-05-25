-- Brave New MTS - control.lua
-- Author: bits-orio
-- License: MIT
--
-- A remote-only, character-free experience layered on top of Multi-Team
-- Support. This mod is a PURE CONSUMER of the public `mts-v1` interface --
-- it never edits MTS source. Two responsibilities:
--   1. Remove every player's character and keep them in remote view
--      (events/player_lifecycle.lua).
--   2. Seed a self-running starter base on each team surface the team
--      reaches, so construction robots can build from real stock
--      (events/player_surface.lua + scripts/starter_base.lua).

local permissions         = require("scripts.permissions")

local ev_player_lifecycle  = require("events.player_lifecycle")
local ev_player_surface    = require("events.player_surface")
local ev_player_movement   = require("events.player_movement")
local ev_player_build      = require("events.player_build")

local function init_events()
    ev_player_lifecycle.register()
    ev_player_surface.register()
    ev_player_movement.register()
    ev_player_build.register()
end

-- ─── Lifecycle ─────────────────────────────────────────────────────────

script.on_init(function()
    log("[brave-new-mts] on_init fired")
    -- surface name -> true once a starter base has been placed there.
    storage.bases_placed = {}
    permissions.apply()
    init_events()
end)

script.on_load(function()
    -- on_load must NOT write to storage. Event registrations don't persist
    -- across save/load, so re-establish them every session.
    init_events()
end)

script.on_configuration_changed(function()
    log("[brave-new-mts] on_configuration_changed fired")
    storage.bases_placed = storage.bases_placed or {}
    permissions.apply()
    init_events()
end)
