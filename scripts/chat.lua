-- scripts/chat.lua
-- How BNM talks to players in chat: the prefix every BNM message starts with,
-- so players can tell BNM's messages from MTS's and the game's, and the one
-- way a message names a planet. A leaf: it requires nothing.

local M = {}

M.PREFIX = "[Brave New MTS] "

--- A surface as a message names it: its planet's localised name, or the
--- surface name for a surface with no planet. A LocalisedString, so it goes
--- in a { "", ... } message, never a plain `..` concatenation.
function M.planet_label(surface)
    return surface.planet and surface.planet.prototype.localised_name or surface.name
end

return M
