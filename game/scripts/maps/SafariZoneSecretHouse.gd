extends "res://scripts/MapScripts.gd"
## scripts/SafariZoneSecretHouse.asm - the secret-house guru gives HM03 (SURF).


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_FISHING_GURU@3,3":
		face_player(npc)
		main.cutscene.safari_surf_guru()
		return true
	return false