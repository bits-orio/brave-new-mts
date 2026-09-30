# Headless test rig for Brave New MTS

Scripted, headless tests of BNM on a real Factorio 2.0.77 server with Space Age,
driven over RCON. It builds on the shared rig in `~/factorio-dev/rig` (see its
README: `start-server.sh`, `stop-server.sh`, `rcon.py`). Everything here is
test-only. `tools/` is excluded from the release zip, and nothing in this
folder is ever written into the repo's mod code.

| File | What it does |
|---|---|
| `stage.sh` | Builds a mods dir: MTS 0.6.6 zip, a copy of the BNM working tree (or of a commit), and a `mod-list.json` |
| `hooks/bnm_rig_data.lua` | Test-only prototypes, injected into the staged copy by `stage.sh --hooks` |
| `probe.py` | RCON helper (library and CLI) that runs Lua in the level, BNM or MTS state |
| `lua/power_rig.lua` | In-game power sampler, loaded into the level state by `power_test.py` |
| `power_test.py` | Measures the starter base's sustainable power on every planet |
| `regress.py` | The regression suite: seventeen PASS/FAIL checks on a fresh server of its own |
| `lua/regress.lua` | `regress.py`'s helpers, loaded into BNM's state (this core first): place a base and read it back |
| `lua/regress_platform.lua` | Platforms made by script, the Establish core, pad deliveries, what `/bnm-test-orbit` leaves a team |
| `lua/regress_site.lua` | What the checks do in a site: a ghost, full chests, what a team built, the ground, the locks |
| `lua/regress_salvage.lua` | Vehicles, a train and items that carry data in and around a site, and where they are after a re-found |
| `lua/regress_records.lua` | BNM's base records as plain values, and placing a base twice |
| `lua/regress_player.lua` | A simulated player's leave and reconnect |

## Quick start

```sh
# 1. Stage (use --hooks for power tests: it adds the bnm-rig-load prototype)
tools/rig/stage.sh ~/factorio-dev/rig/mods-bnm-sp1 --hooks

# 2. Start a fresh server: rig name, game port, RCON port, mods dir
RIG_FRESH=1 ~/factorio-dev/rig/start-server.sh 2.0 bnm-sp1 34311 27311 ~/factorio-dev/rig/mods-bnm-sp1
grep ' Error \|brave-new-mts\]' ~/factorio-dev/rig/bnm-sp1.log   # only "Got EOF on stdin" is expected

# 3. Probe
tools/rig/probe.py --json 'game.tick'
tools/rig/probe.py --state bnm --json 'storage.bases_placed'

# 4. Measure power on every planet (about 5 minutes of wall time)
tools/rig/power_test.py --port 27311 --out /tmp/power_results.json
#    Fulgora's lightning is random: judge it over many cycles, with its own sweep
tools/rig/power_test.py --planets fulgora --sweep fulgora:700:1200 --cycles 20 --rounds 0 --out /tmp/fulgora.json
#    Re-print the table from a saved file, using the current pass/fail rule
tools/rig/power_test.py --summarize /tmp/power_results.json

# 5. Stop (it saves; the next start without RIG_FRESH=1 reloads that world)
~/factorio-dev/rig/stop-server.sh 27311
```

`stage.sh` copies the working tree, so uncommitted edits are tested. Re-run it
and restart the server after every change to the mod. Other options:
`--mts <zip-or-dir>` stages a different MTS (a source dir is symlinked),
`--rev <commit>` stages BNM as committed there (for a migration test), and
`--no-space-age` disables space-age, quality and elevated-rails.

