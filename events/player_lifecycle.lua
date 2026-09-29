-- events/player_lifecycle.lua
-- Re-assert parking + remote view on the lifecycle events (the last surface the
-- player viewed, else their home surface), and release the parked slot when a
-- player really leaves their team. The primary parking trigger is arrival on a
-- team surface (events/player_surface.lua); these cover reconnects, respawns
-- and the return from spectating a rival team.
--
-- Spectating is a force hop: MTS moves the player to the 'spectator' force and
-- back again, so the team is judged by mts-v1 get_effective_force, never by
-- player.force. On the way back MTS restores the camera AFTER the force change
-- (onto the pen cell, for a parked player), so the re-park waits one tick, in a
-- storage queue (storage.bnm_repark: player index -> due tick) drained by an
-- on_tick handler that is attached only while the queue is non-empty. register()
-- re-attaches it from storage, so on_load stays deterministic.

local remote_player = require("scripts.remote_player")

local M = {}

local on_tick_repark  -- forward declaration: attach_tick and the handler use each other

--- Attach the on_tick handler exactly while re-parks are pending. Reads storage
--- only, so it is safe in on_load and identical on every peer.
local function attach_tick()
    local pending = storage.bnm_repark ~= nil and next(storage.bnm_repark) ~= nil
    script.on_event(defines.events.on_tick, pending and on_tick_repark or nil)
end

local function queue_repark(player_index)
    storage.bnm_repark = storage.bnm_repark or {}
    storage.bnm_repark[player_index] = game.tick + 1
    attach_tick()
end

local function dequeue_repark(player_index)
    if storage.bnm_repark then storage.bnm_repark[player_index] = nil end
end

on_tick_repark = function(event)
    local queue = storage.bnm_repark or {}
    local due = {}
    for index, at in pairs(queue) do
        if event.tick >= at then due[#due + 1] = index end
    end
    for _, index in ipairs(due) do
        queue[index] = nil
        remote_player.repark_if_away(game.get_player(index))
    end
    if not next(queue) then storage.bnm_repark = nil end
    attach_tick()
end

local function on_force_changed(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    -- Left the team for real (MTS moves them off the team force): free the
    -- parked slot. A spectate hop keeps the effective force, so it stays parked.
    if not remote_player.on_team(player) then
        remote_player.unpark(player)
        dequeue_repark(player.index)
        return
    end

    -- Back from spectating: re-centre on the team's ground next tick. A pen
    -- player joining a team also arrives from 'spectator', but is not parked yet.
    local old = event.force
    if old and old.valid and old.name == "spectator"
            and player.force.name == remote_player.effective_force(player)
            and remote_player.is_parked(player) then
        queue_repark(player.index)
    end
end

function M.register()
    local function reassert(event)
        remote_player.park(game.get_player(event.player_index))
    end

    script.on_event(defines.events.on_player_created,     reassert)
    script.on_event(defines.events.on_player_joined_game, reassert)
    script.on_event(defines.events.on_player_respawned,   reassert)
    script.on_event(defines.events.on_player_changed_force, on_force_changed)
    attach_tick()
end

return M
