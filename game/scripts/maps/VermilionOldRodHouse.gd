extends "res://scripts/MapScripts.gd"
## scripts/VermilionOldRodHouse.asm - the Fishing Guru gives the OLD ROD.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_FISHING_GURU@2,4":
		face_player(npc)
		main.cutscene.old_rod_guru()
		return true
	return false