# Data format: maps

## `.blk` — block map (`pokered/maps/<Name>.blk`)

A flat binary file of `width * height` bytes. Each byte is a **block id** into the map's
tileset blockset (`.bst`). Row-major (left→right, top→bottom).

- A **block** is 4×4 tiles = 32×32 px.
- Example: `PalletTown.blk` is 90 bytes = 10×9 blocks.

Map dimensions are **not** in the `.blk`; they come from `constants/map_constants.asm`:

```
map_const PALLET_TOWN, 10, 9   ; width, height (in blocks)
```

## Map header (`pokered/data/maps/headers/<Name>.asm`)

```
map_header PalletTown, PALLET_TOWN, OVERWORLD     ; label, id, TILESET
connection north, Route1, ROUTE_1, 0
connection south, Route21, ROUTE_21, 0
end_map_header
```

- 3rd arg of `map_header` = **tileset constant** → picks blockset/gfx/collision.
- `connection <dir>, <Map>, <ID>, <offset>` = adjacent map for seamless scrolling (M7).

## Map objects (`pokered/data/maps/objects/<Name>.asm`)

```
db $b ; border block                       ; block id drawn outside the map edge

def_warp_events
warp_event  5,  5, REDS_HOUSE_1F, 1        ; x, y (cell units), dest map, dest warp index

def_bg_events
bg_event 13, 13, TEXT_PALLETTOWN_OAKSLAB_SIGN   ; x, y, text id (signs)

def_object_events
object_event 8, 5, SPRITE_OAK, STAY, NONE, TEXT_PALLETTOWN_OAK
;            x  y  sprite      movement dir  text id
```

- **Coordinates are in 16px cell units**, not blocks or pixels. Pallet Town = 20×18 cells.
  See [../engine/coordinates.md](../engine/coordinates.md).
- `warp_event` is what we use for doors (M6). `dest warp index` selects which warp in the
  destination map's warp list the player arrives at.

## Extracted form (`game/assets/maps/<Name>.json`)

```json
{ "name": "PalletTown", "tileset": "overworld", "width": 10, "height": 9,
  "blocks": [[..row..], ...], "border_block": 11,
  "warps": [ {"x":5,"y":5,"dest_const":"REDS_HOUSE_1F","dest_warp":1,"dest_map":"RedsHouse1F"}, ... ],
  "connections": [ {"dir":"north","map":"Route1","offset":0}, ... ],
  "bg_events": [ {"x":13,"y":13,"text":"TEXT_..."} ],
  "object_events": [ {"x":8,"y":5,"sprite":"SPRITE_OAK","args":["STAY","NONE","TEXT_..."]} ] }
```

A trainer `object_event` (its `args` include an `OPP_*` class + party number) also gets
`"sight"` (line-of-sight range in tiles) plus the resolved `"battle_text"` / `"end_text"` /
`"after_text"` strings, pulled from the map's script trainer headers — see
[../engine/npcs.md](../engine/npcs.md).

All 223 maps + 24 tilesets are extracted (a `.blk` whose size ≠ `width*height` from the map
constants uses its actual height when it's a clean multiple of the width — e.g. the North-South
underground path; a `…Copy` map with no `.blk` reuses the base map's). `tileset` is the slug of a
`game/assets/tilesets/<slug>.json`. Consumed by the engine: warps →
[../engine/warps.md](../engine/warps.md); connections →
[../engine/connections.md](../engine/connections.md); object_events →
[../engine/npcs.md](../engine/npcs.md).
