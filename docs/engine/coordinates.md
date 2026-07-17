# Engine: coordinate units

Four units are in play. Keep them straight — mixing them is a common bug source.

| Unit | Size | Used by |
|---|---|---|
| **pixel** | 1 px | rendering, sprite/camera positions |
| **tile** | 8 px | tileset/blockset graphics, screen tilemap |
| **cell** | 16 px | player movement grid, collision, warp/object coords |
| **block** | 32 px | `.blk` map data (4×4 tiles / 2×2 cells) |

## Conversions

```
cell  = block * 2          # each block is 2×2 cells
px    = cell  * 16
px    = block * 32 = tile * 8
grid  size = (width_blocks * 2)  ×  (height_blocks * 2)   cells
```

## Important: warp/object coordinates are in **cells**

`warp_event x, y` and `object_event x, y` from `data/maps/objects/*.asm` are in **16px cell
units**, the same grid as collision and player movement. Pallet Town (10×9 blocks) =
**20×18 cells**, and its warp/object coords fall in `0..19 × 0..17`. So they index our
collision grid directly — no conversion needed.

## Player position

`Player.position` is the **pixel** position of the top-left of the 16×16 sprite, i.e.
`cell * 16`. Movement tweens between `cell*16` positions over `STEP_TIME`.
