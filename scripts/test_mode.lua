-- scripts/test_mode.lua
-- The admin test commands' switch (map setting "Enable test commands",
-- bnm-test-commands; the commands are in scripts/test_commands.lua), and the
-- loud warning shown while it is on, so nobody starts or plays a real game
-- with it on by accident. While it is on, every player gets:
--   * a big red warning window when they join (dismissed until their next
--     join with "I understand"),
--   * a red "TEST COMMANDS ON" badge at the top of the screen that stays,
--   * big red text on the landing pen floor.
-- Everyone is told in chat when an admin turns the setting on or off.

local chat      = require("scripts.chat")
local pen_cells = require("scripts.pen_cells")

local M = {}

M.SETTING = "bnm-test-commands"

local WINDOW    = "bnm_test_warning"
local OK_BUTTON = "bnm_test_warning_ok"
local BADGE     = "bnm_test_badge"
local RED       = { r = 1, g = 0.2, b = 0.15 }
local WIDTH     = 560

-- Fonts from prototypes/fonts.lua: natively large, so they stay crisp.
local TITLE_FONT = "bnm-warning-title"
local PEN_FONT   = "bnm-warning-world"

local ICON  = "[img=utility/warning_icon] "
local TITLE = "TEST COMMANDS ARE ON"
local BODY  = "An admin has switched on Brave New MTS's test commands. "
    .. "/bnm-test-orbit grants research and creates items, and "
    .. "/bnm-test-kill-roboport destroys bases, so this is a test game, "
    .. "not a real one.\n\nTo play for real, an admin turns off \"Enable test "
    .. "commands\" in Settings > Mod settings > Map before the game starts."

--- True while the admin test commands are switched on.
function M.is_on()
    local setting = settings.global[M.SETTING]
    return setting ~= nil and setting.value == true
end

-- ─── Per-player GUI ────────────────────────────────────────────────────

local function add_text(parent, caption, font, color)
    local label = parent.add{ type = "label", caption = caption }
    label.style.font          = font
    label.style.font_color    = color
    label.style.single_line   = false
    label.style.maximal_width = WIDTH
    return label
end

local function show_window(player)
    local screen = player.gui.screen
    if screen[WINDOW] then return end
    local frame = screen.add{ type = "frame", name = WINDOW, direction = "vertical" }
    frame.auto_center = true
    add_text(frame, ICON .. TITLE, TITLE_FONT, RED)
    add_text(frame, BODY, "default-large", { r = 1, g = 1, b = 1 }).style.top_margin = 8
    local ok = frame.add{ type = "button", name = OK_BUTTON, caption = "I understand",
        style = "red_button" }
    ok.style.top_margin = 12
    ok.style.horizontally_stretchable = true
    player.print(chat.PREFIX .. "Test commands are ON: this is a test game.", { color = RED })
end

local function show_badge(player)
    local top = player.gui.top
    if top[BADGE] then return end
    local badge = top.add{ type = "label", name = BADGE, caption = ICON .. "TEST COMMANDS ON",
        tooltip = BODY }
    badge.style.font       = "default-large-bold"
    badge.style.font_color = RED
end

local function destroy(element)
    if element and element.valid then element.destroy() end
end

local refresh_pen_text  -- defined below

--- Show or remove one player's warning to match the setting. Runs on every
--- join, so the window comes back each time a player enters the game. The pen
--- text is refreshed too: MTS creates the landing pen lazily, so it may not
--- have existed when the setting was switched on.
function M.refresh_player(player)
    if not (player and player.valid) then return end
    refresh_pen_text()
    if M.is_on() then
        show_window(player)
        show_badge(player)
        return
    end
    destroy(player.gui.screen[WINDOW])
    destroy(player.gui.top[BADGE])
end

-- ─── Landing pen text ──────────────────────────────────────────────────

--- Draw or remove the big text on the landing pen floor, north of the
--- pen's centre where waiting players spawn.
function refresh_pen_text()
    local text = storage.bnm_test_pen_text
    if not M.is_on() then
        if text and text.valid then text.destroy() end
        storage.bnm_test_pen_text = nil
        return
    end
    if text and text.valid then return end
    local pen = pen_cells.surface()
    if not pen then return end
    storage.bnm_test_pen_text = rendering.draw_text{
        text = TITLE, surface = pen, target = { 0, -9 }, color = RED,
        font = PEN_FONT, alignment = "center", vertical_alignment = "middle",
    }
end

--- Bring every warning in line with the setting: the pen text and each
--- connected player's GUI (offline players catch up when they join).
function M.refresh_all()
    refresh_pen_text()
    for _, player in pairs(game.connected_players) do M.refresh_player(player) end
end

-- ─── Events ────────────────────────────────────────────────────────────

local function on_setting_changed(event)
    if event.setting ~= M.SETTING then return end
    M.refresh_all()
    local player = event.player_index and game.get_player(event.player_index)
    local who = player and player.name or "The server"
    game.print(chat.PREFIX .. who .. " turned test commands " .. (M.is_on() and "ON." or "off."),
        { color = RED })
end

--- Called from control.lua's single on_gui_click dispatcher.
function M.on_gui_click(event)
    local el = event.element
    if not (el and el.valid and el.name == OK_BUTTON) then return end
    destroy(el.parent)  -- the window; the badge stays while the setting is on
end

function M.register()
    script.on_event(defines.events.on_runtime_mod_setting_changed, on_setting_changed)
end

return M
