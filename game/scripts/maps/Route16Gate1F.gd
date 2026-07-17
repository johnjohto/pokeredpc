extends "res://scripts/MapScripts.gd"
## scripts/Route16Gate1F.asm — no pedestrians on CYCLING ROAD without the BICYCLE.

const COORDS := [Vector2i(4, 7), Vector2i(4, 8), Vector2i(4, 9), Vector2i(4, 10)]


func on_enter() -> void:
	# scripts/Route16Gate1F.asm: res BIT_ALWAYS_ON_BIKE, [wStatusFlags6]
	main.force_bike = false


func on_step(cell: Vector2i) -> bool:
	if cell in COORDS and not main.player_bag.has("BICYCLE"):
		bounce_back(cell)                             # turned back the way you came
		say("No pedestrians\nare allowed on\nCYCLING ROAD!")
		return true
	return false
