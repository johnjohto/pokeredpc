extends "res://scripts/MapScripts.gd"
## scripts/CinnabarLabFossilRoom.asm - the fossil scientist revives DOME/HELIX/AMBER.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_SCIENTIST@5,2":
		face_player(npc)
		main.cutscene.revive_fossil()
		return true
	return false