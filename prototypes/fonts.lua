-- prototypes/fonts.lua
-- Natively large fonts for the test-commands warning (scripts/test_mode.lua).
-- A large font renders crisp; scaling a small one up is blurry.

data:extend({
    { type = "font", name = "bnm-warning-title", from = "default-bold", size = 34 },
    { type = "font", name = "bnm-warning-world", from = "default-bold", size = 72 },
})
