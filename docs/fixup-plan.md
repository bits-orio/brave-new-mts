# Brave New MTS: fix-up plan for the Space Age server run

Goal: a one-week public server running Brave New MTS with Space Age, where
every planet works for a character-free team and nothing a normal player does
strands them. This file is the task list and the design contract the code
follows. `docs/` is not shipped in the mod zip.

Status keys: `todo`, `done`, `spike` (investigation, finished), `manual` (needs
a real game client), `ask` (author decides before it ships).

## Decisions (made by the author)

| Topic | Decision |
|---|---|
| Planet power | Keep the human-designed Nauvis footprint everywhere. Swap in uncraftable, planet-tuned panels and accumulators in the same slots. Mining one returns an ordinary vanilla item. |
| Tuned copies and the unlock | Planet-tuned entities (the generated `bnm-*` panels and accumulators, `bnm-radar`, `bnm-inserter`) stay locked even after the team unlocks its power core; only vanilla core entities become minable. |
| Fulgora | Lightning-based power: one vanilla lightning collector (in a panel slot) plus tuned accumulators, vanilla panels kept (measured design D1). |
| Power margin | Sustained total (idle included): Nauvis ~855 kW measured, Gleba and Fulgora at least 1.08 MW, Aquilo at least 1.30 MW. Vulcanus keeps vanilla panels (~3.8 MW). |
| Outpost loss | Only the home (first) base's roboport eliminates the team. Losing an outpost roboport wipes that outpost; another clone re-founds it. |
| Re-founding | Never lose the fresh planet kit or salvage: place the pad before any delivery, stock the kit first, then deliver the salvage into every logistic chest the base built plus the pad's inventory, and spill what still does not fit near the roboport for the robots. Player-built entities swept from the site come back as their placing item; the old base's own entities (up to one base's count of each blueprint name after substitution, and the pad, at normal quality) do not. The code leaves requester and buffer chests out (see step 7 below): the author to confirm. |
| Forgetting a home | `/bnm-forget-base` refuses a home base: a home cannot be re-founded, and `/mts-disband` is the way to end that team. |
| Reconnect view | A reconnect returns the remote view to the spot the player was looking at on their team's own (non-platform) surface, not only to the same surface. |
| Clone tech | Prerequisite `rocket-silo` only, red/green/blue science. |
| Off-world kit | A cargo landing pad plus a short planet-specific kit. Nauvis-only items dropped off-world. |
| Landing pad spot | Below the south wall, centred under the roboport, with a 3-tile gap between wall and pad. |
| Blueprints | No change. MTS blocks blueprint imports by default, but players create blueprints in game, which is enough. |
| MTS interface | Any change is proposed to the author first, never made unasked. |

## Measured facts (headless rig, Factorio 2.0.77, MTS 0.6.6)

- Idle draw of the starter base is about 255 kW with MTS's default passive
  radars (roboport 200, radar 50, lamps, inserter). It is about 505 kW if a
  server turns `mts_passive_radars` off.
- Sustained totals of today's base: Nauvis 855 kW, Vulcanus 3807 kW, Gleba
  504 kW, Fulgora about 450 kW (lightning is random), Aquilo 10 kW.
- Tuned bases (3% buffer margin, 6 cycles, 3 rounds): Gleba 1091 kW, Aquilo
  1313 kW sustained, idle 256 kW on both. Solar averages 1260 and 1512 kW, so
  both are storage-bound, as modelled.
- On Aquilo the roboport, radar and inserter freeze on the tick they are
  placed. A frozen roboport has no logistic network, so nothing can ever be
  built there.
- Busy robots add roughly 170 to 830 kW of recharge load on top of idle. The
  roboport shares power with every other consumer on the network.
- Fulgora lightning strikes only between dusk and dawn. Robots outside
  attractor cover get struck (about 33 per game hour of nonstop flying).
- A platform that flies to a planet creates the planet surface with no
  generated chunks. A script-made platform does not create it.
- Without a cargo landing pad a remote-only team has no practical way to get
  items down to a planet.
- Construction robots deconstructing a trigger target (rocks, stromatolites,
  icebergs, ruin vaults) completes the research trigger, provided a chest in
  the network has space.

Tooling: `tools/rig/` (harness, power test, Fulgora lightning lab),
`tools/syntax_check.py` (Lua 5.2 parse of every mod file).

## Design contract

### Planet profiles (data stage)

`data-final-fixes.lua` runs after MTS has created its per-team planet copies
(`mts-<planet>-<slot>`). For every planet prototype it writes a profile into
a `mod-data` prototype named `bnm-planet-profiles`:

```lua
data = { planets = { ["mts-gleba-3"] = {
  base         = "gleba",                -- MTS copy name stripped of "mts-" and "-<slot>"
  solar_panel  = "bnm-solar-panel-gleba", -- nil = keep vanilla
  accumulator  = "bnm-accumulator-gleba", -- nil = keep vanilla
  fulgora      = false,                  -- true = lightning layout D1
  freezing     = false,                  -- planet.entities_require_heating
} } }
```

Runtime looks a surface up by `surface.planet.name`; a surface with no planet
gets the Nauvis profile.

Prototype rules, per base planet (solar power `s` in percent, day length `d`
in ticks, Nauvis `d0 = 25200`):

- `s >= 100`: vanilla panels and accumulators (Nauvis, Vulcanus).
- Fulgora (base name `fulgora`): `bnm-accumulator-fulgora`, buffer 10 MJ,
  input 1 MW, output 300 kW. Vanilla `lightning-collector` in one panel slot.
  Vanilla panels elsewhere.
- Other `s < 100`: margin `m = 1.5` if `s <= 5`, else `1.25`.
  - `bnm-solar-panel-<base>`: output `60 kW * (100 / s) * m`.
  - `bnm-accumulator-<base>`: buffer `5 MJ * max(1, d / d0) * m * 1.03`, input
    and output flow `300 kW * m`. The extra 3% covers the lamps' night draw,
    which does not scale with `m`: without it the model gives Gleba 1071 kW and
    Aquilo 1288 kW, just short of the targets.
  - Gleba: 150 kW panels, 9.20 MJ accumulators (measured 1091 kW sustained).
    Aquilo: 9 MW panels (90 kW in Aquilo's 1% sun), 22.07 MJ accumulators
    (measured 1313 kW).
- Freezing planets: `bnm-radar` and `bnm-inserter`, copies with
  `heating_energy = "0kW"`.
- `bnm-roboport`: `heating_energy = "0kW"` on every planet.

Every generated entity: deep copy of the vanilla prototype, no item, no
recipe, no `placeable_by`, `minable.result` = the vanilla item, flag
`not-blueprintable`, `create_ghost_on_death = false`, a light green tint like
the roboport, locale name with the planet name as a parameter.

### Base placement (runtime)

`starter_base.place(force_name, surface, opts)` returns true only when a base
with a live roboport was built. `opts.outpost = true` marks an off-world base.

1. Force-generate chunks around the base (`CHART_CHUNK_MARGIN + 1`).
2. Clear enemies (force `enemy`) inside the roboport's construction area (a
   square of half-width `construction_radius`, not a circle).
3. Sweep leftovers of the same force in the footprint and pad area (a lost
   outpost being re-founded) into the salvage pool, a script inventory that
   takes whole stacks, so an item keeps its data (an equipment grid, a
   set-up blueprint). An entity beyond one base's count of its name (a
   blueprint name after the swaps, or the pad), or not normal quality, is
   something the team built: it is mined, so it comes back as the item that
   places it (a vehicle's with its grid) along with what it holds, belt
   lanes and inserter hand included. The old base's own entities and what no
   item places (ghosts) are emptied and destroyed. A replacement the team
   built for a destroyed base part counts as a base part: the new base
   re-supplies it. Spider legs are skipped (the body takes them along, and a
   spider parked outside the site is left alone); nothing that cannot be
   destroyed yet (a rail under a train) is touched, and whatever failed is
   tried once more after the rest.
4. Substitute entities per profile (panels, accumulators, Fulgora collector at
   the panel slot (3.5, -1.5) placed at (3, -1), radar, inserter). Compute the
   roboport offset before substituting.
5. Build, passing each blueprint entity's own settings to `create_entity`
   (request filters, display panel text, etc.). The display panel text comes
   from code, per planet.
6. Outposts: place a `cargo-landing-pad` centred under the roboport, its top
   edge 3 tiles below the bottom wall, on refined concrete. It is minable (not
   part of the locked core).
7. Kits, before any salvage: home gets the Nauvis kit and MTS admin items,
   outposts the planet kit only. A kit spreads over all passive provider
   chests, then storage chests, then the logistic network, and logs anything
   left over. Then the salvage pool (crash loot at home, a lost outpost's
   leftovers): storage, passive provider and active provider chests, then
   the pad's main inventory, then the network. What still does not fit is
   spilled at the roboport in whole-stack piles, marked for deconstruction by
   the team, so its robots carry it in as chests free up. Requester and
   buffer chests get no salvage, a deliberate narrowing of the decision:
   nothing takes an unrequested item back out of either (a requester takes
   from a buffer only when set to), and the roboport's feeder (the requester
   asking for 50 + 50 robots) would lose room for the robots it requests. On
   the ground, the same items reach storage once there is room.
