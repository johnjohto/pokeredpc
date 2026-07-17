extends "res://scripts/MapScripts.gd"
## scripts/CinnabarIsland.asm - leaving the lab finishes the fossil revival, and the Gym door
## stays locked without the SECRET KEY.

const GYM_DOOR_STEP := Vector2i(18, 4)          # the street tile below the Gym door warp (18,3)


func on_enter() -> void:
	clear_event("LAB_STILL_REVIVING_FOSSIL")   # leaving the lab finishes the revival


## CinnabarIslandDefaultScript: without the SECRET KEY, standing on the tile below the Gym door bounces
## you straight back — a MovePlayerDownScript (face up, "The door is locked...", one simulated PAD_DOWN) —
## so you never step onto the door warp itself (gh #172; the old code intercepted the warp AFTER you had
## already walked onto the door). With the key this is a no-op and the door warp works normally.
func on_step(cell: Vector2i) -> bool:
	if cell == GYM_DOOR_STEP and not main.player_bag.has("SECRET KEY"):
		step_back_down(cell)
		say("The door is\nlocked...")
		return true
	return false
