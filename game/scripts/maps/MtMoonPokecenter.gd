extends "res://scripts/MapScripts.gd"
## scripts/MtMoonPokecenter.asm - the MAGIKARP salesman (L5 for 500).


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_MIDDLE_AGED_MAN@10,6":
		face_player(npc)
		main.cutscene.magikarp_salesman()
		return true
	return false