8. The power core stays locked unless the team already unlocked it.
   Lightning attractors are part of the core. Planet-tuned copies (no item
   places them) are locked on every base, unlocked or not; only losing their
   outpost frees them for salvage.
9. `storage.bnm_base[surface]` records `home = true` for the first base of a
   force, `outpost = true` otherwise.

Outpost kits (chest contents; the pad is placed as an entity):

| Planet | Items |
|---|---|
| All outposts | medium-electric-pole 20, transport-belt 100, inserter 10, pipe 10 |
| Vulcanus | electric-mining-drill 3, roboport 1, construction-robot 10, steel-chest 4 |
| Fulgora | electric-mining-drill 2, roboport 2, construction-robot 15, lightning-rod 10, steel-chest 4 |
| Gleba | gun-turret 6, firearm-magazine 200, roboport 1, construction-robot 10 |
| Aquilo | heating-tower 1, heat-pipe 20, solid-fuel 50, electric-mining-drill 1 |
| Other planets | roboport 1, construction-robot 10 |

Relay roboports are there because the first research trigger on Vulcanus
(calcite) and Fulgora (ruin vault) measured just outside the 110-tile
construction radius on one seed.

Public functions `starter_base` exposes to events: `place`, `lose_outpost`,
`forget_surface`, `cleanup_force`, `profile_for`, `base_for`,
`add_items_to_spawned_bases` (home bases only), `unlock_minable`,
`is_unlocked`, `migrate`.

