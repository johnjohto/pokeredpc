extends "res://scripts/MapScripts.gd"
## scripts/Route7Gate.asm — the thirsty guard blocks the way into Saffron until given a drink.

const COORDS := [Vector2i(3, 3), Vector2i(3, 4)]
const PUSH := Vector2i(-1, 0)   # back west to Route 7


func on_step(cell: Vector2i) -> bool:
	if not has_event("GAVE_SAFFRON_GUARDS_DRINK") and cell in COORDS:
		thirsty_guard(cell, PUSH)
		return true
	return false
