# pokeredpc documentation

Knowledge base for the native PC port of pret/pokered (Godot 4.7). Kept up to date
as development proceeds — when a format, rule, or decision is discovered, record it here.

## Map

- **[architecture.md](architecture.md)** — high-level design of the data-driven port.
- **[roadmap.md](roadmap.md)** — living status & milestone tracker. **Update as work lands.**
- **[decisions.md](decisions.md)** — architecture decision records (why, not just what).
- **[v2/plan.md](v2/plan.md)** — north-star plan for **v2**: turning the port into a standalone
  monster-RPG creation toolkit (Studio editor + generic engine + shareable projects). Starts after 1.0;
  see ADR-013.
- **[v2/project-format.md](v2/project-format.md)** — the v2 project format (Phase 1, ADR-017):
  layout, schemas, manifest + identity, versioning.
- **[v2/ruleset-seam.md](v2/ruleset-seam.md)** — the ruleset seam (Phase 2, ADR-018): the five
  Core interfaces, the registry, `gen1`, and the strangler-fig migration protocol.
- **[v2/studio-visual-direction.md](v2/studio-visual-direction.md)** — the reference boards and
  durable visual/layout contract for Studio, including the Phase-5 map workspace.
- **[v2/tiled-map-bridge.md](v2/tiled-map-bridge.md)** — Project-format-2 TMX/TSX contract,
  gameplay properties/objects, lossless round trips, and the Engine/Studio tracer.

### Data formats (`pokered/` → `game/assets/`)
- **[data-formats/maps.md](data-formats/maps.md)** — `.blk`, headers, objects, warps, connections.
- **[data-formats/tilesets.md](data-formats/tilesets.md)** — `.bst` blocksets, collision tables.
- **[data-formats/graphics.md](data-formats/graphics.md)** — tile/sprite PNGs, palettes, transparency.
- **[data-formats/pokemon.md](data-formats/pokemon.md)** — base stats, moves, types, learnsets.
- **[data-formats/battle-anims.md](data-formats/battle-anims.md)** — per-move battle animations (`move_anims.json`).
- **[data-formats/mon-record.md](data-formats/mon-record.md)** — the `mon/1` link wire schema for one exchanged Pokémon.

### Engine (Godot side)
- **[engine/rendering.md](engine/rendering.md)** — block→tile expansion, custom 2D draw.
- **[engine/collision.md](engine/collision.md)** — passability rule, 16px movement grid.
- **[engine/coordinates.md](engine/coordinates.md)** — units: px / tiles / cells / blocks.
- **[engine/timing.md](engine/timing.md)** — pokered's two frame domains (60 Hz V-blank vs 30 Hz overworld tick) → seconds.
- **[engine/warps.md](engine/warps.md)** — doors/warps & map switching.
- **[engine/connections.md](engine/connections.md)** — seamless route↔town connections.
- **[engine/ledges-and-grass.md](engine/ledges-and-grass.md)** — ledge hops & tall-grass overlap.
- **[engine/npcs.md](engine/npcs.md)** — NPC sprites, wander, collision, interaction.
- **[engine/map-scripts.md](engine/map-scripts.md)** — per-map script adapters (triggers, gates, visibility).
- **[engine/text.md](engine/text.md)** — font, charmap, dialogue extraction & text box.
- **[engine/menus.md](engine/menus.md)** — reusable menus, start menu, modal input model.
- **[engine/battle.md](engine/battle.md)** — battle data, Gen-1 formulas, turn loop.
- **[engine/save.md](engine/save.md)** — save/continue, title screen, Pokécenter heal, whiteout, poison.
- **[engine/wild.md](engine/wild.md)** — per-map grass encounter tables + slot probabilities.
- **[engine/audio.md](engine/audio.md)** — GB music synthesis (extract song commands, 4-channel synth).
- **[engine/link.md](engine/link.md)** — v1.1 link layer: ENet transport, link identity handshake, session lifecycle.

### Guides ("how do I…")
- **[guides/build-and-run.md](guides/build-and-run.md)** — setup, build, run, debug flags.
- **[guides/extending-the-extractor.md](guides/extending-the-extractor.md)** — add a new asset type.

## Conventions for keeping docs current

- When you change a data format or engine rule, edit the matching doc **in the same change**.
- `roadmap.md` is the single source of truth for status — flip the table entry when a
  milestone lands, and add newly-discovered sub-tasks.
- Record non-obvious "why" choices in `decisions.md` as a new ADR entry.
