extends "res://scripts/MapScripts.gd"
## scripts/CeladonMartRoof.asm - the rooftop vending machines (bg_events) sell the drinks the
## Saffron guards want. (The roof girl''s drink-for-TM trade is a text-id branch in Main.)


func on_interact(front: Vector2i, _npc) -> bool:
	if front in [Vector2i(10, 1), Vector2i(11, 1), Vector2i(12, 2)]:
		main._vending_enter()
		return true
	return false