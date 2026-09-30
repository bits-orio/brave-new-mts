-- scripts/test_commands.lua
-- Shortcuts for testing Space Age outposts without launching rockets and
-- flying a platform. They do nothing unless the map setting "Enable test
-- commands" (bnm-test-commands) is on, and they are admin-only like the
-- recovery commands. They grant research and create items, so leave the
-- setting off on a real server. Every use is announced to everyone.
--
--   /bnm-test-orbit <planet> [team-N]   research the way to <planet> and the
--        Character Clone, park a platform above the team's copy of <planet>
--        with one clone aboard (again: one more clone), and view its hub
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

--- The force a test command acts on: the named team, else the caller's own.
local function target_force(cmd, team)
    if not team then
        local player = cmd_util.caller(cmd)
        team = player and remote_player.effective_force(player)
    end
    return teams.is_team_force(team) and game.forces[team] or nil
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

--- Move the caller's remote view onto the hub and open it, if a player called.
local function view_hub(cmd, hub)
    local player = cmd_util.caller(cmd)
    if not (player and hub and hub.valid) then return end
    player.set_controller{ type = defines.controllers.remote, surface = hub.surface, position = hub.position }
    pcall(function() player.opened = hub end)  -- if it will not open remotely, one click does
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
        return cmd_util.reply(cmd, PREFIX .. "no team to act for: join a team, or name one, "
            .. "for example /bnm-test-orbit " .. base .. " team-2")
    end
    local planet = game.planets["mts-" .. base .. "-" .. teams.slot_of(force.name)]
    if not planet then return orbit_usage(cmd) end
    local researched = unlock_route(force, base, planet)
    local platform = test_platform(force, planet, base)
    local hub = platform and platform.hub
    if not (hub and hub.valid) then
        return cmd_util.reply(cmd, PREFIX .. "could not create a platform above " .. planet.name .. ".")
    end
    hub.get_inventory(defines.inventory.hub_main).insert{ name = CLONE, count = 1 }
    cmd_util.audit(cmd, "(test command) parked " .. force.name .. "'s platform \"" .. platform.name
        .. "\" above " .. planet.name .. " with a Character Clone aboard; researched "
        .. researched .. " technologies. Open the hub and press Establish base.")
    view_hub(cmd, hub)
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
