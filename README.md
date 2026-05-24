# Brave New MTS

A remote-only, character-free experience layered on top of
[Multi-Team Support](https://github.com/bits-orio/multi-team-support) (MTS).

Inspired by Brave New OARC, but built entirely on the public **`mts-v1`**
interface — this mod never patches MTS. Anyone can build a similar (or better)
experience the same way.

## What it does

- **No character.** Every player's character is removed; you play from remote
  view. Handcrafting and hand-mining are impossible by construction — no
  permission groups, no cheat mode (so the save is never flagged as cheated).
- **You place blueprints, robots build.** Each team's spawn is seeded with a
  self-running starter base — power (solar + accumulators + substations) and a
  [K2 Roboports](https://mods.factorio.com/mod/K2-Roboports) roboport stocked
  with construction and logistic robots — plus logistic chests pre-filled with
  starter items so the bots always have stock to bootstrap from. You expand by
  drawing blueprints; the network does the rest.
- **Every team surface.** A starter base is placed on each team surface the
  team reaches, including additional planets under Space Age. Aquilo gets a
  variant with extra solar.

## Requirements

- `multi-team-support` (required)
- [`K2-Roboports`](https://mods.factorio.com/mod/K2-Roboports) (required — the
  standalone roboport, not the full Krastorio 2 overhaul)
- `space-age` (optional — enables per-planet starter bases)

## Status

Work in progress. See the phase notes and `TODO(phase3)` markers in
`scripts/` — the starter-base blueprint strings, chest contents, and resource
seeding are filled in once the in-game blueprint is finalised.

## License

MIT
