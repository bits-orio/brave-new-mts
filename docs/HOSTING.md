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
forever. It's a **startup** setting, so changing it needs a full server restart: stop
the server, change it in the server's mod settings (`mod-settings.dat`), and start the
same save again. It isn't locked into the save, so a map that started with it off can
be switched back on.

BNM's starter-base power was measured with this setting on. A starter base's idle
draw is about **255 kW** (roboport 200 kW, radar 50 kW, lamps and inserter make up
the rest). Turn it off and idle draw rises to about **505 kW**, and every radar a
team builds draws 300 kW instead of 50. That extra 250 kW hits Nauvis hardest: its
spare power drops from about 600 kW to about 350 kW. The tuned Gleba and Fulgora
bases are designed to sustain at least 1.08 MW, so a quarter of that goes to the
radar. Leave `mts_passive_radars` at its default. If a map was started with it off,
turn it back on and restart the server.

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

Fulgora's starter base keeps its ordinary solar panels and adds a vanilla lightning
collector (in one panel slot) plus tuned accumulators that bank the night's strikes.
If a team unlocks its core, it should keep the panels: they carry part of the
strike-free day, which is when the accumulators run lowest. Two things to expect,
both measured on the headless rig, not guessed:

- Lightning only strikes between dusk and dawn. The base's buffer, together with the
  panels, is sized to carry it through the strike-free daytime stretch, so a healthy
  base shouldn't blackout under normal (non-saturated) load. A base running its
  factory at or near the design ceiling can still see a rare blackout night; that's
  expected, not a bug.
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

All four are gated to the server console (RCON / no player attached) or an admin
player. None of them flags the save as cheated the way `/sc`, `/c` or the map
editor does.

| Command | What it does |
|---|---|
| `/bnm-status [team-N]` | Read-only. Lists each team's rescues left and its bases (home or outpost, per surface), whether each roboport is alive, out of power or missing, whether the power core is unlocked, and for each member the surface they are viewing, the one they last viewed and their home surface. It also flags a surface marked as founded with no base record. Without an argument it covers every team. Run this first, to see what actually happened. |
| `/bnm-repark <player>` | Puts a connected player who's stuck outside remote view (for example, after spectating a rival team through the ordinary MTS Teams panel) back into their team's cell and remote view: the own-team surface they last viewed, else their home surface, else the team's home base. An offline player is re-parked when they reconnect. |
| `/bnm-forget-base <surface>` | Wipes a gone outpost as if its roboport had died: Brave New MTS forgets the surface's base record, so it can be founded again, and its power core becomes minable, so the team's robots can salvage it. It refuses while the base's roboport is still alive, so it only recovers an outpost that is already gone or failed to place. It does not place a new base by itself: another Character Clone does that. It also refuses a home base: the home's roboport is what ends a team, so `/mts-disband <team-N>` (in game, as an admin) is the way to end that team. If a team's home surface is ever deleted without a disband, the team keeps its outposts, and a Character Clone shipped back to its home planet re-founds the home. |
| `/bnm-rescue <surface>` | Refills the roboport of the base on that surface, for example `mts-gleba-3`, as a team's rescue does, without spending any of the team's rescues. Use it for a team that is stuck with none left. It works on any base whose roboport stands, out of power or not, and says which it was. The roboport is full again, about half an hour of its idle draw, so the team should fix its power in that time. |

`/bnm-repark`, `/bnm-forget-base` and `/bnm-rescue` are logged and announced to
everyone on the server, so a public server keeps an audit trail. `/bnm-status` answers only the
admin who ran it.

## A roboport out of power: rescues and deleting a planet

The `bnm-roboport` is fed before anything else on its network, so a factory
sharing a base's power can't starve it. Before this, measured on the headless rig at
Nauvis noon, 30 empty player-built roboports, or 300 beacons, left the central
roboport less than its 200 kW idle draw. Once its buffer ran dry the engine shut its
network down until the buffer refilled, which it never did, and a team with no
character had no way to fix the base.

A roboport can still run dry when its base has no power at all: a night with empty
accumulators, panels destroyed, or the power core removed after the unlock. Its
network then shuts down and its robots stop until the base's power has recharged
it. The team is told in chat, and the server log gets a line
(`[brave-new-mts] team-N's roboport on <surface> is out of power`).

- **Rescues.** The team leader can spend a rescue in Team Settings > Brave New MTS,
  which refills the roboport at once. Each team gets 3, from the runtime map setting
  **Rescues per team** (`bnm-rescues-per-team`). A change applies to every team at
  once and counts what each has already spent, so raising it hands everyone more. A
  released team slot starts again with the full number. `/bnm-rescue <surface>` does
  the same for an admin without spending any.
