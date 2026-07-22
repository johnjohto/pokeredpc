# pokeredpc

**Pokémon Red, rebuilt as a native PC game—and now growing into a standalone
monster-RPG creation toolkit.**

pokeredpc is a from-scratch, data-driven Godot 4.7 port of
[pret/pokered](https://github.com/pret/pokered). It is not an emulator, ROM patcher, or
static recompilation. A local extractor turns the disassembly into project data and
assets; an original native engine reproduces the game using the assembly as its behavioral
specification.

The faithful port is complete and playable. Current development is **Studio**: a desktop
editor and generic Engine/Project/Ruleset architecture for making other monster-catching
RPGs without opening the Godot editor.

## Status

| Track | State |
|---|---|
| Native Pokémon Red | **v1.2.0 shipped** — all 223 maps, complete critical path, battles, saves, audio, and Cable Club multiplayer |
| v2 Core | **Phases 1–3 complete** — versioned projects, stable IDs, ruleset modules, formulas, and authored Event VM |
| Studio | **Phase 4 complete** — project browser, schema-driven content editors, validation, canonical Save/Revert, and isolated live play-test |
| Maps and events | **Phase 5 active** — native Tiled TMX/TSX maps now render identically in Engine and Studio; painting and Kanto migration follow |

The detailed, evidence-backed tracker is [docs/roadmap.md](docs/roadmap.md). The v2 product
direction lives in [docs/v2/plan.md](docs/v2/plan.md), and the supplied Studio reference
boards are translated into an implementation contract in
[docs/v2/studio-visual-direction.md](docs/v2/studio-visual-direction.md).

## Build and play

You need Python 3, Pillow, PowerShell 7, a local checkout of `pret/pokered`, and the
portable Godot 4.7 binary. Extracted assets and builds are deliberately not stored in this
repository.

```powershell
git clone https://github.com/johnjohto/pokeredpc.git
cd pokeredpc
git clone --depth 1 https://github.com/pret/pokered.git pokered
python -m pip install --user Pillow

# Put Godot 4.7 in tools/godot/ (or set POKEREDPC_GODOT), then:
pwsh tools/build.ps1
pwsh tools/run.ps1
```

Controls: **arrow keys** move/navigate · **Enter/Space** is A (interact/confirm/advance) ·
**Esc** is B/START (back/cancel/open the start menu).

See [the build and run guide](docs/guides/build-and-run.md) for exact Godot filenames,
exports, multiplayer, verification flags, and troubleshooting.

## Open Studio

After building the project:

```powershell
pwsh tools/run.ps1 -- --studio
```

Studio opens as a native, resizable 1280×800 desktop application with a persistent 80–200%
UI-scale slider (125% by default). It currently edits
species, moves, items, and trainers, validates through the same Core schemas the Engine
uses, and launches a separate play-test process with an isolated save. Do not edit the
extractor-owned `game/project` in place; copy it to a creator workspace and open that copy.

Developers can open the focused Phase-5 native-map tracer directly:

```powershell
pwsh tools/run.ps1 -- --studio-map-fixture
```

The map surface is intentionally read-only in this tracer. Painting, collision editing,
objects, world connections, event authoring, undo/redo, and softlock lints are the remaining
Phase-5 slices. MIDI and pluggable chiptune import are tracked for the later asset-pipeline
phase in [gh #60](https://github.com/johnjohto/pokeredpc/issues/60).

## How it is shaped

```text
Studio ───────┐
              ├── Core ── Project (data, TMX maps, events, assets)
Engine ───────┘              │
  │                          └── selected Ruleset (built-in: gen1)
  └── plays the same Project Studio edits
```

- **Core** owns project schemas, stable IDs, validation, event definitions, ruleset
  interfaces, and the native `MapDocument` boundary.
- **Engine** owns runtime presentation and systems. Gen-1 mechanics live behind a built-in
  ruleset rather than defining the whole architecture.
- **Studio** is a creator-facing desktop application over Core—not a Godot plugin.
- **Project** is the portable, versioned, diff-friendly game folder both applications use.
- **Tiled TMX/TSX** is the native map format. The canonical grid is one 16×16 movement cell;
  familiar 32×32 Game Boy blocks remain optional authoring metadata.

The current TMX bridge and lossless preservation rules are documented in
[docs/v2/tiled-map-bridge.md](docs/v2/tiled-map-bridge.md).

## Repository map

```text
docs/                 architecture, format, engine rules, ADRs, roadmap, guides
game/core/            shared Project/schema/ruleset/event/map contracts
game/rulesets/gen1/   faithful Gen-1 mechanics modules
game/scripts/         Engine runtime and Studio application
game/project/         extracted default Project (generated, git-ignored)
pokered/               upstream disassembly (clone separately, git-ignored)
tools/extract.py       pokered source → project data and PNG assets
tools/build.ps1        extract and import
tools/run.ps1          launch Engine, Studio, or a verification scenario
build/                 local previews/exports (git-ignored)
```

Start in [docs/index.md](docs/index.md) when changing behavior or formats. Decisions with
lasting architectural consequences are recorded in [docs/decisions.md](docs/decisions.md).

## Verification philosophy

The port treats the disassembly as executable specification. Focused `--…test` scenarios,
schema/refusal fixtures, deterministic battle hashes, link soaks, and a seeded legit-play bot
cover systems from small rules through NEW GAME → HALL OF FAME. Studio adds byte-identity
round trips: opening and saving untouched project content must not create a diff.

Useful fast checks include:

```powershell
pwsh tools/run.ps1 -- --selftest
pwsh tools/run.ps1 -- --schematest
pwsh tools/run.ps1 -- --tmxtest
pwsh tools/run.ps1 -- --studiotest
```

## Assets and distribution

This is a personal-use project. Pokémon data and graphics are extracted locally from the
user-supplied `pret/pokered` checkout and remain git-ignored. Do not distribute extracted
assets or builds containing them. The long-term toolkit ships original Engine/Studio code
and import recipes, not Nintendo content.

##
In the beginning was the Word, 
and the Word was with God, 
and the Word was God.
