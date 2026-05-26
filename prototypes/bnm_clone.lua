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

data:extend({
    {
        type                  = "item",
        name                  = CLONE,
        localised_name        = { "", "Character Clone" },
        localised_description  = { "",
            "Ship one to a planet your team's space platform has reached, then "
            .. "press \"Establish base\" in the platform hub to found your "
            .. "overseer base there. Weighs a full rocket on its own." },
        icon                  = "__core__/graphics/icons/entity/character.png",
        icon_size             = 64,
        stack_size            = 1,
        weight                = rocket_lift,
        subgroup              = "intermediate-product",
        order                 = "z[bnm-character-clone]",
    },
    {
        type            = "recipe",
        name            = CLONE,
        enabled         = true,           -- available from the start (tune as needed)
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
