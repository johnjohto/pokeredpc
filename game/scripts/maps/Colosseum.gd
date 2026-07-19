extends "res://scripts/MapScripts.gd"
## The Cable Club Colosseum room (gh #6 gives it the shared room behavior — the partner's
## avatar opposite, the doormat exit; the link battle itself is gh #7).

const TABLE := [Vector2i(4, 4), Vector2i(5, 4)]


func on_enter() -> void:
	main.club_room_enter()


func on_step(cell: Vector2i) -> bool:
	return main.club_room_step(cell)


func on_interact(front: Vector2i, npc) -> bool:
	if npc != null or front in TABLE:
		main.cutscene.colosseum_table()
		return true
	return false
