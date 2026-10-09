-- settings.lua
-- How many robots each team's starter roboport is seeded with. Runtime-global
-- so a server admin can tune it; changes apply to bases placed afterwards.
-- Names and descriptions: locale/en/locale.cfg.

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
    -- Rescues each team may spend on a base whose roboport ran out of power
    -- (scripts/rescue.lua). Raising it gives every team more at once. At most
    -- 10, so the team tab's cards fit in three rows.
    {
        type          = "int-setting",
        name          = "bnm-rescues-per-team",
        setting_type  = "runtime-global",
        default_value = 3,
        minimum_value = 0,
        maximum_value = 10,
        order         = "c",
    },
    -- Admin test shortcuts (scripts/test_commands.lua). Off on a real server.
    {
        type          = "bool-setting",
        name          = "bnm-test-commands",
        setting_type  = "runtime-global",
        default_value = false,
        order         = "z",
    },
})
