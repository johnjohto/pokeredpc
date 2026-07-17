# Engine: rendering

The overworld is drawn with a **custom `_draw()`** (Godot `Node2D`), not a TileMap node.
This keeps full control and lets us author scenes as text without the editor GUI.

## Pipeline (`Main.gd`)

1. Load `assets/tilesets/<ts>.json` (cols, blocks, walkable) and `assets/maps/<map>.json`.
2. Load the tileset PNG as a `Texture2D`.
3. For each block in the map's `blocks` grid:
   - look up its 16 tile ids in the blockset,
   - for each of the 16 tiles, `draw_texture_rect_region()` the 8×8 source rect to its
     destination at `block_origin + tile_offset`.

```
src  = Rect2((tid % cols)*8, (tid / cols)*8, 8, 8)
dst  = Rect2(bx*32 + tx*8, by*32 + ty*8, 8, 8)
```

## Pixel crispness

- `project.godot`: `rendering/textures/canvas_textures/default_texture_filter=0` (Nearest).
- `Main.gd` sets `texture_filter = TEXTURE_FILTER_NEAREST` on the node as well.
- Window: base viewport **160×144** (GB screen), `window/stretch/mode="viewport"`, aspect
  `keep`, window override 480×432 (3×).

## Camera

`Camera2D` is a child of the player, offset by `(8,8)` so it centers on the 16×16 sprite's
middle. Zoom = 1 (the viewport stretch does the upscaling). Shows 10×9 cells.

## Future

- Static maps can stay in `_draw`; once maps get large or animated (water/flowers), consider
  drawing only on-screen blocks or switching to `TileMapLayer`.
- Y-sorting NPCs/player vs. tall tiles will matter for M8.