- **Deleting a planet.** The team leader can delete the team's copy of any planet
  but the home one, from the same tab, after a second confirmation click. The
  surface is deleted with `game.delete_surface`, so everything on it is gone: the
  base, what the team built, the items in its chests and its robots. Team members
  viewing it are moved back to their own ground first. A Character Clone shipped to a
  platform above the planet founds a fresh outpost there. BNM does not use MTS's
  `retire_team_surface` for this: that drops MTS's planet-to-team entry, and the
  planet made again would have no owner.

## Test shortcuts (off on a real server)

Reaching a planet the normal way means a rocket, a whole platform with
thrusters and defence, and the research to get there. To test outposts
without all that, turn on the map setting **Enable test commands** (Settings >
Mod settings > Map; it is off by default and should stay off on a public
server). Then, as an admin:

| Command | What it does |
|---|---|
| `/bnm-test-orbit <planet> [team-N]` | Researches the planet's discovery technology with everything it depends on, plus the Character Clone, and unlocks the team's copy of the planet. Parks a platform called "BNM test: <planet>" above it with one Character Clone in the hub and, for your own team, moves your view to the hub: open it and press Establish base, exactly as a player would. Run it again for one more clone (to test re-founding); a test platform flown elsewhere is brought back, and a deleted one is replaced. `<planet>` is `vulcanus`, `fulgora`, `gleba` or `aquilo`; the team defaults to your own, and a team slot nobody has claimed is refused. Naming another team (or running it from the console) only sets up that team's platform: Establish base acts for the player who presses it, so a member of that team presses it. |
| `/bnm-test-kill-roboport [surface]` | Kills a base's roboport as an enemy would, so BNM handles it as a real loss: an outpost is wiped, a home base eliminates the team. Defaults to the surface you are viewing, for example `mts-vulcanus-1`. |

Both refuse while the setting is off, and every use is announced to everyone.
They grant research and create items, so a save they were used on is a test
save.

So nobody plays a real game with the setting on by accident, it is loud
while it is on: every player who enters the game gets a big red "TEST
COMMANDS ARE ON" window (closed with "I understand", back on their next
join), a red "TEST COMMANDS ON" badge stays at the top of the screen, big red
text sits on the landing pen floor, and chat says when an admin turns the
setting on or off. If you see any of that on a server meant for real play,
turn the setting off.

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
  loads correctly, rather than snapping back to your home planet.
- **Reconnect returns to the spot you were looking at.** In remote view, look at a
  spot on one of your team's planets well away from its roboport, then disconnect
  and reconnect. Confirm the view comes back on that planet at that spot, not
  re-centred on the roboport. Then spectate a rival and come back: that return
  should centre on the base again. The headless rig checks the stored spot with a
  simulated player (regress.py check 12), but only a client shows the real view.
- **Kicked, or team ended, while offline.** With a second member offline, have the
  leader kick them (`/mts-kick` or the Teams panel), then reconnect as that member.
  Confirm they come back in the open pen with its GUI, not walled inside the team's
  cell. Repeat with a team that ends while a member is offline (its home roboport
  destroyed). The headless rig cannot tell whether a reconnect keeps remote view,
  which decides this.
- **The Brave New MTS tab, as leader and as member.** Open Team Settings > Brave New
  MTS as the team leader and as another member. Confirm the warning, Rescues and
  Delete a planet sections fit the panel without clipping. The member sees no
  buttons, just the note that only the leader can change this.
- **A roboport out of power, then a rescue.** As an admin, starve a base: freeze the
  night and empty its accumulators and roboport, for example
  `/c local s = game.player.surface s.daytime = 0.5 s.freeze_daytime = true for _, a in pairs(s.find_entities_filtered{type = "accumulator"}) do a.energy = 0 end s.find_entities_filtered{name = "bnm-roboport"}[1].energy = 0`
  (this flags the save, so use a test save). Within about 15 seconds the team gets a
  chat line saying the roboport is out of power. As leader, the base shows up under
  Rescues; press Rescue. Confirm the chat line, the count going down by one, the
  row going away, and robots flying again. Afterwards, unfreeze the day with
  `/c game.player.surface.freeze_daytime = false`.
- **Delete a planet.** With an outpost founded, press Delete... on its planet, then
  Cancel: nothing happens. Press Delete... again, then the red confirm button, while
  a second member is viewing that planet. Confirm the planet leaves the list, that
  member's view moves back to the home base, the team gets the chat line, and a
  Character Clone on a platform above the planet founds a fresh outpost there. The
  rig checks all of this except the GUI and the real player's view (regress.py
  checks 17 to 19).

## Development

Developed with AI coding assistants alongside human review and in-game testing.
