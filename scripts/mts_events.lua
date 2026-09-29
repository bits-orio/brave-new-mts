-- scripts/mts_events.lua
-- This session's ids for mts-v1 custom events.
--
-- MTS generates its event ids in its main chunk (script.generate_event_name),
-- so they are fixed for a session but shift whenever the mod set or the game
-- version changes: adding a mod that loads before MTS moves every one of them.
-- An id must therefore never be cached in storage. A cached id makes the
-- server register handlers a joining client does not (the join is refused:
-- "event handlers are not identical"), and an id past the new last one makes
-- on_load throw, so the save will not load at all.
--
-- get_event_id is a pure lookup into that main-chunk table: the same answer on
-- every peer, and legal in on_load (only a main chunk may not remote.call).
-- Every register() looks its id up here instead.

local M = {}

--- The id of mts-v1 custom event `name` this session, or nil without MTS.
function M.id(name)
    local iface = remote.interfaces["mts-v1"]
    if not (iface and iface.get_event_id) then return nil end
    return remote.call("mts-v1", "get_event_id", name)
end

return M
