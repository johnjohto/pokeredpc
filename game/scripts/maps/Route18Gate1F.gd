extends "res://scripts/MapScripts.gd"
## scripts/Route18Gate1F.asm — no pedestrians on CYCLING ROAD without the BICYCLE.

const COORDS := [Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6)]


func on_enter() -> void:
	# scripts/Route18Gate1F.asm: res BIT_ALWAYS_ON_BIKE, [wStatusFlags6]
	main.force_bike = false


func on_step(cell: Vector2i) -> bool:
	if cell in COORDS and not main.player_bag.has("BICYCLE"):
		bounce_back(cell)                             # turned back the way you came
		say("No pedestrians\nare allowed on\nCYCLING ROAD!")
		return true
	return false
