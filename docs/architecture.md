# Architecture

## Goal

A **native** PC build of Pokémon Red — a real Godot application, not an emulator and not a
static recompilation of the Game Boy assembly.

## Two-stage design

```
 pokered/ (RGBDS asm + data)
        │
        │  tools/extract.py   (Python + Pillow)
        ▼
 game/assets/  (PNG + JSON)   ← engine-ready, no GB concepts leak through
        │
        │  Godot 4.7 reads at runtime
        ▼
 game/  (the PC game)         ← engine reimplemented natively
```

### Stage 1 — Extraction (mechanical)

Most of Pokémon Red is **data, not code**: maps, tilesets, base stats, moves, text, and
graphics are all stored as readable files in the disassembly. `tools/extract.py` parses
them and writes clean PNG + JSON into `game/assets/`. This stage carries no gameplay logic.

### Stage 2 — Engine (the real work)

The game logic (overworld movement, collision, battles, menus, …) is **reimplemented** in
Godot/GDScript, using the disassembly as the exact behavioral spec. We mirror pokered's
rules (e.g. the collision passability test) rather than inventing our own.

## Why this approach

See [decisions.md](decisions.md). Briefly: it's the only route that is both *finishable*
and produces clean, modifiable, genuinely-native code. asm→C static recompilation would
still require reimplementing the GB's PPU/APU/timing and yields an unmaintainable blob.

## Component overview

| Component | Where | Responsibility |
|---|---|---|
| Extractor | `tools/extract.py` | all maps+tilesets+sprite → `game/assets/` PNG+JSON |
| Game root | `game/scripts/Main.gd` | load a world (map + connected neighbors), render, collision, warps, crossings |
| Map scripts | `game/scripts/MapScripts.gd` + `game/scripts/maps/*.gd` | per-map story triggers: one adapter per scripted map (five hooks; see [engine/map-scripts.md](engine/map-scripts.md)) |
| Player | `game/scripts/Player.gd` | grid movement, walk animation, ledges, grass, interact; `moved` signal |
| NPCs | `game/scripts/NPC.gd` | per-map object_event characters: facing sprite, wander, solid |
| Text box | `game/scripts/TextBox.gd` | font dialogue box: typewriter, pages, NPC/sign text |
| Menu | `game/scripts/Menu.gd` | reusable cursor list (start menu, yes/no); modal input |
| Battle | `game/scripts/Battle.gd` | wild battle modal: scene, HP bars, Gen-1 damage, turns |
| Engine binary | `tools/godot/` | portable Godot 4.7 (not installed system-wide) |

As systems grow, `Main.gd` will split into focused nodes/scripts (MapManager, Battle,
DialogueBox, etc.). Keep this table current.
