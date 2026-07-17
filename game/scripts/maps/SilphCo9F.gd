extends "res://scripts/MapScripts.gd"
## scripts/SilphCo9F.asm — the floor's card-key doors (GateCallbackScript).

const DOORS := [[1, 4, 0x5F], [9, 2, 0x54], [9, 5, 0x54], [5, 6, 0x5F]]


func on_enter() -> void:
	place_silph_doors(DOORS)


func on_interact(front: Vector2i, npc) -> bool:
	if npc != null and npc.file == "nurse":
		main.cutscene.silph_co9f_nurse()
		return true
	return silph_door_interact(front, DOORS, 0xE)
