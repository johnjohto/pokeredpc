extends "res://scripts/MapScripts.gd"
## scripts/PewterCity.asm — the two escort drags: the museum guy marches you to the museum,
## and the gym guide kid intercepts anyone leaving east before BROCK is beaten.

const _EAST_GATE := [Vector2i(35, 17), Vector2i(36, 17), Vector2i(37, 18), Vector2i(37, 19)]


func on_step(cell: Vector2i) -> bool:
	# Leaving east before beating BROCK — the gym guide kid intercepts and marches you to the
	# gym (PewterCityCheckPlayerLeavingEastScript -> the youngster's drag).
	if not has_event("BEAT_BROCK") and cell in _EAST_GATE:
		var kid = main._npc_by_key("SPRITE_YOUNGSTER@35,16")
		if kid and kid.shown:
			main.cutscene.pewter_gym_guy(kid)
			return true
	return false


func on_interact(_front: Vector2i, npc) -> bool:
	if npc == null:
		return false
	# The museum guy and the gym guide kid march the player across town.
	if npc.key == "SPRITE_SUPER_NERD@27,17":
		face_player(npc)
		main.cutscene.pewter_museum_guy(npc)
		return true
	if npc.key == "SPRITE_YOUNGSTER@35,16":
		face_player(npc)
		main.cutscene.pewter_gym_guy(npc)
		return true
	return false
