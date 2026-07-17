extends "res://scripts/MapScripts.gd"
## scripts/Daycare.asm - the Day-Care man boards one party mon.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_GENTLEMAN@2,3":
		face_player(npc)
		main.cutscene.daycare_man()
		return true
	return false