# Engine: ledges & tall grass

Two overworld tile effects, both driven by extracted tileset data and implemented in
`Player.gd` with helpers in `Main.gd`.

## Ledges (one-way hops)

Source: `data/tilesets/ledge_tiles.asm` (`HandleLedges`, OVERWORLD tileset only). Extracted
into the **overworld** tileset JSON as `ledges: [{dir, stand, ledge}]`.

A hop triggers when, pressing a direction, **all** hold:
- the player is **facing** that direction,
- the tile the player **stands on** == `stand`,
- the tile **in front** == `ledge`.

Then the player jumps **2 cells** in that direction (`Player._ledge_jump`): a position tween
over `JUMP_TIME` plus an arc on the body sprite (up then down) and a ground **shadow**
(`Player._draw`, drawn behind the body so it stays at ground level while the body arcs).
Ledges are one-way (only down/left/right exist in the table — never up) and ignore the
normal passability of the ledge tile.

`Main.ledge_match(cell, dir, delta)` does the lookup (returns false off the overworld
tileset). Verified by `--ledgetest` (hop is exactly +2; arc + shadow captured mid-hop).

## Tall grass (leg overlap)

Source: the 5th `tileset` arg in `data/tilesets/tileset_headers.asm` = the tileset's grass
tile (Overworld `$52`, Forest `$20`, else none). Extracted into each tileset JSON as
`grass_tile` (-1 if none).

In pokered, a sprite standing on the grass tile gets `OAM_PRIO` on its **bottom two OAM
tiles** (`movement.asm` sets `GRASSPRIORITY`; `sprite_oam.asm` applies it to the tiles
flagged `BIT_SPRITE_UNDER_GRASS`), putting its lower half *behind BG colors 1-3* — the
actual map pixels at their fixed grid positions overdraw the legs, and BG color 0 (the
gaps) lets the sprite show through.

The port reproduces this exactly with `Main.grass_overlay`: a `z_index`-topmost node that,
for every grass-standing sprite (player, NPCs, and objects alike), **redraws the map tiles
under the sprite's lower 16×8 band** (`tile_gfx_at`) through `shaders/grass_overlay.gdshader`
(which discards the lightest shade). Because it redraws whatever BG is really there, the
effect follows the sprite pixel-for-pixel mid-step, exactly like the GB. The **standing
tile** is the one being *left* during a step (it only updates on arrival), so a sprite
walking into grass stays fully drawn until the step lands and then pops under — the
authentic Gen-1 look. Verified by `--grasstest` (at-rest legs-behind-blades +
`grass_midstep.png` fully-drawn mid-step).

## Not yet modelled

- Tile-pair collisions (`TilePairCollisionsLand`) — specific land/water edge pairs.
- Wild encounters when walking in grass (the grass tile also gates the encounter check).
- Grass rustle has no separate animation in RBY; the effect is purely the leg overlap.
