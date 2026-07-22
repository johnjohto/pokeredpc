# Engine: map connections (seamless routes)

Implemented in `game/scripts/Main.gd` as a multi-map **world**: the active ("center") map
plus its connected neighbors are loaded, placed at block offsets, rendered seamlessly, and
collided across the seam. Walking off the center map **rebases** the world onto the neighbor.

## Connection data (Project format 2)

```json
{"maps": {"map:PalletTown": [
  {"direction": "north", "map": "map:Route1", "offset": 0}
]}}
```

`data/world.json` owns these map-to-map relationships; TMX owns only local geometry.
`ProjectData` translates the active map's records to the runtime's historical
`{dir,map,offset}` shape. Kanto's extractor derives them from
`data/maps/headers/<Map>.asm`'s `connection <dir>, <Map>, <CONST>, <offset>`.

Studio edits one logical pair through `WorldDocument`: `A east → B` at offset `n` requires
`B west → A` at offset `-n` (likewise north/south). Core refuses duplicate directions,
missing/mismatched reciprocals, missing maps, and placements whose perpendicular spans do
not overlap. This keeps rebase geometry valid before the Engine sees the project.

## Neighbor placement (block offset of neighbor origin vs center origin)

From the `connection` macro (`macros/scripts/maps.asm`), with `cur`/`nb` = center/neighbor
block dims and `off` = the connection offset (in **blocks**):

```
north -> (off,      -nb_h)
south -> (off,      +cur_h)
west  -> (-nb_w,     off)
east  -> (+cur_w,    off)
```

Cell coords = block × 2. So a neighbor placed at block `(ox,oy)` owns world cells starting
at `(ox*2, oy*2)`. Reciprocal connections are consistent: Route1 `north Viridian -5` ⇔
Viridian `south Route1 +5` (both mean Route1 col 0 ↔ Viridian col 5). Verified visually in
`build/preview/world_route1.png` (Viridian → Route 1 → Pallet Town line up exactly).

## Rendering & collision

- `placed[]` holds the center (index 0) + neighbors, each with its own tileset, blockset,
  and a precomputed collision grid. Tilesets are cached (`_ts_cache`) since neighbors may use
  different tilesets.
- `_draw` walks the bounding box of all placed maps (+ `BORDER_MARGIN`); each block is drawn
  from its owning map, or the center map's `border_block` where no map exists.
- `is_walkable` / `_cell_walkable` find the owning placed map and read its collision grid;
  cells owned by no map are blocked.

## Crossing / rebase

`_on_player_moved`: when the player's cell leaves the center bounds and lands inside a
neighbor, the world reloads centered on that neighbor and the player is re-placed at the
translated local cell with **facing preserved** (`player.place(cell, keep_facing=true)`).
Because the camera follows the player, the rebase is visually seamless. Verified by
`--conntest` (Pallet Town → walk north → center becomes Route1).

## Simplifications vs pokered (refine later)

- Full neighbor maps are rendered at their offset (pokered streams only a 3-block strip).
  Visually identical near the seam; only matters for very large neighbors (drawn once per
  load, so perf is fine).
- Rebase happens the moment the player steps 1 cell off the center map (pokered switches at a
  fixed threshold). No visible difference because the camera tracks the player.
- Only N/S/E/W neighbors; corner gaps fall back to the border block.
