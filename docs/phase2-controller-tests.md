# Phase 2 — Controller / character empirical tests

Goal: confirm the core remote-only technique works **before** we rely on it.
The mod's plan is: destroy the player's character and put them in remote view,
with no god mode and no cheat (`scripts/remote_player.lua`). We need to verify
the engine actually lets a character-less player build via blueprints + bots.

Run these in a **throwaway** save with **Multi-Team Support** active (you do NOT
need Krastorio2 or this mod loaded — we're testing engine primitives directly).
Console use (`/c`) taints the save, so don't use your real server save.

In multiplayer, `game.player` is the local player running the command.

---

## Probe 0 — baseline

```
/c local p=game.player; local n; for k,v in pairs(defines.controllers) do if v==p.controller_type then n=k end end; game.print("controller="..n.." | character="..tostring(p.character~=nil).." | surface="..p.surface.name)
```
Expect: `controller=character | character=true`.

## Probe 1 — the mod's actual technique (destroy + remote view)

```
/c local p=game.player; local s,pos=p.surface,p.position; if p.character then p.character.destroy() end; p.set_controller{type=defines.controllers.remote, surface=s, position=pos}; local n; for k,v in pairs(defines.controllers) do if v==p.controller_type then n=k end end; game.print("controller="..n.." | character="..tostring(p.character~=nil))
```
Record what `controller=` prints. **Key question: does `set_controller{type=remote}`
succeed with NO backing character, or does it error / snap you elsewhere?**

Then observe manually:
- Can you pan the map / are you in remote view?
- **Hand-mine test:** try to mine a tree or rock. Expect: impossible (good).

## Probe 2 — can a character-less player place a ghost that bots build?

Give yourself a one-entity blueprint, then stamp it somewhere charted:
```
/c local p=game.player; local bp=p.cursor_stack; bp.set_stack("blueprint"); bp.set_blueprint_entities({{entity_number=1,name="transport-belt",position={x=0,y=0}}}); game.print("blueprint in cursor — try stamping it in remote view")
```
- Does a **ghost** appear when you click? (placement works)
- If you spawn a roboport with bots + a belt in a storage chest nearby, does a
  construction bot build the ghost? (This is the whole gameplay loop.)

Quick bot/roboport seed to test the build loop:
```
/c local p=game.player; local s=p.surface; local rp=s.create_entity{name="roboport",position={x=2,y=0},force=p.force,raise_built=true}; rp.energy=rp.electric_buffer_size; rp.get_inventory(defines.inventory.roboport_robot).insert{name="construction-robot",count=10}; local c=s.create_entity{name="storage-chest",position={x=4,y=0},force=p.force,raise_built=true}; c.insert{name="transport-belt",count=20}; game.print("roboport+bots+belts seeded")
```

## Probe 3 — respawn / death with no character

With no character you can't take damage, so death shouldn't occur. Confirm
`on_player_respawned` never fires in normal play. If MTS or the engine ever
hands the player a character back (e.g. on rejoin), our `make_remote` on
`on_player_joined_game` should strip it again — verify by reconnecting.

## Probe 4 — does remote-view surface switching fire on_player_changed_surface?

This decides whether first-arrival is a safe base-placement trigger
(`events/player_surface.lua`). Register a temporary logger, then switch the
surface you're viewing in remote view (needs ≥2 surfaces, e.g. a second team
surface or a platform):
```
/c script.on_event(defines.events.on_player_changed_surface, function(e) game.print("changed_surface -> "..game.players[e.player_index].surface.name) end)
```
- If merely *viewing* another surface in remote view prints `changed_surface`,
  first-arrival would place bases on planets you're only looking at → switch the
  trigger to the `mts-v1` `on_team_surface_created` event instead.
- If it only fires on real relocation, first-arrival is safe.

---

## What the results decide

| Result | Action |
| --- | --- |
| `set_controller{remote}` works, ghosts placeable, bots build | Technique confirmed — `remote_player.lua` stands as written. |
| remote controller needs a character / can't place ghosts | Fall back to: keep a hidden parked character + permanent remote view + a permission group blocking mining & crafting. |
| Probe 4 fires on view-switch | Move base-placement trigger to `on_team_surface_created`. |
