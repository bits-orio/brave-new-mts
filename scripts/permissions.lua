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
    -- No building by hand -- robots build from blueprints.
    "craft",                -- no handcrafting
    "begin_mining",         -- no mining entities / resources
    "begin_mining_terrain", -- no mining ground / water

    -- No moving items by hand to/from entities -- inserters and bots do that.
    -- Only the ENTITY-specific transfer actions are blocked: the generic
    -- stack_/cursor_/inventory_ transfer actions are shared with managing your
    -- own inventory and the blueprint library, so blocking them breaks copying
    -- and storing blueprints. open_gui stays allowed (logistic requests/recipes).
    -- Consequence: deliberate click-dragging items out of an open chest is
    -- still possible; the common ctrl-click vector is not.
    "fast_entity_transfer", -- ctrl-click to/from an entity
    "fast_entity_split",    -- ctrl-right-click to/from an entity
    "drop_item",            -- drop items on the ground
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
