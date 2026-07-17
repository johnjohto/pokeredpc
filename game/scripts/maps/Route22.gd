extends "res://scripts/MapScripts.gd"
## scripts/Route22.asm — the rival walks in for a battle at the gate approach: battle 1 after
## the Pokédex (until Brock), battle 2 after the 8th badge.


func on_step(cell: Vector2i) -> bool:
	if cell in [Vector2i(29, 4), Vector2i(29, 5)]:
		if has_event("GOT_POKEDEX") and not has_event("BEAT_BROCK") and not has_event("BEAT_ROUTE22_RIVAL_1"):
			main.cutscene.route22_rival(1)
			return true
		elif main.badges.size() >= 8 and not has_event("BEAT_ROUTE22_RIVAL_2"):
			main.cutscene.route22_rival(2)
			return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_BLUE@25,5":
		return false            # the rival walks in only for his battle
	return null
