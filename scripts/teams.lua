-- scripts/teams.lua
-- The one rule for what is a team force, and the order teams are listed in,
-- as MTS keeps it in helpers.is_team_force / helpers.team_slot. MTS names each
-- team's force "team-<slot>". This is a leaf: it requires nothing, so any
-- module can use it without a require cycle (remote_player requires
-- pen_cells, so pen_cells could not use a rule kept in remote_player).

local M = {}

--- True for an MTS team force name ("team-7"). The type() guard keeps it
--- safe on a value read back from mts-v1.
function M.is_team_force(name)
    return type(name) == "string" and name:match("^team%-%d+$") ~= nil
end

--- The team's slot number ("team-7" -> 7), or nil when it isn't a team force.
function M.slot_of(name)
    if type(name) ~= "string" then return nil end
    return tonumber(name:match("^team%-(%d+)$"))
end

--- Sort comparator for force names: by slot number, not the string, which
--- would put team-10 before team-2; then by name, so the order is total.
function M.by_slot(a, b)
    local na, nb = M.slot_of(a) or math.huge, M.slot_of(b) or math.huge
    if na ~= nb then return na < nb end
    return a < b
end

return M
