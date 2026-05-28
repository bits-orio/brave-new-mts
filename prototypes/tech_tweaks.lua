-- prototypes/tech_tweaks.lua
-- Hide technologies that serve no purpose for character-free overseer teams.
-- BNM players never control a body on the team surface, so character-only
-- bonuses (mining speed, etc.) are dead research. We hide + disable rather than
-- delete them, so any other tech that lists one as a prerequisite still loads.

local USELESS = {
    "steel-axe",  -- character-mining-speed: there's no character to mine
    "health",
}

for _, name in pairs(USELESS) do
    local tech = data.raw.technology[name]
    if tech then
        tech.hidden  = true
        tech.enabled = false
    end
end
