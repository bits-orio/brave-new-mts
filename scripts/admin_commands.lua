-- scripts/admin_commands.lua
-- Recovery commands for server admins, so a stuck team or player can be fixed
-- without /sc (which flags the save as achievement-disabled). Usable by an
-- admin or from the server console / RCON only. Every action is logged and
-- printed to everyone, so a public server keeps an audit trail.
--
--   /bnm-status [team-N]         bases, roboports, rescues and parked players
--                                (read-only, scripts/admin_status.lua)
--   /bnm-repark <player>         put a player back in remote view of their team
--   /bnm-forget-base <surface>   wipe a dead outpost so it can be founded again
--   /bnm-rescue <surface>        refill a base's roboport, spending none of the
--                                team's rescues (scripts/rescue.lua)
--
-- M.register() adds the commands. It must run ONCE per Lua state, from
-- control.lua's main chunk: init_events runs in on_load and again in
-- on_configuration_changed, and adding a command twice is an error.

local admin_status  = require("scripts.admin_status")
local remote_player = require("scripts.remote_player")
local rescue        = require("scripts.rescue")
local starter_base  = require("scripts.starter_base")
local cmd_util      = require("scripts.command_util")

local M = {}

local PREFIX     = cmd_util.PREFIX
local reply      = cmd_util.reply
local authorised = cmd_util.authorised
local audit      = cmd_util.audit
local trimmed    = cmd_util.trimmed

-- ─── /bnm-repark ───────────────────────────────────────────────────────

local function repark(cmd)
    if not authorised(cmd) then return end
    local name = trimmed(cmd.parameter)
    if not name then
        reply(cmd, PREFIX .. "usage: /bnm-repark <player name>")
        return
    end
    local target = game.get_player(name)
    if not target then
        reply(cmd, PREFIX .. "no player named " .. name .. ".")
        return
    end
    if not target.connected then
        reply(cmd, PREFIX .. target.name .. " is offline; they are re-parked when they reconnect.")
        return
    end
    local viewed = remote_player.park(target)
    if viewed then
        audit(cmd, "re-parked " .. target.name .. " (viewing " .. viewed .. ").")
    else
        reply(cmd, PREFIX .. target.name .. " was not re-parked: not on a team, "
            .. "spectating, in the map editor, or no team surface to view.")
    end
end

-- ─── /bnm-forget-base ──────────────────────────────────────────────────

--- Why /bnm-forget-base must leave the base on `name` alone, or nil.
local function forget_refusal(name, base)
    if not base then return nil end
    -- Never a home: a clone founding it again records an outpost, and a
    -- team with no home base can never be eliminated.
    if base.home then
        return name .. " is " .. base.force .. "'s home base, and a home base cannot be "
            .. "re-founded. To end that team, an admin runs /mts-disband " .. base.force .. " in game."
    end
    if base.roboport and base.roboport.valid then
        return name .. " still has a live roboport; refusing, so a standing base is never founded twice."
    end
    return nil
end

local function forget_base(cmd)
    if not authorised(cmd) then return end
    local name = trimmed(cmd.parameter)
    if not name then
        reply(cmd, PREFIX .. "usage: /bnm-forget-base <surface name>")
        return
    end
    local base = starter_base.base_for(name)
    local refusal = forget_refusal(name, base)
    if refusal then
        reply(cmd, PREFIX .. refusal)
        return
    end
    -- A dead outpost is wiped as its roboport's death would wipe it: its
    -- core, tuned copies included, becomes minable for the team's robots.
    local wiped = starter_base.lose_outpost(name)
    if not wiped then starter_base.forget_surface(name) end
    audit(cmd, "forgot the base record for " .. name .. (base and "" or " (none was recorded)")
        .. (wiped and "; its power core can now be mined" or "") .. "; it can be founded again.")
end

-- ─── /bnm-rescue ───────────────────────────────────────────────────────

local function rescue_base(cmd)
    if not authorised(cmd) then return end
    local name = trimmed(cmd.parameter)
    local base = name and starter_base.base_for(name)
    if not (base and base.roboport and base.roboport.valid) then
        reply(cmd, PREFIX .. (name and ("no base with a standing roboport on " .. name .. ". ") or "")
            .. "usage: /bnm-rescue <surface name>, for example /bnm-rescue mts-gleba-3 (see /bnm-status)")
        return
    end
    local was_dark = rescue.refill(base)
    audit(cmd, "refilled " .. base.force .. "'s " .. (base.home and "home" or "outpost")
        .. " roboport on " .. name .. " (" .. (was_dark and "it was out of power" or "it still had power")
        .. "); the team's rescues are untouched.")
end

-- ─── Registration ──────────────────────────────────────────────────────

function M.register()
    commands.add_command("bnm-status",
        "[team-N] - Brave New MTS bases, roboports, rescues and parked players (admin).",
        admin_status.status)
    commands.add_command("bnm-repark",
        "<player> - put a player back in remote view of their team (admin).", repark)
    commands.add_command("bnm-forget-base",
        "<surface> - wipe a dead outpost so it can be founded again (admin).", forget_base)
    commands.add_command("bnm-rescue",
        "<surface> - refill a base's roboport that ran out of power (admin).", rescue_base)
end

return M
