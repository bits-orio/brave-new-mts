-- scripts/test_commands.lua
-- Shortcuts for testing Space Age outposts without launching rockets and
-- flying a platform. They do nothing unless the map setting "Enable test
-- commands" (bnm-test-commands) is on, and they are admin-only like the
-- recovery commands. They grant research and create items, so leave the
-- setting off on a real server. Every use is announced to everyone.
--
--   /bnm-test-orbit <planet> [team-N]   research the way to <planet> and the
--        Character Clone, park a platform above the team's copy of <planet>
--        with one clone aboard (again: one more clone), and, for your own
--        team, view its hub (Establish base acts for the pressing player's
--        force, so a member of another team presses it)
--   /bnm-test-kill-roboport [surface]   kill a base's roboport as an enemy
--        would, to test outpost loss and home loss (default: the surface
--        you are viewing)
--
-- M.register() adds the commands. It must run ONCE per Lua state, from
-- control.lua's main chunk, like scripts/admin_commands.lua.

local cmd_util      = require("scripts.command_util")
local remote_player = require("scripts.remote_player")
local starter_base  = require("scripts.starter_base")
local teams         = require("scripts.teams")

local M = {}

local PREFIX       = cmd_util.PREFIX
local SETTING      = "bnm-test-commands"
local CLONE        = "bnm-character-clone"
local STARTER_PACK = "space-platform-starter-pack"
local PLATFORM     = "BNM test: "

--- True when test commands are switched on; tells the caller how otherwise.
local function enabled(cmd)
    local setting = settings.global[SETTING]
    if setting and setting.value then return true end
    cmd_util.reply(cmd, PREFIX .. "/" .. cmd.name .. " is off. Turn on the map setting "
        .. "\"Enable test commands\" (Settings > Mod settings > Map) first.")
    return false
end

-- ─── /bnm-test-orbit ───────────────────────────────────────────────────

--- Research `name` and everything it depends on, prerequisites first.
--- Returns how many technologies this call researched.
local function research_with_prerequisites(force, name, done)
    local tech = force.technologies[name]
    if not tech or done[name] then return 0 end
    done[name] = true
    local count = 0
    for pre in pairs(tech.prerequisites) do
        count = count + research_with_prerequisites(force, pre, done)
    end
    if tech.researched then return count end
    tech.researched = true
    return count + 1
end

--- Research what a team needs to reach `base` and ship a clone there, and make
--- sure the team's copy of the planet is unlocked (MTS does it on the
--- discovery research; a planet with no discovery tech is unlocked here).
local function unlock_route(force, base, planet)
    local done = {}
    local count = research_with_prerequisites(force, "planet-discovery-" .. base, done)
        + research_with_prerequisites(force, CLONE, done)
    if not force.is_space_location_unlocked(planet.name) then
        force.unlock_space_location(planet.name)
    end
    return count
end

--- The force a test command acts on: the named team, else the caller's own,
--- and only while its MTS slot is claimed. MTS's claim resets a force but
--- keeps its platforms, so a platform made for a free slot would pass, clones
--- and all, to the next team that claims it.
local function target_force(cmd, team)
    if not team then
        local player = cmd_util.caller(cmd)
        team = player and remote_player.effective_force(player)
    end
    local info = teams.is_team_force(team) and teams.info(team)
    return (info and info.is_occupied) and game.forces[team] or nil
end

--- The force's platform called `name`, or nil. One pending deletion (Delete
--- in the GUI) counts as gone: a clone put aboard would vanish with it.
local function live_platform(force, name)
    for _, p in pairs(force.platforms) do
        if p.valid and p.name == name and p.scheduled_for_deletion == 0 then return p end
    end
end

--- The team's test platform, parked above `planet`: created with a starter
--- pack the first time, and brought back if it was flown elsewhere or is in
--- transit, paused as a new one is, so its schedule does not fly it off again.
--- Returns the platform, or nil if the engine refused to make it.
local function test_platform(force, planet, base)
    local name = PLATFORM .. base
    local p = live_platform(force, name)
        or force.create_space_platform{ name = name, planet = planet.name, starter_pack = STARTER_PACK }
    if not p then return nil end
    p.apply_starter_pack()  -- does nothing once applied
    if not (p.space_location and p.space_location.name == planet.name) then
        p.space_location = planet.prototype
        p.paused = true
    end
    return p
