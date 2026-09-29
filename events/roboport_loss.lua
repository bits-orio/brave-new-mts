-- events/roboport_loss.lua
-- The bnm-roboport is the heart of each base and can never be removed by the
-- team (it's non-minable). But it CAN be destroyed by enemies:
--   * an OUTPOST's roboport: that outpost is lost (starter_base.lose_outpost),
--     the rest of the team plays on, and another Character Clone shipped to a
--     platform above the planet re-founds it;
--   * the HOME (first) base's roboport, or one BNM has no record of: the team
--     has lost. Announce the elimination and disband the team via the mts-v1
--     disband_team API (members back to the pen, slot freed, surfaces wiped).
--
-- Surface deletion during disband destroys the other roboports without firing
-- on_entity_died, so there's no re-trigger / double-disband.

local starter_base = require("scripts.starter_base")

local M = {}

local function planet_label(surface)
    return surface.planet and surface.planet.prototype.localised_name or surface.name
end

local function team_name(force_name)
    local info = remote.call("mts-v1", "get_team_info", force_name)
    return (info and info.display_name) or force_name
end

local function lose_outpost(force, surface)
    starter_base.lose_outpost(surface.name)
    log("[brave-new-mts] " .. force.name .. " lost its outpost on " .. surface.name)
    force.print({ "", "[Brave New MTS] ", team_name(force.name), " lost its ",
        planet_label(surface), " outpost. Your other bases are safe: ship another ",
        "[item=bnm-character-clone] to a platform above the planet to re-found it." })
end

local function eliminate(force_name)
    game.print("[Brave New MTS] " .. team_name(force_name)
        .. " lost their home roboport, and the team has been eliminated!")
    if remote.interfaces["mts-v1"].disband_team then
        remote.call("mts-v1", "disband_team", force_name)
    end
end

local function on_roboport_died(event)
    local e = event.entity
    if not (e and e.valid and e.name == "bnm-roboport") then return end

    local fn = e.force and e.force.name
    if not (fn and fn:match("^team%-%d+$")) then return end
    if not remote.interfaces["mts-v1"] then return end

    local base = starter_base.base_for(e.surface.name)
    if base and base.outpost and base.force == fn then
        lose_outpost(e.force, e.surface)
    else
        eliminate(fn)
    end
end

function M.register()
    -- Filter so the handler only fires for our roboport.
    script.on_event(defines.events.on_entity_died, on_roboport_died,
        { { filter = "name", name = "bnm-roboport" } })
end

return M
