# Data format: tilesets

A tileset bundles: tile graphics (PNG), a blockset (`.bst`), and a passability table.

## Tile graphics (`pokered/gfx/tilesets/<name>.png`)

- Grayscale PNG, 8×8 px tiles packed in a grid. `overworld.png` = 128×48 = 16×6 = 96 tiles.
- Up to 4 GB shades. We remap shades onto the classic GB green palette during extraction
  (darkest source → darkest green). See [graphics.md](graphics.md).
- Tile id = `row * cols + col` (row-major), referenced by blocksets.

## Blockset (`pokered/gfx/blocksets/<name>.bst`)

Flat binary, **16 bytes per block** (a 4×4 tile arrangement, row-major). `overworld.bst` =
2048 bytes = 128 blocks. Block id (from a `.blk`) indexes into this array; the 16 bytes are
tile ids into the tileset PNG.

```
block tile layout (indices):
   0  1  2  3
   4  5  6  7
   8  9 10 11
  12 13 14 15
```

## Passability / collision (`pokered/data/tilesets/collision_tile_ids.asm`)

Each tileset has a `*_Coll` label listing the **passable** (walkable) tile ids — NOT the
blocked ones. Labels can be stacked (shared) above one `coll_tiles` line.

```
Overworld_Coll::
	coll_tiles $00, $10, $1b, $20, $21, $23, $2c, ...   ; passable tile ids
```

A movement cell is walkable iff its representative tile id is in this list. The
"representative" tile is the **bottom-left 8×8 tile of the 16px cell** — see
[../engine/collision.md](../engine/collision.md).

## Tileset constant → asset names

The map header gives a tileset constant (e.g. `OVERWORLD`); resolving it to assets uses three
files, tied together by the tileset's CamelCase **name** (e.g. `Overworld`, `RedsHouse1`):

- **`constants/tileset_constants.asm`** — `const OVERWORLD`, `REDS_HOUSE_1`, … in id order.
- **`data/tilesets/tileset_headers.asm`** — the `Tilesets:` table lists `tileset <Name>, …`
  rows in the **same order**, so const ⇄ name is by **index**. The macro is
  `tileset Name, counter1, counter2, counter3, grass, anim`; the **5th arg is the grass
  tile** (`$52` Overworld, `$20` Forest, else `-1`).
- **`gfx/tilesets.asm`** — wires each name to files via labels before an `INCBIN`:
  `<Name>_GFX:: INCBIN "gfx/tilesets/<file>.2bpp"` and `<Name>_Block:: INCBIN
  "gfx/blocksets/<file>.bst"`. Labels can be **stacked/shared** (e.g. `RedsHouse1_GFX::`
  + `RedsHouse2_GFX::` share `reds_house.2bpp`). We use the sibling `<file>.png` for gfx.
- Collision label = **`<Name>_Coll`** in `collision_tile_ids.asm`.

19 distinct gfx/blockset files back the 24 tilesets (some shared). The extractor emits one
JSON per tileset name (slug = name lowercased: `overworld`, `redshouse1`, …); the map JSON's
`tileset` field is that slug.

## Extracted form (`game/assets/tilesets/<slug>.json`)

```json
{ "name": "overworld", "tile_cols": 16, "tile_count": 96,
  "blocks": [[16 tile ids], ...], "walkable_tiles": [ ... ],
  "grass_tile": 82,                       // 0x52; -1 if the tileset has no grass
  "ledges": [ {"dir":"down","stand":44,"ledge":55}, ... ]  // overworld.json only
}
```

`grass_tile` and `ledges` drive the tall-grass and ledge-hop effects — see
[../engine/ledges-and-grass.md](../engine/ledges-and-grass.md).
