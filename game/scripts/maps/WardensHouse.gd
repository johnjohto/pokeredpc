extends "res://scripts/MapScripts.gd"
## scripts/WardensHouse.asm - the Warden trades the GOLD TEETH for HM04 (STRENGTH).


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_WARDEN@2,3":
		face_player(npc)
		main.cutscene.warden_strength()
		return true
	return false