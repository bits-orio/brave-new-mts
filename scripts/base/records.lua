-- scripts/base/records.lua
-- The base records, per surface name: storage.bnm_base (the owning force,
-- home or outpost, the roboport, the locked core, the chests, the pad, the
-- unlock) and storage.bases_placed, which makes placement idempotent. A
-- team has at most one HOME; every other base is an OUTPOST.

local power_core = require("scripts.base.power_core")

local M = {}

--- The force's home base record and its surface name, or nil. The one rule
--- for which base is a team's home.
function M.home_of(force_name)
    for surface_name, base in pairs(storage.bnm_base or {}) do
        if base.force == force_name and base.home then return base, surface_name end
    end
    return nil
end

--- True if a base was placed on the surface and not forgotten since.
function M.is_placed(surface_name)
    storage.bases_placed = storage.bases_placed or {}
    return storage.bases_placed[surface_name]
end

--- File a logistic chest under the record's providers or storage chests.
function M.add_chest(record, chest)
    local mode = chest.prototype.logistic_mode
    if mode == "passive-provider" then
        record.providers[#record.providers + 1] = chest
    elseif mode == "storage" then
        record.storage_chests[#record.storage_chests + 1] = chest
    end
end

--- The logistic network of a base's live roboport, or nil.
function M.network_of(record)
    local roboport = record.roboport
    return roboport and roboport.valid and roboport.logistic_network or nil
end

--- Track the base per surface, so the minable toggle, the roboport-loss
--- handler and admin item grants can find it. `protected` is the power core;
--- `providers` / `storage_chests` receive later deliveries.
function M.record(force_name, surface_name, built, home, locked)
    storage.bnm_base = storage.bnm_base or {}
    storage.bnm_base[surface_name] = {
        force          = force_name,
        home           = home,
        outpost        = not home,
        roboport       = built.roboport,
        protected      = built.protected,
        providers      = built.providers,
        storage_chests = built.storage_chests,
        pad            = built.pad,
        unlocked       = not locked,
    }
    storage.bases_placed[surface_name] = true
end

--- The storage.bnm_base record for a surface name, or nil.
function M.base_for(surface_name)
    return storage.bnm_base and storage.bnm_base[surface_name] or nil
end

--- Forget a surface's base, so it can be founded again.
function M.forget_surface(surface_name)
    if storage.bnm_base then storage.bnm_base[surface_name] = nil end
    if storage.bases_placed then storage.bases_placed[surface_name] = nil end
end

--- Wipe an outpost whose roboport was lost: its locked core, tuned copies
--- included, becomes minable, so the team's bots can salvage it, and the
--- surface is forgotten, so a clone can re-found it (place then sweeps what
--- is left in the site). A home base is never wiped here. Returns true if an
--- outpost was wiped.
function M.lose_outpost(surface_name)
    local base = M.base_for(surface_name)
    if not (base and base.outpost) then return false end
    power_core.release(base)
    M.forget_surface(surface_name)
    return true
end

--- Unlock the team's power core so it can be mined too, opt-in once the team
--- accepts the soft-lock risk. The roboport and the planet-tuned copies
--- always stay non-minable. Applies to all the team's bases; bases founded
--- later are built unlocked.
function M.unlock_minable(force_name)
    if not storage.bnm_base then return end
    for _, base in pairs(storage.bnm_base) do
        if base.force == force_name then power_core.unlock(base) end
    end
end

--- Forget all per-surface base state for a force, so a team that later recycles
--- this slot gets a fresh base. MTS deletes the team's surfaces on disband; if
--- we kept `bases_placed` set for those (recycled) surface names, place would
--- early-return and never re-chart the new base -- leaving the new occupant
--- unable to see their surface. Keyed off bnm_base (which records the owning
--- force per surface), since the surfaces themselves are already gone by the
--- time on_team_released fires.
function M.cleanup_force(force_name)
    if not storage.bnm_base then return end
    for surface_name, base in pairs(storage.bnm_base) do
        if base.force == force_name then M.forget_surface(surface_name) end
    end
end

--- True if the team has opted to make its starter base minable.
function M.is_unlocked(force_name)
    if not storage.bnm_base then return false end
    for _, base in pairs(storage.bnm_base) do
        if base.force == force_name and base.unlocked then return true end
    end
    return false
end

return M
