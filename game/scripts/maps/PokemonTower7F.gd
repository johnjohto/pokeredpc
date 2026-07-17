extends "res://scripts/MapScripts.gd"
## scripts/PokemonTower7F.asm — rescuing Mr. Fuji warps you to his house.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_MR_FUJI@10,3" and not has_event("RESCUED_MR_FUJI"):
		face_player(npc)
		main.cutscene.mr_fuji_tower()
		return true
	return false
