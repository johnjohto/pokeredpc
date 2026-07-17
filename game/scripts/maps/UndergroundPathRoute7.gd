extends "res://scripts/MapScripts.gd"
## scripts/UndergroundPathRoute7.asm sets `wLastMap = ROUTE7` on load, so this connector's `LAST_MAP`
## exits go back to Route7 regardless of which side you entered from — without it the exit loops
## you back to wherever you came from (gh #114).


func on_enter() -> void:
	main.last_outside_map = "Route7"
