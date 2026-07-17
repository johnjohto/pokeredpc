extends "res://scripts/MapScripts.gd"
## scripts/DiglettsCaveRoute2.asm sets `wLastMap = ROUTE2` on load, so this connector's `LAST_MAP`
## exits go back to Route2 regardless of which side you entered from — without it the exit loops
## you back to wherever you came from (gh #114).


func on_enter() -> void:
	main.last_outside_map = "Route2"
