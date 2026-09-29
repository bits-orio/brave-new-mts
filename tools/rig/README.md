# Headless test rig for Brave New MTS

Scripted, headless tests of BNM on a real Factorio 2.0.77 server with Space Age,
driven over RCON. It builds on the shared rig in `~/factorio-dev/rig` (see its
README: `start-server.sh`, `stop-server.sh`, `rcon.py`). Everything here is
test-only. `tools/` is excluded from the release zip, and nothing in this
folder is ever written into the repo's mod code.

| File | What it does |
|---|---|
| `stage.sh` | Builds a mods dir: MTS 0.6.6 zip, a copy of the BNM working tree, and a `mod-list.json` |
| `hooks/bnm_rig_data.lua` | Test-only prototypes, injected into the staged copy by `stage.sh --hooks` |
| `probe.py` | RCON helper (library and CLI) that runs Lua in the level, BNM or MTS state |
| `lua/power_rig.lua` | In-game power sampler, loaded into the level state by `power_test.py` |
| `power_test.py` | Measures the starter base's sustainable power on every planet |

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
tools/rig/power_test.py --planets fulgora --sweep fulgora:0:350 --cycles 20 --rounds 0 --out /tmp/fulgora.json
#    Re-print the table from a saved file, using the current pass/fail rule
tools/rig/power_test.py --summarize /tmp/power_results.json

# 5. Stop (it saves; the next start without RIG_FRESH=1 reloads that world)
~/factorio-dev/rig/stop-server.sh 27311
```

`stage.sh` copies the working tree, so uncommitted edits are tested. Re-run it
and restart the server after every change to the mod. Other options:
`--mts <zip-or-dir>` stages a different MTS (a source dir is symlinked), and
`--no-space-age` disables space-age, quality and elevated-rails.

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
