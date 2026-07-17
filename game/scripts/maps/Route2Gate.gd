extends "res://scripts/MapScripts.gd"
## scripts/Route2Gate.asm - Oak''s aide: HM05 (FLASH) at 10 owned species.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_SCIENTIST@1,4":
		face_player(npc)
		main.cutscene.oaks_aide_flash()
		return true
	return false