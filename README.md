# pokeredpc — a native PC port of Pokémon Red

A from-scratch, **data-driven native port** of [pret/pokered](https://github.com/pret/pokered)
to the PC, built on **Godot 4.7**. It is *not* an emulator and not a static recompile of
the Game Boy assembly. Instead it:

1. **Extracts** pokered's source data (maps, tilesets, stats, text, graphics) into clean,
   engine-ready PNG + JSON, and
2. **Reimplements** the game engine (overworld, collision, battles, …) natively in Godot,
   using the disassembly as an exact behavioral spec.

## Status

See [docs/roadmap.md](docs/roadmap.md) for the live tracker. In short:

| Area | State |
|---|---|
| Asset extraction (all 221 maps, 24 tilesets, player sprite) | ✅ done |
| Map rendering (block → tile expansion) + map border | ✅ done |
| Collision (bottom-left-tile passability rule) | ✅ done |
| Player: grid movement, walk animation, follow camera | ✅ done |
| Warps / doors (enter & exit buildings) | ✅ done |
| Seamless map connections (routes ↔ towns) | ✅ done |
| Ledge hops + tall-grass leg overlap | ✅ done |
| NPCs (sprites, wander, solid, interaction hook) | ✅ done |
| Text boxes + font (real dialogue, typewriter, signs) | ✅ done |
| Menus (start menu, yes/no, cursor lists) | ✅ done |
| Wild battles: party/switch, EXP/level, catching, items, stat stages | ✅ done |
| Trainer battles (full enemy party, prize money, no catch/run) | ✅ done |
| Status conditions (psn/par/slp/brn/frz) | ✅ done |
| All move effects (multi-hit, drain, recoil, charge, trap, …) + evolution | ✅ done |
| Save / continue, Pokécenter healing, overworld poison | ✅ done |
| Music (GB sound-chip synthesis of pokered song data) | ✅ done |
| Sound effects + Pokémon cries (pitch/length per species) | ✅ done |

## Layout

```
pokered/        upstream disassembly (source data; clone separately)
docs/           knowledge base — start at docs/index.md
tools/
  extract.py    reads pokered/ -> game/assets/ (PNG + JSON) and build/preview/
  godot/        portable Godot 4.7 engine (download separately)
  build.ps1     run extraction + (re)import assets
  run.ps1       launch the game
game/           the Godot project (the actual PC game)
  assets/       generated tilesets + maps + sprites (git-ignored)
  scripts/      Main.gd (world loader: render, collision, warps, connections), Player.gd
  shaders/      grass_overlay.gdshader (tall-grass transparency)
  scenes/Main.tscn
build/preview/  verification renders (maps, collision overlays, effect zooms)
```

Full design/format/engine notes live in **[docs/](docs/index.md)**. Source repo:
`github.com/johnjohto/pokeredpc`.

## First-time setup

```sh
git clone --depth 1 https://github.com/pret/pokered.git pokered
# download portable Godot 4.7 (win64) into tools/godot/
python -m pip install --user Pillow
```

## Build & run

```powershell
pwsh tools/build.ps1   # extract assets + import into Godot
pwsh tools/run.ps1     # play
```

Controls: **arrows** move/navigate · **Enter/Space** = A (interact / confirm / advance) ·
**Esc** = B / START (open the start menu; back/cancel).

## How the rendering works

- A map's `.blk` file is a grid of 1-byte **block** ids (a block = 4×4 tiles = 32×32 px).
- The tileset's `.bst` maps each block id to its 16 tile ids; tile graphics come from the
  tileset PNG (8×8 px each).
- **Collision**: the player moves on a 16×16 px grid (a block = 2×2 cells). A cell is
  passable iff its **bottom-left 8×8 tile** (the player's feet) is in the tileset's
  passable-tile list — matching pokered's `GetTileAndCoordsInFrontOfPlayer` /
  `CheckTilePassable`. (Connections, warps, ledges and grass build on this — see `docs/`.)

##
In the beginning was the Word, 
and the Word was with God, 
and the Word was God.