-- prototypes/bnm_clone.lua
-- The "character clone": a token you ship to another planet to found your
-- overseer base there. It does nothing on its own -- it's purely a carry-along
-- proof that you've brought yourself to that world. It weighs exactly one
-- rocket's lift capacity, so a rocket carries one clone and nothing else:
-- shipping yourself somewhere is a dedicated launch.
--
-- It is craftable (in an assembler -- handcrafting is blocked for overseers),
-- so a team produces clones as part of their factory.

local CLONE = "bnm-character-clone"

-- One clone fills a whole rocket payload (weight == the rocket's lift capacity).
local rocket_lift = (data.raw["utility-constants"]["default"] or {}).rocket_lift_weight or 1000000

-- Live in the Space tab when Space Age is present (the clone is only useful
-- with planets/platforms); fall back to a base subgroup otherwise so the
-- prototype still loads cleanly without Space Age.
local clone_subgroup = mods["space-age"] and "space-rocket" or "intermediate-product"

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
                tint      = { r = 0.4, g = 1.0, b = 0.4, a = 1.0 },
            },
        },
        pictures = {
            layers = {
                {
                    size     = 64,
                    filename = "__core__/graphics/icons/entity/character.png",
                    scale    = 0.5,
                    tint     = { r = 0.4, g = 1.0, b = 0.4, a = 1.0 },
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
                    tint          = { r = 0.4, g = 1.0, b = 0.4, a = 1.0 },
                },
            },
        },
        stack_size            = 1,
        weight                = rocket_lift,
        subgroup              = clone_subgroup,
        order                 = "z[bnm-character-clone]",
    },
    {
        type            = "recipe",
        name            = CLONE,
        enabled         = false,          -- unlocked by the rocket-silo technology
        energy_required = 30,
        category        = "crafting",     -- assembler-craftable; not hand-craftable
        ingredients     = {
            { type = "item", name = "processing-unit",       amount = 20 },
            { type = "item", name = "low-density-structure", amount = 20 },
            { type = "item", name = "electric-engine-unit",  amount = 10 },
        },
        results         = { { type = "item", name = CLONE, amount = 1 } },
    },
})

-- Unlock the clone alongside rocket silo -- you can't ship one anywhere until
-- you can launch rockets, so that's the natural gate.
local silo_tech = data.raw.technology["rocket-silo"]
if silo_tech then
    silo_tech.effects = silo_tech.effects or {}
    silo_tech.effects[#silo_tech.effects + 1] = { type = "unlock-recipe", recipe = CLONE }
end
