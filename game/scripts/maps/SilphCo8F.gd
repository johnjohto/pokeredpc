extends "res://scripts/MapScripts.gd"
## scripts/SilphCo8F.asm — the floor's card-key door (GateCallbackScript).

const DOORS := [[3, 4, 0x5F]]


func on_enter() -> void:
	place_silph_doors(DOORS)


func on_interact(front: Vector2i, _npc) -> bool:
	return silph_door_interact(front, DOORS, 0xE)
