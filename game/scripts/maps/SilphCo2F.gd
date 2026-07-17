extends "res://scripts/MapScripts.gd"
## scripts/SilphCo2F.asm — the floor's card-key doors (GateCallbackScript).

const DOORS := [[2, 2, 0x54], [2, 5, 0x54]]


func on_enter() -> void:
	place_silph_doors(DOORS)


func on_interact(front: Vector2i, _npc) -> bool:
	return silph_door_interact(front, DOORS, 0xE)