end

--- Move the player's remote view onto the hub and open it.
local function view_hub(player, hub)
    player.set_controller{ type = defines.controllers.remote, surface = hub.surface, position = hub.position }
    pcall(function() player.opened = hub end)  -- if it will not open remotely, one click does
end

--- Announce the parked platform, and take the caller to its hub only if it is
--- their own team's. Establish base acts for the pressing player's force, so
--- on another team's hub it is refused, and MTS may make the caller a
--- spectator of that team on the way there: a member of that team presses it.
local function announce(cmd, force, platform, planet, researched)
    local caller = cmd_util.caller(cmd)
    local own = caller ~= nil and remote_player.effective_force(caller) == force.name
    cmd_util.audit(cmd, "(test command) parked " .. force.name .. "'s platform \"" .. platform.name
        .. "\" above " .. planet.name .. " with a Character Clone aboard; researched "
        .. researched .. " technologies. "
        .. (own and "Open the hub and press Establish base."
                or ("A member of " .. force.name .. " can now open its hub and press Establish base.")))
    if own then view_hub(caller, platform.hub) end
end

local function orbit_usage(cmd)
    cmd_util.reply(cmd, PREFIX .. "usage: /bnm-test-orbit <planet> [team-N], "
        .. "for example /bnm-test-orbit vulcanus (planets: vulcanus, fulgora, gleba, aquilo)")
end

local function orbit(cmd)
    if not (cmd_util.authorised(cmd) and enabled(cmd)) then return end
    local base, team = (cmd_util.trimmed(cmd.parameter) or ""):lower():match("^(%S+)%s*(%S*)$")
    if not base then return orbit_usage(cmd) end
    local force = target_force(cmd, team ~= "" and team or nil)
    if not force then
        local why = team ~= "" and (team .. " is not a claimed team") or "no team to act for"
        return cmd_util.reply(cmd, PREFIX .. why .. ": join a team, or name a claimed one, "
            .. "for example /bnm-test-orbit " .. base .. " team-2; a member of that team presses Establish base.")
    end
    local planet = game.planets["mts-" .. base .. "-" .. teams.slot_of(force.name)]
    if not planet then return orbit_usage(cmd) end
    local researched = unlock_route(force, base, planet)
    local platform = test_platform(force, planet, base)
    local hub = platform and platform.hub
    if not (hub and hub.valid) then  -- the research and unlock stand, so announce them
        return cmd_util.audit(cmd, "(test command) researched " .. researched .. " technologies for "
            .. force.name .. " and unlocked " .. planet.name .. ", but could not create a platform above it.")
    end
    hub.get_inventory(defines.inventory.hub_main).insert{ name = CLONE, count = 1 }
    announce(cmd, force, platform, planet, researched)
end

-- ─── /bnm-test-kill-roboport ───────────────────────────────────────────

local function kill_roboport(cmd)
    if not (cmd_util.authorised(cmd) and enabled(cmd)) then return end
    local player = cmd_util.caller(cmd)
    local name = cmd_util.trimmed(cmd.parameter) or (player and player.surface.name)
    local base = name and starter_base.base_for(name)
    if not (base and base.roboport and base.roboport.valid) then
        return cmd_util.reply(cmd, PREFIX .. "no live base roboport on " .. tostring(name)
            .. ". Usage: /bnm-test-kill-roboport [surface name]")
    end
    cmd_util.audit(cmd, "(test command) destroyed the " .. (base.home and "home" or "outpost")
        .. " roboport on " .. name .. ".")
    base.roboport.die()  -- an ordinary death: BNM's roboport-loss handler takes it from here
end

-- ─── Registration ──────────────────────────────────────────────────────

function M.register()
    commands.add_command("bnm-test-orbit",
        "<planet> [team-N] - TEST: park a platform with a clone above a planet (admin, test setting).", orbit)
    commands.add_command("bnm-test-kill-roboport",
        "[surface] - TEST: kill a base's roboport (admin, test setting).", kill_roboport)
end

return M
