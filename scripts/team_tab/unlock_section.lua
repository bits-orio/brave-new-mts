-- scripts/team_tab/unlock_section.lua
-- The team tab's soft-lock warning, and the one-time, leader-only "I know what
-- I am doing" button that makes the locked power core of every base minable
-- (except the permanent roboports and the planet-tuned copies, which no item
-- can place again).

local starter_base = require("scripts.starter_base")
local chat         = require("scripts.chat")
local widgets      = require("scripts.team_tab.widgets")

local M = {}

local UNLOCK_BUTTON = widgets.PREFIX .. "unlock"

-- Mirrors the power core (scripts/base/power_core.lua): solar panels,
-- accumulators, substations, lamps, lightning collectors (Fulgora) and the
-- display panel, plus the planet-tuned copies (is_tuned), which stay locked
-- even after the unlock. The sign is part of the core, so every string says
-- so the same way (CORE). STAYS_LOCKED is what the unlock never frees: the
-- roboport (scripts/base/builder.lua) and the tuned copies. README.md ("The
-- base is permanent") and docs/portal.md (Features) repeat these rules and
-- cannot be built from here: change them together.
local CORE         = "power core (warning sign included)"
local STAYS_LOCKED = "The central roboports and the green-tinted, planet-tuned "
    .. "buildings stay locked, because nothing can place one again."

local WARNING =
    "You can already mine and redesign most of your bases. The power core "
    .. "stays locked: solar panels, accumulators, substations, lamps, lightning "
    .. "collectors and the power warning sign, so you can't accidentally kill "
    .. "your own power and strand your team.\n\n"
    .. "Unlocking lets you mine / deconstruct that power core too, on every base "
    .. "your team has or founds later, to rebuild it your way. " .. STAYS_LOCKED
    .. " The tuned buildings are the panels, accumulators, radar and inserter "
    .. "made for their planet.\n\n"
    .. "[color=1,0.5,0.2]Warning:[/color] if you remove your power before "
    .. "replacements are running, your team can be soft-locked: a rescue only "
    .. "refills the roboport, and with no power it runs dry again. This is one-way."

local UNLOCKED_NOTE = "[color=0,1,0]Your " .. CORE .. " is now mineable on every "
    .. "base. " .. STAYS_LOCKED .. "[/color]"

local UNLOCKED_PRINT = chat.PREFIX .. "Power core unlocked on every base: it can "
    .. "now be mined / deconstructed. " .. STAYS_LOCKED
    .. " Be careful not to soft-lock the team."

local UNLOCK_TOOLTIP = "Make the locked " .. CORE .. " mineable on every base. "
    .. STAYS_LOCKED .. " One-way."

--- The Power core panel: the warning, then the unlocked note, or the button
--- for the leader.
function M.build(player, parent)
    local body = widgets.section(parent, "Power core")
    widgets.label(body, WARNING)
    if starter_base.is_unlocked(player.force.name) then
        widgets.label(body, UNLOCKED_NOTE)
    elseif widgets.is_leader(player) then
        body.add{ type = "button", name = UNLOCK_BUTTON,
            caption = "I know what I am doing", tooltip = UNLOCK_TOOLTIP }
    end
end

--- nil for another section's element; true (rebuild the tab) for the button.
function M.on_click(player, el)
    if el.name ~= UNLOCK_BUTTON then return nil end
    if not widgets.is_leader(player) then return true end
    starter_base.unlock_minable(player.force.name)
    player.force.print(UNLOCKED_PRINT)
    return true
end

return M
