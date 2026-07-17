extends "res://scripts/MapScripts.gd"
## scripts/CeladonDiner.asm - the gambler hands over the COIN CASE (he lost it at the slots).


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_GYM_GUIDE@0,1":
		face_player(npc)
		main.cutscene.coin_case_giver()
		return true
	return false