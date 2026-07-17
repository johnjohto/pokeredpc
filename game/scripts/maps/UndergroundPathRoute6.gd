extends "res://scripts/MapScripts.gd"
## scripts/UndergroundPathRoute6.asm sets `wLastMap = ROUTE_6` on every load, so the building's two
## `LAST_MAP` exit mats go back to Route 6 no matter which underground path you walked in from. Without it
## the port leaves `last_outside_map` at wherever you entered (Route 5, if you walked Route 5 → tunnel →
## here), and the exit loops you back to Route 5 (gh #114).


func on_enter() -> void:
	main.last_outside_map = "Route6"
