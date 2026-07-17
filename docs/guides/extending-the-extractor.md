# Guide: extending the extractor

`tools/extract.py` turns pokered source data into `game/assets/`. To add a new asset type,
follow the existing pattern.

## Anatomy

- `SRC` = `pokered/`, `OUT` = `game/assets/`, `PREVIEW` = `build/preview/`.
- Loaders parse one source format and return plain Python data:
  - `load_tileset_image(name)` → palette-mapped RGBA + grid info
  - `load_blockset(name)` → list of 16-int blocks
  - `load_blk(name, w, h)` → 2D block-id grid
  - `parse_walkable_tiles(label)` → passable tile ids from `collision_tile_ids.asm`
- `main()` wires loaders → JSON/PNG outputs and prints a one-line summary per asset.

## Adding an asset type — checklist

1. Find the source file(s) in `pokered/` and confirm the format (hex-dump binaries; read the
   relevant `macros/` macro for `.asm` tables).
2. Write a `load_*` / `parse_*` function returning clean Python data. **Strip `;` comments**
   from `.asm` lines (see `parse_walkable_tiles`).
3. Emit JSON under `game/assets/<category>/` (or PNG for graphics). Prefer flat,
   engine-friendly shapes (arrays of ints, no GB-isms).
4. Add a `print(...)` summary line.
5. If a binary, add an assertion on expected size (e.g. `.blk` == w*h) to catch format drift.
6. **Document the format** in `docs/data-formats/` and update `docs/roadmap.md`.
7. Re-run `pwsh tools/build.ps1` and sanity-check (a preview render or `--selftest`).

## Parsing `.asm` tables — tips

- Symbolic constants (e.g. `GRASS`, `TACKLE`, `OVERWORLD`) resolve via `constants/*.asm`.
  Build a name→number dict from the relevant constants file rather than hardcoding.
- Many tables use macros (`map_header`, `warp_event`, `object_event`, `coll_tiles`,
  `tmhm`). Read the macro in `macros/` to know the argument order.
- Labels can be shared/stacked above a single data line (multiple `*_Coll::` → one
  `coll_tiles`). Handle the "pending labels" case.

## Generalizing to all maps/tilesets (M5) — plan

- Map list + dimensions: `constants/map_constants.asm` (`map_const NAME, w, h`).
- Per-map tileset: 3rd arg of `map_header` in `data/maps/headers/<Name>.asm`.
- Tileset constant → (blockset, gfx, collision label, grass tile): fully decoded in
  [../data-formats/tilesets.md](../data-formats/tilesets.md#tileset-constant--asset-names).

(Done — `build_tilesets`/`build_maps` in `extract.py` implement all of the above.)
