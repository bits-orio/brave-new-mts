-- scripts/rescue.lua
-- Rescues: restarting a base whose roboport ran out of power. When a
-- roboport's buffer empties, the engine shuts its logistic network down until
-- the buffer climbs back to the prototype's recharge_minimum, and with no
-- network the robots stay docked; a character-free team has no other hands. A
-- rescue fills the buffer, and the network is back at once (measured on the
-- rig).
--
-- Each team may spend a few (map setting bnm-rescues-per-team, default 3); the
-- team leader spends them from the team tab (scripts/team_tab/rescue_section.lua).
-- Admins refill a roboport without spending one (/bnm-rescue). The roboport
-- is fed before anything else on its network (prototypes/bnm_roboport.lua),
-- so it goes dark only when the base's own power cannot cover it: the core
-- removed after the unlock, its panels destroyed, a night with empty
-- accumulators.
--
-- storage.bnm_rescues_spent: force name -> the rescues it spent, oldest first,
-- each { surface = surface name, by = player name or nil }, so the team tab can
-- show what each card went on. A released team slot starts again from none
-- (M.cleanup_force).

local starter_base = require("scripts.starter_base")

local M = {}

local SETTING = "bnm-rescues-per-team"

--- Rescues every team may spend, from the map setting.
function M.allowance()
    return settings.global[SETTING].value
end

--- The rescues the team spent, oldest first: { surface, by }.
function M.spent(force_name)
    return (storage.bnm_rescues_spent or {})[force_name] or {}
end

--- Rescues the team has left.
function M.left(force_name)
    return math.max(0, M.allowance() - #M.spent(force_name))
end

--- True if the base's roboport stands but its network is shut down. A full
--- roboport is never dark: a refill counts at once, before the engine turns
--- the network back on at the roboport's next update.
function M.is_dark(base)
    local roboport = base and base.roboport
    if not (roboport and roboport.valid) then return false end
    local cell = roboport.logistic_cell
    if cell and cell.transmitting then return false end
    return roboport.energy < roboport.electric_buffer_size
end

--- The surface names of the team's bases whose roboport is dark, sorted.
function M.dark_bases(force_name)
    local out = {}
    for surface_name, base in pairs(storage.bnm_base or {}) do
        if base.force == force_name and M.is_dark(base) then out[#out + 1] = surface_name end
    end
    table.sort(out)
    return out
end

--- Fill a base's roboport, which must stand. Returns whether it was dark.
function M.refill(base)
    local dark = M.is_dark(base)
    base.roboport.energy = base.roboport.electric_buffer_size
    return dark
end

--- Why the team cannot spend a rescue on `base`, or nil.
local function refusal(force_name, base)
    if not (base and base.force == force_name) then return "your team has no base there" end
    if not (base.roboport and base.roboport.valid) then return "that base's roboport is gone" end
    if not M.is_dark(base) then return "that base's roboport already has power" end
    if M.left(force_name) == 0 then return "your team has no rescues left" end
    return nil
end

--- Spend one of the team's rescues on its base on `surface_name`, which must
--- be dark; `by` names who spent it (optional). Returns ok, and the reason
--- when not.
function M.spend(force_name, surface_name, by)
    local base = starter_base.base_for(surface_name)
    local why = refusal(force_name, base)
    if why then return false, why end
    M.refill(base)
    storage.bnm_rescues_spent = storage.bnm_rescues_spent or {}
    local spent = storage.bnm_rescues_spent[force_name] or {}
    spent[#spent + 1] = { surface = surface_name, by = by }
    storage.bnm_rescues_spent[force_name] = spent
    return true
end

--- Forget a released team's spent rescues, so the next team in its slot
--- starts with the full allowance.
function M.cleanup_force(force_name)
    if storage.bnm_rescues_spent then storage.bnm_rescues_spent[force_name] = nil end
end

return M
