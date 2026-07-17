extends "res://scripts/MapScripts.gd"
## scripts/RocketHideoutElevator.asm — the LIFT-KEY elevator. The panel at (1,1) needs the
## LIFT KEY and offers B1F/B2F/B4F (RocketHideoutElevatorFloors/WarpMaps; the asm warp
## numbers are 0-based, +1 here).

const FLOORS := [["B1F", "RocketHideoutB1F", 5], ["B2F", "RocketHideoutB2F", 5],
	["B4F", "RocketHideoutB4F", 3]]


func on_enter() -> void:
	elevator_enter()


func on_interact(front: Vector2i, _npc) -> bool:
	if front != Vector2i(1, 1):                      # the panel (TEXT_ROCKETHIDEOUTELEVATOR)
		return false
	if not main.player_bag.has("LIFT KEY"):
		say("It appears to\nneed a key.")
		return true
	elevator_panel(FLOORS)
	return true
