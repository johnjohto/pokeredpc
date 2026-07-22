# Native Tiled map bridge (Project format 2)

Project format 2 makes Tiled TMX/TSX the native map source. The Engine and Studio both open
it through `game/core/MapDocument.gd`; callers do not parse XML or resolve Tiled paths.
ADR-021 records why this seam and the conservative tracer subset exist.

## Files and coordinate model

```
project/
  data/world.json
  maps/<MapLabel>.tmx
  tilesets/<tileset>.tsx
  assets/<atlas>.png
```

The TMX map is finite, orthogonal, and uses 16×16 tiles. One tile is one movement/collision
cell. Pixel coordinates therefore convert directly as `cell = pixel / 16`; objects must be
point objects aligned to that grid. Maps may have odd cell dimensions.

Gen-1's 32×32 blocks are optional authoring groups, not geometry. Kanto's importer maps
each block to four native cells and attaches reversible `pokeredpc:block` metadata so
Studio can offer a block brush without making other projects or rulesets use Game Boy
geometry. ADR-023 records this cutover.

## TMX contract

The bridge accepts:

- exactly one external `<tileset firstgid="…" source="…tsx"/>`;
- exactly one full-map tile layer named `Ground`, using CSV GIDs;
- zero or one full-map tile layer named `Collision`, using CSV GIDs;
- no empty cells, flipped/rotated GIDs, embedded tilesets, or infinite chunks;
- referenced TSX/image paths contained by the Project directory.

`Ground` stores local visual cells. `Collision` is an optional per-instance override:
GID `0` is walkable and any valid GID from the external tileset is solid. When the layer is
absent, each Ground tile's TSX `pokeredpc:walkable` property supplies collision. Studio only
adds the hidden override layer when authored collision differs from those defaults.

Map properties owned by pokeredpc:

| Property | Type | Meaning |
|---|---|---|
| `pokeredpc:format` | int | Tiled bridge version. Current value: `1`. |
| `pokeredpc:border_tile` | int | Local TSX tile ID drawn outside the map/at an odd batch edge. |
| `pokeredpc:border_block` | int | Optional reversible 32×32 border group used by block-authored projects. |
| `pokeredpc:default_spawn` | string `x,y` | Initial movement cell when no warp/spawn override is named. |

The Project manifest's `format: 2` and the map's `pokeredpc:format: 1` version different
contracts. A build refuses a newer value at either boundary and names its supported value.

## TSX contract

The external tileset is one 16×16 atlas image. Local tile IDs use these properties:

| Property | Type | Meaning |
|---|---|---|
| `pokeredpc:walkable` | bool | Whether the player may stand on this cell. Absent is solid. |
| `pokeredpc:feet_tile` | int | Optional ruleset semantic tile ID; defaults to the local tile ID. |
| `pokeredpc:block` | string `id,quadrant` | Optional reversible block id and quadrant (`0` top-left through `3` bottom-right). |
| `pokeredpc:subtiles` | string `a,b,c,d` | Optional exact four 8×8 source ids, used by Kanto animation/parity. |
| `pokeredpc:grass` | bool | Optional grass semantic for Engine presentation. |
| `pokeredpc:counter` | bool | Optional counter semantic for interaction. |
| `pokeredpc:bottom_right_tile` | int | Optional Gen-1 semantic used by ledge-style checks. |

The atlas loads directly from the opened Project with `Image.load_from_file`; it never
silently falls back to similarly named extracted `res://assets` content.

Kanto's TSX also carries a tileset-level `pokeredpc:ledges` compact-JSON property. The
Engine consumes its semantic 8×8 ids through the same rules as format 1. Composite atlas
cells normally draw in one blit; flower and water cells split into their preserved four
subtiles only while animating.

## World graph

`data/world.json` owns seamless map placement. Its `maps` object is keyed by stable map id;
each value is an ordered list of `{direction, map, offset}` records. Direction is cardinal,
the destination is an `x-ref`-validated `map:<label>`, and offset remains in 32px block
units to preserve pokered's connection headers. `ProjectData` injects the selected map's
connections into the runtime view; a TMX document remains local geometry.

## Gameplay objects

Gameplay objects are grid-aligned named Tiled points. Their stable `name` is the object ID;
their Tiled `class` (or legacy `type`) selects one of these records:

| Class | Required/recognized properties |
|---|---|
| `pokeredpc:warp` | `pokeredpc:dest_map` (`map:<label>`) or explicit `pokeredpc:dest_const` ruleset sentinel; `pokeredpc:dest_warp` (int) |
| `pokeredpc:npc` | `pokeredpc:sprite`, optional `pokeredpc:movement`, `pokeredpc:facing`, `pokeredpc:event` |
| `pokeredpc:sign` | optional `pokeredpc:text`, `pokeredpc:event` |
| `pokeredpc:trigger` | optional `pokeredpc:event` |

Map and event references are validated with the same stable ID registry as JSON content.
An unknown `pokeredpc:*` class refuses; a third-party class is preserved but ignored by the
runtime.

Extractor-authored Kanto objects additionally carry `pokeredpc:legacy`, compact JSON of the
exact former runtime record. This preserves ordered macro arguments and trainer-dialogue
control characters while common fields remain visible as typed Tiled properties.

## Round trips and ownership

`MapDocument` retains original source bytes. A no-op save writes the TMX byte-for-byte,
including comments and unknown layers, objects, properties, ordering, and formatting.
Unknown Tiled content is outside pokeredpc's runtime model but inside its preservation
promise.

Studio's Phase-5.3 map tools edit through `MapDocument`, which patches only the CSV bodies
of `Ground` and an existing `Collision` layer. When an override layer is first needed, the
writer inserts that one owned layer and advances `nextlayerid`; it does not reserialize the
XML tree. The external TSX is read-only in this slice, so its bytes are never rewritten.

A project may paint arbitrary 16×16 cells even when its TSX carries optional Gen-1 block
metadata. A coherent 2×2 group exposes its block id and can be stamped with the block brush;
a mixed group is valid native geometry and simply has no reconstructed block id.

## Verification

- `--schematest` opens the format-2 fixture, checks normalization, path/refusal cases, typed
  objects, exact no-op save, targeted Ground/Collision writes, and preservation of unknown
  TMX plus exact TSX bytes.
- `--tmxtest` drives Main's native placement, collision, atlas quad renderer, and writes
  `game/tmxtest.png`.
- `--studiotest` mounts the real three-column Studio workspace, renders
  `game/studio_tmx.png`, then creates, paints, fills, block-stamps, collides, undo/redoes,
  saves, reopens, and child-play-tests a scratch map through real controls.
- The two PNGs must be byte-identical; the fixture currently renders 64×48 pixels.
- `--projparitytest` deep-compares all 223 native maps with the legacy semantic oracle and
  independently compares all 24 TSX block mappings and composite pixels.
- The Kanto gate also requires two byte-identical extractions, zero validation errors,
  unchanged battle stream hashes, and the seeded NEW GAME → HALL OF FAME playthrough.