## Tasks

Every status below was re-checked against the code on `space-age-fixup` as of
this pass (2026-09-29): README, `docs/portal.md`, `docs/HOSTING.md`,
`changelog.txt`, `tools/portal_meta.json` and `locale/en/locale.cfg` all still
match what the code does. A later review pass added B13, B14, C11 and C12.

### Spikes (finished)

| ID | Task | Status |
|---|---|---|
| S1 | Headless harness and per-planet power measurement | spike |
| S2 | Fulgora lightning design by measurement (D1) | spike |
| S3 | Establish-base path and landing pad delivery | spike |
| S4 | Planet kit research (first research triggers, useless items) | spike |
| S5 | Adversarial audit of the whole mod: 42 findings, 37 confirmed | spike |

### A. Data stage

| ID | Sev | Task | Status |
|---|---|---|---|
| A1 | blocker | `bnm-roboport`: `heating_energy = "0kW"`, no ghost on death, fix the "it is minable" header comment | done |
| A2 | blocker | Planet power prototypes and `bnm-planet-profiles` mod-data in `data-final-fixes.lua` | done |
| A3 | high | Clone tech: prerequisite `rocket-silo`, red/green/blue, rewrite the tank comment | done |
| A4 | medium | `locale/en/locale.cfg`: settings, roboport, clone item and tech, generated entities | done |
| A5 | low | `info.json`: require `multi-team-support >= 0.6.6` | done |

