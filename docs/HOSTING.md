# Hosting Brave New MTS with Space Age

A checklist for running a public Brave New MTS (BNM) server with Space Age enabled.
This is written for the admin, not for players -- player-facing information is
[README.md](https://github.com/bits-orio/brave-new-mts/blob/master/README.md) and
[docs/portal.md](https://github.com/bits-orio/brave-new-mts/blob/master/docs/portal.md).
`docs/` is not shipped in the mod zip, so this file only exists on GitHub.

## Two MTS settings that matter for BNM

### `mts_passive_radars` (MTS startup setting, default on) -- leave it on

MTS cuts the vanilla radar's power draw from 300 kW to 50 kW while it's set, because
every team otherwise carpets its territory with full-power radars that chart chunks
forever. It's a **startup** setting: it can only be set when the save is created and
can't be flipped mid-run.

BNM's starter-base power was measured with this setting on. A starter base's idle
draw is about **255 kW** (roboport 200 kW, radar 50 kW, lamps and inserter make up
the rest). Turn it off and idle draw rises to about **505 kW**, and every radar a
team builds draws 300 kW instead of 50. That extra 250 kW hits Nauvis hardest: its
spare power drops from about 600 kW to about 350 kW. The tuned Gleba and Fulgora
bases are designed to sustain at least 1.08 MW, so a quarter of that goes to the
radar. Leave `mts_passive_radars` at its default before you create the map.

### `allow_blueprint_imports` (MTS admin flag, default off) -- leave it off

MTS blocks the blueprint library and pasted blueprint strings by default. This is
fine for BNM as shipped, and there's nothing to turn on: players build by ghosting
entities from single-entity pipettes, the quickbar, or by making a blueprint of part
of their own base (`select_blueprint_entities` / `setup_blueprint`, both allowed).
That's enough to play the mod as designed. If you'd still rather let players use
their personal blueprint library and paste strings, it's a runtime toggle in the MTS
Admin panel ("Allow Blueprint Imports") and needs no restart -- but it isn't required
for anything BNM does.

## Fulgora: lightning power and flying robots

Fulgora's starter base runs on a vanilla lightning collector plus tuned
accumulators instead of solar. Two things to expect, both measured on the headless
rig, not guessed:

- Lightning only strikes between dusk and dawn. The base's buffer is sized to carry
  it through the strike-free daytime stretch, so a healthy base shouldn't blackout
  under normal (non-saturated) load. A base running its factory at or near the
  design ceiling can still see a rare blackout night; that's expected, not a bug.
- Construction robots that fly outside the collector's protection radius get struck.
  Measured at roughly 33 robot deaths per game hour of continuous flying beyond
  cover. This mostly matters for a team running bots on a long supply line at night;
  it's a real cost of playing Fulgora, not a soft-lock (the base itself and the
  roboport are not realistic lightning targets).

There's no admin action here. It's worth a line in your own server rules or MOTD so
players don't mistake dead robots for a bug report.

## The clone / outpost flow, in short

1. A team researches the Character Clone (needs `rocket-silo`, plus red, green and
   blue science) and the normal Space Age chain to reach a planet.
2. They load a clone onto a space platform and fly it to that planet.
3. Once the platform is parked there, a player opens the platform hub and presses
   **Establish base**. That consumes the clone and founds a starter base tuned for
   the planet, with its own cargo landing pad just outside the base's south wall.
4. From then on the outpost is a second, independent base: its own roboport, its own
   power, its own kit. Only the team's original (home) base can end the game --
   losing an outpost's roboport wipes just that outpost, and another clone re-founds
   it later.

Nothing here needs admin intervention in the normal case. If a base fails to place
(a rare collision, or a placement that never confirms), see the admin commands
below rather than reaching for `/sc`.

## Admin commands

All three are gated to the server console (RCON / no player attached) or an admin
player. None of them flags the save as cheated the way `/sc`, `/c` or the map
editor does.

| Command | What it does |
|---|---|
| `/bnm-status [team-N]` | Read-only. Lists each team's bases (home or outpost, per surface), whether each roboport is alive, whether the power core is unlocked, and for each member the surface they are viewing, the one they last viewed and their home surface. It also flags a surface marked as founded with no base record. Without an argument it covers every team. Run this first, to see what actually happened. |
| `/bnm-repark <player>` | Puts a connected player who's stuck outside remote view (for example, after spectating a rival team through the ordinary MTS Teams panel) back into their team's cell and remote view: the own-team surface they last viewed, else their home surface, else the team's home base. An offline player is re-parked when they reconnect. |
| `/bnm-forget-base <surface>` | Clears Brave New MTS's own bookkeeping for that surface so it can be founded again. It refuses while the base's roboport is still alive, so it only recovers a base that is already gone or failed to place. It does not place a new base by itself: a player arriving on a home surface, or another Character Clone for an outpost, does that. |

`/bnm-repark` and `/bnm-forget-base` are logged and announced to everyone on the
server, so a public server keeps an audit trail. `/bnm-status` answers only the
admin who ran it.

## Manual client test checklist

The following need a real game client, not the headless rig, and are worth running
through once before opening the server to the public and again after any update
that touches parking, remote view or the platform hub:

- **Reconnect keeps inventory and blueprints.** Join a team, put a blueprint or a
  deconstruction planner in your inventory, disconnect, and reconnect. Confirm it's
  still there (only your very first spawn should ever be cleared).
- **Spectate a rival team and come back.** Open the MTS Teams panel, spectate a
  team you're not friended with, then stop spectating. Confirm your camera returns
  to your own base, not to your empty pen cell, and that you can still see and
  build normally afterward.
- **Establish a base from the hub GUI.** Fly a platform carrying a Character Clone
  to one of your team's planets, open the platform hub, and press Establish base.
  Confirm the base appears with a working roboport and a cargo landing pad, and
  that the clone is only consumed once the base is actually built.
- **Remote view of a new outpost.** After establishing an outpost, open remote view
  of that surface from a fresh client session (or after a reconnect) and confirm it
  loads correctly and stays where you left it, rather than snapping back to your
  home planet.

## Development

Developed with AI coding assistants alongside human review and in-game testing.
