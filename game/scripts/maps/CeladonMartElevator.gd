extends "res://scripts/MapScripts.gd"
## scripts/CeladonMartElevator.asm — the department store elevator: no key, floors 1F-5F
## (CeladonMartElevatorFloors/WarpMaps; the asm warp numbers are 0-based, +1 here).

const FLOORS := [["1F", "CeladonMart1F", 6], ["2F", "CeladonMart2F", 3],
	["3F", "CeladonMart3F", 3], ["4F", "CeladonMart4F", 3], ["5F", "CeladonMart5F", 3]]


func on_enter() -> void:
	elevator_enter()


func on_interact(front: Vector2i, _npc) -> bool:
	if front != Vector2i(3, 0):                      # the panel (TEXT_CELADONMARTELEVATOR)
		return false
	elevator_panel(FLOORS)
	return true
