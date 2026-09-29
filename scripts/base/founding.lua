-- scripts/base/founding.lua
-- Founds a starter base on a team surface. A team's first base is its HOME;
-- a base founded later with a Character Clone is an OUTPOST. Placement is
-- idempotent per surface (storage.bases_placed[surface.name]).
--
-- M.place, in order:
--   1. Generate the ground. Off-world surfaces start with no generated chunks,
--      and generating them after the build overwrites the floor and drops
--      cliffs and ocean into the base.
--   2. Clear the site: enemies inside the roboport's construction area
--      (worms outrange the footprint and shoot down robots), cargo moved aside
--      (it holds the team's items), leftovers of a lost base swept into a
--      salvage pool (their contents, and what the team built there as items),
--      then obstacles and resources.
--   3. Build the blueprint (scripts/blueprints.lua, swapped per planet) as
--      REAL entities centred on its roboport, each with its own blueprint
--      settings. There are no bots or materials yet to build ghosts.
--   4. Outposts get a cargo landing pad below the south wall: without one,
--      nothing a platform carries reaches the ground.
--   5. Stock the chests. The kit goes in first (home: the Nauvis kit and MTS
--      admin items; outpost: a short planet kit), then the salvage pool
--      (crash-site loot at home), so salvage never crowds out the kit. What
--      no chest can hold is spilled for the robots (scripts/item_delivery.lua).
--   6. Lock the power core (unless the team already unlocked it; planet-tuned
--      copies are locked for good) and record the base in storage.bnm_base.

local blueprints  = require("scripts.blueprints")
local builder     = require("scripts.base.builder")
local chunks      = require("scripts.base.chunks")
local geometry    = require("scripts.base.geometry")
local kits        = require("scripts.base.kits")
local landing_pad = require("scripts.base.landing_pad")
local oil_node    = require("scripts.base.oil_node")
local profiles    = require("scripts.base.profiles")
local records     = require("scripts.base.records")
local salvage     = require("scripts.base.salvage")
local site_prep   = require("scripts.base.site_prep")

local M = {}

-- The research that makes bot-driven play possible from the start.
local CONSTRUCTION_TECH = "construction-robotics"

--- True if the base's roboport stands; logs why the base is not recorded
--- otherwise.
local function roboport_stands(built, surface)
    if built.roboport and built.roboport.valid then return true end
    log("[brave-new-mts] no roboport was built on " .. surface.name .. " -- base not recorded")
    return false
end

--- Build a base and record it. Returns true only when its roboport stands.
--- The pad and the kit go in before the salvage, so salvage never crowds out
--- the kit. Salvage is delivered even when no roboport stands: the sweep has
--- already destroyed what held it.
local function found_base(force, surface, home)
    local profile = profiles.profile_for(surface)
    local plan = blueprints.plan_for(profile, home)
    if not plan then
        log("[brave-new-mts] the starter blueprint has no roboport -- no base on " .. surface.name)
        return false
    end
    local origin = geometry.BASE_ORIGIN
    local site   = geometry.site_for(origin, plan, not home)
    local pool   = site_prep.prepare(force, surface, origin, site, plan, home)
    builder.place_tiles(surface, origin, plan)
    local locked = not records.is_unlocked(force.name)
    local built  = builder.build(force, surface, origin, plan, locked)
    local stands = roboport_stands(built, surface)
    if stands then
        built.pad = site.pad and landing_pad.place(force, surface, site.pad) or nil
        kits.stock(built, profile, home)
    end
    salvage.deliver(pool, built, force, surface)
    if not stands then return false end
    if profile.base == "nauvis" then oil_node.place(force, surface) end
    chunks.chart(force, surface, site.footprint)  -- no character stands here to chart it
    records.record(force.name, surface.name, built, home, locked)
    return true
end

--- Grant construction robotics so bot-driven play is possible from the start.
local function grant_construction_robotics(force)
    local cr = force.technologies[CONSTRUCTION_TECH]
    if cr and not cr.researched then
        cr.researched = true
        force.print("[Brave New MTS] Construction robotics research has been unlocked for your team.")
    end
end

--- Place a starter base for `force_name` on `surface` (idempotent). The
--- force's first base is its home; opts.outpost = true marks an off-world
--- base founded with a clone. Returns true only when a base with a live
--- roboport was built in this call.
function M.place(force_name, surface, opts)
    if not (surface and surface.valid) then return false end
    if records.is_placed(surface.name) then return false end
    local force = game.forces[force_name]
    if not (force and force.valid) then return false end

    local home = not (opts and opts.outpost) and not records.has_base(force_name)
    if not found_base(force, surface, home) then return false end
    grant_construction_robotics(force)
    log("[brave-new-mts] starter " .. (home and "home base" or "outpost") .. " placed for "
        .. force_name .. " on " .. surface.name)
    return true
end

return M
