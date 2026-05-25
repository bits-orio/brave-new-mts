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

    -- No moving items by hand -- inserters and bots move items, not players.
    -- Opening entity GUIs (open_gui) is intentionally LEFT ALLOWED so logistic
    -- requests / recipes can still be configured; only item movement is blocked.
    -- The stack_/cursor_ actions are generic (also used for the player's own
    -- inventory and the blueprint library) -- verify blueprint grab+stamp still
    -- works; if not, drop stack_transfer/cursor_transfer.
    "fast_entity_transfer", -- ctrl-click to/from an entity
    "fast_entity_split",    -- ctrl-right-click to/from an entity
    "inventory_transfer",   -- ctrl-click "transfer all" within an open inventory
    "inventory_split",
    "stack_transfer",       -- click a stack to move it between slots
    "stack_split",
    "cursor_transfer",      -- place the held cursor stack into a slot
    "cursor_split",
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
