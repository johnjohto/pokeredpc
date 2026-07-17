extends "res://scripts/MapScripts.gd"
## scripts/SilphCo3F.asm — the floor's card-key doors (GateCallbackScript).

const DOORS := [[4, 4, 0x5F], [8, 4, 0x5F]]


func on_enter() -> void:
	place_silph_doors(DOORS)


func on_interact(front: Vector2i, _npc) -> bool:
	return silph_door_interact(front, DOORS, 0xE)
