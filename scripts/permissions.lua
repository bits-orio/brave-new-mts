-- scripts/permissions.lua
-- Brave New MTS players build ONLY through robots: no handcrafting and no
-- hand-mining. Permission groups gate only HUMAN input actions; assemblers,
-- mining drills, and construction/logistic bots are unaffected ("machines
-- yes, humans no").
--
-- We lock down the engine "Default" permission group, which is the group MTS
-- keeps team players in.
--
-- NOTE: we deliberately do NOT block start_walking. It also drives remote-view
-- camera panning, so blocking it freezes remote view entirely. Roaming/charting
-- on foot is handled separately by the charted-area clamp (scripts/movement_clamp.lua).

local M = {}

local BLOCKED = {
    "craft",                -- no handcrafting
    "begin_mining",         -- no mining entities / resources
    "begin_mining_terrain", -- no mining ground / water
}

function M.apply()
    local group = game.permissions.get_group("Default")
    if not group then return end

    for _, name in ipairs(BLOCKED) do
        local action = defines.input_action[name]
        if action then group.set_allows_action(action, false) end
    end

    log("[brave-new-mts] Default permission group locked down (no craft / mining)")
end

return M
