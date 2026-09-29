-- scripts/base/kits.lua
-- What a base's chests start with, so the logistic network has stock to
-- bootstrap from: the home kit and the MTS admin's starter items at home, a
-- short planet kit at an outpost. A kit goes to passive providers first, then
-- storage chests, then the network; what is left over is logged.

local item_delivery = require("scripts.item_delivery")
local records       = require("scripts.base.records")

local M = {}

-- The home base's anti-soft-lock kit, dropped into its passive provider
-- chests so the logistic network has stock to bootstrap from. Edit
-- names/counts here to retune. Any name that isn't a valid item is skipped
-- (and logged) at placement time.
M.STARTER_ITEMS = {
    { name = "transport-belt",        count = 240 },
    { name = "medium-electric-pole",  count = 20  },
    { name = "inserter",              count = 12  },
    { name = "pipe",                  count = 10  },
    { name = "burner-inserter",       count = 8   },
    { name = "underground-belt",      count = 4  },
    { name = "splitter",              count = 4  },
    { name = "pipe-to-ground",        count = 4  },
    { name = "small-lamp",            count = 4  },
    { name = "stone-furnace",         count = 4   },
    { name = "assembling-machine-3",  count = 1   },
    { name = "electric-mining-drill", count = 3   },
    { name = "steam-engine",          count = 2   },
    { name = "lab",                   count = 2   },
    { name = "boiler",                count = 2   },
    { name = "offshore-pump",         count = 1   },
    { name = "advanced-circuit",      count = 4  },
    -- Defense + early mid-tier bootstrap.
    { name = "gun-turret",            count = 4   },
    { name = "firearm-magazine",      count = 100  },
}

-- An outpost's kit: the common list plus its planet's (the landing pad is
-- placed as an entity, not stocked). Nauvis-only items are left out. The
-- relay roboports are there because the first research trigger on Vulcanus
-- (calcite) and Fulgora (ruin vault) measured just outside the 110-tile
-- construction radius on one seed.
local OUTPOST_KIT_COMMON = {
    { name = "medium-electric-pole", count = 20  },
    { name = "transport-belt",       count = 100 },
    { name = "inserter",             count = 10  },
    { name = "pipe",                 count = 10  },
}
local OUTPOST_KITS = {
    vulcanus = {
        { name = "electric-mining-drill", count = 3  },
        { name = "roboport",              count = 1  },
        { name = "construction-robot",    count = 10 },
        { name = "steel-chest",           count = 4  },
    },
    fulgora = {
        { name = "electric-mining-drill", count = 2  },
        { name = "roboport",              count = 2  },
        { name = "construction-robot",    count = 15 },
        { name = "lightning-rod",         count = 10 },  -- cover for robots flying at night
        { name = "steel-chest",           count = 4  },
    },
    gleba = {
        { name = "gun-turret",         count = 6   },
        { name = "firearm-magazine",   count = 200 },
        { name = "roboport",           count = 1   },
        { name = "construction-robot", count = 10  },
    },
    aquilo = {
        { name = "heating-tower",         count = 1  },
        { name = "heat-pipe",             count = 20 },
        { name = "solid-fuel",            count = 50 },
        { name = "electric-mining-drill", count = 1  },
    },
}
local OUTPOST_KIT_OTHER = {
    { name = "roboport",           count = 1  },
    { name = "construction-robot", count = 10 },
}

--- A new list: `a` then `b` (either may be nil).
local function joined(a, b)
    local out = {}
    for _, v in ipairs(a or {}) do out[#out + 1] = v end
    for _, v in ipairs(b or {}) do out[#out + 1] = v end
    return out
end

--- Deliver an item list (or pool) across `chests`, then the network; log
--- whatever is left over rather than dropping it silently.
local function deliver(items, chests, network)
    local left = item_delivery.deliver(items, chests, network)
    if #left > 0 then
        log("[brave-new-mts] no room in the base's chests for: " .. item_delivery.describe(left))
    end
end

--- Kits go to passive providers first, then storage chests.
local function kit_chests(record)
    return joined(record.providers, record.storage_chests)
end

--- The admin-configured starter items tracked by MTS. With BNM loaded these are
--- routed into the team's home chests instead of a (non-existent) player
--- inventory, so every team -- including ones that spawn after an admin adds
--- items -- gets them once. Empty when MTS has none or is too old to expose
--- the query.
local function mts_starter_items()
    if not remote.interfaces["mts-v1"] then return {} end
    local ok, items = pcall(remote.call, "mts-v1", "get_starter_items")
    if ok and type(items) == "table" then return items end
    return {}
end

--- What a base's chests start with: the home kit, or the outpost's planet kit.
local function kit_for(profile, home)
    if home then return M.STARTER_ITEMS end
    return joined(OUTPOST_KIT_COMMON, OUTPOST_KITS[profile.base] or OUTPOST_KIT_OTHER)
end

--- Stock a freshly built base's chests with its kit, and a home base's with
--- the MTS admin items after it.
function M.stock(built, profile, home)
    local chests, network = kit_chests(built), records.network_of(built)
    deliver(kit_for(profile, home), chests, network)
    if home then deliver(mts_starter_items(), chests, network) end
end

--- Push an admin's freshly-added starter items into every HOME base already
--- placed, once per team. Teams that haven't spawned yet pick the items up at
--- placement time via mts_starter_items(), so between the two paths every
--- team ends up with the full admin list exactly once.
function M.add_items_to_spawned_bases(items)
    if not (storage.bnm_base and items and #items > 0) then return end
    for _, base in pairs(storage.bnm_base) do
        if base.home then deliver(items, kit_chests(base), records.network_of(base)) end
    end
end

return M
