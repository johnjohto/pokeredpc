extends "res://scripts/MapScripts.gd"
## scripts/FuchsiaGoodRodHouse.asm - the Fishing Guru''s older brother gives the GOOD ROD.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_FISHING_GURU@5,3":
		face_player(npc)
		main.cutscene.good_rod_guru()
		return true
	return false