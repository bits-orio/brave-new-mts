-- events/player_lifecycle.lua
-- Re-assert parking + remote view on the lifecycle events (the last surface the
-- player viewed, else their home surface), and release the parked slot when a
-- player really leaves their team. The primary parking trigger is arrival on a
-- team surface (events/player_surface.lua); these cover reconnects, respawns
-- and the return from spectating a rival team. A player disconnecting has the
-- spot they were looking at remembered, so the reconnect's park returns there.
--
-- Spectating is a force hop: MTS moves the player to the 'spectator' force and
-- back again, so the team is judged by mts-v1 get_effective_force, never by
-- player.force. On the way back MTS restores the camera AFTER the force change
-- (onto the pen cell, for a parked player), so the re-park waits one tick, in a
-- storage queue (storage.bnm_repark: player index -> due tick) drained by an
-- on_tick handler that is attached exactly while the queue is non-empty. Every
-- write to the queue goes through set_repark, which re-runs attach_tick, so the
-- server's handlers always match what register() derives from storage in a
-- joining client's on_load.
--
-- A player entering the game (created or joined) also gets the test-commands
-- warning when that setting is on (scripts/test_mode.lua).

local remote_player = require("scripts.remote_player")
local test_mode     = require("scripts.test_mode")

local M = {}

local on_tick_repark  -- forward declaration: attach_tick and the handler use each other

--- Attach the on_tick handler exactly while re-parks are pending. Reads storage
--- only, so it is safe in on_load and identical on every peer.
local function attach_tick()
    local pending = storage.bnm_repark ~= nil and next(storage.bnm_repark) ~= nil
    script.on_event(defines.events.on_tick, pending and on_tick_repark or nil)
end

--- The only writer of the queue: set (or, with nil, clear) a player's due
--- tick. An emptied queue becomes nil, never {}, and on_tick follows it.
local function set_repark(player_index, due_tick)
    local queue = storage.bnm_repark or {}
    queue[player_index] = due_tick
    storage.bnm_repark = next(queue) ~= nil and queue or nil
    attach_tick()
end

on_tick_repark = function(event)
    local due = {}
    for index, at in pairs(storage.bnm_repark or {}) do
        if event.tick >= at then due[#due + 1] = index end
    end
    for _, index in ipairs(due) do
        set_repark(index, nil)
        remote_player.repark_if_away(game.get_player(index))
    end
    attach_tick()
end

local function on_force_changed(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    -- Left the team for real (MTS moves them off the team force): free the
    -- parked slot. A spectate hop keeps the effective force, so it stays parked.
    if not remote_player.on_team(player) then
        remote_player.unpark(player)
        set_repark(player.index, nil)
        return
    end

    -- Back from spectating: re-centre on the team's ground next tick. A pen
    -- player joining a team also arrives from 'spectator', but is not parked yet.
    local old = event.force
    if old and old.valid and old.name == "spectator"
            and player.force.name == remote_player.effective_force(player)
            and remote_player.is_parked(player) then
        set_repark(player.index, event.tick + 1)
    end
end

function M.register()
    local function reassert(event)
        remote_player.park(game.get_player(event.player_index))
    end
    local function entered(event)
        reassert(event)
        test_mode.refresh_player(game.get_player(event.player_index))
    end

    script.on_event(defines.events.on_player_created,     entered)
    script.on_event(defines.events.on_player_joined_game, entered)
    script.on_event(defines.events.on_player_respawned,   reassert)
    script.on_event(defines.events.on_player_changed_force, on_force_changed)
    script.on_event(defines.events.on_pre_player_left_game, function(event)
        remote_player.remember_view_spot(game.get_player(event.player_index))
    end)
    attach_tick()
end

return M
