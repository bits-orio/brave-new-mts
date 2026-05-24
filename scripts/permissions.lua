-- scripts/permissions.lua
-- Brave New MTS players build ONLY through robots: no handcrafting, no
-- hand-mining, and -- experimentally -- no physical movement, so the
-- character-less body can't roam and chart fresh map on foot. Permission
-- groups gate only HUMAN input actions; assemblers, mining drills, and
-- construction/logistic bots are unaffected ("machines yes, humans no").
--
-- We lock down the engine "Default" permission group, which is the group MTS
-- keeps team players in (see multi-team-support spectator core). MTS's
-- transient "spectator" group is left to MTS.

local M = {}

-- Always blocked -- the safety baseline the design calls for either way.
local BLOCKED = {
    "craft",                -- no handcrafting
    "begin_mining",         -- no mining entities / resources
    "begin_mining_terrain", -- no mining ground / water
    "cycle_quality_up",     -- anti-dupe safety (matches Brave New OARC)
    "cycle_quality_down",
}

-- Blocking movement immobilises the character-less physical body so panning
-- around can't chart new chunks. VERIFY in-game that remote view still pans
-- with this blocked; if it breaks remote view, set this false and fall back to
-- a charted-area movement clamp (Brave New OARC style, on_player_changed_position).
local LOCK_PHYSICAL_MOVEMENT = true

function M.apply()
    local group = game.permissions.get_group("Default")
    if not group then return end

    for _, name in ipairs(BLOCKED) do
        local action = defines.input_action[name]
        if action then group.set_allows_action(action, false) end
    end

    if LOCK_PHYSICAL_MOVEMENT then
        local walk = defines.input_action.start_walking
        if walk then group.set_allows_action(walk, false) end
    end

    log("[brave-new-mts] Default permission group locked down (movement_locked="
        .. tostring(LOCK_PHYSICAL_MOVEMENT) .. ")")
end

return M
