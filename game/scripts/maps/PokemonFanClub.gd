extends "res://scripts/MapScripts.gd"
## scripts/PokemonFanClub.asm - the chairman''s rapture ends with the BIKE VOUCHER.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_GENTLEMAN@3,1":
		face_player(npc)
		main.cutscene.fan_club_chairman()
		return true
	return false