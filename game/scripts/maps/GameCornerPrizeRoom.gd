extends "res://scripts/MapScripts.gd"
## scripts/GameCornerPrizeRoom.asm — the three prize counters (bg_events): coins for the RED
## prizes, two Pokémon counters and a TM counter.


func on_interact(front: Vector2i, _npc) -> bool:
	if front in [Vector2i(2, 2), Vector2i(4, 2), Vector2i(6, 2)]:
		main.cutscene.prize_vendor(front.x / 2 - 1)
		return true
	return false
