extends "res://scripts/MapScripts.gd"
## scripts/PokemonMansion1F.asm - the switch-door blocks + this floor''s switch.

const BLOCKS := [[12, 6, 0x0E, 0x2D], [8, 3, 0x2D, 0x0E], [10, 8, 0x2D, 0x0E], [13, 13, 0x2D, 0x0E]]
const SWITCHES := [Vector2i(2, 5)]


func on_enter() -> void:
	mansion_blocks(BLOCKS)


## The switch is a wall panel: you stand below it and press A facing UP. pokered keys it off the
## *faced* tile (data/events/hidden_events.asm, `hidden_event <x>, <y>, Mansion*Script_Switches,
## SPRITE_FACING_UP`) — every switch cell is solid, so testing the player's own cell could never fire
## (gh #83).
func on_interact(front: Vector2i, _npc) -> bool:
	if main.player.facing == 1 and front in SWITCHES:
		mansion_switch(BLOCKS)
		return true
	return false