extends "res://scripts/MapScripts.gd"
## scripts/PokemonMansionB1F.asm - the switch-door blocks + this floor''s two switches; the
## SECRET KEY item ball lives here.

const BLOCKS := [[13, 8, 0x0E, 0x2D], [6, 11, 0x0E, 0x5F], [4, 3, 0x5F, 0x0E], [8, 8, 0x54, 0x0E]]
const SWITCHES := [Vector2i(20, 3), Vector2i(18, 25)]


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