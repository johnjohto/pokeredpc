extends "res://scripts/MapScripts.gd"
## scripts/CeladonMansionRoofHouse.asm - the Eevee gift ball.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_POKE_BALL@4,3":
		face_player(npc)
		main.cutscene.gift_mon_ball("eevee", 25, "GOT_EEVEE", npc)
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_POKE_BALL@4,3":
		return not has_event("GOT_EEVEE")             # the Eevee gift ball
	return null