### B. Starter base (`scripts/starter_base.lua`, `scripts/blueprints.lua`)

| ID | Sev | Task | Status |
|---|---|---|---|
| B1 | medium | Profile lookup from mod-data; drop substring planet matching; oil node on the Nauvis profile only | done |
| B2 | blocker | Per-planet substitutions (panels, accumulators, Fulgora collector, radar, inserter); remove the lamp-to-rod swap | done |
| B3 | high | Force-generate chunks before placing (off-world surfaces start with none) | done |
| B4 | blocker | Home and outpost bases; outpost kits; landing pad 3 tiles below the south wall | done |
| B5 | medium | MTS admin items to the home base only; delivery with overflow across chests | done |
| B6 | medium | A base founded after the unlock is created unlocked | done |
| B7 | high | Clear enemy nests and worms within the construction radius at placement | done |
| B8 | medium | Pass blueprint entity settings to `create_entity` (the roboport feeder request was lost); per-planet display panel text that is accurate (bots slow to 20%, they do not crash) | done |
| B9 | medium | Lightning attractors belong to the locked power core; fix core comments | done |
| B10 | high | `lose_outpost`, re-found sweep of leftovers, `forget_surface` | done |
| B11 | low | Bot count fallback 50, matching the setting default | done |
| B12 | medium | Migration for 0.1.x saves: mark home bases, provider lists | done |
| B13 | high | Re-founding never loses the kit or salvage: pad and kit first, salvage into every storage and provider chest and the pad, spill the rest for the robots; player-built entities in the site come back as items (`scripts/item_delivery.lua`) | done |
| B14 | medium | Planet-tuned copies stay locked after the unlock; the team tab, README, portal, locale and changelog say so | done |

### C. Events and lifecycle

| ID | Sev | Task | Status |
|---|---|---|---|
| C1 | blocker | Establish base: resolve the planet via `game.planets`, create the surface on click, drop the `speed ~= 0` test, accept any clone quality, consume the clone only after success, require the hub's force, pass `mod`, report an MTS milestone, clearer reasons | done |
| C2 | blocker | Roboport loss: home eliminates the team, outpost calls `lose_outpost` and tells the team | done |
| C3 | high | Empty each parked body once, not on every reconnect (blueprints were being deleted); editor guard; header comment | done |
| C4 | medium | Force-change handler uses `get_effective_force`, so MTS's spectate hop no longer unparks the player; re-centre the view afterwards | done |
| C5 | low | Surface-arrival handler ignores the map editor and other teams' surfaces; remember the last own surface viewed and restore it on reconnect | done |
| C6 | low | Pen cells: 12 slots per cell, evict bodies from a released team's cell, reset its label | done |
| C7 | low | Team tab: pass `mod`, make the unlock text list what is really locked | done |
| C8 | medium | Admin commands (admin or server console only): `/bnm-status`, `/bnm-repark`, `/bnm-forget-base` | done |
| C9 | low | `on_pre_surface_deleted` forgets base state for that surface | done |
| C10 | medium | `control.lua` wiring; call `starter_base.migrate`; record current parked bodies so the first reconnect after the update does not empty them | done |
| C11 | medium | `/bnm-forget-base` refuses a home base and points at `/mts-disband`; `docs/HOSTING.md` no longer says an arriving player re-founds a home | done |
| C12 | low | `on_pre_player_left_game` stores the spot a remote-view player was looking at on their own ground; the reconnect's `park` views it once | done |

