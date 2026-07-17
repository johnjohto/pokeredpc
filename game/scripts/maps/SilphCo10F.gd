extends "res://scripts/MapScripts.gd"
## scripts/SilphCo10F.asm — the floor's card-key door (GateCallbackScript).

const DOORS := [[5, 4, 0x54]]


func on_enter() -> void:
	place_silph_doors(DOORS)


func on_interact(front: Vector2i, _npc) -> bool:
	return silph_door_interact(front, DOORS, 0xE)
