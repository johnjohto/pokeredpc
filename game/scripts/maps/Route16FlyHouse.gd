extends "res://scripts/MapScripts.gd"
## scripts/Route16FlyHouse.asm - the girl gives HM02 (FLY).


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_BRUNETTE_GIRL@2,3":
		face_player(npc)
		main.cutscene.fly_house_girl()
		return true
	return false