### D. Docs and portal

| ID | Sev | Task | Status |
|---|---|---|---|
| D1 | doc | README: AI sentence to a bottom Development section with the standard wording; fix the minable, every-surface, settings-type, colour and Aquilo claims; describe clones and outposts; GPL-3.0-or-later | done |
| D2 | doc | `docs/portal.md`: same fixes, honest Status, clone in Features, MDW described as a separate game mode | done |
| D3 | doc | `tools/portal_meta.json`: drop the `Character` tag, keep every summary token and add the missing search words, note why the category is Scenarios | done |
| D4 | doc | Changelog 0.2.0 | done |
| D5 | doc | `docs/HOSTING.md`: passive radars, blueprint imports, Fulgora lightning and bots, clone flow, admin commands, manual test checklist | done |
| D6 | doc | Stale comments (`permissions.lua` movement clamp, `blueprints.lua` header, `remote_player.lua` header) | done |

### E. Verification

| ID | Task | Status |
|---|---|---|
| E1 | Commit the rig harness and Fulgora tooling | done |
| E2 | Rig regression: power per planet against targets, Aquilo roboport not frozen and a ghost gets built, establish on a surface that does not exist yet, pad delivery, outpost loss and re-found, home loss eliminates, save and reload with no errors; then (B13, C11, B14, C12) re-found over full chests, forget-base on a home, unlock keeps tuned copies locked, reconnect view with a simulated player; placing twice builds once; a re-found keeps vehicles' equipment and items' data | done — `tools/rig/regress.py` + `tools/rig/lua/regress*.lua`, 15/15 checks pass; see Results below |
| E3 | Client checklist for the author: reconnect keeps inventory blueprints, spectate a rival and come back, establish from the hub GUI, remote view of a new outpost, a reconnect returns the view to the spot the player was looking at (not the roboport), a member kicked (or whose team ended) while offline reconnects outside the team's cell | manual |

### Release

| ID | Task | Status |
|---|---|---|
| R1 | Bump to 0.2.0 and release to the portal | ask |
| R2 | Sync the portal description and metadata | ask |

### Proposals for MTS (not made; for the author)

