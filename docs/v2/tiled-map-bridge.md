# Native Tiled map bridge (Project format 2)

Project format 2 makes Tiled TMX/TSX the native map source. The Engine and Studio both open
it through `game/core/MapDocument.gd`; callers do not parse XML or resolve Tiled paths.
ADR-021 records why this seam and the conservative tracer subset exist.

## Files and coordinate model

```
project/
  maps/<MapLabel>.tmx
  tilesets/<tileset>.tsx
  assets/<atlas>.png
```

The TMX map is finite, orthogonal, and uses 16×16 tiles. One tile is one movement/collision
cell. Pixel coordinates therefore convert directly as `cell = pixel / 16`; objects must be
point objects aligned to that grid. Maps may have odd cell dimensions.

Gen-1's 32×32 blocks are optional authoring groups, not geometry. A tileset may attach a
`pokeredpc:block` string to a tile so Studio can offer a block brush without making projects
or other rulesets depend on the Game Boy representation.

## TMX contract

The tracer accepts:

- exactly one external `<tileset firstgid="…" source="…tsx"/>`;
- exactly one full-map tile layer named `Ground`, using CSV GIDs;
- no empty cells, flipped/rotated GIDs, embedded tilesets, or infinite chunks;
- referenced TSX/image paths contained by the Project directory.

Map properties owned by pokeredpc:

| Property | Type | Meaning |
|---|---|---|
| `pokeredpc:format` | int | Tiled bridge version. Current value: `1`. |
| `pokeredpc:border_tile` | int | Local TSX tile ID drawn outside the map/at an odd batch edge. |
| `pokeredpc:default_spawn` | string `x,y` | Initial movement cell when no warp/spawn override is named. |

The Project manifest's `format: 2` and the map's `pokeredpc:format: 1` version different
contracts. A build refuses a newer value at either boundary and names its supported value.

## TSX contract

The external tileset is one 16×16 atlas image. Local tile IDs use these properties:

| Property | Type | Meaning |
|---|---|---|
| `pokeredpc:walkable` | bool | Whether the player may stand on this cell. Absent is solid. |
| `pokeredpc:feet_tile` | int | Optional ruleset semantic tile ID; defaults to the local tile ID. |
| `pokeredpc:block` | string | Optional Studio block-brush grouping/position metadata. |
| `pokeredpc:grass` | bool | Optional grass semantic for Engine presentation. |
| `pokeredpc:counter` | bool | Optional counter semantic for interaction. |
| `pokeredpc:bottom_right_tile` | int | Optional Gen-1 semantic used by ledge-style checks. |

The atlas loads directly from the opened Project with `Image.load_from_file`; it never
silently falls back to similarly named extracted `res://assets` content.

## Gameplay objects

Gameplay objects are grid-aligned named Tiled points. Their stable `name` is the object ID;
their Tiled `class` (or legacy `type`) selects one of these records:

| Class | Required/recognized properties |
|---|---|
| `pokeredpc:warp` | `pokeredpc:dest_map` (`map:<label>`), `pokeredpc:dest_warp` (int) |
| `pokeredpc:npc` | `pokeredpc:sprite`, optional `pokeredpc:movement`, `pokeredpc:facing`, `pokeredpc:event` |
| `pokeredpc:sign` | optional `pokeredpc:text`, `pokeredpc:event` |
| `pokeredpc:trigger` | optional `pokeredpc:event` |

Map and event references are validated with the same stable ID registry as JSON content.
An unknown `pokeredpc:*` class refuses; a third-party class is preserved but ignored by the
runtime.

## Round trips and ownership

`MapDocument` retains original source bytes. A no-op save writes the TMX byte-for-byte,
including comments and unknown layers, objects, properties, ordering, and formatting.
Unknown Tiled content is outside pokeredpc's runtime model but inside its preservation
promise.

Phase 5.3 will add targeted edits. Those edits must change only pokeredpc-owned fields and
preserve unrelated XML rather than formatting the whole document. The external TSX has the
same preservation requirement when tile/collision tools begin writing it.

## Verification

- `--schematest` opens the format-2 fixture, checks normalization, path/refusal cases, typed
  objects, and exact no-op save.
- `--tmxtest` drives Main's native placement, collision, atlas quad renderer, and writes
  `game/tmxtest.png`.
- `--studiotest` mounts the real three-column Studio workspace, renders
  `game/studio_tmx.png`, and saves through its real document control.
- The two PNGs must be byte-identical; the fixture currently renders 64×48 pixels.
