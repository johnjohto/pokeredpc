extends "res://scripts/MapScripts.gd"
## scripts/SilphCoElevator.asm — the Silph Co elevator: no key, floors 1F-11F
## (SilphCoElevatorFloors/WarpMaps; the asm warp numbers are 0-based, +1 here). The static
## map data ships its door warps pointing at UNUSED_MAP_ED — pokered relies on the runtime
## retarget, so elevator_enter is what makes the doors work at all.

const FLOORS := [["1F", "SilphCo1F", 4], ["2F", "SilphCo2F", 3], ["3F", "SilphCo3F", 3],
	["4F", "SilphCo4F", 3], ["5F", "SilphCo5F", 3], ["6F", "SilphCo6F", 3],
	["7F", "SilphCo7F", 3], ["8F", "SilphCo8F", 3], ["9F", "SilphCo9F", 3],
	["10F", "SilphCo10F", 3], ["11F", "SilphCo11F", 2]]


func on_enter() -> void:
	elevator_enter()


func on_interact(front: Vector2i, _npc) -> bool:
	if front != Vector2i(3, 0):                      # the panel (TEXT_SILPHCOELEVATOR_ELEVATOR)
		return false
	elevator_panel(FLOORS)
	return true