- Sweep stale hub widgets and team tabs from players' GUIs when their
  registering mod is gone (BNM now passes `mod`, which covers MTS's registry).
- A `get_planet_owner(planet_name)` query that works before the planet's
  surface exists.
- The same AI-disclosure wording fix in the MTS, diggy and land-title-registry
  READMEs.
- `docs/MTS_API.md` ("Subscribing") says `remote.call` is not legal in
  `on_load` and suggests a one-shot `on_nth_tick(1)`. On 2.0.77 only the main
  chunk forbids it: `get_event_id` works in `on_load` (measured), and that is
  the pattern BNM now uses (`scripts/mts_events.lua`). The one-shot tick is not
  join-safe (a client joining later never runs it), and the note steers
  consumers toward caching ids in storage, which breaks when the ids shift.
  mts-expanse caches the ids the same way.

### Refuted during the audit (no action)

Roboport creation failure soft-lock; rod coverage on the current layout (moot
under D1); Vulcanus demolisher territory at spawn; changelog missing the
construction-robotics grant; extra portal tags.

## Results

`tools/rig/regress.py` (fifteen checks, about 2.5 minutes, driven by the
`tools/rig/lua/regress*.lua` helpers inside BNM's own state) passed 15/15 on
the final code on `space-age-fixup` (run as `--rig bnm-reg2 --ports
34343,27343`). Checks 9 to 12 were added with B13, C11, B14 and C12; run
against the code before those fixes, all four fail. Check 13 guards
`place()`'s idempotence. Checks 9, 10, 11 and 13 were also run against a
staged copy with one fault planted for each (no refund for what a team
built, no home refusal, an unlock that frees tuned copies plus locked walls,
no placed-flag guard): each fault failed the check meant for it. See [`tools/rig/README.md`](https://github.com/bits-orio/brave-new-mts/blob/master/tools/rig/README.md#regresspy-the-regression-suite)
for what each check verifies and how the fixtures work.

1. **Clean load:** 0 errors in the log. `bnm-planet-profiles` holds 105
   profiles, and those for `mts-<planet>-1` match the design contract above.
   Measured: Gleba panel 150 kW / accumulator 9.20 MJ, Aquilo panel 9000 kW /
   accumulator 22.07 MJ, Fulgora accumulator 10 MJ. `bnm-roboport`,
   `bnm-radar` and `bnm-inserter` need no heating.
2. **Power** (sustained total, idle about 255.8 kW):

   | Planet | Sustained | Next load fails at | Target | Result |
   |---|---|---|---|---|
   | Nauvis | 848.6 kW | 858.9 kW | about 855 kW (+-2.5%) | PASS |
   | Vulcanus | 3779.8 kW | 3826.3 kW | about 3807 kW (+-2.5%) | PASS |
   | Gleba | 1089.8 kW | 1097.3 kW | at least 1080 kW | PASS |
   | Aquilo | 1309.9 kW | 1317.3 kW | at least 1300 kW | PASS |
   | Fulgora | 2 bases x 20 days at 1091 kW | -- | at least 1080 kW, no blackouts | PASS: 0/40 blackout nights, lowest reserve 56.2 MJ |
3. **Aquilo:** after 10 game minutes the roboport, `bnm-radar` and
   `bnm-inserter` are all unfrozen, and the roboport has a network with 50
   bots. A transport-belt ghost 31 tiles out was built after 613 ticks.
4. **Establish:** `mts-vulcanus-1` had no surface before. After
   `establish_for`, the surface exists (owner team-1) with 81 chunks
   generated and 0 out-of-map tiles. The uncommon clone was consumed, the
   outpost was recorded, and the pad sits at (16, 30), 3 tiles below the
   south wall and centred under the roboport.
5. **Pad delivery:** the pad received 100 iron plate after 1215 ticks, and
   the hub was left with 0.
6. **Outpost loss:** team-1's slot stayed occupied and its home was kept.
   The record and `bases_placed` were cleared, and all 47 core entities
   became minable. A new clone re-founded the outpost: all 148 leftovers
   were swept, the base's entity counts match a fresh one, and the new
   storage chests hold exactly what the leftovers held, including the 37
   iron-gear-wheel marker. The new core is locked.
7. **Home loss:** MTS released team-1's slot, both of its surfaces were
   deleted, BNM forgot its bases, and BNM's `on_team_released` handler ran.
8. **Save and reload:** the reload had 0 errors (tick 255369 before, 255500
   after), and the Gleba outpost survived. After the reload, check 6 passed
   again for team-2 on Gleba (148 swept, pooled exactly), and check 7 also
   repeated: team-2 was disbanded.
9. **Re-found over full chests:** a team-3 Fulgora outpost had every chest
   filled with stone and its pad with coal (37,150 items), plus five things
   built above the pad: an iron chest of 100 copper plate, a fast belt
   carrying 2 iron plate, a small pole, a wooden chest of 30 wood and a
   stone wall. After the roboport died and the outpost was re-founded, the
   site held exactly one fresh base with its whole Fulgora kit in the chests.
   The new base held 32,596 items and 5,036 lay beside it in 104 piles, all
   marked for deconstruction. That is exactly what the site held, plus the
   fresh kit, plus one item for each extra except the stone wall, item by
   item and in total (37,632 before and after); the extras came back as one
   iron chest, fast belt, small pole and wooden chest. Run on the
   code before B13, the same check found none of the kit in the chests and
   18,402 of the expected items gone: the kit, 17,950 stone and coal that
   did not fit (only logged as "no room"), and the extras, which came back
   as nothing.
10. **Forget a home:** `/bnm-forget-base` over RCON refused team-13's home
    ("a home base cannot be re-founded ... /mts-disband team-13") both with
    its roboport standing and after `destroy()` removed it (no death event),
    and refused the outpost while its roboport stood. None of those changed
    a record, placed flag, entity count or core lock. With its roboport
    gone, the outpost's record and flag were forgotten and all 47 of its
    core entities became minable, as when a roboport dies; no other record
    or entity changed, and `place()` founded it again with a new roboport.
11. **Unlock:** team-14 unlocked with Gleba and Fulgora outposts standing,
    then founded Aquilo. Gleba's 40, Fulgora's 16 and Aquilo's 42 tuned
    copies (Aquilo's include `bnm-radar` and `bnm-inserter`) stayed
    non-minable, as did every `bnm-*` entity, the roboport included; the
    tuned copies are exactly the `bnm-*` entities but the roboport. The
    vanilla core (7, 31 and 7 entities) became minable. The 84 walls of each
    base were minable before and after.
12. **Reconnect view** (a stand-in player table: a real player needs a
    client): leaving while looking at (60.5, -30.25) on `mts-gleba-14`
    stored that spot, the reconnect's `park` viewed it, and the next
    re-park centred on the roboport at (16, 16). Nothing was stored on
    team-15's surface or outside remote view, and a spot on another
    surface was dropped. The real view on a client is in E3.
13. **Placing twice:** team-16's Nauvis home (148 entities) and Vulcanus
    outpost (149) were each followed, in the same tick, by `place()` with
    the same options and with the other kind. Both repeats returned false,
    and the entity count, unit-number sum, roboport, site contents and
    record table were unchanged. A call 60 ticks later also returned false
    and changed nothing, and each base was logged as placed once.
14. **Salvage keeps data:** team-17's Gleba outpost had an equipped
    spidertron (3 pieces, 50 iron plate aboard) and tank (2 pieces, 20 wood)
    beside its pad, six rails with a locomotive (10 coal) above it, an iron
    chest holding a spidertron item with 2 pieces, a modular armor with 1 and
    a set-up blueprint, a spidertron item with 1 piece in one of the base's
    own storage chests, and a spidertron with 1 piece parked outside the
    site, 2 legs inside. The re-found swept all 158 leftovers. The vehicles came
    back as items with all their equipment, the chests' items kept their
    grids and the blueprint its contents, the parked spider stood where it
    was with its equipment, no rail or locomotive was left, and the new base
    plus the ground held exactly what the site held, the kit and one item for
    each thing built. Run on the code before this fix, the same check found
    the in-site spidertron gone with its trunk (a leg came first and took it),
    the tank and the chest's spidertron flattened to plain items, the armor
    emptied, the blueprint blank, the parked spider deleted, and one rail
    still standing under the refunded locomotive.
15. **Migration:** a 0.1.3 world (commit 0ad9363) with the old single
   `provider` record ran `on_configuration_changed` with 0 errors. The
   record now has `home = true`, `outpost = false`, 4 valid providers and 4
   storage chests. The old key and the cached event ids are gone.

Two fixtures the suite relies on to make these checks real, neither a change
to MTS's or BNM's own code:

- **MTS storage.** A server with no players never claims a team slot, so
  MTS's `disband_team` does nothing for an unclaimed one. Each team that gets
  a home in the suite has `storage.team_pool[N] = "occupied"` set in MTS's
  storage, so "not disbanded" in check 6 and the disband in check 7 are real
  tests.
- **BNM storage.** Checks 7 and 8 add an empty `storage.park_index[force]`,
  which only BNM's `on_team_released` handler clears -- proof the handler
  ran, including after the reload.

One caveat the suite reports but does not fail on: after a disband, the
engine only schedules the team's platforms for deletion, about 17,500 ticks
later.
