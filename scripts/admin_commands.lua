-- scripts/admin_commands.lua
-- Recovery commands for server admins, so a stuck team or player can be fixed
-- without /sc (which flags the save as achievement-disabled). Usable by an
-- admin or from the server console / RCON only. Every action is logged and
-- printed to everyone, so a public server keeps an audit trail.
--
--   /bnm-status [team-N]         bases, roboports and parked players (read-only)
--   /bnm-repark <player>         put a player back in remote view of their team
--   /bnm-forget-base <surface>   drop a dead outpost's record so it can be founded again
--
-- M.register() adds the commands. It must run ONCE per Lua state, from
-- control.lua's main chunk: init_events runs in on_load and again in
-- on_configuration_changed, and adding a command twice is an error.

local remote_player = require("scripts.remote_player")
local starter_base  = require("scripts.starter_base")

local M = {}

local PREFIX = "[Brave New MTS] "

-- ─── Caller, replies and audit ─────────────────────────────────────────

--- The calling player, or nil for the server console / RCON.
local function caller(cmd)
    return cmd.player_index and game.get_player(cmd.player_index)
end

local function reply(cmd, text)
    local player = caller(cmd)
    if player then player.print(text) else rcon.print(text); log(text) end
end

--- True for an admin or the server console; tells anyone else no.
local function authorised(cmd)
    local player = caller(cmd)
    if not player or player.admin then return true end
    player.print(PREFIX .. "/" .. cmd.name .. " is for admins only.")
    return false
end

--- Announce an admin action to everyone and log it.
local function audit(cmd, text)
    local player = caller(cmd)
    local line = PREFIX .. (player and player.name or "server") .. " " .. text
    game.print(line)
    log(line)
    if not player then rcon.print(line) end
end

local function trimmed(parameter)
    local s = parameter and parameter:match("^%s*(.-)%s*$")
    return (s ~= "" and s) or nil
end

-- ─── /bnm-status ───────────────────────────────────────────────────────

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function base_line(surface_name, base)
    local kind  = base.home and "home" or base.outpost and "outpost" or "base"
    local robo  = (base.roboport and base.roboport.valid) and "roboport alive" or "roboport MISSING"
    local lock  = base.unlocked and "unlocked" or "locked"
    return "  " .. surface_name .. ": " .. kind .. ", " .. robo .. ", " .. lock
end

local function player_line(player)
    local function get(t) return (storage[t] and storage[t][player.index]) or "-" end
    local view = player.connected and player.surface.name or "offline"
    return "  " .. player.name .. ": viewing " .. view .. ", last view "
        .. get("last_view") .. ", home " .. get("home_surface")
end

--- Status lines for one team force.
local function team_lines(force_name)
    local info  = remote.interfaces["mts-v1"]
        and remote.call("mts-v1", "get_team_info", force_name)
    local lines = { force_name .. " (" .. ((info and info.display_name) or "?") .. ")" }
    local bases = storage.bnm_base or {}
    for _, name in ipairs(sorted_keys(bases)) do
        if bases[name].force == force_name then lines[#lines + 1] = base_line(name, bases[name]) end
    end
    if #lines == 1 then lines[#lines + 1] = "  no bases" end
    for _, player in pairs(game.players) do
        if remote_player.effective_force(player) == force_name then
            lines[#lines + 1] = player_line(player)
        end
    end
    return lines
end

--- Every team with a base record or a member, in slot order.
local function teams_to_show()
    local seen = {}
    for _, base in pairs(storage.bnm_base or {}) do
        if base.force then seen[base.force] = true end
    end
    for _, player in pairs(game.players) do
        local fn = remote_player.effective_force(player)
        if fn and fn:match("^team%-%d+$") then seen[fn] = true end
    end
    local list = sorted_keys(seen)
    table.sort(list, function(a, b)
        return (tonumber(a:match("%d+")) or 0) < (tonumber(b:match("%d+")) or 0)
    end)
    return list
end

local function status(cmd)
    if not authorised(cmd) then return end
    local team  = trimmed(cmd.parameter)
    local teams = team and { team } or teams_to_show()
    local lines = {}
    for _, fn in ipairs(teams) do
        for _, line in ipairs(team_lines(fn)) do lines[#lines + 1] = line end
    end
    -- A "placed" flag without a base record would block a planet for good.
    for _, name in ipairs(sorted_keys(storage.bases_placed or {})) do
        if not (storage.bnm_base and storage.bnm_base[name]) then
            lines[#lines + 1] = "stale placed flag (no base record): " .. name
        end
    end
    if #lines == 0 then lines[1] = "no bases and no team players" end
    reply(cmd, PREFIX .. "status\n" .. table.concat(lines, "\n"))
end

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

local function forget_base(cmd)
    if not authorised(cmd) then return end
    local name = trimmed(cmd.parameter)
    if not name then
        reply(cmd, PREFIX .. "usage: /bnm-forget-base <surface name>")
        return
    end
    local base = starter_base.base_for(name)
    -- Never a home: whatever founds a base there next (a clone, or a new
    -- member arriving) records an outpost while the team has any other base,
    -- and a team with no home base can never be eliminated.
    if base and base.home then
        reply(cmd, PREFIX .. name .. " is " .. base.force .. "'s home base, and a home base "
            .. "cannot be re-founded. To end that team, an admin runs /mts-disband "
            .. base.force .. " in game.")
        return
    end
    if base and base.roboport and base.roboport.valid then
        reply(cmd, PREFIX .. name .. " still has a live roboport; refusing, so a "
            .. "standing base is never founded twice.")
        return
    end
    starter_base.forget_surface(name)
    audit(cmd, "forgot the base record for " .. name
        .. (base and "" or " (none was recorded)") .. "; it can be founded again.")
end

-- ─── Registration ──────────────────────────────────────────────────────

function M.register()
    commands.add_command("bnm-status",
        "[team-N] - Brave New MTS bases, roboports and parked players (admin).", status)
    commands.add_command("bnm-repark",
        "<player> - put a player back in remote view of their team (admin).", repark)
    commands.add_command("bnm-forget-base",
        "<surface> - drop a dead outpost's record so it can be founded again (admin).", forget_base)
end

return M
