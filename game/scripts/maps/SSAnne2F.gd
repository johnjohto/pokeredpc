extends "res://scripts/MapScripts.gd"
## scripts/SSAnne2F.asm — the rival intercepts the player on deck.


func on_step(cell: Vector2i) -> bool:
	# The deck ambush (coords 36/37,8).
	if (cell == Vector2i(36, 8) or cell == Vector2i(37, 8)) and not has_event("BEAT_SS_ANNE_RIVAL"):
		main.cutscene.ss_anne_rival()
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_BLUE@36,4":
		return false            # rival appears only for the deck battle cutscene
	return null