To run the whole regression suite instead, see [regress.py](#regresspy-the-regression-suite).

## Calling BNM's internals from RCON

`/sc __brave-new-mts__ <lua>` runs a console command inside BNM's own Lua
state. That gives you BNM's `storage`, and every BNM module it has loaded
through `package.loaded`, keyed by file path:

```lua
/sc __brave-new-mts__ local sb = package.loaded["__brave-new-mts__/scripts/starter_base.lua"]
    sb.place("team-1", game.surfaces["mts-nauvis-1"])
```

In Python, `probe.bnm_mod("scripts.starter_base")` builds that expression, and
`Rig.sc(lua, state="bnm")` sends it. The same works for MTS
(`__multi-team-support__`, state `"mts"`), but treat MTS as read-only: an
interface change is proposed to its author, never made from here. No control-
stage hooks are needed. The only injected hook is data-stage.

The first `/sc` of every RCON session is swallowed by the "this disables
achievements" prompt. `probe.Rig` sends a warmup command for you.

## probe.py

```python
from probe import Rig, bnm_mod
rig = Rig(27311)
rig.sc('rcon.print(game.tick)')                     # raw output
rig.eval('game.surfaces["mts-nauvis-1"].daytime')   # decoded value (via JSON)
rig.eval('storage.bnm_base', state="bnm")
rig.run_file('lua/power_rig.lua')                   # multi-line Lua with comments is fine
rig.wait_ticks(600)
```

A Lua error raises `RuntimeError` with the engine's message.

## Surfaces and teams

MTS pre-creates `team-1` .. `team-20`. With Space Age each team has its own
planets, `mts-<planet>-<slot>` (for example `mts-nauvis-1` or `mts-vulcanus-3`), and
the engine creates their surfaces lazily. To get one without a player, do what
MTS's `planet_map.get_or_create_planet_surface` does:

```lua
local s = game.planets["mts-gleba-2"].create_surface()
s.request_to_generate_chunks({0, 0}, 3)
s.force_generate_chunk_requests()
```

`remote.call("mts-v1", "get_surface_owner", s.name)` then returns `"team-2"`.
MTS's reaper is off by default, so surfaces of teams with no players survive.
One exception: if a `bnm-roboport` dies, BNM disbands that team, and MTS
deletes all of the team's surfaces.

## power_test.py: how the measurement works

- **Test load.** `bnm-rig-load` (from `hooks/`) is a `secondary-input`
  electric-energy-interface. It sits in the same priority class as the
  roboport, radar and lamps, so it competes for power like a real machine. The
  vanilla EEI is `tertiary`, which makes it charge and discharge like an
  accumulator, so it is useless as a load.
- **Parallel runs.** Each planet gets one base per team slot. Slot 1 carries no
  test load (idle). Slots 2 to 9 carry 8 test loads. Slot 10 carries 100 MW,
  which reads the plant's raw energy per cycle. On Fulgora, slot 11 keeps
  construction bots flying (ghost belts placed and deconstructed in a loop) to
  see whether lightning hits robots.
- **One run.** Each run starts at noon (`daytime = 0`) with full accumulators
  and a full roboport. It runs `--cycles` day/night cycles (default 3) at
  `game.speed = 1000`, which is about 1,500 to 6,000 UPS depending on the number
  of bases. A sampler runs every 7 ticks and records the minimum accumulator and
  roboport energy, whether anything is frozen (`LuaEntity.frozen`), and every
  `on_entity_damaged` / `on_entity_died` event on the run's surface. At each
  noon it snapshots the network's `electric_network_statistics`:
  `input_counts` is consumption and `output_counts` is production, in joules.
- **Pass or fail.** A run passes only if:
  - in every cycle, the accumulators never drop below 0.1% of capacity,
  - in every cycle, the roboport ends at least as full as it started,
  - the test load receives at least 99.5% of what it asked for,
  - the accumulators are in steady state: summed over cycles 2 to n, they must not
    lose more than 0.5 MJ from noon to noon. Cycle 1 is excluded because its full
    noon start is not the steady-state noon level. Without this check, a load above
    the plant's energy per cycle (Gleba) passes a short run on its initial charge.
- **Sustained total.** For a passing run this is the measured average
  consumption over the cycles: idle draw plus the test load.
- **Refinement.** Later rounds re-run the sweep slots on the same bases, spread
  between the highest passing load and the lowest failing one. `--sweep
  PLANET:LO:HI` overrides a planet's first-round range. Running again on the same
  world reuses the bases that are already there (placement is idempotent).
- **Randomness.** Fulgora's lightning makes a single 3-cycle run noisy, and
  results are not monotonic in load. Use `--cycles 20 --rounds 0` and read how
  many cycles blacked out at each load.

Output is one JSON file with a report per run and round. Each report holds
per-cycle consumption and production per entity name (kW), the start, end and
minimum of accumulator and roboport energy, freeze times, damage and death
counts, and the `failed to place` lines from the server log, attributed to their
surface.

## regress.py: the regression suite

```sh
tools/rig/regress.py                      # all seventeen checks, about 3 minutes
tools/rig/regress.py --checks 4,6         # a subset (5 and 6 pull in 4)
tools/rig/regress.py --out /tmp/reg.json  # also write every check's numbers as JSON
tools/rig/regress.py --rig bnm-f4 --ports 34341,27341   # a second suite beside the first
```

It stages the working tree (`stage.sh --hooks` into `~/factorio-dev/rig/mods-bnm-reg`),
starts a fresh server named `bnm-reg` on game port 34332 and RCON 27332, runs the
checks in order and stops the server. `--rig NAME` and `--ports GAME,RCON` change
the server name (and so its mods dir `mods-NAME` and write-data `w-NAME`) and ports. Each check prints PASS or FAIL with the
numbers it judged, then a summary; the exit code is 0 only if all pass. A failing
check does not stop the others. It refuses to start while anything listens on
its RCON port; `--keep` leaves the server running at the end, `--no-stage` reuses
the staged mods dir.

| # | Check | Passes when |
|---|---|---|
| 1 | Clean load | No error in the log; `bnm-planet-profiles` holds the contract's profile for every `mts-<planet>-1`; the tuned prototypes exist |
| 2 | Power | Sustained total, idle included: Nauvis 855 kW and Vulcanus 3807 kW within 2.5%, Gleba >= 1080 kW, Aquilo >= 1300 kW; Fulgora: 2 bases x 20 days at >= 1080 kW with 0 blackout nights |
| 3 | Aquilo | After 10 game minutes the roboport, radar and inserter are not frozen, the roboport has a network, and a ghost 20 to 40 tiles out gets built |
| 4 | Establish | A script-made platform over `mts-vulcanus-1` (no surface yet) with an uncommon clone: `establish_for` creates the surface with at least 81 generated chunks, consumes the clone, founds an outpost, and its pad sits 3 tiles below the south wall, centred |
| 5 | Pad delivery | 100 iron-plate in the hub and a request on the pad: a cargo pod lands them |
| 6 | Outpost loss | `die()` on the outpost roboport: team-1 is not disbanded, the outpost is forgotten, its core became minable. A new clone re-founds it: the site holds exactly one fresh base, every leftover was swept, and the new storage chests hold exactly what the leftovers held |
| 7 | Home loss | `die()` on the home roboport: MTS disbands the team, deletes its surfaces, BNM forgets its bases and its `on_team_released` handler ran |
| 8 | Save and reload | Team-2 founds a Gleba outpost, the server restarts on its save with no error, then checks 6 and 7 again, which proves the handlers came back in `on_load` |
| 9 | Re-found over full chests | Team-3 founds a Fulgora outpost; every logistic chest is filled with stone and the pad with coal, and a few things are built in the gap above the pad (chests with items, a belt carrying plates, a pole, a stone wall and an inserter, both one past a base's worth of their name). After the roboport dies and the outpost is re-founded: the site holds one fresh base, the whole fresh kit is in its chests, and what is in the new base plus what lies on the ground equals what the site held, plus the fresh kit, plus one placing item per extra: item by item, and in total. The ground and the base gained exactly one of each extra's item. Every pile on the ground is marked for deconstruction |
| 10 | Forget a home | Team-13 has a home and an outpost. `/bnm-forget-base` over RCON refuses the home, naming `/mts-disband team-13`, both while its roboport stands and after it is lost to `destroy()` (no death event); it refuses the outpost while its roboport stands. None of those change any record, placed flag, entity or core lock. With its roboport gone, the outpost's record and flag are forgotten and its core, tuned copies included, becomes minable, as when its roboport dies; no other record changes, and `place()` can then found it again |
| 11 | Unlock | Team-14 founds Gleba and Fulgora outposts, unlocks its power core, then founds Aquilo. On all three the planet-tuned copies (no item places them; Aquilo's include `bnm-radar` and `bnm-inserter`) and every `bnm-*` entity, the roboport included, stay non-minable, and the tuned copies are exactly the `bnm-*` entities but the roboport. The vanilla core entities are minable. The walls, never part of the core, are minable before and after |
| 12 | Reconnect view | A stand-in player table on team-14 (a real player needs a client) goes through `remember_view_spot` and `park`: the spot it left on is stored and viewed once, the next re-park centres on the base, nothing is stored on a rival's surface or outside remote view, and a spot on another surface is dropped |
| 13 | Placing twice | Team-16 gets a home on Nauvis and an outpost on Vulcanus from `place()`, each followed in the same tick by `place()` again with the same options and with the other kind. The repeats return false, and the entity count, the sum of unit numbers (never reused), the roboport, the site's contents and the record table are unchanged. A third call 60 ticks later also returns false and changes nothing, and each base is logged as placed once |
| 14 | Salvage keeps data | Team-17 founds a Gleba outpost; an equipped spidertron and tank stand beside the pad, six rails with a fuelled locomotive cross the gap above it, an iron chest holds a spidertron item with equipment, an equipped modular armor and a set-up blueprint, one of the base's own storage chests holds another equipped spidertron item, and a spidertron is parked just outside the site with legs reaching in. After the roboport dies and the outpost is re-founded: both vehicles are back as items with all their equipment, the chests' items keep their grids and blueprint, the parked spider is untouched, no rail or locomotive stands in the site, every leftover was swept, and the new base plus the ground hold what the site held plus the kit plus exactly one placing item per thing built (6 rails) |
| 15 | Home founded again | Team-18 has a home and an outpost. `game.delete_surface` removes the home surface outside a disband: BNM forgets the home record and keeps the outpost. `place()` with no options (a member arriving) on the recreated surface records a home, so the team again has one home and its outpost |
| 16 | Test commands | Over RCON as the console, on team-20 (a home, slot occupied): `/bnm-test-orbit gleba team-20` refuses while `bnm-test-commands` is off and changes nothing. With it on, it researches `planet-discovery-gleba` and `bnm-character-clone`, unlocks `mts-gleba-20` and parks "BNM test: gleba" above it with 1 clone, the surface not yet created; again, still one platform, with 2 clones and nothing more researched, and the announcement tells the console a member of team-20 presses Establish base. Flown to `mts-nauvis-20`, the platform is brought back above Gleba with 3 clones; scheduled for deletion, it is left to die and a new one gets 1 clone. `establish_for` on that hub founds an outpost; `/bnm-test-kill-roboport mts-gleba-20` wipes it and the team keeps its slot and home. The same command on a surface with no base (and with no argument, never "on nil") answers with usage and changes no record; so does `/bnm-test-orbit` with an unknown planet or no argument, changing nothing. `/bnm-test-orbit gleba team-15`, a slot never claimed, is refused as "not a claimed team" and changes nothing, and with no team from the console there is "no team to act for" |
| 17 | Migration | A world made by 0.1.3 (commit 0ad9363, staged with `--rev`) with a home base, loaded by this code in the same write-data: `on_configuration_changed` runs with no error, the record gets `home`, a providers list and storage chests, and the old keys are dropped |

How it gets there:

- Checks 3 to 9 use teams 1 to 3 (`mts-<planet>-1` .. `-3`), checks 10 to 15 teams 13
  to 19, check 16 team-20; the power runs use slots 4 to 12, one base per slot on each planet, placed by `power_test.setup_run`
  (Nauvis as a home, everywhere else as an outpost). Slot 4 is the idle run; the
  others carry test loads that bracket the target, 8 in parallel.
- Establishing goes through the real core, `platform_hub.establish_for(force, hub)`,
  with the planet unlocked the way play unlocks it (its discovery tech researched,
  then MTS unlocks the team's copy). Roboports die by `die()` from the level
  state, so BNM's handlers see an ordinary `on_entity_died`.
- **Fixtures.** No slot is ever claimed on a server with no players, and MTS's
  `disband_team` skips an unclaimed slot. So each team that gets a home here
  (team-1 in checks 4 to 7, team-2 in check 8, team-20 in check 16) has its slot set to `"occupied"` in
  MTS's storage (a claimed team whose members are all offline), so "not
  disbanded" means something and a disband is real. Checks 7 and 8 also
  give the team an empty `storage.park_index` entry in BNM, which only BNM's
  `on_team_released` handler clears. This is test state in a throwaway world;
  MTS's code is never changed.
- Check 17 runs in its own world, `bnm-reg-mig` (mods in `mods-bnm-reg-mig`), on the
  same ports, after stopping `bnm-reg`.
- Check 12 creates the landing pen with MTS's own `get_or_create_surface` (in MTS's
  state), as a player's first landing would, since `park` needs the pen.
- Every check also scans the log lines written during it: an engine ` Error `
  (other than "Got EOF on stdin") or a BNM warning about a base it could not build
  fully (`failed to place`, `no room in the base's chests`, ...) fails the check.

## Gotchas

- `/sc` in the level state registers handlers such as `on_nth_tick(7)` and
  `on_entity_damaged` in memory only. After a server restart, re-run
  `RIG.start()` (power_test.py does this each time it starts).
- A roboport's power draw is a drain: neither `active = false` nor
  `disabled_by_script` stops it, so the base's 200 kW floor cannot be switched
  off. Both do stop a radar.
- The world is saved when the server stops and reloaded on the next start.
  Pass `RIG_FRESH=1` for a clean map.
- Another rig server may be running on other ports. `stop-server.sh` only
  kills the process with the matching RCON port.
