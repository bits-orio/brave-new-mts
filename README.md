# Brave New MTS

A remote-only experience layered on top of
[Multi-Team Support](https://github.com/bits-orio/multi-team-support) (MTS).

Inspired by Brave New OARC, but built entirely on the public **`mts-v1`**
interface — this mod never patches MTS. Anyone can build a similar (or better)
experience the same way.

## What it does

- **You're the overseer.** When you spawn into a team, your character is parked
  in your team's walled cell in the landing pen and you play entirely through
  **remote view** of your team surface. Teammates stand together in the same
  cell; the body never sets foot on the team surface (so it can't roam or expose
  the map). No god mode, no cheat mode — the save is never flagged as cheated.
- **You place blueprints, robots build.** Each team's spawn is seeded with a
  self-running starter base — power (solar + accumulators + substations) and a
  [Better Robots Extended](https://mods.factorio.com/mod/Better_Robots_Extended)
  roboport stocked with construction and logistic robots — plus logistic chests
  pre-filled with starter items so the bots always have stock to bootstrap from.
  You expand by drawing blueprints; the network does the rest.
- **No hand-work.** Handcrafting, mining, and manual item transfer to/from
  chests are blocked; everything moves through inserters and bots.
- **Every team surface.** A starter base is placed on each team surface the
  team reaches, including additional planets under Space Age. Aquilo gets a
  variant with extra solar.

## Requirements

- `multi-team-support` (required)
- [`Better_Robots_Extended`](https://mods.factorio.com/mod/Better_Robots_Extended) (required)
- `space-age` (optional — enables per-planet starter bases)

## License

MIT
