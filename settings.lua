-- settings.lua
-- How many robots each team's starter roboport is seeded with. Runtime-global
-- so a server admin can tune it; changes apply to bases placed afterwards.

data:extend({
    {
        type          = "int-setting",
        name          = "bnm-construction-robots",
        setting_type  = "runtime-global",
        default_value = 50,
        minimum_value = 0,
        order         = "a",
    },
    {
        type          = "int-setting",
        name          = "bnm-logistic-robots",
        setting_type  = "runtime-global",
        default_value = 50,
        minimum_value = 0,
        order         = "b",
    },
})
