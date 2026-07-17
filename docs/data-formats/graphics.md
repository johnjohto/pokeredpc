# Data format: graphics

pokered stores graphics as **PNG** in the repo (the build converts them to 2bpp). That means
we can use them directly — no 2bpp decoding needed.

## Shades & palette

GB graphics use up to 4 shades. Source PNGs are grayscale (`L` mode). The extractor reads the
distinct shade values and maps them onto a target palette:

```
GB_PALETTE (light → dark): #E0F8D0  #88C070  #346856  #081820   (classic GB green)
```

Mapping is by brightness rank: lightest source shade → lightest palette entry, etc. This is
purely cosmetic; swap `GB_PALETTE` in `extract.py` for a different look (grayscale, SGB, …).

## Tilesets vs sprites

- **Tilesets** (`gfx/tilesets/*.png`) — opaque background tiles. No transparency.
- **Sprites** (`gfx/sprites/*.png`, player/NPC overworld) — need **transparency**: the
  **lightest** GB shade (white, value 255) is the background → transparent (verified via
  corner pixels). The remaining **visible** shades are spread across the **full** GB palette
  by brightness rank (darkest → `palette[3]`, lightest visible → `palette[0]`).
  - Why the full range: on GB hardware sprite color 0 is transparent and thus *unusable*, so
    a sprite's lightest pixel is only `palette[1]`. But we key transparency with **alpha**,
    so reserving `palette[0]` would just render every sprite a shade too dark (figures looked
    muddy). Using the full range gives proper highlights/contrast, matching the tiles.
    See `build/preview/sprite_before_after.png`.
- **Pokémon battle pics** (`gfx/pokemon/front|back/*.png`, `_mon_sprite`) — these use all four
  GB shades deliberately, so they map by **absolute** shade index, not brightness rank: white
  (255) → transparent, and 170/85/0 → `palette[1]/[2]/[3]`. (The rank stretch used for the
  overworld sprites pushed the light body shade to near-white and washed the pics out — a 3- or
  4-shade pic must keep its true tone.)
  - Overworld sprite sheets are **16×96 = six 16×16 frames**, in order:
    `0 down(stand) · 1 up(stand) · 2 side(stand) · 3 down(walk) · 4 up(walk) · 5 side(walk)`.
    Side frames face **left**; right = same frame flipped horizontally. (Verified with
    `red.png`; see `build/preview/red_frames.png`.)
  - Animation: down/up alternate the walk frame's H-flip to swap legs; sides alternate
    between stand and walk frames. Implemented in `game/scripts/Player.gd`.
  - **All 66** overworld sprites are extracted (not just the player); static objects
    (poké balls, boulders) are 16×16 single-frame. `assets/sprites/index.json` maps
    `SPRITE_* -> {file, frames}`. See [../engine/npcs.md](../engine/npcs.md).

## Other graphics (later milestones)

- `gfx/font/` — text font tiles (M9).
- `gfx/pokemon/front|back/*.png` — battle sprites (40×40 / 32×32). Already PNG in the repo —
  extracted directly (no LZ decode needed). See [../engine/battle.md](../engine/battle.md).
- `gfx/pokedex/`, `gfx/title/`, etc. — UI screens.
