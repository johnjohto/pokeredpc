extends "res://scripts/MapScripts.gd"
## scripts/PokemonMansion3F.asm - the switch-door blocks, this floor''s switch, and the balcony holes.

const BLOCKS := [[7, 2, 0x0E, 0x5F], [7, 5, 0x5F, 0x0E]]
const SWITCHES := [Vector2i(10, 5)]

## `PokemonMansion3FDefaultScript`'s `.holeCoords`, in order — the two balcony drops. The matched index
## picks the floor: `cp $3` sends coord 3 to 2F, the others to 1F. Landing cells from `DungeonWarpData`
## (data/maps/special_warps.asm). The western drop onto **1F (16,14)** is the *only* way into 1F's
## southern half, and so the only route to the SECRET KEY on B1F (gh #85).
const HOLES := [
	[Vector2i(16, 14), "PokemonMansion1F", Vector2i(16, 14)],
	[Vector2i(17, 14), "PokemonMansion1F", Vector2i(16, 14)],
	[Vector2i(19, 14), "PokemonMansion2F", Vector2i(18, 14)],
]


func on_enter() -> void:
	mansion_blocks(BLOCKS)


func on_step(cell: Vector2i) -> bool:
	return dungeon_hole(cell, HOLES)


## The switch is a wall panel: you stand below it and press A facing UP. pokered keys it off the
## *faced* tile (data/events/hidden_events.asm, `hidden_event <x>, <y>, Mansion*Script_Switches,
## SPRITE_FACING_UP`) — every switch cell is solid, so testing the player's own cell could never fire
## (gh #83).
func on_interact(front: Vector2i, _npc) -> bool:
	if main.player.facing == 1 and front in SWITCHES:
		mansion_switch(BLOCKS)
		return true
	return false