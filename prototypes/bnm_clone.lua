-- prototypes/bnm_clone.lua
-- The "character clone": a token you ship to another planet to found your
-- overseer base there. It does nothing on its own -- it's purely a carry-along
-- proof that you've brought yourself to that world. It weighs exactly one
-- rocket's lift capacity, so a rocket carries one clone and nothing else:
-- shipping yourself somewhere is a dedicated launch.
--
-- It is craftable (in an assembler -- handcrafting is blocked for overseers),
-- so a team produces clones as part of their factory.
--
-- The clone is ONLY meaningful with Space Age (it exists to ship yourself
-- between planets/platforms). Without Space Age there are no other planets, so
-- the whole thing -- item, recipe and unlocking technology -- is skipped: the
-- green-character tech is then not even available, as intended.

if not mods["space-age"] then return end

local CLONE      = "bnm-character-clone"
local CLONE_TINT = { r = 0.4, g = 1.0, b = 0.4, a = 1.0 }

-- One clone fills a whole rocket payload (weight == the rocket's lift capacity).
local rocket_lift = (data.raw["utility-constants"]["default"] or {}).rocket_lift_weight or 1000000

data:extend({
    {
        type                  = "item",
        name                  = CLONE,
        localised_name        = { "", "Character Clone" },
        localised_description  = { "",
            "Ship one to a planet your team's space platform has reached, then "
            .. "press \"Establish base\" in the platform hub to found your "
            .. "overseer base there. Weighs a full rocket on its own." },
        -- Radioactive uranium-green clone: a green-tinted character icon, plus
        -- an additive glow layer so it actually radiates when on the ground/belt.
        icons = {
            {
                icon      = "__core__/graphics/icons/entity/character.png",
                icon_size = 64,
                tint      = CLONE_TINT,
            },
        },
        pictures = {
            layers = {
                {
                    size     = 64,
                    filename = "__core__/graphics/icons/entity/character.png",
                    scale    = 0.5,
                    tint     = CLONE_TINT,
                },
                -- Two additive light layers, stacked for a brighter, hotter glow.
                {
                    draw_as_light = true,
                    blend_mode    = "additive",
                    size          = 64,
                    filename      = "__core__/graphics/icons/entity/character.png",
                    scale         = 0.5,
                    tint          = { r = 0.2, g = 1.0, b = 0.2, a = 1.0 },
                },
                {
                    draw_as_light = true,
                    blend_mode    = "additive",
                    size          = 64,
                    filename      = "__core__/graphics/icons/entity/character.png",
                    scale         = 0.5,
                    tint          = CLONE_TINT,
                },
            },
        },
        stack_size            = 1,
        weight                = rocket_lift,
        subgroup              = "space-rocket",  -- lives in the Space tab
        order                 = "z[bnm-character-clone]",
    },
    {
        type            = "recipe",
        name            = CLONE,
        enabled         = false,          -- unlocked by the bnm-character-clone technology
        energy_required = 30,
        category        = "crafting",     -- assembler-craftable; not hand-craftable
        ingredients     = {
            { type = "item", name = "processing-unit",       amount = 20 },
            { type = "item", name = "low-density-structure", amount = 20 },
            { type = "item", name = "electric-engine-unit",  amount = 10 },
        },
        results         = { { type = "item", name = CLONE, amount = 1 } },
    },
    -- A dedicated technology that unlocks the clone. Requiring BOTH rocket-silo
    -- (you can't ship a clone until you can launch rockets) AND tank (a military
    -- gate) means the recipe only appears once both are researched -- two
    -- separate unlock effects would be an OR, so one shared tech is the way to
    -- AND them. Space-Age-only: see the guard at the top of this file.
    {
        type          = "technology",
        name          = CLONE,
        icon_size     = 64,
        icons = {
            {
                icon      = "__core__/graphics/icons/entity/character.png",
                icon_size = 64,
                tint      = CLONE_TINT,
            },
        },
        prerequisites = { "rocket-silo", "tank" },
        effects       = { { type = "unlock-recipe", recipe = CLONE } },
        unit = {
            count = 300,
            ingredients = {
                { "automation-science-pack", 1 },
                { "logistic-science-pack",   1 },
                { "military-science-pack",   1 },
                { "chemical-science-pack",   1 },
                { "production-science-pack", 1 },
                { "utility-science-pack",    1 },
            },
            time = 30,
        },
        order = "e-z-[bnm-character-clone]",
    },
})
