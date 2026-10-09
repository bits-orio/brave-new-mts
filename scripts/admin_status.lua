-- scripts/admin_status.lua
-- /bnm-status [team-N]: a read-only report for admins. Per team: its rescues
-- left, each base (home or outpost, whether its roboport stands and has power,
-- whether its core is unlocked), and for each member the surface they view,
-- the one they last viewed and their home surface. It also flags a placed
-- flag with no base record, which would block a planet for good. Registered
-- by scripts/admin_commands.lua; answers only the caller.

local remote_player = require("scripts.remote_player")
local rescue        = require("scripts.rescue")
local teams         = require("scripts.teams")
local cmd_util      = require("scripts.command_util")

local M = {}

--- The keys of `t`, sorted by `order` (a table.sort comparator), else by name.
local function sorted_keys(t, order)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, order)
    return keys
end

local function roboport_state(base)
    if not (base.roboport and base.roboport.valid) then return "roboport MISSING" end
    return rescue.is_dark(base) and "roboport OUT OF POWER" or "roboport alive"
end

local function base_line(surface_name, base)
    local kind = base.home and "home" or base.outpost and "outpost" or "base"
    local lock = base.unlocked and "unlocked" or "locked"
    return "  " .. surface_name .. ": " .. kind .. ", " .. roboport_state(base) .. ", " .. lock
end

local function player_line(player)
    local function get(t) return (storage[t] and storage[t][player.index]) or "-" end
    local view = player.connected and player.surface.name or "offline"
    return "  " .. player.name .. ": viewing " .. view .. ", last view "
        .. get("last_view") .. ", home " .. get("home_surface")
end

--- Status lines for one team force. "?" in place of the team's name says
--- MTS does not know the force, which teams.display_name would hide.
local function team_lines(force_name)
    local info  = teams.info(force_name)
    local lines = { force_name .. " (" .. ((info and info.display_name) or "?") .. "), rescues left "
        .. rescue.left(force_name) .. " of " .. rescue.allowance() }
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
        if teams.is_team_force(fn) then seen[fn] = true end
    end
    return sorted_keys(seen, teams.by_slot)
end

--- A "placed" flag without a base record would block a planet for good.
local function stale_flag_lines(lines)
    for _, name in ipairs(sorted_keys(storage.bases_placed or {})) do
        if not (storage.bnm_base and storage.bnm_base[name]) then
            lines[#lines + 1] = "stale placed flag (no base record): " .. name
        end
    end
end

--- The /bnm-status handler.
function M.status(cmd)
    if not cmd_util.authorised(cmd) then return end
    local team  = cmd_util.trimmed(cmd.parameter)
    local shown = team and { team } or teams_to_show()
    local lines = {}
    for _, fn in ipairs(shown) do
        for _, line in ipairs(team_lines(fn)) do lines[#lines + 1] = line end
    end
    stale_flag_lines(lines)
    if #lines == 0 then lines[1] = "no bases and no team players" end
    cmd_util.reply(cmd, cmd_util.PREFIX .. "status\n" .. table.concat(lines, "\n"))
end

return M
