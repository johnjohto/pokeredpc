extends "res://scripts/MapScripts.gd"
## scripts/VictoryRoad1F.asm - the boulder-onto-switch door puzzle.

const SWITCHES := [{"sw": Vector2i(17, 13), "ev": "VR1_SWITCH", "blk": [4, 6, 0x1D]}]


func on_enter() -> void:
	switch_doors_enter(SWITCHES)


func on_boulder(cell: Vector2i, _npc) -> void:
	boulder_switch(cell, SWITCHES)