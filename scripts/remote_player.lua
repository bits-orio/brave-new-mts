-- scripts/remote_player.lua
-- Parks a team player's CHARACTER in their team's landing-pen cell and puts the
-- player into remote view of a team surface. The character never sets foot on
-- the team surface, so it can't chart or collide with it -- and remote-view
-- placement is naturally ghosts, which robots build. No instant-build and no
-- charting hacks; the god controller is used only for a moment, as a fallback
-- to create a missing character, and the player never plays in it.
--
-- Which surface and spot the view shows: scripts/remote_view.lua.

local pen_cells   = require("scripts.pen_cells")
local remote_view = require("scripts.remote_view")
local teams       = require("scripts.teams")

local M = {}

local is_team_force = teams.is_team_force

--- A player's real team force name. A member spectating a rival sits on the
--- 'spectator' force while MTS remembers their team; mts-v1 resolves that.
function M.effective_force(player)
    local iface = remote.interfaces["mts-v1"]
    if iface and iface.get_effective_force then
        return remote.call("mts-v1", "get_effective_force", player.index)
    end
    return player.force.name
end

--- True if the player belongs to a team, even while spectating another one.
function M.on_team(player)
    return is_team_force(M.effective_force(player))
end

--- True if BNM has parked this player for their current team membership.
function M.is_parked(player)
    return storage.home_surface ~= nil and storage.home_surface[player.index] ~= nil
end

-- Remembering what a player looks at, for their re-park (scripts/remote_view.lua).
M.remember_view      = remote_view.remember_view
M.remember_view_spot = remote_view.remember_view_spot

--- Lowest free slot index within a team's cell for this player (stable once set).
local function slot_for(force_name, player_index)
    storage.park_index = storage.park_index or {}
    storage.park_index[force_name] = storage.park_index[force_name] or {}
    local slots = storage.park_index[force_name]
    if slots[player_index] then return slots[player_index] end

    local used = {}
    for _, s in pairs(slots) do used[s] = true end
    local idx = 0
    while used[idx] do idx = idx + 1 end
    slots[player_index] = idx
    return idx
end

--- Empty each BODY once, keyed on its unit_number. A fresh body (first spawn,
--- respawn, the create_character fallback) may carry a loadout; a reconnect
--- re-parks the same body, whose inventory holds the player's own blueprints
--- and planners, and those must survive.
local function empty_once(player)
    local body = player.character
    if not (body and body.valid) then return end
    storage.emptied_body = storage.emptied_body or {}
    local emptied = storage.emptied_body
    if emptied[body.unit_number] then return end
    for number, owner in pairs(emptied) do  -- forget this player's old body
        if owner == player.index then emptied[number] = nil end
    end
    body.clear_items_inside()
    emptied[body.unit_number] = player.index
end

-- ─── Parking, step by step ─────────────────────────────────────────────

--- The team force of a player park() may act on, or nil: a connected player
--- on a team (not in the pen or spectating), with MTS loaded.
local function parkable_force(player)
    if not (player and player.valid and player.connected) then return nil end
    if not remote.interfaces["mts-v1"] then return nil end
    -- The map editor is observation: never pull an admin out of it.
    if player.physical_controller_type == defines.controllers.editor then return nil end
    local fn = player.force.name
    if not is_team_force(fn) then return nil end
    return fn
end

--- The surface to view. `team_surface`, the surface a player just arrived on,
--- becomes their home surface; without it (a reconnect or re-park) the view
--- is resolved as scripts/remote_view.lua describes. May be nil.
local function resolve_view(player, team_surface)
    storage.home_surface = storage.home_surface or {}
    if team_surface and team_surface.valid then
        storage.home_surface[player.index] = team_surface.name
        return team_surface
    end
    return remote_view.surface_for(player)
end

--- The landing pen, its team cells built, or nil.
local function landing_pen()
    pen_cells.ensure_built()
    local pen = game.surfaces["landing-pen"]
    return (pen and pen.valid) and pen or nil
end

--- Give the player an emptied body to park. MTS provides one on spawn; a
--- body is created for any path that doesn't.
local function ensure_body(player)
    if not player.character then
        player.set_controller{ type = defines.controllers.god }
        player.create_character()
    end
    empty_once(player)
end

--- Stand the body at `pos` in the pen and switch the player into remote view
--- of `surface`. The view's position is read here, after every guard, since
--- reading it uses up a reconnect's spot.
local function enter_remote_view(player, pen, pos, surface)
    player.teleport(pos, pen)
    if player.character then player.character.destructible = false end
    player.set_controller{
        type     = defines.controllers.remote,
        surface  = surface,
        position = remote_view.position_for(player, surface),
    }
