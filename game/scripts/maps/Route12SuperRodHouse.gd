extends "res://scripts/MapScripts.gd"
## scripts/Route12SuperRodHouse.asm - the Route 12 brother gives the SUPER ROD.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_FISHING_GURU@2,4":
		face_player(npc)
		main.cutscene.super_rod_guru()
		return true
	return false