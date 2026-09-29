-- scripts/starter_base.lua
-- Seeds a self-running starter base on a team surface, so a character-free,
-- cheat-free team can bootstrap a bot factory. The base founded while the
-- team has no home (its first) is its HOME: losing its roboport eliminates
-- the team. A base founded with a Character Clone is an OUTPOST: losing its
-- roboport wipes only that outpost (M.lose_outpost), and another clone
-- re-founds it. Placement is idempotent per surface
-- (storage.bases_placed[surface.name]).
--
-- This file is the public face the events and commands use. The work lives
-- in scripts/base/, one concern per file:
--   founding.lua     M.place: the order a base is founded in
--   profiles.lua     the planet profile a surface gets, from the data stage
--   geometry.lua     the base's origin, footprint and site
--   site_prep.lua    ground, enemies, cargo and obstacles cleared off the site
--   salvage.lua      crash loot and a lost base's leftovers, pooled and delivered
--   builder.lua      the blueprint built as real, seeded entities
--   power_core.lua   what stays non-minable, and when
--   landing_pad.lua  an outpost's cargo landing pad
--   kits.lua         the starter kits and MTS admin items in the chests
--   oil_node.lua     the Nauvis crude-oil node
--   chunks.lua       generating and charting the chunks around the base
--   records.lua      storage.bnm_base and storage.bases_placed
--   migration.lua    upgrading 0.1.x records

local founding  = require("scripts.base.founding")
local geometry  = require("scripts.base.geometry")
local kits      = require("scripts.base.kits")
local migration = require("scripts.base.migration")
local profiles  = require("scripts.base.profiles")
local records   = require("scripts.base.records")

local M = {}

-- Where every base is centred: the roboport sits here (a chunk centre).
M.BASE_ORIGIN = geometry.BASE_ORIGIN

-- The home base's kit, stocked into its chests.
M.STARTER_ITEMS = kits.STARTER_ITEMS

-- Founding: place(force_name, surface, opts) -> true when a base with a live
-- roboport was built. opts.outpost = true marks an off-world base.
M.place       = founding.place
M.profile_for = profiles.profile_for

-- Records: look up, forget, lose and unlock bases.
M.base_for       = records.base_for
M.forget_surface = records.forget_surface
M.lose_outpost   = records.lose_outpost
M.cleanup_force  = records.cleanup_force
M.unlock_minable = records.unlock_minable
M.is_unlocked    = records.is_unlocked

-- Admin starter items added after some home bases were placed.
M.add_items_to_spawned_bases = kits.add_items_to_spawned_bases

-- Upgrade 0.1.x records; call from on_configuration_changed.
M.migrate = migration.migrate

return M
