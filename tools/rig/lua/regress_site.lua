-- tools/rig/lua/regress_site.lua
-- regress.py's helpers for what the checks do in a base's site, loaded into
-- BNM's own state after regress.lua: a ghost for the robots and the machines
-- that must not freeze (Aquilo), full chests and things a team built (the
-- re-found), the items on the ground, and the lock state of every building.

REG = REG or {}
local R = REG

-- ─── Robots and machines ─────────────────────────────────────────────

--- Place a ghost of `name` somewhere buildable 20 to 40 tiles north of the
--- roboport, inside its construction area. Returns its position.
function R.place_ghost(surface_name, force_name, name)
    local s = game.surfaces[surface_name]
    local rp = R.roboport(surface_name, force_name)
    for dy = 20, 40 do
        for dx = -12, 12, 3 do
            local p = { x = rp.position.x + dx + 0.5, y = rp.position.y - dy + 0.5 }
            if s.can_place_entity{ name = name, position = p, force = force_name,
                                   build_check_type = defines.build_check_type.manual_ghost } then
                s.create_entity{ name = "entity-ghost", inner_name = name, position = p, force = force_name }
                return { x = p.x, y = p.y, distance = math.sqrt(dx * dx + dy * dy) }
            end
        end
    end
    error("no buildable spot for a " .. name .. " ghost on " .. surface_name)
end

--- Whether the ghost at `pos` has been built: { built, ghost }.
function R.ghost_state(surface_name, name, pos)
    local s = game.surfaces[surface_name]
    local area = { { pos.x - 0.4, pos.y - 0.4 }, { pos.x + 0.4, pos.y + 0.4 } }
    return { built = #s.find_entities_filtered{ name = name, area = area } > 0,
             ghost = #s.find_entities_filtered{ ghost_name = name, area = area } > 0 }
end

--- The radar and inserter of a base (by type) with their frozen state.
function R.machines(surface_name, force_name)
    local s = game.surfaces[surface_name]
    local out = {}
    for _, t in pairs({ "radar", "inserter" }) do
        local e = s.find_entities_filtered{ type = t, force = force_name,
            area = { { -20, -20 }, { 52, 52 } } }[1]
        out[t] = e and { name = e.name, frozen = e.frozen } or false
    end
    return out
end

-- ─── Re-founding over full chests ────────────────────────────────────

--- Fill every container a base left in its site (logistic chests and the pad,
--- found on the ground) with `filler`, and the pad with `pad_filler`. Returns
--- how many items went in.
function R.fill_site(surface_name, force_name, filler, pad_filler)
    local s = game.surfaces[surface_name]
    local st = R.site(s, force_name)
    local n = 0
    for _, e in pairs(s.find_entities_filtered{ area = st.area, force = force_name,
                                                type = { "logistic-container", "cargo-landing-pad" } }) do
        local item = e.type == "cargo-landing-pad" and pad_filler or filler
        n = n + e.insert{ name = item, count = 1000000 }
    end
    return n
end

--- Build what a team might have added around a base: `list` holds
--- { name, dx, dy, items = {name, count} } placed relative to the pad's
--- centre (the gap between wall and pad), each holding its items (a belt
--- carries them one per lane, at most two). Returns how many were built.
function R.build_extras(surface_name, force_name, list)
    local s = game.surfaces[surface_name]
    local pad = R.site(s, force_name).pad
    local n = 0
    for _, x in pairs(list) do
        local e = s.create_entity{ name = x.name, force = force_name,
            position = { pad.position.x + x.dx, pad.position.y + x.dy } }
        if e and x.items then
            if e.type == "transport-belt" then
                for lane = 1, x.items.count do e.get_transport_line(lane).insert_at_back({ name = x.items.name }) end
            else
                e.insert(x.items)
            end
        end
        if e then n = n + 1 end
    end
    return n
end

--- Items on the ground around a surface's base origin: { key = count } and
--- how many piles are marked for deconstruction (by the base's force: an
--- item on the ground is neutral, the mark is the force's).
function R.ground_items(surface_name)
    local s = game.surfaces[surface_name]
    local out, marked, piles = {}, 0, 0
    for _, e in pairs(s.find_entities_filtered{ type = "item-entity", area = { { -84, -84 }, { 116, 116 } } }) do
        local st = e.stack
        local key = st.quality.name == "normal" and st.name or (st.name .. "/" .. st.quality.name)
        out[key] = (out[key] or 0) + st.count
        piles = piles + 1
        if e.to_be_deconstructed() then marked = marked + 1 end
    end
    return { items = out, piles = piles, marked = marked }
end

-- ─── Locks ───────────────────────────────────────────────────────────

--- Count `e` under `key`, and under key .. "_minable" when it can be mined.
local function tally(out, key, e)
    out[key] = out[key] + 1
    if e.minable_flag then out[key .. "_minable"] = out[key .. "_minable"] + 1 end
end

--- File one site entity under R.locks' groups. "tuned" is BNM's own test for
--- a planet-tuned copy (no item places it); "bnm" goes by the bnm- name
--- prefix instead, the roboport included, so the two tests check each other.
local function tally_lock(out, e)
    if e.name:find("^bnm%-") then
        tally(out, "bnm", e)
        out.bnm_names[e.name] = true
    end
    if e.type == "wall" then tally(out, "walls", e) end
    if e.type == "roboport" then return end
    local items = e.prototype.items_to_place_this
    if not (items and items[1]) then
        tally(out, "tuned", e)
        out.tuned_names[e.name] = true
    elseif R.is_core(e) then
        tally(out, "core", e)
    end
end

--- The lock state of a base: its power core split into planet-tuned copies
--- and vanilla core entities, every bnm-* entity, and its walls (never part
--- of the core). Counts, how many of each are minable, and the names seen.
function R.locks(surface_name, force_name)
    local s = game.surfaces[surface_name]
    local out = { tuned = 0, tuned_minable = 0, core = 0, core_minable = 0, bnm = 0, bnm_minable = 0,
                  walls = 0, walls_minable = 0, tuned_names = {}, bnm_names = {} }
    for _, e in pairs(s.find_entities_filtered{ area = R.site(s, force_name).area, force = force_name }) do
        if R.in_base(e) then tally_lock(out, e) end
    end
    return out
end

return true
