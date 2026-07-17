extends "res://scripts/MapScripts.gd"
## scripts/FightingDojo.asm - the Hitmonlee/Hitmonchan prize: pick one, the other vanishes.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc == null:
		return false
	if npc.key == "SPRITE_POKE_BALL@4,1":
		face_player(npc)
		main.cutscene.hitmon_gift("hitmonlee", npc)
		return true
	if npc.key == "SPRITE_POKE_BALL@5,1":
		face_player(npc)
		main.cutscene.hitmon_gift("hitmonchan", npc)
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_POKE_BALL@4,1" or k == "SPRITE_POKE_BALL@5,1":
		return not (has_event("GOT_HITMONLEE") or has_event("GOT_HITMONCHAN"))
	return null