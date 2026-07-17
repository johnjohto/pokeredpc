extends "res://scripts/MapScripts.gd"
## scripts/SilphCo7F.asm — the corridor rival ambush, the grateful worker's Lapras, and the
## floor's card-key doors (GateCallbackScript).

const DOORS := [[5, 3, 0x54], [10, 2, 0x54], [10, 6, 0x54]]


func on_enter() -> void:
	place_silph_doors(DOORS)


func on_step(cell: Vector2i) -> bool:
	# The rival ambushes you in the corridor (SilphCo7FDefaultScript coords).
	if (cell == Vector2i(3, 2) or cell == Vector2i(3, 3)) and not has_event("BEAT_SILPH_CO_RIVAL"):
		main.cutscene.silph_rival()
		return true
	return false


func on_interact(front: Vector2i, npc) -> bool:
	if silph_door_interact(front, DOORS, 0xE):
		return true
	if npc == null:
		return false
	if npc.key == "SPRITE_BLUE@3,7" and not has_event("BEAT_SILPH_CO_RIVAL"):
		face_player(npc)
		main.cutscene.silph_rival()
		return true
	if npc.key == "SPRITE_SILPH_WORKER_M@1,5":
		face_player(npc)
		main.cutscene.silph_lapras()
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_BLUE@3,7":
		return not has_event("BEAT_SILPH_CO_RIVAL")     # the rival leaves after the fight
	return null
