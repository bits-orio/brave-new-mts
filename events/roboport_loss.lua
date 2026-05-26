-- events/roboport_loss.lua
-- The bnm-roboport is the heart of a team's base and can never be removed by
-- the team (it's non-minable). But it CAN be destroyed by enemies -- and if it
-- is, the team has lost: announce the elimination and disband the team via the
-- mts-v1 disband_team API (members back to the pen, slot freed, surfaces wiped).
--
-- Surface deletion during disband destroys the other roboports without firing
-- on_entity_died, so there's no re-trigger / double-disband.

local M = {}

local function on_roboport_died(event)
    local e = event.entity
    if not (e and e.valid and e.name == "bnm-roboport") then return end

    local fn = e.force and e.force.name
    if not (fn and fn:match("^team%-%d+$")) then return end
    if not remote.interfaces["mts-v1"] then return end

    local info = remote.call("mts-v1", "get_team_info", fn)
    local name = (info and info.display_name) or fn
    game.print("[Brave New MTS] " .. name
        .. " lost their roboport — the team has been eliminated!")

    if remote.interfaces["mts-v1"].disband_team then
        remote.call("mts-v1", "disband_team", fn)
    end
end

function M.register()
    -- Filter so the handler only fires for our roboport.
    script.on_event(defines.events.on_entity_died, on_roboport_died,
        { { filter = "name", name = "bnm-roboport" } })
end

return M
