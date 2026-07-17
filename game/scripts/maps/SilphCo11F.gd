extends "res://scripts/MapScripts.gd"
## scripts/SilphCo11F.asm — Giovanni #2, the president's MASTER BALL, and the floor's card-key
## door (GateCallbackScript; this floor's open block is 0x3, not 0xE).

const DOORS := [[3, 6, 0x20]]


func on_enter() -> void:
	place_silph_doors(DOORS)


func on_interact(front: Vector2i, npc) -> bool:
	if silph_door_interact(front, DOORS, 0x3):
		return true
	if npc == null:
		return false
	if npc.key == "SPRITE_GIOVANNI@6,9" and not has_event("BEAT_SILPH_CO_GIOVANNI"):
		face_player(npc)
		main.cutscene.giovanni_silph()
		return true
	if npc.key == "SPRITE_SILPH_PRESIDENT@7,5" and has_event("BEAT_SILPH_CO_GIOVANNI"):
		face_player(npc)
		main.cutscene.silph_president()
		return true
	return false


func object_shown(k: String) -> Variant:
	# TOGGLE_SILPH_CO_11F_1/2/3: Giovanni AND this floor's two rockets all leave with him —
	# SilphCo11FTeamRocketLeavesScript hides them under the post-battle fade (gh #158).
	if k in ["SPRITE_GIOVANNI@6,9", "SPRITE_ROCKET@3,16", "SPRITE_ROCKET@15,9"]:
		return not has_event("BEAT_SILPH_CO_GIOVANNI")
	return null
