extends "res://scripts/MapScripts.gd"
## scripts/SSAnneCaptainsRoom.asm — rub the seasick captain's back -> HM01 (CUT).


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_CAPTAIN@4,2":
		face_player(npc)
		main.cutscene.ss_anne_captain()
		return true
	return false
