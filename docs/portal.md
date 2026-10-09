# Brave New MTS

> You never touch the world. The robots do.

[![Discord](https://img.shields.io/badge/Discord-join%20the%20server-5865F2?logo=discord&logoColor=white)](https://discord.gg/tWz4FT74pH) [![GitHub](https://img.shields.io/badge/GitHub-source-181717?logo=github&logoColor=white)](https://github.com/bits-orio/brave-new-mts)

Brave New MTS requires [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support) and turns it into a remote-only, character-free game. Your character is parked in a walled cell in the landing pen and never sets foot on the team surface. You play entirely through remote view. Each team's spawn is seeded with a self-running starter base built around a large roboport, and every entity after that arrives by blueprint, placed by construction robots.

[![Factorio multiplayer where your robots are your only hands](https://img.youtube.com/vi/9CjGeF6vIX8/maxresdefault.jpg)](https://www.youtube.com/watch?v=9CjGeF6vIX8)

Watch on YouTube: [Factorio multiplayer where your robots are your only hands](https://www.youtube.com/watch?v=9CjGeF6vIX8)

## Status

Playable and in active development, running on public multiplayer servers. With Space Age a team can found an outpost on any planet it reaches: research the Character Clone, ship one to a planet on a space platform, and press Establish base in the platform hub to found a starter base tuned for that planet. Space Age support is newer than the Nauvis-only base, so expect more rough edges there than at home. Only a team's original base can end the game; losing an outpost's roboport only wipes that outpost, and another clone re-founds it. Report anything odd on [Discord](https://discord.gg/tWz4FT74pH) or in the [issue tracker](https://github.com/bits-orio/brave-new-mts/issues).

## Quick start

1. Install [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support) first. Nothing in this mod runs without it.
2. Enable Brave New MTS and start or load an MTS game.
3. Join a team. Your character is parked in your team's cell and you start in remote view of your team's base.
4. Ghost a blueprint next to the starter roboport, made from your own copy of part of the base or anything you've built, and watch the bots build it.
5. With Space Age: research the Character Clone, fly one to a planet on a space platform, and press Establish base in the platform hub to found an outpost there.

## Features

- Parked character. You are teleported into your team's cell in the landing pen and locked there, playing through remote view. Teammates share a cell.
- No roaming, no map-peeking: the body never lands on the team surface, so the map opens only as your bot network expands.
- Self-running starter base: solar, accumulators, substations and a large roboport stocked with construction and logistic robots (how many is a map setting), pre-charged so the network is alive when you arrive.
- Blueprints in, factory out. A ghost, from a blueprint or a single entity, is the only way to place something; bots build every one.
- Hand-work is blocked: no handcrafting, no hand-mining, no manual transfer to or from chests. Inserters, machines and bots move everything.
- The power core (solar panels, accumulators, substations, the lights, the warning sign and, on Fulgora, the lightning collector) is non-minable by default, and a team-leader button in the mod's team-settings tab unlocks it for a team that wants to rebuild on its own terms. Planet-tuned buildings stay locked even then. The rest of the base is already minable.
- The central roboport is a custom, uncraftable entity that can never be made minable. Losing your team's home roboport eliminates the team; losing an outpost's roboport only wipes that outpost.
- No god mode and no cheat mode; the save is never flagged as cheated, so achievements stay intact.
- Space Age: research and ship a Character Clone to found an outpost on any planet your team has reached, complete with a cargo landing pad and power tuned to that planet.
- Out of trouble without an admin: if a base's roboport runs out of power, the team leader can spend one of three rescues to restart it, or delete an outpost planet and found it again.

## Compatibility

Factorio 2.0. Space Age is optional and enables per-planet outposts. No roboport mod is needed, since the starter roboport is provided by this mod. Built purely against Multi-Team Support's public `mts-v1` remote interface, so it never patches or forks MTS. MTS blocks the blueprint library and pasted blueprint strings by default; that's fine here, since every blueprint you need can be made in game by copying part of your own base.

## Works with

- [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support) is required. It is the foundation this mod is built on.
- [MTS Dimension Warp](https://mods.factorio.com/mod/mts-dimension-warp) is a sibling game mode on the same `mts-v1` interface. It is not meant to be combined with Brave New MTS: the warp platform does not carry the starter base.

## Links

- [Discord](https://discord.gg/tWz4FT74pH)
- [Source on GitHub](https://github.com/bits-orio/brave-new-mts)
- [Changelog](https://github.com/bits-orio/brave-new-mts/blob/master/changelog.txt)
- [Issue tracker](https://github.com/bits-orio/brave-new-mts/issues)
- [License](https://github.com/bits-orio/brave-new-mts/blob/master/LICENSE)

## Development

Developed with AI coding assistants alongside human review and in-game testing. Issues and pull requests are welcome on [GitHub](https://github.com/bits-orio/brave-new-mts).

License: MIT
