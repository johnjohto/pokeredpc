extends "res://scripts/MapScripts.gd"
## scripts/Route6Gate.asm — the thirsty guard blocks the way into Saffron until given a drink.

const COORDS := [Vector2i(3, 2), Vector2i(4, 2)]
const PUSH := Vector2i(0, 1)   # back down to Route 6


func on_step(cell: Vector2i) -> bool:
	if not has_event("GAVE_SAFFRON_GUARDS_DRINK") and cell in COORDS:
		thirsty_guard(cell, PUSH)
		return true
	return false