end

--- Heal a record 0.1.x lost (its spectate hop ran unpark): a player parked
--- here is parked for this team, so is_parked and /bnm-status agree. Only
--- after a park succeeded: before it, a failed park would leave is_parked
--- true for a player who was never parked.
local function heal_home_record(player, fn, surface)
    if storage.home_surface[player.index] then return end
    storage.home_surface[player.index] = remote_view.team_home(fn) or surface.name
end

--- Park `player` for their team and view a team surface. `team_surface` is the
--- surface they just arrived on (it becomes their home surface); if omitted,
--- the view is resolved as scripts/remote_view.lua describes (a reconnect or
--- re-park). Returns the name of the surface viewed, or nil if nothing was
--- done. The pen is checked before a body is made and the cell after, so a
--- missing pen never creates a character.
function M.park(player, team_surface)
    local fn = parkable_force(player)
    if not fn then return nil end
    local surface = resolve_view(player, team_surface)
    if not (surface and surface.valid) then return nil end
    local pen = landing_pen()
    if not pen then return nil end
    ensure_body(player)
    local pos = pen_cells.park_position(fn, slot_for(fn, player.index))
    if not pos then return nil end
    enter_remote_view(player, pen, pos, surface)
    heal_home_record(player, fn, surface)
    log("[brave-new-mts] parked " .. player.name .. " in " .. fn
        .. " cell; viewing " .. surface.name)
    return surface.name
end

--- Re-park a player whose view was left off their team's surfaces (MTS's
--- spectate exit restores the camera onto the pen cell), but keep a view MTS
--- restored onto their own team's ground (a GPS-ping spectate).
function M.repark_if_away(player)
    if not (player and player.valid and player.connected) then return end
    if not remote.interfaces["mts-v1"] then return end
    local fn = player.force.name
    if not is_team_force(fn) or M.effective_force(player) ~= fn then return end
    if player.controller_type == defines.controllers.remote
            and remote_view.owned_surface(player.surface.name, fn) then
        return
    end
    M.park(player)
end

--- Release a player's parked slot and view state (on really leaving a team).
--- MTS's return_to_pen moves a CONNECTED player's body back to the selection
--- ring; an offline member's body leaves the cell when the team's slot is
--- released (pen_cells.evict_cell).
function M.unpark(player)
    if not (player and player.valid) then return end
    if storage.park_index then
        for _, team in pairs(storage.park_index) do
            team[player.index] = nil
        end
    end
    if storage.home_surface  then storage.home_surface[player.index]  = nil end
    if storage.last_view     then storage.last_view[player.index]     = nil end
    if storage.last_view_pos then storage.last_view_pos[player.index] = nil end
end

--- Drop a whole team's parked-slot bookkeeping when its slot is released, so a
--- team that recycles the slot starts cell-slot numbering from scratch instead
--- of inheriting the previous occupants' (now meaningless) assignments.
function M.cleanup_force(force_name)
    if storage.park_index then storage.park_index[force_name] = nil end
end

--- Migration (on_configuration_changed): mark every body already parked in a
--- cell as emptied, so the first reconnect after updating from a version that
--- emptied on every park keeps what the player stored since. Offline players'
--- bodies have no player attached, so they are found in the cells.
---
--- Also give every team member a home surface again. 0.1.x cleared it on each
--- rival spectate (its force check read player.force), and without it
--- is_parked stays false, so the return from spectating never re-parks them.
--- park() heals this on reconnect too, but a single-player load raises no
--- on_player_joined_game. Runs after starter_base.migrate, so team_home sees
--- the home flags.
function M.migrate()
    storage.emptied_body = storage.emptied_body or {}
    for _, body in pairs(pen_cells.parked_characters()) do
        if body.unit_number and not storage.emptied_body[body.unit_number] then
            storage.emptied_body[body.unit_number] = body.player and body.player.index or true
        end
    end

    storage.home_surface = storage.home_surface or {}
    if not remote.interfaces["mts-v1"] then return end
    for _, player in pairs(game.players) do
        local fn = M.effective_force(player)
        if is_team_force(fn) and not storage.home_surface[player.index] then
            storage.home_surface[player.index] = remote_view.team_home(fn)  -- nil: no home base yet
        end
    end
end

return M
