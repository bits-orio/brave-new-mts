-- scripts/command_util.lua
-- What every BNM console command shares: who called it, how it answers, the
-- admin gate, and the public audit line. A command is usable by an admin or
-- from the server console / RCON only, and every action it takes is printed
-- to everyone, so a public server keeps an audit trail.

local chat = require("scripts.chat")

local M = {}

M.PREFIX = chat.PREFIX

--- The calling player, or nil for the server console / RCON.
function M.caller(cmd)
    return cmd.player_index and game.get_player(cmd.player_index)
end

--- Answer only the caller: in chat for a player, over RCON and in the log
--- for the console.
function M.reply(cmd, text)
    local player = M.caller(cmd)
    if player then player.print(text) else rcon.print(text); log(text) end
end

--- True for an admin or the server console; tells anyone else no.
function M.authorised(cmd)
    local player = M.caller(cmd)
    if not player or player.admin then return true end
    player.print(M.PREFIX .. "/" .. cmd.name .. " is for admins only.")
    return false
end

--- Announce an admin action to everyone and log it.
function M.audit(cmd, text)
    local player = M.caller(cmd)
    local line = M.PREFIX .. (player and player.name or "server") .. " " .. text
    game.print(line)
    log(line)
    if not player then rcon.print(line) end
end

--- The command's parameter without surrounding spaces, or nil when empty.
function M.trimmed(parameter)
    local s = parameter and parameter:match("^%s*(.-)%s*$")
    return (s ~= "" and s) or nil
end

return M
