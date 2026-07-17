extends "res://scripts/MapScripts.gd"
## scripts/VictoryRoad2F.asm - the boulder-onto-switch door puzzle (two switches).
##
## The 1F ladder drops you into a sealed 71-cell west pocket; switch1 (1,16) is its only door, and the
## only boulder in the pocket is BOULDER1 at (4,14). Switch2 (9,16) opens a shortcut in the main region,
## and the boulder for it is the one that falls through **3F's hole** — BOULDER3 at (23,16) starts hidden
## (`toggleable_objects.asm` + `Route23SetVictoryRoadBoulders`) and only appears once it has fallen.
## Loading this floor also clears 1F's switch (`VictoryRoad2FResetBoulderEventScript`).

const SWITCHES := [
	{"sw": Vector2i(1, 16), "ev": "VR2_SWITCH1", "blk": [3, 4, 0x15]},
	{"sw": Vector2i(9, 16), "ev": "VR2_SWITCH2", "blk": [11, 7, 0x1D]}]


func on_enter() -> void:
	clear_event("VR1_SWITCH")                     # VictoryRoad2FResetBoulderEventScript
	switch_doors_enter(SWITCHES)


func on_boulder(cell: Vector2i, _npc) -> void:
	boulder_switch(cell, SWITCHES)


func object_shown(k: String) -> Variant:
	if k == "SPRITE_BOULDER@23,16":               # TOGGLE_VICTORY_ROAD_2F_BOULDER
		return has_event("VR3_SWITCH2")           # ...it is the boulder that fell through 3F's hole
	return null
